#!/bin/bash

AZB_TEST=0
AZB_MODE_GIT=0
AZB_MODE_LTS=0
AZB_PKG_TYPE=""
AZB_TEST_PKG_WORKDIR="archzfs"

export PACKER_CACHE_DIR="../testdata/packer_cache"

SNAME=$(basename $0)

source ../lib.sh

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
        AZB_MODE_GIT=1
    elif [[ ${ARGS[$a]} == "lts" ]]; then
        AZB_MODE_LTS=1
    elif [[ ${ARGS[$a]} == "test" ]]; then
        AZB_TEST=1
    elif [[ ${ARGS[$a]} == "base" ]]; then
        AZB_BASE=1
    elif [[ ${ARGS[$a]} == "-h" ]]; then
        usage;
        exit 0;
    elif [[ ${ARGS[$a]} == "-n" ]]; then
        DRY_RUN=1
    elif [[ ${ARGS[$a]} == "-d" ]]; then
        DEBUG=1
    fi
done

[[ $AZB_MODE_GIT == 0 && $AZB_MODE_LTS == 0 && $AZB_BASE == 0 ]] && error "Mode not specified!" && exit 1;
[[ $AZB_MODE_GIT == 1 ]] && AZB_PKG_TYPE="git" || AZB_PKG_TYPE="lts"
# [[ $AZB_TEST == 0 ]] && warning "No commands were used!"

copy_latest_packages() {
    msg2 "Creating package arch directories"
    run_cmd "[[ -d $AZB_TEST_PKG_WORKDIR ]] && rm -rf $AZB_TEST_PKG_WORKDIR"
    run_cmd "mkdir -p $AZB_TEST_PKG_WORKDIR/{x64,x32}"

    #msg2 "Copying x32 packages"
    #run_cmd 'find ../../ -type f -name "'"*$AZB_PKG_TYPE"'*i686.pkg.tar.xz" -printf "%C@ %p\n" | sort -rn | head -n 4 | awk "{ print \$2 }" | xargs -i cp {} '"$AZB_TEST_PKG_WORKDIR"'/x32/'

    msg2 "Copying x64 packages"
    run_cmd 'find ../../ -type f -name "'"*$AZB_PKG_TYPE"'*x86_64.pkg.tar.xz" -printf "%C@ %p\n" | sort -rn | head -n 4 | awk "{ print \$2 }" | xargs -i cp {} "'"$AZB_TEST_PKG_WORKDIR"'/x64/"'
}

if [[ $AZB_BASE == 1 ]]; then
    if [[ -z mirrorlist ]]; then
        msg "Generating pacman mirrorlist"
        /usr/bin/reflector -c US -l 5 -f 5 --sort rate 2>&1 | tee testdata/files/mirrorlist
    fi

    msg "Building arch base image"
    run_cmd "packer build arch-zfs-base.json"
fi

if [[ $AZB_TEST == 1 ]]; then
    msg "Copying latest packages"
    copy_latest_packages

    msg "Building arch base image with archzfs $AZB_PKG_TYPE packages"
    run_cmd "packer build arch.json"
fi
