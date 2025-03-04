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

report_host="$HOSTNAME.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc"
echo "report_host = $report_host "
localhost="127.0.0.1"

function join_by_gtid() {
    # member try to join into the existing group as old instance
    log "INFO" "The replica, ${report_host} is joining to master node ${master} by master node's gtid..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Resetting binlog,gtid and set gtid_slave_pos to master gtid.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    retry 20 ${mysql} -N -e "SET GLOBAL gtid_slave_pos = '$gtid';"
    retry 10 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master',MASTER_USER='repl',MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD',MASTER_USE_GTID = slave_pos;"
    retry 10 ${mysql} -N -e "START SLAVE;"
    retry 10 ${mysql} -N -e "SET SQL_LOG_BIN=0;"
    echo "end join to master node by gtid"
}

export mysql_header="mariadb -u ${USER} --port=3306"
export MYSQL_PWD=${PASSWORD}

# wait for the script copied by coordinator
while [ ! -f "/scripts/signal.txt" ]; do
    log "WARNING" "signal is not present yet!"
    sleep 1
done
desired_func=$(cat /scripts/signal.txt)
rm -rf /scripts/signal.txt
log "INFO" "going to execute $desired_func"
if [[ $desired_func == "join_to_master" ]]; then
    # wait for the script copied by coordinator
    while [ ! -f "/scripts/master.txt" ]; do
        log "WARNING" "master detector file isn't present yet!"
        sleep 1
    done
    master=$(cat /scripts/master.txt)

    while [ ! -f "/scripts/gtid_slave_pos.txt" ]; do
        log "WARNING" "gtid detector file isn't present yet!"
        sleep 1
    done
    gtid=$(cat /scripts/gtid_slave_pos.txt)
    echo "master replica's current gtid position is $gtid"
    rm -rf /scripts/gtid_slave_pos.txt
    join_by_gtid
fi

