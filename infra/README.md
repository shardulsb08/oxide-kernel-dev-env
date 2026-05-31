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

Sizes and launches the Helios build VM via the helios-engvm clone's
`create.sh`. It picks guest RAM from live host availability
(`MemAvailable - HOST_RESERVE_GB`, clamped to `[MIN_GB, MAX_GB]`), so a
long illumos build won't starve the desktop. Knobs (RAM floor/cap, host
reserve, vCPU, disk size) are at the top of the script.

```
$ infra/scripts/vm/start-build-vm.sh
```

It writes one generated file into the clone --
`$ENGVM_DIR/config/build.sh` -- because `create.sh` only reads its VM
config from its own `config/<name>.sh`. That file is a regenerated
runtime artifact; the launcher adds it to the clone's
`.git/info/exclude` itself (idempotent, self-healing on a fresh clone),
so the clone stays pristine. The launcher itself stays here in the
tracked repo.

Prerequisites: the helios-engvm clone present under
`src/vm/helios-engvm`, libvirt/QEMU installed, and your user in the
`libvirt` group (see that clone's README).
