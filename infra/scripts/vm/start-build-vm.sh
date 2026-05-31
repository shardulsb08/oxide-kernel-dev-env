#!/bin/bash
#
# start-build-vm.sh -- create or boot a named Helios build VM, sizing guest
# RAM from live host memory, attaching a persistent data disk, and (by
# default) provisioning the guest's ZFS data pool. Wraps helios-engvm's
# create.sh. Lives in the tracked workspace-root repo (infra/), not the clone.
#
#   start-build-vm.sh [profile]          create or boot VM helios-<profile> (default 'dev')
#   start-build-vm.sh --list             list existing helios-* VMs
#   start-build-vm.sh --ssh <profile>    SSH into the VM (resolves its IP)
#   start-build-vm.sh --console <profile> attach the serial console (Ctrl+] to detach)
#   start-build-vm.sh --ip  <profile>    print the VM's IP
#   start-build-vm.sh --set-ram <p> [GB] resize an existing VM's RAM (shuts it down)
#   start-build-vm.sh --ensure-data <p> [SIZE]   (just) create+attach the data disk
#   start-build-vm.sh --help
#
# Profiles name independent VMs (helios-<profile>) + disks, so several build
# images can coexist (one at a time may use the shared data pool). Re-running
# a profile BOOTS its VM, never recreates it (recreate would wipe its root).
#
# By default the persistent data disk is attached and the guest 'data' ZFS
# pool is provisioned automatically. Opt out with DATA_DISK=0 / PROVISION_GUEST=0.
# Other env knobs (override per run):
#   MIN_GB MAX_GB HOST_RESERVE_GB VCPU SIZE DATA_VOL DATA_SIZE OXIDE_VM_PROFILE GUEST_USER

set -o pipefail
set -o errexit

# --- Tunable knobs (env-overridable) ----------------------------------
MIN_GB="${MIN_GB:-8}"
MAX_GB="${MAX_GB:-16}"
HOST_RESERVE_GB="${HOST_RESERVE_GB:-8}"
VCPU="${VCPU:-12}"
SIZE="${SIZE:-200G}"
DEFAULT_PROFILE="${OXIDE_VM_PROFILE:-dev}"
DATA_VOL="${DATA_VOL:-helios-data}"
DATA_SIZE="${DATA_SIZE:-200G}"
DATA_DISK="${DATA_DISK:-1}"            # 1=attach persistent data disk by default
PROVISION_GUEST="${PROVISION_GUEST:-1}" # 1=auto-provision guest ZFS pool by default
GUEST_USER="${GUEST_USER:-$(id -un)}"   # engvm creates a guest account matching host user
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

usage() {
    # Print the leading comment block (after the shebang), stripped of '# '.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
}

# ---- helpers ----------------------------------------------------------
host_avail_gb() { awk '/^MemAvailable:/{print int($2/1024/1024)}' /proc/meminfo; }

compute_mem_gb() {
    local avail m
    avail=$(host_avail_gb)
    m=$(( avail - HOST_RESERVE_GB ))
    [ "$m" -gt "$MAX_GB" ] && m=$MAX_GB
    if [ "$m" -lt "$MIN_GB" ]; then
        echo "ERROR: only ${avail} GB available; after the ${HOST_RESERVE_GB} GB host" >&2
        echo "reserve, the guest would get < the ${MIN_GB} GB build floor. Free RAM and retry." >&2
        return 1
    fi
    echo "guest RAM: ${m} GB  (= ${avail} avail - ${HOST_RESERVE_GB} reserve, clamped to [${MIN_GB},${MAX_GB}])" >&2
    echo "$m"
}

get_ip() {  # echo the VM's IPv4 from the libvirt DHCP leases (no guest agent needed)
    virsh domifaddr "$1" --source lease 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1
}

wait_ssh() {  # poll until SSH answers (or ~3 min timeout)
    local ip="$1" i=0
    while [ "$i" -lt 60 ]; do
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
            "$GUEST_USER@$ip" true 2>/dev/null && return 0
        sleep 3; i=$(( i + 1 ))
    done
    return 1
}

vm_ensure_off() {  # graceful shutdown + wait (≤2 min)
    local vm="$1" st i=0
    st=$(virsh domstate "$vm" 2>/dev/null || echo unknown)
    [ "$st" = "shut off" ] && return 0
    virsh shutdown "$vm" >/dev/null 2>&1 || true
    while [ "$i" -lt 40 ]; do
        st=$(virsh domstate "$vm" 2>/dev/null || echo unknown)
        [ "$st" = "shut off" ] && return 0
        sleep 3; i=$(( i + 1 ))
    done
    return 1
}

running_domain_using() {  # echo a running helios-* domain that has path $1 attached
    local path="$1" d
    for d in $(virsh list --name --state-running 2>/dev/null | grep '^helios-'); do
        if virsh domblklist "$d" --details 2>/dev/null | grep -qF "$path"; then echo "$d"; return; fi
    done
}

# Create (if missing) the shared persistent data volume and attach it to $1
# as vdc. Returns non-zero (without aborting the script) on guard failure.
ensure_data_attach() {
    local vm="$1" pool volname volpath state inuse
    pool=$( . "$ENGVM_DIR/config/defaults.sh" >/dev/null 2>&1; printf '%s' "${POOL:-default}" )
    volname="${DATA_VOL}.qcow2"
    if ! virsh vol-info --pool "$pool" "$volname" >/dev/null 2>&1; then
        echo "creating shared persistent data volume $volname (${DATA_SIZE}, thin qcow2) in pool '$pool'..."
        virsh vol-create-as --pool "$pool" --capacity "$DATA_SIZE" --format qcow2 --name "$volname"
    fi
    volpath=$(virsh vol-path --pool "$pool" "$volname")
    inuse=$(running_domain_using "$volpath")
    if [ -n "$inuse" ] && [ "$inuse" != "$vm" ]; then
        echo "WARNING: data disk is in use by running VM '$inuse'; not attaching to '$vm'" >&2
        echo "(a ZFS pool must not be imported by two VMs at once). Shut '$inuse' down first." >&2
        return 1
    fi
    if virsh domblklist "$vm" --details 2>/dev/null | grep -qF "$volpath"; then
        return 0   # already attached
    fi
    state=$(virsh domstate "$vm" 2>/dev/null || echo unknown)
    echo "attaching data disk $volpath to $vm as vdc ..."
    if [ "$state" = "running" ]; then
        virsh attach-disk "$vm" "$volpath" vdc --targetbus virtio --subdriver qcow2 --persistent
    else
        virsh attach-disk "$vm" "$volpath" vdc --targetbus virtio --subdriver qcow2 --config
    fi
}

provision_data_pool() {  # run the guest setup script over SSH (idempotent)
    local vm="$1" ip
    ip=$(get_ip "$vm")
    [ -n "$ip" ] || { echo "no guest IP yet; skip pool provisioning (run again later)."; return 0; }
    wait_ssh "$ip" || { echo "guest SSH not reachable; skip pool provisioning."; return 0; }
    echo "provisioning ZFS 'data' pool in guest ($ip)..."
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$GUEST_USER@$ip" \
        "GUEST_USER='$GUEST_USER' pfexec sh -s" < "$SCRIPT_DIR/guest/setup-data-pool.sh" \
        || echo "guest pool provisioning did not complete; see the getting-started guide."
}

# Wait until the guest has a leased IP and answers SSH; echo the IP. ~4 min.
wait_guest_ready() {
    local vm="$1" ip i=0
    while [ "$i" -lt 80 ]; do
        ip=$(get_ip "$vm")
        if [ -n "$ip" ] && ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
                -o ConnectTimeout=5 "$GUEST_USER@$ip" true 2>/dev/null; then
            echo "$ip"; return 0
        fi
        sleep 3; i=$(( i + 1 ))
    done
    return 1
}

# Run engvm create.sh but suppress its final `virsh start --console`, so the
# VM starts HEADLESS and control returns to us automatically -- no "press
# Ctrl+]" step for the user. A throwaway PATH shim drops --console from the
# start command; every other virsh call passes straight through to the real
# binary. Watch first boot any time with `virsh console <vm>` if you want.
run_create_headless() {
    local shim real
    real=$(command -v virsh)
    shim=$(mktemp -d)
    cat > "$shim/virsh" <<SH
#!/bin/bash
a=(); for x in "\$@"; do [ "\$x" = "--console" ] || a+=("\$x"); done
exec "$real" "\${a[@]}"
SH
    chmod +x "$shim/virsh"
    if ! PATH="$shim:$PATH" "$ENGVM_DIR/create.sh" "$CONFIG_NAME"; then
        rm -rf "$shim"; return 1
    fi
    rm -rf "$shim"
}

print_connect_info() {
    local vm="$1" prof ip; prof=${vm#helios-}; ip=$(get_ip "$vm")
    echo
    echo "=================================================================="
    if [ -n "$ip" ]; then
        echo " VM '$vm' is ready at $ip"
        echo "   connect:  ./ssh_connect.sh $prof        (or: ssh $GUEST_USER@$ip)"
        echo "   console:  virsh console $vm             (Ctrl+] to detach)"
    else
        echo " VM '$vm' booted; IP not leased yet."
        echo "   connect:  ./ssh_connect.sh $prof        (retry in a few seconds)"
    fi
    echo "=================================================================="
}

# CLI: resize an existing VM's RAM (shut off required to change max memory).
do_set_ram() {
    local prof="$1" want="$2" vm gb kib state cfg
    [ -n "$prof" ] || { echo "usage: $0 --set-ram <profile> [GB]" >&2; exit 2; }
    vm="helios-$prof"
    virsh domstate "$vm" >/dev/null 2>&1 || { echo "no such VM: $vm" >&2; exit 1; }
    if [ -n "$want" ]; then
        gb="$want"
        local avail headroom; avail=$(host_avail_gb); headroom=$(( avail - HOST_RESERVE_GB ))
        [ "$gb" -gt "$headroom" ] && echo "warning: ${gb} GB exceeds headroom (~${headroom} GB); host may swap." >&2
    else
        gb=$(compute_mem_gb) || exit 1
    fi
    kib=$(( gb * 1024 * 1024 ))
    if [ "$(virsh domstate "$vm" 2>/dev/null)" = "running" ]; then
        echo "$vm is running; shutting it down to change max memory (save your work)..."
        vm_ensure_off "$vm" || { echo "ERROR: $vm did not shut down; 'virsh destroy $vm' then retry." >&2; exit 1; }
    fi
    echo "setting $vm RAM -> ${gb} GB (persistent)..."
    virsh setmaxmem "$vm" "$kib" --config
    virsh setmem    "$vm" "$kib" --config
    cfg="$ENGVM_DIR/config/${prof}.sh"
    [ -f "$cfg" ] && sed -i "s|^MEM=.*|MEM=\$(( $gb * 1024 * 1024 ))|" "$cfg"
    echo "Done. Boot it with: $0 $prof"
    exit 0
}

# CLI: just create+attach the data disk (the create/boot flow does this by default).
do_ensure_data() {
    local prof="$1" vm
    [ -n "$prof" ] || { echo "usage: $0 --ensure-data <profile> [SIZE]" >&2; exit 2; }
    [ -n "${2:-}" ] && DATA_SIZE="$2"
    vm="helios-$prof"
    virsh domstate "$vm" >/dev/null 2>&1 || { echo "no such VM: $vm  (create it first: $0 $prof)" >&2; exit 1; }
    ensure_data_attach "$vm" || exit 1
    echo "Data disk ensured for $vm. Boot it ($0 $prof) and the 'data' pool is provisioned automatically."
    exit 0
}

# Ensure the VM will accept an SSH key THIS host actually holds (engvm seeds
# authorized_keys from the host's, which may list only other machines' keys).
ensure_vm_keys() {
    local akf="$ENGVM_DIR/input/cpio/authorized_keys" hostkeys added=0 kb line
    hostkeys=$(ssh-add -L 2>/dev/null)
    [ -n "$hostkeys" ] || hostkeys=$(cat ~/.ssh/*.pub 2>/dev/null)
    if [ -z "$hostkeys" ]; then
        echo "warning: no usable host SSH keys; reach the VM via 'virsh console $VMNAME'." >&2
        return 0
    fi
    mkdir -p "$(dirname "$akf")"; touch "$akf"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        kb=$(awk '{print $2}' <<<"$line")
        grep -qF "$kb" "$akf" 2>/dev/null || { printf '%s\n' "$line" >> "$akf"; added=1; }
    done <<< "$hostkeys"
    [ "$added" = 1 ] && echo "Provisioned the VM's authorized_keys with this host's SSH key(s)."
}

# --- Argument handling -------------------------------------------------
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -l|--list)
        echo "Helios build VMs (libvirt domains named helios-*):"
        virsh list --all 2>/dev/null | awk 'NR<=2 || /helios-/'
        exit 0 ;;
    --ip)  shift; [ -n "${1:-}" ] || { echo "usage: $0 --ip <profile>" >&2; exit 2; }
           get_ip "helios-$1"; exit 0 ;;
    --ssh) shift; [ -n "${1:-}" ] || { echo "usage: $0 --ssh <profile>" >&2; exit 2; }
           ip=$(get_ip "helios-$1"); [ -n "$ip" ] || { echo "no IP for helios-$1 (is it running?)" >&2; exit 1; }
           exec ssh -o StrictHostKeyChecking=accept-new "$GUEST_USER@$ip" ;;
    --console) shift; [ -n "${1:-}" ] || { echo "usage: $0 --console <profile>" >&2; exit 2; }
           exec virsh console "helios-$1" ;;
    -r|--set-ram)  shift; do_set_ram "$@" ;;       # exits internally
    --ensure-data) shift; do_ensure_data "$@" ;;   # exits internally
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

PROFILE="${1:-$DEFAULT_PROFILE}"
VMNAME="helios-${PROFILE}"
CONFIG_NAME="$PROFILE"

if [ ! -x "$ENGVM_DIR/create.sh" ]; then
    echo "ERROR: helios-engvm clone not found at $ENGVM_DIR" >&2
    echo "Run infra/scripts/bootstrap.sh first (clones the upstream repos)." >&2
    exit 1
fi

# --- Existing VM: attach data disk if needed, boot headless, provision -----
if virsh domstate "$VMNAME" >/dev/null 2>&1; then
    state=$(virsh domstate "$VMNAME" 2>/dev/null || echo unknown)
    echo "VM '$VMNAME' already exists (state: $state) -- booting it (not recreating)."
    if [ "$state" != "running" ]; then
        [ "$DATA_DISK" = 1 ] && { ensure_data_attach "$VMNAME" || true; }
        virsh start "$VMNAME" >/dev/null
        echo "Waiting for the guest to accept SSH..."
        wait_guest_ready "$VMNAME" >/dev/null || echo "warning: guest slow to come up." >&2
        [ "$PROVISION_GUEST" = 1 ] && provision_data_pool "$VMNAME"
    fi
    print_connect_info "$VMNAME"
    exit 0
fi

echo "Creating new build VM '$VMNAME' (profile '$PROFILE')."

# Read ONLY the seed-image name from defaults.sh, in a subshell, so its
# VCPU/SIZE/MEM assignments cannot clobber our knobs.
INPUT_IMAGE=$( . "$ENGVM_DIR/config/defaults.sh" >/dev/null 2>&1; printf '%s' "${INPUT_IMAGE:-}" )

echo "Host memory: $(awk '/^MemTotal:/{print int($2/1024/1024)}' /proc/meminfo) GB total, $(host_avail_gb) GB available now."
echo "Memory-heavy processes competing with the build VM:"
ps -eo rss,pid,comm --sort=-rss 2>/dev/null | awk '
    NR>1 && ($3 ~ /qemu/ || $3 ~ /ollama/ || $3 ~ /boinc/) {
        printf "  %-18s pid %-7s %6.1f GB\n", $3, $2, $1/1024/1024
    }' || true
echo

mem_gb=$(compute_mem_gb) || exit 1
echo "==> vCPU: ${VCPU}   disk ceiling: ${SIZE} (thin qcow2)"

if [ ! -f "$ENGVM_DIR/input/$INPUT_IMAGE" ]; then
    echo "Seed image $INPUT_IMAGE not found -- downloading via engvm download.sh ..."
    ( cd "$ENGVM_DIR" && ./download.sh )
fi
virsh net-info default 2>/dev/null | grep -q 'Active:.*yes' || { echo "Activating libvirt 'default' network..."; virsh net-start default || true; }

cfg="$ENGVM_DIR/config/${CONFIG_NAME}.sh"
if [ -d "$ENGVM_DIR/.git" ]; then
    exclude_file="$ENGVM_DIR/.git/info/exclude"; exclude_pat="/config/${CONFIG_NAME}.sh"
    mkdir -p "$(dirname "$exclude_file")"
    grep -qxF "$exclude_pat" "$exclude_file" 2>/dev/null || \
        printf '\n# Generated by infra/scripts/vm/start-build-vm.sh (runtime artifact, never commit)\n%s\n' "$exclude_pat" >> "$exclude_file"
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

ensure_vm_keys
echo
echo "First-booting '$VMNAME' headless -- no keystrokes needed. This sets up the"
echo "guest account + swap; watch it any time with 'virsh console $VMNAME'."
run_create_headless || { echo "create.sh failed." >&2; exit 1; }

echo "Waiting for the guest to finish first boot and accept SSH (a minute or two)..."
if ! ip=$(wait_guest_ready "$VMNAME"); then
    echo "Guest didn't become reachable in time. Inspect with: virsh console $VMNAME" >&2
    print_connect_info "$VMNAME"; exit 0
fi
echo "Guest is up at $ip."

if [ "$DATA_DISK" = 1 ]; then
    echo "Attaching the persistent data disk (one quick reboot so the guest sees it)..."
    if vm_ensure_off "$VMNAME" && ensure_data_attach "$VMNAME"; then
        virsh start "$VMNAME" >/dev/null
        wait_guest_ready "$VMNAME" >/dev/null || echo "warning: guest slow to return after reboot." >&2
        [ "$PROVISION_GUEST" = 1 ] && provision_data_pool "$VMNAME"
    else
        echo "warning: couldn't attach the data disk now; do it later with: $0 --ensure-data $PROFILE" >&2
    fi
fi
print_connect_info "$VMNAME"
