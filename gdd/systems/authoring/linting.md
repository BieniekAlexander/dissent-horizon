---
title: Linting and formatting
type: system-note
---

# Linting and formatting

`gdlint` and `gdformat --check` both run from `tools/lint.sh`. Both come from
[gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) 4.x:

```
pipx install "gdtoolkit==4.*"    # a plain `pip install --user` is refused by PEP 668 here
./tools/lint.sh
```

The config is `gdlintrc` at the repository root. `tools/lint.sh` covers `scripts/`,
`tools/` and `tests/`; `addons/` is vendored and `scripts/generated/` is generated, so
neither is ours to style.

---

## The config records conventions; it does not bend to the tree

Every disabled rule in `gdlintrc` names the convention it contradicts. The four that
matter:

* **`max-file-lines` and `max-public-methods`** — `~/.claude/CLAUDE.md` §Deferred settles
  this outright: file size limits are deliberately none, and cohesion is the test.
* **`class-definitions-order`** — this project orders a class body by `#region`, which is a
  different scheme, not an absent one.
* **`duplicated-load`** — hoisting a test's second `load` of an entity scene into a shared
  file-scope const is precisely the bug `CLAUDE.md` §A file-scope `preload`… describes: it
  poisons the `Tool` registry for the entire run.

Two regexes are widened rather than disabled, for a case the convention actually allows: a
`static var` spelled `SCREAMING_SNAKE` is a constant GDScript will not let be `const` (a
class reference, or a value read from the engine at load), and a test name may capitalise a
whole word for emphasis (`test_the_banner_sits_ABOVE_the_grid`). A camelCase name still
fails, which is the case §3.2 forbids.

---

## What is still outstanding

The tree reports **5 findings** (2026-10-02), down from 449 and from 982 before the config
existed. Both are recorded at the code:

| Finding | Count | State |
|---|--:|---|
| `function-name` | 4 | `VU.inXZ` / `onXZ` / `fromXZ` / `l1Norm`. Genuine §3.2 violations; ~174 call sites. PLANNED: the rename is approved (2026-09-24), not yet done. |
| `function-arguments-number` | 1 | `Tool._init` takes thirteen. The composition rework is what shortens it. |

---

## gdformat is the house style

**Decided 2026-09-24, run 2026-10-02.** Every hand-written script is formatted by gdformat at
line length 100 with tabs, and `tools/lint.sh` fails when `gdformat --check` would change a
file. Format with:

```
gdformat -l 100 <files>
```

Its choices are opinionated — a `push_error("…" % [...])` becomes a parenthesised block, a
ternary grows wrapping, `class X extends Y:` splits in two, `#endregion` gets blank lines —
and that was accepted with the decision. gdformat neither wraps comments nor splits string
literals; a line it leaves over 100 columns is wrapped by hand, and must stay as gdformat
leaves it.

**Three gdformat failure modes, found in the run** — write code so it never meets them:

- **A multiline lambda nested two brackets deep** formats to a closing line Godot rejects
  ("Unindent doesn't match the previous indentation level"); gdtoolkit's own parser accepts
  it, so lint passes and the game does not compile. Hoist the lambda to a local first.
- **Comments inside a dictionary of multiline lambdas, or just above a statement whose
  dictionary gdformat reflows,** are duplicated or moved — in one file ~150 times. Use named
  functions, or build the dictionary first, already in its final shape.
- **An enum or argument list with inline comments and no trailing comma** is joined onto one
  line with every comment stacked at the end. Keep the trailing comma.

The run was verified by token-comparing every file against the commit before it, comparing
every comment word for word, and `godot --check-only` on every script, then the whole suite.
Do the same for any bulk reformat.

## Indentation is enforced, and gdlint is not what enforces it

**The tree is tab-indented and `./tools/lint.sh` fails on any space-indented line** outside a
triple-quoted string (where leading whitespace is string content). Settled 2026-09-11, on the
grounds the style guide gives.

**gdlint cannot do this job.** Its `mixed-tabs-and-spaces` rule matches mixing only within a
SINGLE line's leading whitespace (`^(\t+ +| +\t+)`), so a file that is half tab-indented and
half space-indented passes it clean — and that is precisely the state that stops a file
parsing. Measured: it found 0 of the 1 genuinely mixed file in the tree. The check in
`tools/lint.sh` is therefore hand-rolled, and gdlint's own rule stays on beneath it.

**The real authority is a Godot editor setting, and the lint check is only a detector.**
`text_editor/behavior/indent/type` is per-user, cannot be pinned by `project.godot`, and
**every Godot invocation rewrites the whole tree to match it — `--headless --import`
included.** That was isolated by md5-ing a file across a bare `--import`. It is the mechanism
behind the 2026-09-10 incident (42 files reindented, project stopped compiling) and it
recurred on 2026-09-11 in the opposite direction, repeatedly undoing the conversion until the
setting was changed. A red indentation lint means that option needs setting to **Tabs**;
repairing the files without it buys one command's worth of peace.

## PLANNED — CI

Not wired. `.github/` does not exist, and the plan's rule is to wire CI *once the tree is
clean* — which is the line above, not this one.

## TODO — pre-commit hook

Deferred by `~/.claude/CLAUDE.md` §Deferred: linting is required (§6.3), mandating the hook
is a separate decision.
