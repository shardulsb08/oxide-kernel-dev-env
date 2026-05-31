#!/bin/bash
#
# ssh_connect.sh -- SSH into a Helios build VM. Run it in any terminal; run it
# again in another for a second session. (Analogous to mpiric_kernel_dev_env's
# ssh.sh, but resolves the VM's DHCP-leased IP automatically.)
#
#   ./ssh_connect.sh [profile] [N]
#
#   profile   build-VM profile (default 'dev' -> domain helios-dev)
#   N         optional: open N terminals, each SSH'd in (uses your terminal
#             emulator: terminator / gnome-terminal / x-terminal-emulator)
#
# Examples:
#   ./ssh_connect.sh                # ssh into helios-dev in this terminal
#   ./ssh_connect.sh dev 3          # open 3 terminals into helios-dev
#   ./ssh_connect.sh test           # ssh into helios-test

set -o pipefail

profile="${1:-dev}"
n="${2:-1}"
vm="helios-${profile}"
user="${GUEST_USER:-$(id -un)}"

ip=$(virsh domifaddr "$vm" --source lease 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
if [ -z "$ip" ]; then
    echo "No leased IP for '$vm'. Is it running?  (virsh list --all)" >&2
    echo "Start it with: ./infra/scripts/vm/start-build-vm.sh ${profile}" >&2
    exit 1
fi

sshcmd="ssh -o StrictHostKeyChecking=accept-new ${user}@${ip}"

if ! [ "$n" -ge 2 ] 2>/dev/null; then
    exec $sshcmd
fi

# N >= 2: fan out into separate terminal windows.
term=$(command -v terminator || command -v gnome-terminal || command -v x-terminal-emulator || true)
if [ -z "$term" ]; then
    echo "No known terminal emulator found. Run this in each terminal:" >&2
    echo "    $sshcmd" >&2
    exit 1
fi

echo "Opening $n terminals into $vm ($ip) via $(basename "$term")..."
i=0
while [ "$i" -lt "$n" ]; do
    case "$(basename "$term")" in
        gnome-terminal) "$term" -- bash -lc "$sshcmd" >/dev/null 2>&1 & ;;
        *)              "$term" -e "$sshcmd"          >/dev/null 2>&1 & ;;  # terminator / x-terminal-emulator
    esac
    i=$(( i + 1 ))
done
wait 2>/dev/null || true
