#!/bin/bash

AZT_TEST=0
AZT_BASE=0
AZT_MODE_GIT=0
AZT_MODE_LTS=0
AZT_PKG_TYPE=""
AZT_TEST_PKG_WORKDIR="archzfs"

# SSH config
SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
SSH_OPTS="$SSH_OPTS -o ConnectTimeout=3 -p 2222"
SSH="/usr/sbin/ssh $SSH_OPTS"
AZT_SSH_PASS="sshpass -p azfstest"
AZT_SSH="$AZT_SSH_PASS $SSH"

# For building the base image
export AZT_ARCHISO="https://mirrors.kernel.org/archlinux/iso/2015.04.01/archlinux-2015.04.01-dual.iso"
export AZT_ARCHISO_SHA="95122cbbde7252959bcea1c49fd797eb0eb25a4b"
export AZT_PACKER_HTTPDIR="$PWD/testdata/files"

AZT_ARCHISO_BASENAME=$(basename $AZT_ARCHISO)
export AZT_BASE_IMAGE_BASENAME="archzfs-base-${AZT_ARCHISO_BASENAME:10:-9}"
export AZT_BASE_IMAGE_OUTPUT_DIR="$PWD/testdata/base"
AZT_BASE_IMAGE_NAME="$AZT_BASE_IMAGE_OUTPUT_DIR/${AZT_BASE_IMAGE_BASENAME}.qcow2"
AZT_WORK_IMAGE_RANDNAME="$AZT_BASE_IMAGE_OUTPUT_DIR/${AZT_BASE_IMAGE_BASENAME}_${RANDOM}.qcow2"

export PACKER_CACHE_DIR="$PWD/testdata/packer_cache"

SNAME=$(basename $0)

source ../lib.sh

cleanup() {
    [[ -f "$PWD/testdata/files/setup-test-image.sh" ]] && rm "$PWD/testdata/files/setup-test-image.sh"
    [[ -f "$AZT_WORK_IMAGE_RANDNAME" ]] && rm "$AZT_WORK_IMAGE_RANDNAME"
	[[ $1 ]] && exit $1
}

trap 'trap_abort' INT QUIT TERM HUP
trap 'trap_exit' EXIT

usage() {
cat << EOF

$SNAME - A test script for archzfs

Usage: $SNAME [options] [mode] [command [command option] [...]

Options:

    -h:    Show help information.
    -n:    Dryrun; Output commands, but don't do anything.
    -d:    Show debug info.

Modes:

    base   Build the base image

    git    Use the latest git packages.
    lts    Use the latest lts packages.

Commands:

    test   Build test packages. Only used with git and lts modes.
EOF
}

if [[ $# -lt 1 ]]; then
    usage;
    exit 0;
fi

ARGS=("$@")
for (( a = 0; a < $#; a++ )); do
    if [[ ${ARGS[$a]} == "git" ]]; then
        AZT_MODE_GIT=1
    elif [[ ${ARGS[$a]} == "lts" ]]; then
        AZT_MODE_LTS=1
    elif [[ ${ARGS[$a]} == "test" ]]; then
        AZT_TEST=1
    elif [[ ${ARGS[$a]} == "base" ]]; then
        AZT_BASE=1
    elif [[ ${ARGS[$a]} == "-h" ]]; then
        usage;
        exit 0;
    elif [[ ${ARGS[$a]} == "-n" ]]; then
        DRY_RUN=1
    elif [[ ${ARGS[$a]} == "-d" ]]; then
        DEBUG=1
    fi
done

[[ $AZT_MODE_GIT == 0 && $AZT_MODE_LTS == 0 && $AZT_BASE == 0 ]] && error "Mode not specified!" && usage && exit 1;
[[ $AZT_MODE_GIT == 1 ]] && AZT_PKG_TYPE="git" || AZT_PKG_TYPE="lts"
# [[ $AZT_TEST == 0 ]] && warning "No commands were used!"

copy_latest_packages() {
    msg2 "Creating package arch directories"
    run_cmd "[[ -d $AZT_TEST_PKG_WORKDIR ]] && rm -rf $AZT_TEST_PKG_WORKDIR"
    run_cmd "mkdir -p $AZT_TEST_PKG_WORKDIR/{x64,x32}"

    #msg2 "Copying x32 packages"
    #run_cmd 'find ../../ -type f -name "'"*$AZT_PKG_TYPE"'*i686.pkg.tar.xz" -printf "%C@ %p\n" | sort -rn | head -n 4 | awk "{ print \$2 }" | xargs -i cp {} '"$AZT_TEST_PKG_WORKDIR"'/x32/'

    msg2 "Copying x64 packages"
    run_cmd 'find ../../ -type f -name "'"*$AZT_PKG_TYPE"'*x86_64.pkg.tar.xz" -printf "%C@ %p\n" | sort -rn | head -n 4 | awk "{ print \$2 }" | xargs -i cp {} "'"$AZT_TEST_PKG_WORKDIR"'/x64/"'
}

if [[ $AZT_BASE == 1 ]]; then
    if [[ -z "$AZT_PACKER_HTTPDIR/mirrorlist" ]]; then
        msg "Generating pacman mirrorlist"
        /usr/bin/reflector -c US -l 5 -f 5 --sort rate 2>&1 > $AZT_PACKER_HTTPDIR/mirrorlist
    fi

    msg "Building arch base image"
    run_cmd "rm -rf '$AZT_BASE_IMAGE_OUTPUT_DIR'"
    run_cmd "ln -s '$PWD/arch-zfs-base/setup-test-image.sh' '$AZT_PACKER_HTTPDIR/setup-test-image.sh'"
    run_cmd "packer build arch-zfs-base/arch-zfs-base.json"

    # msg "Moving the compiled base image"
    # run_cmd "mv $AZT_BASEIMAGE_NAME'"
fi

if [[ $AZT_TEST == 1 ]]; then
    msg "Testing $AZT_PKG_TYPE packages"

    msg2 "Copying latest $AZT_PKG_TYPE packages"
    copy_latest_packages
    if [[ $(ls $AZT_TEST_PKG_WORKDIR/x64/ | wc -w) == 0 ]]; then
        error "No $AZT_PKG_TYPE packages found in $AZT_TEST_PKG_WORKDIR/x64/"
        exit 1
    fi

    msg2 "Cloning $AZT_BASE_IMAGE_NAME"
    run_cmd "cp $AZT_BASE_IMAGE_NAME $AZT_WORK_IMAGE_RANDNAME"

    msg "Booting VM clone..."
    cmd="qemu-system-x86_64 -enable-kvm "
    cmd="$cmd -m 4096 -smp 2 -redir tcp:2222::22 -drive "
    cmd="$cmd file=$AZT_WORK_IMAGE_RANDNAME,if=virtio"
    run_cmd "$cmd" &

    sleep 2;

    if [[ -z "$DEBUG" ]]; then
        msg "Waiting for SSH..."
        while :; do
            run_cmd "$AZT_SSH root@localhost echo &> /dev/null"
            if [[ $? == 0 ]]; then
                break
            fi
        done
    fi

    msg2 "Copying the latest packages to the VM"
    copy_latest_packages
    run_cmd "rsync -vrthP -e '$AZT_SSH' archzfs/x64/ root@localhost:"
    run_cmd "$AZT_SSH root@localhost pacman -U --noconfirm '*.pkg.tar.xz'"

    msg2 "Cloning ZFS test suite"
    run_cmd "$AZT_SSH root@localhost git clone https://github.com/zfsonlinux/zfs-test.git"

    # msg2 "Building ZFS test suite"
    # run_cmd "$AZT_SSH root@localhost 'cd zfs-test && ./autogen.sh && ./configure && make test'"

    # msg2 "Cause I'm housin"
    # run_cmd "$AZT_SSH root@localhost systemctl poweroff &> /dev/null"
fi

wait
