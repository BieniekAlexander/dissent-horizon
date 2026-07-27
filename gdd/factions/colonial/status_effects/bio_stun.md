---
kind: StatusEffect
title: bio_stun
scene: res://scenes/entities/status_effects/bio_stun.tscn
---

# Bio Stun

A tuned instance of the generic `StunStatusEffect`
(`scripts/entities/effects/stun_status_effect.gd`): 1 second (30 ticks), restricted to
`Defense.FrameType.BIO` hosts only (`affects_frames = 1`) — a MECH target the projectile
hits is unaffected.

**Nothing fires it today.** It was written for Morgan (`cl_aircraftLight_antiBio`), a
light aircraft whose whole design was this stun; that unit was cut and the Clipper
(`cl_aircraftLight_antiLight`) took its Air Field slot instead. The effect and its script
are kept deliberately — the mechanic is the considered part and outlived the unit that
was going to carry it, so the next "disable infantry" weapon points a projectile's
`status_effects:` at this id rather than re-deriving it.

Registration only, per the spec importer's `kind: StatusEffect` schema — the tuning
above lives in the scene itself (`bio_stun.tscn`), not in this doc.
