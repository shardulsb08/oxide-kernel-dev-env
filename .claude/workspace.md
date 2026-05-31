# Workspace layout, repos, and tracking model (oxide_computer)

Read this when the work is **cross-repo or workspace-level**: the
directory organization, how the repos relate, the git-tracking model, or
adding/bootstrapping a new clone. For work inside a single repo, the
repo's own `CLAUDE.md` is enough -- you don't need this file.

This is the Claude-facing detailed context the minimal root `CLAUDE.md`
points to. The human-facing version is the root `README.md`; the
session-scaffold methodology is `.claude/SESSION_SETUP_PATTERN.md`.

## What this workspace is

`/mnt/work_4gb/Dev/oxide_computer` is a local workspace for Oxide
Computer software (Helios + tooling), its **own git repo**, modeled on
`/mnt/work_4gb/Dev/mpiric_kernel_dev_env`: a `src/` tree of upstream
clones grouped by role, under a tracked root.

```
oxide_computer/                  git repo (tracks docs + workspace .claude/)
├── README.md  CLAUDE.md  .gitignore
├── .claude/                     workspace scaffold (this file, methodology, README)
└── src/                         upstream clones (gitignored; cloned individually)
    ├── os/helios/               Helios OS build orchestrator (oxidecomputer/helios)
    └── vm/helios-engvm/         VM/host provisioning   (oxidecomputer/helios-engvm)
```

## The repos and how they relate

| Path                  | Repo (`origin`)              | Role                                                  |
|-----------------------|------------------------------|-------------------------------------------------------|
| `src/os/helios`       | `oxidecomputer/helios`       | Build driver: clones illumos consolidations and builds them into a Helios OS + images (`helios-build`, illumos host only). |
| `src/vm/helios-engvm` | `oxidecomputer/helios-engvm` | Provisions a Helios VM (Linux libvirt/QEMU or Intel-Mac VMware) or physical host to build on. |

Typical flow: provision a Helios VM with **helios-engvm**, then build OS
packages/images inside it with **helios**.

## Two-tier git-tracking model (the defining rule)

- **Root repo tracks Claude data.** `README.md`, `CLAUDE.md`, and the
  whole root `.claude/` (this file + methodology + README) are tracked
  in the `oxide_computer` repo -- it's the collaborative home. Only
  `.claude/settings.local.json` is gitignored (per-machine).
- **Each `src/` clone keeps its scaffold per-clone.** The clone's
  `origin` is a public upstream Oxide repo, so its entire `CLAUDE.md` +
  `.claude/` tree goes in that clone's `.git/info/exclude` -- never
  committed, so it can't reach a branch headed upstream. The clones
  themselves are **gitignored** from the root repo (downloaded
  individually). This is the "upstream-mirror clones" exception in
  `.claude/SESSION_SETUP_PATTERN.md`.

## Adding a new clone

1. Clone it under `src/<group>/<repo>/`.
2. Add its path to the root `.gitignore` (next to the existing
   `/src/os/helios/` etc.).
3. Bootstrap its per-clone scaffold per `.claude/SESSION_SETUP_PATTERN.md`
   ("Bootstrapping the pattern in a new `src/` clone") -- including
   adding `/CLAUDE.md` and `/.claude/` to the clone's `.git/info/exclude`.

## Conventions

- **Tasks live per-clone**, not at the root:
  `src/<group>/<repo>/.claude/users/<name>/tasks/index.md`. Workspace-
  level multi-session tasks are rare; add a root `.claude/users/` tree
  only if one actually appears.
- **Don't add `infra/` / `shared/` speculatively.** The sibling kernel
  workspace has them (shared scripts + `config.sh`); add the equivalent
  here only when a real cross-repo need appears.
