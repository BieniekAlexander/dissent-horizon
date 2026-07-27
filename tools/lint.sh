#!/usr/bin/env bash
# Lint every hand-written GDScript file against gdlintrc, and enforce TAB indentation.
#
# Requires gdtoolkit 4.x. Installed here with pipx (a plain `pip install --user` is refused
# by PEP 668 on this machine):   pipx install "gdtoolkit==4.*"
#
# addons/ is excluded: it is vendored third-party code and its style is not ours to
# enforce. scripts/generated/ is excluded because it is generated — the generator's
# output style is the generator's business (see ~/.claude/CLAUDE.md §10).
#
# NOTE: gdformat, gdtoolkit's formatter, is still deliberately NOT run here. Indentation is
# only one of the things it rewrites — it also re-wraps calls, splits `class X extends Y:`
# in two, and inserts blank lines before every `#endregion`, which this tree uses heavily.
# Measured: it would rewrite 477 of 493 files, and it cannot parse one of them at all
# (verbose_tooltip_button.gd's inline `if …: _dismiss()`). See gdd/systems/authoring/linting.md.
set -uo pipefail
cd "$(dirname "$0")/.."

FILES=()
while IFS= read -r f; do FILES+=("$f"); done \
  < <(find scripts tools tests -name '*.gd' -not -path 'scripts/generated/*' | sort)

status=0
gdlint "${FILES[@]}" || status=1

# --- Tab indentation -----------------------------------------------------------------
# GDScript's official style guide specifies tabs, and this is what holds the tree to it.
#
# gdlint CANNOT do this job. Its `mixed-tabs-and-spaces` check only matches mixing inside a
# SINGLE line's leading whitespace (`^(\t+ +| +\t+)`), so a file that is half tab-indented
# and half space-indented — the state Godot leaves behind, and the one that actually stops
# the file parsing — passes it clean. Measured: it found 0 of the 1 genuinely mixed file.
#
# THE REAL AUTHORITY IS A GODOT EDITOR SETTING, not this script.
# `text_editor/behavior/indent/type` is per-user, cannot be pinned by project.godot, and
# ANY Godot invocation — `--headless --import` included — rewrites every script in the tree
# to match it. That is what caused the 2026-09-10 incident (42 files reindented, the project
# stopped compiling) and it recurred on 2026-09-11. This check is the detector; the fix is
# always to set that option to Tabs.
python3 - "${FILES[@]}" <<'PY' || status=1
import re
import sys

TRIPLE = re.compile(r'"""|\'\'\'')
offenders = []
for path in sys.argv[1:]:
    in_string = False
    for number, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        # Leading whitespace inside a triple-quoted string is string CONTENT, not indentation.
        if not in_string and re.match(r"^ +\S", line):
            offenders.append(f"{path}:{number}: Error: Space indentation (tabs required)")
        if len(TRIPLE.findall(line)) % 2:
            in_string = not in_string

for line in offenders[:40]:
    print(line)
if len(offenders) > 40:
    print(f"... and {len(offenders) - 40} more")
if offenders:
    print(f"Failure: {len(offenders)} space-indented line(s).")
    print("If a Godot save did this, set Editor Settings -> Text Editor -> Behavior ->")
    print("Indent -> Type to Tabs; otherwise it will undo any repair on the next import.")
sys.exit(1 if offenders else 0)
PY

exit $status
