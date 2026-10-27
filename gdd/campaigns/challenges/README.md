# Challenge series

Status: draft scoping, 2026-10-27; was a stub. Short, optional scenarios, each drilling one
skill the [prologue](../01-prologue/README.md) leaves out so as not to overwhelm new players.
Reached from Campaign > Challenges, which is greyed out as "(WIP)" today.

Nothing here is decided. Each challenge below is a proposal shaped by
[mission-design](../mission-design.md), with its questions at the end of this note.

## How a challenge differs from a mission

- **One skill per challenge**, about 2–5 minutes, taught in steps that get harder, not a story
  arc. A one-line framing is enough, and a narrative justification is optional.
- **Playable in any order** and after any amount of the prologue, so each assumes only
  prologue mission 1 (unit control, the camera, attacking).
- **Scored, not just passed** (proposed): a time or efficiency rating, so a challenge is worth
  replaying.
- What carries over from missions: an `ObjectiveChain` that reads the steps, one How to Play note
  per skill raised just before it is needed, scripted-only bots, everything present from the
  first frame placed in the scene, and failure conditions that name what the drill needs.

The mission doc template applies with Player fantasy and Narrative justification optional.

## Planned challenges

### C1 — Controls

**Teaches:** the modifiers (Alt narrows a command to one unit, Ctrl/Cmd broadens it, Shift
appends to the queue); the F1–F3 selector matrix (idle and on-screen by default, broadened
with the modifier); control groups on the number keys.

**Shape:** three short drills, possibly three challenges (Q2):

1. **Modifiers:** a builder squad and a scatter of build sites, timed. Narrowing sends one
   builder per site, broadening all of them to one, and Shift queues the next.
2. **Selectors:** idle builders and an army spread across the map, with tasks that need "every
   idle builder" or "the army on screen" in a hurry. Moving the camera to each unit loses time.
3. **Control groups:** two fights at once, at opposite ends of the map, that can't both be
   managed by box-selecting.

**Needs:** conditions that read how an order was given (its modifier), a selector use, and a
control group being set and recalled. None exist; `ConditionUnitSelected` and
`ConditionUnitHasCommand` only see the result.

### C2 — Spatial counters and spotting

**Teaches:** outpacing projectiles, kiting, turret arcs and turn rates, and spotting for an
artillery piece that can't see its own target.

**Shape:** in steps. A fast unit dodges slow shells. A ranged unit kites a slower melee group.
A tank is flanked before its turret comes round. Last, an MLRS that can't fire until a spotter
sees for it.

**Needs:** the projectile, turret and spotting mechanics exist
([projectile-evasion](../../systems/combat/projectile-evasion.md),
[turrets](../../systems/combat/turrets.md), [bombardment](../../systems/combat/bombardment.md)).
Bombard spotting is deferred to its own session (prologue README §Decisions). C2's spotting
step should use the MLRS until that is settled.

### C3 — Requisition

**Teaches:** queuing a purchase you can't afford yet, so it waits and is paid for when it is
fulfilled; standing (repeating) purchases; a queued structure's dependents; aborting an
upstream purchase.

**Shape:** an economy under time pressure. A wave is coming, and the player can only be ready
for it by queuing ahead of their income.

**Needs:** a condition on the purchase queue (a transaction waiting, a standing purchase set,
a dependent aborted). None exists.

## Open questions

**Q1. When to build these.** The challenges menu is greyed out. Build them after the prologue,
or interleave them (for example C1 right after mission 1, which is the first time a player
commands a group)?
*Leaning:* after the prologue's missions 2 and 3 are scoped.

**Q2. Controls as one challenge or three?** Three drills in one is long for a challenge, and
the modifier vocabulary is what the selector and control group drills build on.
*Leaning:* three challenges, C1a–C1c.

**Q3. Faction.** Anarchical, as in the prologue, or whatever best shows the skill (C2's
turrets are a Colonial Matilda, and its spotting may be Colonial once Bombards are settled)?
*Leaning:* per challenge, whatever shows the skill most clearly.

**Q4. Scoring.** Pass/fail, or rated (time, units lost)?
*Leaning:* rated, recorded in the match log.

**Engine work (decided).** Each challenge needs conditions that observe the player's input or
queue, not just the world: how an order was given, selector and control-group use, and
purchase-queue state. To be built, scoped on their own, apart from the prologue's
scenario restrictions (Alex, 2026-10-27).
