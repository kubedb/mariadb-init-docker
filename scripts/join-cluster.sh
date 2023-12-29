#!/usr/bin/env bash

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

export DATABASE_ALREADY_EXISTS=true

if [[ $MARIADB_VERSION == "1:11"* ]]; then
    docker-entrypoint.sh mariadbd $@
else
    docker-entrypoint.sh mysqld $@
fi
