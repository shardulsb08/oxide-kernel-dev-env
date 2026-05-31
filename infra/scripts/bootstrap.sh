#!/bin/bash
#
# bootstrap.sh -- clone the upstream Oxide repos this workspace builds on,
# into the paths the tooling expects (src/os/helios, src/vm/helios-engvm).
# These clones are gitignored by the root repo and tracked in their own
# upstream remotes. Idempotent: skips a clone that already exists.
#
#   infra/scripts/bootstrap.sh

set -o pipefail
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

clone_if_missing() {
    local url="$1" dir="$2"
    if [ -d "$dir/.git" ]; then
        echo "ok: $dir already cloned"
    else
        echo "cloning $url -> $dir"
        mkdir -p "$(dirname "$dir")"
        git clone "$url" "$dir"
    fi
}

# helios-engvm runs on THIS host to create/boot the build VM.
clone_if_missing "https://github.com/oxidecomputer/helios-engvm.git" "$ENGVM_DIR"
# helios is the build orchestrator. The host clone is the reference / scaffold
# home; the actual build happens inside the guest (cloned there onto ZFS).
clone_if_missing "https://github.com/oxidecomputer/helios.git" "$HELIOS_DIR"

echo
echo "Done. Next: infra/scripts/vm/start-build-vm.sh   (see infra/GETTING_STARTED.md)"
