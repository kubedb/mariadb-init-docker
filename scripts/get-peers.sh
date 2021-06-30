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

cur_host=$(echo -n ${HOST_ADDRESS%.svc*})
log "INFO" "I am $cur_host"

log "INFO" "Reading standard input from peer-finder..."
while read -ra line; do
    tmp=$(echo -n ${line%.svc*})
    if [[ "$HOST_ADDRESS_TYPE" == "IPv6" ]]; then
        tmp="[$tmp]"
    fi
    peers=("${peers[@]}" "$tmp")
done
log "INFO" "Trying to start group with peers'${peers[*]}'"

cat <<<"${peers[*]}" >/scripts/peer-list.txt

log "VALO koira dekh" "First peer-finder passed"

## find peers, configure galera and add custom config
#/scripts/peer-finder -service=${GOVERNING_SERVICE_NAME} -on-start scripts/on-start.sh


# comma separated host names
export hosts=$(echo -n ${peers[*]} | sed -e "s/ /,/g")

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

FILE=/run-script/run-on-present.sh

# wait for the script copied by coordinator
while [ ! -f "$FILE" ]; do
    log "WARNING" "run-on-present script is not present yet"
    sleep 1
done

log "INFO" "found run-on-present script"

# include directory in my.cnf for custom-config
mkdir /etc/mysql/custom.conf.d/
echo '!includedir /etc/mysql/custom.conf.d/' >>/etc/mysql/my.cnf

# run the script copied by mariadb-coordinator
./run-script/run-on-present.sh