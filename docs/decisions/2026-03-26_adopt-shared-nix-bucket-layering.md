---
date: 2026-03-26
status: accepted
deciders: [lefant]
consulted: [Codex]
---

# Adopt Shared Nix Bucket Layering

## Context

The host-native Nix work now spans several overlapping configuration surfaces:

- Home Manager for host shell and tmux placement
- `devenv` for project and target runtime environments
- tracked agent configuration and shared skills in the shared Nix repo
- bootstrap provisioning logic for credentials and machine setup

Earlier docs mixed two different classification models:

- host vs guest vs project scope
- implementation mechanism (`dotfiles`, Home Manager, `devenv`, provisioner)

That made it harder to decide where a concern should actually live.

## Decision

Adopt four shared Nix buckets as the primary architectural classification:

| Bucket | Meaning |
| --- | --- |
| `A` | Agent baseline |
| `R` | Required shell/system baseline |
| `O` | Opinionated shell baseline |
| `H` | Host/control-only baseline |

## Meaning of each bucket

### `A`: Agent baseline

Includes:

- shared agent binaries
- shared agent config
- shared skills

Typical consumers:

- `devenv`
- target/VM/container definitions
- most Home Manager hosts

Default policy:

- enabled by default on normal development hosts and targets

### `R`: Required shell/system baseline

Includes:

- ubiquitous non-controversial shell/system tools and config

Current examples:

- `git`
- `gh`
- `tmux`
- `bat`
- `just`
- `mg` as a package
- UTF-8 locale support
- repo GitHub workflow readiness

Typical consumers:

- Home Manager
- `devenv`
- guest/container images

Default policy:

- enabled by default everywhere we expect a normal development environment

### `O`: Opinionated shell baseline

Includes:

- personal but reusable interactive ergonomics

Current examples:

- `e` alias
- `tmux-here`
- tmux status-bar color logic
- `claude` and `codex` wrapper aliases
- Stockholm `TZ`

Typical consumers:

- Home Manager by default
- optional import in `devenv`, with explicit exceptions where we decide to enable some items by default

Default policy:

- reusable and encouraged, but still recognized as opinionated rather than neutral baseline

### `H`: Host/control-only baseline

Includes:

- behavior that only makes sense on direct-login machines or control hosts

Current examples:

- `tmux-meta`
- target-entry aliases
- SSH defaults
- management credentials

Typical consumers:

- Home Manager
- host provisioning

Default policy:

- not part of generic project or guest/container runtime

## Concrete policy updates adopted with this decision

- Stockholm `TZ` should be included in Home Manager and also in `devenv` by default.
- `mg` should be included in the required baseline as a package.
- Hosts should be considered agent-capable by default.
- `direnv` support may remain available, but automatic `direnv` activation should not be part of the default shell baseline.
- `~/.zsh/zshlocal.sh` should be empty/minimal by default and not carry routine baseline behavior.
- `~/.env.toolnix` should be treated as the primary credentials-only escape hatch, with `~/.env.toolbox` supported only as a compatibility fallback during migration.

## Consequences

### Positive

- clearer split between neutral baseline, opinionated ergonomics, agent runtime, and control-plane-only behavior
- easier to decide whether Home Manager, `devenv`, or provisioning should consume a concern
- better fit for sharing the same conventions across hosts, guests, and projects without over-coupling everything to personal dotfiles

### Tradeoffs

- some existing specs need to be regrouped around `A/R/O/H`
- some items remain mixed internally even if they now share one bucket heading
- the initial extraction required a follow-up implementation pass to make these buckets concrete modules in a shared Nix repo

## Implementation status

The bucket layering is no longer just conceptual.

The first complete implementation landed in `sources/toolbox`, and the current
primary implementation now lives in `toolnix`.

Current primary module locations:

- `sources/toolnix/modules/shared/required-baseline.nix`
- `sources/toolnix/modules/shared/agent-baseline.nix`
- `sources/toolnix/modules/shared/opinionated-shell.nix`
- `sources/toolnix/modules/shared/host-control.nix`

Current primary consumers:

- `sources/toolnix/modules/devenv/default.nix`
- `sources/toolnix/modules/home-manager/toolnix-host.nix`

Historical prototype locations:

- `sources/toolbox/nix/modules/required-baseline.nix`
- `sources/toolbox/nix/modules/agent-baseline.nix`
- `sources/toolbox/nix/modules/opinionated-shell.nix`
- `sources/toolbox/nix/modules/host-control.nix`

## Related

- `toolnix` repo module layout under `modules/shared/`, `modules/devenv/`, and `modules/home-manager/`
