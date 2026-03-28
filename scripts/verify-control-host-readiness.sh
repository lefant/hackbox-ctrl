#!/usr/bin/env bash
# verify-control-host-readiness.sh — print the interactive control-host procedure
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-control-host-readiness.sh [target-name]

Print the interactive acceptance procedure for the active control host.
An optional target name can be supplied for the target-entry or SSH workflow.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET="${1:-}"

cat <<USAGE
Interactive acceptance procedure for the active control host

Purpose:
- validate tmux-meta, control-plane shell behavior, and live fleet workflows
- complement smoke tests with session-shaped evidence

Baseline procedure:

1. Start the meta workflow
   tmux-meta
   Confirm a usable local ctrl session appears.

2. Enter the inventory workspace
   cd ~/git/lefant/hackbox-ctrl-inventory
   tmux-here

3. Verify shell and repo baseline
   type e
   which mg
   which bat
   locale | grep '^LANG='
   echo "\$TZ"
   date
   gh auth status
   git pull --ff-only
   Use a safe branch or other prepared workflow if you need to prove push capability.

4. Verify tmux behavior
   Visually inspect that tmux-meta uses the intended neutral control-host styling.
   In the nested session, inspect the status bar and confirm it is usable.

5. Verify control-host agent readiness
   claude
   codex
   pi
   Confirm all three are usable without first-run blockers.
   Treat missing-auth or missing-credential warnings from Pi as a readiness failure.
   Verify Pi keybindings:
   - newline: Ctrl-J, Ctrl-M, Shift-Enter, Alt-Enter, Enter
   - submit: Alt-J, Alt-M
   - follow-up queue: Alt-Q
   - restore/edit queued: Alt-Up, Alt-P
   Verify Claude and Codex multiline behavior with Ctrl-J, Ctrl-M, and Shift-Enter to the degree supported by the current CLI builds.
   Verify the exe-dev-fleet skill is discoverable from at least one agent.

6. Verify fleet workflow
   Run one real exe-dev-fleet overview workflow and confirm the output is derived from live machine state.

Target-entry workflow:
USAGE

if [ -n "$TARGET" ]; then
  cat <<USAGE
- if a target-entry alias is implemented, invoke it for: $TARGET
- otherwise compare the current behavior against:
  scripts/target-ssh.sh $TARGET tmux
USAGE
else
  cat <<'USAGE'
- if a target-entry alias is implemented, invoke it for one configured target
- otherwise compare the current behavior against:
  scripts/target-ssh.sh <target-name> tmux
USAGE
fi

cat <<'USAGE'
- confirm the workflow lands in the target repo and reattaches or creates tmux-here cleanly

Record:
- whether tmux-meta and nested tmux feel usable without workaround steps
- whether control-plane auth and repo operations succeed
- whether the fleet workflow returns real non-empty output
- whether the target-entry alias exists and behaves as specified
USAGE
