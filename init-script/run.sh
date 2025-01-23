#!/bin/sh

rm -rf /var/lib/mysql/lost+found
rm -rf /scripts/*

cp /tmp/scripts/* /scripts

if [[ "${MAXSCALE:-}" == "true" ]]; then
  cat /tmp/scripts/maxscale.sh
  /tmp/scripts/maxscale.sh
fi

