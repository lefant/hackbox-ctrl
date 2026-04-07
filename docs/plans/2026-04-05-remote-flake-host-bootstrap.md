# Plan: remote-flake toolnix host bootstrap from hackbox-ctrl

## Date

2026-04-05

## Goal

Add a control-host-driven bootstrap path that can provision a fresh exe.dev VM with `toolnix` host config and local credentials without cloning `toolnix` on the target machine.

Related artifacts:

- `toolnix/docs/specs/fresh-environment-bootstrap.md`
- `toolnix/docs/specs/llm-agents-cache-bootstrap.md`
- `toolnix/docs/decisions/2026-04-05_use-remote-flake-bootstrap-for-toolnix.md`
- `toolnix/docs/decisions/2026-04-05_use-public-resource-flake-inputs.md`

## Desired end state

1. `toolnix` publishes a small tracked bootstrap script that can:
   - install Nix if needed
   - configure the Numtide cache prerequisite for exeuntu/Determinate multi-user Nix
   - render a minimal standalone Home Manager bootstrap flake from parameters
   - activate `toolnix.homeManagerModules.default`

2. `hackbox-ctrl` provides a control-host wrapper that can:
   - create or reach a target exe.dev VM
   - upload machine-local credentials such as `~/.env.toolnix` and auth files
   - invoke the tracked `toolnix` bootstrap script on the target
   - run host-bootstrap readiness checks without requiring a project repo checkout

3. the proof path is verified on one or more fresh exe.dev VMs using no target-side git clone of `toolnix`

## Scope

### In scope

- `toolnix` bootstrap artifact for host bootstrap
- `hackbox-ctrl` control-host wrapper for credentials injection + remote execution
- host-bootstrap readiness checks focused on host config and managed agent state
- fresh exe.dev proof runs and iteration until passing

### Out of scope for this slice

- redesign of full project checkout provisioning
- replacing all existing `devenv`/project-target readiness flows
- broad inventory-architecture changes beyond minimal proof needs

## Implementation steps

### Step 1 — Add tracked bootstrap artifact in toolnix

Create a script in `toolnix` that accepts host/bootstrap parameters and performs the minimal pre-Nix + handoff work.

Acceptance target:

- can run on a fresh exe.dev VM
- does not require a target-side `toolnix` checkout
- results in the expected Home Manager-managed files under `$HOME`

### Step 2 — Add control-host wrapper in hackbox-ctrl

Create a provisioning wrapper that:

- uses existing credential upload helpers where possible
- installs local credential files on the target
- executes the tracked `toolnix` bootstrap script remotely
- avoids cloning `toolnix`, `agent-skills`, or `claude-code-plugins` on the target

Acceptance target:

- a fresh target VM can be provisioned from `hackbox-ctrl` without a target-side `toolnix` clone

### Step 3 — Add host-bootstrap readiness checks

Add checks suitable for the host-bootstrap path, for example:

- `claude` and `pi` present on `PATH`
- managed files under `~/.claude/` and `~/.pi/agent/`
- skills symlink present
- optional auth-dependent checks when the injected credentials support them

Acceptance target:

- readiness output is deterministic enough for repeated proof runs

### Step 4 — Proof on fresh exe.dev VMs

Run dedicated VM proofs and iterate until:

- no target-side `toolnix` clone is required
- bootstrap succeeds
- host-bootstrap readiness checks pass

### Step 5 — Document the resulting path

Update repo docs in both repos to describe:

- the standalone/public bootstrap artifact
- the control-host credential injection path
- the readiness and maintenance procedure

## Risks

- Determinate multi-user Nix may continue to require machine-local cache trust details beyond flake `nixConfig`
- host-bootstrap readiness must avoid implicitly depending on a project checkout
- auth-dependent checks may need to degrade gracefully when only partial credentials are injected
