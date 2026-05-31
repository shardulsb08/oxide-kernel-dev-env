#!/bin/sh
#
# build-helios.sh -- runs INSIDE the Helios guest (as the build user) to clone
# (if needed) and build illumos via the Helios orchestrator. Driven from the
# host by infra/scripts/vm/build-helios.sh over SSH, but also runnable directly
# in the guest.
#
# Steps: ensure build deps -> clone helios -> `gmake setup OXIDE_STAFF=no`
# (once) -> `gmake illumos` (quick build). Idempotent.
#
# Env:
#   WORK=/data/helios     persistent work root (the ZFS dataset)
#   FORCE_SETUP=1         re-run `gmake setup` even if ./helios-build exists
#   OXIDE_STAFF=no        public path (no SSH/staff-gated private repos)

set -eu
WORK="${WORK:-/data/helios}"
REPO="$WORK/helios"
OXIDE_STAFF="${OXIDE_STAFF:-no}"

# illumos build tools land under /opt/ooce; cargo under ~/.cargo. Make sure a
# non-login SSH shell can find them.
export PATH="$PATH:/usr/bin:/opt/ooce/bin:/opt/ooce/sbin:$HOME/.cargo/bin"

echo "===== Helios build ($(uname -v)) -- work root $WORK ====="

# 1. Build dependencies (gmake/git/gcc via pkg; Rust via rustup).
if ! command -v gmake >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "== installing /developer/build-essential + /developer/illumos-tools =="
    pfexec pkg install -v /developer/build-essential /developer/illumos-tools \
        || echo "(pkg install reported nonzero -- continuing; may already be present)"
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if ! command -v cargo >/dev/null 2>&1; then
    echo "== installing Rust toolchain via rustup =="
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
    . "$HOME/.cargo/env"
fi
echo "gmake: $(command -v gmake || echo MISSING)   cargo: $(command -v cargo || echo MISSING)"

# 2. Clone Helios if it isn't there yet.
if [ ! -e "$REPO/.git" ]; then
    echo "== cloning oxidecomputer/helios into $REPO =="
    mkdir -p "$WORK"
    git clone https://github.com/oxidecomputer/helios.git "$REPO"
fi
cd "$REPO"

# 3. One-time setup: clone the consolidations + build the helios-build tool.
if [ ! -e ./helios-build ] || [ "${FORCE_SETUP:-0}" = 1 ]; then
    echo "== gmake setup (OXIDE_STAFF=$OXIDE_STAFF) -- clones illumos-gate(stlouis), omnios(helios3), builds the tool =="
    gmake setup "OXIDE_STAFF=$OXIDE_STAFF"
else
    echo "== ./helios-build present; skipping setup (FORCE_SETUP=1 to redo) =="
fi

# 4. Quick illumos build (the normal dev cadence).
echo "== gmake illumos (quick build) =="
gmake illumos

echo "===== build complete -- packages under $REPO/projects/illumos/packages/i386 ====="
echo "Next: 'gmake bldenv' for the interactive incremental (dmake) build environment."
