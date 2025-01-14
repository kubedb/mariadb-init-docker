#!/usr/bin/env bash

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

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
    # now we need to configure a replication user for each server.
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether replication user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Replication user not found. Creating new replication user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'repl'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' REQUIRE SSL;"
        retry 120 ${mysql} -N -e "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"
        retry 120 ${mysql} -N -e "FLUSH PRIVILEGES;"
        retry 120 ${mysql} -N -e "FLUSH PRIVILEGES;"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
        retry 120 ${mysql} -N -e "RESET SLAVE ALL;"
    else
        log "INFO" "Replication user exists. Skipping creating new one......."
    fi
}

function create_maxscale_user() {
    # now we need to configure a replication user for each server.
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether maxscale user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Replication user not found. Creating new maxscale user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'maxscale'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' REQUIRE SSL;"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.user TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.db TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.tables_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.columns_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.procs_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.proxies_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SELECT ON mysql.roles_mapping TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "GRANT SHOW DATABASES ON *.* TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "FLUSH PRIVILEGES;"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
    else
        log "INFO" "Maxscale user exists. Skipping creating new one......."
    fi
}

function create_monitor_user() {
    # now we need to configure a replication user for each server.
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether monitor user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Replication user not found. Creating new monitor user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
        retry 120 ${mysql} -N -e "CREATE USER 'monitor_user'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' REQUIRE SSL;"
        retry 120 ${mysql} -N -e "GRANT REPLICATION CLIENT on *.* to 'monitor_user'@'%';"
        retry 120 ${mysql} -N -e "GRANT SUPER, RELOAD on *.* to 'monitor_user'@'%';"
        retry 120 ${mysql} -N -e "FLUSH PRIVILEGES;"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
    else
        log "INFO" "Monitor user exists. Skipping creating new one......."
    fi
    touch /scripts/ready.txt
}
export pid
function start_mysqld_in_background() {
    log "INFO" "Starting mysql server with 'docker-entrypoint.sh mysqld $args'..."

    if [[ $MARIADB_VERSION == "1:11"* ]]; then
        docker-entrypoint.sh mariadbd $@
    else
        docker-entrypoint.sh mysqld $@
    fi
#    docker-entrypoint.sh mysqld $args &
    pid=$!
    log "INFO" "The process id of mysqld is '$pid'"
}



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
        check_member_list_updated "${member_hosts[*]}"
        wait_for_primary "${member_hosts[*]}"
        set_valid_donors
        join_into_cluster
    fi
    if [[ $desired_func == "join_by_clone" ]]; then
        check_member_list_updated "${member_hosts[*]}"
        wait_for_primary "${member_hosts[*]}"
        set_valid_donors
        join_by_clone
    fi
    joining_for_first_time=0
    log "INFO" "waiting for mysql process id  = $pid"
    wait $pid
done

if [[ $MARIADB_VERSION == "1:11"* ]]; then
    docker-entrypoint.sh mariadbd $@
else
    docker-entrypoint.sh mysqld $@
fi
