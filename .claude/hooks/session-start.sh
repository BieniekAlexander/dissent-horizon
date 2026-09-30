#!/bin/bash
# SessionStart hook for Claude Code on the web: gets Godot onto PATH and the project imported,
# so the GUT suite (CLAUDE.md §Running and testing) runs headlessly from the first prompt.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

"$PWD/tools/install_godot.sh"

# `.godot/` is git-ignored, so a fresh clone has no import cache and no class_name registry —
# scripts referencing a `class_name` fail to parse until this has run. It is cheap once cached.
# The engine reports leaked RIDs at exit even on success, so judge the run by the registry it writes.
godot --headless --path . --import >/dev/null 2>&1 || true
if [ ! -s .godot/global_script_class_cache.cfg ]; then
  echo "session-start: godot --import did not produce .godot/global_script_class_cache.cfg" >&2
  exit 1
fi
