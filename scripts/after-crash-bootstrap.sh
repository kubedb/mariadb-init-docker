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
major=$(echo "$MARIADB_VERSION" | sed -E 's/^1:([0-9]+).*/\1/' | grep -E '^[0-9]+$' || echo "0")

if [[ "$major" -ge 11 ]]; then
    docker-entrypoint.sh mariadbd --wsrep-new-cluster $@
else
    docker-entrypoint.sh mysqld --wsrep-new-cluster $@
fi
