#!/usr/bin/env bash
env | sort | grep "POD\|HOST\|NAME\|SSL"

args=$@
NAMESPACE="$POD_NAMESPACE"
USER="$MYSQL_ROOT_USERNAME"
PASSWORD="$MYSQL_ROOT_PASSWORD"
function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

function retry {
    local retries="$1"
    shift

    local count=0
    local wait=1
    until "$@"; do
        exit="$?"
        if [ $count -lt $retries ]; then
            log "INFO" "Attempt $count/$retries. Command exited with exit_code: $exit. Retrying after $wait seconds..."
            sleep $wait
        else
            log "INFO" "Command failed in all $retries attempts with exit_code: $exit. Stopping trying any further...."
            return $exit
        fi
        count=$(($count + 1))
    done
    return 0
}

report_host="$HOSTNAME.$GOVERNING_SERVICE_NAME.$POD_NAMESPACE.svc"
echo "report_host = $report_host"

localhost="127.0.0.1"
# wait for mysql daemon be running (alive)
function wait_for_mysqld_running() {
    local mysql="$mysql_header --host=$localhost"
    for i in {900..0}; do
        out=$(${mysql} -N -e "select 1;" 2>/dev/null)
        log "INFO" "Attempt $i: Pinging '$report_host' has returned: '$out'...................................."
        if [[ "$out" == "1" ]]; then
            break
        fi
        echo -n .
        sleep 1
    done

    if [[ "$i" == "0" ]]; then
        echo ""
        log "ERROR" "Server ${report_host} failed to start in 900 seconds............."
        exit 1
    fi
    log "INFO" "mysql daemon is ready to use......."
}

joining_for_first_time=1

function alter_user(){
      local mysql="$mysql_header --host=$localhost"
      local ssl_require=""
      local user="$1"
      if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
        ssl_require="REQUIRE SSL"
      else
        ssl_require="REQUIRE NONE"
      fi
      retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;ALTER USER '$user'@'%' $ssl_require;"
}

function create_replication_user() {
    # https://mariadb.com/kb/en/setting-up-replication/
    log "INFO" "Checking whether replication user exist or not......"
    local mysql="$mysql_header --host=$localhost"
    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='repl';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        joining_for_first_time=0
        log "INFO" "Replication user not found. Creating new replication user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'repl'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Replication user exists. Skipping creating new one......."
    fi
    alter_user "repl"
}

function create_maxscale_user() {
    log "INFO" "Checking whether maxscale user exist or not......"
    local mysql="$mysql_header --host=$localhost"
    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Maxscale user not found. Creating new maxscale user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'maxscale'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.user TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.db TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.tables_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.columns_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.procs_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.proxies_priv TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT ON mysql.roles_mapping TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SHOW DATABASES ON *.* TO 'maxscale'@'%';"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Maxscale user exists. Skipping creating new one......."
    fi
    alter_user "maxscale"
}

#//TODO:
#function create_maxscale_confsync_user() {
#    log "INFO" "Checking whether maxscale user exist or not......"
#    local mysql="$mysql_header --host=$localhost"
#    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
#    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale_confsync';" | awk '{print$1}'
#    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='maxscale_confsync';" | awk '{print$1}')
#    # if the user doesn't exist, crete new one.
#    if [[ "$out" -eq "0" ]]; then
#        log "INFO" "maxscale_confsync user not found. Creating new maxscale_confsync user........"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'maxscale_confsync'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SELECT, INSERT, UPDATE, CREATE ON mysql.maxscale_config TO maxscale_confsync@'%';"
#        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
#    else
#        log "INFO" "maxscale_confsync user exists. Skipping creating new one......."
#    fi
#}


function create_monitor_user() {
    log "INFO" "Checking whether monitor user exist or not......"
    local mysql="$mysql_header --host=$localhost"

    # At first, ensure that the command executes without any error. Then, run the command again and extract the output.
    retry 120 ${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}'
    out=$(${mysql} -N -e "select count(host) from mysql.user where mysql.user.user='monitor_user';" | awk '{print$1}')
    # if the user doesn't exist, crete new one.
    if [[ "$out" -eq "0" ]]; then
        log "INFO" "Monitor user not found. Creating new monitor user........"
        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;CREATE USER 'monitor_user'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
        #mariadb 10.6+ change SUPER-> READ_ONLY ADMIN, REPLICATION CLIENT> SLAVE MONITOR
        if [[ "$(echo -e "1:10.7\n$MARIADB_VERSION" | sort -V | tail -n1)" == "$MARIADB_VERSION" ]]; then
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT READ_ONLY ADMIN, RELOAD on *.* to 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SLAVE MONITOR ON *.* TO 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT BINLOG ADMIN, REPLICATION MASTER ADMIN, REPLICATION SLAVE ADMIN ON *.* TO 'monitor_user'@'%';"
        else
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT SUPER, RELOAD on *.* to 'monitor_user'@'%';"
          retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;GRANT REPLICATION CLIENT on *.* to 'monitor_user'@'%';"
        fi

        retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=0;FLUSH PRIVILEGES;"
    else
        log "INFO" "Monitor user exists. Skipping creating new one......."
    fi
    alter_user "monitor_user"
}
function bootstrap_cluster() {
    echo "this is master node"
    local mysql="$mysql_header --host=$localhost"
    retry 120 ${mysql} -N -e "SET SQL_LOG_BIN=1;"
}

function join_to_master_by_current_pos() {
    # member try to join into the existing group as fresh install, datadir is clean and no backup is restored
    log "INFO" "The replica, ${report_host} is joining to master node ${master}..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Joining to master with gtid current_pos.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    local ssl_options=""
    if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
        ssl_options=", MASTER_SSL=1, MASTER_SSL_CA='/etc/mysql/certs/server/ca.crt'"
        log "INFO" "Configuring replication with TLS enabled"
    else
        log "INFO" "Configuring replication without TLS"
    fi
    retry 20 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master', MASTER_USER='repl', MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD' $ssl_options, MASTER_USE_GTID=current_pos;"
    retry 20 ${mysql} -N -e "START SLAVE;"
    joining_for_first_time=0
    echo "end join to master node by gtid current_pos"
}

function join_to_master_by_slave_pos() {
    # member try to join into the existing group as old instance
    log "INFO" "The replica, ${report_host} is joining to master node ${master} by slave_pos..."
    local mysql="$mysql_header --host=$localhost"
    log "INFO" "Resetting binlog,gtid and set gtid_slave_pos.."
    retry 20 ${mysql} -N -e "STOP SLAVE;"
    retry 20 ${mysql} -N -e "RESET SLAVE ALL;"
    if [ $joining_for_first_time -eq 1 ]; then
      retry 20 ${mysql} -N -e "SET GLOBAL gtid_slave_pos = '$gtid';"
    fi
    if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
        ssl_options=", MASTER_SSL=1, MASTER_SSL_CA='/etc/mysql/certs/server/ca.crt'"
        log "INFO" "Configuring replication with TLS enabled"
    else
        log "INFO" "Configuring replication without TLS"
    fi
    retry 20 ${mysql} -N -e "CHANGE MASTER TO MASTER_HOST='$master', MASTER_USER='repl', MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD' $ssl_options, MASTER_USE_GTID=slave_pos;"
    retry 20 ${mysql} -N -e "START SLAVE;"
    joining_for_first_time=0
    echo "end join to master node by gtid slave_pos"
}

export pid
function start_mysqld_in_background() {
    log "INFO" "Starting MySQL server with docker-entrypoint.sh mysqld $args..."
    process=""
    major=$(echo "$MARIADB_VERSION" | sed -E 's/^1:([0-9]+).*/\1/' | grep -E '^[0-9]+$' || echo "0")

    if [[ "$major" -ge 11 ]]; then
        docker-entrypoint.sh mariadbd $args &
        process="mariadbd"
    else
        docker-entrypoint.sh mysqld $args &
        process="mysqld"
    fi

    pid=$!
    log "INFO" "The process ID of $process is '$pid'"
}

backup_restored=0
if [ -f "/scripts/receive_backup.txt" ]; then
  echo "Waiting for the master to start streaming backup data..."

  # Wait for coordinator to write the master IP. Without this we would
  # accept the first TCP connection from any pod in the cluster, letting
  # a malicious pod overwrite /var/lib/mysql by racing the master.
  MASTER_IP=""
  for i in {60..0}; do
      if [ -s "/scripts/master_ip.txt" ]; then
          MASTER_IP=$(cat /scripts/master_ip.txt)
          break
      fi
      sleep 1
  done
  if [ -z "$MASTER_IP" ]; then
      log "ERROR" "master_ip.txt not provided by coordinator within 60s — refusing to open unauthenticated backup stream listener"
      exit 1
  fi
  log "INFO" "Expecting backup stream from master IP $MASTER_IP only"

  echo "$POD_IP">/scripts/backup_receive_started.txt

  # Bounded retries — the old script looped FOREVER on failure while
  # wiping /var/lib/mysql each time, giving any attacker infinite
  # chances to poison the datadir.
  MAX_BACKUP_STREAM_ATTEMPTS=3
  stream_attempt=0
  stream_success=0
  while [ $stream_attempt -lt $MAX_BACKUP_STREAM_ATTEMPTS ]; do
      stream_attempt=$((stream_attempt + 1))
      log "INFO" "Backup stream attempt $stream_attempt/$MAX_BACKUP_STREAM_ATTEMPTS (bind=$POD_IP, accept only from $MASTER_IP)"

      # Use TCP4-LISTEN / pf=ip4 to force IPv4 address family. Without
      # this, socat defaults to PF_UNSPEC and:
      #   (a) the CIDR form range=X/32 is rejected ("unspecified family")
      #   (b) the ADDR:MASK form is also unusable — socat's option lexer
      #       treats ':' as its own address separator and truncates at it
      #       ("syntax error in 10.244.0.10"). Forcing IPv4 lets us use
      #       the clean /32 CIDR syntax.
      if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
          # TLS + IP allowlist + local bind.
          # verify=1 validates the master's cert chain against our CA.
          # pf=ip4 forces IPv4 for range= parsing.
          socat -u \
              "OPENSSL-LISTEN:3307,pf=ip4,bind=${POD_IP},range=${MASTER_IP}/32,cert=/etc/mysql/certs/server/tls.crt,key=/etc/mysql/certs/server/tls.key,cafile=/etc/mysql/certs/server/ca.crt,verify=1,reuseaddr" \
              STDOUT | mbstream -x -C /var/lib/mysql
      else
          # Plain TCP bound to pod IP + range-limited to master IP.
          # TCP4-LISTEN is the IPv4 variant of TCP-LISTEN.
          socat -u \
              "TCP4-LISTEN:3307,bind=${POD_IP},range=${MASTER_IP}/32,reuseaddr" \
              STDOUT | mbstream -x -C /var/lib/mysql
      fi

      # Check BOTH pipeline members. A plain $? only reports mbstream's
      # exit code — when socat dies (syntax error, cert mismatch, peer
      # rejection), mbstream sees EOF immediately and exits 0 with no
      # work done, silently claiming success on an empty datadir.
      socat_rc=${PIPESTATUS[0]}
      mbstream_rc=${PIPESTATUS[1]}
      if [ "$socat_rc" -ne 0 ] || [ "$mbstream_rc" -ne 0 ]; then
          log "WARNING" "Backup stream pipeline failed (socat=${socat_rc}, mbstream=${mbstream_rc})"
      elif [ ! -s /var/lib/mysql/xtrabackup_checkpoints ] && [ ! -f /var/lib/mysql/ibdata1 ]; then
          # Both commands claimed success but no mariabackup artifacts
          # landed. Treat as failure — prevents pod-0 starting with an
          # empty datadir and silently passing the "restore successful"
          # check. xtrabackup_checkpoints is written by every mariabackup
          # stream; ibdata1 is the primary data file.
          log "WARNING" "Backup stream reported success but datadir lacks mariabackup artifacts — treating as failure"
      else
          log "INFO" "Data restore successful."
          stream_success=1
          break
      fi

      log "WARNING" "Backup stream attempt $stream_attempt failed."

      # /var/lib/mysql is a Kubernetes PVC mount point. We cannot rename
      # or delete the mount point itself (EBUSY / permission), but we do
      # have write access to its contents. Clean contents in place so
      # the next mbstream extraction starts from a clean slate. Record
      # size/file-count first for operator forensics (the actual bytes
      # are gone either way — an attacker's poisoned stream leaves no
      # particularly useful trace, and preserving as a subdirectory
      # inside /var/lib/mysql confuses mariadbd's datadir scan later).
      if [ -d /var/lib/mysql ] && [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
          before_count=$(find /var/lib/mysql -mindepth 1 2>/dev/null | wc -l)
          before_size=$(du -sh /var/lib/mysql 2>/dev/null | awk '{print $1}')
          log "WARNING" "Cleaning failed restore from /var/lib/mysql (${before_count} entries, ${before_size:-unknown})"
          if ! find /var/lib/mysql -mindepth 1 -delete 2>/dev/null; then
              log "ERROR" "Failed to clean /var/lib/mysql contents — cannot retry safely"
              exit 1
          fi
      fi
  done

  if [ $stream_success -ne 1 ]; then
      log "ERROR" "All $MAX_BACKUP_STREAM_ATTEMPTS backup stream attempts failed — aborting (operator intervention required)"
      exit 1
  fi

  mariabackup --prepare --target-dir=/var/lib/mysql
  rm /scripts/backup_receive_started.txt
  backup_restored=1
  rm /scripts/receive_backup.txt
  rm -f /scripts/master_ip.txt
fi

start_mysqld_in_background

if [[ "${REQUIRE_SSL:-}" == "TRUE" ]]; then
  export mysql_header="mariadb -u ${USER} --port=3306 --ssl-ca=/etc/mysql/certs/server/ca.crt  --ssl-cert=/etc/mysql/certs/server/tls.crt --ssl-key=/etc/mysql/certs/server/tls.key"
else
  export mysql_header="mariadb -u ${USER} --port=3306"
fi

export MYSQL_PWD=${PASSWORD}

# wait for mysqld to be ready
wait_for_mysqld_running

# ensure replication user
create_replication_user

# ensure maxscale user
create_maxscale_user

# ensure monitor user
create_monitor_user

#TODO:
# ensure maxscale_confsync user
#create_maxscale_confsync_user

while true; do
    kill -0 $pid
    exit="$?"
    if [[ "$exit" == "0" ]]; then
        echo "mysqld process is running"
    else
        echo "need start mysqld and wait_for_mysqld_running"
        start_mysqld_in_background
        wait_for_mysqld_running
    fi

    # wait for the script copied by coordinator
    while [ ! -f "/scripts/signal.txt" ]; do
        log "WARNING" "signal is not present yet!"
        sleep 1
    done
    desired_func=$(cat /scripts/signal.txt)
    rm -rf /scripts/signal.txt
    log "INFO" "going to execute $desired_func"
    if [[ $desired_func == "create_cluster" ]]; then
        bootstrap_cluster
    fi

    if [[ $desired_func == "join_to_master" ]]; then
      # wait for the script copied by coordinator
      while [ ! -f "/scripts/master.txt" ]; do
          log "WARNING" "master detector file isn't present yet!"
          sleep 1
      done
      master=$(cat /scripts/master.txt)
      rm -rf /scripts/master.txt
      if [[ $backup_restored -eq 0 ]]; then
        join_to_master_by_current_pos
      else
        while [ ! -f "/scripts/gtid.txt" ]; do
            log "WARNING" "gtid detector file isn't present yet!"
            sleep 1
        done
        gtid=$(cat /scripts/gtid.txt)
        echo "master replica's current gtid position is $gtid"
        rm -rf /scripts/gtid.txt
        join_to_master_by_slave_pos
      fi
    fi
    log "INFO" "waiting for mysql process id  = $pid"
    wait $pid
done

