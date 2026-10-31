#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
AGENT=${1:-}
run_app_bridge() {
  local interpreter
  local candidates=()
  if [[ -n "${TMUX_AGENT_PYTHON:-}" ]]; then
    candidates=("$TMUX_AGENT_PYTHON")
  else
    candidates=(python3 python3.14 python3.13 python3.12 python3.11 python3.10)
  fi
  for interpreter in "${candidates[@]}"; do
    if command -v "$interpreter" >/dev/null 2>&1 &&
       "$interpreter" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
      exec "$interpreter" "$SCRIPT_DIR/app_bridge.py" "$@"
    fi
  done
  printf '%s\n' '{"status":"failed","error":"App bridge requires Python 3.10 or newer; set TMUX_AGENT_PYTHON to a supported interpreter","details":null}'
  exit 1
}
case "$AGENT" in
  codex-app|claude-app|reply)
    run_app_bridge "$@"
    ;;
esac
if [[ -z "$AGENT" || "$AGENT" == --help || "$AGENT" == -h ]]; then
  printf 'Usage: tmux-agent.sh <agent> <command> [args...]\nAdapters:\n'
  for adapter in "$SCRIPT_DIR"/adapters/*.sh; do
    basename "$adapter" .sh
  done
  printf 'App routes: codex-app, claude-app; callback: reply (Python 3.10+)\n'
  exit 0
fi
# Only load shipped adapters, never an arbitrary path or shell expression.
if [[ ! "$AGENT" =~ ^[a-z][a-z0-9-]*$ || ! -f "$SCRIPT_DIR/adapters/$AGENT.sh" ]]; then
  printf 'unsupported agent: %s\n' "$AGENT" >&2
  exit 1
fi
shift
source "$SCRIPT_DIR/adapters/$AGENT.sh"
source "$SCRIPT_DIR/lib/core.sh"
main "$@"
