=====================
archzfs testing guide
=====================
:Modified: Mon Apr 13 23:08 2015

--------
Overview
--------

* Hosted at archzfs.com

  archzfs.com for the project webpage (webfaction)
  archzfs.com/repo for the repo (webfaction)
  build.archzfs.com for packer/vagrant/droneio (local server)
  deploy.archzfs.com custom webpage for deploying valid builds (local server)

* Bulder hardware Intel NUC 5th Gen Core I5 with 16GB of RAM @ home in DMZ

* drone.archzfs.com is droneio ci for automated building and testing

* Build a base image for vagrant-libvirt using packer

  Use the ansible provisioner to build archzfs from arbitrary git commits and
  pull requests

* Provision a test environment with vagrant

  Regression test suite (http://zfsonlinux.org/zfs-regression-suite.html)

  Test booting into a zfs root filesystem

* deploy.archzfs.com for pushing packages to AUR and the archzfs package repo

  2fa login

  Shows complete list of changes from zfsonlinux git

  Shows all log output from builders and tests

  One button deploy

------------
Requirements
------------

* reflector
* nfs (pacman package cache)

  /var/cache/pacman/pkg   127.0.0.1(rw,async,no_root_squash,no_subtree_check,insecure)

  qemu sends packets from 127.0.0.1:44730 to 127.0.0.1:2049 for mounting.
  The insecure option allows packets from ports > 1024

libvirt
+++++++

.. code:: console

   sudo pacman -Sy virt-manager

libvirt will need a bridged network in order for the containers to reach the
internet. This can easily be done with Network Manager. It can also be done in
the virt-manager interface, but some say this is not reliable.

packer
++++++

.. code:: console

   sudo pacman -Sy go
   mkdir ~/{bin,src}
   export GOPATH=$HOME
   go get -u github.com/mitchellh/gox
   go get github.com/mitchellh/packer
   cd $GOPATH/src/github.com/mitchellh/packer
   make updatedps
   make bin

After the build has completed, the binaries should be in ``~/bin``

----------------------
Build and test process
----------------------

Stage 1
+++++++

1. Build the packages using the normal build process, but without signing.

   Build on local machine and copy the packages to the test environment.

   ccm64 command will need to be run without root priviledges.

#. Use packer to create a test instance with the zfs packages installed

#. Perform regression tests

Stage 2
+++++++

1. Use packer to build zfs root filesystem test instances

   packer configurations for:

   a. zfs single root filesystem

   #. zfs with storage pool as root filesystem

   #. zfs root with legacy mounts

---------------------------------------
Packer/KVM build/test environment setup
---------------------------------------

The goal of this article is to setup a qemu based testing environment for the
archzfs project.

This guide provides details on setting up VM's for multiple zfs usage
scenarios.

-------------
Helpful links
-------------

* http://blog.falconindy.com/articles/build-a-virtual-army.html

--------
Packages
--------

1. qemu

#. bridge-utils

#. libvirt

----------
Qemu Setup
----------

1. Check kvm compatibility

.. code:: bash

   $ lscpu | grep Virtualization

#. Load kernel modules

.. code:: bash

   # modprobe -a kvm tun virtio

#. Install qemu

.. code:: bash

   # pacman -Sy qemu

---------------
VDE2 networking
---------------

1. Make sure the logged in user is in the "kvm" group.

.. code:: bash

   $ groups

#. Create /etc/systemd/system/vde2@.service

https://wiki.archlinux.org/index.php/Systemd/Services#VDE2_interface

.. code:: ini

   [Unit]
   Description=Network Connectivity for %i
   Wants=network.target
   Before=network.target

   [Service]
   Type=oneshot
   RemainAfterExit=yes
   ExecStart=/usr/bin/vde_switch -tap %i -daemon -mod 660 -group kvm
   ExecStart=/usr/bin/ip link set dev %i up
   ExecStop=/usr/bin/ip addr flush dev %i
   ExecStop=/usr/bin/ip link set dev %i down

   [Install]
   WantedBy=multi-user.target

#. Enable the vde2 service

.. code:: bash

   # systemctl enable vde2@tun0
   # systemctl start vde2@tun0

#. Setup the eno1 interface

.. code:: bash

   # vim /etc/netctl/ethernet-noip

   Description='A more versatile static Ethernet connection'
   Interface=eno1
   Connection=ethernet
   IP=no

#. Start the eno1 interface

.. code:: bash

   # netctl enable ethernet-noip
   # netctl start ethernet-noip

#. Setup the bridge with netctl

https://wiki.archlinux.org/index.php/Bridge_with_netctl

.. code:: bash

   # vim /etc/netctl/bridge

   Description="Example Bridge connection"
   Interface=br0
   Connection=bridge
   BindsToInterfaces=(eno1 tap0)
   IP=dhcp
   ## Ignore (R)STP and immediately activate the bridge
   #SkipForwardingDelay=yes

#. Enable and start the bridge

.. code:: bash

   # netctl enable bridge
   # netctl start bridge

.. --------------------
.. Embed ZFS in archiso
.. --------------------

.. 1. Install archiso

.. .. code:: bash

   .. # pacman -Sy archiso

.. #. Copy archiso scripts

.. .. code:: bash

   .. $ mkdir archiso
   .. $ cp -r /usr/share/archiso/configs/releng archiso

.. #. Edit packages.both

.. .. code:: bash

   .. $ vim archiso/releng/archiso

   .. zfs-git
   .. zfs-utils-git
   .. spl-git
   .. spl-utils-git
   .. vim

.. #. Edit archiso/releng/pacman.conf

.. .. code:: bash

   .. $ vim archiso/releng/pacman.conf

   .. [demz-repo-core]
   .. SigLevel = Required
   .. Server = file:///data/pacman/repo/$repo/$arch

.. #. Build the iso

.. .. code:: bash

    .. # ./build.sh -v

.. ---------------
.. Qemu disk image
.. ---------------

.. 1. Create a disk image

.. .. code:: bash

   .. $ qemu-img create -f qcow2 zfs_test.qcow2 5G

.. #. Activate the VM using the archiso

.. .. code:: bash

   .. qemu-system-x86_64 -enable-kvm -m 1024 -smp 2 -net nic,model=virtio -net vde -drive file=zfs_test.qcow2,if=virtio -cdrom /path/to/livecd.iso -boot order=d

.. -----------
.. Install ZFS
.. -----------

.. 1. Mount package cache

   .. nfs share of /var/cache/pacman

.. .. code:: bash

   .. mount -t nfs4 -o wsize=8192,rsize=8192,timeo=14 lithium:/var/cache/pacman/pkg /var/cache/pacman/pkg

.. 1. Install Arch Linux OS

.. .. code:: bash

   .. a. pacman -Sy vim
   .. #. pacman-key -r 0EE7A126
   .. #. pacman-key --lsign-key 0EE7A126
   .. #. Add demz-repo-archiso to pacman.conf
   .. #. pacman -S zfs

.. Mount an existing zfs pool
.. --------------------------

.. .. code:: bash

   .. # mkdir /mnt/root
   .. # zpool -R /mnt/root -a -f

.. Legacy mount points
.. ~~~~~~~~~~~~~~~~~~~

.. To see available mount points:

.. .. code:: bash

   .. zfs list

.. .. image:: images/qemu_zfs_list.png

.. .. code:: bash

   .. # mount -t zfs zroot/var var
   .. # mount -t zfs zroot/var/empty var/empty
   .. # mount -t zfs zroot/var/log var/log
   .. # mount -t zfs zroot/usr usr
   .. # mount -t zfs zroot/usr/include usr/include

.. .. image:: images/qemu_zfs_mounts.png

.. Create the zpool
.. ----------------

.. .. code:: bash

   .. # cfdisk /dev/vda

.. First partition is 500mb ext4.

.. Second partition is of the "Solaris" type and should be sized to the end of the disk.

.. .. code:: bash

   .. # mkfs.ext4 /dev/vda1

.. #. Create the root pool

   .. For some reason there are no ids in /dev/disk/by-id. I'm not sure how to fix
   .. that yet. Its probably a bug in the udev version contained in the archiso.

.. .. code:: bash

   .. # zpool create zroot /dev/vda2

.. #. Create the zpool datasets

.. .. code:: bash

   .. # zfs create zroot/home
   .. # zfs create zroot/etc
   .. # zfs create zroot/usr
   .. # zfs create zroot/usr/include
   .. # zfs create zroot/var
   .. # zfs create zroot/var/empty
   .. # zfs create zroot/var/log
   .. # zfs create -V 1G -b 4K zroot/swap

.. #. Activate the swap space

.. .. code:: bash

   .. # mkswap /dev/zvol/zroot/swap
   .. # swapon /dev/zvol/zroot/swap

.. #. Set various settings

.. .. code:: bash

   .. # zfs set mountpoint=/ zroot
   .. # zfs set mountpoint=legacy zroot/usr
   .. # zfs set mountpoint=legacy zroot/usr/include
   .. # zfs set mountpoint=legacy zroot/var
   .. # zfs set mountpoint=legacy zroot/var/empty
   .. # zfs set mountpoint=legacy zroot/var/log
   .. # zpool set bootfs=zroot zroot

.. #. Export zroot and reimport

.. .. code:: bash

   .. # swapoff /dev/zvol/zroot/swap
   .. # zpool export zroot
   .. # zpool import -R /mnt zroot

.. #. Copy zpool cache

.. .. code:: bash

   .. # zpool set cachefile=/etc/zfs/zpool.cache zroot
   .. # cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache

.. #. Mount partitions

.. .. code:: bash

   .. # cd /mnt
   .. # mkdir boot
   .. # mount /dev/vda1 boot
   .. # mount -t zfs zroot/var var
   .. # mkdir var/{log,empty}
   .. # mount -t zfs zroot/var/empty var/empty
   .. # mount -t zfs zroot/var/log var/log
   .. # mount -t zfs zroot/usr usr
   .. # mount -t zfs zroot/usr/include usr/include

.. ---------------------------
.. Existing Arch Linux Install
.. ---------------------------

.. .. code:: bash

   .. # arch-chroot /mnt/root /bin/bash

.. -----------------------
.. Mount archzfs nfs share
.. -----------------------

.. This requires the archzfs project directory to be shared via nfs.

.. .. code:: bash

   .. # vim /etc/fstab

.. Add:

.. .. code:: bash

   .. # lithium:/home/demizer/projects/arch/archzfs /archzfs rsize=8192,wsize=8192,timeo=14,_netdev 0 0

.. .. image:: qemu_fstab_mounts.png

.. ------------------
.. Install Arch Linux
.. ------------------

.. .. code:: bash

   .. # pacstrap /mnt base sudo vim openssh
   .. # genfstab -U -p /mnt >> /mnt/etc/fstab
   .. # arch-chroot /mnt /bin/bash
   .. # echo 'zfstest001' > /etc/hostname
   .. # Edit /etc/locale.gen and run "locale-gen"
   .. # ln -s /usr/share/zoneinfo/America/Los_Angeles /etc/localtime

.. #. Add demz-repo-core to /etc/pacman.conf and install zfs-git.

.. #. Edit /etc/fstab adding legacy ZFS mounts.

.. .. image:: qemu_fstab_mounts.png

.. #. Install the boot loader

.. .. code:: bash

   .. # pacman -S grub
   .. # grub-install --target=i386-pc --recheck /dev/vda
   .. # grub-mkconfig -o /boot/grub/grub.cfg
   .. # Edit grub.cfg changing root=UUID* to zfs=zroot on both menuentries.

.. #. Reboot into the new VM

.. .. code:: bash

   .. # qemu-system-x86_64 -m 1024 -smp 2 -enable-kvm -net nic -net vde -drive file=zfs_test.qcow2,if=virtio -boot d

.. --------------------
.. Regenerate initramfs
.. --------------------

.. .. images:: qemu_regensh.png

.. .. code:: bash

   .. # ./regen.sh
