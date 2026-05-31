# CLAUDE.md -- oxide_computer workspace (root)

This is the root of a local multi-repo workspace for Oxide Computer
software (Helios + tooling). It is its own git repo; the upstream code
clones live under `src/` (gitignored, cloned individually).

> **Keep this file minimal -- by design.** It auto-loads into every
> session running in a nested `src/` clone (Claude Code walks up the
> directory tree), so it must stay cheap. Do **not** grow it with
> workspace detail; put that in the on-demand `.claude/` files below and
> add a pointer here instead. Future sessions: respect this.

## Shared rules -- read at the start of EVERY session

**Every session must read `/mnt/work_4gb/Dev/oxide_computer/.claude/rules.md`
at the start** -- this root repo *and* every nested `src/` clone session
(this file auto-loads up the directory tree, so the requirement reaches
clone sessions too). `rules.md` is the single home for abstract,
cross-cutting rules (context-maintenance cadence; upstream-clone
hygiene), kept there instead of duplicated across per-repo `CLAUDE.md`
files. Repo-specific facts stay in each repo's own `CLAUDE.md`.

## Where to look (read on demand -- only when the work needs it)

| For...                                                        | Read |
|---------------------------------------------------------------|------|
| Workspace layout, the repos and how they relate, the two-tier git-tracking model, adding/bootstrapping a new clone | `.claude/workspace.md` |
| The session-setup scaffold methodology (per-repo `CLAUDE.md` + `.claude/` pattern) | `.claude/SESSION_SETUP_PATTERN.md` |
| Human-facing overview of the workspace                        | `README.md` |
| Repo-specific build/run/tasks (the usual case)                | that clone's own `CLAUDE.md`, e.g. `src/os/helios/CLAUDE.md`, `src/vm/helios-engvm/CLAUDE.md` |

The clones today: `src/os/helios` (Helios OS build orchestrator) and
`src/vm/helios-engvm` (VM/host provisioning). Repo work happens inside
the clones -- start from the relevant clone's `CLAUDE.md`. Tasks and
memories are per-clone, not here.

(Cross-cutting working rules -- including the milestone context-update
cadence -- live in `.claude/rules.md`, required above, not inline here.)
