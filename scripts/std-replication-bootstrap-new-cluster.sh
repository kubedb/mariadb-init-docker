#!/usr/bin/env bash
env | sort | grep "POD\|HOST\|NAME"
args=$@
NAMESPACE="$POD_NAMESPACE"
USER="$MYSQL_ROOT_USERNAME"
PASSWORD="$MYSQL_ROOT_PASSWORD"
function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

function retry {
    local retries="$1"
    shift

    local count=0
    local wait=1
    until "$@"; do
        exit="$?"
        if [ $count -lt $retries ]; then
            log "INFO" "Attempt $count/$retries. Command exited with exit_code: $exit. Retrying after $wait seconds..."
            sleep $wait
        else
            log "INFO" "Command failed in all $retries attempts with exit_code: $exit. Stopping trying any further...."
            return $exit
        fi
        count=$(($count + 1))
    done
    return 0
}

# wait for the peer-list file created by coordinator
while [ ! -f "/scripts/peer-list" ]; do
    log "WARNING" "peer-list is not created yet"
    sleep 1
done
hosts=$(cat "/scripts/peer-list")
IFS=', ' read -r -a peers <<<"$hosts"
echo "${peers[@]}"
log "INFO" "hosts are ${peers[@]}"

report_host="$HOSTNAME.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc"
echo "report_host = $report_host "
localhost="127.0.0.1"

# wait for mysql daemon be running (alive)
function wait_for_mysqld_running() {
    local mysql="$mysql_header --host=$localhost"
    for i in {900..0}; do
        out=$(${mysql} -N -e "select 1;" 2>/dev/null)
        log "INFO" "Attempt $i: Pinging '$report_host' has returned: '$out'...................................."
        if [[ "$out" == "1" ]]; then
            break
        fi
        echo -n .
        sleep 1
    done

    if [[ "$i" == "0" ]]; then
        echo ""
        log "ERROR" "Server ${report_host} failed to start in 900 seconds............."
        exit 1
    fi
    log "INFO" "mysql daemon is ready to use......."
}

function create_replication_user() {
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether replication user exist or not......"
    local mysql="$mysql_header --host=$localhost"
    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        joining_for_first_time=1
        log "INFO" "Replication user not found. Creating new replication user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'repl'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
    else
        log "INFO" "Replication user exists. Skipping creating new one......."
    fi
}

function create_maxscale_user() {
    log "INFO" "Checking whether maxscale user exist or not......"
    local mysql="$mysql_header --host=$localhost"
    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Maxscale user not found. Creating new maxscale user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'maxscale'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.user TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.db TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.tables_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.columns_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.procs_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.proxies_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.roles_mapping TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SHOW DATABASES ON *.* TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
    else
        log "INFO" "Maxscale user exists. Skipping creating new one......."
    fi
}

function create_monitor_user() {
    log "INFO" "Checking whether monitor user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Monitor user not found. Creating new monitor user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'monitor_user'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "GRANT REPLICATION CLIENT on *.* to 'monitor_user'@'%';"
        retry 120 ${mysql} -N -e "GRANT SUPER, RELOAD on *.* to 'monitor_user'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
    else
        log "INFO" "Monitor user exists. Skipping creating new one......."
    fi
    touch /scripts/ready.txt
}
function bootstrap_cluster() {

    echo "this is master node"
    # ensure replication user
    create_replication_user

    # ensure maxscale user
    create_maxscale_user

    # ensure monitor user
    create_monitor_user
}

function join_into_cluster() {
    # member try to join into the existing group as a fresh instance
    log "INFO" "The replica, ${report_host} is joining into the existing group..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Resetting binlog & gtid to initial state as $report_host is joining first time.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    retry 20 ${mysql} -N -e "set global gtid_slave_pos='';"
    retry 20 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master',MASTER_USER='repl',MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD',MASTER_USE_GTID = current_pos;"
    retry 20 ${mysql} -N -e "START SLAVE;"

    echo "end join in cluster"
}

function join_by_gtid() {
    # member try to join into the existing group as old instance
    log "INFO" "The replica, ${report_host} is joining into the existing group by master replica's gtid..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Resetting binlog & gtid to initial state as $report_host is joining for first time.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    retry 20 ${mysql} -N -e "SET GLOBAL gtid_slave_pos = '$gtid';"
    retry 10 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master',MASTER_USER='repl',MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD',MASTER_USE_GTID = slave_pos;"
    retry 10 ${mysql} -N -e "START SLAVE;"
    echo "end join with gtid in cluster"
}


export pid
function start_mysqld_in_background() {
    log "INFO" "Starting MySQL server with docker-entrypoint.sh mysqld $args..."

    if [[ $MARIADB_VERSION == "1:11"* ]]; then
        docker-entrypoint.sh mariadbd $args &
    else
        docker-entrypoint.sh mysqld $args &
    fi

    pid=$!
    log "INFO" "The process ID of mysqld is '$pid'"
}
start_mysqld_in_background

export mysql_header="mariadb -u ${USER} --port=3306"
export MYSQL_PWD=${PASSWORD}
export member_hosts=($(echo -n ${peers[*]} | tr -d '[]'))
export joining_for_first_time=0

# wait for mysqld to be ready
wait_for_mysqld_running

while true; do
    kill -0 $pid
    exit="$?"
    if [[ "$exit" == "0" ]]; then
        echo "mysqld process is running"
    else
        echo "need start mysqld and wait_for_mysqld_running"
        start_mysqld_in_background
        wait_for_mysqld_running
    fi

    # wait for the script copied by coordinator
    while [ ! -f "/scripts/signal.txt" ]; do
        log "WARNING" "signal is not present yet!"
        sleep 1
    done
    desired_func=$(cat /scripts/signal.txt)
    rm -rf /scripts/signal.txt
    log "INFO" "going to execute $desired_func"
    if [[ $desired_func == "create_cluster" ]]; then
        bootstrap_cluster
    fi

    if [[ $desired_func == "join_in_cluster" ]]; then
        # wait for the script copied by coordinator
        while [ ! -f "/scripts/master.txt" ]; do
            log "WARNING" "master detector file isn't present yet!"
            sleep 1
        done
        master=$(cat /scripts/master.txt)
        echo "master is $master"
        rm -rf /scripts/master.txt
        join_into_cluster
    fi

    if [[ $desired_func == "join_by_gtid" ]]; then
        # wait for the script copied by coordinator
        while [ ! -f "/scripts/master.txt" ]; do
            log "WARNING" "master detector file isn't present yet!"
            sleep 1
        done
        master=$(cat /scripts/master.txt)

        while [ ! -f "/scripts/gtid.txt" ]; do
            log "WARNING" "gtid detector file isn't present yet!"
            sleep 1
        done
        gtid=$(cat /scripts/gtid.txt)

        echo "master replica's current gtid position is $gtid"
        rm -rf /scripts/gtid.txt
        join_by_gtid
    fi
    log "INFO" "waiting for mysql process id  = $pid"
    wait $pid
done














