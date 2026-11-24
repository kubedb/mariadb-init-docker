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

# include directory in my.cnf for custom-config
if [ ! -z "$(ls -A /etc/mysql/custom.conf.d/)" ]; then
    echo '!includedir /etc/mysql/custom.conf.d/' >>/etc/mysql/my.cnf
fi

# DC-DR automatic re-seed (mariadb-coordinator dcdr_reseed.go): while /scripts/dcdr-hold exists this node
# must not start mariadbd. With /scripts/dcdr-wipe it first empties its data directory, so it joins the
# re-seeded node of its data center by SST. /scripts/dcdr-held tells the coordinator it is stopped and empty.
function dcdr_hold() {
    [ -f /scripts/dcdr-hold ] || return 0
    if [ -f /scripts/dcdr-wipe ]; then
        log "WARNING" "DC-DR re-seed: wiping the data directory; this node joins the re-seeded node empty"
        find /var/lib/mysql -mindepth 1 -maxdepth 1 ! -name lost+found -exec rm -rf {} +
        rm -f /scripts/dcdr-wipe
    fi
    echo held >/scripts/dcdr-held
    while [ -f /scripts/dcdr-hold ]; do
        log "INFO" "DC-DR re-seed: holding until the re-seeded node of this data center serves"
        sleep 5
    done
    rm -f /scripts/dcdr-held
    log "INFO" "DC-DR re-seed: hold released"
}

while [ true ]; do
    dcdr_hold
    log "INFO" "initializing run.sh"

    # clean up old files
    rm -rf /run-script/*
    if [ -f "/scripts/peer-list" ]; then
        rm /scripts/peer-list
    fi

    if [ -f "/scripts/seqno" ]; then
        rm /scripts/seqno
    fi
    ./scripts/ensure-restore.sh
    # start on-start script
    ./scripts/on-start.sh $@
    sleep 1
done
