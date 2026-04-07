#!/usr/bin/env bash
# smoke-tests.sh — deterministic readiness checks for toolnix-managed hosts
set -euo pipefail

# Run a command on the remote inside the declared repo context.
# Usage: _remote_cmd <fqdn> <mode> <repo_dir> <ssh_opts_str> <cmd...>
_remote_cmd() {
  local fqdn="$1"
  local mode="$2"
  local repo_dir="$3"
  local ssh_opts_str="$4"
  shift 4
  local cmd="$*"
  local remote_cmd

  local -a ssh_opts
  read -ra ssh_opts <<< "$ssh_opts_str"

  if [ "$mode" != "devenv" ]; then
    printf 'ERROR: unsupported target mode for smoke tests: %s\n' "$mode" >&2
    return 1
  fi

  remote_cmd="cd '$repo_dir' && direnv exec . $cmd"
  ssh "${ssh_opts[@]}" "$fqdn" \
    "zsh -ilc $(printf '%q' "$remote_cmd")"
}

_smoke_result() {
  local name="$1"
  local ok="$2"
  local detail="${3:-}"

  if [ "$ok" = "1" ]; then
    printf '  ✓ %s' "$name"
  else
    printf '  ✗ %s' "$name"
  fi
  if [ -n "$detail" ]; then
    printf ' — %s' "$detail"
  fi
  printf '\n'
}

smoke_test_gh_auth() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    "gh api user --jq '.login'" 2>/dev/null)" || true
  if [ -n "$result" ]; then
    _smoke_result "gh auth" 1 "login=$result"
  else
    _smoke_result "gh auth" 0 "failed"
  fi
}

smoke_test_claude() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'claude -p "respond with just the word pong"' 2>/dev/null)" || true
  # Trim whitespace
  result="$(printf '%s' "$result" | xargs)"
  if printf '%s' "$result" | grep -qi 'pong'; then
    _smoke_result "claude" 1 "$result"
  else
    _smoke_result "claude" 0 "expected pong, got: $result"
  fi
}

smoke_test_codex() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'codex exec --skip-git-repo-check "respond with just the word pong"' 2>/dev/null)" || true
  result="$(printf '%s' "$result" | xargs)"
  if printf '%s' "$result" | grep -qi 'pong'; then
    _smoke_result "codex" 1 "$result"
  else
    _smoke_result "codex" 0 "expected pong, got: $result"
  fi
}

smoke_test_pi() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'timeout 45 pi -p "respond with just the word pong" 2>&1' 2>/dev/null)" || true
  local trimmed
  trimmed="$(printf '%s' "$result" | xargs)"
  if printf '%s' "$trimmed" | grep -qi 'pong' \
    && ! printf '%s' "$trimmed" | grep -Eqi 'warning|missing[- ]auth|missing[- ]credential|not authenticated|api key|login required|auth required'; then
    _smoke_result "pi" 1 "pong"
  else
    _smoke_result "pi" 0 "unexpected output: $trimmed"
  fi
}

smoke_test_pi_keybindings() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" '
    jq -e "
      .[\"tui.input.newLine\"] == [\"ctrl+j\",\"ctrl+m\",\"shift+enter\",\"alt+enter\",\"enter\"] and
      .[\"tui.input.submit\"] == [\"alt+j\",\"alt+m\"] and
      .[\"app.message.followUp\"] == [\"alt+q\"] and
      .[\"app.message.dequeue\"] == [\"alt+up\",\"alt+p\"]
    " ~/.pi/agent/keybindings.json >/dev/null && echo ok
  ' 2>/dev/null)" || true
  result="$(printf '%s' "$result" | tail -n 1)"
  if [ "$result" = "ok" ]; then
    _smoke_result "pi keybindings" 1 "expected bindings present"
  else
    _smoke_result "pi keybindings" 0 "unexpected ~/.pi/agent/keybindings.json"
  fi
}

smoke_test_environment_entry() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result

  local -a ssh_opts
  read -ra ssh_opts <<< "$ssh_opts_str"
  local remote_cmd
  remote_cmd="cd '$repo_dir' && devenv shell -- printenv DEVENV_ROOT"
  result="$(ssh "${ssh_opts[@]}" "$fqdn" \
    "zsh -ilc $(printf '%q' "$remote_cmd")" 2>/dev/null)" || true
  result="$(printf '%s' "$result" | tail -n 1)"
  if [ -n "$result" ]; then
    _smoke_result "environment entry" 1 "DEVENV_ROOT=$result"
  else
    _smoke_result "environment entry" 0 "devenv shell failed"
  fi
}

smoke_test_tools() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local tools="claude codex pi gh jq bat"
  local missing=""
  local tool
  for tool in $tools; do
    if ! _remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
      "which $tool" >/dev/null 2>&1; then
      missing="$missing $tool"
    fi
  done
  if [ -z "$missing" ]; then
    _smoke_result "tools" 1 "all found: $tools"
  else
    _smoke_result "tools" 0 "missing:$missing"
  fi
}

smoke_test_timezone() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local tz_value date_output
  tz_value="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'printf "%s" "$TZ"' 2>/dev/null)" || true
  date_output="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'date' 2>/dev/null)" || true
  tz_value="$(printf '%s' "$tz_value" | tail -n 1)"
  date_output="$(printf '%s' "$date_output" | tail -n 1)"
  if [ "$tz_value" = "Europe/Stockholm" ] && ! printf '%s' "$date_output" | grep -q ' UTC '; then
    _smoke_result "timezone" 1 "TZ=$tz_value"
  else
    _smoke_result "timezone" 0 "TZ=$tz_value date=$date_output"
  fi
}

smoke_test_skills() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  local -a ssh_opts
  read -ra ssh_opts <<< "$ssh_opts_str"
  result="$(ssh "${ssh_opts[@]}" "$fqdn" \
    "test -e ~/.claude/skills/github-access && readlink -f ~/.claude/skills/github-access 2>/dev/null" 2>/dev/null)" || true
  if [ -n "$result" ]; then
    _smoke_result "skills" 1 "github-access -> $result"
  else
    _smoke_result "skills" 0 "expected ~/.claude/skills/github-access"
  fi
}

smoke_test_zsh_completion() {
  local fqdn="$1" mode="$2" repo_dir="$3" ssh_opts_str="$4"
  local result
  result="$(_remote_cmd "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str" \
    'zsh -ilc '\''whence -w compinit >/dev/null && typeset -p _comps >/dev/null 2>&1 && test -r "$HOME/.zsh/completion" && grep -q "special-dirs true" "$HOME/.zsh/completion" && echo ok'\''' 2>/dev/null)" || true
  result="$(printf '%s' "$result" | tail -n 1)"
  if [ "$result" = "ok" ]; then
    _smoke_result "zsh completion" 1 "compinit + special-dirs active"
  else
    _smoke_result "zsh completion" 0 "expected compinit and completion defaults"
  fi
}

run_smoke_tests() {
  local fqdn="$1"
  local mode="$2"
  local repo_dir="$3"
  local ssh_opts_str="$4"

  printf '\n==> Running smoke tests (%s mode)\n' "$mode"
  smoke_test_gh_auth "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_tools "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_timezone "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_environment_entry "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_skills "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_zsh_completion "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_claude "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_codex "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_pi "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
  smoke_test_pi_keybindings "$fqdn" "$mode" "$repo_dir" "$ssh_opts_str"
}

print_manual_checks() {
  local fqdn="$1"
  local mode="$2"

  printf '\n==> Interactive acceptance recommended\n'
  printf '  • General-machine procedure: scripts/verify-general-machine-readiness.sh %s\n' "$fqdn"
  if [ "$mode" = "devenv" ]; then
    printf '  • Explicit environment entry uses devenv shell; direnv auto-activation is optional\n'
  fi
}
