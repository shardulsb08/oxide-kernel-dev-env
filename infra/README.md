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
