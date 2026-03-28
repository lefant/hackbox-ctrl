# Hackbox Ctrl Inventory Architecture

## Purpose

This feature defines a private `hackbox-ctrl-inventory` repository that serves as the composition root for provisioned coding environments. It matters because project code, shared tooling, instance-specific inventory, and personal credentials need different lifecycles, visibility, and reuse boundaries.

See: [project-environment-manifest.md](project-environment-manifest.md)

## Requirements

### Inventory As Composition Root

The system SHALL use a dedicated `hackbox-ctrl-inventory` repository as the source of truth for instance-specific environment definitions.

**Scenarios:**
- GIVEN an exe.dev target such as `altego-agent-now.exe.xyz` WHEN provisioning begins THEN the target-specific manifest and config are resolved from the inventory repository rather than from the project repo
- GIVEN multiple VMs for the same project WHEN provisioning begins THEN each VM can have its own target-specific inventory entry without duplicating project source code

### Shared Tooling Separation

The system SHALL keep general tooling in separate reusable repositories rather than vendoring them into `hackbox-ctrl-inventory` by default.

**Scenarios:**
- GIVEN shared tooling such as `lefant/toolnix`, `lefant/agent-skills`, and `lefant/claude-code-plugins` WHEN the inventory is resolved THEN those repositories are referenced by URL and ref rather than copied into `hackbox-ctrl-inventory`
- GIVEN tooling that is private but reusable WHEN the inventory is resolved THEN it remains a separate repository with its own lifecycle and access controls
- GIVEN shared control-plane helpers WHEN an operator needs them locally THEN they are provided by the tracked `hackbox-ctrl` repository rather than vendored into the inventory

### Private Inventory Scope

`hackbox-ctrl-inventory` SHALL contain only information that is target-specific, private, or necessary to compose environments.

**Scenarios:**
- GIVEN instance-specific files like `targets/<fqdn>/config.env` and credentials under `credentials/targets/<fqdn>/` WHEN `hackbox-ctrl-inventory` is reviewed THEN those files belong there because they describe private target setup
- GIVEN application source code for a project WHEN `hackbox-ctrl-inventory` is reviewed THEN that code is absent and referenced externally instead

### Project Refs, Not Project Copies

The system SHALL reference project repositories from manifests instead of storing project source code in the inventory repository.

**Scenarios:**
- GIVEN a project like `lingontuvan-it-group/lingontuvan-stadbokning` WHEN provisioning begins THEN the inventory provides the project repo URL, branch, and checkout path without embedding the project source in the inventory repository
- GIVEN collaborators with different local environments WHEN they use the same project repo THEN they can still share the same project source while using different inventory entries or overlays

### Credentials Out Of Git

The system SHALL keep credentials inside `hackbox-ctrl-inventory/credentials/` as runtime inputs that are present in the checkout but not committed to git.

**Scenarios:**
- GIVEN shared Codex auth and target-specific `GH_TOKEN` WHEN provisioning runs THEN `hackbox-ctrl-inventory/credentials/` contains the local secret material while git tracks only the surrounding structure and ignore rules
- GIVEN a collaborator without access to another user's credentials WHEN they use the same inventory repository THEN they can still use the shared manifests and provide their own local credential material under `credentials/`

### Shared Bootstrap Tooling

The system SHALL allow shared provisioning and repository-fetching scripts to live in `hackbox-ctrl` rather than inside `hackbox-ctrl-inventory` itself.

**Scenarios:**
- GIVEN a script that fetches referenced tooling and project repositories into a local checkout WHEN provisioning logic is needed across multiple inventories THEN that script lives in `hackbox-ctrl/scripts/`
- GIVEN changes to provisioning mechanics WHEN `hackbox-ctrl-inventory` is updated THEN the manifests can continue to reference the shared scripts without duplicating their implementation

### Minimal Inventory Structure

The system SHOULD keep `hackbox-ctrl-inventory` minimal and focused on manifests, target inventory, credentials, and provisioning logs.

**Scenarios:**
- GIVEN the older `bootstrap-configs/` compatibility layout WHEN bootstrap logic still needs it THEN it is generated from `targets/` plus `credentials/` rather than committed as a second source of truth
- GIVEN future growth in environment definitions WHEN `hackbox-ctrl-inventory` evolves THEN its structure stays centered on describing environments rather than re-implementing shared `toolnix` internals
- GIVEN shared architecture, bootstrap, or repository-structure documentation WHEN it is written THEN it lives in `hackbox-ctrl/docs/` or `sources/toolnix/docs/`, not as a general documentation tree inside the private inventory repo

### Thin Project Integration

The system SHOULD prefer thin project-level integration that delegates to centrally defined `toolnix` concerns instead of repeating generic runtime scaffolding in each project repository.

**Scenarios:**
- GIVEN a project that wants `toolnix`-provided host-native development tooling WHEN it integrates with the environment system THEN it can do so through a small delegating config rather than a vendored shared-repo subtree
- GIVEN shared `toolnix` defaults for packages, skills, and generic agent integration WHEN multiple projects use them THEN those defaults are defined centrally and referenced, not copied into each project repo
- GIVEN a project that needs extensive customization WHEN it adds local config THEN that config is primarily project-specific behavior, not repetition of generic shared-runtime concerns

### Minimal Host-Native Provisioning

The system SHOULD keep host-native provisioning small and focused on machine bootstrap plus inventory-resolved inputs.

**Scenarios:**
- GIVEN a fresh exe.dev VM WHEN host-native provisioning runs THEN the first-stage provisioner installs the minimum Nix/devenv machinery, places credentials, and fetches the declared repositories without bringing along Docker-specific compatibility code
- GIVEN target metadata such as hostname, repo URL, branch, checkout path, and credential fragments WHEN provisioning runs THEN those are sufficient to bootstrap the machine without requiring project-local Docker Compose scaffolding
- GIVEN future changes to `toolnix` internals WHEN host-native provisioning evolves THEN the inventory and provisioner remain focused on wiring inputs together rather than embedding generic shared-repo implementation details

### Logs Directory

The system SHOULD use `hackbox-ctrl-inventory/logs/` for provisioning and control-plane activity logs rather than folding those records into a development-log convention from other repos.

**Scenarios:**
- GIVEN provisioning activity on `lefant-ctrl.exe.xyz` WHEN control-plane work is recorded THEN operational logs are written under `logs/`
- GIVEN a machine-specific or dated note such as a bootstrap session, rollout note, or target status snapshot WHEN it is retained in the inventory repo THEN it uses a dated filename under `logs/`, for example `logs/YYYY-MM-DD-<fqdn>-<slug>.md`
- GIVEN shared architecture or feature documentation WHEN it is authored THEN it lives in shared docs, not under `logs/`

## Open Questions

- [ ] Should environment manifests and target manifests be separate files or one merged manifest per target?
- [ ] Should the inventory repository keep a lock file for exact tooling commits in addition to human-edited manifests?
- [ ] How should user-specific overlays be represented without making the shared inventory noisy?
- [ ] Should the current `bootstrap-configs` shape remain visible in `hackbox-ctrl-inventory`, or should it become an implementation detail generated from higher-level manifests?
