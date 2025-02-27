#!/usr/bin/env bash

export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
mariadb-admin -u "$MYSQL_ROOT_USERNAME" shutdown
