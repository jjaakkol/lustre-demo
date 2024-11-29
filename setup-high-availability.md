## Setting up HA cluster

### set cluster user passwd
```
passwd hacluster
```
### Create the cluster and start it

```
pcs cluster setup lustre-demo-mds --start lustre-demo-mds0 lustre-demo-mds1
```

### Disable stonith for now

```
pcs property set stonith-enabled=false
```

### Create zpool resources to manage zpools 

```
pcs resource create zpool-MDT1 ZFS pool=MDT1 --group mds1
```

### Create Lustre resources to bring up lustre services

```
pcs resource create lustre-MGT ocf:lustre:Lustre target=MDT0/MGT mountpoint=/mnt/MGT --group=mds0 --before lustre-MDT0
```

### Set up location constrainsts

```
pcs constraint location mds1 prefers lustre-demo-mds1
```

### Configure stonith fencing
yum install fence-agents-virsh
pcs stonith create fence-virsh fence_virsh pcmk_host_list=lustre-demo-mds1  plug=lustre-demo-mds1 ip="192.168.234.1" username=jjaakkol identity_file=/root/.ssh/id_rsa ssh_options='-t "LIBVIRT_DEFAULT_URI=qemu:///system PS1=[EXPECT]#\  /bin/bash --norc --noprofile"'

### Test your cluster status

```
[root@lustre-demo-mds0 lustre-demo]# pcs status
Cluster name: lustre-demo-mds
Cluster Summary:
  * Stack: corosync (Pacemaker is running)
  * Current DC: lustre-demo-mds0 (version 2.1.7-5.2.el8_10-0f7f88312) - partition with quorum
  * Last updated: Fri Nov 29 03:30:04 2024 on lustre-demo-mds0
  * Last change:  Thu Nov 28 09:49:24 2024 by root via root on lustre-demo-mds0
  * 2 nodes configured
  * 7 resource instances configured

Node List:
  * Online: [ lustre-demo-mds0 lustre-demo-mds1 ]

Full List of Resources:
  * Resource Group: mds0:
    * zpool-MDT0	(ocf::heartbeat:ZFS):	 Started lustre-demo-mds0
    * lustre-MGT	(ocf::lustre:Lustre):	 Started lustre-demo-mds0
    * lustre-MDT0	(ocf::lustre:Lustre):	 Started lustre-demo-mds0
  * Resource Group: mds1:
    * zpool-MDT1	(ocf::heartbeat:ZFS):	 Started lustre-demo-mds1
    * lustre-MDT1	(ocf::lustre:Lustre):	 Started lustre-demo-mds1
  * fence-virsh	(stonith:fence_virsh):	 Started lustre-demo-mds1
  * fence-virsh-mds0	(stonith:fence_virsh):	 Started lustre-demo-mds0

Daemon Status:
  corosync: active/enabled
  pacemaker: active/enabled
  pcsd: active/enabled
```

### Kill a node stonith fence

```
pcs stonith fence lustre-demo-mds1
```

