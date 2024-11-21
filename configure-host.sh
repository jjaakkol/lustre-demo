#!/bin/bash

git pull
host=lustre-demo-$1
echo "Configuring this host as $host"
hostnamectl set-hostname $host
cp -v etc-issue /etc/issue
cp -va known_hosts /etc/ssh/ssh_known_hosts
rm /root/.bash_history

