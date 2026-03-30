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

## Validation

Validated from the standalone `~/git/lefant/hackbox-ctrl` repo with:

- `HACKBOX_CTRL_INVENTORY_ROOT=/home/exedev/git/lefant/hackbox-ctrl-inventory`
- sourced `scripts/lib/provision-common.sh`
- sourced `scripts/lib/smoke-tests.sh`

Smoke coverage passed for:

- `lefant-toolnix.exe.xyz`
- `lefant-toolbox-nix.exe.xyz`
- `lefant-toolbox-nix2.exe.xyz`

Per-host smoke results all passed for:

- GitHub auth
- required tools present
- Stockholm timezone
- `devenv` environment entry
- shared skills presence
- Claude prompt ping
- Codex prompt ping
- Pi prompt ping
- Pi keybindings config

Also verified standalone helper behavior:

- `scripts/target-ssh.sh --list` enumerates inventory targets correctly when
  `HACKBOX_CTRL_INVENTORY_ROOT` points at the sibling inventory checkout
- `scripts/verify-general-machine-readiness.sh lefant-toolnix` renders the
  expected interactive acceptance procedure from the standalone repo
- `scripts/verify-control-host-readiness.sh lefant-toolnix` renders the control
  host acceptance procedure

## Next Likely Step

If a stronger closure checkpoint is wanted, the next step should be interactive
acceptance evidence from the standalone repo path for:

- `lefant-toolnix`
- one toolbox-era migrated VM
- the active control host workflow
