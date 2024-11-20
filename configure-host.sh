#!/bin/bash

git pull
host=lustre-demo-$1
echo "Configuring this host as $host"
hostnamectl set-hostname $host
cp -v etc-issue /etc/issue
rm /root/.bash_history

