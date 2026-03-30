# 2026-03-30 Hackbox-Ctrl Convergence

## Summary

Started the standalone `hackbox-ctrl` convergence pass after the `toolnix`
refactor stream reached a stable checkpoint.

This pass focused on repo-local coherence rather than new provisioning
mechanics.

## What Landed

- added a standalone convergence plan:
  - `docs/plans/2026-03-30-hackbox-ctrl-convergence.md`
- added the missing durable decision doc:
  - `docs/decisions/2026-03-16_adopt-composable-project-environments.md`
- fixed the broken link from:
  - `docs/specs/project-environment-manifest.md`
- rewrote the root `README.md` so the standalone repo explains:
  - its role relative to `toolnix`
  - the nested `hackbox-ctrl-inventory` contract
  - common control-plane entrypoints
  - the current generated Home Manager bootstrap model

## Repo-Local Findings

Current repo state already includes:

- first extracted provisioning/readiness scripts
- generated Home Manager bootstrap provisioning
- readiness specs/reference docs
- `toolnix`-first architectural direction

The most obvious remaining gap at this checkpoint was documentation coherence,
not absence of a provisioning path.

## Next Likely Step

Use the standalone repo itself as the primary validation path and confirm the
current scripts/docs still match real execution on the active VM set:

- `lefant-toolnix`
- `lefant-toolbox-nix`
- `lefant-toolbox-nix2`
