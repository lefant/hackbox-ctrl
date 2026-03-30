---
date: 2026-03-16
status: proposed
deciders: [lefant]
consulted: []
---

# Adopt Composable Project Environments

## Context

`toolbox` originally acted as runtime image, provisioning entrypoint, bootstrap
file generator, and carrier for dotfiles, skills, and plugins. That was enough
to get exe.dev VMs working, but it created the wrong boundary: provisioning a
non-toolbox project copied runtime files into the project repo and mixed generic
environment concerns with project-specific concerns.

At the same time, the same environment should eventually work across more than
one backend. exe.dev is Docker-friendly, while sprites.dev and similar targets
may need a host-native path. We need one source of truth for what environment a
project uses without tying that description to one execution backend.

## Decision

Treat a provisioned coding environment as a composition of separate components
rather than as a project repo that a shared runtime repo bootstraps by copying
files into it.

The primary components are:

- project repo
- shared system/runtime tooling
- agent skills
- dotfiles
- optional Claude plugins and similar extras

Define this composition through a project-environment manifest and keep backend
execution separate from that manifest. Docker remains historical context and an
older backend shape. Host-native execution is the active follow-up backend once
the composition contract is stable.

## Consequences

It becomes easier to reason about which parts of a provisioned VM are generic
versus project-specific, and to support multiple backends without redefining the
environment each time.

It becomes harder to keep relying on bootstrap behavior that writes broad shared
runtime scaffolding into project repos. That behavior needs to shrink or be
replaced. The next work is to define the manifest, map current provisioning
inputs onto it, and migrate bootstrap toward consuming that manifest instead of
mutating project repos directly.
