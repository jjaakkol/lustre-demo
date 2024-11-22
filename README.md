This repository contains scripts and instructions for installing a VM and
virtual disks to test different Lustre setups under libvirt and Qemu.

The id_rsa secret key is here on purpose. You use it to login as root to
the virtual machines. Do not expose these virtual machines to the public
Internet, anymore than you would expose your Lustre servers.

virsh net-dhcp-leases default

