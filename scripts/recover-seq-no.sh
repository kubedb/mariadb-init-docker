#!/usr/bin/env bash

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

export line=$(docker-entrypoint.sh mysqld --wsrep-recover 2>&1 | grep "Recovered position:" | xargs echo) && echo -n ${line##*:} > /scripts/seqno

FILE=/run-script/after-run-on-present.sh

# wait for the script copied by coordinator
while [ ! -f "$FILE" ]; do
    log "WARNING" "after-run-on-present script is not present yet"
    sleep 1
done

log "INFO" "found after-run-on-present script"

# run the script copied by mariadb-coordinator
./run-script/after-run-on-present.sh


