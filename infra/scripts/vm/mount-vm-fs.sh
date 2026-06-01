#!/bin/bash
#
# mount-vm-fs.sh -- sshfs-mount the build VM's /data (kernel source + build
# tree + logs) onto the host, so you can use HOST tools (ctags, cscope,
# your editor, ~/shortcuts/setup_code_navigation.sh) against the live tree.
#
#   infra/scripts/vm/mount-vm-fs.sh [profile]            mount  (default 'dev')
#   infra/scripts/vm/mount-vm-fs.sh --umount [profile]   unmount
#
# Mountpoint: $OXIDE_WS_ROOT/vm-mnt/<profile> (gitignored). After mounting,
# the illumos source is at:
#   vm-mnt/<profile>/helios/projects/illumos/usr/src
#
# NOTE: ctags/cscope over sshfs on the *whole* illumos tree is slow to index
# (every file is read over SSH). For the big tree, prefer generating the
# index IN the guest (it's local/fast there) and just navigate over the
# mount; or point your indexer at a single subsystem dir.

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

umount=0
profile=""
for a in "$@"; do
    case "$a" in
        --umount|-u) umount=1 ;;
        -*) echo "unknown option: $a" >&2; exit 2 ;;
        *) profile="$a" ;;
    esac
done
profile="${profile:-dev}"
vm="helios-${profile}"
user="${GUEST_USER:-$(id -un)}"
mnt="$OXIDE_WS_ROOT/vm-mnt/${profile}"

if [ "$umount" = 1 ]; then
    fusermount -u "$mnt" 2>/dev/null || umount "$mnt" 2>/dev/null || true
    echo "unmounted $mnt"
    exit 0
fi

command -v sshfs >/dev/null 2>&1 || { echo "sshfs not installed (apt install sshfs)" >&2; exit 1; }
ip=$("$SCRIPT_DIR/start-build-vm.sh" --ip "$profile" 2>/dev/null || true)
[ -n "$ip" ] || { echo "VM '$vm' has no IP (running?). Start: $SCRIPT_DIR/start-build-vm.sh $profile" >&2; exit 1; }

mkdir -p "$mnt"
if mountpoint -q "$mnt" 2>/dev/null; then
    echo "already mounted: $mnt"
else
    echo "mounting ${user}@${ip}:/data -> $mnt"
    sshfs "${user}@${ip}:/data" "$mnt" \
        -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 \
        -o idmap=user,follow_symlinks \
        -o StrictHostKeyChecking=accept-new
fi

cat <<EOF
Mounted. Useful paths on the host now:
  illumos source : $mnt/helios/projects/illumos/usr/src
  helios repo    : $mnt/helios
  guest logs     : (kernel) on the guest via /var/adm/messages; build under $mnt/helios
Code navigation, e.g.:
  cd "$mnt/helios/projects/illumos/usr/src" && /home/shardul/shortcuts/setup_code_navigation.sh
Unmount with: $0 --umount $profile
EOF
