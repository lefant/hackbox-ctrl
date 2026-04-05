---
date: 2026-03-30
status: in_progress
---

# Hackbox-Ctrl Convergence Plan

## Goal

Bring the standalone `hackbox-ctrl` repo up to the same level of coherence that
`toolnix` now has, without reopening the already-settled repo boundaries.

The desired near-term state is:

- `hackbox-ctrl` is the normal tracked home for shared control-plane scripts
- the repo documents the nested `hackbox-ctrl-inventory` contract clearly
- extracted provisioning and readiness flows are documented from the standalone
  repo itself
- durable shared docs needed by the standalone repo are present locally rather
  than only in the historical subtree source

## Current State

Already landed:

- first standalone extraction from the old subtree
- extracted host-native provisioning and readiness scripts
- generated Home Manager bootstrap provisioning
- toolnix-first env and credentials naming in the active implementation path
- core readiness, inventory, and environment specs

Current gaps from repo-local review:

- root README is too thin for current usage
- `docs/specs/project-environment-manifest.md` links to a missing decision doc
- the standalone repo still lacks a compact convergence plan of its own
- docs do not yet give a crisp operator-facing summary of the nested inventory
  contract and common entrypoints

## Non-Goals

This plan does not:

- redesign `toolnix`
- move inventory-private data into this repo
- replace the generated Home Manager bootstrap model
- redesign target manifests into a new schema yet

## Workstreams

### 1. Documentation coherence

- add the missing composable-project-environments decision to this repo
- expand the root README with:
  - repo role
  - nested inventory expectations
  - common commands
  - current provisioning/readiness entrypoints
- ensure docs reference local durable documents rather than historical subtree
  paths where possible

### 2. Standalone repo posture

- make the standalone repo readable on its own without requiring older subtree
  history for basic architectural context
- keep compatibility details in code where needed, but lead docs with the
  `toolnix`-first model

### 3. Validation follow-up

After the docs baseline is coherent, verify the extracted repo itself remains the
primary execution path for:

- `scripts/provision-exe-dev-nix.sh`
- `scripts/verify-general-machine-readiness.sh`
- `scripts/verify-control-host-readiness.sh`

Preferred initial verification set:

- `lefant-toolnix`
- `lefant-toolbox-nix`
- `lefant-toolbox-nix2`

## Success Criteria

This convergence checkpoint is successful when:

- the repo README explains how to use the standalone repo in practice
- durable linked docs exist locally and no longer break
- a new session can understand the repo boundary and nested inventory contract
  directly from `hackbox-ctrl`
- follow-up implementation can focus on provisioning/validation behavior rather
  than documentation archaeology
