# infra/ -- workspace automation (tracked)

Local tooling and automation glue for the `oxide_computer` workspace.
Unlike the upstream clones under `src/` (which are public Oxide mirrors,
gitignored from this repo, and must stay pristine), everything here is
**tracked in the workspace-root repo** -- it is ours to maintain. Scripts
reference the clones by path; they never live inside them.

This mirrors the `mpiric_kernel_dev_env/infra` pattern: a central
`config.sh` locates the workspace and exports canonical paths, and the
scripts source it instead of hard-coding absolute paths.

## Layout

```
infra/
  README.md                this file
  scripts/
    config.sh              workspace-root detection + path exports
    vm/
      start-build-vm.sh     launch the Helios build VM with dynamic RAM sizing
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

### Persistent data disk (survives VM recreate)

The build runs on the guest's local ZFS for speed, but a VM's root disk
is wiped on `destroy.sh`/recreate. To keep your work, use a **separate
persistent data disk**:

```
$ infra/scripts/vm/start-build-vm.sh --ensure-data dev          # 200G default
$ infra/scripts/vm/start-build-vm.sh --ensure-data dev 300G     # explicit size
```

This creates a standalone `helios-data.qcow2` volume (NOT named
`<vm>.qcow2`, so `destroy.sh` never deletes it) and attaches it to
`helios-dev` as `vdc`. In the guest, put a ZFS pool on it once and work
there:

```
# diskinfo                       # find the new disk (likely c3t0d0)
# pfexec zpool create data c3t0d0
# pfexec zfs create data/helios  # clone + build under /data/helios
```

After a VM recreate, the volume persists -- just `--ensure-data` again to
reattach, then `pfexec zpool import data` in the guest. Reach the data
from the host (while the VM runs) via sshfs/NFS.

Caveats:
- **One VM at a time.** A ZFS pool must not be imported by two running
  VMs simultaneously (corruption). `--ensure-data` refuses to attach the
  disk if another running `helios-*` VM already holds it.
- **Git is the real safety net.** The disk protects WIP/build caches;
  push illumos-gate commits to a remote so published work can't be lost.
- The volume lives in the libvirt `default` pool (`/`). For more room set
  `DATA_VOL`/`DATA_SIZE` or relocate the pool to `/mnt/work_4gb` (see the
  disk note above; non-default pool paths may need an AppArmor allow).

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
