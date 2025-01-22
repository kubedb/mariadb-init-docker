#!/bin/sh

# Assuming HOST_LIST is set as a comma-separated list like "ha-mariadb-0,ha-mariadb-1,ha-mariadb-2"
IFS=',' read -r -a hosts <<< "$HOST_LIST"

log "INFO" "Storing default mysqld config into /etc/mysql/my.cnf"
mkdir -p /etc/maxscale/conf.d/
echo "!includedir /etc/maxscale/conf.d/" >>/etc/maxscale.cnf
mkdir -p /etc/maxscale/custom-conf.d/
echo "!includedir /etc/maxscale/custom-conf.d/" >>/etc/maxscale.cnf

cat >>/etc/maxscale/conf.d/maxscale.cnf <<EOL
[maxscale]
threads=auto
log_debug=1
EOL

cat >>/etc/maxscale/conf.d/maxscale.cnf <<EOL
[maxscale]
threads=auto
log_debug=1
EOL

cat >>/etc/maxscale/conf.d/monitor.cnf <<EOL
[ReplicationMonitor]
type=monitor
module=mariadbmon
servers=server1,server2,server3
user=monitor_user
password='$MYSQL_ROOT_PASSWORD'
auto_failover=ON
auto_rejoin=ON
enforce_read_only_slaves=true
monitor_interval=2s
replication_user=repl
replication_password='$MYSQL_ROOT_PASSWORD'
EOL


cat >>/etc/maxscale/conf.d/router.cnf <<EOL
[RW-Split-Router]
type=service
router=readwritesplit
servers=server1,server2,server3
user=maxscale
password='$MYSQL_ROOT_PASSWORD'
master_reconnection=true
master_failure_mode=fail_on_write
transaction_replay=true
slave_selection_criteria=ADAPTIVE_ROUTING
master_accept_reads=true
EOL

cat >>/etc/maxscale/conf.d/listener.cnf <<EOL
[RW-Split-Listener]
type=listener
service=RW-Split-Router
protocol=MariaDBClient
port=3306
EOL

# Append the server configurations to /etc/maxscale/conf.d/servers.cnf
cat >> /etc/maxscale/conf.d/servers.cnf <<EOL
# Auto-generated server list from environment
EOL

for i in "${!hosts[@]}"; do
  cat >> /etc/maxscale/conf.d/servers.cnf <<EOL
[server$((i+1))]
type=server
address=${hosts[$i]}.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc.cluster.local
port=3306
protocol=MariaDBBackend
EOL
done
