This repository contains scripts and instructions for installing a VM and
virtual disks to test Lustre under libvirt and Qemu.

The id_rsa secret key is here on purpose. You use it to login as root to
the virtual machines. Do not expose these virtual machines to the public
Internet, anymore than you would expose your Lustre servers.

When you have started all the VMs you can check that they have requested a IP address from the DHCP server at lustre-demo virtual network:


```
$ virsh net-dhcp-leases lustre-demo
 Expiry Time           MAC address         Protocol   IP address          Hostname             Client ID or DUID
---------------------------------------------------------------------------------------------------------------------
 2024-11-25 09:50:07   52:54:00:0e:8d:29   ipv4       192.168.234.20/24   lustre-demo-oss0     01:52:54:00:0e:8d:29
 2024-11-25 09:56:24   52:54:00:85:f0:ae   ipv4       192.168.234.21/24   lustre-demo-oss1     01:52:54:00:85:f0:ae
 2024-11-25 09:47:58   52:54:00:a7:29:6c   ipv4       192.168.234.10/24   lustre-demo-mds0     01:52:54:00:a7:29:6c
 2024-11-25 09:57:32   52:54:00:e5:b1:6a   ipv4       192.168.234.11/24   lustre-demo-mds1     01:52:54:00:e5:b1:6a
 2024-11-25 09:42:17   52:54:00:f9:c2:18   ipv4       192.168.234.2/24    lustre-demo-client   01:52:54:00:f9:c2:18
```

Now you should be able to ssh into the VM guests with the provided `id_rsa` ssh key:

```
$ ssh -i ./id_rsa root@192.168.234.10
* jani.jaakkola@helsinki.fi Almalinux 8 with Lustre installed.


Last login: Mon Nov 25 02:06:14 2024 from 192.168.234.1
[root@lustre-demo-mds0 ~]# 
```

You are now free to play around in the vm. Use command `lshw` list all virtual devices in the VM.

Lustre servers need a hole in the firewall. This commands adds a rule to allow TCP connections to Lustre port is 988 from `lustre-demo`virtual network:

```
[root@lustre-demo-mds0 ~]# systemctl start firewalld
[root@lustre-demo-mds0 ~]# firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.234.0/24" port port="988" protocol="tcp" accept' --permanent
success
[root@lustre-demo-mds0 ~]#
```

Check that the network and Lustre Lnet works in the designated client VM:

```
[root@lustre-demo-client ~]# lnetctl net show
net:
    - net type: lo
      local NI(s):
        - nid: 0@lo
          status: up
    - net type: tcp
      local NI(s):
        - nid: 192.168.234.2@tcp
          status: up
[root@lustre-demo-client ~]# lnetctl ping 192.168.234.10@tcp
ping:
    - primary nid: 192.168.234.10@tcp
      Multi-Rail: True
      peer ni:
        - nid: 192.168.234.10@tcp
[root@lustre-demo-client ~]# 
```

You should check that `lnetctl ping` works to all Lustre VMs.

Here is a list of all VMs and their IPs and Lnet nids in the default VM installation:

| VM   | IP            | NID                | Description               |
|------|---------------|--------------------|---------------------------|
| lustre-demo-mds0  | 192.168.234.10  | 192.168.234.10@tcp  | Metadata server mds0 and MGS  |
| lustre-demo-mds1  | 192.168.234.11  | 192.168.234.11@tcp  | Metadata server mds1 |
| lustre-demo-oss0  | 192.168.234.20  | 192.168.234.20@tcp  | Payload data server oss0         |
| lustre-demo-oss1  | 192.168.234.21  | 192.168.234.21@tcp  | Payload data server oss1  |
| lustre-demo-client| 192.168.234.2   | 192.168.234.2@tcp   | Lustre client VM   |


You can also now check the hardware of the VM and play with the virtual disks. You list the disks and their metadata with commands `blkid` or `lsblk`.

There is 6 "SSD" shared virtual disks with 50MB/s max throughput shared between `lustre-demo-mds0` and `lustre-demo-mds1` nodes and 6 "HDD" shared virtual disks with 25MB/s max throughput shared between `lustre-demo-oss0' and 'lustre-demo-oss1'. 

Throughput and IOPS of the virtual disks is intentionally very low to be better able to demonstrate how Lustre achieves performance by distribution IO over multiple disks and hosts. The MDS disks have max throughput of 50MB/s by default:

```
[root@lustre-demo-mds0 ~]# pv -s 1G -S /dev/vdc > /dev/null
1.00GiB 0:00:20 [50.2MiB/s] [======================================================================>] 100%            
```

Create raidz1 zpools for our two Lustre metadata servers (MDS). The zpool property `multihost=on` enables safe zpool sharing between multiple hosts. The zpool property `cachefile=none`turns off automatical zpool import on host restart.

```
modprobe zfs
zpool create MDT0 -o multihost=on -o cachefile=none raidz1 /dev/vdb /dev/vdc /dev/vdd
zpool create MDT1 -o multihost=on -o cachefile=none raidz1 /dev/vde /dev/vdf /dev/vdg
```

Since the created zpool has three disks, where one disk is used for parity data, it has twice the throughput of a single disk. Lets test this with creating a new ZFS dataset `test` and writing to it. We need to write enough data (8G) to fill the ARC, otherwise we just measure write cache speed. 

```
[root@lustre-demo-mds0 ~]# zfs create MDT0/test -o recordsize=1M
[root@lustre-demo-mds0 ~]# openssl aes256 -pass pass:foo < /dev/zero | pv -s 8G -S > /MDT0/test/testfile 
*** WARNING : deprecated key derivation used.
Using -iter or -pbkdf2 would be better.
8.00GiB 0:01:24 [96.9MiB/s] [==========================================================>] 100%            
error writing output file
[root@lustre-demo-mds0 ~]#
```


Format Lustre Management Target (MGT) and Lustre metadata target MDT0 and second metadata target MDT1 on the `lustre-demo-mds0` node:

```
mkfs.lustre --mgs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp --backfstype=zfs MDT0/MGT
mkfs.lustre --mdt --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=0 --backfstype=zfs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp MDT0/MDT0
mkfs.lustre --mdt --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=1 --backfstype=zfs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp MDT1/MDT1
```

Now we have 3 new ZFS datasets, one for each created Lustre target:

```
[root@lustre-demo-mds0 ~]# zfs list
NAME        USED  AVAIL     REFER  MOUNTPOINT
MDT0       8.00G  40.1G     30.6K  /MDT0
MDT0/MDT0  3.70M  40.1G     3.70M  /MDT0/MDT0
MDT0/MGT   3.30M  40.1G     3.30M  /MDT0/MGT
MDT0/test  7.99G  40.1G     7.99G  /MDT0/test
MDT1       3.80M  48.1G     30.6K  /MDT1
MDT1/MDT1  3.52M  48.1G     3.52M  /MDT1/MDT1
[root@lustre-demo-mds0 ~]# 
```

The Lustre metadata service is started by mounting the newly created Lustre target filesystems:

```
mkdir -p /mnt/MGT /mnt/MDT0 /mnt/MDT1
mount MDT0/MGT /mnt/MGT -t lustre
mount MDT1/MDT1 /mnt/MDT1 -t lustre
mount MDT0/MDT0 /mnt/MDT0 -t lustre
```


Now ssh to the lustre-demo-oss0 Lustre payload data server (Object Storage Server OSS) and create Lustre OST target datasets:

```
modprobe zfs
zpool create OST0 -o multihost=on -o cachefile=none raidz1 /dev/vdb /dev/vdc /dev/vdd
zpool create OST1 -o multihost=on -o cachefile=none raidz1 /dev/vde /dev/vdf /dev/vdg
mkfs.lustre --ost --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=0 --backfstype=zfs --servicenode=192.168.234.20@tcp --servicenode=192.168.234.21@tcp OST0/OST0
mkfs.lustre --ost --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=1 --backfstype=zfs --servicenode=192.168.234.20@tcp --servicenode=192.168.234.21@tcp OST1/OST1
```
The OST virtual disks are intentionally slower (10MB/s) than MDS virtual disks:
```
[root@lustre-demo-oss0 test]# openssl aes256 -pass pass:foo < /dev/zero | pv -s 4G -S > testfile
*** WARNING : deprecated key derivation used.
Using -iter or -pbkdf2 would be better.
4.00GiB 0:03:05 [22.0MiB/s] [===================================================>] 100%            
error writing output file
[root@lustre-demo-oss0 test]# 
```
Now start the object storage service by mounting the newly create object storage targets (OSTs):

```
mkdir -p /mnt/OST0 /mnt/OST1
mount -t lustre OST0/OST0 /mnt/OST0
mount -t lustre OST1/OST1 /mnt/OST1
```

At this point the Lustre servers are running and we are ready to mount the Lustre filesystem to our client. Now ssh to the lustre-demo-client and mount the newly created Lustre filesystem:

```
mkdir -p demo /mnt/demo
mount -t lustre 192.168.234.10@tcp:192.168.234.11@tcp:/demo /mnt/demo
```

Now chech that all the Lustre server nodes are visible to the client:

```
[root@lustre-demo-client ~]# lfs df
UUID                   1K-blocks        Used   Available Use% Mounted on
demo-MDT0000_UUID       41699840        3840    41693952   1% /mnt/demo[MDT:0]
demo-MDT0001_UUID       50019328        3584    50013696   1% /mnt/demo[MDT:1]
demo-OST0000_UUID       98706432     5615616    93088768   6% /mnt/demo[OST:0]
demo-OST0001_UUID      100038656     3591168    96445440   4% /mnt/demo[OST:1]

filesystem_summary:    198745088     9206784   189534208   5% /mnt/demo

[root@lustre-demo-client ~]# 
```

Now we can test the throughput of our Lustre system. In the default configuration you should get only 20MB/s, since we are only writing `testfile` to one of our two OST targets. Command 'lfs getstripe' gets the stripe layout of the generated file:

```
[root@lustre-demo-client demo]# openssl aes256 -pass pass:foo < /dev/zero | pv -s 4G -S > testfile
*** WARNING : deprecated key derivation used.
Using -iter or -pbkdf2 would be better.
4.00GiB 0:02:39 [25.6MiB/s] [===================================================>] 100%            
error writing output file
[root@lustre-demo-client demo]# lfs getstripe testfile
testfile
lmm_stripe_count:  1
lmm_stripe_size:   1048576
lmm_pattern:       raid0
lmm_layout_gen:    0
lmm_stripe_offset: 0
	obdidx		 objid		 objid		 group
	     0	             2	          0x2	             0

[root@lustre-demo-client demo]# 
```

Now create a directory where files are striped to all available OSTs by default:

```
[root@lustre-demo-client stripeddir]# openssl aes256 -pass pass:foo < /dev/zero | pv -s 4G -S > testfile
*** WARNING : deprecated key derivation used.
Using -iter or -pbkdf2 would be better.
4.00GiB 0:00:57 [71.3MiB/s] [===============================================================================>] 100%            
error writing output file
[root@lustre-demo-client stripeddir]# 
```

The same test run twice as fast, because we were using also the second storage target. Lustre throughput can scale linearly with the number of storage targets! Note that Lustre IO isn't synchronous. The actual max throughput is 60MB/s. The last bits were just left in write cache. 

Lets test Lustre metadata performance with a very simple shell script `simple-metadata-test`:

```
[root@lustre-demo-client demo]# cd /mnt/demo/
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 37 seconds.
[root@lustre-demo-client demo]# 
```

Configure Lustre to save small files to MDT insteast of slow OST:

```
[root@lustre-demo-client demo]# lfs setstripe -E 64k --layout mdt -E eof --stripe-count -1  --stripe-size=1M testdir1 testdir2
[root@lustre-demo-client demo]# lfs getstripe testdir1
testdir1
  lcm_layout_gen:    0
  lcm_mirror_count:  1
  lcm_entry_count:   2
    lcme_id:             N/A
    lcme_mirror_id:      N/A
    lcme_flags:          0
    lcme_extent.e_start: 0
    lcme_extent.e_end:   65536
      stripe_count:  0       stripe_size:   65536       pattern:       mdt       stripe_offset: -1

    lcme_id:             N/A
    lcme_mirror_id:      N/A
    lcme_flags:          0
    lcme_extent.e_start: 65536
    lcme_extent.e_end:   EOF
      stripe_count:  -1       stripe_size:   1048576       pattern:       raid0       stripe_offset: -1

[root@lustre-demo-client demo]# 
```

Now run the metadata test again with Data-on-MDT (DOM):
```
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 36 seconds.
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 30 seconds.
[root@lustre-demo-client demo]# 
```

One more thing to test. Configure all IO to testdir1 to go to MDT0 and all IO to destdir2 to go to MDT1:

```
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 0 testdir1
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 1 testdir2
[root@lustre-demo-client demo]# lfs getdirstripe -D testdir1 testdir2
lmv_stripe_count: 0 lmv_stripe_offset: 0 lmv_hash_type: none lmv_max_inherit: 3
lmv_stripe_count: 0 lmv_stripe_offset: 1 lmv_hash_type: none lmv_max_inherit: 3
[root@lustre-demo-client demo]# 
```

Now run the test. The second metadata test takes only 0 seconds! Can you explain what happens here?

```
[root@lustre-demo-client demo]# lfs getdirstripe testdir1 testdir2
lmv_stripe_count: 0 lmv_stripe_offset: 1 lmv_hash_type: none
lmv_stripe_count: 0 lmv_stripe_offset: 0 lmv_hash_type: none
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 0 testdir1
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 1 testdir2
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 72 seconds.
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 1 testdir1
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 0 testdir2
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 0 seconds.
[root@lustre-demo-client demo]# 
```

Lets create and mount a new MDT3:

```
[root@lustre-demo-mds0 ~]# mkfs.lustre --mdt --fsname=demo --mgsnode 192.168.234.10@tcp:192.168.234.11@tcp --index=2 --backfstype=zfs --servicenode=192.168.234.10@tcp --servicenode=192.168.234.11@tcp  MDT0/MDT2

   Permanent disk data:
Target:     demo:MDT0002
Index:      2
Lustre FS:  demo
Mount type: zfs
Flags:      0x1061
              (MDT first_time update no_primnode )
Persistent mount opts: 
Parameters: mgsnode=192.168.234.10@tcp:192.168.234.11@tcp  failover.node=192.168.234.10@tcp:192.168.234.11@tcp
checking for existing Lustre data: not found
mkfs_cmd = zfs create -o canmount=off  MDT0/MDT2
  xattr=sa
  dnodesize=auto
Writing MDT0/MDT2 properties
  lustre:mgsnode=192.168.234.10@tcp:192.168.234.11@tcp
  lustre:failover.node=192.168.234.10@tcp:192.168.234.11@tcp
  lustre:version=1
  lustre:flags=4193
  lustre:index=2
  lustre:fsname=demo
  lustre:svname=demo:MDT0002
[root@lustre-demo-mds0 ~]# mkdir /mnt/MDT2
[root@lustre-demo-mds0 ~]# mount -t lustre MDT0/MDT2 /mnt/MDT2
```

It will immediately be visible in the client:

```
[root@lustre-demo-client ~]# lfs df
UUID                   1K-blocks        Used   Available Use% Mounted on
demo-MDT0000_UUID       41694848        6272    41686528   1% /mnt/demo[MDT:0]
demo-MDT0001_UUID       50018176        6272    50009856   1% /mnt/demo[MDT:1]
demo-MDT0002_UUID       41692160        3584    41686528   1% /mnt/demo[MDT:2]
demo-OST0000_UUID       95880192     6290432    89587712   7% /mnt/demo[OST:0]
demo-OST0001_UUID      100038656     2100224    97936384   3% /mnt/demo[OST:1]

filesystem_summary:    195918848     8390656   187524096   5% /mnt/demo
```

It seems Lustre works much faster, when directories are created to the same MDT where parent directory is:

```
[root@lustre-demo-client demo]# lfs getdirstripe testdir1 testdir2
lmv_stripe_count: 0 lmv_stripe_offset: 1 lmv_hash_type: none
lmv_stripe_count: 0 lmv_stripe_offset: 2 lmv_hash_type: none
[root@lustre-demo-client demo]# lfs getdirstripe -D testdir1 testdir2
lmv_stripe_count: 0 lmv_stripe_offset: 1 lmv_hash_type: none lmv_max_inherit: 3
lmv_stripe_count: 0 lmv_stripe_offset: 2 lmv_hash_type: none lmv_max_inherit: 3
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 2 seconds.
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 2 testdir1
[root@lustre-demo-client demo]# lfs setdirstripe -D --mdt-index 1 testdir2
[root@lustre-demo-client demo]# /root/lustre-demo/simple-metadata-test 
Creating 50 files and directories in 2 threads in directories: testdir1 testdir2
....................................................................................................
Removing created files and directories in 2 threads:
done. Time elapset 77 seconds.
[root@lustre-demo-client demo]# 
```

More things to test:

- Create more users
- Check Lustre quotas
- Swap Lustre to another server
- Install High Availability server

