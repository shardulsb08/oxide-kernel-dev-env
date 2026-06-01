#!/bin/bash
#
# zloop-status.sh -- quick check on a running zloop ZFS hunt in the guest:
# is it running, recent log, and (most importantly) any crash dirs.
#
#   infra/scripts/vm/zloop-status.sh        (profile via OXIDE_VM_PROFILE; default dev)
#
# A non-empty cores dir = ztest crashed = a candidate ZFS bug. Share the
# crash dir's ztest log + an mdb backtrace of the core for diagnosis:
#   mdb <core> then ::status, $C   (or ::stack)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

profile="${OXIDE_VM_PROFILE:-dev}"
user="${GUEST_USER:-$(id -un)}"
ip=$("$SCRIPT_DIR/start-build-vm.sh" --ip "$profile" 2>/dev/null || true)
[ -n "$ip" ] || { echo "VM helios-$profile not running." >&2; exit 1; }

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$user@$ip" '
echo "=== zloop process ==="; pgrep -fl "[u]sr/bin/zloop" || echo "(not running)"
echo; echo "=== zloop.log (tail) ==="; tail -12 /data/zloop/zloop.log 2>/dev/null || echo "(no log yet)"
echo; echo "=== crash dirs (each = a ztest failure to investigate) ==="
ls -1 /data/zloop/cores/ 2>/dev/null | sed "s/^/  /" || true
n=$(ls -1 /data/zloop/cores/ 2>/dev/null | wc -l)
echo "  -> $n crash dir(s)"
'
