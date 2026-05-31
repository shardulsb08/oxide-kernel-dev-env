#!/bin/sh
#
# setup-data-pool.sh -- runs INSIDE the Helios guest (via pfexec) to make the
# persistent data disk usable. Idempotent and conservative:
#
#   1. If the 'data' pool is already imported -> nothing to do.
#   2. Else if it can be imported (existing pool, e.g. after a VM recreate)
#      -> import it (non-destructive).
#   3. Else create it -- but ONLY on a single, blank, large, non-root disk.
#      If zero or multiple candidates, ABORT and ask the user to do it by
#      hand (never guess a disk -- that would destroy data).
#
# Then ensure the data/helios dataset exists and is owned by the build user,
# and clone Helios into it for building (Phase 1) if not already present.
#
# Driven by infra/scripts/vm/start-build-vm.sh over SSH. GUEST_USER is passed
# in the environment (the account to own the tree); defaults to root.

set -eu
POOL=data
DS=data/helios
MIN_BYTES=1073741824        # ignore disks < 1 GiB (e.g. the ~1M metadata disk)
GUEST_USER="${GUEST_USER:-root}"

if zpool list -H -o name "$POOL" >/dev/null 2>&1; then
    echo "pool '$POOL' already imported."
elif zpool import "$POOL" >/dev/null 2>&1; then
    echo "imported existing pool '$POOL'."
else
    rpdisk=$(zpool status rpool 2>/dev/null | awk '/c[0-9]+t[0-9]+d[0-9]+/{print $1; exit}')
    cand=
    # diskinfo -Hp is TAB-separated; the PID column ("Block Device") contains a
    # space, so split strictly on tabs: $2=disk, $5=size in bytes.
    for d in $(diskinfo -Hp 2>/dev/null | awk -F'\t' '{print $2}'); do
        [ "$d" = "$rpdisk" ] && continue
        sz=$(diskinfo -Hp 2>/dev/null | awk -F'\t' -v dd="$d" '$2==dd{print $5}')
        [ "${sz:-0}" -lt "$MIN_BYTES" ] && continue
        # Skip disks that already carry a ZFS label (belong to some pool).
        if zdb -l "/dev/dsk/${d}s0" 2>/dev/null | grep -q txg; then continue; fi
        if [ -n "$cand" ]; then
            echo "ERROR: multiple blank candidate disks ($cand, $d) -- refusing to guess." >&2
            echo "Create the pool by hand: pfexec zpool create $POOL <disk>" >&2
            exit 1
        fi
        cand=$d
    done
    if [ -z "$cand" ]; then
        echo "ERROR: no blank data disk found -- not creating a pool." >&2
        echo "Confirm the data disk is attached, or create by hand." >&2
        exit 1
    fi
    echo "creating pool '$POOL' on blank disk $cand ..."
    zpool create -f "$POOL" "$cand"
fi

if ! zfs list -H -o name "$DS" >/dev/null 2>&1; then
    echo "creating dataset $DS ..."
    zfs create "$DS"
fi
mp=$(zfs get -H -o value mountpoint "$DS")
chown "$GUEST_USER" "$mp" 2>/dev/null || true
echo "data dataset ready at $mp (owner $GUEST_USER)"

if [ ! -e "$mp/helios/.git" ]; then
    echo "cloning oxidecomputer/helios into $mp/helios ..."
    if git clone https://github.com/oxidecomputer/helios.git "$mp/helios" 2>/dev/null; then
        chown -R "$GUEST_USER" "$mp/helios" 2>/dev/null || true
    else
        echo "(helios clone skipped -- clone it manually when ready: git clone https://github.com/oxidecomputer/helios.git $mp/helios)"
    fi
fi
echo "guest data setup complete."
