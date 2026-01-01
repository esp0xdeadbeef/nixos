IN the following test, a test-copy.qcow was created, rsynced to the server, and afterwards edited one byte and rsynced again, which was fast:

```bash
┌─[deadbeef@s-sigma] - [/mnt/nas/private/testing] - [do jan 01, 09:48]
└─[$]> qemu-img create -f qcow2 -o preallocation=full /tmp/test-copy.qcow 1G

Formatting '/tmp/test-copy.qcow', fmt=qcow2 cluster_size=65536 extended_l2=off preallocation=full compression_type=zlib size=1073741824 lazy_refcounts=off refcount_bits=16
┌─[deadbeef@s-sigma] - [/mnt/nas/private/testing] - [do jan 01, 09:48]
└─[$]> ls -lh /tmp/test-copy.qcow
du -h /tmp/test-copy.qcow

-rwxr-xr-x 1 deadbeef users 1,1G  1 jan 09:48 /tmp/test-copy.qcow
1,1G	/tmp/test-copy.qcow
┌─[deadbeef@s-sigma] - [/mnt/nas/private/testing] - [do jan 01, 09:48]
└─[$]> rsync -av --inplace --no-whole-file /tmp/test-copy.qcow /mnt/nas/private/testing/test-copy.qcow

sending incremental file list
test-copy.qcow

sent 1.074.397.391 bytes  received 35 bytes  69.315.962,97 bytes/sec
total size is 1.074.135.040  speedup is 1,00
┌─[deadbeef@s-sigma] - [/mnt/nas/private/testing] - [do jan 01, 09:49]
└─[$]> printf '\x42' | dd of=/tmp/test-copy.qcow bs=1 seek=$((512*1024*1024)) conv=notrunc

1+0 records in
1+0 records out
1 byte copied, 5,0319e-05 s, 19,9 kB/s
┌─[deadbeef@s-sigma] - [/mnt/nas/private/testing] - [do jan 01, 09:49]
└─[$]> rsync -av --inplace --no-whole-file /tmp/test-copy.qcow /mnt/nas/private/testing/test-copy.qcow

sending incremental file list
test-copy.qcow

sent 164.011 bytes  received 229.507 bytes  10.221,25 bytes/sec
total size is 1.074.135.040  speedup is 2.729,57
```
