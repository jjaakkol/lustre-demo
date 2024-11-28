#!/bin/bash

guest=$1

if [ -z "$guest" ]; then
  echo "$0 needs guest hostname to configure it"
  exit 1
fi

hostnamectl set-hostname $guest
cp etc-issue /etc/issue
cp -a known_hosts /etc/ssh/ssh_known_hosts
rm /etc/machine-id
systemd-machine-id-setup
genhostid 2>/dev/null
cp heartbeat-agent-ZFS /usr/lib/ocf/resource.d/lustre/
#rm -f /root/.bash_history
echo "Configured guest $guest"
