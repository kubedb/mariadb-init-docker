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
# write on galera configuration file
cat >>/etc/maxscale.cnf <<EOL
    [maxscale]
    threads=auto
    log_debug=1
    [server1]
    type=server
    address=mariadb-primary-0.mariadb-primary.demo.svc.cluster.local
    port=3306
    protocol=MariaDBBackend

    [server2]
    type=server
    address=mariadb-replica1-0.mariadb-replica1.demo.svc.cluster.local
    port=3306
    protocol=MariaDBBackend

    [server3]
    type=server
    address=mariadb-replica2-0.mariadb-replica2.demo.svc.cluster.local
    port=3306
    protocol=MariaDBBackend

    [ReplicationMonitor]
    type=monitor
    module=mariadbmon
    servers=server1,server2,server3
    user=monitor_user
    password=my_password
    auto_failover=ON
    auto_rejoin=ON
    enforce_read_only_slaves=true
    monitor_interval=2s
    replication_user=repl
    replication_password=repl_password

    [RW-Split-Router]
    type=service
    router=readwritesplit
    servers=server1,server2,server3
    user=maxscale
    password=maxscale_pw
    master_reconnection=true
    master_failure_mode=fail_on_write
    transaction_replay=true
    slave_selection_criteria=ADAPTIVE_ROUTING
    master_accept_reads=true

    [RW-Split-Listener]
    type=listener
    service=RW-Split-Router
    protocol=MariaDBClient
    port=3306
EOL
