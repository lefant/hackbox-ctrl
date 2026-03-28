#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
TOOLNIX_REPO_ROOT="${TOOLNIX_REPO_ROOT:-$INVENTORY_ROOT/sources/toolnix}"
SHARED_REPO_ROOT="$TOOLNIX_REPO_ROOT"
CLAUDE_TEMPLATE_ROOT="$SHARED_REPO_ROOT/agents/claude/templates"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON_PATH="$HOME/.claude.json"
CLAUDE_SETTINGS_PATH="$CLAUDE_DIR/settings.json"

log() {
  printf '==> %s\n' "$1"
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

merge_json_defaults() {
  local template_path="$1"
  local dest_path="$2"
  local tmp_path

  tmp_path="$(mktemp "${TMPDIR:-/tmp}/claude-config.XXXXXX.json")"

  if [ -f "$dest_path" ]; then
    jq -s '.[0] * .[1]' "$template_path" "$dest_path" > "$tmp_path"
  else
    cp "$template_path" "$tmp_path"
  fi

  install -m 600 "$tmp_path" "$dest_path"
  rm -f "$tmp_path"
}

rewrite_host_statusline_path() {
  local dest_path="$1"
  local tmp_path
  local host_statusline_path="$SHARED_REPO_ROOT/agents/claude/scripts/statusline.sh"

  tmp_path="$(mktemp "${TMPDIR:-/tmp}/claude-config.XXXXXX.json")"

  jq --arg host_statusline_path "$host_statusline_path" '
    if (.statusLine.command // "") == "/opt/toolnix/agents/claude/scripts/statusline.sh"
       or (.statusLine.command // "") == "/opt/toolbox/agents/claude/scripts/statusline.sh" then
      .statusLine.command = $host_statusline_path
    else
      .
    end
  ' "$dest_path" > "$tmp_path"

  install -m 600 "$tmp_path" "$dest_path"
  rm -f "$tmp_path"
}

main() {
  require_cmd jq
  require_file "$CLAUDE_TEMPLATE_ROOT/dot-claude.json"
  require_file "$CLAUDE_TEMPLATE_ROOT/settings.json"

  mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/projects"

  log "Seeding ~/.claude.json"
  merge_json_defaults "$CLAUDE_TEMPLATE_ROOT/dot-claude.json" "$CLAUDE_JSON_PATH"

  log "Seeding ~/.claude/settings.json"
  merge_json_defaults "$CLAUDE_TEMPLATE_ROOT/settings.json" "$CLAUDE_SETTINGS_PATH"
  rewrite_host_statusline_path "$CLAUDE_SETTINGS_PATH"
}

main "$@"
