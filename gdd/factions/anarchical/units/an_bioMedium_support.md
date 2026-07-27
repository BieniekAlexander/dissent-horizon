---
kind: Entity
title: Hijacker
scene: res://scenes/entities/units/an/an_bioMedium_support.tscn
flavor:
  description: Steals enemy vehicles; expended doing it
  verbose: Walks up to a mechanical unit and takes it over, and is spent in the attempt
build:
  cost: {energy: 500}
  time: 20
  requires: [an_tech2]
defense:
  hp: 150
  armour: MEDIUM
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
ui: {grid: [4, 1], factions: [anarchists]}
---

# Hijacker

Its whole kit is one INTERACTION, not a weapon: walk up to an enemy or neutral
**MECH-frame unit**, work on it for 1.5s, and the vehicle changes hands to the Hijacker's
commander while the Hijacker itself is expended.

# Notes
- `Interaction.Type.HIJACK`, authored on the scene's `Interactor` — interactions are an
  array of sub-resources, so they stay scene-authored rather than doc-governed (see the
  spec importer README's "what belongs in a doc"). The Supply Truck's ABDUCT/DEPOSIT pair
  is the same shape
- **Units only, never structures.** A building changing hands is `Capture`'s job and has
  completely different bookkeeping — structure registry, infrastructure, terrain grid — so the
  precondition excludes anything with a `Structure` component outright
- **Non-friendly, not enemy-only**, matching ABDUCT: a derelict neutral vehicle is a
  legitimate prize
- The pairing with ABDUCT is deliberate and worth keeping in mind when balancing: the
  Colonials' Supply Truck takes the CREW (biological, light), the Hijacker takes the
  MACHINE (mech). Same interaction machinery, opposite frame
- **Stagger-blocked**, like PLANT. A hijacker under fire holds at the vehicle instead of
  completing, so the counterplay is simply shooting it while it works
- It carries an `interact_shape` (a 1.0-radius cylinder) rather than the default
  near-touch reach. Its target MOVES, and RVO keeps bodies apart — with touch-only reach
  a hijacker chases a tank forever without ever arriving. Same reason ABDUCT has one
- Expended via `defense.kill()`, not `queue_free()`, so the normal death path does the
  teardown (spatial partition, garrison release, production refunds). Accepted
  consequence: the ON_DEATH occurrence fires and the death sound plays, so a scenario
  counting hijacker deaths counts a successful hijack too. The Kamikaze is expended the
  same way and has the same property
- **Known gap:** a hijacked unit stays in its former owner's HUD selection until they
  reselect — `RTSController` prunes its selection on validity, not on ownership. Nothing
  could change hands before this, so the case had never arisen
- 1500 energy for a one-shot unit is priced as a super-unit trade: it must take something
  worth more than itself. Nothing has been balanced against it
