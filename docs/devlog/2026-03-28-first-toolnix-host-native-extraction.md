# 2026-03-28 First Toolnix Host-Native Extraction

## Summary

Seeded the first standalone `hackbox-ctrl` slice from the old shared subtree and
made it runnable against a nested `hackbox-ctrl-inventory` checkout.

## What Landed

- copied the first durable docs:
  - inventory architecture
  - project environment manifest
  - readiness spec and reference
  - bucket-layering and toolnix-primary decisions
- copied the first host-native scripts:
  - `scripts/lib/provision-common.sh`
  - `scripts/lib/smoke-tests.sh`
  - `scripts/provision-exe-dev-nix.sh`
  - `scripts/seed-host-claude-config.sh`
  - `scripts/target-ssh.sh`
  - `scripts/verify-general-machine-readiness.sh`
  - `scripts/verify-control-host-readiness.sh`

## Adaptations

- scripts now default to `./hackbox-ctrl-inventory` via
  `HACKBOX_CTRL_INVENTORY_ROOT`
- script help text now points at `hackbox-ctrl/scripts/...` instead of the old
  subtree path
- smoke tests are now explicitly host-native `devenv` checks rather than mixed
  Docker and host-native logic
- provisioning prefers `env.toolnix` and `env.toolnix.fragment`, with fallback
  support for existing `env.toolbox` names
- Claude config seeding is toolnix-first
- readiness guidance now reflects the current Pi bindings:
  - follow-up queue: `Alt-Q`
  - restore/edit queued: `Alt-Up`, `Alt-P`

## Validation

Validated directly from `~/git/lefant/hackbox-ctrl` against:

- `lefant-toolbox-nix.exe.xyz`
- `lefant-toolbox-nix2.exe.xyz`
- `lefant-toolnix.exe.xyz`

Smoke suite result on both hosts:

- `gh auth`
- tool presence
- Stockholm timezone
- `devenv shell` entry
- shared skills
- Claude prompt ping
- Codex prompt ping
- Pi prompt ping
- Pi keybinding config

All passed.

## Smoke Runner Follow-Up

The first `lefant-toolnix` smoke attempt exposed a bug in the extracted
smoke-runner wrapper rather than in the host itself.

Cause:

- remote commands were executed through the remote default shell instead of the
  managed `zsh -il` path

Fix:

- wrap remote smoke-test commands with `zsh -ilc ...`

After that change:

- `lefant-toolnix` smoke tests passed
- `lefant-toolbox-nix` still passed as a regression check

## Follow-Up

- continue replacing copied subtree-era docs with `hackbox-ctrl`-native wording
- migrate the next script slice, especially control-host bootstrap and any
  remaining inventory path assumptions
- expand validation from the current three proven hosts to `lefant-ctrl` and
  then a small toolnix-managed production subset
