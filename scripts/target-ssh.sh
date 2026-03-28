#!/usr/bin/env bash
# target-ssh.sh — self-contained, mode-aware target SSH entry
# Reads config.env directly from inventory targets/ dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"

config_value() {
  local key="$1"
  local config_file="$2"
  sed -n "s/^${key}=//p" "$config_file" | tail -n 1
}

resolve_remote_path() {
  local path="$1"
  local resolved="$path"
  resolved="${resolved/\$HOME/\/home\/exedev}"
  case "$resolved" in
    '$HOME'/*) resolved="/home/exedev/${resolved#\$HOME/}" ;;
  esac
  printf '%s\n' "$resolved"
}

config_mode() {
  local config_file="$1"
  local mode
  mode="$(config_value TOOLNIX_MODE "$config_file")"
  if [ -z "$mode" ]; then
    mode="$(config_value TOOLBOX_MODE "$config_file")"
  fi
  printf '%s\n' "${mode:-devenv}"
}

list_targets() {
  local config_path fqdn mode
  printf '%-40s %s\n' "TARGET" "MODE"
  printf '%-40s %s\n' "------" "----"
  while IFS= read -r config_path; do
    fqdn="$(basename "$(dirname "$config_path")")"
    mode="$(config_mode "$config_path")"
    printf '%-40s %s\n' "$fqdn" "$mode"
  done < <(find "$INVENTORY_ROOT/targets" -mindepth 2 -maxdepth 2 -name config.env | sort)
}

usage() {
  cat <<'USAGE'
Usage:
  target-ssh.sh <target-name>          SSH into target (runs zsh -ilc 'cd <repo> && tmux-here')
  target-ssh.sh <target-name> <recipe> SSH into target (runs just <recipe>)
  target-ssh.sh --list                 List all targets with mode

Target name can be the short name (e.g., lefant-toolbox-nix2) or the full
FQDN (e.g., lefant-toolbox-nix2.exe.xyz).
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  list_targets
  exit 0
fi

TARGET="${1:?Usage: target-ssh.sh <target-name> [recipe]}"
RECIPE="${2:-tmux}"

# Resolve short name to FQDN
if [[ "$TARGET" != *.exe.xyz ]]; then
  TARGET="$TARGET.exe.xyz"
fi

TARGET_CONFIG="$INVENTORY_ROOT/targets/$TARGET/config.env"
if [ ! -f "$TARGET_CONFIG" ]; then
  echo "ERROR: target config not found: $TARGET_CONFIG" >&2
  echo "Run 'target-ssh.sh --list' to see available targets." >&2
  exit 1
fi

TARGET_MODE="$(config_mode "$TARGET_CONFIG")"
MAIN_REPO_DIR="$(config_value MAIN_REPO_DIR "$TARGET_CONFIG")"
REMOTE_REPO_DIR="$(resolve_remote_path "$MAIN_REPO_DIR")"

if [ "$RECIPE" = "tmux" ]; then
  printf "ssh -tt %s 'zsh -ilc %q'\n" "$TARGET" "cd '$REMOTE_REPO_DIR' && tmux-here"
  exec ssh -tt "$TARGET" "zsh -ilc $(printf '%q' "cd '$REMOTE_REPO_DIR' && tmux-here")"
fi

printf 'ssh -tt %s '\''cd %s && just %s'\''\n' "$TARGET" "$REMOTE_REPO_DIR" "$RECIPE"
exec ssh -tt "$TARGET" "cd '$REMOTE_REPO_DIR' && just $RECIPE"
