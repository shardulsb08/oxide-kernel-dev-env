# Oxide Computer development workspace

A local workspace for working on [Oxide Computer](https://oxide.computer)
software -- primarily Helios, the illumos distribution that powers the
Oxide Rack, and its surrounding tooling. The layout mirrors the
structured approach used in the kernel development workspace at
`/mnt/work_4gb/Dev/mpiric_kernel_dev_env` (a `src/` tree of upstream
clones, each carrying its own Claude Code session scaffold).

## Directory structure

```
oxide_computer/                  git repo (tracks the lines below)
├── README.md                    this file
├── CLAUDE.md                    workspace-level context for Claude Code
├── .claude/                     workspace Claude scaffold (canonical methodology)
├── .gitignore                   ignores the src/** clones + build artifacts
└── src/                         upstream source clones, grouped by role
    │                            (gitignored; each cloned individually)
    ├── os/
    │   └── helios/              Helios OS build orchestrator
    │                            (github.com/oxidecomputer/helios)
    └── vm/
        └── helios-engvm/        VM / host provisioning for Helios dev
                                 (github.com/oxidecomputer/helios-engvm)
```

The workspace root is its **own git repo** and tracks the docs +
workspace Claude scaffold. Each clone under `src/` is a **separate
mirror of a public Oxide repository**, downloaded individually and
gitignored from the root repo. Build artifacts, project checkouts, and
VM images created by the tools stay inside their respective clones (each
repo gitignores its own outputs).

## The two repos and how they relate

- **`src/os/helios`** -- the build driver. It clones several upstream
  consolidations (illumos-gate, omnios build/extra, phbl, image-builder,
  ...) and builds them into a shippable Helios OS and bootable images,
  via the `helios-build` Rust tool. Builds must run on an illumos host.
  See `src/os/helios/README.md`.
- **`src/vm/helios-engvm`** -- the provisioning companion. It stands up
  a Helios virtual machine (Linux libvirt/KVM/QEMU, or Intel-Mac VMware
  Fusion) or a physical host that you then use as the illumos build
  machine for `src/os/helios`. See `src/vm/helios-engvm/README.md`.

Typical flow: provision a Helios VM with **helios-engvm**, then build OS
packages and images inside it with **helios**.

## Claude Code session scaffolding

Every repo under `src/` carries a `CLAUDE.md` + `.claude/` session
scaffold so Claude Code sessions start with the right context without
re-explanation. The methodology's **collaborative canonical** lives in
this root repo at `.claude/SESSION_SETUP_PATTERN.md` (tracked, so it
survives a clone of the root); each `src/` clone carries its own
self-contained copy and a `.claude/README.md` that adapts it.

Tracking is **two-tier**:
- **This root repo tracks Claude data** (`README.md`, `CLAUDE.md`, the
  whole root `.claude/`) -- it's the home for workspace-level
  collaboration.
- **Each `src/` clone keeps its scaffold per-clone** via that clone's
  `.git/info/exclude`, because the clone tracks a **public** Oxide repo
  and nothing Claude-related should ever land on a branch headed
  upstream. The clones are also gitignored from this root repo (they're
  downloaded individually).

## Conventions borrowed from the kernel workspace

The kernel workspace adds an `infra/` tree (shared scripts +
`config.sh` exporting workspace paths) and a `shared/` scratch area.
This workspace does not have those yet -- they should be added only when
a real need appears (e.g. cross-repo build/run scripts), not
speculatively.
