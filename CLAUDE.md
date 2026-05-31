# CLAUDE.md -- oxide_computer workspace

Workspace-level entry point for Claude Code. This is the root of a local
workspace for Oxide Computer software (Helios + tooling), organized as a
`src/` tree of upstream clones, each carrying its own per-repo
`CLAUDE.md`. See `README.md` for the human-facing overview and
`.claude/SESSION_SETUP_PATTERN.md` for the session-setup methodology.

> **This root is its own git repo** and *does* track Claude data (it's
> the collaborative home for the workspace scaffold). The nested clones
> under `src/` are gitignored and downloaded individually. Do **not**
> confuse this with the per-clone rule: inside each `src/` clone the
> scaffold is per-clone via `.git/info/exclude` and must never be
> committed upstream.

## Where work actually happens

This root is a meta layer. Repo-specific work happens inside the clones,
each of which has its own `CLAUDE.md`, task registry, and principles:

| Path                      | Repo (`origin`)                  | What it is                                              |
|---------------------------|----------------------------------|---------------------------------------------------------|
| `src/os/helios`           | `oxidecomputer/helios`           | Helios OS build orchestrator (illumos consolidations)   |
| `src/vm/helios-engvm`     | `oxidecomputer/helios-engvm`     | VM / host provisioning for Helios development           |

When the user's request is about building/running Helios, open or read
the relevant clone's `CLAUDE.md` first -- that's where the build
commands, design principles, and task registry live. Typical flow:
provision a Helios VM with **helios-engvm**, then build OS packages and
images inside it with **helios**.

## Task system

Tasks live **per-clone**, not here:
`src/<group>/<repo>/.claude/users/<name>/tasks/index.md`. When work
targets a specific repo, read that clone's task index (and follow its
"ask before loading a brief" rule). Workspace-level multi-session tasks
are rare; if one appears, add a `users/` tree under this root `.claude/`
and record it here.

## Design principles (workspace-wide)

- **Two-tier tracking.** This root repo tracks Claude data for
  collaboration; every `src/` clone keeps its scaffold per-clone
  (`.git/info/exclude`) because each tracks a public upstream Oxide
  repo. Never commit scaffold/experiments onto a branch headed upstream.
- **Clones are downloaded individually.** `src/**` is gitignored from
  the root repo. Adding a new repo means: clone it under `src/<group>/`,
  add its path to the root `.gitignore`, and bootstrap its per-clone
  scaffold (see `.claude/SESSION_SETUP_PATTERN.md`, "Bootstrapping").
- **Don't add infra speculatively.** The sibling kernel workspace has
  `infra/` (shared scripts + `config.sh`) and `shared/`; add the
  equivalent here only when a real cross-repo need appears.

## Codebase facts

- **Not a code repo** -- this root holds organization, docs, and the
  workspace Claude scaffold. Builds/tests run inside the `src/` clones.
- **Modeled on** `/mnt/work_4gb/Dev/mpiric_kernel_dev_env` (a `src/`
  tree of upstream clones under a tracked root repo).
- **Layout:** `src/os/helios`, `src/vm/helios-engvm` (see the table
  above and `README.md`).

## Always-load at session start

- `~/.claude/projects/-mnt-work-4gb-Dev-oxide-computer/memory/MEMORY.md`
  (index; individual memories load on trigger). Currently minimal.
