#!/usr/bin/env bash

ip=$(cat "/scripts/joiner_ip.txt")
echo "Start master data transferring..ip $ip"
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
    # TLS mode: validate joiner's cert against our CA. Joiner's listener
    # also validates our cert (verify=1 on both sides → mutual auth).
    # pf=ip4 keeps the connect side on IPv4 to match the joiner's listener.
    mariabackup --backup --stream=mbstream --user=root | \
        socat -u STDIN \
        "OPENSSL:${ip}:3307,pf=ip4,cert=/etc/mysql/certs/server/tls.crt,key=/etc/mysql/certs/server/tls.key,cafile=/etc/mysql/certs/server/ca.crt,verify=1"
else
    # Plain TCP. TCP4 forces IPv4, matching the joiner's TCP4-LISTEN.
    # The joiner's listener restricts source via range=<master-ip>/32.
    mariabackup --backup --stream=mbstream --user=root | socat -u STDIN "TCP4:${ip}:3307"
fi

# Check both ends of the pipeline — a plain $? would only see socat's exit
# code and miss a failed mariabackup upstream (producing an "apparent
# success" while no bytes were actually transferred).
mariabackup_rc=${PIPESTATUS[0]}
socat_rc=${PIPESTATUS[1]}
if [ "$mariabackup_rc" -eq 0 ] && [ "$socat_rc" -eq 0 ]; then
    echo "Backup data for pod $ip transferred successfully."
else
    echo "Backup data transfer for pod $ip failed (mariabackup=${mariabackup_rc}, socat=${socat_rc})."
fi
rm /scripts/joiner_ip.txt
