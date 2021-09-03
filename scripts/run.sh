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

# write on galera configuration file
cat >>/etc/mysql/conf.d/galera.cnf <<EOL
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

# Galera Provider Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# Galera Cluster Configuration, Add the list of peers in wrsep_cluster_address
wsrep_cluster_name=$CLUSTER_NAME
wsrep_cluster_address="gcomm://${hosts}"

# Galera Synchronization Configuration
wsrep_node_address=${POD_IP}
wsrep_sst_method=rsync
EOL

# include directory in my.cnf for custom-config
mkdir /etc/mysql/custom.conf.d/
echo '!includedir /etc/mysql/custom.conf.d/' >>/etc/mysql/my.cnf

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
