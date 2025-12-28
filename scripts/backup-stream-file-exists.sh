#!/usr/bin/env bash

if [ -f /scripts/backup_data_stream_pod_ip.txt ]; then
    echo -n "Yes"
else
    echo -n "No"
fi
