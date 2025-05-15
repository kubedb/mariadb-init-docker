#!/usr/bin/env bash
env | sort | grep "POD\|HOST\|NAME\|SSL"

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

report_host="$HOSTNAME.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc"
echo "report_host = $report_host"

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

joining_for_first_time=1
function create_replication_user() {
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether replication user exist or not......"
    local mysql="$mysql_header --host=$localhost"
    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        joining_for_first_time=0
        log "INFO" "Replication user not found. Creating new replication user........"
        local ssl_require=""
        [[ "${REQUIRE_SSL:-}" == "TRUE" ]] && ssl_require="REQUIRE SSL"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'repl'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' $ssl_require;"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Replication user exists. Skipping creating new one......."
    fi
    local ssl_require=""
    [[ "${REQUIRE_SSL:-}" == "TRUE" ]] && ssl_require="REQUIRE SSL"
    retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;ALTER USER 'repl'@'%' $ssl_require;"
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
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'maxscale'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.user TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.db TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.tables_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.columns_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.procs_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.proxies_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.roles_mapping TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SHOW DATABASES ON *.* TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Maxscale user exists. Skipping creating new one......."
    fi
    local ssl_require=""
    [[ "${REQUIRE_SSL:-}" == "TRUE" ]] && ssl_require="REQUIRE SSL"
    retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;ALTER USER 'maxscale'@'%' $ssl_require;"
}

#//TODO:
#function create_maxscale_confsync_user() {
#    log "INFO" "Checking whether maxscale user exist or not......"
#    local mysql="$mysql_header --host=$localhost"
#    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
#    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale_confsync';" | awk '{print$1}'
#    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale_confsync';" | awk '{print$1}')
#    # if the user doesn't exist, crete new one.
#    if [[ "$out" -eq "0" ]]; then
#        log "INFO" "maxscale_confsync user not found. Creating new maxscale_confsync user........"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'maxscale_confsync'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' REQUIRE SSL;;"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT, INSERT, UPDATE, CREATE ON mysql.maxscale_config TO maxscale_confsync@'%';"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
#    else
#        log "INFO" "maxscale_confsync user exists. Skipping creating new one......."
#    fi
#}

function create_monitor_user() {
    log "INFO" "Checking whether monitor user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Monitor user not found. Creating new monitor user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'monitor_user'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        #mariadb 10.6+ change SUPER-> READ_ONLY ADMIN, REPLICATION CLIENT> SLAVE MONITOR
        if [[ "$(echo -e "1:10.7\n$MARIADB_VERSION" | sort -V | tail -n1)" == "$MARIADB_VERSION" ]]; then
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT READ_ONLY ADMIN, RELOAD on *.* to 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SLAVE MONITOR ON *.* TO 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT BINLOG ADMIN, REPLICATION MASTER ADMIN, REPLICATION SLAVE ADMIN ON *.* TO 'monitor_user'@'%';"
        else
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SUPER, RELOAD on *.* to 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT REPLICATION CLIENT on *.* to 'monitor_user'@'%';"
        fi

        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Monitor user exists. Skipping creating new one......."
    fi
    local ssl_require=""
    [[ "${REQUIRE_SSL:-}" == "TRUE" ]] && ssl_require="REQUIRE SSL"
    retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;ALTER USER 'monitor_user'@'%' $ssl_require;"
}
function bootstrap_cluster() {
    echo "this is master node"
    local mysql="$mysql_header --host=$localhost"
    retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
}

function join_to_master_by_current_pos() {
    # member try to join into the existing group as old instance
    log "INFO" "The replica, ${report_host} is joining to master node ${master}..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Joining to master with gtid current_pos.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    local ssl_options=""
    if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
        ssl_options=", MASTER_SSL=1, MASTER_SSL_CA='/etc/mysql/certs/server/ca.crt'"
        log "INFO" "Configuring replication with TLS enabled"
    else
        log "INFO" "Configuring replication without TLS"
    fi
    retry 20 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master', MASTER_USER='repl', MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD' $ssl_options, MASTER_USE_GTID=current_pos;"
    retry 20 ${mysql} -N -e "START SLAVE;"
    joining_for_first_time=0
    echo "end join to master node by gtid current_pos"
}

function join_to_master_by_slave_pos() {
    # member try to join into the existing group as old instance
    log "INFO" "The replica, ${report_host} is joining to master node ${master} by slave_pos..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Resetting binlog,gtid and set gtid_slave_pos.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    if [ $joining_for_first_time -eq 1 ]; then
      retry 20 ${mysql} -N -e "SET GLOBAL gtid_slave_pos = '$gtid';"
    fi
    if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
        ssl_options=", MASTER_SSL=1, MASTER_SSL_CA='/etc/mysql/certs/server/ca.crt'"
        log "INFO" "Configuring replication with TLS enabled"
    else
        log "INFO" "Configuring replication without TLS"
    fi
    retry 20 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master', MASTER_USER='repl', MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD' $ssl_options, MASTER_USE_GTID=slave_pos;"
    retry 20 ${mysql} -N -e "START SLAVE;"
    joining_for_first_time=0
    echo "end join to master node by gtid slave_pos"
}


export pid
function start_mysqld_in_background() {
    log "INFO" "Starting MySQL server with docker-entrypoint.sh mysqld $args..."
    process=""
    if [[ $MARIADB_VERSION == "1:11"* ]]; then
        docker-entrypoint.sh mariadbd $args &
        process="mariadbd"
    else
        docker-entrypoint.sh mysqld $args &
        process="mysqld"
    fi

    pid=$!
    log "INFO" "The process ID of $process is '$pid'"
}

backup_restored=0
if [ -f "/scripts/receive_backup.txt" ]; then
  echo "Waiting for the master to start streaming backup data..."
  echo "$POD_IP">/scripts/backup_receive_started.txt
  while true; do
    socat -u TCP-LISTEN:3307 STDOUT | mbstream -x -C /var/lib/mysql
    if [ $? -eq 0 ]; then
      log "INFO" "Data restore successful."
      break
    else
      log "INFO" "Data restore failed."
      rm -rf /var/lib/mysql
    fi
  done
  mariabackup --prepare --target-dir=/var/lib/mysql
  rm /scripts/backup_receive_started.txt
  backup_restored=1
  rm /scripts/receive_backup.txt
fi

start_mysqld_in_background

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
  export mysql_header="mariadb -u ${USER} --port=3306 --ssl-ca=/etc/mysql/certs/server/ca.crt  --ssl-cert=/etc/mysql/certs/server/tls.crt --ssl-key=/etc/mysql/certs/server/tls.key"
else
  export mysql_header="mariadb -u ${USER} --port=3306"
fi

export MYSQL_PWD=${PASSWORD}

# wait for mysqld to be ready
wait_for_mysqld_running

# ensure replication user
create_replication_user

# ensure maxscale user
create_maxscale_user

# ensure monitor user
create_monitor_user

#TODO:
# ensure maxscale_confsync user
#create_maxscale_confsync_user

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

    if [[ $desired_func == "join_to_master" ]]; then
      # wait for the script copied by coordinator
      while [ ! -f "/scripts/master.txt" ]; do
          log "WARNING" "master detector file isn't present yet!"
          sleep 1
      done
      master=$(cat /scripts/master.txt)
      rm -rf /scripts/master.txt
      if [[ $backup_restored -eq 0 ]]; then
        join_to_master_by_current_pos
      else
        while [ ! -f "/scripts/gtid.txt" ]; do
            log "WARNING" "gtid detector file isn't present yet!"
            sleep 1
        done
        gtid=$(cat /scripts/gtid.txt)
        echo "master replica's current gtid position is $gtid"
        rm -rf /scripts/gtid.txt
        join_to_master_by_slave_pos
      fi
    fi
    log "INFO" "waiting for mysql process id  = $pid"
    wait $pid
done

