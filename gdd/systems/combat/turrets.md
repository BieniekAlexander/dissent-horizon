---
title: Turrets
type: system-note
---

# Turrets

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

A **turret** is a weapon that aims on its own yaw rather than with its carrier's body
(`Weapon.turret`). Being turreted is a property of the weapon, not a movement class — see
[commitment-and-movement](../../design-framework/commitment-and-movement.md) §Movement classes
for why it matters (it takes the turn term out of kiting). The first turreted piece is the
Matilda: [cl_mechMedium_antiMech](../../factions/colonial/units/cl_mechMedium_antiMech.md).

## Authoring

Two weapon keys: `turret: true` and `turret_turn_rate:` (degrees per second, omitted = the
`Weapon` default). A `turret_turn_rate` on a weapon that is not a turret is a hard import
error, since it would sit in the doc doing nothing. The rest delay and the rest-swing factor
are `Weapon` constants (`TURRET_REST_DELAY_SECONDS`, `TURRET_REST_RATE_FACTOR`), not doc keys:
they do not vary between pieces yet (see [calibration-rules](../authoring/calibration-rules.md)
§Govern an export iff its value varies).

## The rules

- **A turret must point DIRECTLY at its target to fire** — the same hair
  `Movement.is_facing()` holds a turning body to, not an arc. Turn rates are meant to be high
  enough that a target outrunning the turret does not come up in play; if it does, that is a
  tuning problem to look at then, not something the rule absorbs.
- **The turret swings every tick an Attack or FocusFire holds a target**, including while
  closing, so it is usually already on target on arrival. The body never turns to aim a
  turret weapon; it still stops when in range, because stop-to-fire is unchanged.
- **Its yaw is relative to the body** (`Weapon.turret_yaw`, 0 = the body's forward). The
  turret turns with its hull and aiming makes that up — the same way a turret node parented to
  the hull will read it.
- **An idle turret holds its last bearing, then drifts home**: after
  `TURRET_REST_DELAY_SECONDS` without being aimed it swings back to forward at
  `TURRET_REST_RATE_FACTOR` of its aiming speed.
- **A non-turret weapon keeps the old rule**: the body turns to face the target
  ([attack-runs](aerial-operations/attack-runs.md) §A stationary attacker aims itself).

## Attacking while moving

**A turret holds its attack target through a movement order** (`Orders.held_attack_target`).
When a replacing order that is not itself an attack takes over from an Attack, the Attack's
target is kept, and each tick the turret aims at it and fires once aimed, loaded and locked on —
the same rules an Attack's turret fire follows — while the body carries out the move. It is
dropped when the target leaves range or sight, dies or is taken out of the world, stops being an
enemy (either side changed hands), when the unit holds fire, or when another Attack (which names
its own target) replaces the order. **A Stop keeps it**: hold fire is the order that means "stop
shooting", and Stop only stops the body (decided 2026-10-08).

Only a turret does this. A weapon the body aims faces the way the unit travels, so it still
stops to fire ([commitment-and-movement](../../design-framework/commitment-and-movement.md)
§Commitment, per action).

## The visual

**The model part shows the physics aim; it never leads it.** `Weapon.turret_visual_path` names
the model node that is the turret, and every change to `turret_yaw` — aiming and the rest
swing alike — is written straight to that node's `rotation.y`. There is no separate visual
easing, so what the player sees pointing at a target is what is allowed to fire.

- The node must sit on the turret's yaw axis and be **parented to the hull**, so its local
  yaw is body-relative exactly as `turret_yaw` is. The Matilda's model,
  `assets/meshes/entities/matilda_split.blend`, is authored that way: a `Turret` object
  parented to `Hull`, origin on the yaw axis.
- The path is **scene-authored, not a doc key**: which node of a model is the turret is a
  fact about the model, not the piece's stats.
- An empty path is a turret nobody has modelled yet — it aims, with nothing to show it. A
  path that is set but resolves to nothing warns once at `_ready`.
- Updated at the physics rate, like the body's own yaw (the project has no physics
  interpolation).
- The turret is also the frame its weapon's shots leave from: the Weapon node's position is
  read relative to the turret model, so a shot comes out of the barrel wherever it points
  ([projectiles](projectiles.md) §Where an emission leaves from).

## Not done

- Projectiles still leave from the weapon node at the unit's centre, not from the barrels.
- Barrel elevation: the Matilda's two barrels are separate pieces of the turret object, so
  they could become their own part if pitch is ever wanted.
- Bunker fire ignores turrets: a garrisoned occupant's weapon fires from its host with no
  aiming at all, turret or not.
