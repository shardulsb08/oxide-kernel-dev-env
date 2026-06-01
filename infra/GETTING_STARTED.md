# Getting started: Helios build VM

End-to-end, from a fresh workspace to a Helios guest with a persistent
data disk ready for kernel work. The build runs **inside** the guest (an
illumos host); your Linux box is only the hypervisor.

Prerequisites on the Linux host: libvirt + QEMU (`sudo apt install
virt-manager`), your user in the `libvirt` group, and an SSH key loaded
in your agent (`ssh-add -l` should list at least one).

## 1. Clone the upstream repos

```bash
cd /mnt/work_4gb/Dev/oxide_computer
infra/scripts/bootstrap.sh
```

Clones `oxidecomputer/helios-engvm` (drives the VM) and
`oxidecomputer/helios` (build orchestrator / scaffold reference) under
`src/`. Idempotent -- skips anything already present.

## 2. Create and boot the build VM

```bash
infra/scripts/vm/start-build-vm.sh           # profile 'dev' -> VM helios-dev
```

This is **hands-off** -- no keystrokes. It:
- sizes guest RAM from live host memory (clamped to `[8,16]` GB; ~12 GB typical),
- gives the VM 12 vCPU and a 200 GB thin disk,
- downloads the seed image on first run (~2.5 GB, once),
- provisions a usable SSH key,
- **boots the guest headless**, waits for it to come up, then attaches the
  persistent data disk and provisions the ZFS pool automatically,
- prints how to connect when done.

(Want to watch first boot? `virsh console helios-dev` in another terminal,
`Ctrl+]` to detach -- optional, not required.)

Multiple build images? Use profiles: `start-build-vm.sh test` ->
`helios-test` (independent VM + root disk). `--list` shows them. Note only
one VM at a time may use the shared data pool.

## 3. Find and connect to the VM

```bash
./ssh_connect.sh                # SSH into helios-dev (default profile; any terminal)
./ssh_connect.sh dev 3          # open 3 terminals, each SSH'd in
./ssh_connect.sh test           # SSH into the 'test' profile's VM
```

`ssh_connect.sh` resolves the VM's leased IP for you. Equivalent built-ins
(profile defaults to `dev`):

```bash
infra/scripts/vm/start-build-vm.sh --ssh        # SSH straight in
infra/scripts/vm/start-build-vm.sh --ip         # just print the IP
infra/scripts/vm/start-build-vm.sh --console    # serial console (Ctrl+] to detach)
```

## 4. The persistent data disk

A separate `helios-data.qcow2` (not part of any VM's root image) is
attached as `vdc` and survives `destroy.sh`/recreate. By default the
launcher provisions a ZFS pool `data` on it and a `data/helios` dataset,
and clones Helios into `/data/helios` for building. After a VM recreate,
the launcher reattaches the disk and re-imports the pool automatically --
your work is intact.

- One VM at a time may import the pool (the launcher refuses to attach it
  to a second running VM).
- Reach the data from the host (while the VM runs) via sshfs/NFS.
- **Push commits to a git remote** -- the disk protects WIP/caches, but a
  published fork is the real safety net.

Opt out of the automatic disk/pool: `DATA_DISK=0` or `PROVISION_GUEST=0`.

## 5. Build illumos (Phase 1)

One command from the host builds it inside the guest (profile defaults to `dev`):

```bash
infra/scripts/vm/build-helios.sh
```

It SSHes into `helios-dev` and runs `guest/build-helios.sh`, which:
1. installs build deps (`/developer/build-essential`, `/developer/illumos-tools`, Rust via rustup) if missing,
2. clones Helios into `/data/helios/helios` if not already there,
3. `gmake setup OXIDE_STAFF=no` -- clones the consolidations (illumos-gate
   `stlouis`, omnios `helios3`, ...) and builds the `helios-build` tool (once),
4. `gmake illumos` -- a quick illumos build.

Output streams live and is teed to `infra/build-logs/build-dev.log` (gitignored).
Artifacts land in the guest at `/data/helios/helios/projects/illumos/packages/i386`.

This is long-running (tens of minutes to a couple of hours, depending on
cores/disk/network -- `gmake setup` clones several GB). It's idempotent:
re-run if SSH drops (setup is skipped once `./helios-build` exists). For a
detach-proof run, do it inside `tmux` in the guest:

```bash
./ssh_connect.sh dev
tmux new -s build
cd /data/helios/helios && gmake illumos      # or run build-helios.sh's steps
```

## 6. The kernel edit -> build -> test loop (Phase 1+)

**One command for the whole cycle** (rebuild + repackage -> `onu` ->
cold-boot into the new BE, console captured):

```bash
infra/scripts/vm/test-kernel.sh            # edit source first; run in a real terminal
./ssh_connect.sh                           # after it boots, verify your change
```

The manual steps are below for understanding. **The #1 gotcha:** `onu`
installs from the *package repo*, so you must **rebuild/repackage**
(`build-helios.sh`, or `test-kernel.sh` which does it) after editing -- a
bare `dmake install` only updates the proto area, and `onu` will then
install a *stale* kernel without your change.


The illumos source lives in the guest at
`/data/helios/helios/projects/illumos/usr/src` (= `$SRC` inside bldenv):

| Path | What |
|------|------|
| `uts/common/`  | architecture-independent kernel (drivers in `io/`, filesystems in `fs/`, networking in `inet/`, dtrace, ...) |
| `uts/intel/`   | x86 ISA-common (e.g. `genunix`) |
| `uts/i86pc/`   | **the standard PC platform -- what this QEMU VM runs** (`unix`, platform code) |
| `uts/oxide/`   | the Oxide rack platform (real hardware) |
| `cmd/`, `lib/` | userland commands and libraries |

Compile-check a change fast with the quick build environment (rebuilds
only what changed):

```bash
./ssh_connect.sh                       # into the guest
cd /data/helios/helios
./helios-build bldenv -q               # interactive build shell; drops you in $SRC

# inside bldenv (pwd is .../usr/src):
vi uts/common/os/main.c                # edit a kernel source file
cd uts && dmake -S -m serial install   # build + stage into the PROTO area
exit
```

IMPORTANT: run `dmake` from **`uts/`** (or a module's build dir under
`uts/intel` / `uts/i86pc`), NOT the leaf source dir -- `uts/common/os` has
no `install` target.

**`dmake install` only updates the proto area.** `onu` installs from the
IPS package repo (`projects/illumos/packages/i386/nightly-nd`), which the
`uts/` build does NOT refresh -- so repackage first, or `onu` installs a
STALE build. The reliable way is to re-run the quick build (incremental
rebuild AND repackage):

```bash
infra/scripts/vm/build-helios.sh       # from the HOST: gmake illumos = build + repackage
# then, in the guest:
./ssh_connect.sh
cd /data/helios/helios
./helios-build onu -t my-change        # assemble a BE from the FRESH packages
pfexec poweroff                        # clean shutdown -- do NOT use `reboot` (see below)
# back on the HOST, cold-boot into the new BE:
infra/scripts/vm/boot-with-log.sh      # (or start-build-vm.sh) -- full power-cycle
```

**Use a cold boot (poweroff + start), NOT `pfexec reboot`, to switch BEs.**
On x86, illumos `reboot` does a *fast reboot* (loads the next kernel
directly, bypassing the firmware + loader); in this QEMU setup that wedges
the guest (running but no console/network). A full power-cycle goes through
the loader and boots the new BE cleanly. (Validated 2026-06-01:
`pfexec reboot` -> wedge; `poweroff` + cold start -> booted the self-built
`stlouis-0-g…` kernel fine.)

After reboot, reconnect and check `uname -v` (should no longer be the seed
`helios-3.0.23976`), then `dmesg | grep ...`.

**To debug a boot** (e.g. a new BE that won't come up): the normal start is
headless, so use the logged cold-boot helper instead -- it attaches the
serial console from power-on and captures the whole boot to a timestamped
file:

```bash
# in the guest, after onu: pfexec poweroff      (clean shutdown, not reboot)
infra/scripts/vm/boot-with-log.sh dev            # cold-start with console + log
#   watch the loader/kernel live; Ctrl+] to detach once up.
#   full boot saved to infra/serial-logs/helios-dev-<timestamp>.log
```

If the new BE won't boot/network, recover by selecting the previous BE at
the loader, or destroy + recreate the VM (your work on `/data` survives;
`zpool import -f data` reattaches it).

(`./helios-build onu --help` for options; the Helios README "Making
changes" has the full walkthrough.)

Preserve your work: commit under `projects/illumos` and **push to your
GitHub fork of illumos-gate**. The VM and even the data disk are
replaceable; published commits are the durable record -- and a clean,
reviewable commit/PR is the actual deliverable for the hiring goal.

## 7. Kernel logging & debug prints

illumos's `printk` family is **`cmn_err(9F)`** (and `dev_err(9F)` in
drivers). The Linux mapping:

| Linux            | illumos                       | Output prefix |
|------------------|-------------------------------|---------------|
| `pr_info`/`pr_notice` | `cmn_err(CE_NOTE, "...")` | `NOTICE:` |
| `pr_warn`        | `cmn_err(CE_WARN, "...")`     | `WARNING:` |
| `pr_cont`/plain  | `cmn_err(CE_CONT, "...")`     | (none)        |
| `panic`          | `cmn_err(CE_PANIC, "...")` / `panic()` | panic |
| driver-context   | `dev_err(dip, CE_WARN, ...)`  | includes the device |

(`<sys/cmn_err.h>` is already included in most kernel files.)

**Boot-ordering gotcha:** a `cmn_err()` near the top of `main()`
(`uts/common/os/main.c`) runs *before* `main()` calls `startup()` (~line
476), which is what initializes the message buffer `dmesg` reads. Such an
early message shows on the **console** (and in `boot-with-log.sh`'s capture)
but **not in `dmesg`**. Put the call *after* `startup()`, or in a module's
`_init()`, to have it land in both. (Confirmed 2026-06-01: a `cmn_err` at
main.c:455 printed to console but not `dmesg`.)

Reading the log -- the `dmesg` equivalents:

```bash
dmesg | tail                      # the kernel message buffer (like Linux dmesg)
tail -f /var/adm/messages         # FOLLOW live  (your `dmesg -w`)
```

There's no `dmesg -c`; just note the timestamp, or truncate as root
(`pfexec sh -c ': > /var/adm/messages'`). For non-invasive tracing of a
running kernel, `dtrace`/`mdb` are usually better than adding prints.

Quick round-trip to see a message: add `cmn_err(CE_NOTE, "kdev: hi from
main()");` in `uts/common/os/main.c` (in `main()`, after the
`ASSERT_STACK_ALIGNED();` line), rebuild that component, `onu -t kdev`,
reboot, then `dmesg | grep kdev`.

## Other operations

```bash
infra/scripts/vm/start-build-vm.sh --set-ram dev 14   # resize RAM (shuts VM down)
(cd src/vm/helios-engvm && ./destroy.sh dev)          # tear down a VM (data disk survives)
```

See `infra/README.md` for the launcher's knobs and internals.
