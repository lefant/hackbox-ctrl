# hackbox-ctrl

Standalone control-plane toolkit for toolnix-managed hackboxes.

Structure:

- `scripts/` — tracked shared control-plane scripts
- `docs/` — tracked shared docs, specs, decisions, plans, and devlogs
- `hackbox-ctrl-inventory/` — nested local inventory checkout, intentionally untracked here

The default local layout is:

```text
~/git/lefant/hackbox-ctrl/
├── scripts/
├── docs/
└── hackbox-ctrl-inventory/
```

The scripts in this repo assume that nested layout by default. Override it with
`HACKBOX_CTRL_INVENTORY_ROOT` if needed.
