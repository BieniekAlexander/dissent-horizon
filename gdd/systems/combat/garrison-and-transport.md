---
title: Garrison and transport
type: system-note
---

# Garrison and transport

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Garrison occupancy


One entity being INSIDE another is `Garrison`'s job — the only mechanic for it. Occupants are held as orphaned nodes (out of the scene tree, so out of physics, rendering, AI and fog) and returned to their own `Commander` on release.

**Who may enter is the host's business; how much room they take is the occupant's.** Three `@export_flags` masks on `Garrison` — `occupiable_frames` (`Defense.FrameType`), `occupiable_armours` (`Defense.ArmourType`), `occupiable_movements` (`Movement.Mode`) — plus an optional `occupiable_ids` allowlist, say what a host accepts. `Entity.occupancy_size` (default 1; a `collective` is 2) says how much of `capacity` an occupant consumes, so **`capacity` is occupancy, not a head count**: a capacity-4 host takes four soldiers or two collectives. The mask bits are looked up through `Garrison.FRAME_BITS` / `ARMOUR_BITS` / `MOVEMENT_BITS` rather than computed as `1 << value`, because `Movement.Mode` is not a dense enum (`GROUNDED = 0x0`, `HOVERING = 0x10`, `FLYING = 0x11`).

Three questions, three methods — reach for the one that matches what you are asking:

| Method | Asks | Used by |
| --- | --- | --- |
| `admits(unit)` | do the masks and the allowlist let it in? | `Occupy.meets_precondition` |
| `has_room_for(unit)` | does its `occupancy_size` fit? | capture, deposit, `EventSpawnEntities` |
| `accepts(unit)` | both — can it garrison now? | `Occupy.can_act`, the bot's host filters |

Defaults reproduce the pre-mask behavior exactly: all frames, all armours, GROUNDED only — which is what `Occupy` used to hard-code. Widening `occupiable_movements` is how a hangar/carrier host would take aircraft.

### The id allowlist, and why empty means the opposite of an empty mask

`occupiable_ids` (doc key `garrison.pieces`) is a fourth filter, ANDed with the three masks: name piece ids and only those may enter. **An empty list restricts nothing**, which is the exact opposite of what an empty mask means, and the asymmetry is deliberate rather than an oversight:

- a mask enumerates a CLOSED enum, so "all three frames" is a statement a host can actually make, and "none of them" is therefore a meaningful one too — it is the closed hold;
- piece ids are OPEN-ended. No host could list every id, so an empty list can only mean "not asking".

It exists because the Compound admits Servants and nothing else, and **frame, armour and locomotion cannot tell a Servant from a Recruit** — they are the same body. The alternative considered and rejected was a marker component on the admissible piece (the [`Liberatable`](../../../scripts/entities/components/liberatable.gd) idiom): that is right when the predicate is DYNAMIC and read by a physics query every frame, and wrong here, where the question is asked once per order and the answer is a fixed property of the host, not of the guest. The pitfall accepted is that an id list is identity rather than capability, so a second builder piece must be added to the list by hand; the importer validates the ids, so a rename fails the import rather than silently shutting the door.

`closed: true` and `pieces:` together are a hard import error — "only Servants may enter, and nobody may enter".

**Closed garrisons are holds.** Every mask cleared → `is_closed()`, and the host takes no voluntary occupants at all: `Occupy` and `Embark` both refuse it (`CommandContextParser` hides the Embark button). Units get in only through mechanics that don't ask consent — which is why those all check `has_room_for` rather than `accepts`:

- **capture** — driving over the target puts it straight into the actor's garrison (the Colonial Stock Truck takes light biological units, enemy or neutral). See §Capture is a crush.
- **deposit** — `Interaction.Type.DEPOSIT` hands a carrier's captives to a garrison that INTERNS them (below).
- **scenario authoring** — see below.

**Scenario authoring** fills a hold too: `EventSpawnEntities` (`garrison_host`, or nested spawn events) fills any host, closed or not, which is how a scenario starts a truck already loaded. For a load that is there from frame 0, park the event as a direct child of the host itself (`garrison_host = ".."`) and the scenario-start pass runs it — see §The three ways an event runs, and `InternmentCamp1` in `s1.tscn` (a scenario node name that predates the Compound rename).

### The two directions of the door are separate statements

`is_closed()` is about getting IN. **Getting out is `releasable`, asked through `Garrison.can_release()`, and it defaults to true — a hold included.**

They were one question until 2026-08-28, when `is_closed()` gated `Occupy`, `Embark`, `Evacuate` and the info panel's occupant cards alike. The Compound is what separates them today: nothing can be ordered into it (deposit is the only way in), and the Servants delivered there can still be let out.

So each command asks the direction it is actually about:

| | asks | why |
| --- | --- | --- |
| `Occupy`, `Embark` | `not is_closed()` | entry, plus the host's masks per-target |
| `Evacuate`, occupant cards | `can_release_occupant()` | exit, for the host's own side only |

**An order releases only the host's own side; a captive is never let out by order.** A captive
— an occupant belonging to a side the host is not friendly to (`Garrison.is_captive`) — leaves
only when it is deposited, or when its host dies and it goes back to the commander it was taken
from. So Evacuate on a Stock Truck turns out the Servants riding in it and leaves the prisoners
beside them, and the same holds at the Compound. A neutral host adopts its occupants' side, so
its occupants are never captives.

REJECTED (2026-09-28) — letting the truck's owner release a captive by order, whole cage or one
card at a time. It was built so a player could let a prisoner go without driving to a Compound;
it was withdrawn when Servants began riding in the cage, so that turning them out never throws
the captives away with them.

The pitfall accepted is that `releasable: true` is now the default on a hold, so a garrison that genuinely must never open — a cell rather than a cage — has to say `releasable: false` and nothing warns when it forgets. Nothing in the game is one yet.

## Ordering someone aboard: the host's half of a garrison order

**`Occupy` is the only thing that puts a unit inside a garrison, and it is issued to the unit going in.** That is the whole mechanic and it does not change. What was missing was a way to say it from the other end: with a transport selected, right-clicking a soldier resolved a plain move, so loading a squad meant selecting the squad instead — the wrong selection to be holding if the next thing you want to do is drive the transport somewhere.

`Embark` is that order, and it is a *dispatcher rather than a second route in*. Given to the host, it does exactly two things:

1. On its first tick, it hands the unit it names an `Occupy` aimed back at the host. The passenger's own orders are replaced, which is what a right-click means everywhere else.
2. Thereafter it is a plain follow. The host walks to the passenger instead of making the passenger do all the travelling; `CommandReceiver` already turns a move at a friendly unit into a follow, and this inherits that unchanged rather than restating it.

An **immobile host** — a bunker, a safehouse — is still given the order. `should_move()` is false for it, so its whole half of the order is the `Occupy` it handed out, which is the point of having it. It ends when the unit it was calling becomes unavailable: boarded (a garrisoned unit is orphaned, so *tree membership* is the test, not `is_instance_valid`) or dead. That is the only end condition, and it is the one a follow already has.

**Who may be told to collect whom is asked in one place.** `Occupy.host_admits(occupant, host)` is the masks-and-ownership rule, factored out of `Occupy.meets_precondition` so `Embark` asks the same question from the other side. A copy of "which units a garrison takes" in a second precondition is a copy that rots, and the identical copy in `RTSController._resolve_command_class` already did once (it resolved `Occupy` for a closed hold, producing an invalid cursor and no order at all).

`Embark` adds exactly one condition of its own: **`has_room_for`**. `Occupy` deliberately omits capacity — a unit *ordered* into a full garrison walks over and waits for a slot — but a player *hovering* a unit over a full transport is asking whether calling it in would achieve anything, and it would not.

### With several hosts, or a mixed selection

**One host collects: the applicable one nearest the unit being called** (`Embark.nearest_host`, settled at issue time in `assign_command_to_units`). An order given to three transports is an order to *collect that soldier*, and collecting him three times is not a thing.

**Everything else selected still moves to the same unit.** That is a deliberate exception to the standing mixed-selection rule — *any member can offer it, only the members that can carry it out receive it* — expressed as `MoveCommand.bystanders_move()`, which `Embark` alone overrides. The standing rule is right for an order aimed at a THING TO BE DONE (a soldier has no business receiving a Build) and wrong for one aimed at a PLACE: right-clicking a friendly unit with a transport and four soldiers selected means "everyone go there, and you pick him up", and skipping the soldiers leaves four units standing still for an order the player plainly gave. A stationary producer among them absorbs its move as a rally point exactly as it would from any other right-click, which is what "as normal" has to mean.

The control matrix wants this generalised — an actor that cannot carry out the resolved command should fall back to a move at the same target *in every issuance context* — and that is a separate change. The hook defaults to false so nothing else moved when this landed.

**No grid cell is spent on it.** `Embark` names its subject by hovering it, exactly as `Occupy` does, so a button would need the same hover to mean anything and would buy nothing. It resolves directly below `Occupy` in the click ladder; the two can only both apply when each side would take the other, and the click is then read as "I go in", the older and stronger idiom.

Tests: `tests/test_Embark.gd`.

## Meeting in the middle

**A garrison order suspends RVO avoidance between its two halves, for as long as the order lasts.** The passenger must not steer around the very thing it is climbing into, and a host driving out to collect it must not shove it aside on arrival. Both sides say so themselves — `MoveCommand.avoidance_exception` returns the *other* half — and `CommandReceiver` feeds that to the same per-pair exception mechanism a follow already uses, so there is one mechanism and not two.

**The order's answer beats the follow rule.** A unit moving at a friendly unit is already exempted from avoidance against it, and for a same-team ground transport that incidentally covered the common case. It is the wrong rule to rely on, because it asks three narrower questions:

- *is the target a friendly unit?* — a **neutral** host (a Shelter) is not, and never got the exemption at all;
- *is the target in group `unit`?* — an immobile host is a structure, which is harmless only because a structure is not an RVO agent;
- *is the follower still moving?* — the exemption was therefore **dropped at the moment the two were closest**, which is precisely when it matters: a passenger that has arrived at a full hold and is waiting for a slot is standing still, in contact, being pushed around by the host it is queuing for.

So the exemption is stated by the order and lasts the order's whole life, arrival included. The follow rule still answers for everything that does not name a partner.

**What this does not replace.** `Occupy` also zeroes both bodies' avoidance *broadcast* layers for the duration (`Movement.suppress_avoidance_layers`), which is a blunter, wider thing: it hides the pair from **everyone**, and it is what silences the host's `NavigationObstacle3D` — the cross-team channel a per-pair agent exception cannot reach, and the only thing standing between a soldier and a **neutral** shelter. The two overlap for the same-team case and are not redundant at the edges. Collapsing them into one mechanism wants a per-unit obstacle channel, which the 32-bit avoidance layout does not currently have room for.

Tests: `tests/test_GarrisonAvoidance.gd`.

## Capture is a crush

**A Stock Truck takes prisoners by DRIVING OVER them.** There is no capture order, no button and no interaction: the truck outsizes light infantry, and running one over puts it in the cage instead of killing it. The right-click that starts a capture is a plain move at the prey — the same "Go" that expresses any other deliberate drive-through.

This replaced a dedicated `ABDUCT` `Interaction`, which was removed outright. What it cost: an order with its own precondition, its own reach shape (a 1-unit cylinder, so RVO could not keep the truck permanently a hair short of its target), and a second answer to "may this unit be taken" living beside the garrison's own. What it buys is that **the capture and the crush are the same event**, which is the only way the next rule can hold at all.

**Capacity gates the capture, never the crush.** `Garrison.can_capture(captor, captive)` is the whole rule of who may be taken — a non-friendly, non-structure, LIGHT-armoured BIOLOGICAL unit, when the captor has a hold with room. A full truck answers *no*, and the contact then falls straight through to the ordinary crush: it flattens the enemy soldier under its wheels exactly as any other vehicle would. Nothing about being a carrier makes a truck gentler. A NEUTRAL it cannot take is simply left alone, because neutrals were never crushable — the capture arm is the only reason a neutral is ever run over.

**Neutrals qualify, which is why the rule asks `is_friendly_to` and not `is_enemy_of`.** Taking a [Shelter](../../../scripts/entities/components/shelter.gd)'s Terrestrials is the Colonial half of the population race, and a Terrestrial is nobody's enemy. That single distinction propagates: `Commandable._can_run_over` — "would driving into this come to anything?" — is `outsizes it AND (it is an enemy OR it is prey I have room for)`, and both halves of the crush mechanic ask it. The avoidance half in particular must, or the truck would politely steer around every Terrestrial it was sent to collect and never make contact.

**The truck had to become a crusher for any of this to work.** Its `crush_class` is `MEDIUM`, matching every other vehicle in the game; before this it was the default `SMALL` and could not run over anything at all.

**The occupancy masks are not consulted** — a prisoner does not consent — which is exactly why the cage is authored `closed`. It is filled by capture and emptied by deposit, and no `Occupy` order can reach it.

### What a crusher avoids, and what it drives through

Three rules, and RVO has to express all three at once:

1. **Same team always respects itself.** Whatever the size gap, friendlies do reciprocal RVO.
2. **If X can crush Y, X ignores Y** and paths straight through rather than around.
3. **If X can crush Y, Y still treats X as an obstacle** and tries to get out of the way.

Rules 2 and 3 are one-sided, which is why cross-team avoidance is a `NavigationObstacle3D` on a per-commander channel rather than agent-to-agent RVO: X can stop watching Y's obstacle channel without Y losing sight of X's. Same-team RVO runs on a different set of bits entirely (`AvoidanceAgent3D`'s team channels), so rule 1 is untouched by anything the crush mechanic does — and `_can_run_over` refuses a friendly regardless.

**The scan for crushable neighbours is scoped to the agent's RVO neighbourhood, and must never be scoped to AGGRO RANGE.** Aggro range answers *how far will I pick a fight*. Whether to drive through something is not that question: it has no aim, no range and no intent — it is a physics contact — and **a peaceful crusher deliberately has no aggro volume at all.** The Stock Truck, the transports and the dominion generator all carry none, and every one of them must still run people over.

Scoping the scan to the aggro range therefore silenced the mechanic on exactly the pieces it exists for: they excluded nothing, ever, and politely steered around the infantry they outweigh — a `cl_mechLight_dominionGen` detouring around an enemy `cl_bioLight_builder` is how it was caught. It read as correct because the guard was on the aggro NODE, which every piece inherits from `commandable.tscn`, while the scan needed the aggro SHAPE, which a piece with no aggro range does not have. `neighbor_distance` is the right bound instead: it is the region RVO reacts within by definition, so it is exactly the set of neighbours there is anything to stop avoiding.

Tests: `tests/test_CrushAvoidance.gd`.

**Crushing is not a weapon, and the order table says so.** `command_attack_move` is offered on `CommandContextParser._is_armed` — a `Loadout` actually holding a `Weapon` — not on the presence of a `Loadout` node, which an unarmed vehicle carries empty. An attack-move click that lands on a Commandable resolves to `Attack`, and `Attack` on a weaponless actor can neither act nor move, so the unit stood still holding an order it could never carry out. Being able to flatten something is not being able to shoot it.

### Open: the crush-class table decides who is capturable, and it is inconsistent

**`crush_class` is authored on ten pieces and defaults to `SMALL` everywhere else, and `CRUSH_CLASS_GAP` is two tiers — so in practice the only crushable pairing in the game is a `MEDIUM` vehicle over `TINY` infantry.** Which units a Stock Truck can capture is therefore settled entirely by that table, and the table does not currently agree with itself:

| piece | class | capturable by the truck |
|---|---|---|
| Recruit, Servant, and the Colonial light infantry | `TINY` | yes |
| Terrestrial | was `MEDIUM`, now `TINY` | yes |
| Irregular | `MEDIUM` | **no** |
| the Anarchical builder | `MEDIUM` | **no** |

The Terrestrial was lowered as part of this change because the Colonial route to a Shelter's population is specified behaviour and would otherwise have died with the interaction — a civilian the truck cannot drive over is a civilian it can never take.

## Entry and exit take no time

A unit is inside the tick `Occupy.can_act` finds it in reach, and every occupant is back on the
ground the tick `Evacuate` fires (a hovering host first lands; nothing else waits).

TODO: the timing of the door is undesigned, and it decides the garrison's reaction-time and
counterplay window. The concrete symptom: **an instant evacuate undermines every weapon that
exists to flush a garrison** (the Libertarian vipers, say) — the defender empties the host the
moment the threat shows, so the flush never lands on anyone. Levers, each with its cost:

- **Exit time** (per host, or per occupant in sequence) — gives a flush its window; costs the
  garrison's value as an emergency shelter, since leaving is also slow when it is on fire.
- **Entry time** — prices ducking in against incoming area fire; costs the same for honest use.
- **Exit exposure** — occupants reappear staggered, or disoriented for a moment (no fire, slow),
  so fleeing the flush is survivable but not free.
- **Flush on the host, not the occupants** — the weapon disables the door (sealed or forced out)
  instead of racing it, which removes the race rather than tuning it.

It is an elasticity question as much as a combat one — see
[elasticity](../../design-framework/elasticity.md), where garrisoning is a preservation option.

## An occupant can be ORDERED before it comes out

Right-clicking an occupant's card in the info panel SELECTS it (its LEFT click evacuates it);
the selected occupant then takes orders like any other unit.

Two things had to change for that to work at all, and both are about the same confusion —
**a garrisoned unit is REMOVED FROM THE TREE, which is exactly what a dead one looks like.**

1. **`Commandable.garrisoned_in` tells held from gone.** `RTSController` prunes any selected
   node that is not `is_inside_tree()` every frame, which silently dropped an occupant one
   frame after its card selected it. Nothing else could have distinguished them: off-the-tree
   is what dying and boarding have in common. The prune now keeps a unit that
   `is_garrisoned()`.
2. **Garrisoning CLEARS the unit's selection flag**, mirroring what release does.
   `Selectable.select()` returns whether the state CHANGED and every caller reads false as
   "this cannot be selected", so an occupant that kept a stale SELECTED flag could never be
   picked again — and a squad is normally selected at the moment it is ordered aboard.

Both failed silently and both looked like the card was simply not wired.
`tools/hud_panels_preview.tscn --probe-cards` is what found them; a GUT test cannot stand
`player.tscn` up, because its `_ready` wants a Map. **An order does not imply
evacuation** — a garrisoned unit is off the tree, so it processes nothing and simply carries
the orders until something lets it out. A unit that never comes out never acts on them, and
that is the whole of what happens in that case.

**On release, its own orders win over the host's rally**, which is the same precedence a
trained unit gets between a player order and its producer's rally (see
[commands/construction](../commands/construction.md) §The rally is read at SPAWN). The chain
`Garrison._release_commands` builds is:

1. the immediate exit-point move, so the evacuee clears the host without overlapping it;
2. then **its own orders if it has any**, and the host's `rally_chain()` otherwise.

Each evacuee gets its own copies either way, so a group released together never shares command
instances. Tests: `tests/test_OccupantOrders.gd`.

**TODO — the Irregular and the Anarchical builder are left alone, and that is the open question.** Under the old `ABDUCT` order the truck could take an Irregular; it no longer can. Fixing it by lowering them to `TINY` also makes them crushable by *every* `MEDIUM` vehicle in the game, which is a balance change nobody asked for and does not belong in this change. The alternatives, none obviously right:

1. **Light-armoured biological infantry is `TINY`, always** — one rule, stated in the calibration pass, and vehicles flatten infantry as a matter of course. The Irregular becomes crushable.
2. **Leave the table alone** and accept that the truck's prey is narrower than its description says.
3. **Widen the capture rule past the crush gap** — let a carrier take prey it could not kill. That splits "captures" from "runs over" again, which is exactly the split this change removed.

Leaning: 1, because the capture rule already names *light biological infantry* and the crush table should say the same thing in the same words.

**Not covered by tests:** the contact itself. Both predicates are pure and pinned (`tests/test_CaptureByCrushing.gd`), but the tick that queries the truck's movement collider and calls `Garrison.garrison` needs a live physics server, and there is no simulation harness for it yet.

## A captive serves a sentence

**A captive deposited at a Compound is not stored, and it is not converted — it is HELD, and
timed.** `Garrison.deposit_from` moves each captive directly into the sink's `_garrisoned`
(`detach` on the source, `garrison` on the sink — the same entry point an Occupy order would
use), unconverted, and starts a `sentence_length`-second countdown on it (`garrison()`'s own
bookkeeping — every occupant of a garrison with a positive `sentence_length` is timed, not
only deposited ones). Partial deposits are allowed: the loop stops when the camp fills and the
carrier keeps the rest. Ownership never changes hands: a captive's `Ownership` still names the
side it was taken from throughout its term.

Three consequences worth knowing:

- **A positive `sentence_length` is what marks a prison** (`Garrison.can_intern`), and it is
  the whole of the `DEPOSIT` precondition's target rule — the same role `interned_scene` used
  to play before the sentence model, and `is_closed()` before that. `Bot.get_deposit_structures`
  asks the same question, so a future holding structure is picked up with no code change.
- **A finished sentence CONSUMES the captive** (`Garrison.discard`, called from the component's
  own `_physics_process`): the unit is freed outright, producing nothing further but the
  dominion it paid along the way and the [[work_detail|Work Detail]] cooldown reduction it
  fires on the way out. This is what separates the Colonial route from the Anarchical one —
  a Warlord converts a Terrestrial and keeps the unit in the world; a Compound spends it.
- **The camp holds no Servants of its own** — it is a CLOSED garrison again (every mask
  cleared, no `pieces:` allowlist), because a prisoner it holds is never something that could
  walk back out as a Servant. `Occupy` refuses it exactly as the truck's cage does.

Release is garrison logic too, with no second code path: a destroyed host runs
`Commandable._on_death` → `evacuate` / `kill_occupants` per `preserve_occupants`, and each
occupant returns to **its own** commander mid-term — so destroying a Compound *rescues* its
prisoners rather than merely denying the income. A Servant delivered alongside the prisoners
serves a sentence too, and is the one occupant an order can let out before it ends (§The two
directions of the door are separate statements).

The Colonial POW loop (truck cage, Compound, `OccupantDominionGenerator`) is built entirely on
the above; `Inventory` now holds only ability `ToolSpec`s. Tests: `tests/test_Garrison.gd`.

**Reworked 2026-09-17.** Conversion-on-deposit (below) is retired: a captive used to come out
of the Compound as a Servant, and now it does not come out at all. See
[colonial-dominion](colonial-dominion.md) for the full mechanics and the reasoning (paying for
a *term* rather than a *stock* is what makes route length matter).

**Reworked 2026-08-26** (superseded above). The Compound used to be a second closed hold
banking anonymous prisoners, and `DEPOSIT` was a straight custody transfer (`Garrison.receive_from`
/ `release_to`, both gone) whose target rule was `is_closed()`. The prisoners kept their own
commander and could never leave, so a raid produced a number and nothing else. The 2026-08-26
rework made the raid produce WORKERS instead — a Stock Truck captured,
[`cl_infrastructure`](../../factions/colonial/structures/cl_infrastructure.md) (the Compound)
converted each deposit into a [`cl_bioLight_builder`](../../factions/colonial/units/cl_bioLight_builder.md)
(the Servant), and the garrison opened to admit Servants by order. The 2026-09-17 rework closed
it again for a different reason: not because prisoners are held anonymously, but because
nothing it holds is ever a Servant to begin with.

---

## Per-occupant reach

`range_bonus` (doc key `garrison.range_bonus`) grants every occupant firing out of a bunker the
same extra reach. It is authored as two reach buckets, `{from: ground_range_medium, to:
ground_range_long}`, and the bonus is the gap between them, never a number: a bonus meant to
lift one tier to another has to keep doing so when the shape library is retuned
([range-buckets](range-buckets.md)). The two ordinary shelters, the neutral building and the
Anarchist Safehouse, share the same bonus: medium-reach infantry inside fire at long reach, so
they are out-ranged only by pieces whose tier is above long.

**`reach_by_piece`** (doc key `garrison.reach_by_piece`, a mapping of piece id to reach bucket)
SETS the reach one occupant piece fires out with, in place of its own reach and the host bonus
(`Garrison.reach_bonus_for`); it never shortens a weapon that already reaches further. It is
the first PER-OCCUPANT property — the stub for hosts whose character depends on which unit
holds them. Its user is the Warden's Security Tower, where a garrisoned Shock Drone fires at
`ground_range_long` instead of its melee zap
([static-defence](../../design-framework/static-defence.md) §Libertarians).

**Superseded:** a numeric `range_bonus` (the neutral building's was 1.0) and a numeric
`range_bonus_by_piece` that ADDED to the occupant's reach (the Shock Drone's was +10). Both
went stale the moment a bucket moved.

