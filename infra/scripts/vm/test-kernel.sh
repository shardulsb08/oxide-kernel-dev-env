#!/bin/bash
#
# test-kernel.sh -- one command to test a kernel change end to end:
#   (1) rebuild + REPACKAGE illumos in the guest   (build-helios.sh)
#   (2) onu the fresh packages into a new boot environment
#   (3) cold-boot the VM into it, console captured  (boot-with-log.sh)
#
#   infra/scripts/vm/test-kernel.sh [profile]        (default 'dev')
#   --no-build : skip step 1 (onu the CURRENT packages -- only useful if you
#                already ran build-helios.sh; otherwise you'll boot a stale
#                kernel without your change, which is the #1 gotcha)
#
# Run in a real terminal -- step 3 attaches the serial console. After it
# boots, detach with Ctrl+]; verify with:  ./ssh_connect.sh <profile>
#
# NOTE: editing source + `dmake install` only updates the proto area; `onu`
# installs from the package repo, so the rebuild/repackage in step 1 is what
# makes your change actually take effect.

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

build=1
profile=""
for a in "$@"; do
    case "$a" in
        --no-build) build=0 ;;
        -*) echo "unknown option: $a" >&2; exit 2 ;;
        *) profile="$a" ;;
    esac
done
profile="${profile:-dev}"
vm="helios-${profile}"
user="${GUEST_USER:-$(id -un)}"

ip=$("$SCRIPT_DIR/start-build-vm.sh" --ip "$profile" 2>/dev/null || true)
[ -n "$ip" ] || { echo "VM '$vm' isn't running. Start it: $SCRIPT_DIR/start-build-vm.sh $profile" >&2; exit 1; }

# 1. Rebuild + repackage (so onu installs your change, not a stale build).
if [ "$build" = 1 ]; then
    echo "==> [1/3] rebuild + repackage (build-helios.sh)"
    "$SCRIPT_DIR/build-helios.sh" "$profile"
else
    echo "==> [1/3] skipped (--no-build); onu will use the CURRENT packages"
fi

# 2. onu into a fresh boot environment (prune old test BEs first; can't make
#    two BEs of the same name, and they accumulate on rpool).
be="kdev-$(date +%m%d-%H%M%S)"
echo "==> [2/3] onu -> boot environment '$be'"
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$user@$ip" "
    set -e
    for b in \$(pfexec beadm list -H 2>/dev/null | cut -f1 | grep '^kdev-' || true); do
        pfexec beadm destroy -fF \"\$b\" 2>/dev/null || true   # skips the active one
    done
    cd /data/helios/helios && ./helios-build onu -t '$be'
"

# 3. Cold-boot into the new BE with the console captured to a timestamped log.
echo "==> [3/3] cold boot into '$be' (console logged)"
exec "$SCRIPT_DIR/boot-with-log.sh" "$profile"
