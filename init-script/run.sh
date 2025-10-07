#!/bin/sh

rm -rf /var/lib/mysql/lost+found
rm -rf /scripts/*

cp /tmp/scripts/* /scripts

if [[ "$PITR_RESTORE" == "true" ]]; then
  if [[ "$HOSTNAME" != *"-0" ]]; then
    if [[ -f /var/lib/mysql/gvwstate.dat ]]; then
       rm /var/lib/mysql/gvwstate.dat
    fi
  fi
fi