#!/bin/bash
#
# boot-with-log.sh -- cold-start a build VM with its serial console attached
# AND captured to a timestamped log, so you can see (and keep) the full boot
# -- loader, kernel, panics. Use this to debug boot/console problems that the
# normal headless `start-build-vm.sh` hides.
#
#   infra/scripts/vm/boot-with-log.sh [profile]      (default 'dev')
#
# Run it in a real terminal (it attaches the interactive console). Once the
# guest is up, detach with Ctrl+]. The full boot is saved to
# infra/serial-logs/<vm>-<timestamp>.log (gitignored) -- share that to debug.
#
# Capturing the WHOLE boot requires attaching from power-on, so this does a
# cold start: it shuts the VM down first if it's running.

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

profile="${1:-dev}"
vm="helios-${profile}"

virsh domstate "$vm" >/dev/null 2>&1 || { echo "no such VM: $vm" >&2; exit 1; }
command -v script >/dev/null 2>&1 || { echo "'script' (util-linux) is required for logging." >&2; exit 1; }

# Cold start needed so the console is attached from the very first output.
state=$(virsh domstate "$vm" 2>/dev/null || echo unknown)
if [ "$state" = "running" ]; then
    echo "Shutting '$vm' down for a clean logged boot..."
    virsh shutdown "$vm" >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 40 ]; do
        [ "$(virsh domstate "$vm" 2>/dev/null)" = "shut off" ] && break
        sleep 3; i=$(( i + 1 ))
    done
    if [ "$(virsh domstate "$vm" 2>/dev/null)" != "shut off" ]; then
        echo "Guest didn't shut down gracefully. Force it with:  virsh destroy $vm" >&2
        echo "then re-run this script." >&2
        exit 1
    fi
fi

logdir="$OXIDE_WS_ROOT/infra/serial-logs"
mkdir -p "$logdir"
ts=$(date +%Y%m%d-%H%M%S)
log="$logdir/${vm}-${ts}.log"

cat <<EOF
Cold-starting '$vm' with serial console attached + logged.
  log: $log
Watch the boot below. Detach with Ctrl+]  (the VM keeps running).
EOF
echo

# `script` provides the controlling TTY virsh console needs, shows the boot
# live, and tees everything to the timestamped log.
script -q -c "virsh start --console '$vm'" "$log"

echo
echo "Boot log saved: $log"
echo "Connect once it's up:  ./ssh_connect.sh $profile"
