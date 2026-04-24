#!/usr/bin/env bash
# setup-target-tailscale.sh — install and configure Tailscale on an inventory-managed target host
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
BOOTSTRAP_SSH_KEY="${BOOTSTRAP_SSH_KEY:-$INVENTORY_ROOT/credentials/shared/ssh/exe-dev-bootstrap}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provision-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/setup-target-tailscale.sh <target-fqdn>

Installs and configures Tailscale on a target host using inventory-managed
per-target credentials.

Reads target metadata from:
  targets/<target-fqdn>/config.env

Reads target-local Tailscale credentials from:
  credentials/targets/<target-fqdn>/env.tailscale

Expected env.tailscale fields:
  TAILSCALE_AUTH_KEY   required

Optional config/env fields:
  TAILSCALE_HOSTNAME            default: <target short name>
  TAILSCALE_ENABLE_SSH          default: 1
  TAILSCALE_SERVE_ENABLE        default: 1
  TAILSCALE_SERVE_HTTPS_PORT    default: 443
  TAILSCALE_SERVE_TARGET        default: http://127.0.0.1:8000
  TAILSCALE_ADVERTISE_TAGS      optional comma-separated list
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET_FQDN="${1:?Usage: setup-target-tailscale.sh <target-fqdn>}"
if [[ "$TARGET_FQDN" != *.exe.xyz ]]; then
  TARGET_FQDN="$TARGET_FQDN.exe.xyz"
fi

TARGET_CONFIG="$INVENTORY_ROOT/targets/$TARGET_FQDN/config.env"
TARGET_ENV="$INVENTORY_ROOT/credentials/targets/$TARGET_FQDN/env.tailscale"
require_file "$TARGET_CONFIG"
require_file "$TARGET_ENV"
require_file "$BOOTSTRAP_SSH_KEY"

set -a
# shellcheck disable=SC1090
. "$TARGET_ENV"
set +a

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "ERROR: TAILSCALE_AUTH_KEY missing in $TARGET_ENV" >&2
  exit 1
fi

TARGET_SHORT="${TARGET_FQDN%.exe.xyz}"
TAILSCALE_HOSTNAME_VALUE="$(config_value TAILSCALE_HOSTNAME "$TARGET_CONFIG")"
TAILSCALE_HOSTNAME_VALUE="${TAILSCALE_HOSTNAME_VALUE:-${TAILSCALE_HOSTNAME:-$TARGET_SHORT}}"
TAILSCALE_ENABLE_SSH_VALUE="$(config_value TAILSCALE_ENABLE_SSH "$TARGET_CONFIG")"
TAILSCALE_ENABLE_SSH_VALUE="${TAILSCALE_ENABLE_SSH_VALUE:-${TAILSCALE_ENABLE_SSH:-1}}"
TAILSCALE_SERVE_ENABLE_VALUE="$(config_value TAILSCALE_SERVE_ENABLE "$TARGET_CONFIG")"
TAILSCALE_SERVE_ENABLE_VALUE="${TAILSCALE_SERVE_ENABLE_VALUE:-${TAILSCALE_SERVE_ENABLE:-1}}"
TAILSCALE_SERVE_HTTPS_PORT_VALUE="$(config_value TAILSCALE_SERVE_HTTPS_PORT "$TARGET_CONFIG")"
TAILSCALE_SERVE_HTTPS_PORT_VALUE="${TAILSCALE_SERVE_HTTPS_PORT_VALUE:-${TAILSCALE_SERVE_HTTPS_PORT:-443}}"
TAILSCALE_SERVE_TARGET_VALUE="$(config_value TAILSCALE_SERVE_TARGET "$TARGET_CONFIG")"
TAILSCALE_SERVE_TARGET_VALUE="${TAILSCALE_SERVE_TARGET_VALUE:-${TAILSCALE_SERVE_TARGET:-http://127.0.0.1:8000}}"
TAILSCALE_ADVERTISE_TAGS_VALUE="$(config_value TAILSCALE_ADVERTISE_TAGS "$TARGET_CONFIG")"
TAILSCALE_ADVERTISE_TAGS_VALUE="${TAILSCALE_ADVERTISE_TAGS_VALUE:-${TAILSCALE_ADVERTISE_TAGS:-}}"

SSH_OPTS=(-i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

log "Configuring Tailscale on $TARGET_FQDN"
ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" env \
  TAILSCALE_AUTH_KEY="$TAILSCALE_AUTH_KEY" \
  TAILSCALE_HOSTNAME_VALUE="$TAILSCALE_HOSTNAME_VALUE" \
  TAILSCALE_ENABLE_SSH_VALUE="$TAILSCALE_ENABLE_SSH_VALUE" \
  TAILSCALE_SERVE_ENABLE_VALUE="$TAILSCALE_SERVE_ENABLE_VALUE" \
  TAILSCALE_SERVE_HTTPS_PORT_VALUE="$TAILSCALE_SERVE_HTTPS_PORT_VALUE" \
  TAILSCALE_SERVE_TARGET_VALUE="$TAILSCALE_SERVE_TARGET_VALUE" \
  TAILSCALE_ADVERTISE_TAGS_VALUE="$TAILSCALE_ADVERTISE_TAGS_VALUE" \
  bash -se <<'REMOTE'
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled

up_cmd=(sudo tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --hostname="$TAILSCALE_HOSTNAME_VALUE")
if [ "$TAILSCALE_ENABLE_SSH_VALUE" = "1" ]; then
  up_cmd+=(--ssh)
fi
if [ -n "$TAILSCALE_ADVERTISE_TAGS_VALUE" ]; then
  up_cmd+=(--advertise-tags="$TAILSCALE_ADVERTISE_TAGS_VALUE")
fi
"${up_cmd[@]}"

if [ "$TAILSCALE_SERVE_ENABLE_VALUE" = "1" ]; then
  sudo tailscale serve --bg --https="$TAILSCALE_SERVE_HTTPS_PORT_VALUE" "$TAILSCALE_SERVE_TARGET_VALUE"
fi

echo
printf 'tailscale_version='; tailscale version | head -n 1 || true
printf 'tailscaled_enabled='; systemctl is-enabled tailscaled || true
printf 'tailscaled_active='; systemctl is-active tailscaled || true
printf '\nstatus_json_extract=\n'
tailscale status --json | jq -r '
  "BackendState=" + (.BackendState // ""),
  "MagicDNSSuffix=" + (.MagicDNSSuffix // ""),
  "Self.DNSName=" + (.Self.DNSName // ""),
  "Self.HostName=" + (.Self.HostName // ""),
  "Self.TailscaleIPs=" + ((.Self.TailscaleIPs // []) | join(",")),
  "Self.Tags=" + ((.Self.Tags // []) | join(","))
'
printf '\nserve_enabled=%s\n' "$TAILSCALE_SERVE_ENABLE_VALUE"
if [ "$TAILSCALE_SERVE_ENABLE_VALUE" = "1" ]; then
  printf '\nserve_status=\n'
  tailscale serve status | sed -n '1,80p'
else
  printf '\nserve_status=skipped (native tailnet routing mode)\n'
fi
REMOTE

log "Tailscale setup complete: $TARGET_FQDN"
