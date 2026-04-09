#!/usr/bin/env bash
# provision-common.sh — shared functions for provisioning scripts
set -euo pipefail

log() {
  printf '\n==> %s\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command missing: $cmd" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "ERROR: required file not found: $path" >&2
    exit 1
  fi
}

config_value() {
  local key="$1"
  local config_file="$2"
  sed -n "s/^${key}=//p" "$config_file" | tail -n 1
}

resolve_remote_path() {
  local path="$1"
  local resolved="$path"
  # Expand $HOME to /home/exedev for remote paths
  resolved="${resolved/\$HOME/\/home\/exedev}"
  case "$resolved" in
    '$HOME'/*) resolved="/home/exedev/${resolved#\$HOME/}" ;;
  esac
  printf '%s\n' "$resolved"
}

ensure_exe_dev_vm() {
  local fqdn="$1"
  local ssh_key="${BOOTSTRAP_SSH_KEY:-}"

  # Check if VM is reachable
  local ssh_opts=()
  if [ -n "$ssh_key" ]; then
    ssh_opts+=(-i "$ssh_key")
  fi
  ssh_opts+=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

  if ssh "${ssh_opts[@]}" "$fqdn" true 2>/dev/null; then
    log "VM $fqdn is reachable"
    return 0
  fi

  log "VM $fqdn not reachable, creating via exe.dev"
  local short_name="${fqdn%.exe.xyz}"
  ssh exe.dev new --name="$short_name" --no-email

  # Wait for VM to become reachable
  local attempts=0
  while [ "$attempts" -lt 30 ]; do
    if ssh "${ssh_opts[@]}" "$fqdn" true 2>/dev/null; then
      log "VM $fqdn is now reachable"
      return 0
    fi
    sleep 5
    attempts=$((attempts + 1))
  done

  echo "ERROR: VM $fqdn did not become reachable after creation" >&2
  exit 1
}

shared_env_file() {
  local inventory_root="$1"
  local path="$inventory_root/credentials/shared/env.toolnix"
  require_file "$path"
  printf '%s\n' "$path"
}

target_env_fragment_file() {
  local inventory_root="$1"
  local fqdn="$2"
  printf '%s\n' "$inventory_root/credentials/targets/$fqdn/env.toolnix.fragment"
}

upload_credentials() {
  local fqdn="$1"
  local inventory_root="$2"
  local remote_tmp="$3"
  local ssh_opts_str="$4"
  local install_exe_dev_bootstrap_ssh_key="${5:-0}"

  # Parse ssh opts from string
  local -a ssh_opts
  read -ra ssh_opts <<< "$ssh_opts_str"

  log "Uploading credentials"
  local shared_env
  shared_env="$(shared_env_file "$inventory_root")"
  scp "${ssh_opts[@]}" \
    "$shared_env" \
    "$fqdn:$remote_tmp/env.toolnix"

  if [ -f "$inventory_root/credentials/shared/codex/auth.json" ]; then
    scp "${ssh_opts[@]}" \
      "$inventory_root/credentials/shared/codex/auth.json" \
      "$fqdn:$remote_tmp/codex-auth.json"
  fi

  if [ -f "$inventory_root/credentials/shared/pi-agent/auth.json" ]; then
    scp "${ssh_opts[@]}" \
      "$inventory_root/credentials/shared/pi-agent/auth.json" \
      "$fqdn:$remote_tmp/pi-agent-auth.json"
  fi

  if [ -f "$inventory_root/credentials/shared/opencode/auth.json" ]; then
    scp "${ssh_opts[@]}" \
      "$inventory_root/credentials/shared/opencode/auth.json" \
      "$fqdn:$remote_tmp/opencode-auth.json"
  fi

  if [ "$install_exe_dev_bootstrap_ssh_key" = "1" ] && [ -f "$inventory_root/credentials/shared/ssh/exe-dev-bootstrap" ]; then
    scp "${ssh_opts[@]}" \
      "$inventory_root/credentials/shared/ssh/exe-dev-bootstrap" \
      "$inventory_root/credentials/shared/ssh/exe-dev-bootstrap.pub" \
      "$fqdn:$remote_tmp/"
  fi

  local fragment
  fragment="$(target_env_fragment_file "$inventory_root" "$fqdn")"
  if [ -f "$fragment" ]; then
    scp "${ssh_opts[@]}" "$fragment" "$fqdn:$remote_tmp/env.toolnix.fragment"
  fi
}

configure_gh_auth() {
  local gh_token="$1"

  if [ -z "$gh_token" ]; then
    echo "WARNING: GH_TOKEN not set, skipping gh auth" >&2
    return 0
  fi

  printf '%s\n' "$gh_token" | gh auth login --with-token
  gh auth setup-git
}
