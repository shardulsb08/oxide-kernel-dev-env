#!/bin/bash
#
# config.sh -- shared path configuration for oxide_computer workspace infra.
#
# Sourced by every script under infra/scripts/. Locates the workspace root
# and exports canonical paths to the upstream clones, so scripts never
# hard-code absolute paths and keep working if the workspace moves.
#
# Usage in a script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../config.sh"        # adjust ../ to reach infra/scripts/
#
# This file always lives at infra/scripts/config.sh, so it can locate the
# root from its OWN location regardless of which script sources it.

# Directory this config file lives in (infra/scripts).
_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Workspace root = two levels up (infra/scripts -> infra -> root), unless
# overridden. Validate it looks like the oxide_computer workspace.
if [ -z "$OXIDE_WS_ROOT" ]; then
    _detected="$(cd "$_CONFIG_DIR/../.." && pwd)"
    if [ -d "$_detected/src" ] && [ -f "$_detected/CLAUDE.md" ]; then
        OXIDE_WS_ROOT="$_detected"
    else
        echo "config.sh: could not detect workspace root from $_CONFIG_DIR." >&2
        echo "Set OXIDE_WS_ROOT to the oxide_computer directory and retry." >&2
        return 1 2>/dev/null || exit 1
    fi
fi
export OXIDE_WS_ROOT

# ---- Standard areas ----
export INFRA_DIR="$OXIDE_WS_ROOT/infra"
export SCRIPTS_DIR="$INFRA_DIR/scripts"
export SRC_DIR="$OXIDE_WS_ROOT/src"

# ---- Upstream clones (gitignored from the root repo; cloned individually) ----
# Helios OS build orchestrator (oxidecomputer/helios).
export HELIOS_DIR="$SRC_DIR/os/helios"
# VM / host provisioning tooling (oxidecomputer/helios-engvm).
export ENGVM_DIR="$SRC_DIR/vm/helios-engvm"

# Print everything this config sets (debugging aid):
#   source infra/scripts/config.sh && oxide_printvars
oxide_printvars() {
    echo "=== oxide_computer workspace paths ==="
    echo "  OXIDE_WS_ROOT = $OXIDE_WS_ROOT"
    echo "  INFRA_DIR     = $INFRA_DIR"
    echo "  SCRIPTS_DIR   = $SCRIPTS_DIR"
    echo "  SRC_DIR       = $SRC_DIR"
    echo "  HELIOS_DIR    = $HELIOS_DIR"
    echo "  ENGVM_DIR     = $ENGVM_DIR"
}
