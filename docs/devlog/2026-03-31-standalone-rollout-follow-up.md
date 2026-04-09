---
date: 2026-03-31
status: 🔄 PARTIAL
related_spec: docs/specs/control-host-and-target-agent-readiness.md
related_adr: docs/decisions/2026-03-28_adopt-toolnix-as-primary-shared-nix-repo.md
related_plan: docs/plans/2026-03-30-hackbox-ctrl-convergence.md
related_research: docs/research/2026-03-27-exe-dev-state-backups.md
related_issues: []
---

# Implementation Log - 2026-03-31

**Implementation**: Follow up the standalone `hackbox-ctrl` rollout, migrated-host cleanup, tmux/Pi reliability fixes, and control-plane convergence audit.

## Summary

This session continued the standalone `hackbox-ctrl` track after the initial convergence baseline. The main outcomes were: rolling the current `toolnix` update across active `devenv` targets; removing remaining Docker/toolbox fallback from `lefant-memory`, `lingontuvan-stadbokning`, and the on-host `altego-agent-now` checkout; debugging nested `tmux-here` failures down to stale project-socket tmux state on `lefant-memory` and `altego-agent-now`; refreshing Pi auth on `altego-agent-now`; and auditing whether standalone `hackbox-ctrl` still depends on older `toolbox` or `hackbox-ctrl-utils` repository shapes. The control-plane conclusion is that the standalone `hackbox-ctrl` repo is operationally sufficient for the current host-native path, but migration-era compatibility and local source-checkout assumptions remain. The next strategic focus should now return to improving provisioning reliability for initial deployment without a control host, and only then continue the cleanup of extra local repository checkouts.

## Plan vs Reality

**What was planned:**
- [ ] Continue host-native rollout of the latest `toolnix` changes to active targets
- [ ] Finish migrated-host acceptance and cleanup work
- [ ] Decide whether old toolbox-era control-plane checkouts are still required
- [ ] Improve Pi reliability and host readiness signal quality

**What was actually implemented:**
- [x] Pulled and rolled the current `toolnix` revision including Pi default reasoning alignment to the active `devenv` host set
- [x] Finished project-local Docker/toolbox fallback removal for `lefant-memory` and `lingontuvan-stadbokning`
- [x] Added the same thin host-native `toolnix` + `devenv` entrypoint shape to `altego-agent-now` on-host and removed its local toolbox Docker fallback there
- [x] Verified acceptance-style evidence for `lefant-memory` and `lingontuvan-stadbokning` host-native shells, tools, `devenv`, `tmux-here`, Claude, and Codex
- [x] Diagnosed `tmux-here` failures on `lefant-memory` and `altego-agent-now` as stale project tmux server/socket state rather than broken host-native setup
- [x] Fixed the stale tmux condition on those hosts by killing the old project socket/server state
- [x] Refreshed Pi auth on `altego-agent-now`, restarted the broken Pi tmux pane, and restored a healthy interactive Pi session there
- [x] Audited `hackbox-ctrl` completeness and concluded the active standalone path does not require the old private `toolbox` control-plane model
- [x] Removed active-doc references to `tooling/hackbox-ctrl-utils` from standalone `hackbox-ctrl` and inventory entry docs
- [ ] Eliminate remaining compatibility assumptions around local source checkouts and control-host-centric provisioning
- [ ] Normalize remaining `TOOLBOX_MODE` / `env.toolbox` compatibility naming

## Challenges & Solutions

**Challenges encountered:**
- Several hosts still carried stale nested tmux state, which made `tmux-here` fail with `open terminal failed: not a terminal` even though the shell function existed and host-native setup looked healthy.
- Shared Pi auth copied from inventory had drifted behind the current working local auth and caused `openai-codex` refresh-token reuse failures inside long-lived tmux sessions.
- `altego-agent-now` could be migrated structurally on-host, but repo rules blocked direct push to `main`, so upstream landing was out of scope for the control-plane work itself.
- Convergence analysis showed the standalone repo is mostly sufficient, but some scripts and docs still assume local inventory-side source mirrors such as `sources/toolnix`.

**Solutions found:**
- Treated stale tmux server/socket state as the primary issue and fixed it directly (`tmux -L <project> kill-server` plus socket cleanup) instead of over-rotating on shell quoting or tty diagnosis.
- Replaced the stale shared Pi auth with the newer working local auth and explicitly restarted the Pi pane in the remote tmux session.
- Continued treating upstream repo landing separately from host-local structural migration, which kept the control-plane work moving even when GitHub rules blocked direct pushes.
- Wrote a completeness audit that distinguishes what is operationally required today (`hackbox-ctrl`, inventory, and `toolnix`) from what is mostly historical context (`toolbox` control-plane assumptions, `hackbox-ctrl-utils` subtree references, proof checkouts).

## Learnings

- Nested tmux failures on migrated hosts can be caused by stale project socket state even when `tmux-here`, interactive `zsh`, and ssh `-tt` all appear correct.
- Pi auth breakage can persist inside an existing tmux pane after credential files are refreshed; restarting the actual interactive Pi process matters.
- Standalone `hackbox-ctrl` is already good enough for the current host-native control-plane path, so the main remaining convergence work is reliability and assumption cleanup rather than missing core functionality.
- The largest remaining architectural smell is not `toolbox` itself; it is the continued assumption that provisioning starts from a control-host-shaped workspace with pre-existing local checkouts.

## Next Steps

- [ ] Focus next on improving provisioning reliability for initial deployment without a control host and without assuming pre-existing extra repository checkouts
- [ ] After that reliability work lands, return to the convergence task and remove/relax remaining local source-checkout assumptions such as inventory-local `sources/toolnix`
- [ ] Decide whether `agent-skills` and `claude-code-plugins` should stay as direct cloned host inputs or move behind a more declarative `toolnix`-owned distribution model
- [ ] When ready, continue auditing whether `sources/toolbox` and other local proof/history checkouts can be retired from the normal workflow entirely
