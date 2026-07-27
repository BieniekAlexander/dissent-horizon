---
title: Saying it plainly — Go and Fire
type: system-note
---

# Saying it plainly — Go and Fire

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Two orders that exist because the right-click could not express them. Both are about the
same gap: **`_resolve_command_class` reads a click as the most specific thing the selection
could be asking for**, which is right almost always and leaves the *least* specific asks —
"just move" and "just shoot, at nothing in particular" — with no way to be said at all.

They share the verb row with attack-move, stop and defend: A S D F G, the orders every unit
answers to. Making room for them is what moved Evacuate off `F` and down to `V`, beside Land
and Rearm — Evacuate needs a garrison, so it was never a generic verb, and the ability rows
are where a command that belongs to whoever carries the component belongs.

## Go — a move nothing may reinterpret

`command_move` was already a capability every mover and every producer advertised (movement,
or a producer's rally point); what it had no way to be was ARMED. Every route to a plain
`MoveCommand` was the fallback at the bottom of the resolution ladder, taken only when
nothing above it applied.

Arming it suppresses the ladder for one click. Two orders become expressible:

- **Crush.** There is no crush command and there should not be one — crushing is a physics
  consequence of a heavy thing arriving where a light thing is standing. What the player
  needs is a way to drive a truck AT an enemy without the click being read as an attack.
- **Shadow.** A move at a friendly unit is already a follow — `CommandReceiver._follow_target`
  makes that of it, so no follow command exists either — but the click at an ENEMY resolved
  to Attack before it could ever be a follow. A stealth unit tailing a target without opening
  fire is one armed press away, and needs no new machinery at all.

It is labelled **"Go"** in the HUD and stays `MoveCommand` in the code. The two names are
allowed to differ: "Move" is what the class does and "Go" is what the button distinguishes
itself by, beside a row of other things that also involve moving.

The order stays a plain `MoveCommand`, which matters for one thing that is easy to miss: a
stationary `can_rally()` commandable absorbs an EXACT `MoveCommand` as its rally point
(`Commandable._absorb_rally_commands`). So pressing G at a barracks and clicking sets the
rally, which is correct and needed no special case.

## Fire — shooting at a place

**`Attack` cannot hit the ground, and should not be taught to.** It is built end to end
around a target entity: `weapon_for_target`, `is_in_attack_range`, the pursuit leash, the
dive-contact gate and `Weapon.fire` all take one. The single hook that could have carried a
point is a null `message.target` — and that is the same null a DEAD target leaves behind.
That was tried: `Attack._target_attackable` still carries the note. Every finished engagement
read as an order to shell the ground where the victim had been standing, and the checks
downstream crashed on it. The ambiguity is not fixable while a live target and an absent one
share one field, so `FocusFire` is its own class.

**Not every weapon is offered it.** `Weapon.can_fire_at_ground()` asks two things, and
neither implies the other:

- the weapon is allowed at the ground layer at all (`target_mask`) — an anti-air battery has
  nothing to shoot at down there;
- it delivers its damage with a PROJECTILE. Melee damage is applied straight to a target
  entity, and a map coordinate is not one, so a bayonet has nothing it could do to a point.

**What the shot then does is the projectile's business, honestly so.** A blast lands and
splashes whatever is standing there; a single-target shot resolves onto the target it was
fired at — nobody — and hurts nothing. Shelling a chokepoint works, emptying a rifle into
bare dirt does not, and both are the right answer. That is why the gate above is about
whether the weapon *can be aimed*, not about whether the shot will *achieve* anything.

Range is measured differently from `Attack`'s, and it has to be: `SpaceUtils.is_in_attack_range`
is a physics query against the target's body, and there is no body at the far end. `FocusFire`
compares plain XZ distance against the ground range shape's radius, which is the whole of
what "in range" can mean for a point. Height is ignored for the same reason every
`AttackRange` is authored as a very tall cylinder — a slope must never deny a shot.

An **immobile** actor aimed past its reach is refused at order time
(`MoveCommand.unreachable_for_immobile`), rather than holding an order it can never walk
closer to fulfil.

### Open: one salvo, or until told to stop

Built as **sustained** — the actor keeps shelling the point until it is given another order.
That is what attack-ground means in the games that have it, and it is what makes the order
useful for holding a crossing under fire.

The cost, named because it is real: **ground does not die**, so nothing ends the order on its
own and the unit never goes idle. A Stop clears it, but the idle selectors will not find that
unit until the player does. A one-salvo version would have no such hole and would be a worse
order — you would re-issue it every two seconds. If the idle-selector cost turns out to bite,
the fix is a shot count or a duration on the order, not a change of default.

Tests: `tests/test_FocusFire.gd`, `tests/test_ExplicitMove.gd`.
