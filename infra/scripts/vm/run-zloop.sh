#!/bin/bash
#
# run-zloop.sh [hours] -- launch a DETACHED ZFS stress hunt (zloop/ztest) in
# the guest. Runs in userland (libzpool) -- no kernel build/onu/reboot. If a
# ztest run crashes, zloop preserves its log + vdev files + core under the
# cores dir for analysis.
#
#   infra/scripts/vm/run-zloop.sh [hours]     (default 8h; profile via OXIDE_VM_PROFILE)
#
# vdevs + cores live under /data/zloop on the persistent data disk (off
# rpool). Check progress / crashes with: infra/scripts/vm/zloop-status.sh
# When a core appears, share it -- I'll walk the backtrace (mdb).

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

hours="${1:-8}"
profile="${OXIDE_VM_PROFILE:-dev}"
secs=$(( hours * 3600 ))
user="${GUEST_USER:-$(id -un)}"
ip=$("$SCRIPT_DIR/start-build-vm.sh" --ip "$profile" 2>/dev/null || true)
[ -n "$ip" ] || { echo "VM helios-$profile not running. Start: $SCRIPT_DIR/start-build-vm.sh $profile" >&2; exit 1; }

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$user@$ip" "bash -s" <<REMOTE
set -e
P=/data/helios/helios/projects/illumos/proto/root_i386-nd
[ -x "\$P/usr/bin/zloop" ] || { echo "zloop not built at \$P -- run a build first." >&2; exit 1; }
if pgrep -f '[u]sr/bin/zloop' >/dev/null 2>&1; then
    echo "zloop is already running (pid \$(pgrep -f '[u]sr/bin/zloop' | head -1)); not starting another."
    exit 0
fi
# /data (pool root) is root-owned; create our dir and hand it to us once.
if [ ! -w /data/zloop ] 2>/dev/null; then
    pfexec mkdir -p /data/zloop/cores
    pfexec chown -R "$user" /data/zloop
fi
mkdir -p /data/zloop/cores
cd /data/zloop
# zloop calls /usr/bin/ztest by ABSOLUTE path, but ztest ships only in the
# proto -- symlink it (system libzpool matches, since the OS is this build).
[ -e /usr/bin/ztest ] || pfexec ln -s "\$P/usr/bin/ztest" /usr/bin/ztest
# zloop runs 'sudo coreadm -e process' (to capture cores); on illumos shim
# sudo -> pfexec so it works without a tty/password.
mkdir -p /data/zloop/bin
printf '#!/bin/sh\nexec pfexec "\$@"\n' > /data/zloop/bin/sudo
chmod +x /data/zloop/bin/sudo
nohup env \
    PATH="/data/zloop/bin:\$P/usr/bin:\$P/usr/sbin:\$PATH" \
    LD_LIBRARY_PATH_64="\$P/usr/lib/amd64:\$P/lib/amd64" \
    "\$P/usr/bin/zloop" -t $secs -f /data/zloop -c /data/zloop/cores \
    > /data/zloop/zloop.log 2>&1 &
echo "launched zloop (pid \$!) for ${hours}h"
echo "  log:   /data/zloop/zloop.log"
echo "  cores: /data/zloop/cores  (a subdir appears here on each crash)"
REMOTE

echo
echo "Detached. It keeps running after you log out. Check it with:"
echo "  infra/scripts/vm/zloop-status.sh"
