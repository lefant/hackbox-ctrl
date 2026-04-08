#!/usr/bin/env bash
# provision-exe-dev-nix.sh — minimal host-native Nix/devenv provisioner for exe.dev VMs
#
# Scope:
# - ensure the VM exists
# - install Nix + minimal profile tooling
# - place credentials
# - clone the declared project repo into MAIN_REPO_DIR
# - bootstrap toolnix host state through the tracked remote-flake bootstrap script
# - install devenv after the cache-backed host baseline is active
# - activate persistent host state declaratively through Home Manager
#
# Intentionally out of scope:
# - Docker mode
# - host dotfiles management strategy
# - target-side clones of shared bootstrap repos such as toolnix, agent-skills, or claude-code-plugins
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
TOOLNIX_REPO_ROOT="${TOOLNIX_REPO_ROOT:-/home/exedev/git/lefant/toolnix}"
TOOLNIX_BOOTSTRAP_SCRIPT="$TOOLNIX_REPO_ROOT/scripts/bootstrap-home-manager-host.sh"
export BOOTSTRAP_SSH_KEY="${BOOTSTRAP_SSH_KEY:-$INVENTORY_ROOT/credentials/shared/ssh/exe-dev-bootstrap}"
REMOTE_SETUP_TIMEOUT_SECONDS="${REMOTE_SETUP_TIMEOUT_SECONDS:-600}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provision-common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/smoke-tests.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/provision-exe-dev-nix.sh <target-fqdn>

Environment:
  REMOTE_SETUP_TIMEOUT_SECONDS  Max seconds for the remote setup phase (default: 600)

Minimal host-native provisioner for exe.dev VMs using generated Home Manager
bootstrap derived from target inventory.

Reads target metadata from:
  targets/<target-fqdn>/config.env

Expected target fields:
  TARGET_FQDN
  REPO_URL
  MAIN_REPO_BRANCH
  MAIN_REPO_DIR

Optional:
  TOOLNIX_MODE   Defaults to devenv; legacy TOOLBOX_MODE is still accepted
  HOME_MANAGER_HOST_NAME
  HOME_MANAGER_ENABLE_HOST_CONTROL
  HOME_MANAGER_ENABLE_AGENT_BASELINE
  HOME_MANAGER_ENABLE_AGENT_BROWSER
  HOME_USERNAME
  HOME_DIRECTORY
  HOME_STATE_VERSION
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET_FQDN="${1:?Usage: provision-exe-dev-nix.sh <target-fqdn>}"
TARGET_CONFIG="$INVENTORY_ROOT/targets/$TARGET_FQDN/config.env"
require_file "$TARGET_CONFIG"
require_file "$TOOLNIX_BOOTSTRAP_SCRIPT"
SHARED_ENV_FILE="$(shared_env_file "$INVENTORY_ROOT")"
require_file "$SHARED_ENV_FILE"

TARGET_MODE="$(config_value TOOLNIX_MODE "$TARGET_CONFIG")"
TARGET_MODE="${TARGET_MODE:-$(config_value TOOLBOX_MODE "$TARGET_CONFIG")}"
TARGET_MODE="${TARGET_MODE:-devenv}"
if [ "$TARGET_MODE" != "devenv" ]; then
  echo "ERROR: provision-exe-dev-nix.sh only supports TOOLNIX_MODE=devenv" >&2
  exit 1
fi

MAIN_REPO_DIR="$(config_value MAIN_REPO_DIR "$TARGET_CONFIG")"
MAIN_REPO_BRANCH="$(config_value MAIN_REPO_BRANCH "$TARGET_CONFIG")"
REPO_URL="$(config_value REPO_URL "$TARGET_CONFIG")"
TOOLNIX_REF="$(config_value TOOLNIX_REF "$TARGET_CONFIG")"
TOOLNIX_REF="${TOOLNIX_REF:-github:lefant/toolnix}"
INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY="$(config_value INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY "$TARGET_CONFIG")"
INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY="${INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY:-0}"
REMOTE_REPO_DIR="$(resolve_remote_path "$MAIN_REPO_DIR")"
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

if [ -z "$MAIN_REPO_DIR" ] || [ -z "$MAIN_REPO_BRANCH" ] || [ -z "$REPO_URL" ]; then
  echo "ERROR: target config must define MAIN_REPO_DIR, MAIN_REPO_BRANCH, and REPO_URL" >&2
  exit 1
fi

TARGET_FRAGMENT="$(target_env_fragment_file "$INVENTORY_ROOT" "$TARGET_FQDN")"
if ! grep -q '^GH_TOKEN=' "$SHARED_ENV_FILE" 2>/dev/null && \
   ! grep -q '^GH_TOKEN=' "$TARGET_FRAGMENT" 2>/dev/null; then
  echo "ERROR: GH_TOKEN is required for remote provisioning but not found in shared env file or target fragment for $TARGET_FQDN" >&2
  exit 1
fi

SSH_OPTS=(-i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
SSH_OPTS_STR="${SSH_OPTS[*]}"

log "Provisioning $TARGET_FQDN (minimal toolnix host-native path)"
ensure_exe_dev_vm "$TARGET_FQDN"

REMOTE_TMP=""
LOCAL_REMOTE_SCRIPT=""
cleanup() {
  if [ -n "$REMOTE_TMP" ]; then
    ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "rm -rf '$REMOTE_TMP'" >/dev/null 2>&1 || true
  fi
  if [ -n "$LOCAL_REMOTE_SCRIPT" ] && [ -f "$LOCAL_REMOTE_SCRIPT" ]; then
    rm -f "$LOCAL_REMOTE_SCRIPT"
  fi
}
trap cleanup EXIT

REMOTE_TMP="$(ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" 'mktemp -d')"

upload_credentials "$TARGET_FQDN" "$INVENTORY_ROOT" "$REMOTE_TMP" "$SSH_OPTS_STR" "$INSTALL_EXE_DEV_BOOTSTRAP_SSH_KEY"
scp "${SSH_OPTS[@]}" "$TOOLNIX_BOOTSTRAP_SCRIPT" "$TARGET_FQDN:$REMOTE_TMP/bootstrap-home-manager-host.sh"

LOCAL_REMOTE_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/provision-devenv-minimal.XXXXXX.sh")"
cat > "$LOCAL_REMOTE_SCRIPT" <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_TMP="$1"
REMOTE_REPO_DIR="$2"
MAIN_REPO_BRANCH="$3"
REPO_URL="$4"
HM_HOST_NAME="$5"
HM_ENABLE_HOST_CONTROL="$6"
HM_ENABLE_AGENT_BASELINE="$7"
HM_ENABLE_AGENT_BROWSER="$8"
HM_USERNAME="$9"
HM_HOME_DIRECTORY="${10}"
HM_STATE_VERSION="${11}"
TOOLNIX_REF="${12}"

log() { printf '\n==> %s\n' "$1"; }
warn() { printf '\nWARNING: %s\n' "$1" >&2; }

print_preflight_status() {
  log "Remote preflight status"
  df -h / /nix 2>/dev/null || df -h /
  ps -eo pid,etime,cmd | egrep 'nix|home-manager|cargo|rustc|go build' | egrep -v egrep | tail -n 20 || true
}

require_root_disk_headroom_mb() {
  local minimum_mb="$1"
  local available_mb
  available_mb="$(df -Pm / | awk 'NR==2 { print $4 }')"
  if [ -z "$available_mb" ] || [ "$available_mb" -lt "$minimum_mb" ]; then
    echo "ERROR: insufficient root disk headroom before provisioning (${available_mb:-unknown} MB available, need at least $minimum_mb MB)" >&2
    df -h / /nix 2>/dev/null || df -h /
    exit 1
  fi
}

bool_to_nix() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) printf 'true\n' ;;
    *) printf 'false\n' ;;
  esac
}

if ! command -v nix >/dev/null 2>&1; then
  log "Installing Nix"
  sh <(curl -L https://nixos.org/nix/install) --daemon --yes
fi

if ! command -v nix >/dev/null 2>&1; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

nix_flake_cmd() {
  nix --extra-experimental-features 'nix-command flakes' --accept-flake-config "$@"
}

print_preflight_status
require_root_disk_headroom_mb 8192

log "Installing minimal profile packages"
nix_flake_cmd profile install nixpkgs#direnv nixpkgs#git nixpkgs#gh nixpkgs#zsh 2>/dev/null || true
export PATH="$HOME/.nix-profile/bin:$PATH"
hash -r

log "Installing credentials"
cat "$REMOTE_TMP/env.toolnix" > "$HOME/.env.toolnix"
if [ -f "$REMOTE_TMP/env.toolnix.fragment" ]; then
  cat "$REMOTE_TMP/env.toolnix.fragment" >> "$HOME/.env.toolnix"
fi

mkdir -p "$HOME/.codex" "$HOME/.pi/agent" "$HOME/.local/share/opencode" "$HOME/.ssh" "$HOME/.ssh/sock"
if [ -f "$REMOTE_TMP/codex-auth.json" ]; then
  install -m 600 "$REMOTE_TMP/codex-auth.json" "$HOME/.codex/auth.json"
fi
if [ -f "$REMOTE_TMP/pi-agent-auth.json" ]; then
  install -m 600 "$REMOTE_TMP/pi-agent-auth.json" "$HOME/.pi/agent/auth.json"
fi
if [ -f "$REMOTE_TMP/opencode-auth.json" ]; then
  install -m 600 "$REMOTE_TMP/opencode-auth.json" "$HOME/.local/share/opencode/auth.json"
fi
if [ -f "$REMOTE_TMP/exe-dev-bootstrap" ]; then
  install -m 600 "$REMOTE_TMP/exe-dev-bootstrap" "$HOME/.ssh/exe-dev-bootstrap"
  install -m 644 "$REMOTE_TMP/exe-dev-bootstrap.pub" "$HOME/.ssh/exe-dev-bootstrap.pub"
fi

log "Configuring gh auth"
set -a
source "$HOME/.env.toolnix"
set +a
if [ -n "${GH_TOKEN:-}" ]; then
  printf '%s\n' "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
  gh auth setup-git 2>/dev/null || true
fi

clone_repo() {
  local url="$1" dir="$2" branch="$3"
  mkdir -p "$(dirname "$dir")"
  if [ -d "$dir/.git" ]; then
    log "Repo already exists: $dir"
    if git -C "$dir" fetch origin; then
      :
    else
      warn "git fetch failed for $dir; continuing with local repo state"
    fi
    if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$dir" checkout "$branch"
    elif git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git -C "$dir" checkout -B "$branch" "origin/$branch"
    else
      echo "ERROR: branch $branch not available locally in $dir" >&2
      exit 1
    fi
    git -C "$dir" pull --ff-only origin "$branch" || true
    return
  fi
  log "Cloning $url -> $dir (branch $branch)"
  local auth_url="$url"
  if [ -n "${GH_TOKEN:-}" ]; then
    auth_url="${url/https:\/\/github.com/https://${GH_TOKEN}@github.com}"
  fi
  git clone --branch "$branch" "$auth_url" "$dir"
  git -C "$dir" remote set-url origin "$url"
}

clone_repo "$REPO_URL" "$REMOTE_REPO_DIR" "$MAIN_REPO_BRANCH"

log "Running tracked toolnix host bootstrap script"
bash "$REMOTE_TMP/bootstrap-home-manager-host.sh" \
  --toolnix-ref "$TOOLNIX_REF" \
  --host-name "$HM_HOST_NAME" \
  --home-username "$HM_USERNAME" \
  --home-directory "$HM_HOME_DIRECTORY" \
  --state-version "$HM_STATE_VERSION" \
  --backup-extension pre-toolnix-bootstrap \
  $( [ "$HM_ENABLE_HOST_CONTROL" = "1" ] && printf '%s ' -- '--enable-host-control' ) \
  $( [ "$HM_ENABLE_AGENT_BASELINE" = "0" ] && printf '%s ' -- '--disable-agent-baseline' ) \
  $( [ "$HM_ENABLE_AGENT_BROWSER" = "1" ] && printf '%s ' -- '--enable-agent-browser' )

log "Installing devenv after cache-backed host bootstrap"
nix_flake_cmd profile install nixpkgs#devenv 2>/dev/null || true
hash -r

log "Installing devenv direnvrc"
mkdir -p "$HOME/.config/direnv"
devenv direnvrc > "$HOME/.config/direnv/direnvrc"

log "Minimal toolnix host-native provisioning complete"
REMOTE_SCRIPT

log "Running remote host-native setup"
scp "${SSH_OPTS[@]}" "$LOCAL_REMOTE_SCRIPT" "$TARGET_FQDN:$REMOTE_TMP/remote-host-native-setup.sh"
if ! timeout --foreground "$REMOTE_SETUP_TIMEOUT_SECONDS" \
  ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" \
    "bash '$REMOTE_TMP/remote-host-native-setup.sh' \
      '$REMOTE_TMP' '$REMOTE_REPO_DIR' '$MAIN_REPO_BRANCH' '$REPO_URL' \
      '$HOME_MANAGER_HOST_NAME' '$HOME_MANAGER_ENABLE_HOST_CONTROL' \
      '$HOME_MANAGER_ENABLE_AGENT_BASELINE' '$HOME_MANAGER_ENABLE_AGENT_BROWSER' \
      '$HOME_USERNAME_VALUE' '$HOME_DIRECTORY_VALUE' '$HOME_STATE_VERSION_VALUE' \
      '$TOOLNIX_REF'"; then
  printf '\nWARNING: Remote setup failed or timed out after %ss; collecting remote status\n' "$REMOTE_SETUP_TIMEOUT_SECONDS" >&2
  ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "df -h / /nix 2>/dev/null || df -h /; echo ---; ps -eo pid,etime,cmd | egrep 'nix|home-manager|cargo|rustc|go build' | egrep -v egrep | tail -n 40 || true; echo ---; if [ -f /etc/nix/nix.custom.conf ]; then sudo cat /etc/nix/nix.custom.conf; fi" || true
  exit 1
fi

run_smoke_tests "$TARGET_FQDN" "$TARGET_MODE" "$REMOTE_REPO_DIR" "$SSH_OPTS_STR"
print_manual_checks "$TARGET_FQDN" "$TARGET_MODE"

log "Provisioning complete: $TARGET_FQDN"
