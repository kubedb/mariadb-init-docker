#!/bin/sh

args="$@"
echo "INFO" "Storing default config into /etc/maxscale/maxscale.cnf"

mkdir -p /etc/maxscale/maxscale.cnf.d
cat >>/etc/maxscale/maxscale.cnf <<EOL
[maxscale]
threads=1
log_debug=1
EOL

cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL
# Auto-generated server list from environment
EOL

serverList=""
# Split HOST_LIST into an array
for ((i=1; i<=REPLICAS; i++)); do
  cat >> /etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL
[server$i]
type=server
address=$BASE_NAME-$((i - 1)).$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc.cluster.local
port=3306
protocol=MariaDBBackend
EOL
  if [[ -n "$serverList" ]]; then
      serverList+=","
  fi
  serverList+="server$i"
done

if [[ "${UI:-}" == "true" ]]; then
  cat >>/etc/maxscale/maxscale.cnf <<EOL
admin_secure_gui=false
# this enables external access to the REST API outside of localhost
# review / modify for any public / non development environments
admin_host=0.0.0.0
EOL
else
  echo "UI is not set to true or does not exist."
fi

cat >>/etc/maxscale/maxscale.cnf.d/maxscale.cnf <<EOL

[ReplicationMonitor]
type=monitor
module=mariadbmon
servers=$serverList
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
servers=$serverList
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

echo "INFO: MaxScale configuration files have been successfully created."
IFS=' '
set -- $args
docker-entrypoint.sh maxscale "$@"

