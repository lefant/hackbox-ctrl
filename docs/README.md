# Documentation

`hackbox-ctrl` is the shared documentation hub for the control-plane side of the
stack.

## Repo boundaries

- `hackbox-ctrl/docs/` — shared control-plane architecture, specs, plans,
  reference material, and devlog notes
- `hackbox-ctrl-inventory/` — private targets, credentials, and operational
  logs
- `toolnix/docs/` — shared Nix, Home Manager, `devenv`, and bootstrap internals

## Layout

- `docs/specs/` defines control-plane and readiness behavior
- `docs/decisions/` records durable architectural choices
- `docs/reference/` captures operator-facing validation and usage details
- `docs/devlog/` records dated implementation progress for this repo
- `docs/plans/` tracks active implementation sequencing
- `docs/research/` holds discovery notes

Instance-specific host manifests, credentials, and logs stay in the separate
`hackbox-ctrl-inventory` checkout.
