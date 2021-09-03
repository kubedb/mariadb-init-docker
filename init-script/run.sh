#!/bin/sh

rm -rf /var/lib/mysql/lost+found
rm -rf /run-script/*
rm -rf /scripts/*

cp /tmp/scripts/* /scripts
