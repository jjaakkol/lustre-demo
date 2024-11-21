#!/bin/bash

guest=$1

if [ -z "$host" ]; then
  echo "$0 needs guest hostname to configure it"
  exit 1
fi

echo "Configuring guest $(uname -r) as $guest"
hostnamectl set-hostname $guest
cp -v etc-issue /etc/issue
cp -va known_hosts /etc/ssh/ssh_known_hosts
rm /root/.bash_history

