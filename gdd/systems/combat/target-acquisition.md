---
title: Target acquisition
type: system-note
---

# Target acquisition

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

What a unit is allowed to pick up as a target on its own, and how long it keeps one.
`Actor.get_aggro_near_position` is the acquisition side; `Attack._target_within_leash`
is the release side. **They are two halves of one rule, and every bug in this note is a case
of the two halves disagreeing.**

## You may only shoot at what your side can see

An aggro candidate must be `is_visible_to(commander_id)` — the asking commander's fog pixel
clear AND the target not stealthed. Vision, not the aggro shape, is the outer limit on what a
unit will start a fight with: the shape decides *how far it reaches*, fog decides *whether
there is anything there as far as this commander knows*. The bot's own read of a unit's aggro
(`Bot.get_enemies_in_aggro_range`, which gates retreat) applies the same test, so a bot never
reacts to an enemy its units could not have picked a fight with. Pinned by
`tests/test_AggroNeedsVision.gd`.

**Vision is per COMMANDER, not per unit.** A target twenty units away can be perfectly
visible because something else on the same side is standing next to it. That matters for the
leash rule below, because vision radii in this game are roughly twice aggro radii — so the
set of things a unit may acquire is genuinely wider than the set it is standing on top of.

### One `Fog` per commander id

`Fog` nodes register themselves under the RESOLVED viewer id (`Fog.viewer_commander_id`), and
`Fog.for_commander` is the only way back out. That is a rule rather than an implementation
detail, and it is worth stating because the alternative shipped and was invisible:

The player's `Fog` is placed in `player.tscn`, where `watching_commander_id` keeps its
authoring default of `-1` meaning "whoever the local player is". Registering under the RAW
field filed the player's fog under `-1` while every bot's went under its real id — so every
caller had to remember to map the player's id back to `-1`, and each one wrote that mapping
out for itself. `Actor.is_visible_to` did not: it looked up commander `1`, found
nothing, and returned "no fog, so everything is visible". The player's entire army therefore
aggroed onto units in the fog, all match, with the fog code itself working perfectly.

The fix is not "remember to map it in one more place" — it is to resolve `-1` once, at the
point of registration, so there is exactly one key per commander and `-1` never reaches the
dictionary at all.

### Out of play is not in vision

The fog texture covers the terrain plus a margin, but the terrain grid is SQUARE while the
play area is a rectangle rotated within it (see
[terrain-and-navigation/map-and-terrain-grid](../terrain-and-navigation/map-and-terrain-grid.md)),
so the four corners of the grid are outside play. `Fog._build_play_mask` holds those pixels
at byte 0 so the shroud does not hang over ground that is not there.

**Byte 0 is also what "revealed" looks like.** Transparency and vision are two different
questions that happened to share a value, and `fog_clear_at` answered the wrong one: anything
standing on an out-of-play pixel read as permanently in sight. Since a structure is in vision
when ANY of its footprint cells is (`structure_in_vision`), a base sited near the play edge
needs only one cell over the line to show through the fog for the whole match — which is
exactly what the Colonial base in `mesh_terrain_plateau` did, with 6 of its safehouse's 16
cells outside the rectangle.

So `fog_clear_at` tests the mask before the byte, matching `terrain_visibility_at`, which
already reported out-of-play pixels as UNSEEN. The consequence worth accepting deliberately:
a piece standing ENTIRELY outside the play rectangle can never be seen. That ground is
already unwalkable, unbuildable and un-meshed, so a piece out there is a broken authoring
state either way — and invisible is the less exploitable of the two failures.

## Alliances

Decided 2026-09-24: the game has alliances. Built 2026-10-09 to these decisions (Alex,
2026-10-08):

- **Teams are fixed before the match** on `PlayerSlot.alliance`: 0 is no team, 1…7 a team
  (`PlayerSlot.NUM_TEAMS`). There is no diplomacy during a match. Under the hood there are 8
  alliances (`Commander.NUM_MAX_COMMANDERS`), so a free-for-all of eight puts each player in
  its own; a team game offers only 7, since an eighth team of one is a free-for-all slot.
  `Scenario.alliance_indices` numbers them in order of first appearance, so a teamless slot can
  never land in a team, and `Scenario._assign_alliances` hands each commander its alliance and
  its members (`Commander.set_alliance`) before any piece exists.
- **A side is a commander and its allies.** `Commander.is_allied_with` / `shares_side_with`,
  `Entity.is_on_side_of` (asker has only an id) and `Entity.is_friendly_to` answer it;
  `Entity.is_enemy_of` is "owned, and not on my side". A commander no scenario placed is alone,
  which is what keeps every out-of-scenario test and tool behaving as before. Neutral is
  nobody's ally.
- **What allies share:** not being enemies (aggro, retaliation, capture, hijack, kill bounties,
  scripted assaults), **vision** (each `Fog` counts every allied vision source as its own, and
  an ally's stealth hides nothing from its side), **repair** (`Repair.repairable_cause`), and
  **friendly-target abilities** (`EventTargetUnit` Scope.OWN admits an ally's unit). Also the
  readouts that follow from shared sight: allied blueprints shown and refused as building
  sites, capacity pips on a selected allied unit, allied structures' ranges round a placement.
- **What they do not share:** orders, garrisons and transports (`Occupy`, docking, `Embark`
  stay owner-only), resuming an ally's construction, and passive bonuses — the Compound's
  Work Detail cooldown cut reaches only its owner's buildings. **Dignify** stays own-only
  (`EventDignify._admits_allies`): the Warlord it makes is the caster's, so it would take an
  ally's Irregular.
- **Splash hurts allies**, as it hurts one's own pieces: the blast query is `TARGETABLE_ANY`,
  so area weapons friendly-fire by construction ([projectiles](projectiles.md)).
- **An ally's fixtures shield Libertarian dominion tiles** exactly as one's own do
  ([lb_dominion](../../factions/libertarian/structures/lb_dominion.md)).
- **HEGEMONY removes players one at a time and judges alliances.** A commander with no command
  centre left is still eliminated alone and its pieces freed — under HEGEMONY only. The local
  player loses when every member of its alliance is gone; until then it keeps watching
  through its allies' shared vision. Its alliance wins when it is armed and every rival
  alliance is gone, and the match log names every winner (`MatchLog.end`, `MatchSummary.winners`)
  ([objectives-and-completion](../scenario-scripting/objectives-and-completion.md)).
- **Bots know only that allies are not enemies** and see what their allies see. They do not
  coordinate.

**Pitfall accepted:** the side bits on a Hurtbox stay per COMMANDER, not per alliance — an
aggro query leaves out every ally's bit instead (`CollisionLayers.hostile_mask` takes the
asker's allied ids). Fixed teams make that free, and it is what would let mid-match diplomacy
work without re-filing every body.

TODO: the heal aura (`HealAOE`) still mends only its owner's units — see
[tasks](../../tasks.md) T-028.

## Aggro filters allegiance in the physics query

The aggro query asks the physics engine for hostile bodies only, so allies and neutrals never
reach the script filter. It matters for correctness, not only cost: the query is capped
(`Actor.AGGRO_SCAN_MAX_RESULTS`) before any filter runs and does not return
nearest-first, so when it returned allies too, a crowd of friendly bodies could fill the cap
and hide a visible enemy. `tests/test_AggroIgnoresAllies.gd` pins that case.

**A physics mask can only OR bits together** (`layer & mask != 0`), so "on the ground AND
hostile" cannot be two bits tested together; the layer encodes the combination. A Hurtbox
keeps its generic `TARGETABLE_GROUND` / `TARGETABLE_AIR` bit, which projectiles, AoE, vision
and every other broad scan still query, and also carries one side bit for that layer and its
owner (`CollisionLayers.side_bits`). Neutral has no side, which is what keeps it out of every
hostile mask for free. The side bits follow the owner, so a capture re-files them.

The script-side `is_enemy_of` stays as a guard, and the vision filter stays in script: fog
cannot be a layer. **Fogged and stealthed enemies can therefore still fill the cap.** Raise the
cap, or make it a floor on distinct enemies rather than raw hits, if that shows up in practice.

**Alliances leave the side slot per commander:** `CollisionLayers.hostile_mask` excludes
every side bit of the asker's alliance ([Alliances](#alliances)).

## Retaliation answers fire from past aggro

A piece hit by an attacker answers it with an Attack, wherever the attacker stands — so fire
from beyond aggro, which idle pickup never sees, is still returned
(`Actor._retaliation_against`). It answers only when:

- **it is idle** — any order, queued or active, stands; retaliation never overrides one;
- **it is not holding fire;**
- **its side can see the attacker,** by the same vision gate as idle pickup above: an attacker
  in the fog or under stealth is not answered;
- **it can fire on the attacker at all** — its own weapons, or a bunker's occupants'. A garrison
  host with no weapon of its own answers through them.

**A piece that cannot move** — a structure, or a unit that is currently immobile — answers only
an attacker it already reaches, since it could never close on anything else; anything past that
is ignored rather than acquired and then leashed away.

An answering attack is persistent, like a player's: a mobile piece chases. What ends the chase
is the rule below.

**Superseded:** retaliation looked for the attacker among the targetable bodies inside the
piece's OWN vision shape. That answered stealthed attackers, missed ones spotted only by the
rest of the side, and — being an unfiltered, capped query — could miss the attacker in a crowd.

## An attack is dropped when its target is lost from sight

Every Attack, persistent or not, is dropped once its target — having been seen during the
attack — is no longer visible to the attacker's side: it ran into the fog, or went stealthed
(`Attack._target_lost_from_sight`). It is the release-side twin of the vision gate on
acquisition.

**It is a transition, not a state.** An order may name a target nobody on the side can see yet:
a scripted assault on a fogged base (`EventCommandTarget`, BASE) or a bot's attack on a
remembered structure. Those are pursued until the target is first seen, and dropped only if it
is then lost.

## Line of fire

A ground piece may not shoot a ground target through an OBSTRUCTION: `Attack` refuses the
shot while a finished obstruction's body lies on the line between them, and the attacker
closes or goes round (`Attack._obstruction_on_line`).

- **Only obstructions are cover** — the fixtures whose cells leave the navmesh
  (`Entity.has_obstructing_footprint`, the same flag the navmesh reads). An occupant-only
  fixture, which units walk across, does not block a shot; nor does a foundation
  ([construction](../commands/construction.md) §It is not COVER either).
- **Neither end is cover for itself.** The ray runs from the shooter's origin to the target's,
  so both ends' own bodies are excluded — a shooting STRUCTURE starts the ray on its own
  blocker body, and counting it once stopped every unordered Watch Tower shot.
- **Nothing blocks a shot to or from an air target.** When the attacker or its target is
  airborne (`Entity.is_air_target`), buildings are not in the way. A landed aircraft is a
  ground piece and is blocked like one.
- **The shot may pass visibly through a building** on its way to an air target, or from one.
  Line of fire is decided at order time; emissions do not collide in flight unless a phase
  asks to ([projectiles](projectiles.md)).

**Superseded:** every finished fixture was cover, occupant-only ones included, and it was cover
against aircraft too.

### Terrain on the line of fire

**Terrain never obstructs SIGHT.** Fog and vision ignore the ground (decided 2026-10-08).

**Terrain obstructs a shot from a weapon whose reach is below `RangeShapes.artillery_reach()`**
(the radius of the imported `ground_range_artillery` shape, 20 today, from `gdd/shapes/shapes.md`; decided 2026-10-08).
Artillery and siege weapons lob over the ground and are exempt; everything shorter fires along
it. `Attack._terrain_on_line` casts ONE ray from the shooter to the target against the
`TERRAIN` layer — the physics body the surface mesh is baked into — and any hit refuses the
shot, so the attacker closes or goes round exactly as for an obstruction. Both ends are lifted
`TERRAIN_RAY_LIFT` (0.5) so the ray does not graze the surface it starts on; a bump lower than
that is not cover.

- **Ground to ground only,** the same air exemption as obstructions.
- **The weapon that would fire decides** (`Weapon.reach_for` the target). A piece with no
  weapon of its own, such as a bunker firing its occupants' weapons, is not terrain-blocked.
- **Pitfall accepted:** the rule is a straight ray with no height judgement, so a ridge higher
  than the lift blocks too, and a cliff between two elevations blocks when the ray clips it.
  The earlier cases ("a ridge should not block") are met only by the lift. Refine with a
  minimum obstruction height if play shows it matters.
- **Pitfall accepted:** only the order-time check sees terrain; an emission still flies
  free of it unless a phase's `impact_mask` names `TERRAIN`.

## A Defend order also considers every enemy structure

Aggro skips a candidate ranked worse than the command's floor
(`CommandMessage.target_priority`, default `NON_COMBAT_UNITS`), so idle aggro, Patrol and the
player's attack-move ignore UNARMED enemy structures. Armed structures (`COMBAT_STRUCTURES`)
are always in. A Defend order's floor is `NON_COMBAT_STRUCTURES` (decided 2026-09-25), so a
defender also takes on any enemy structure in its region: a forward structure raised inside a
defended area, or a captured neutral building.

- **Set in `Defend._init`, not at each call site.** Defend messages are built in four places
  (`RTSController`, `EventCommandPoint`, `sim_arena`, `attack_probe`), and a floor set at each
  would drift. The constructor widens `message.target_priority` itself, so the message says
  what the order does and any copy of it carries the same floor.
- **Order is unchanged:** candidates sort by rank, then distance. A defender takes armed
  units, then armed structures, then unarmed units, and only then unarmed structures.
- **Unchanged elsewhere:** idle aggro, Patrol and the player's attack-move keep
  `NON_COMBAT_UNITS`. The bot's attack-move widens to structures on its own
  (`BotActuator.attack_move`). Neutral structures are never enemies, so never taken.
- **The leash** needs nothing new: a structure is on the ground layer, so with no region shape
  the engagement is leashed by the defender's ground aggro volume around the post.

Pinned by `tests/test_DefendTargetsStructures.gd`.

## Acquire and release must measure the same region

An engagement picked up by aggro is not persistent: it ends when the target leaves the
leash. **The leash must be the region the target was acquired in.** There are two regimes,
and which one applies is decided by whether the order named a region:

| Order | Acquisition region | Leash |
|---|---|---|
| Idle aggro pickup | the unit's own aggro volume for the target's layer, where it stands | measured from the UNIT, so it chases |
| `Defend` | the defended area | measured from that AREA, so it does not |

The unit-measured leash is what lets an idle unit pursue: as it closes, the region moves with
it. The area-measured leash is what stops a bait peeling a defender off its post.

**`Defend` fell between them.** It scans around its POST — deliberately, so that every
defender reacts to the same incursion rather than each guarding its own little circle — but
handed the resulting `Attack` no region, so the Attack fell back to the unit-measured leash.
Those agree only while the defender is standing on its post, and the whole march out to it is
time when it is not. An intruder near a post the defender had not reached yet was acquired,
failed the leash on the tick the order was created, and was acquired again on the next:
**Attack → null → Attack, once per tick, forever.** Neither command ever reached
`should_move`, so the defender did not move either — it stood where the order was given,
flickering, while the intruder walked past. A headless probe measured 400 command changes in
400 ticks and zero distance covered.

`Defend._leash_to_defended_area` stamps the region onto every command it hands back. With no
region authored, the defended area is the defender's own aggro shape **centred on the post**
— which is exactly the area the scan just used. That is why `CommandMessage` carries an
`aggro_center` alongside `aggro_shape`: the shape is a template, and for the fallback case it
is a node that follows the defender around, so reading its live origin would put the area
wherever the defender happens to be.

Tests: `tests/test_FogVisibility.gd`, `tests/test_DefendLeash.gd`.

## One definition of "airborne", and it is altitude

**`Entity.is_air_target()` — `height_offset() >= Aerial.AIR_TARGET_ALTITUDE` — is
the only thing that decides whether a piece is engaged as an AIR target or a GROUND one.**
Both halves of "can this weapon reach it" read it: the `TARGETABLE_AIR` / `TARGETABLE_GROUND`
bit on the piece's `Hurtbox`, and the air-vs-ground reach `Weapon.get_range_for_target`
picks. The threshold is derived from `Aerial.AERIAL_HEIGHT`, not typed, so raising cruise
altitude cannot leave the whole air force below the line.

**What it supersedes: the locomotion mode.** The mode answered this for as long as locomotion and
altitude were the same fact, and they stopped being it twice over — an AERIAL unit can be on
the ground (parked on a pad), and a GROUNDED one can be in the air (under a parachute,
see [off-map-abilities](../macroeconomics/sanctions/off-map-abilities.md)). The two
halves had already drifted apart: the layer came from `mode` and was written exactly twice in
a piece's life, while the range came from `is_airborne()` and was live. So a jet on its pad
sat on `TARGETABLE_AIR` where no ground-only weapon could lock it at all, while the range rule
said it should be shot at ground range — a hangar full of aircraft was immune to the infantry
standing next to it.

**The layer is now re-filed on the tick the answer flips**, from
`Actor._physics_process`, immediately after the same height is applied to the body.
That costs one float comparison per piece per tick and a property write only on a crossing;
it is on the tick boundary with the Y-write on purpose, so the two can never be a frame apart.

**`is_airborne()` survives, and is a different question.** It means "flying rather than on its
deck", and it governs what a piece may DO: whether it can shoot (`can_use_weapons`), whether
it still needs the runway, whether it can be ordered to land. It cannot answer the targeting
question, because a parachuting soldier is not in an aerial mode and a parked jet is.

Two consequences, both accepted deliberately rather than worked around:

- **A parachuting unit is an AIR target for the first half of its drop.** It is released at
  `AERIAL_HEIGHT` and only anti-air can touch it until it falls past half that. This reverses
  what `Movement.begin_parachute_descent` originally claimed ("grounded cargo, shot at from
  the ground") — that note deferred this decision, and this is it. A drop into anti-air cover
  is now a real risk, which is the interesting reading of it.
- **A FLYING unit loses its air-target status at the bottom of a dive**, because a dive
  descends to the target's own altitude. An anti-air battery therefore cannot hold a lock
  through the last moments of an attack run. Lower `AIR_TARGET_ALTITUDE` if that reads as too
  forgiving; it is one derived constant, and the dive is the only case that lives near it.

### The latch costs one tick, so "no reach" has to be a legal answer

**The layer is LATCHED and the reach is LIVE, and nothing makes those simultaneous for an
observer.** `refresh_targetable_altitude` writes the layer at the end of the piece's OWN
`_physics_process`; `Weapon.get_range_for_target` reads `is_air_target()` at the moment it is
asked. Another entity's command tick runs in between. So for the one tick a piece spends
crossing `AIR_TARGET_ALTITUDE` — a descending aircraft, a parachutist halfway down — the two
halves of "can this weapon reach it" genuinely disagree: `Loadout.weapon_for_target` accepts a
ground-only weapon because the LAYER still says ground, and that weapon is then asked for an
AIR reach it does not have.

Latching is not the mistake; it is what keeps the per-tick call to one float comparison. **The
rule is that `Weapon.get_range_for_target` returning null is a legal answer meaning THIS
WEAPON HAS NO REACH AGAINST THAT SIDE, and every reader treats it as "not in range"** —
`Weapon._range_radius` (−1.0), `Attack._leash_radius` (falls back to aggro range) and
`SU.is_in_attack_range` (false). Only the last of the three was missing it, and it
dereferenced the null instead: a recruit firing at a unit that crossed the line mid-tick
crashed the command tick, and with it the rest of that entity's frame.

The alternative — making eligibility read live altitude too — was rejected. `can_target` reads
the layer because the LAYER is what the reach test masks against, so a weapon that agreed
to fire on altitude alone would be refused by that mask and report "not in range" anyway. That trades a crash for a silent miss and splits the two answers in the
other direction. **One tick of no-reach, stated explicitly, is the cheaper accepted cost.**

Tests: `tests/test_AirTargetAltitude.gd`, `tests/test_WeaponReachAcrossTheAirLine.gd`.
