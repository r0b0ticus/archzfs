#!/usr/bin/env bash

DISK='/dev/vda'
FQDN='test.archzfs.test'
KEYMAP='us'
LANGUAGE='en_US.UTF-8'
PASSWORD=$(/usr/bin/openssl passwd -crypt 'azfstest')
TIMEZONE='UTC'

CONFIG_SCRIPT='/usr/local/bin/arch-config.sh'
ROOT_PARTITION="${DISK}1"
TARGET_DIR='/mnt'

# Additional packages to install after base and base-devel
PACKAGES="ksh gptfdisk openssh syslinux parted lsscsi rsync vim git tmux htop tree python26"

echo "==> clearing partition table on ${DISK}"
/usr/bin/sgdisk --zap ${DISK}

echo "==> destroying magic strings and signatures on ${DISK}"
/usr/bin/dd if=/dev/zero of=${DISK} bs=512 count=2048
/usr/bin/wipefs --all ${DISK}

echo "==> creating /root partition on ${DISK}"
/usr/bin/sgdisk --new=1:0:0 ${DISK}

echo "==> setting ${DISK} bootable"
/usr/bin/sgdisk ${DISK} --attributes=1:set:2

echo '==> creating /root filesystem (ext4)'
/usr/bin/mkfs.ext4 -F -m 0 -q -L root ${ROOT_PARTITION}

echo "==> mounting ${ROOT_PARTITION} to ${TARGET_DIR}"
/usr/bin/mount -o noatime,errors=remount-ro ${ROOT_PARTITION} ${TARGET_DIR}

echo "==> create NFS mount points"
/usr/bin/mkdir -p /mnt/var/cache/pacman/pkg
/usr/bin/mkdir -p /repo
/usr/bin/mkdir -p /mnt/repo


echo "==> Setting archiso pacman mirror"
/usr/bin/cp mirrorlist /etc/pacman.d/mirrorlist

echo "==> Setting the package cache (nfs mount)"
mount -t nfs4 -o rsize=32768,wsize=32768,timeo=3 10.0.2.2:/var/cache/pacman/pkg /var/cache/pacman/pkg
mount -t nfs4 -o rsize=32768,wsize=32768,timeo=3 10.0.2.2:/var/cache/pacman/pkg /mnt/var/cache/pacman/pkg

echo "==> Mounting the AUR package repo"
mount -t nfs4 -o rsize=32768,wsize=32768,timeo=3 10.0.2.2:/mnt/data/pacman/repo /repo
mount -t nfs4 -o rsize=32768,wsize=32768,timeo=3 10.0.2.2:/mnt/data/pacman/repo /mnt/repo

# setup pacman repositories
echo '==> Installing local pacman package repositories'
printf "\n%s\n%s\n" "[demz-repo-community]" "Server = file:///repo/\$repo/\$arch" >> /etc/pacman.conf
printf "\n%s\n%s\n" "[demz-repo-core]" "Server = file:///repo/\$repo/\$arch" >> /etc/pacman.conf
dirmngr < /dev/null
pacman-key -r 0EE7A126
if [[ $? != 0 ]]; then
    exit 1
fi
pacman-key --lsign-key 0EE7A126
pacman -Sy

echo '==> bootstrapping the base installation'
/usr/bin/pacstrap -c ${TARGET_DIR} base base-devel

echo '==> pulling in external package repositories'
printf "\n%s\n%s\n" "[demz-repo-community]" "Server = file:///repo/\$repo/\$arch" >> /mnt/etc/pacman.conf
printf "\n%s\n%s\n" "[demz-repo-core]" "Server = file:///repo/\$repo/\$arch" >> /mnt/etc/pacman.conf
/usr/bin/arch-chroot ${TARGET_DIR} dirmngr < /dev/null
/usr/bin/arch-chroot ${TARGET_DIR} pacman-key -r 0EE7A126
if [[ $? != 0 ]]; then
    exit 1
fi
/usr/bin/arch-chroot ${TARGET_DIR} pacman-key --lsign-key 0EE7A126
/usr/bin/arch-chroot ${TARGET_DIR} pacman -Sy --noconfirm ${PACKAGES}
if [[ $? != 0 ]]; then
    exit 1
fi
/usr/bin/arch-chroot ${TARGET_DIR} syslinux-install_update -i -a -m
/usr/bin/sed -i 's/sda3/vda1/' "${TARGET_DIR}/boot/syslinux/syslinux.cfg"
/usr/bin/sed -i 's/TIMEOUT 50/TIMEOUT 10/' "${TARGET_DIR}/boot/syslinux/syslinux.cfg"

echo '==> Setting base image pacman mirror'
/usr/bin/cp /etc/pacman.d/mirrorlist ${TARGET_DIR}/etc/pacman.d/mirrorlist

echo '==> generating the filesystem table'
/usr/bin/genfstab -p ${TARGET_DIR} >> "${TARGET_DIR}/etc/fstab"

echo '==> generating the system configuration script'
/usr/bin/install --mode=0755 /dev/null "${TARGET_DIR}${CONFIG_SCRIPT}"

cat <<-EOF > "${TARGET_DIR}${CONFIG_SCRIPT}"
    echo '${FQDN}' > /etc/hostname
    /usr/bin/ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
    echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf
    /usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
    /usr/bin/locale-gen
    /usr/bin/mkinitcpio -p linux
    /usr/bin/usermod --password ${PASSWORD} root

    # https://wiki.archlinux.org/index.php/Network_Configuration#Device_names
    /usr/bin/ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
    /usr/bin/ln -s '/usr/lib/systemd/system/dhcpcd@.service' '/etc/systemd/system/multi-user.target.wants/dhcpcd@eth0.service'
    /usr/bin/sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
    /usr/bin/systemctl enable sshd.service

    # zfs-test configuration
    /usr/bin/groupadd zfs-tests
    /usr/bin/useradd --comment 'ZFS Test User' -d /var/tmp/test_results --create-home --gid users --groups zfs-tests zfs-tests

    # sudoers.d is the right way, but the zfs test suite checks /etc/sudoers...
    echo 'Defaults env_keep += "SSH_AUTH_SOCK"' > /etc/sudoers.d/10_zfs_test
    echo 'zfs-tests ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/10_zfs_test
    /usr/bin/chmod 0440 /etc/sudoers.d/10_zfs_test

    # clean up
    /usr/bin/pacman -Rcns --noconfirm gptfdisk
    /usr/bin/pacman -Scc --noconfirm
EOF

echo '==> entering chroot and configuring system'
/usr/bin/arch-chroot ${TARGET_DIR} ${CONFIG_SCRIPT}
rm "${TARGET_DIR}${CONFIG_SCRIPT}"

# http://comments.gmane.org/gmane.linux.arch.general/48739
echo '==> adding workaround for shutdown race condition'
/usr/bin/install --mode=0644 poweroff.timer "${TARGET_DIR}/etc/systemd/system/poweroff.timer"

echo '==> installation complete!'
/usr/bin/sleep 5
/usr/bin/umount /mnt/repo
/usr/bin/umount /mnt/var/cache/pacman/pkg
/usr/bin/umount ${TARGET_DIR}
/usr/bin/umount /var/cache/pacman/pkg
/usr/bin/umount /repo
/usr/bin/systemctl reboot
