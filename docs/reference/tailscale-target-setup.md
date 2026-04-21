# Tailscale setup for inventory-managed target hosts

Use this when a target host should join a Tailscale tailnet imperatively from the `hackbox-ctrl` control plane.

This is the current fit for:

- Ubuntu-based exe.dev hosts managed through `hackbox-ctrl`
- hosts where Tailscale is treated as host-level system software
- hosts that are **not** yet NixOS system-managed machines

## Nix stance

Tailscale has strong native NixOS support.

For real NixOS hosts, the preferred long-term shape is:

- declare Tailscale through the NixOS module system
- keep host intent in Nix
- avoid ad-hoc imperative install scripts after the host is fully system-managed

For the current exe.dev `toolnix` hosts, that is not the active model yet. They are Ubuntu hosts with a Home Manager layer, so the practical path is an inventory-driven imperative setup step.

## Inventory inputs

Target metadata lives in:

```text
hackbox-ctrl-inventory/targets/<target-fqdn>/config.env
```

Per-target Tailscale credentials live in:

```text
hackbox-ctrl-inventory/credentials/targets/<target-fqdn>/env.tailscale
```

### Required `env.tailscale`

```bash
TAILSCALE_AUTH_KEY=tskey-auth-...
```

### Optional `config.env` keys

```bash
TAILSCALE_HOSTNAME=lefant-openclaw-bottle
TAILSCALE_ENABLE_SSH=1
TAILSCALE_SERVE_HTTPS_PORT=443
TAILSCALE_SERVE_TARGET=http://127.0.0.1:8000
TAILSCALE_ADVERTISE_TAGS=
```

Notes:

- `TAILSCALE_HOSTNAME` defaults to the target short name.
- `TAILSCALE_SERVE_TARGET` defaults to `http://127.0.0.1:8000`, which matches the current exe.dev OpenClaw deployment pattern.
- leave `TAILSCALE_ADVERTISE_TAGS` empty unless the tailnet ACL/tag-owner rules are already configured to allow the desired tags.

## Script

Run:

```bash
cd ~/git/lefant/hackbox-ctrl
scripts/setup-target-tailscale.sh <target-fqdn>
```

The script will:

1. read `config.env` and `env.tailscale`
2. install Tailscale if missing
3. enable and start `tailscaled`
4. join the target to the tailnet using `TAILSCALE_AUTH_KEY`
5. optionally enable Tailscale SSH
6. configure `tailscale serve` for the configured local target URL
7. print status and serve verification output

## OpenClaw mapping

For the migrated exe.dev OpenClaw hosts, keep OpenClaw itself in local loopback mode:

- `gateway.mode=local`
- `gateway.bind=loopback`
- `gateway.trustedProxies=["127.0.0.1"]`

Then let Tailscale expose the HTTPS entrypoint externally through:

```bash
tailscale serve --bg --https=443 http://127.0.0.1:8000
```

This matches the old Hetzner pattern conceptually, while using exe.dev's local OpenClaw port (`8000`) instead of the Hetzner port (`18789`).

## Current Lefant migration note

Old Hetzner Lefant used:

- MagicDNS suffix: `bat-tuatara.ts.net`
- node hostname: `openclaw-gateway-lefant`
- `tailscale serve` -> `http://127.0.0.1:18789`

While the old node is still kept around for rollback, avoid reusing the same Tailscale hostname.
Use the exe.dev host's own name instead:

- `lefant-openclaw-bottle`

That avoids a MagicDNS/node-name collision while still providing a Tailscale URL for the new primary host.
