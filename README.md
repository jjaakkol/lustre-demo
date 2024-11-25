This repository contains scripts and instructions for installing a VM and
virtual disks to test different Lustre setups under libvirt and Qemu.

The id_rsa secret key is here on purpose. You use it to login as root to
the virtual machines. Do not expose these virtual machines to the public
Internet, anymore than you would expose your Lustre servers.

virsh net-dhcp-leases lustre-demo


zpool create MDT0 -o multihost=on raidz1 /dev/vdb /dev/vdc /dev/vdd
zpool create MDT1 -o multihost=on raidz1 /dev/vde /dev/vdf /dev/vdg
zpool create MDT0 -o multihost=on -o cachefile=none raidz1 /dev/vdb /dev/vdc /dev/vdd
zpool create MDT1 -o multihost=on -o cachefile=none raidz1 /dev/vde /dev/vdf /dev/vdg

modprobe lnet
modprobe lustre
systemctl stop firewalld
lnetctl net show
lnetctl net ping 

mkfs.lustre --mgs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp --backfstype=zfs MDT0/MGT
mkfs.lustre --mdt --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=0 --backfstype=zfs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp MDT0/MDT0
mkfs.lustre --mdt --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=1 --backfstype=zfs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp MDT1/MDT1

mkdir -p /mnt/MGT /mnt/MDT0 /mnt/MDT1

mount MDT0/MGT /mnt/MGT -t lustre
mount MDT1/MDT1 /mnt/MDT1 -t lustre
mount MDT0/MDT0 /mnt/MDT0 -t lustre

dmesg
modprobe zfs
zpool create OST0 -o multihost=on -o cachefile=none raidz1 /dev/vdb /dev/vdc /dev/vdd
zpool create OST1 -o multihost=on -o cachefile=none raidz1 /dev/vde /dev/vdf /dev/vdg
mkfs.lustre --ost --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=1 --backfstype=zfs --servicenode=192.168.234.20@tcp --servicenode=192.168.234.21@tcp OST0/OST0
mkfs.lustre --ost --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=0 --backfstype=zfs --servicenode=192.168.234.20@tcp --servicenode=192.168.234.21@tcp OST0/OST0
mkdir -p /mnt/OST0 /mnt/OST1
mkfs.lustre --ost --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=1 --backfstype=zfs --servicenode=192.168.234.20@tcp --servicenode=192.168.234.21@tcp OST1/OST1
mount -t lustre OST1/OST1 /mnt/OST1
lnetctl ping 192.168.234.11@tcp
mkdir -p demo /mnt/demo
mount -t lustre 192.168.234.10@tcp:192.168.234.11@tcp:/demo /mnt/demo
lfs setstripe -c -1 testdir
lfs getstripe testfile
