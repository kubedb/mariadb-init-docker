#!/usr/bin/env bash

# Environment variables passed from Pod env are as follows:
#
#   CLUSTER_NAME = name of the mariadb cr
#   MYSQL_ROOT_USERNAME = root user name of the mariadb database server
#   MYSQL_ROOT_PASSWORD = root password of the mariadb database server
#   HOST_ADDRESS        = Address used to communicate among the peers. This can be fully qualified host name or IPv4 or IPv6
#   HOST_ADDRESS_TYPE   = Address type of HOST_ADDRESS (one of DNS, IPV4, IPv6)
#   POD_IP              = IP address used to create whitelist CIDR. For HOST_ADDRESS_TYPE=DNS, it will be status.PodIP.
#   POD_IP_TYPE         = Address type of POD_IP (one of IPV4, IPv6)

env | sort | grep "POD\|HOST\|NAME"

script_name=${0##*/}

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

if [ -z "$CLUSTER_NAME" ]; then
    echo >&2 'Error:  You need to specify CLUSTER_NAME'
    exit 1
fi

cur_host=$(echo -n ${HOST_ADDRESS%.svc*})
log "INFO" "I am $cur_host"

log "INFO" "Reading standard input..."
while read -ra line; do
    tmp=$(echo -n ${line%.svc*})
    if [[ "$HOST_ADDRESS_TYPE" == "IPv6" ]]; then
        tmp="[$tmp]"
    fi
    peers=("${peers[@]}" "$tmp")
done
log "INFO" "Trying to start group with peers'${peers[*]}'"

cat <<<"${peers[*]}" >/scripts/peer-list.txt

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

# include directory in my.cnf for custom-config
mkdir /etc/mysql/custom.conf.d/
echo '!includedir /etc/mysql/custom.conf.d/' >>/etc/mysql/my.cnf

# run the script copied by mariadb-coordinator
./run-script/run-on-present.sh
