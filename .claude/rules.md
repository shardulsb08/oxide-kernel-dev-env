# Shared rules & considerations (oxide_computer)

**Auto-referred by every session.** The workspace-root `CLAUDE.md`
instructs all sessions -- this root repo *and* every nested `src/` clone
(the root `CLAUDE.md` auto-loads up the directory tree) -- to read this
file at session start. It is the **single home for abstract,
cross-cutting rules**, so they are not duplicated across the per-repo
`CLAUDE.md` files. Repo-specific facts and constraints stay in each
repo's own `CLAUDE.md`; only rules that apply broadly belong here.

## 1. Every session (root repo and all `src/` clones)

**Keep context current -- milestone cadence, ask first.** Proactively
keep the active repo's context docs in sync with what the work changes
(CLAUDE.md sections, `.claude/` principles|designs|workspace files, task
registries/briefs, project memory) -- but **ask before writing**, at
**milestone** granularity, not every iteration. High-intensity dev/debug
sessions need not pause at each step; at a natural checkpoint (a new
convention or workflow, a structural/build change, a notable decision or
debugging insight, a task start/finish, or just before a likely stopping
point) pause and **offer** the update -- don't write silently, and don't
skip. The goal is resilience to abrupt session closure, so the next
session recovers the majority of the context. When unsure whether
something is milestone-worthy, ask rather than skip.

## 2. Inside any `src/` upstream clone (NOT the root repo)

Each `src/<group>/<repo>` is a clone of a **public upstream Oxide repo**.
For any session working inside one:

- **Never commit the Claude scaffold.** A clone's `CLAUDE.md` +
  `.claude/` live in that clone's `.git/info/exclude` (per-clone, never
  tracked). Never add them to a commit, and never push local scaffolding
  or experiments onto a branch that could be pushed upstream.
- **You are in the `oxide_computer` workspace.** Workspace-level facts
  (layout, the two-tier tracking model, sibling repos, adding a clone)
  are **on-demand** in
  `/mnt/work_4gb/Dev/oxide_computer/.claude/workspace.md` -- read only
  when the work is cross-repo or about the workspace itself, not for
  ordinary repo-local work.

*(The root repo itself is exempt from section 2: it deliberately tracks
its Claude scaffold for collaboration.)*
