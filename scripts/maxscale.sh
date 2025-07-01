#!/bin/sh

args="$@"
echo "INFO:" "Storing default config into /etc/maxscale/maxscale.cnf"

#mkdir -p /etc/maxscale/maxscale.cnf.d

#=====================[maxscale] section started ===============================
cat > /etc/maxscale/maxscale.cnf <<EOL
[maxscale]
threads=1
log_debug=1
EOL

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

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
  cat >>/etc/maxscale/maxscale.cnf <<EOL
ssl=true
ssl_ca=/etc/ssl/maxscale/ca.crt
ssl_cert=/etc/ssl/maxscale/tls.crt
ssl_key=/etc/ssl/maxscale/tls.key
EOL
fi
#=====================[maxscale] section end ====================================

#TODO: configuration sync: among maxscale nodes, when something done in a specific maxscale
#https://mariadb.com/kb/en/mariadb-maxscale-2402-maxscale-2402-mariadb-maxscale-configuration-guide/#runtime-configuration-changes
#if [ "${MAXSCALE_CLUSTER:-}" == "true"  ];then
#  cat >>/etc/maxscale/maxscale.cnf <<EOL
#config_sync_cluster  = ReplicationMonitor
#config_sync_user     = maxscale_confsync
#config_sync_password = '$MYSQL_ROOT_PASSWORD'
#EOL
#fi

cat >> /etc/maxscale/maxscale.cnf <<EOL
# Auto-generated server list from environment
EOL

serverList=""
# Split HOST_LIST into an array
for ((i=1; i<=REPLICAS; i++)); do
  cat >> /etc/maxscale/maxscale.cnf <<EOL

[server$i]
type=server
address=$BASE_NAME-$((i - 1)).$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc.cluster.local
port=3306
protocol=MariaDBBackend
EOL
  if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
    cat >>/etc/maxscale/maxscale.cnf <<EOL
ssl=true
ssl_ca=/etc/ssl/maxscale/ca.crt
ssl_cert=/etc/ssl/maxscale/tls.crt
ssl_key=/etc/ssl/maxscale/tls.key
EOL
  fi

  if [[ -n "$serverList" ]]; then
      serverList+=","
  fi
  serverList+="server$i"
done

cat >>/etc/maxscale/maxscale.cnf <<EOL

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

if [ "${MAXSCALE_CLUSTER:-}" == "true"  ];then
  cat >>/etc/maxscale/maxscale.cnf <<EOL
cooperative_monitoring_locks=majority_of_running
EOL
fi
cat >>/etc/maxscale/maxscale.cnf <<EOL

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
enable_root_user=true
EOL

cat >>/etc/maxscale/maxscale.cnf <<EOL

[RW-Split-Listener]
type=listener
service=RW-Split-Router
protocol=MariaDBClient
port=3306
EOL


echo "INFO: MaxScale configuration files have been successfully created."


# Merge File1 with File2 and store it in File1
function  merge() {
    local tempFile=etc/maxscale/temp.cnf
    touch "$tempFile"
    # Match [section] headers in the first block
    # Match key=value pairs in the second block
    # Ignore all other lines
    # Finally print merged configuration in the third block
    awk '/^\[.*\]$/ {
       section = $0
       if (seen[section] == 0) {
        seq[++n] = section
        seen[section] = 1
       }
       next
    }
    /^[^=]+=[^=]+$/ {
        split($0,kv,"=")
        key = kv[1]
        val = kv[2]
        a[section, key] = val
    }
    END {
       for (i = 1; i <= n; i++){
            section = seq[i]
            print section
            for (k in a){
                split(k, parts, SUBSEP)
                if (parts[1] == section){
                    print parts[2] "=" a[k]
                }
            }
            if (i < n) print ""
       }
    }' $1 $2 > $tempFile

    mv "$tempFile" "$1"

    echo "INFO: $1 merged with $2"
}

function mergeCustomConfig() {
    defaultConfig=/etc/maxscale/maxscale.cnf
    customConfig=(/etc/maxscale/maxscale.custom.d/*.cnf)

   #  Check if any files are found
    if [ -e "${customConfig[0]}" ]; then
      echo "INFO: Found custom config files"
      for file in "${customConfig[@]}"; do
         merge $defaultConfig  $file
      done
    else
      echo "INFO: No custom config found"
    fi
}

mergeCustomConfig

IFS=' '
set -- $args
docker-entrypoint.sh maxscale "$@"

