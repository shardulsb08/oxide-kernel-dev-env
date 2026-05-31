# infra/ -- workspace automation (tracked)

Local tooling and automation glue for the `oxide_computer` workspace.
Unlike the upstream clones under `src/` (which are public Oxide mirrors,
gitignored from this repo, and must stay pristine), everything here is
**tracked in the workspace-root repo** -- it is ours to maintain. Scripts
reference the clones by path; they never live inside them.

This mirrors the `mpiric_kernel_dev_env/infra` pattern: a central
`config.sh` locates the workspace and exports canonical paths, and the
scripts source it instead of hard-coding absolute paths.

**New here? See [GETTING_STARTED.md](GETTING_STARTED.md)** for the
clone -> boot -> connect -> build walkthrough.

## Layout

```
infra/
  README.md                this file
  GETTING_STARTED.md       end-to-end walkthrough
  scripts/
    config.sh              workspace-root detection + path exports
    bootstrap.sh           clone the upstream repos into src/
    vm/
      start-build-vm.sh     create/boot the build VM (RAM sizing, data disk, provisioning)
      guest/
        setup-data-pool.sh  runs IN the guest: import/create the ZFS data pool
```

## config.sh

Source it from any script (`source "$SCRIPT_DIR/../config.sh"`). It
detects `OXIDE_WS_ROOT` from its own location (override with the env var)
and exports `SRC_DIR`, `HELIOS_DIR`, `ENGVM_DIR`, `INFRA_DIR`,
`SCRIPTS_DIR`. Run `source infra/scripts/config.sh && oxide_printvars`
to see them.

## scripts/vm/start-build-vm.sh

Creates or boots a named Helios build VM via the helios-engvm clone's
`create.sh`. It picks guest RAM from live host availability
(`MemAvailable - HOST_RESERVE_GB`, clamped to `[MIN_GB, MAX_GB]`), so a
long illumos build won't starve the desktop.

### Profiles (multiple build images)

A **profile** names an independent VM + disk, so you can keep several
build images side by side -- the Helios analog of the kernel env's
`BUILD_PROFILE`/`KBUILDDIR` (there a profile names a build *dir*; here a
whole *VM*).

```
$ infra/scripts/vm/start-build-vm.sh            # profile 'dev'  -> VM helios-dev
$ infra/scripts/vm/start-build-vm.sh test       # profile 'test' -> VM helios-test
$ OXIDE_VM_PROFILE=exp infra/scripts/vm/start-build-vm.sh
$ infra/scripts/vm/start-build-vm.sh --list      # list existing helios-* VMs
```

- Profile from the first arg, else `$OXIDE_VM_PROFILE`, else `dev`.
- Each profile -> libvirt domain `helios-<profile>` with its own qcow2
  disk; profiles coexist (RAM permitting).
- **Re-running an existing profile BOOTS it, never recreates it** --
  recreating would wipe that VM's disk and lose the build inside. To
  rebuild from the seed image:
  `(cd $ENGVM_DIR && ./destroy.sh <profile>) && start-build-vm.sh <profile>`.

### Resizing an existing VM's RAM

```
$ infra/scripts/vm/start-build-vm.sh --set-ram dev        # re-size from live host RAM
$ infra/scripts/vm/start-build-vm.sh --set-ram dev 14     # set explicitly to 14 GB
```

libvirt requires the domain shut off to change max memory (the engvm
domain has no hotplug slots), so this gracefully shuts the VM down, sets
`maxmem`+`mem` persistently, and syncs the profile's generated config.
Boot it again afterward with `start-build-vm.sh <profile>`.

### Persistent data disk (automatic; survives VM recreate)

The build runs on the guest's local ZFS for speed, but a VM's root disk
is wiped on `destroy.sh`/recreate. So the launcher, **by default**,
attaches a separate persistent data disk and provisions a ZFS pool on it:

- A standalone `helios-data.qcow2` (NOT named `<vm>.qcow2`, so
  `destroy.sh` never deletes it) is attached as `vdc`.
- The guest script `guest/setup-data-pool.sh` runs over SSH to **import**
  the `data` pool if it exists (the case after a recreate), or **create**
  it on a single blank disk if not, make the `data/helios` dataset, and
  clone Helios into `/data/helios`.
- After a VM recreate the launcher reattaches the disk and re-imports the
  pool automatically -- your work is intact.

No flags needed -- it happens on create and on every boot. The
`--ensure-data <profile> [SIZE]` subcommand just does the attach step on
its own (e.g. to add the disk to a VM created with `DATA_DISK=0`).

```
$ infra/scripts/vm/start-build-vm.sh                 # data disk + pool: automatic
$ DATA_DISK=0 infra/scripts/vm/start-build-vm.sh     # skip the data disk entirely
$ PROVISION_GUEST=0 infra/scripts/vm/start-build-vm.sh  # attach disk, skip guest provisioning
$ infra/scripts/vm/start-build-vm.sh --ensure-data dev 300G  # just (re)attach, 300G
```

Caveats:
- **One VM at a time.** A ZFS pool must not be imported by two running
  VMs simultaneously (corruption). The launcher refuses to attach the
  disk to a VM if another running `helios-*` VM already holds it.
- **Conservative create.** The guest script only *creates* a pool when it
  finds exactly one blank, large, non-root disk; otherwise it aborts and
  asks you to create it by hand (it never guesses a disk).
- **Git is the real safety net.** The disk protects WIP/build caches;
  push illumos-gate commits to a remote so published work can't be lost.
- The volume lives in the libvirt `default` pool (`/`). For more room set
  `DATA_VOL`/`DATA_SIZE`, or relocate the pool to `/mnt/work_4gb` (set
  `POOL` in the profile config; non-default pool paths may need an
  AppArmor allow).

### Finding and connecting to a VM

```
$ infra/scripts/vm/start-build-vm.sh --ip  dev    # print the VM's IP (from DHCP leases)
$ infra/scripts/vm/start-build-vm.sh --ssh dev    # SSH straight in
$ virsh console helios-dev                          # serial console (Ctrl+] to detach)
```

### SSH access

engvm's `create.sh` seeds the guest from your host's
`~/.ssh/authorized_keys`, which often lists keys from *other* machines
(whose private halves aren't on this host). The launcher therefore
appends this host's agent identities (`ssh-add -L`, falling back to
`~/.ssh/*.pub`) to the provisioning file, so a key you actually hold is
accepted and `ssh <user>@<vm-ip>` just works. If your agent is empty,
load it (`ssh-add`) before creating, or use `virsh console <vm>` (the dev
image has an empty root password).

### Knobs (env-overridable per run)

`MIN_GB`, `MAX_GB`, `HOST_RESERVE_GB`, `VCPU`, `SIZE` default at the top
of the script and can be overridden per run:

```
$ VCPU=8 SIZE=100G HOST_RESERVE_GB=12 infra/scripts/vm/start-build-vm.sh test
```

### Generated clone artifact

For each profile the launcher writes `$ENGVM_DIR/config/<profile>.sh`
(because `create.sh` only reads its VM config from its own
`config/<name>.sh`). These are regenerated runtime artifacts; the
launcher adds each to the clone's `.git/info/exclude` itself (idempotent,
self-healing on a fresh clone), so the clone stays pristine. The launcher
itself stays here in the tracked repo.

> Disk note: each profile's qcow2 is thin (a 200 GB virtual ceiling that
> grows on demand) and lands in the libvirt `default` pool
> (`/var/lib/libvirt/images` on `/`). Several fully-built VMs can add up;
> if `/` gets tight, point a libvirt pool at `/mnt/work_4gb` and set
> `POOL` in the profile config.

Prerequisites: the helios-engvm clone present under
`src/vm/helios-engvm`, libvirt/QEMU installed, and your user in the
`libvirt` group (see that clone's README).
