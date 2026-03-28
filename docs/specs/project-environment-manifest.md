# Project Environment Manifest

## Purpose

This feature defines a single manifest that describes which project repo, `toolnix`, shared agent/plugin repos, credentials, and related components make up a provisioned coding environment. It matters because the same environment definition should drive legacy Docker-first exe.dev provisioning now and a host-native backend later without changing the logical contract.

See: [2026-03-16-adopt-composable-project-environments.md](../decisions/2026-03-16-adopt-composable-project-environments.md)

## Requirements

### Environment Identity

The system SHALL identify a provisioned environment by target plus project intent rather than by ad hoc shell variables scattered across scripts.

**Scenarios:**
- GIVEN a target VM such as `altego-agent-now.exe.xyz` WHEN provisioning starts THEN the system can resolve one manifest instance that describes the project repo, checkout branch, and expected checkout path for that target
- GIVEN a sibling target such as `altego-agent-now-matrix.exe.xyz` WHEN provisioning starts THEN the system can describe the same project with a different branch or target-specific overrides without redefining the full environment by hand

### Component Composition

The system SHALL describe the environment as a set of components with independently selectable sources or refs.

**Scenarios:**
- GIVEN a project that uses standard lefant `toolnix`, skills, and plugins WHEN its manifest is resolved THEN each component is identifiable separately rather than being implied by one monolithic shared-repo checkout
- GIVEN a project that wants custom host config or no personal shell layer WHEN its manifest is resolved THEN those concerns can be changed or disabled without redefining the project repo or `toolnix` component

### Backend Independence

The system SHALL describe the environment without requiring Docker-specific concepts in the core manifest.

**Scenarios:**
- GIVEN an exe.dev target WHEN provisioning runs with the Docker backend THEN the same manifest can drive image build, container startup, and interactive readiness checks
- GIVEN a future host-native target WHEN provisioning runs without Docker THEN the same manifest still describes the environment intent even if the execution steps differ

### Thin Delegation to Shared Toolnix Definition

The system SHOULD allow project-local configuration to delegate generic `toolnix` concerns to a centrally defined reusable `toolnix` layer.

**Scenarios:**
- GIVEN a project that uses the standard `toolnix` environment WHEN its manifest is resolved THEN generic `toolnix` concerns such as shared packages, skills, and baseline agent integration come from a central definition rather than being repeated in the project repo
- GIVEN a project that needs local customization WHEN it adds project-local `devenv` or Nix configuration THEN that file may be large if necessary, but its repeated generic `toolnix` concerns remain delegated to the shared `toolnix` definition
- GIVEN a project with no need for local customization WHEN it integrates with the environment system THEN a very small delegating config is sufficient

### Target Overrides

The system SHALL support target-specific overrides for credentials, branch, checkout path, and similar operational settings without forcing those overrides into the project repo.

**Scenarios:**
- GIVEN shared agent credentials and a target-specific `GH_TOKEN` WHEN provisioning a VM THEN the target can inject only its own GitHub token while reusing shared Codex or Claude credentials
- GIVEN a default project branch WHEN a specific VM needs to track `matrix` instead THEN the target can override the branch without changing the base project definition

### Runtime Persistence Boundaries

The system SHALL distinguish declarative environment inputs from runtime state.

**Scenarios:**
- GIVEN Codex auth and repo-managed config WHEN provisioning runs THEN auth can be seeded while session logs, caches, and similar machine-local runtime state are not copied by default
- GIVEN dotfiles and skills under version control WHEN a VM is reprovisioned THEN those declarative inputs are restored while ephemeral history and tmux sessions remain local to that VM

### File-Level Ownership Boundaries

The system SHOULD classify configuration at the file level rather than assuming entire directories are either declarative or mutable.

**Scenarios:**
- GIVEN an agent config directory that contains both read-only skills and writable runtime state WHEN ownership is designed THEN skills can be managed declaratively while writable runtime files remain mutable
- GIVEN a file that is required for initial seeding but later modified by the tool WHEN the environment is provisioned THEN the file may be seeded from a declarative template but is not kept as an immutable managed link afterward
- GIVEN writable OAuth state, caches, counters, or session metadata WHEN configuration is reviewed THEN those files are treated as runtime-owned state and excluded from immutable declarative management

### Bootstrap Compatibility

The system SHOULD support a transition period where current bootstrap scripts can consume the manifest without requiring an immediate full replacement of existing project-level runtime files.

**Scenarios:**
- GIVEN a project that still relies on `scripts/bootstrap.sh` outputs WHEN provisioning runs THEN the manifest can still drive that flow while the copied-file surface is being reduced
- GIVEN a project that has moved to a lighter runtime layout WHEN provisioning runs THEN the manifest does not require the old copied `toolbox/*` compatibility structure

## Open Questions

- [ ] Should the base manifest live in each project repo or in a separate environment/composition repo?
- [ ] Should target-specific overrides remain under `bootstrap-configs/targets/` or move to a more explicit environment inventory structure?
- [ ] Which component refs should be pinned exactly versus following a branch?
- [ ] How much of the current project-local `compose.yaml` and `justfile` contract should remain as a compatibility layer?
