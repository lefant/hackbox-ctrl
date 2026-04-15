#!/usr/bin/env bash
# provision-toolnix-host.sh — control-host bootstrap of a toolnix Home Manager host without target-side git clones
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
TOOLNIX_REPO_ROOT="${TOOLNIX_REPO_ROOT:-/home/exedev/git/lefant/toolnix}"
TOOLNIX_BOOTSTRAP_SCRIPT="$TOOLNIX_REPO_ROOT/scripts/bootstrap-home-manager-host.sh"
export BOOTSTRAP_SSH_KEY="${BOOTSTRAP_SSH_KEY:-$INVENTORY_ROOT/credentials/shared/ssh/exe-dev-bootstrap}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provision-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/provision-toolnix-host.sh <target-fqdn>

Provision a fresh exe.dev VM with toolnix host config and machine-local
credentials, without cloning toolnix on the target machine.

Reads target metadata from:
  targets/<target-fqdn>/config.env

Expected target fields:
  TARGET_FQDN

Optional:
  TOOLNIX_REF
  HOME_MANAGER_HOST_NAME
  HOME_MANAGER_ENABLE_HOST_CONTROL
  HOME_MANAGER_ENABLE_AGENT_BASELINE
  HOME_MANAGER_ENABLE_AGENT_BROWSER
  HOME_USERNAME
  HOME_DIRECTORY
  HOME_STATE_VERSION
  INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET_FQDN="${1:?Usage: provision-toolnix-host.sh <target-fqdn>}"
TARGET_CONFIG="$INVENTORY_ROOT/targets/$TARGET_FQDN/config.env"
require_file "$TARGET_CONFIG"
require_file "$TOOLNIX_BOOTSTRAP_SCRIPT"
SHARED_ENV_FILE="$(shared_env_file "$INVENTORY_ROOT")"
require_file "$SHARED_ENV_FILE"

TOOLNIX_REF="$(config_value TOOLNIX_REF "$TARGET_CONFIG")"
TOOLNIX_REF="${TOOLNIX_REF:-github:lefant/toolnix}"
INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY="$(config_value INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY "$TARGET_CONFIG")"
INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY="${INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY:-0}"
HOME_MANAGER_HOST_NAME="$(config_value HOME_MANAGER_HOST_NAME "$TARGET_CONFIG")"
HOME_MANAGER_HOST_NAME="${HOME_MANAGER_HOST_NAME:-${TARGET_FQDN%.exe.xyz}}"
HOME_MANAGER_ENABLE_HOST_CONTROL="$(config_value HOME_MANAGER_ENABLE_HOST_CONTROL "$TARGET_CONFIG")"
HOME_MANAGER_ENABLE_HOST_CONTROL="${HOME_MANAGER_ENABLE_HOST_CONTROL:-0}"
HOME_MANAGER_ENABLE_AGENT_BASELINE="$(config_value HOME_MANAGER_ENABLE_AGENT_BASELINE "$TARGET_CONFIG")"
HOME_MANAGER_ENABLE_AGENT_BASELINE="${HOME_MANAGER_ENABLE_AGENT_BASELINE:-1}"
HOME_MANAGER_ENABLE_AGENT_BROWSER="$(config_value HOME_MANAGER_ENABLE_AGENT_BROWSER "$TARGET_CONFIG")"
HOME_MANAGER_ENABLE_AGENT_BROWSER="${HOME_MANAGER_ENABLE_AGENT_BROWSER:-0}"
HOME_USERNAME_VALUE="$(config_value HOME_USERNAME "$TARGET_CONFIG")"
HOME_USERNAME_VALUE="${HOME_USERNAME_VALUE:-exedev}"
HOME_DIRECTORY_VALUE="$(config_value HOME_DIRECTORY "$TARGET_CONFIG")"
HOME_DIRECTORY_VALUE="${HOME_DIRECTORY_VALUE:-/home/exedev}"
HOME_STATE_VERSION_VALUE="$(config_value HOME_STATE_VERSION "$TARGET_CONFIG")"
HOME_STATE_VERSION_VALUE="${HOME_STATE_VERSION_VALUE:-25.05}"

SSH_OPTS=(-i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
SSH_OPTS_STR="${SSH_OPTS[*]}"

log "Provisioning toolnix host $TARGET_FQDN"
ensure_exe_dev_vm "$TARGET_FQDN"

REMOTE_TMP=""
cleanup() {
  if [ -n "$REMOTE_TMP" ]; then
    ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "rm -rf '$REMOTE_TMP'" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

REMOTE_TMP="$(ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" 'mktemp -d')"

upload_credentials "$TARGET_FQDN" "$INVENTORY_ROOT" "$REMOTE_TMP" "$SSH_OPTS_STR" "$INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY"
scp "${SSH_OPTS[@]}" "$TOOLNIX_BOOTSTRAP_SCRIPT" "$TARGET_FQDN:$REMOTE_TMP/bootstrap-home-manager-host.sh"

ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "bash -se" <<EOF
set -euo pipefail

REMOTE_TMP="$REMOTE_TMP"
mkdir -p "${HOME_DIRECTORY_VALUE}/.ssh" "${HOME_DIRECTORY_VALUE}/.local/share" "${HOME_DIRECTORY_VALUE}/.local/state" "${HOME_DIRECTORY_VALUE}/.local/share/opencode" "${HOME_DIRECTORY_VALUE}/.codex" "${HOME_DIRECTORY_VALUE}/.pi/agent"

cat "\$REMOTE_TMP/env.toolnix" > "${HOME_DIRECTORY_VALUE}/.env.toolnix"
if [ -f "\$REMOTE_TMP/env.toolnix.fragment" ]; then
  cat "\$REMOTE_TMP/env.toolnix.fragment" >> "${HOME_DIRECTORY_VALUE}/.env.toolnix"
fi

if [ -f "\$REMOTE_TMP/codex-auth.json" ]; then
  install -m 600 "\$REMOTE_TMP/codex-auth.json" "${HOME_DIRECTORY_VALUE}/.codex/auth.json"
fi
if [ -f "\$REMOTE_TMP/pi-agent-auth.json" ]; then
  install -m 600 "\$REMOTE_TMP/pi-agent-auth.json" "${HOME_DIRECTORY_VALUE}/.pi/agent/auth.json"
fi
if [ -f "\$REMOTE_TMP/opencode-auth.json" ]; then
  install -m 600 "\$REMOTE_TMP/opencode-auth.json" "${HOME_DIRECTORY_VALUE}/.local/share/opencode/auth.json"
fi
if [ -f "\$REMOTE_TMP/exe-dev-bootstrap" ]; then
  install -m 600 "\$REMOTE_TMP/exe-dev-bootstrap" "${HOME_DIRECTORY_VALUE}/.ssh/exe-dev-bootstrap"
  install -m 644 "\$REMOTE_TMP/exe-dev-bootstrap.pub" "${HOME_DIRECTORY_VALUE}/.ssh/exe-dev-bootstrap.pub"
fi

if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
nix --extra-experimental-features 'nix-command flakes' --accept-flake-config \
  profile install nixpkgs#direnv nixpkgs#git nixpkgs#gh nixpkgs#zsh 2>/dev/null || true
export PATH="${HOME_DIRECTORY_VALUE}/.nix-profile/bin:\$PATH"
hash -r

bash "\$REMOTE_TMP/bootstrap-home-manager-host.sh" \
  --toolnix-ref "${TOOLNIX_REF}" \
  --host-name "${HOME_MANAGER_HOST_NAME}" \
  --home-username "${HOME_USERNAME_VALUE}" \
  --home-directory "${HOME_DIRECTORY_VALUE}" \
  --state-version "${HOME_STATE_VERSION_VALUE}" \
  $( [ "$HOME_MANAGER_ENABLE_HOST_CONTROL" = "1" ] && printf '%s ' '--enable-host-control' ) \
  $( [ "$HOME_MANAGER_ENABLE_AGENT_BASELINE" = "0" ] && printf '%s ' '--disable-agent-baseline' ) \
  $( [ "$HOME_MANAGER_ENABLE_AGENT_BROWSER" = "1" ] && printf '%s ' '--enable-agent-browser' )
EOF

log "Running host-bootstrap readiness checks"
ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "bash -se" <<'EOF'
set -euo pipefail
command -v claude
command -v pi
test -e ~/.claude/settings.json
test -e ~/.claude/skills
test -e ~/.pi/agent/settings.json
printf 'ready: claude+pi+managed-files\n'
EOF

log "Provisioning complete: $TARGET_FQDN"
