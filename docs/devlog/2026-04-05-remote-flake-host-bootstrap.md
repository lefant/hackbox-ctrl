## Summary

Added a host-only control-host provisioning path for `toolnix` that injects machine-local credentials from `hackbox-ctrl-inventory`, runs the tracked `toolnix` bootstrap script remotely, and verifies host readiness without requiring a project checkout or a target-side clone of `toolnix`, `agent-skills`, or `claude-code-plugins`.

## What changed

Changed:

- `scripts/provision-toolnix-host.sh`
- `scripts/verify-toolnix-host-bootstrap.sh`
- `README.md`
- `docs/plans/2026-04-05-remote-flake-host-bootstrap.md`

## Proof

Fresh exe.dev proof target:

- `toolnix-host-proof.exe.xyz`

Validated:

- no target-side shared repo clones under `~/sources/toolnix`, `~/sources/agent-skills`, or `~/sources/claude-code-plugins`
- `claude` and `pi` present on `PATH`
- managed files present under `~/.claude/` and `~/.pi/agent/`
- `scripts/verify-toolnix-host-bootstrap.sh toolnix-host-proof.exe.xyz` returned `ready`

## Notes

- credential injection in this path remains machine-local: `hackbox-ctrl` uploads `~/.env.toolnix` material and shared auth files, but `toolnix` still owns the declarative host state
- follow-up work on the delegated project-target path (`scripts/provision-exe-dev-nix.sh`) added fail-fast remote monitoring, an explicit remote setup timeout, and remote status dumps on failure so fresh-VM proofs do not disappear into long blind runs
- the key cache fix for that delegated path was making the tracked `toolnix` bootstrap script ensure `/etc/nix/nix.conf` includes `/etc/nix/nix.custom.conf`; without that include, fresh VMs still built large Rust trees locally despite the machine-local cache fragment being present on disk
- after that fix, the project-target path was reproved on a fresh exe.dev VM with `devenv` installed after the cache-backed Home Manager bootstrap, and `devenv shell -- printenv DEVENV_ROOT` succeeded without the earlier heavy local compilation failure
- the remaining fresh-VM proof issue is machine-local Codex auth refresh, not bootstrap or cache readiness
- the local repo currently has no configured push remote from this environment, so commits were recorded locally during implementation
