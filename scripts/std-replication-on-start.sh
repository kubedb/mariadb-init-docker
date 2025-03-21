#!/usr/bin/env bash

script_name=${0##*/}

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

# wait for the peer-list file created by coordinator
log "WARNING" "waiting for peer-list file to come"
while [ ! -f "/scripts/peer-list" ]; do
    sleep 1
done

log "INFO" "found peer-list file"

# get the comma separated peer names for galera.cnf file
hosts=$(cat "/scripts/peer-list")

log "INFO" "hosts are {$hosts}"
svr_id=$(($(echo -n "${HOSTNAME}" | sed -e "s/${BASE_NAME}-//g") + 1))

echo "Generated server_id -> $svr_id"
echo "Hostname: ${HOSTNAME}"
echo "Base Name: ${BASE_NAME}"

# write configuration file
if [[ $MARIADB_VERSION == "1:11"* ]]; then
    cat >>/etc/mysql/conf.d/my.cnf <<EOL
[mariadbd]
log-bin
log_bin=mariadb-bin
log_slave_updates=1
server_id=$svr_id
bind-address=0.0.0.0
gtid_strict_mode=ON
binlog-format=mixed
EOL
else
    cat >>/etc/mysql/conf.d/my.cnf <<EOL
[mysqld]
log-bin
log_bin=mariadb-bin
log_slave_updates=1
server_id=$svr_id
bind-address=0.0.0.0
gtid_strict_mode=ON
binlog-format=mixed
EOL
fi

# wait for the pre script copied by coordinator
log "WARNING" "waiting for pre-run-on-present script to come"
while [ ! -f "/run-script/pre-run-on-present.sh" ]; do
    sleep 1
done

log "INFO" "found pre-run-on-present script"

# run the pre script copied by mariadb-coordinator
./run-script/pre-run-on-present.sh

# wait for the script copied by coordinator
log "WARNING" "waiting for run-on-present script to come"
while [ ! -f "/run-script/run-on-present.sh" ]; do
    sleep 1
done

log "INFO" "found run-on-present script"

# run the script copied by mariadb-coordinator and pass the arguments
./run-script/run-on-present.sh $@
