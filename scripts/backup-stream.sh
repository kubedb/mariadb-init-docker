#!/usr/bin/env bash

if [ -f /scripts/backup_data_stream_pod_ip.txt ]; then
   ip=$(cat "/scripts/backup_data_stream_pod_ip.txt")
   echo "Start master data transferring.."
   export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
   mariabackup --backup --stream=mbstream --user=root | socat -u STDIN TCP:$ip:3307
   if [ $? -eq 0 ]; then
     echo "Backup data transferred successfully."
   else
     echo "Backup data transfer failed."
   fi
   rm /scripts/ip.txt
fi

