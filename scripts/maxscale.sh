#!/bin/sh

echo "INFO" "Storing default mysqld config into /etc/mysql/my.cnf"

#mkdir -p /etc/maxscale.cnf.d/conf.d/
#echo "[maxscale] /etc/maxscale.cnf.d/conf.d/" >>/etc/maxscale.cnf.d/maxscale.cnf
#echo "!includedir /etc/maxscale.cnf.d/conf.d/" >>/etc/maxscale.cnf.d/maxscale.cnf
#mkdir -p /etc/maxscale.cnf.d/custom-conf.d/
#echo "!includedir /etc/maxscale.cnf.d/custom-conf.d/" >>/etc/maxscale.cnf.d/maxscale.cnf

# Assuming HOST_LIST is set as a comma-separated list like "ha-mariadb-0,ha-mariadb-1,ha-mariadb-2"
#IFS=',' read -r -a hosts <<< "$HOST_LIST"
IFS=','
set -- $HOST_LIST

#not working, says duplicate, as main file contains maxscale section
#cat >>/etc/maxscale.cnf.d/maxscale.cnf <<EOL
#[maxscale]
#threads=auto
#log_debug=1
#EOL

cat >>/etc/maxscale.cnf.d/monitor.cnf <<EOL
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


cat >>/etc/maxscale.cnf.d/router.cnf <<EOL
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

cat >>/etc/maxscale.cnf.d/listener.cnf <<EOL
[RW-Split-Listener]
type=listener
service=RW-Split-Router
protocol=MariaDBClient
port=3306
EOL

# Append the server configurations to /etc/maxscale/conf.d/servers.cnf
cat >> /etc/maxscale.cnf.d/servers.cnf <<EOL
# Auto-generated server list from environment
EOL

i=1
for host in "$@"; do
  cat >> /etc/maxscale.cnf.d/servers.cnf <<EOL
[server$i]
type=server
address=$host.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc.cluster.local
port=3306
protocol=MariaDBBackend
EOL
  i=$((i + 1))
done

echo "INFO: MaxScale configuration files have been successfully created."
