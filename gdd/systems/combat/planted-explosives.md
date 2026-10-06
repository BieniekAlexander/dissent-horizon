---
title: Planted explosives
type: system-note
---

# Planted explosives

*Design note for [Dissent Horizon](../../../CLAUDE.md).*

The Sapper's **Plant** ability rigs a charge; **Detonate** sets it off. The charge is a piece of
its own (`an_plantedCharge`, with the scene-authored `PlantedCharge` component), and its blast
is the `detonate` ability's emission — an area of radius 3 (`aoe_charge`), so a charge on the
ground hurts what stands around it and one on a carrier hurts the carrier's neighbours too.

## The mechanic

- **Plant** has **one charge**, and places a charge on a point on the ground or on a piece. The
  Sapper walks into reach and works on it — longer on a sturdier target — which a hit interrupts
  (it is a channel, like building). A **MECH** piece, unit or structure, whoever's, **carries** the
  charge: it rides on it. Anything else ordered as the target gets the charge on the ground where
  it stood; an aircraft carries nothing.
- **The Plant charge comes back 30 seconds after the charge it made has left play** — the timer
  does not run while the charge is in the world (`Abilities.hold_recharge`). One charge in play is
  one Sapper occupied.
- **It goes off** when its owner orders it (Detonate — given to the charge, or to its Sapper, from
  anywhere and without sight of it), when a charge on the ground is destroyed, or when its carrier
  dies. It does not go off on a timer.
- **It leaves play without going off** when its Sapper dies, or when an opponent repairs it away.
- **Stealthed** to opponents; a detector shows it. Its **owner** sees it, and can select it, only
  inside their own vision — it has none of its own. A charge on the ground is a LIGHT MECH piece
  with 50 HP that can be shot; one riding on a carrier has no body — shooting it is shooting the
  carrier.

## Defusing

- **Repair on a charge on the ground removes it** on first touch — an opponent's repair or its
  owner's. The owner's is how a charge is taken back; the Plant charge then starts its recharge.
- **Any heal on a carrier removes every enemy charge riding on it**, and every enemy beacon, whether
  or not the carrier is damaged: a repair, a heal aura, anything through `Defense.restore`. A
  staggered piece cannot be healed, so it sheds nothing until the stagger wears off.

## The command card

Plant and Detonate share a cell on the top row (R — Q and W hold Radiate and Spot). A Sapper
offers Plant while it has no charge in play and Detonate while it has; a charge offers Detonate.
Plant takes the cell while any selected Sapper has a Plant charge ready, and steps aside for
Detonate only once none has (`RTSController.selection_commands`). The card re-reads what the
selection offers a few times a second, so it flips as a charge goes down.

## Why it is shaped this way

The unit stops spending *itself* and starts spending *a charge*, which is the difference between a
coin flip and a standing threat — see [design-framework/decisions](../../design-framework/decisions.md)
§Grappler.

- **Killing the Sapper defuses the charge**, so the defender's answer is the attacker's own unit.
- **Killing the carrier does not** — it sets the charge off wherever the carrier stands, which makes
  a charged vehicle a liability to its own side. Driving it clear is the answer, and repairing it
  is the other.
- **Detection is the reaction window.** Under stealth, a side with no detector cannot see the
  charge to answer it, which makes accessible detection a matchup requirement (M1) rather than a
  nicety, and the term to tune if the charge proves too strong.
- **The held recharge prices the threat.** A Sapper cannot fan charges across a base: it places
  one, and is out of the game as a bomber until that one resolves.

**The charge that does not recharge while what it made still exists** is a general rule worth
naming: an emitted object holds its emitter's charge hostage. Anything that places a persistent
thing — a beacon, a drone, a mine — can be priced this way instead of by cooldown alone.

REJECTED: a ten-second fuse (the first version of this note). It gave both sides a fixed reaction
window; manual detonation replaced it, so the window is now whatever the owner leaves it.

REJECTED: `Interaction.Type.PLANT`, the enemy-MECH-only interaction this replaced. Its member
number (1) is left unused, since interaction types are serialised by number.

## Open

- TODO: **the charge's damage against armour.** Today's flat 10000 EXPLOSIVE kills anything. The
  intent is *very effective against MEDIUM, fairly effective against STRONG* — which waits on the
  structure armour policy (`tasks.md` T-046).
- TODO: **the recharge length.** Whether 30 s is long enough is unset; its reach against a base is
  worked in [design-framework/timings](../../design-framework/timings.md).
- TODO: **a second way to learn about a plant** — telling a player when the planting happens inside
  their own vision, whether or not they have detection. Deferred, not rejected.
- TODO: the CPU commander never plants or detonates.
