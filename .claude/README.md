# `.claude/` -- workspace-level Claude scaffold (oxide_computer)

This is the **workspace-root** Claude scaffold, distinct from the
per-clone scaffolds that live inside each repo under `src/`. It holds:

```
.claude/
  README.md                  this file
  SESSION_SETUP_PATTERN.md   the workspace canonical methodology (tracked)
```

## Two tiers of scaffold

- **This root scaffold is tracked** in the workspace-root git repo. The
  root repo is for collaboration, so Claude data is welcome here. A
  contributor who clones the root gets the canonical methodology
  (`SESSION_SETUP_PATTERN.md`) and the workspace `CLAUDE.md`/`README.md`.
- **Per-clone scaffolds** (`src/os/helios/.claude/`,
  `src/vm/helios-engvm/.claude/`, and any future `src/` clone) are
  **not** tracked -- each clone tracks a public upstream Oxide repo, so
  its scaffold is kept per-clone via that clone's `.git/info/exclude`
  and must never reach a branch headed upstream. Those clones are also
  gitignored from this root repo (they're downloaded individually).

See `SESSION_SETUP_PATTERN.md` ("What's tracked in git vs not") for the
full rationale.

## Why the canonical lives here

The methodology was originally developed in the microkernel repo. Within
this workspace, the tracked, collaborative copy is here at the root --
so it survives `git clone` of the root repo even though the `src/`
clones (which each carry their own self-contained copy) do not. When the
pattern changes, update the microkernel canonical first, then this
workspace copy, then the per-clone copies.

## Sessions opened at the workspace root

If a session starts here (rather than inside a specific clone), the
root `CLAUDE.md` orients it: it describes the `src/` layout and points
into the per-clone `CLAUDE.md` files for repo-specific work. Task
registries live per-clone (`src/*/<repo>/.claude/users/...`), not at the
root -- workspace-level multi-session tasks are rare; add a root
`users/` tree only if one actually appears.
