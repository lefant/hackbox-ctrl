#!/usr/bin/env bash
# verify-general-machine-readiness.sh — print the interactive acceptance procedure
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

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-general-machine-readiness.sh <target-name>

Print the interactive acceptance procedure for a general machine target.
This complements automated smoke tests; it is intentionally not a full
automated verifier.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET="${1:?Usage: verify-general-machine-readiness.sh <target-name>}"
if [[ "$TARGET" != *.exe.xyz ]]; then
  TARGET="$TARGET.exe.xyz"
fi

TARGET_CONFIG="$INVENTORY_ROOT/targets/$TARGET/config.env"
if [ ! -f "$TARGET_CONFIG" ]; then
  echo "ERROR: target config not found: $TARGET_CONFIG" >&2
  exit 1
fi

MAIN_REPO_DIR="$(config_value MAIN_REPO_DIR "$TARGET_CONFIG")"
REMOTE_REPO_DIR="$(resolve_remote_path "$MAIN_REPO_DIR")"

cat <<USAGE
Interactive acceptance procedure for general machine: $TARGET

Purpose:
- validate shell, tmux, and live agent behavior that the smoke tests do not try to prove
- record operator or coding-agent evidence against
  docs/specs/control-host-and-target-agent-readiness.md

Recommended entry:
- scripts/target-ssh.sh ${TARGET%.exe.xyz} tmux
- equivalent raw SSH:
  ssh -tt $TARGET 'zsh -ilc '"'"'cd $REMOTE_REPO_DIR && tmux-here'"'"''

Inside the target tmux session, verify:

1. Project context
   pwd
   git branch --show-current

2. Shell baseline
   type e
   which mg
   which bat
   locale | grep '^LANG='
   echo "\$TZ"
   date
   whence -w compinit
   zstyle -L ':completion:*' | grep 'special-dirs true'
   In zsh, verify that typing '..' then TAB completes as a directory path and appends '/'.

3. Explicit environment entry
   devenv shell -- printenv DEVENV_ROOT

4. GitHub and repo workflow
   gh auth status
   git pull --ff-only
   Use a safe branch or other prepared workflow if you need to prove push capability.

5. tmux behavior
   Start by noting whether tmux emitted any startup warnings.
   Invalid default-shell paths, invalid color settings, or similar config warnings are a readiness failure.
   echo "\$TMUX_COLOUR"
   Visually inspect that the status bar clock reflects Stockholm time.
   Treat a stale one-hour-behind UTC-like tmux clock as a readiness failure even if shell \`TZ\` and \`date\` look correct.
   Visually inspect that the status bar color is not the default tmux green.

6. Live agent readiness
   claude
   Confirm no first-run blocker appears, then run a simple pong prompt.
   codex
   Confirm no first-run blocker appears.
   Specifically treat a directory-trust confirmation prompt for the checked out project repo as a readiness failure.
   Then run a simple pong prompt.
   pi
   Confirm no first-run blocker appears, the prompt is readable, and no missing-auth or missing-credential warnings appear before ordinary use.
   Verify Pi keybindings:
   - newline: Ctrl-J, Ctrl-M, Shift-Enter, Alt-Enter, Enter
   - submit: Alt-J, Alt-M
   - follow-up queue: Alt-Q
   - restore/edit queued: Alt-Up, Alt-P
   claude / codex multiline behavior
   Verify Ctrl-J, Ctrl-M, and Shift-Enter produce newline behavior to the degree supported by the current CLI builds.

7. Custom skill usability
   Ask one agent to use a custom skill such as github-access or tasknotes.
   For Claude, also verify slash-command availability if relevant to the target.

Record:
- pass/fail notes for each section
- any first-run prompts or auth blockers
- whether the session felt operator-usable without workaround steps
USAGE
