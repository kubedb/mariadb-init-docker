#!/usr/bin/env bash

# The coordinator invokes this script via kmodules.xyz/client-go/tools/exec
# ExecIntoPod, which treats ANY bytes on stderr as a fatal exec error and
# throws the stdout away — even on successful exit. mariadb-backup is very
# chatty on stderr (every "[00] <timestamp> <file>" progress line goes there),
# so without redirection every run is reported as "failed to exec into pod"
# and the success/failure echoes below never land in the coordinator log.
# Route mariadb-backup's and socat's stderr to per-run log files; surface
# them on stdout at the end only when the pipeline actually fails.
mariabackup_err="/tmp/mariabackup.err"
socat_err="/tmp/socat.err"
: >"$mariabackup_err"
: >"$socat_err"

ip=$(cat "/scripts/joiner_ip.txt")
echo "Start master data transferring..ip $ip"
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"

# Detect address family from the joiner IP so this works on IPv4-only,
# IPv6-only, and dual-stack clusters. IPv6 addresses contain ':'.
if [[ "$ip" == *:* ]]; then
    CONNECT_PROTO="TCP6"
    PF_OPT="pf=ip6"
    # IPv6 needs brackets around the address in TCP:host:port form
    ADDR_SPEC="[${ip}]:4444"
else
    CONNECT_PROTO="TCP4"
    PF_OPT="pf=ip4"
    ADDR_SPEC="${ip}:4444"
fi

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
    # TLS mode: validate joiner's cert against our CA. Joiner's listener
    # also validates our cert (verify=1 on both sides → mutual auth).
    mariadb-backup --backup --stream=mbstream --user=root 2>"$mariabackup_err" | \
        socat -u STDIN \
        "OPENSSL:${ADDR_SPEC},${PF_OPT},cert=/etc/mysql/certs/server/tls.crt,key=/etc/mysql/certs/server/tls.key,cafile=/etc/mysql/certs/server/ca.crt,verify=1" 2>"$socat_err"
else
    # Plain TCP. Family-explicit variant matches the joiner's listener.
    mariadb-backup --backup --stream=mbstream --user=root 2>"$mariabackup_err" | \
        socat -u STDIN "${CONNECT_PROTO}:${ADDR_SPEC}" 2>"$socat_err"
fi

# Check both ends of the pipeline — a plain $? would only see socat's exit
# code and miss a failed mariabackup upstream (producing an "apparent
# success" while no bytes were actually transferred).
#
# Snapshot the whole PIPESTATUS array in one step: any simple command
# (including a variable assignment) executed between two ${PIPESTATUS[n]}
# reads resets the array, so reading [0] first and then [1] would make
# [1] fall through to the default and report a phantom failure.
pipe_status=("${PIPESTATUS[@]}")
mariabackup_rc=${pipe_status[0]:-1}
socat_rc=${pipe_status[1]:-1}
if [ "$mariabackup_rc" -eq 0 ] && [ "$socat_rc" -eq 0 ]; then
    echo "Backup data for pod $ip transferred successfully."
else
    echo "Backup data transfer for pod $ip failed (mariadb-backup=${mariabackup_rc}, socat=${socat_rc})."
    # Fold the captured stderr onto stdout so the operator can read the
    # real cause from the coordinator log (ExecIntoPod discards stderr
    # on success and hides stdout on stderr-non-empty — we want this
    # diagnostic to land either way).
    if [ -s "$mariabackup_err" ]; then
        echo "--- mariadb-backup stderr ---"
        tail -c 4000 "$mariabackup_err"
    fi
    if [ -s "$socat_err" ]; then
        echo "--- socat stderr ---"
        tail -c 2000 "$socat_err"
    fi
fi
rm /scripts/joiner_ip.txt
