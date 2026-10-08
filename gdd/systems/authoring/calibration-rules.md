---
title: Calibration rules
type: system-note
---

# Calibration rules

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

A piece's physics-facing numbers (ranges, speeds, turn rates, acceleration, projectile
velocity) are governed by a second validation pass, `tools/spec_import/spec_rules.gd`,
which runs after the per-key checks in `SpecRegistry`. The two ask different questions:
validation asks "is this value well-formed" and every answer is local to one key, while
a **calibration rule** asks "do these numbers make a unit", which never is — an aggro
radius is fine alone and wrong beside a longer weapon reach.

**Three verdicts, not two.** A roster with no exceptions to its norms is a roster with no
artillery in it, so a violated rule is not automatically a failure: it is `EXCEPTIONAL` if
the doc declares it (with a reason, in an `exceptions:` frontmatter block) and `UNACCEPTED`
— a hard error — if not. A declaration against a rule the piece does NOT violate is `STALE`
and also a hard error, which is what stops the block turning into a list of things that used
to be true. `STRUCTURAL` rules (physics impossibilities) refuse the declaration outright.
The full table and the mechanism live in `tools/spec_import/README.md` §Calibration rules;
the reasoning per rule is the doc comment on its `_check_*` function; the counterexamples
that shaped them are `tools/spec_import/spec_rules.gd` itself. Declared exceptions are printed on every
successful import.

**`ASSET` rules are reported, never failed.** A third severity says a piece is expected to
carry something — a model (`has_mesh_visual`), voice lines (`has_voice_lines`), a death sound
(`has_death_sound`). The importer assumes every such slot is wanted: an unfilled one is
`INCOMPLETE` and printed with its `AssetState` (`PLACEHOLDER` or `MISSING`), never an
error, because a missing asset crashes nothing. A waiver makes the slot `EXEMPT`, and goes
`STALE` once the slot is filled. What an asset slot is, and why the game itself stays silent
about unfilled ones: [ux/README.md](../ux/README.md) §Asset slots.

**Heuristics that are NOT enforced** — how fast a unit turns for its speed, when a long
reach should cost mobility, why brakes beat engines on the ground and not in the air, how
much a projectile has to lead a crossing target — are in `gdd/unit-calibration.md`, along
with the open questions this pass deliberately did not settle.

## Govern an export iff its value varies

The dividing line for what belongs in the doc schema is **variation, not category**: an
export earns a doc key when its value actually differs between pieces. One that is
identical everywhere is not a configuration — it is a constant wearing an export's clothes,
and exporting it makes the inspector claim a choice nobody is making. `EnergyExtractor.energy_rate`
is the type specimen (one component, one scene, one value, never touched); `Spotter` had two
such and now has zero exports, its reach and channel being `TARGETABLE`-style constants.

Variation is measured **within a role**, not across roles: five status effects having five
different durations is not variation, since each is configured once for itself.

The importer's own coverage pass is the forcing mechanism. Every gameplay `@export` is
classified GOVERNED / CONSTANT / SCENE / CANDIDATE with a stated reason, and an export
missing from that table fails the test — so adding one is a decision you have to record.
CANDIDATE is the debt list (it varies and has no doc key yet) and the test prints it.

**`movement:` and `weapons:` sub-keys are whitelisted**, and an unknown one is a hard error.
That omission is precisely how four chassis knobs came to live only in scenes — a doc that
sets an unrecognised key and is silently ignored reads as authority it does not have. It is
also what retires a key cleanly: `dive:` is gone, and a doc still carrying it says so.

## Two units that used to be spelled the same

An emission phase's `speed` is world-units per **tick** (`PhasedLocomotion` adds it to a position
once per `_physics_process`); the doc key is per **second**, and the importer divides by 30.
`Movement.speed` is per second on both sides. Before that conversion the two doc keys were
both spelled `speed:` and differed by a factor of 30 with nothing on the page to say so.
Every authored value was multiplied by 30 in the same pass, so no projectile changed speed.

## A dive is derived, not authored

A FLYING unit with a melee-reach weapon **is** a rammer, so `Weapon.dive_attack` (and the
`dive:` doc key that fed it) were replaced by `Weapon.is_melee_ranged()`. That export's own
comment had argued against this derivation, on the grounds that it "would silently change
how a unit attacks the next time somebody rebalanced a number" — true when nothing watched
the numbers, and no longer true now that `aerial_weapons_not_melee` refuses an undeclared
melee-reach fixed wing. The change cannot be silent any more, which was the whole objection.
NOT derived from "has a projectile": the kamikaze's blast is one.

---
