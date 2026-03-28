#!/usr/bin/env bash
# provision-exe-dev-nix.sh — minimal host-native Nix/devenv provisioner for exe.dev VMs
#
# Scope:
# - ensure the VM exists
# - install Nix + minimal profile tooling
# - place credentials
# - clone the declared repo and the shared toolnix repo
# - generate a host-specific Home Manager bootstrap config from target data
# - activate persistent host state declaratively through Home Manager
#
# Intentionally out of scope:
# - Docker mode
# - host dotfiles management strategy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
export BOOTSTRAP_SSH_KEY="${BOOTSTRAP_SSH_KEY:-$INVENTORY_ROOT/credentials/shared/ssh/exe-dev-bootstrap}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provision-common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/smoke-tests.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/provision-exe-dev-nix.sh <target-fqdn>

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

log() { printf '\n==> %s\n' "$1"; }
warn() { printf '\nWARNING: %s\n' "$1" >&2; }

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

log "Configuring /etc/nix/nix.conf"
sudo tee /etc/nix/nix.conf >/dev/null <<'NIXCONF'
build-users-group = nixbld
experimental-features = nix-command flakes
accept-flake-config = true
trusted-users = root exedev
substituters = https://cache.nixos.org https://devenv.cachix.org https://cache.numtide.com
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= cache.numtide.com-1:VaxqhRn+S+2+dPBM+Op/sZ5wlbXIfJMyFwEql5HTYLI= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
NIXCONF

sudo systemctl restart nix-daemon

log "Installing minimal profile packages"
nix profile install nixpkgs#devenv nixpkgs#direnv nixpkgs#git nixpkgs#gh nixpkgs#zsh 2>/dev/null || true

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

log "Installing devenv direnvrc"
mkdir -p "$HOME/.config/direnv"
devenv direnvrc > "$HOME/.config/direnv/direnvrc"

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

TOOLNIX_DIR="$HOME/sources/toolnix"
if [ "$REMOTE_REPO_DIR" != "$TOOLNIX_DIR" ]; then
  clone_repo "https://github.com/lefant/toolnix.git" "$TOOLNIX_DIR" "main"
fi
clone_repo "https://github.com/lefant/agent-skills.git" "$HOME/sources/agent-skills" "main"
clone_repo "https://github.com/lefant/claude-code-plugins.git" "$HOME/sources/claude-code-plugins" "main"

BOOTSTRAP_DIR="$REMOTE_TMP/toolnix-home-bootstrap"
mkdir -p "$BOOTSTRAP_DIR"

log "Rendering Home Manager bootstrap flake"
cat > "$BOOTSTRAP_DIR/flake.nix" <<EOF
{
  description = "Generated bootstrap for ${HM_HOST_NAME}";

  inputs = {
    toolnix.url = "path:${TOOLNIX_DIR}";
    nixpkgs.follows = "toolnix/nixpkgs";
    home-manager.follows = "toolnix/home-manager";
  };

  outputs = { nixpkgs, home-manager, toolnix, ... }:
    let
      system = "x86_64-linux";
    in {
      homeConfigurations.bootstrap = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        extraSpecialArgs = { inputs = toolnix.devenvSources; };
        modules = [
          toolnix.homeManagerModules.default
          {
            home.username = "${HM_USERNAME}";
            home.homeDirectory = "${HM_HOME_DIRECTORY}";
            home.stateVersion = "${HM_STATE_VERSION}";

            toolnix.hostName = "${HM_HOST_NAME}";
            toolnix.enableHostControl = $(bool_to_nix "$HM_ENABLE_HOST_CONTROL");
            toolnix.enableAgentBaseline = $(bool_to_nix "$HM_ENABLE_AGENT_BASELINE");
            toolnix.agentBrowser.enable = $(bool_to_nix "$HM_ENABLE_AGENT_BROWSER");
          }
        ];
      };
    };
}
EOF

log "Building Home Manager activation"
nix build "$BOOTSTRAP_DIR#homeConfigurations.bootstrap.activationPackage"

log "Switching Home Manager profile"
nix run github:nix-community/home-manager -- switch -b pre-toolnix-bootstrap --flake "$BOOTSTRAP_DIR#bootstrap"

log "Minimal toolnix host-native provisioning complete"
REMOTE_SCRIPT

log "Running remote host-native setup"
scp "${SSH_OPTS[@]}" "$LOCAL_REMOTE_SCRIPT" "$TARGET_FQDN:$REMOTE_TMP/remote-host-native-setup.sh"
ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" \
  "bash '$REMOTE_TMP/remote-host-native-setup.sh' \
    '$REMOTE_TMP' '$REMOTE_REPO_DIR' '$MAIN_REPO_BRANCH' '$REPO_URL' \
    '$HOME_MANAGER_HOST_NAME' '$HOME_MANAGER_ENABLE_HOST_CONTROL' \
    '$HOME_MANAGER_ENABLE_AGENT_BASELINE' '$HOME_MANAGER_ENABLE_AGENT_BROWSER' \
    '$HOME_USERNAME_VALUE' '$HOME_DIRECTORY_VALUE' '$HOME_STATE_VERSION_VALUE'"

run_smoke_tests "$TARGET_FQDN" "$TARGET_MODE" "$REMOTE_REPO_DIR" "$SSH_OPTS_STR"
print_manual_checks "$TARGET_FQDN" "$TARGET_MODE"

log "Provisioning complete: $TARGET_FQDN"
