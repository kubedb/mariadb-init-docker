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

if [[ $DISTRIBUTED == "true" ]]; then
  while [ ! -f "/etc/podip/podip" ];do
    sleep 1
    echo "nsmIP not available!!!"
  done

  while [ ! -s /etc/podip/podip ]; do
    sleep 1
    echo "nsm ip not available"
  done

  export POD_IP=$(cat /etc/podip/podip)
  log "INFO" "pod ip is-> $POD_IP"
fi

# write on galera configuration file
major=$(echo "$MARIADB_VERSION" | sed -E 's/^1:([0-9]+).*/\1/' | grep -E '^[0-9]+$' || echo "0")

if [[ "$major" -ge 11 ]]; then
    cat >>/etc/mysql/conf.d/galera.cnf <<EOL
[mariadbd]
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
EOL
else
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
EOL
fi

# DC-DR (one Galera cluster per data center + an async GTID channel between them). Written on every
# start, including the in-place restart after a crash (run.sh loops), and never appended to:
# - read_only=ON on every boot: a restarted node must never be writable. Galera has no election, so
#   nothing else lifts it; the coordinator opens writes only in the active data center.
# - server_id is the same on all nodes of a data center (wsrep_gtid_mode needs it) and differs
#   between data centers; the GTID domain is per data center. A re-seeded data center moves to a
#   new domain (RESET MASTER is refused inside Galera); the coordinator records it on the data
#   volume, and that value wins over the initial one from the operator.
# - kubedb_system holds the health check writes, which root makes even on a read_only node: they
#   must never reach the binlog, or the standby mints GTIDs the active side does not have.
# - skip_slave_start: a node that held the cross-DC channel must not restart it on its own.
if [[ "$DCDR_ENABLED" == "true" ]]; then
    domain_file=/var/lib/mysql/.dcdr-gtid-domain-id
    domain_id=${DCDR_GTID_DOMAIN_ID:?DCDR_GTID_DOMAIN_ID is required with DCDR_ENABLED}
    if [[ -s "$domain_file" ]] && grep -qE '^[0-9]+$' "$domain_file"; then
        domain_id=$(cat "$domain_file")
    fi
    section=mysqld
    if [[ "$major" -ge 11 ]]; then
        section=mariadbd
    fi
    cat >/etc/mysql/conf.d/dcdr.cnf <<EOL
[$section]
read_only=ON
server_id=${DCDR_SERVER_ID:?DCDR_SERVER_ID is required with DCDR_ENABLED}
log_bin=/var/lib/mysql/mariadb-bin
log_slave_updates=ON
wsrep_gtid_mode=ON
wsrep_gtid_domain_id=${domain_id}
gtid_domain_id=$((domain_id + 1))
binlog_ignore_db=kubedb_system
skip_slave_start=ON
binlog_expire_logs_seconds=${DCDR_BINLOG_EXPIRE_SECONDS:-604800}
EOL
    log "INFO" "DC-DR: booting fenced (read_only=ON), server_id=$DCDR_SERVER_ID, wsrep_gtid_domain_id=$domain_id"
fi

if [[ $WSREP_SST_METHOD == "rsync" ]]; then
    echo "wsrep_sst_method=rsync" >>/etc/mysql/conf.d/galera.cnf
elif [[ $WSREP_SST_METHOD == "mariabackup" ]]; then
    echo "wsrep_sst_method=mariabackup
wsrep_sst_auth=$MYSQL_ROOT_USERNAME:$MYSQL_ROOT_PASSWORD
wsrep_sst_donor=all,  # https://mariadb.com/kb/en/mariabackup-sst-method/#choosing-a-donor-node" >>/etc/mysql/conf.d/galera.cnf
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
