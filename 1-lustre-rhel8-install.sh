#!/bin/bash

# This a shell script implementing Lustre server.
# Basically theprocedure described here, except for 
# current almalinux8

# The Lustre RPM repository version which we are trying to install
lustre=https://downloads.whamcloud.com/public/lustre/lustre-2.15.5/el8.10/

# Lustre Kernel version in the repository
kernel=4.18.0-553.5.1.el8_lustre.x86_64

echo "STEP 1: Configure RPM repositories."

echo "Enabling epel-release repository"
yum -y install epel-release

echo "Enabling HA and powertools repositories repository"
dnf config-manager --set-enabled ha
dnf config-manager --set-enabled powertools

# Set repository configuration in place
echo "Enabling Lustre repository with: /etc/yump.repos.d/lustre.repo"
cat << EOF > /etc/yum.repos.d/lustre-repo.repo
[lustre-server]
name=lustre-server
baseurl=$lustre/server/
# exclude=*debuginfo*
gpgcheck=0

[lustre-client]
name=lustre-client
baseurl=$lustre/client/
# exclude=*debuginfo*
gpgcheck=0
EOF

echo "Disabling selinux:"
cp -v ./selinux-config.txt /etc/selinux/config

echo "Step 2: Installing Lustre kernel $kernel and its headers"
yum install kernel-$kernel kernel-core-$kernel kernel-headers-$kernel kernel-devel-$kernel kernel-debuginfo-common-x86_64

if [ $(uname -r) != $kernel ]; then
  echo "You should boot kernel $kernel now before continuing."
  echo "Remember to disable secure boot!"
  read -p "Reboot y/n ?" ok
  [ "$ok" = "y" ] && reboot
  echo "exiting."
  exit 1
fi

echo "Checking that selinux is disabled:"
selinuxenabled && echo "WARNING: selinux is enabled. If Lustre does not work, check your audit logs."

echo "Step 3: installing ZFS:"
dnf install dkms zfs-dkms zfs

echo "Loading ZFS module"
modprobe zfs

echo "Checking installed zfs version:"
zfs --version || echo "WARNING: zfs installation likely failied."

echo "STEP 4: Install utilities and Lustre ZFS server support module osd-zfs:"
yum install pv tmux nano perftest zfs bison flex libzfs5 libzfs5-devel libmount-devel libnl3-devel patch

echo "Installing Lustre osd-zfs module:"
yum install lustre-zfs-dkms lustre-osd-zfs-mount

echo "Loading osd_zfs module"
if ! modprobe osd_zfs; then
  echo "Could not load osd-zfs module. You should 1. try rebooting 2. check what went wrong with zfs compilation"
  sleep 5
fi

echo "STEP 5: Install Lustre user space utilities."
yum install lustre
modprobe lustre || echo "WARNING: failed to load lustre module."
lfs --version || echo "WARNING: failed to check Lustre version."

echo "STEP 6: Install high availability utilities"
yum install lustre-resource-agents corosync pacemaker pcs

echo "Congratulations, you have installed Whamlinux Lustre kernel and its modules!"
