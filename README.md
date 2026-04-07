# hackbox-ctrl

Standalone control-plane toolkit for toolnix-managed hackboxes.

This repo owns the shared control-plane layer around provisioning, readiness,
and inventory-driven host operations.

It does **not** own:

- generic shared Nix environment logic — that lives in [`toolnix`](https://github.com/lefant/toolnix)
- private target facts, credentials, and logs — those live in the separate
  local `hackbox-ctrl-inventory` checkout

## Repo layout

```text
~/git/lefant/hackbox-ctrl/
├── scripts/
├── docs/
└── hackbox-ctrl-inventory/
```

The scripts in this repo assume that nested layout by default. Override it with
`HACKBOX_CTRL_INVENTORY_ROOT` if needed.

## What lives here

- `scripts/` — tracked shared control-plane scripts
- `docs/specs/` — control-plane and readiness requirements
- `docs/decisions/` — durable architecture decisions
- `docs/reference/` — operator-facing validation notes
- `docs/plans/` — active implementation plans
- `docs/devlog/` — dated implementation outcomes

## What the nested inventory checkout provides

The local `hackbox-ctrl-inventory/` checkout is the composition root for
instance-specific state.

Expected examples there include:

- `targets/<fqdn>/config.env`
- `credentials/shared/env.toolnix`
- `credentials/targets/<fqdn>/env.toolnix.fragment`
- local secret material such as shared agent auth and SSH keys
- target-specific logs under `logs/`

This repo intentionally does not track those private inputs.

## Common commands

Provision or reprovision a project target VM from the standalone repo:

```bash
scripts/provision-exe-dev-nix.sh <target-fqdn>
```

Provision a host-only toolnix target with no target-side `toolnix` git clone:

```bash
scripts/provision-toolnix-host.sh <target-fqdn>
```

SSH to a configured target using inventory target metadata:

```bash
scripts/target-ssh.sh <target-name-or-fqdn>
```

Print the interactive readiness procedure for a general machine:

```bash
scripts/verify-general-machine-readiness.sh <target-name>
```

Print the interactive readiness procedure for the control host:

```bash
scripts/verify-control-host-readiness.sh [target-name]
```

## Current model

### Project-target path

The active project-target host-native path is:

1. read target metadata from `hackbox-ctrl-inventory`
2. place credentials and bootstrap inputs on the target
3. clone the declared project repo and shared repos
4. generate a tiny per-host Home Manager bootstrap flake
5. activate persistent host state via `toolnix.homeManagerModules.default`
6. run smoke tests and then interactive acceptance checks

### Host-only toolnix path

The host-only bootstrap path is:

1. read target metadata from `hackbox-ctrl-inventory`
2. place credentials and bootstrap inputs on the target
3. invoke the tracked `toolnix` bootstrap script on the target
4. consume `toolnix` through its remote flake interface
5. activate persistent host state via `toolnix.homeManagerModules.default`
6. run host-bootstrap readiness checks without requiring a project checkout

## Start here

Recommended reading order:

- `docs/specs/hackbox-ctrl-inventory-architecture.md`
- `docs/specs/project-environment-manifest.md`
- `docs/specs/control-host-and-target-agent-readiness.md`
- `docs/reference/readiness-validation.md`
- `docs/plans/2026-03-30-hackbox-ctrl-convergence.md`
