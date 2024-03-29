#!/usr/bin/env bash

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

# overwrite safe_to_bootstrap=1 to allow cluster bootstrap after crash
sed -i -e 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat

# bootstrap new cluster
if [[ $MARIADB_VERSION == "1:11"* ]]; then
    docker-entrypoint.sh mariadbd --wsrep-new-cluster $@
else
    docker-entrypoint.sh mysqld --wsrep-new-cluster $@
fi
