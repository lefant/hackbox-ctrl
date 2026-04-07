---
date: 2026-03-30
topic: "Adopting beads and Dolt within hackbox-ctrl and toolnix"
tags: [research, beads, dolt, toolnix, hackbox-ctrl, agents, workflow]
---

# Adopting Beads And Dolt Within hackbox-ctrl And toolnix

## Purpose

Record the current design considerations for using **beads** as a durable work-tracking layer in the `toolnix` / `hackbox-ctrl` ecosystem, including what role **Dolt** actually plays, where ownership should live, and what a practical adoption path could look like.

This note is about:

- whether beads should be part of the default operator workflow
- where beads state should live
- how cross-host sync should work
- which concerns belong in `toolnix` versus `hackbox-ctrl`

This note is **not** about introducing Dolt as an independent database product for general application state. In this context, Dolt matters primarily because beads already uses it internally.

## Existing research and repo context found on this host

### Prior dedicated research

A strong existing predecessor already exists in the earlier control-plane
research history:

- `2026-03-18-beads-dolt-investigation.md` from the pre-standalone
  `hackbox-ctrl-utils` era

Its key conclusion is important:

- **beads is already Dolt-native**
- there is no separate "switch beads from sqlite to dolt" step
- the real work is packaging, initialization, remote sync, and workflow design

### Relevant repo facts in current code

#### toolnix

`toolnix` already includes beads in the shared agent baseline:

- `toolnix/modules/shared/agent-baseline.nix`
  - includes `beads` in the package set
  - exports `BEADS_NO_DAEMON=1`

That means the current shared environment already treats beads as part of the standard agent tool surface.

#### hackbox-ctrl

`hackbox-ctrl` is explicitly the control-plane toolkit for **toolnix-managed hackboxes**, not the shared agent-environment repo itself.

That means:

- `hackbox-ctrl` should not become the primary implementation home for beads packaging
- `hackbox-ctrl` may still document control-plane workflow decisions around beads
- any durable shared packaging, shell integration, or runtime defaults should live in `toolnix` first

#### historical toolbox/plugin context

Searches on this host also showed older `toolbox` and `claude-code-plugins` references where:

- beads was installed in the old toolbox image
- an older beads plugin was later removed/deprecated
- the deprecation reason was that plugin-style hook behavior did not fit the newer skills-only direction

That history suggests a useful constraint:

- beads adoption should avoid reviving a fragile plugin/hook architecture
- it should fit the current `toolnix` host-native, Nix-first environment model

## What beads and Dolt mean here

## Core finding

For this ecosystem, the right framing is:

- **beads** = user-facing issue/task/work-tracking tool
- **Dolt** = beads' storage and synchronization engine

So the adoption question is really:

- should `toolnix` / `hackbox-ctrl` standardize a beads-based workflow?
- if yes, how much should be automatic versus optional?

## Why beads is attractive here

Potential benefits:

- local-first issue tracking inside working repos
- durable multi-session context for agent-assisted work
- structured IDs that can be referenced from plans, devlogs, changelog fragments, and handovers
- cross-host synchronization through Dolt remotes
- better continuity across multiple VMs than purely local scratch notes

This matches several recurring needs already visible in the docs:

- multi-session implementation work
- explicit handover context
- issue references in devlogs and changelog fragments
- a desire for agent-friendly, machine-local but syncable state

## Why adoption still needs care

Even though the binary is already present via `toolnix`, broad adoption is not free.

Risks and costs:

- introducing another stateful local workflow to every repo may be too opinionated
- `.beads/` adds repository-local state that should usually stay gitignored
- cross-host sync requires remote design, credentials, and conflict expectations
- operators may prefer GitHub issues for some repos and beads for others
- agent tooling should not assume beads exists unless initialization and conventions are clear

## Boundary decision: what belongs in toolnix vs hackbox-ctrl

## toolnix responsibilities

`toolnix` should own the shared environment and runtime defaults for beads.

That includes:

- packaging `bd` as part of the baseline or an opt-in module
- environment defaults such as `BEADS_NO_DAEMON`
- any future Home Manager or shell integration for user-level config
- reference docs for first-run setup and operational use
- any optional helper wrappers around `bd`

## hackbox-ctrl responsibilities

`hackbox-ctrl` should own only the control-plane side of beads usage.

That includes:

- documenting whether target hosts are expected to support beads workflows
- optionally validating the presence of `bd` in readiness/smoke checks if beads becomes a declared requirement
- possibly provisioning shared credentials or config fragments if a remote sync model is standardized
- documenting inventory conventions if certain environments should enable or disable beads-related behavior

## Recommended ownership rule

**If it changes the shared shell or agent environment, it belongs in `toolnix`. If it changes fleet or provisioning policy, it belongs in `hackbox-ctrl`.**

## Adoption models considered

### Option A: leave beads as an installed but user-driven tool

Behavior:

- `toolnix` keeps shipping `bd`
- no repo is automatically initialized
- users initialize beads manually in repos where they want it
- `hackbox-ctrl` does nothing special

Pros:

- minimal risk
- no surprise `.beads/` directories
- no remote credentials to manage centrally
- works immediately with current `toolnix`

Cons:

- inconsistent usage across hosts and repos
- no standard cross-host workflow
- docs/process references to beads remain weak or ambiguous

### Option B: standardize beads as an optional documented workflow

Behavior:

- `toolnix` still ships `bd`
- selected repos opt into a documented beads workflow
- docs define how to initialize `.beads/`, add remotes, and use issue IDs in related docs
- `hackbox-ctrl` may track which environments/repositories are expected to use beads

Pros:

- strong balance between consistency and flexibility
- no forced state in every repo
- easiest migration path from the current state
- aligns with current architecture boundaries

Cons:

- still requires disciplined human adoption
- some workflow fragmentation remains

### Option C: make beads part of the default repo bootstrap

Behavior:

- entering or provisioning a repo auto-initializes `.beads/`
- helper scripts may auto-configure remotes or seed config
- docs and process assume beads exists everywhere

Pros:

- maximum consistency
- easiest for agents to rely on once established

Cons:

- too opinionated for all repos at the current maturity level
- adds local mutable state automatically
- risks repeating the old plugin/hook overreach
- harder to explain and maintain across mixed repo types

## Recommendation on adoption model

The best near-term path is **Option B: standardize beads as an optional documented workflow**.

That means:

- keep beads available in `toolnix`
- do not auto-create `.beads/` in every repo
- document a recommended opt-in setup for repos where durable local issue tracking is useful
- let `hackbox-ctrl` remain mostly neutral except where provisioning/readiness policy explicitly needs to mention beads

## Where beads state should live

## Per-repo state is the clean default

The cleanest default is:

- each participating repo has its own `.beads/`
- `.beads/` remains local mutable state
- `.beads/` should generally be gitignored rather than committed

Why this fits best:

- work tracking often maps naturally to one codebase
- repo-local state makes context discovery straightforward
- it avoids creating one giant shared task database with blurry ownership
- it aligns with beads' natural initialization model (`bd init` in a repo)

## Cross-host sync should be per logical workspace

If the same repo is worked on from multiple VMs, that repo's beads state can use a remote.

Good principle:

- one beads/Dolt remote per repo or per clearly defined workspace
- avoid one global remote for every repo and host unless a strong reason emerges

## Remote/sync choices

Based on existing research, the main realistic remote options are:

### DoltHub

Pros:

- purpose-built for Dolt
- browser UI and database visibility
- straightforward mental model

Cons:

- separate service/account surface
- another auth system to manage

### Git SSH remote

Pros:

- reuses existing GitHub/Git SSH patterns
- likely easier to fit into current lefant workflows
- avoids introducing a new SaaS dependency if unnecessary

Cons:

- somewhat less purpose-built than DoltHub
- operational understanding may be weaker

## Recommended remote direction

If cross-host sync becomes a real requirement, the first thing to test should be:

- **Git SSH remote for beads state**, reusing existing SSH/GitHub access patterns

Why:

- it fits the current environment better than introducing a whole new hosted dependency immediately
- `hackbox-ctrl` and `toolnix` already assume git/ssh-based workflows heavily
- it keeps authentication closer to the existing operator model

DoltHub is still a valid fallback or later upgrade if web visibility becomes important.

## Current implications for toolnix

`toolnix` already appears close to the right minimum baseline:

- beads is installed in the agent package set
- daemon behavior is already constrained via `BEADS_NO_DAEMON=1`

Possible next `toolnix` improvements:

1. add a short reference doc for beads first-run usage
2. document where `.beads/` should live and that it is mutable local state
3. document a recommended remote-sync setup
4. decide whether beads should remain baseline or move behind an opt-in module
5. if adoption increases, add a small helper command or shell function for status/discovery

## Current implications for hackbox-ctrl

`hackbox-ctrl` should stay light unless and until beads becomes part of declared environment policy.

Possible future `hackbox-ctrl` work only if needed:

1. optional readiness assertion that `bd` is available on beads-enabled environments
2. optional inventory metadata saying a project/environment expects beads
3. optional credential distribution guidance if a shared remote model is adopted
4. operator docs describing whether beads is expected for handovers or multi-session work

## What should not happen yet

The current evidence does **not** support these moves yet:

- forcing beads initialization for every repo during provisioning
- storing one monolithic fleet-wide beads database in `hackbox-ctrl`
- making `hackbox-ctrl` the implementation home for beads packaging or runtime config
- assuming every project must use beads instead of GitHub issues or markdown task systems

## Proposed phased adoption path

### Phase 1: document the real current state

In docs:

- record that beads is already available via `toolnix`
- record that beads already uses Dolt internally
- record that adoption is optional and repo-local

### Phase 2: prove one real workflow

Choose one repo with repeated multi-session work and:

- run `bd init`
- create a few real issues
- establish conventions for referencing beads IDs in devlogs/handovers/plans
- verify the workflow feels better than pure markdown/GitHub for that repo

### Phase 3: prove cross-host sync

On two real hosts for the same repo:

- add a Dolt remote
- push from one host
- pull from another
- verify conflict behavior and operational friction
- document the exact preferred remote type and auth model

### Phase 4: decide whether to standardize more broadly

After proving actual use:

- keep beads merely available, or
- make it a documented recommended default for certain repo classes, or
- add a small amount of explicit `hackbox-ctrl` readiness/provisioning support

## Open questions

- Should beads remain part of the always-on `toolnix` agent baseline, or become opt-in?
- Which repos in the lefant ecosystem actually benefit enough from beads to justify standardization?
- Should `.beads/` always be repo-local, or are there cases where a shared host-level beads store is useful?
- Is Git SSH remote support mature and ergonomic enough for the preferred sync path?
- Do we want beads IDs to become first-class references in `hackbox-ctrl` docs and process templates, or stay informal?
- If a repo uses both GitHub issues and beads, what is the intended division of responsibility?

## Recommended current stance

Adopt the following stance for now:

1. **Beads is available through `toolnix`, not through `hackbox-ctrl`.**
2. **Dolt should be treated as beads' internal storage/sync engine, not as a separate general platform decision.**
3. **Repo-local opt-in beads usage is the default recommendation.**
4. **Cross-host sync should be proven experimentally before being standardized.**
5. **Any broader workflow standardization should be documented in `toolnix` first and reflected in `hackbox-ctrl` only when it becomes part of explicit control-plane policy.**

## References

- `toolnix/modules/shared/agent-baseline.nix`
- `hackbox-ctrl/docs/decisions/2026-03-28_adopt-toolnix-as-primary-shared-nix-repo.md`
- historical `2026-03-18-beads-dolt-investigation.md` from the pre-standalone control-plane research set
- `/home/exedev/git/lefant/toolnix/docs/research/2026-03-28-toolnix-self-hosted-environment-review.md`
- `/home/exedev/sources/claude-code-plugins/docs/plans/2026-02-04-lefant-claude-code-plugins-updates.md`
