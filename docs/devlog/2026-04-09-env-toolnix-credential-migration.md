---
date: 2026-04-09
status: ✅ COMPLETED
related_spec: docs/specs/hackbox-ctrl-inventory-architecture.md
related_adr: docs/decisions/2026-03-26_adopt-shared-nix-bucket-layering.md
related_issues: []
---

# Implementation Log - 2026-04-09

**Implementation**: Completed the active `env.toolbox` to `env.toolnix` credential-path migration for the standalone control-plane

## Summary

Completed the current control-plane-side credential naming migration so the active `hackbox-ctrl` provisioning path now requires `credentials/shared/env.toolnix` and `credentials/targets/<fqdn>/env.toolnix.fragment` rather than falling back to the older `env.toolbox` names. This aligns the provisioner with the documented `toolnix` credential model and makes the inventory-side Exa key rollout land on all `toolnix` hosts through the canonical shared env file. The private inventory checkout was also migrated locally so the shared credential file and all target fragments now use the `env.toolnix` naming convention.

## Plan vs Reality

**What was planned:**
- [ ] Migrate shared inventory credentials from `env.toolbox` naming to `env.toolnix`
- [ ] Migrate target env fragments to `env.toolnix.fragment`
- [ ] Remove active fallback behavior from the standalone control-plane helper
- [ ] Confirm the shared env file still carries `EXA_API_KEY`
- [ ] Record the migration in docs

**What was actually implemented:**
- [x] Renamed the private inventory shared credential file to `credentials/shared/env.toolnix`
- [x] Renamed all private inventory target fragments from `env.toolbox.fragment` to `env.toolnix.fragment`
- [x] Verified the migrated shared env file still contains `EXA_API_KEY`
- [x] Updated `scripts/lib/provision-common.sh` to require `env.toolnix` naming instead of silently falling back to `env.toolbox`
- [x] Updated the mirrored provisioning helper under the inventory tooling subtree to match
- [x] Updated the bucket-layering decision text so current naming policy is explicit
- [x] Wrote this devlog entry

## Challenges & Solutions

**Challenges encountered:**
- The real secret-bearing inventory files are intentionally untracked, so the migration needed both a local file move and a tracked record explaining the new canonical path.
- The active control-plane and the older mirrored helper in the inventory tooling subtree had both retained the same compatibility fallback logic.

**Solutions found:**
- Performed the local secret-file rename without reading or rewriting secret values.
- Switched both active helper implementations to require the new canonical `env.toolnix` path so future drift back to `env.toolbox` fails fast.
- Verified the Exa key remains present in the shared env file after the rename.

## Learnings

- The current standalone control-plane was already very close to the final state; the main migration work left was naming cleanup and fail-fast enforcement.
- Keeping `toolnix` itself tolerant of `~/.env.toolbox` while making `hackbox-ctrl` provisioning canonical on `env.toolnix` is a reasonable staged boundary: runtime stays lenient, provisioning becomes explicit.
- Shared provider credentials like `EXA_API_KEY` fit naturally in `credentials/shared/env.toolnix` when they should land on all provisioned `toolnix` hosts.

## Next Steps

- [ ] Reprovision or sync any target hosts that still only have an old machine-local `~/.env.toolbox` if you want their local files to match the new naming convention exactly
- [ ] When convenient, continue cleaning remaining historical `env.toolbox` references in archival logs and old toolbox-era tooling docs
