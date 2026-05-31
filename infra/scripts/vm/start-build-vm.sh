#!/bin/bash
#
# start-build-vm.sh -- create or boot a named Helios build VM, sizing guest
# RAM from live host memory so a long illumos build doesn't starve the
# desktop. Wraps helios-engvm's create.sh.
#
# PROFILES (multiple build images)
#   A "profile" names an independent VM + disk, so you can keep several
#   build images side by side -- e.g. a stable dev VM and a throwaway test
#   VM. This is the Helios analog of the kernel env's BUILD_PROFILE/KBUILDDIR
#   (there a profile names a build *dir*; here a whole *VM*).
#
#     ./start-build-vm.sh             # profile 'dev'   -> VM helios-dev
#     ./start-build-vm.sh test        # profile 'test'  -> VM helios-test
#     OXIDE_VM_PROFILE=exp ./start-build-vm.sh
#     ./start-build-vm.sh --list      # list existing helios-* VMs
#
#   If the VM for a profile already exists, it is BOOTED (and you attach to
#   its console), never recreated -- recreating would wipe its disk and lose
#   the build inside. To rebuild from the seed image:
#       (cd $ENGVM_DIR && ./destroy.sh <profile>) && ./start-build-vm.sh <profile>
#
# Lives in the tracked workspace-root repo (infra/), NOT in the upstream
# helios-engvm clone. Drives create.sh via $ENGVM_DIR.
#
# Knobs are env-overridable per run, e.g.:
#     VCPU=8 SIZE=100G HOST_RESERVE_GB=12 ./start-build-vm.sh test

set -o pipefail
set -o errexit

# --- Tunable knobs (env-overridable) ----------------------------------
MIN_GB="${MIN_GB:-8}"               # illumos build floor -- never less
MAX_GB="${MAX_GB:-16}"              # host protection -- never more
HOST_RESERVE_GB="${HOST_RESERVE_GB:-8}"  # RAM left free for the desktop
VCPU="${VCPU:-12}"                  # 32 threads here; build jobs = 2 + NCPUS
SIZE="${SIZE:-200G}"               # qcow2 VIRTUAL ceiling (thin, grows on demand)
DEFAULT_PROFILE="${OXIDE_VM_PROFILE:-dev}"
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'
}

# --- Argument handling: option or profile name ------------------------
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -l|--list)
        echo "Helios build VMs (libvirt domains named helios-*):"
        virsh list --all 2>/dev/null | awk 'NR<=2 || /helios-/'
        exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

PROFILE="${1:-$DEFAULT_PROFILE}"
VMNAME="helios-${PROFILE}"
CONFIG_NAME="$PROFILE"

if [ ! -x "$ENGVM_DIR/create.sh" ]; then
    echo "ERROR: helios-engvm clone not found at $ENGVM_DIR" >&2
    echo "Clone oxidecomputer/helios-engvm there first (see workspace README)." >&2
    exit 1
fi

# --- If the VM already exists, boot it -- never recreate (would wipe it) ---
if virsh domstate "$VMNAME" >/dev/null 2>&1; then
    state=$(virsh domstate "$VMNAME" 2>/dev/null || echo unknown)
    echo "VM '$VMNAME' already exists (state: $state)."
    echo "Booting/attaching it -- NOT recreating (recreate would wipe its disk)."
    echo "To rebuild from the seed image instead:"
    echo "    (cd \"$ENGVM_DIR\" && ./destroy.sh \"$PROFILE\") && \"$0\" \"$PROFILE\""
    echo
    if [ "$state" = "running" ]; then
        echo "Attaching console (Ctrl+] to detach)."
        exec virsh console "$VMNAME"
    else
        exec virsh start --console "$VMNAME"
    fi
fi

echo "Creating new build VM '$VMNAME' (profile '$PROFILE')."

# Inherit INPUT_IMAGE/POOL so preflight checks match create.sh.
. "$ENGVM_DIR/config/defaults.sh"

# --- 1. Assess host memory --------------------------------------------
avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
avail_gb=$(( avail_kb / 1024 / 1024 ))
total_gb=$(( total_kb / 1024 / 1024 ))
echo "Host memory: ${total_gb} GB total, ${avail_gb} GB available now."

# --- 2. Report memory-heavy processes (informational only) ------------
echo "Memory-heavy processes competing with the build VM:"
ps -eo rss,pid,comm --sort=-rss 2>/dev/null | awk '
    NR>1 && ($3 ~ /qemu/ || $3 ~ /ollama/ || $3 ~ /boinc/) {
        printf "  %-18s pid %-7s %6.1f GB\n", $3, $2, $1/1024/1024
    }' || true
echo "  (free these and re-run if you want the guest to get more RAM)"

# --- 3. Compute guest RAM ---------------------------------------------
mem_gb=$(( avail_gb - HOST_RESERVE_GB ))
[ "$mem_gb" -gt "$MAX_GB" ] && mem_gb=$MAX_GB
if [ "$mem_gb" -lt "$MIN_GB" ]; then
    echo >&2
    echo "ERROR: only ${avail_gb} GB available; after the ${HOST_RESERVE_GB} GB host" >&2
    echo "reserve, the guest would get < the ${MIN_GB} GB build floor." >&2
    echo "Free RAM (close VMs/tabs, 'sudo systemctl stop ollama', etc) and retry." >&2
    exit 1
fi
echo
echo "==> guest RAM: ${mem_gb} GB  (= ${avail_gb} avail - ${HOST_RESERVE_GB} reserve, clamped to [${MIN_GB},${MAX_GB}])"
echo "==> vCPU: ${VCPU}   disk ceiling: ${SIZE} (thin qcow2)"

# --- 4. Preflight: seed image + libvirt network -----------------------
if [ ! -f "$ENGVM_DIR/input/$INPUT_IMAGE" ]; then
    echo
    echo "Seed image $INPUT_IMAGE not found -- downloading via engvm download.sh ..."
    ( cd "$ENGVM_DIR" && ./download.sh )
fi

if ! virsh net-info default 2>/dev/null | grep -q 'Active:.*yes'; then
    echo "Activating libvirt 'default' network ..."
    virsh net-start default || true
fi

# --- 5. Write the generated config delta and launch -------------------
cfg="$ENGVM_DIR/config/${CONFIG_NAME}.sh"

# Ensure the generated config is git-excluded in the upstream-mirror clone
# so it never shows as untracked noise or risks being committed. Idempotent,
# and self-healing on a fresh clone where it hasn't been excluded yet.
if [ -d "$ENGVM_DIR/.git" ]; then
    exclude_file="$ENGVM_DIR/.git/info/exclude"
    exclude_pat="/config/${CONFIG_NAME}.sh"
    mkdir -p "$(dirname "$exclude_file")"
    if ! grep -qxF "$exclude_pat" "$exclude_file" 2>/dev/null; then
        printf '\n# Generated by infra/scripts/vm/start-build-vm.sh (runtime artifact, never commit)\n%s\n' \
            "$exclude_pat" >> "$exclude_file"
        echo "git-excluded $exclude_pat in the helios-engvm clone."
    fi
fi

cat > "$cfg" <<EOF
#
# GENERATED by infra/scripts/vm/start-build-vm.sh for profile '$PROFILE'.
# Do not hand-edit -- re-run the launcher. Layered over config/defaults.sh.
#
VM=$VMNAME
VCPU=$VCPU
MEM=\$(( $mem_gb * 1024 * 1024 ))
SIZE=$SIZE
EOF
echo "Wrote $cfg (VM=$VMNAME, MEM=${mem_gb} GB, VCPU=${VCPU}, SIZE=${SIZE})"
echo

exec "$ENGVM_DIR/create.sh" "$CONFIG_NAME"
