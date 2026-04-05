---
date: 2026-03-28
status: accepted
deciders: [lefant]
consulted: [Codex]
---

# Adopt Toolnix As Primary Shared Nix Repo

## Context

The original host-native Nix and `devenv` work was proven in `sources/toolbox`,
but `toolbox` still mixes several roles:

- historical Docker/container workflows
- subtree-era assumptions
- prototype Nix/Home Manager work
- legacy compatibility paths for older hosts and projects

That made `toolbox` a poor long-term public interface for new consumers.

`toolnix` now exists as a public repo with:

- shared `A/R/O/H` modules
- Home Manager host integration
- `devenv` project integration
- first consumer proof via a thin project import
- optional `agent-browser` support

## Decision

`toolnix` is now the primary shared repo for host-native Nix, Home Manager, and
`devenv` integration.

`toolbox` is no longer the primary documentation or distribution surface for new
shared Nix work. It remains:

- historical context
- prototype/legacy compatibility surface
- possible container-specific migration material until separately retired

## Consequences

### Documentation

- durable docs in `hackbox-ctrl` and `hackbox-ctrl-inventory` should point to
  `toolnix` first
- `sources/toolbox/docs/` should be treated as historical or migration context
  unless a document is explicitly still about legacy toolbox behavior

### Provisioning and setup

- new host-native setup paths should prefer `toolnix`
- scripts that still depend on `toolbox` should be called out as legacy
  compatibility paths

### Project integration

- the preferred thin project integration surface is a small `devenv` import from
  `toolnix`
- new consumer guidance should not require sibling checkouts or vendored
  `toolbox` content

## Non-goals

This decision does not require:

- deleting `toolbox` immediately
- rewriting old historical devlogs
- moving inventory-specific data out of `hackbox-ctrl-inventory`

## Related

- [2026-03-30-hackbox-ctrl-convergence.md](../plans/2026-03-30-hackbox-ctrl-convergence.md)
- [2026-03-26_adopt-shared-nix-bucket-layering.md](./2026-03-26_adopt-shared-nix-bucket-layering.md)
