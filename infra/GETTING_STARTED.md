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
./ssh_connect.sh                # SSH into helios-dev (run in any terminal)
./ssh_connect.sh dev 3          # open 3 terminals, each SSH'd in
./ssh_connect.sh test           # SSH into the 'test' profile's VM
```

`ssh_connect.sh` resolves the VM's leased IP for you. Equivalent built-ins:

```bash
infra/scripts/vm/start-build-vm.sh --ssh dev      # SSH straight in
infra/scripts/vm/start-build-vm.sh --ip  dev      # just print the IP
infra/scripts/vm/start-build-vm.sh --console dev  # serial console (Ctrl+] to detach)
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

One command from the host builds it inside the guest:

```bash
infra/scripts/vm/build-helios.sh dev
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

For actual kernel changes, iterate inside the guest with the quick build
environment (much faster than a full build):

```bash
cd /data/helios/helios
gmake bldenv                                  # interactive quick build env (dmake)
# inside bldenv:
cd projects/illumos/usr/src/uts/<component>   # e.g. a kernel module/driver
dmake -S -m serial install                    # build + stage to the proto area
cd $SRC/pkg && dmake install                  # regenerate packages
```

Then apply the freshly built packages to the running guest and reboot to
test (see the Helios README "Making changes" for `helios-build onu`
specifics). Commit your illumos-gate work under
`projects/illumos` and **push to your GitHub fork** -- that's the durable
record (the VM and even the data disk are replaceable; published commits
aren't).

## Other operations

```bash
infra/scripts/vm/start-build-vm.sh --set-ram dev 14   # resize RAM (shuts VM down)
(cd src/vm/helios-engvm && ./destroy.sh dev)          # tear down a VM (data disk survives)
```

See `infra/README.md` for the launcher's knobs and internals.
