---
title: Refactoring plan — conventions alignment
type: plan
---

# Refactoring plan

Work that **touches multiple files**, so it is proposed rather than done. Measured against
the tree on 2026-08-25, after the in-file pass. Baseline suite: **1463 passing / 17 failing /
17588 asserts** — every item below must leave that unchanged or better.

Ordered by value per unit of risk. Each is independently shippable.

---

## 1. Standardise time on seconds — **highest value, real correctness bug**

**Problem.** Four vocabularies for one dimension (`_ticks` ×11, `_time` ×19, `_seconds` ×6,
`_frames` ×7), and the tick→second factor is expressed **two ways at once**:

- `scripts/maps/time_utils.gd` derives it — `a_seconds * Engine.physics_ticks_per_second` — and
  survives a change to the physics rate.
- `tools/spec_import/scene_sync.gd` **hardcodes `* 30.0` in four places**.

Change the physics rate today and every imported cooldown, reload and split time is silently
wrong while the runtime adapts correctly. `Projectile.speed` is per **tick** while
`Movement.speed` is per **second** — same name, 30× apart.

**Plan**
1. Add `TimeUtils.TICKS_PER_SECOND` derived from `Engine.physics_ticks_per_second`; make it
   the single expression of the factor.
2. Replace the four hardcoded `30.0`s in `scene_sync.gd` with it.
3. Rename tick-valued identifiers to carry their unit (`cooldown_ticks` stays; bare
   `build_time` → `build_time_seconds` or `_ticks` as appropriate).
4. Convert `Projectile.speed` to per-second at the component boundary so both `speed`
   identifiers mean one thing, and the importer stops dividing.

**Risk** medium — touches importer, projectiles, movement. **Mitigation:** step 2 alone is a
pure bug fix and can ship on its own. Regenerate `resources/generated/` and diff: a correct
change produces **no** diff there.

---

## 2. Give `Ability` an overridable range evaluator

**Problem.** The case that prompted the convention. `Ability` hardcodes
`const RANGE: float = 5.0` — one range for every ability that will ever exist. When Bombard
needed unlimited reach gated on vision-by-proxy, it could not be expressed, so **`Bombard`
was written as a separate command class** duplicating Ability's shape and substituting
`BombardTargeting.is_spotted(...)` for the distance check.

This is the sibling-instead-of-instance smell in `~/.claude/CLAUDE.md` §1.3.

**Plan**
1. Replace `Ability.RANGE` with an overridable `is_in_range(a_actor, a_message) -> bool`,
   defaulting to the current XZ distance test against a per-ability value.
2. Move the ability's range off the class constant onto the ability's own spec.
3. Re-express `Bombard` as an `Ability` whose `is_in_range` consults spotting.
4. Delete the duplicated precondition/targeting scaffolding.

**Risk** medium-high — changes a command hierarchy. **Mitigation:** steps 1–2 are
behaviour-preserving on their own (default evaluator reproduces today's test); step 3 is the
only behavioural step and `tests/test_Bombard*.gd` covers it. **Recommend stopping after
step 2 for review.**

---

## 3. Adopt a linter and formatter

**Problem.** No `gdlint`/`gdformat` config, no `.editorconfig`, no pre-commit hook, no CI
workflow. Per `~/.claude/CLAUDE.md` §6.3 this is required in every project, and it is the
convention furthest from current reality.

**Plan**
1. Add `gdtoolkit` config and an `.editorconfig` fixing indentation (the tree is 2-space; a
   formatter run will otherwise reindent ~200 files in one commit).
2. **Run the formatter in its own commit, touching nothing else**, so the noise is isolated.
3. Add a lint script; wire CI once the tree is clean.
4. Hook enforcement deferred — you said you'd decide separately.

**Risk** low, but step 2 produces an enormous diff. Do it alone and never alongside logic.

---

## 4. Settle the `a_` parameter prefix

**Problem.** 365 of ~1,148 parameters carry it — about a third. The rule is now: **`a_` on
non-static functions, bare on static ones.**

**Plan.** Mechanical rename, one directory per commit. Local to each signature and its body,
so it cannot change behaviour — but it touches nearly every file, so it must not ride along
with anything else.

**Risk** low; volume high. Best done immediately after item 3 so the formatter has settled.

---

## 5. Continue the documentation escalation

**Done:** 26 functions moved into system notes (the last 16 on 2026-10-08: every block at least
twice its function's length outside the bot's files).
**Remaining:** 43 blocks above the threshold (comment block ≥12 lines and longer than the
function it documents). Only the 13 clear cases (≥ 2× the function) are to be escalated —
all in `scripts/interface/commander/bot*.gd`, held back for the bot session (gdd/tasks.md
T-087); the marginal ones stay where they are.

**Plan.** Same mechanism: keep the summary sentence, move the rationale to the owning system
note, leave a `§`-anchored pointer. Verify with the same check — every removed sentence must
appear in a note before the commit lands.

**Risk** low; comment-only. Worth batching by target note.

---

## 7. Fix `tests/test_Garrison.gd` — a silently skipped file

**Problem.** It fails to parse (line 25), and a GUT file that does not parse is **skipped, not
failed**. Whatever it covers has not been tested for some time while the suite reported green.
It also `preload`s entity scenes at file scope, which per your own note can poison the `Tool`
registry for the whole run.

**Plan.** Fix the parse error, convert the file-scope `preload`s to in-test `load`s, confirm
the test count rises.

**Risk** low. **Do this first** — it is small and it tells you what else is currently unmeasured.

---

## Suggested order

**7** (small, reveals unknowns) → **1 step 2** (pure bug fix) → **3** (tooling, isolated
commits) → **4** (mechanical, after formatting) → **5** (comment-only) → **1 rest**
→ **2** (stop at step 2 for review).
