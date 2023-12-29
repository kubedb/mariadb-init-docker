#!/usr/bin/env bash

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

if [[ $MARIADB_VERSION == "1:11"* ]]; then
    docker-entrypoint.sh mariadbd --wsrep-new-cluster $@
else
    docker-entrypoint.sh mysqld --wsrep-new-cluster $@
fi
