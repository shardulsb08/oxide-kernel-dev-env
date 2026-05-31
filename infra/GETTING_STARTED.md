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

This:
- sizes guest RAM from live host memory (clamped to `[8,16]` GB; ~12 GB typical),
- gives the VM 12 vCPU and a 200 GB thin disk,
- downloads the seed image on first run (~2.5 GB, once),
- provisions a usable SSH key, then boots the guest.

The guest prints its own SSH line during first boot. **Press `Ctrl+]`** to
detach the console -- the launcher then attaches the persistent data disk
and provisions the guest ZFS pool automatically.

Multiple build images? Use profiles: `start-build-vm.sh test` ->
`helios-test` (independent VM + root disk). `--list` shows them. Note only
one VM at a time may use the shared data pool.

## 3. Find and connect to the VM

```bash
infra/scripts/vm/start-build-vm.sh --ip  dev    # print the VM's IP
infra/scripts/vm/start-build-vm.sh --ssh dev    # SSH straight in
# or manually:
ssh "$(id -un)@$(infra/scripts/vm/start-build-vm.sh --ip dev)"
# console instead of SSH:
virsh console helios-dev                         # Ctrl+] to detach
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

## 5. Build Helios (inside the guest -- Phase 1)

```bash
ssh "$(id -un)@$(infra/scripts/vm/start-build-vm.sh --ip dev)"
# in the guest:
cd /data/helios
gmake setup OXIDE_STAFF=no       # clone consolidations + build the tool (public path)
gmake illumos                    # quick illumos build
gmake bldenv                     # interactive incremental (dmake) build env
```

## Other operations

```bash
infra/scripts/vm/start-build-vm.sh --set-ram dev 14   # resize RAM (shuts VM down)
(cd src/vm/helios-engvm && ./destroy.sh dev)          # tear down a VM (data disk survives)
```

See `infra/README.md` for the launcher's knobs and internals.
