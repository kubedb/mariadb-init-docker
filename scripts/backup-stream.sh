#!/usr/bin/env bash

ip=$(cat "/scripts/backup_data_stream_pod_ip.txt")
echo "Start master data transferring..ip $ip"
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
mariabackup --backup --stream=mbstream --user=root | socat -u STDIN TCP:$ip:3307
if [ $? -eq 0 ]; then
    echo "Backup data for pod $ip transferred successfully."
else
    echo "Backup data transfer for pod $ip failed."
fi
rm /scripts/backup_data_stream_pod_ip.txt
