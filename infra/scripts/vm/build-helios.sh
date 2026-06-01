#!/bin/bash
#
# build-helios.sh -- HOST-side wrapper: build Helios/illumos inside a running
# build VM. Resolves the VM's IP, runs guest/build-helios.sh over SSH (clone
# if needed -> gmake setup -> gmake illumos), and tees the output to a log
# under the workspace. Build artifacts live in the guest at /data/helios.
#
#   infra/scripts/vm/build-helios.sh [profile]        (default 'dev')
#   infra/scripts/vm/build-helios.sh --fast [profile]  quick incremental rebuild
#       (bldenv dmake of $SRC/uts + repackage; ~2x faster, kernel-focused --
#        requires a prior full build. For cmd/lib changes use a full build.)
#
# Env: FORCE_SETUP=1 re-runs `gmake setup`; GUEST_USER overrides the SSH user.

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

fast=0
profile=""
for a in "$@"; do
    case "$a" in
        --fast) fast=1 ;;
        -*) echo "unknown option: $a" >&2; exit 2 ;;
        *) profile="$a" ;;
    esac
done
profile="${profile:-dev}"
vm="helios-${profile}"
user="${GUEST_USER:-$(id -un)}"

ip=$("$SCRIPT_DIR/start-build-vm.sh" --ip "$profile" 2>/dev/null || true)
if [ -z "$ip" ]; then
    echo "VM '$vm' has no IP (is it running?)." >&2
    echo "Start it first: $SCRIPT_DIR/start-build-vm.sh $profile" >&2
    exit 1
fi

logdir="$OXIDE_WS_ROOT/infra/build-logs"
mkdir -p "$logdir"
log="$logdir/build-${profile}.log"

if [ "$fast" = 1 ]; then
    steps="FAST: bldenv dmake (\$SRC/uts) + repackage (~minutes; kernel-focused)"
else
    steps="clone (if needed) -> gmake setup OXIDE_STAFF=no -> gmake illumos (full nightly)"
fi
cat <<EOF
Building Helios/illumos in guest '$vm' ($ip) as $user.
  steps:   $steps
  output:  /data/helios/helios  (in the guest; on the persistent data disk)
  log:     $log  (host copy; streamed below)

It streams live; if your SSH drops, re-run -- the steps are idempotent.
For a detach-proof run, start it inside tmux/screen in the guest instead.

EOF

# Pass FORCE_SETUP/FAST through. No pty (-t) so non-interactive pkg/rustup
# steps don't expect one; output streams and is teed to the host log.
ssh -o StrictHostKeyChecking=accept-new "$user@$ip" \
    "FORCE_SETUP='${FORCE_SETUP:-0}' FAST='${fast}' sh -s" < "$SCRIPT_DIR/guest/build-helios.sh" 2>&1 \
    | tee "$log"
