#!/bin/sh

args="$@"
echo "INFO" "Storing default mysqld config into /etc/maxscale/maxscale.cnf"

mkdir -p /etc/maxscale/maxscale.cnf.d
#not working, says duplicate, as main file contains maxscale section
cat >>/etc/maxscale/maxscale.cnf <<EOL
[maxscale]
admin_secure_gui=false
threads=1
log_debug=1
# this enables external access to the REST API outside of localhost
# please review / modify for any public / non development environments
admin_host=0.0.0.0

EOL

cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL

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


cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL

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

cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL

[RW-Split-Listener]
type=listener
service=RW-Split-Router
protocol=MariaDBClient
port=3306
EOL

cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL
# Auto-generated server list from environment
EOL

i=1
# Split HOST_LIST into an array
IFS=',' read -r -a host_array <<< "$HOST_LIST"
for host in "${host_array[@]}"; do
  cat >> /etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL

[server$i]
type=server
address=$host.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc.cluster.local
port=3306
protocol=MariaDBBackend
EOL
  i=$((i + 1))
done

echo "INFO: MaxScale configuration files have been successfully created."
IFS=' '
set -- $args
docker-entrypoint.sh maxscale "$@"










