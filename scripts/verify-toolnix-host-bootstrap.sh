#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_ROOT="${HACKBOX_CTRL_INVENTORY_ROOT:-$REPO_ROOT/hackbox-ctrl-inventory}"
export BOOTSTRAP_SSH_KEY="${BOOTSTRAP_SSH_KEY:-$INVENTORY_ROOT/credentials/shared/ssh/exe-dev-bootstrap}"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provision-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-toolnix-host-bootstrap.sh <target-fqdn>

Run deterministic readiness checks for the host-bootstrap path that does not
require a project checkout.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

TARGET_FQDN="${1:?Usage: verify-toolnix-host-bootstrap.sh <target-fqdn>}"
SSH_OPTS=(-i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

ssh "${SSH_OPTS[@]}" "$TARGET_FQDN" "bash -se" <<'EOF'
set -euo pipefail

echo '== toolnix host-bootstrap readiness =='
command -v claude
command -v pi
ls -l ~/.claude/settings.json
ls -l ~/.claude/skills
ls -l ~/.pi/agent/settings.json
if [ -f ~/.env.toolnix ]; then
  echo '~/.env.toolnix present'
fi
echo 'ready'
EOF
