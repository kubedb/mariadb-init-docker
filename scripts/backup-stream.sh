#!/usr/bin/env bash

ip=$(cat "/scripts/joiner_ip.txt")
echo "Start master data transferring..ip $ip"
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"

# Detect address family from the joiner IP so this works on IPv4-only,
# IPv6-only, and dual-stack clusters. IPv6 addresses contain ':'.
if [[ "$ip" == *:* ]]; then
    CONNECT_PROTO="TCP6"
    PF_OPT="pf=ip6"
    # IPv6 needs brackets around the address in TCP:host:port form
    ADDR_SPEC="[${ip}]:3307"
else
    CONNECT_PROTO="TCP4"
    PF_OPT="pf=ip4"
    ADDR_SPEC="${ip}:3307"
fi

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
    # TLS mode: validate joiner's cert against our CA. Joiner's listener
    # also validates our cert (verify=1 on both sides → mutual auth).
    mariadb-backup --backup --stream=mbstream --user=root | \
        socat -u STDIN \
        "OPENSSL:${ADDR_SPEC},${PF_OPT},cert=/etc/mysql/certs/server/tls.crt,key=/etc/mysql/certs/server/tls.key,cafile=/etc/mysql/certs/server/ca.crt,verify=1"
else
    # Plain TCP. Family-explicit variant matches the joiner's listener.
    mariadb-backup --backup --stream=mbstream --user=root | \
        socat -u STDIN "${CONNECT_PROTO}:${ADDR_SPEC}"
fi

# Check both ends of the pipeline — a plain $? would only see socat's exit
# code and miss a failed mariabackup upstream (producing an "apparent
# success" while no bytes were actually transferred). Default empty to 1
# so a missing PIPESTATUS entry is treated as failure, not parsed as "".
mariabackup_rc=${PIPESTATUS[0]:-1}
socat_rc=${PIPESTATUS[1]:-1}
if [ "$mariabackup_rc" -eq 0 ] && [ "$socat_rc" -eq 0 ]; then
    echo "Backup data for pod $ip transferred successfully."
else
    echo "Backup data transfer for pod $ip failed (mariadb-backup=${mariabackup_rc}, socat=${socat_rc})."
fi
rm /scripts/joiner_ip.txt
