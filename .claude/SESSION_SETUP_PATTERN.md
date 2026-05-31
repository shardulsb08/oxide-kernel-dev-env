# Session-setup pattern -- workspace canonical (oxide_computer)

**Status:** Methodology developed 2026-05-02 with Shardul, applied to
the Linux-clone working tree on 2026-05-08, to BRF on 2026-05-14, and to
this `oxide_computer` workspace on 2026-05-31. This copy is the
**collaborative canonical** for the workspace -- it is tracked in the
workspace-root git repo so a contributor who clones only the root gets
the methodology. The per-clone scaffolds under `src/` carry their own
self-contained copies (the clones are downloaded individually and are
gitignored from the root repo). Per-deployment deviations are recorded
at the bottom of each scaffold's README, not by silently diverging this
body.

## What problem this solves

In a repo with non-trivial domain context (here: the illumos
consolidation/build model in `src/os/helios`, the VM-provisioning
tooling in `src/vm/helios-engvm`), Claude sessions otherwise need to be
told the same things every time:

- Who the user is and how they work
- The codebase conventions
- What is currently being worked on
- Which design principles flip "obvious" defaults
- Which past decisions matter

Re-explaining this is a tax on every session. The pattern below encodes
it in files Claude reads automatically or on-trigger, so the first turn
of a new session is productive instead of preparatory.

## The layout (per repo)

```
<repo>/
  CLAUDE.md                            always-loaded entry point
  .claude/
    README.md                          explains THIS repo's layout
    SESSION_SETUP_PATTERN.md           this methodology (per-clone copy)
    settings.local.json                Claude Code local settings
    principles/<aspect>.md             short design-principle files (read on trigger)
    designs/<subject>.md               technical / recipe docs (read on trigger)
    users/                             per-user working memory
      README.md
      .contributors                    one line per active collaborator
      <name>/
        tasks/index.md                 registry: status, keywords, brief path
        tasks/<slug>/CLAUDE.md         task brief
        notes/                         free-form per-session notes
    archive/README.md                  retired memories with index
```

## What goes in repo-root `CLAUDE.md`

Five sections, in order:

1. **Task system.** Read the active user's
   `.claude/users/<name>/tasks/index.md` at session start; ask before
   loading any task brief; propose status updates on task switch.
2. **Design principles.** 3-5 invariants that drive non-obvious
   decisions. Short. The kind that flip "conservative" defaults.
3. **Auto-loaded references** trigger table. Rows mapping work
   conditions to files Claude reads *without asking*, announcing each
   load. Includes `.claude/principles/*.md`, `.claude/designs/*.md`, and
   specific memory files.
4. **Always-load at session start.** A small list (4-6) of universal
   memories read on the first turn. Keep tight -- per-session cost.
5. **Codebase facts.** Build/run commands, architecture, constraints.
   The output of `/init`, trimmed.

## Asymmetric loading rules

| Class                    | Load when                       | Behavior                                         |
|--------------------------|---------------------------------|--------------------------------------------------|
| Repo-root `CLAUDE.md`    | Always                          | Auto                                             |
| `MEMORY.md` index        | Always                          | Auto                                             |
| Always-load memories     | Session start                   | Auto (per CLAUDE.md instruction)                 |
| Principle / design files | Work matches trigger            | Auto + announce                                  |
| Task brief               | User mentions task keywords     | **Ask first**, then auto-load referenced files   |
| Other memories           | Mentioned by name or grep need  | On demand                                        |

Principles are short and decision-shaping (cheap to load, high judgment
value). Briefs are larger and task-specific (should not contaminate
unrelated work).

## What's tracked in git vs not

This workspace has two tiers:

**Workspace-root repo** (this directory, `oxide_computer/`): tracks
`README.md`, `CLAUDE.md`, and the whole root `.claude/` (this file +
the root README). Claude data is welcome here -- the root repo is for
collaboration. The nested `src/**` clones are **gitignored** (downloaded
individually).

**Per-clone scaffolds** (`src/os/helios`, `src/vm/helios-engvm`, and any
future clone under `src/`): the clone's `origin` is a **public upstream
Oxide repo**, so the clone's entire `CLAUDE.md` + `.claude/` tree goes
in that clone's `.git/info/exclude` -- per-clone, never committed, so it
can never appear on a branch headed upstream. This is the
"upstream-mirror clones" exception; it is the operative mode for every
`src/` clone.

## Adding a new design principle

1. Create `.claude/principles/<aspect>.md` (or `designs/<subject>.md`).
   First line: a "Read this when:" trigger phrase. Keep dense and
   focused -- read into context, so density wins over completeness.
2. Add a row to the "Auto-loaded references" table in that repo's
   `CLAUDE.md`.
3. Cross-link from related memory files.

## Adding a new task

1. Create `.claude/users/<your-name>/tasks/<task_slug>/CLAUDE.md` (the
   brief): goal, scope/anti-scope, memory-load list (critical / helpful
   / skip), key files, working principles, open questions.
2. Add an entry to `.claude/users/<your-name>/tasks/index.md` with
   status, keywords, brief path, one-line goal. `status: active` if
   it's the current focus.
3. When done: `status: done`. Don't delete the brief immediately. Move
   to `.claude/archive/` with an index entry if worth preserving.

**What counts as "active":** a task is active if it has open threads --
including waiting on stakeholder input, hardware, review, or external
CI -- not only when code is being typed.

## When to apply this pattern (to new repos)

Apply when the repo has at least two of: strong implicit conventions a
newcomer wouldn't infer; recurring tasks with distinct scope;
multi-session work that gets dropped and resumed; decision drivers that
flip naive intuition. Skip for small/exploratory repos.

## Bootstrapping the pattern in a new `src/` clone

1. Run `/init` (or assemble manually from the repo's README/Makefile).
2. Insert the four pre-codebase sections (Task system, Design
   principles, Auto-loaded references, Always-load).
3. Write `.claude/principles/<aspect>.md` only for principles a real
   session has shown are needed -- never speculatively.
4. Populate the trigger table.
5. Copy `.claude/README.md` and this `SESSION_SETUP_PATTERN.md` from an
   existing `src/` clone as templates; adapt.
6. **Upstream-mirror exception:** add `/CLAUDE.md` and `/.claude/` to
   the clone's `.git/info/exclude` (not `.gitignore`). Create
   `.claude/users/README.md` + `.claude/users/.contributors`.
7. Add the clone's path to the **workspace-root `.gitignore`** so the
   root repo ignores it.
8. Create the first contributor's
   `.claude/users/<name>/tasks/index.md` when the first multi-session
   task appears.

## Cross-machine sync

- The workspace-root repo travels via `git pull` (it tracks the root
  scaffold + this canonical).
- The `src/**` clones are fetched individually (`git clone`), and their
  per-clone scaffolds are local-only (`.git/info/exclude`) -- copy them
  manually between machines if needed.
- `.claude/users/<name>/tasks/` is per-machine regardless.
- Memory files sync separately per the global `reference_memory_sync.md`.

## Maintenance

Living documentation. When the pattern evolves: update the *microkernel*
canonical copy first (the original source), refresh this workspace copy,
then refresh the per-clone copies. Update each repo-root `CLAUDE.md` if
its always-loaded surface changes.

## Workspace-specific notes

- **Two-tier tracking** (above) is the defining deviation: the root repo
  tracks Claude data for collaboration; every `src/` clone keeps its
  scaffold per-clone via `.git/info/exclude` because each tracks a
  public upstream Oxide repo.
- The original canonical lives in the microkernel repo; this copy and
  the per-clone copies descend from it.
