---
title: Ideas — a brainstorm against the current roster
type: design-note
---

# Ideas

Proposals for review, each named by **the decision it creates** rather than by the effect it
has. Nothing here is decided; nothing here is built. The analysis they are drawn from is
[decisions](decisions.md), and anything that graduates moves to [proposals](proposals.md) and
then to a system note.

Out of scope by instruction: new resources, new ways to collect them, and new faction dominion
routes.

---

## What the roster already covers

| Structure | Carried today by | Verdict |
|---|---|---|
| Commitment | Spot's channel, the Hijacker's channel, build and repair, aircraft rearming | good |
| Confirm | **Overcharge** — aimable only at an already-stunned unit | the pattern exists once, in one faction, at tier 3 |
| Fungible resource | the Citadel's four sanctions sharing one charge pool | good, and under-exploited |
| Zoning | Bombard over spotted ground, MLRS, Toxin Tractor, Radiate, SAM and towers | present, but every instance zones by DAMAGE |
| Read | Ambush, Informant stealth, slow projectiles | thin |
| Grappler | the **Hijacker** — walk up, channel, take the vehicle, and be expended | exists, at maximum variance |
| Reactability | fog, stealth, Scan | handled almost entirely by fog, which is a blunt dial |
| Footsies | range bands, vision, reinforcement distance, terrain height | gradients exist; structures are pure commitment |
| **Reversal** | the **Bombard** — highly effective, long cooldown, its owner exposed while it recharges | present; coverage is the question, not existence |

Three roster facts worth knowing before adding anything:

- **Six of nine damage types are fielded** (2026-10-05). Incendiary, Sonic and Lazer appear
  nowhere; Toxic and Plasma (the Bombard's shell) appear once each. New pieces should be pulled
  toward the empty rows rather than adding another Lead gun.
- **The Sapper has no weapon authored**, and the Refraction Tank's deploy is a `TODO`. Two of the
  most interesting decision shapes in the game are unbuilt rather than badly tuned.
- **Reversals are not meant to be generic.** Not every fighting-game character has one, and here
  a reversal is less one-size-fits-all still: the Bombard answers a slow ground push and does
  nothing about nimble or airborne attackers. What a faction's reversal *cannot* cover is the
  statement of what that faction cannot defend against, and that is the useful output.

---

## Generic proposals

### Disengagement, priced rather than ordered

**Superseded — no withdraw command.** The decision is wanted; the order is not. Pricing it out of
movement properties (turn rate, holster, a post-attack speed penalty, suppression, health-linked
speed) is worked through with formulas in
[commitment-and-movement](commitment-and-movement.md).

### Rubble, as the surviving half of the wreck idea

Unit wrecks are **rejected**: blocking vision is computationally infeasible, blocking line of fire
contradicts living units (which do not block it either) and would cap how armies scale, and a
fixed despawn timer is arbitrary. Husk reactivation needs a generic repair or steal mechanic
that does not exist, and every mech leaving a husk would be far too much of it.

What survives is **rubble from STRUCTURES**: a destroyed building leaves its footprint obstructed,
and the obstruction clears when somebody builds over it — construction on rubble simply costs
extra time.

- **The decision:** ground a building died on stays denied until someone pays to reclaim it, so
  razing a forward position buys the attacker more than the kill.
- **Why it avoids the wreck problems:** structures are rare and static, the count is bounded by
  how many buildings actually die, and the despawn condition is a player action rather than an
  arbitrary timer.
- Still not proposed: salvaging anything for resources — that is a resource route, and out of
  scope.

### The telegraph rule

Not a mechanic but a constraint on all of them: any effect above a payoff threshold must have a
visible pre-state — a charging glow, a deployed stance, a beacon — that lasts long enough for a
player who is looking elsewhere to notice it.

- **The decision:** it is what makes a strong action a test of attention rather than a coin flip,
  and it is the practical form of "payoff scales with the reaction window granted".
- **The telegraph SHRINKS as the match goes on**, which is already how the Bombard's beacon works
  and how capture investment is meant to work: early actions are loudly announced, late ones much
  less so. That is a volatility curve built out of information rather than damage, and it belongs
  in the mechanics table as one of the levers that serves G3.

### Capture on a confirm

A disabled unit is capturable regardless of its class — the Stock Truck (or a future equivalent)
may take something it could never crush, if somebody else disabled it first.

- **The decision:** it makes capture a two-commitment play — the disable, then the truck — which
  is the confirm shape generalised beyond Overcharge.
- It fits the intended progression: capture routes vary per faction, and the investment a capture
  demands is meant to fall as the match goes on, in step with the shrinking telegraph.
- It also offers a way out of the old capturability-class question: capturability stops being a static class table
  and becomes a state, which is the thing the table keeps getting wrong.

---

## Re-readings of mechanics that already exist

### Freeze, with an after-window

Give a thawing unit a few seconds of sluggishness. Freeze becomes a genuine reversal: still the
save it is now, but baitable, and a Freeze spent early is punished by the attack that follows.

- **The decision:** the chicken game around a defensive charge — the thing the game currently has
  nowhere.
- **Risk:** it weakens a tier-0 sanction. If Freeze is meant to be a clean save, the reversal
  shape belongs on a new piece instead.

### Cryo with an onset time

**The direction, as decided:** freezing takes time to set in, and how long depends on the ability
doing it. The Avalanche — effectively unimplemented today — channels its attack over an area, and
a unit that stays inside that area long enough freezes.

- **The decision:** it is zoning that costs position rather than hit points, and the onset time is
  the reaction window: leaving in time is the counterplay, and a unit that cannot leave in time is
  the payoff.
- **The parameters are the design surface** — onset duration, area, channel length and what
  interrupts it — because they set reactability and the caster's own commitment independently.
- **Counterplay:** leave the area (position), push through and accept the freeze (attrition),
  or break the channel (risk) — three options at different prices, which is what separates zoning
  from a wall.

### Reversals: read the ones that exist before adding more

The Bombard already is one — a powerful defensive answer with a long cooldown, during which its owner is more exposed than usual. The useful work is therefore **auditing coverage**, not adding a charge to every defensive building:

- **A reversal's strength is modulated by reach, cooldown and mobility.** A structure has no
  mobility, which is what keeps a strong one honest.
- **What it fails to cover is the faction's stated weakness.** The Bombard handles a slow ground
  push and does nothing about nimble or airborne attackers, so that is what the Colonials must
  answer some other way.
- **Reversals belong EARLY in the tech tree**, because they are at their best defensively and a
  defensive tool that arrives late has spent the period it was needed. **The Bombard should move
  lower in the Colonial tech tree** — it currently sits behind the Operations Center.
- Not every faction needs one, and none needs one for every situation. Which situations a
  faction's reversal covers is a compact description of what that faction can and cannot defend.

### Sanction pools as a real budget

The Citadel already shares one charge pool across four sanctions. That is a burst meter nobody is currently forced to think about, because the pool is large relative to what is on it.

- **The decision:** which of four good options this pool is for. Worth tuning deliberately rather
  than leaving as an implementation detail — and worth repeating on other structures.

---

## Faction-shaped proposals

### Anarchists — the Sapper as a grappler

**Specified and queued**: a one-charge plant ability with a ten-second fuse, an area effect, a
recharge blocked while the bomb is live, and a bomb that vanishes if its Sapper dies first. See
[systems/combat/planted-explosives](../systems/combat/planted-explosives.md).

### Anarchists — demolition traps

A planted, hidden charge that triggers on an enemy passing. Zoning plus a read: it costs the
attacker either a detector, a route, or a unit.

- **Risk:** invisible unreactable damage is exactly what the analysis says must stay small.
  Detection has to be reachable for every faction, or this is a matchup rule violation (M1).

### Colonials — a forward deployment structure

A structure that reinforcements arrive at, turning the Colonial reinforcement distance from a
fixed penalty into something placed and defended.

- **The decision:** it puts the faction's stated weakness (map traversal) on a position the
  opponent can attack, which is the compensation their identity departure currently lacks.
- Fits `cl_support1` (Annex), which has no mechanic yet.

### Libertarians — drone attachment

Their own doc already names it: a drone docks onto a larger friendly unit and lends it something
(point defence, repair, vision).

- **The decision:** allocating a small number of drones across an army — a fungible resource
  spent positionally, and the coverage micro pattern in [micro](micro.md) made into a piece.
- It also gives the faction an answer to "no BIO" in a way that is theirs: their support is
  attached, not healed.

### Technocrats — the Obfuscator, as information

The structure exists by name. Proposal: decoys — cheap holograms of units or structures that read
as real until touched.

- **The decision:** it spends the opponent's attention, which is the scarce resource the RTS form
  adds. A player who must check is already paying.

---

## Unhomed ideas

These have no faction; they are recorded because the decision shape is good.

- **Overwatch.** A unit holds fire until something enters a marked area, then fires first with a
  bonus. A read committed in advance, paid in tempo; the counter is a bait.
- **A relocatable structure.** It packs into a slow vehicle and redeploys elsewhere over a long,
  visible commitment. This is the only idea here that makes a structure's position REVERSIBLE,
  which is what would let structures participate in footsies at all.
- **An aimed structure arc.** A support building whose effect is a directional arc the player
  rotates, adding orientation as a second continuous positional variable at almost no rules cost.
