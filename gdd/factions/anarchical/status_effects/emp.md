---
kind: StatusEffect
title: emp
scene: res://scenes/entities/status_effects/emp.tscn
---

# EMP

The MECH counterpart of [[bio_stun]], and the same script: a `StunStatusEffect`
(`scripts/entities/effects/stun_status_effect.gd`) with `affects_frames = 2` (Mech) and
`duration_ticks = 60` (2s). A BIO target the projectile reaches is unaffected — the
effect removes itself in `_on_apply` rather than sitting inert, so `is_active()` never
lies about a target being stunned.

**No generalisation was needed to build this.** `StunStatusEffect` already carries the
two things an EMP wants: a `affects_frames` bitmask over `Defense.FrameType` (using
Garrison's own `FRAME_*` constants, so there is one frame/bit mapping in the project) and
a `duration_ticks` field. `bio_stun` is the same script with the other bit set. The mask
lives on the EFFECT rather than on the `EffectApplicator` because the applicator
duplicates its effect templates per recipient — so the effect is already the per-recipient
object, and a second copy of the rule on the applicator could only disagree with it.

A stun here is a HARD stop: `Commandable.is_stunned()` gates all command processing, so an
EMP'd vehicle neither moves nor fires. "Disabled but still mobile" would be a different
effect type and does not exist.

Applied by: Condor (`an_aircraftMedium_support`) in a radius, Juggernaut
(`an_bioHeavy_superUnit`) and Shock Trooper (`an_bioMedium_antiMech`) on a single target.

Registration only, per the spec importer's `kind: StatusEffect` schema — the tuning above
lives in the scene itself (`emp.tscn`), not in this doc.
