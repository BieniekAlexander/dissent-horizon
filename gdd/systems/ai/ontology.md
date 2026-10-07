---
title: The bot's ontology
type: system-note
---

# The bot's ontology

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**TODO — an unapproved proposal, drafted 2026-10-06 from a design conversation.** What the
bot's model of the game is MADE OF: the kinds of thing in the game, the affordances a thing
has and how each is derived from the code, the temporal rules that say what the bot can
perceive at all, attention as the sensor the human tiers look with, and the one rule for
cues. [world-model](world-model.md) is the machinery that holds these; this note is the
vocabulary it holds them in. The brief is [brief.md](brief.md).

Two tests run through everything here, both decided in the world-model note:

- **A player has it, or the bot does not.** Every signal below is placed by asking whether a
  human player holds that information, not by whether the engine does.
- **Derived from the code, declared only where it cannot be.** An affordance is read off the
  components a piece carries; a declaration is allowed only for what no component expresses,
  and it lives with the thing it describes.

---

## The kinds

Five kinds of thing exist in the game as the bot's model sees it. The sixth heading says
what is deliberately NOT a game kind.

### Pieces

The four nouns of [piece-vocabulary](../authoring/piece-vocabulary.md), exactly as that note
partitions them — **structure** (Actor fixture), **unit** (Actor figure), **feature**
(uncommandable fixture), **token** (uncommandable figure) — with its two rules carried over:
the code tests facets and never the noun, and **a noun follows ACTIVE facets**, so a
deployable transformer changes noun without changing identity. A track therefore carries the
noun as STATE alongside its type, read from `Deployable.stance` and the live facets, never
from the scene file.

### The map

The setting, with the primitive layers the code actually has:

| layer | source | note |
|---|---|---|
| passability | `TerrainGrid` per `NavAgentClass.Size` | RELATIVE to the agent: each size class has its own eroded navmesh, so a one-cell gap is a road for infantry and a wall for a truck |
| buildability | `Structure.valid_placement` over the footprint | in bounds, unoccupied, clearance |
| elevation and occlusion | `TerrainData.heights`, `STRUCTURE_BLOCKER` | **does NOT gate vision** — see §Vision is unoccluded |
| water | `WaterBody` | passability and extraction |

Everything else said about the map — bases, approaches, expansion sites, chokes, the front —
is DERIVED and belongs to the model (§What is not a game kind), not to the game.

### Commanders

The owners. A piece has no value without one, and three of the abstract things the bot must
reason about are commander state rather than world state:

- **resources** — energy, infrastructure, dominion (`Commander`);
- **the tech position** — what is unlocked and what unlocks it (`technology_mapping`);
- **holdings** — upgrades researched, sanctions unlocked, abilities carried.

An enemy commander is a BELIEVED instance of the same kind, which is where the world-model's
tech inference lands. **Relation to the observer — own / enemy / neutral — is a property of
the pairing, not of the piece.**

A commander may carry affordances DIRECTLY: an off-map sanction is lethality or sensing with
no piece carrying it. The kind must allow that, or those abilities have nowhere to live.

### Modifiers

Things that do not exist as pieces and **rescale an affordance of something that does**:
upgrades (`kind: Upgrade`), sanction unlocks, `Veterancy` levels, a `Shield`. One shape for
all of them — (what it attaches to: commander / type / instance; which affordance it scales;
by how much) — so a bot wanting "more of X" reasons over the affordance and finds the
modifier, rather than knowing each modifier by name. The game currently has no modifier
registry; the importer's `technology.json` and the ability catalog are the two places the
data exists, and the kind is a view over both.

### Hazards

Emissions in flight and lingering area effects: a shell, a `FrostField`, a `PlantedCharge`, a
bombardment zone. Tokens by the vocabulary; a kind of their own for the model because they are
consumed as a FIELD (the avoid-region channel) and never as tracks — most live below the
perception floor (§Time), and the ones that do not are read for their remaining lifetime
rather than their identity. Their CUES (§Cues) are the only part of them tracked individually.

### What is not a game kind

Tracks, groups, fields, regions, engagements and objectives are constructs of the MODEL over
the game. A human has none of them as game facts — they are how a human organises game facts
in their head — which is exactly why they live on the bot and not on `Commander`
([world-model](world-model.md) §The model). This note is the ontology of the game as
perceived; the model's own constructs are defined where they are built.

---

## Affordances: capability × scope × magnitude

An affordance is **not a boolean**. It is:

- a **capability** — what KIND of thing the piece can do (the table below);
- a **scope** — whom it acts on: `self`, a `target`, an `area`, or the `commander`;
- a **magnitude** — a number derived from component values, which for the relational
  capabilities EXISTS ONLY ONCE THE OTHER PARTY IS NAMED.

The paradigm case is the weapon. "Has a weapon" is the capability. What the bot needs is the
RELATION: threat of *a* to *b* is `reach(a, b) × dps(a → b)` with the damage table applied,
and "negligible" is `time_to_kill = hp(b) / dps(a → b)` past a horizon — a lone rifle against
a wall is lethal in principle and irrelevant in practice. The kernel exists —
`Bot.unit_effectiveness_vs`, `DamageTable.calculate_damage`, `Weapon.per_shot_damage` and
`split_time_ticks` — and stops at a multiplier; the affordance carries it on to a rate and a
time.

### The capability vocabulary

Each capability names the components it is derived from, so the set is READ, never declared.
Three capabilities replace the single "defence" word, which the code uses for one thing
(`Defense`, a piece's own constitution) and the economy ladder for another (a static
defence — which is a ROLE, §Roles are not affordances):

| capability | means | derived from | scope |
|---|---|---|---|
| **lethality** | can destroy | `Loadout` / `Weapon` (reach, `split_time_ticks`, damage type, `charged` → tethered to a `DockingBay`), `Payload` (`base_damage`, `damage_type`, `has_blast`, `hitscan`), crush via `Movement.can_crush`, damaging abilities (`AbilityDefinition.emission_path`), `PlantedCharge` | target, area |
| **durability** | how much it takes to destroy — the code's `Defense` | `Defense` (`hp_max`, `armour_type`, `frame_type`), `Shield`, `Stealth`, `Veterancy`, whether `Repairs` can reach it | self |
| **protection** | reduces harm to OTHERS — lethality's symmetric opposite | a shield provider, a `Garrison` host with `bunker` and `preserve_occupants`, `FrostField` as suppression | target, area |
| **mobility** | can be elsewhere | `Locomotion` strategy and speed, `Aerial`, `NavAgentClass.Size`, `Docking` (must return to rearm) | self |
| **sensing** | reveals | `VisionRange` shape, Scan (`AbilityDefinition.reveals`), `BeaconRange.radius`, detection of `Stealth` | area |
| **income** | makes resources | `EnergyExtractor.energy_rate`, `DominionGenerator.dominion_rate`, `OccupantDominionGenerator.dominion_per_unit`, `Shelter` (`spawn_interval`, `capacity`) | commander |
| **production** | makes pieces | `Production.producible_types` and rate, `Builds.buildable_types`, infrastructure provided and consumed | commander |
| **logistics** | holds, carries, restores | `Garrison` (`capacity`, occupancy masks, `is_closed`, `can_intern`), `DockingBay` / `DockingPad` / `Runway` (`charge_rate`), `Repairs.repair_rate` | target, area |
| **conversion** | changes what something is or whose it is | `Interactor` / `Interaction` (`DEPOSIT`, `HIJACK`), `Liberator` / `Liberatable`, capture | target |
| **persistence** | how long it is what it is | `Lifespan.lifespan_seconds`, `Deployable` (`deploy_ticks`, the noun switch) | self |

A capability a component does not express is not an affordance until a component does. The
list grows by adding a row with its derivation, never by adding a tag.

**Crush is lethality, and actuates as a Move at a target** (decided 2026-10-06). A crusher's
lethality against a piece it outsizes is a kill on contact: dps is effectively infinite and
time-to-kill is the travel time, so it is scored on the same signals as a shot. The game's
controls already express the order — a Move whose `CommandMessage` names a target FOLLOWS it
— so the actuator gains the target form of `move`, `BotTargeting` produces a run-over order for
a crusher as it produces Attack for a shooter, and the capture errand follows its prey rather
than walking to where it stood. Capture is then a BONUS on the kill, and crushing a
non-capturable is worth the kill alone; today's `CRUSH_EFFECTIVENESS` discount, which prices
a crusher that never drives through, expires with it.

### Relational affordances

Lethality needs a target, logistics an occupant, conversion a victim, protection a ward. These
are **relations between two pieces within a reach**, which is the same shape
[squads-and-relations](squads-and-relations.md) §Relations gives every inter-piece
dependency. One mechanism, not two: a relational affordance IS a relation whose magnitude the
components determine.

### Type-level, with instance deltas

An affordance set is a property of the TYPE and computed once per type; what varies per
instance is a short list of deltas — a `Veterancy` level, a spent clip, a `Shield` up or
broken, a `Deployable` stance, a modifier applied. The model stores the type's set and
applies the deltas on read. This is where the performance budget of the whole scheme goes,
and why the ontology insists on type-level derivation.

### Roles are not affordances

"Scout", "builder", "static defence", "spotter" are ROLES: an affordance plus a position plus
a job. `BotScout` already scores a scout from speed and vision — two affordances — and that is
the pattern: a role is an L3 read over affordances and the situation, decided by the bot,
never a property of the piece. The economy ladder's "defence structure" is lethality that is
also a fixture, placed at home.

---

## Time: what the bot can perceive at all

Three numbers, and every temporal rule in the model is one of them.

**The perception floor** — a constant of the model, **1.0 s to start** (decided 2026-10-06;
arbitrary, retune in testing). The shortest-lived thing the model will represent at all. A lead round reaches its target in a handful of ticks and the physics
supports no meaningful response to one, so it never enters L0, by construction. This bounds
the computation and the behaviour search space, and it is the model's, not a tier's.

**Reaction latency** — a `BotDifficulty` parameter, since the tiers are a parameter vector
and their periods are already "the tier's identity" (`bot_difficulty.gd`). A sighting becomes
a track only once it has persisted for `reaction_seconds`. It composes with the existing
decision periods: latency is when the bot NOTICES, the period is when it ACTS. Starting values
(decided 2026-10-06; arbitrary, retune in testing): `EASY` 2.0 s, so it never dodges
anything · `MEDIUM` 1.0 s · `HARD` 0.5 s · `IMPOSSIBLE` one perception tick, 0.2 s.

**Hazard lifetime** — derived from the emission: a phase list with a flight time gives
time-to-impact, `Lifespan` gives a dwell. **Whether a hazard can be answered is
`lifetime_remaining > reaction_seconds`**, which separates a ten-second shell from a lead
round with no per-type code.

---

## Attention: the sensor the human tiers look with

In the fusion model's terms L4 is sensor management; a human player's sensor is their GAZE.
So the model has a **focus** — a set of lattice regions perceived at full fidelity — and
**attention is the budget that sizes it**:

- **Foveal.** Inside the focus, L0 → L1 runs every perception tick: sightings become tracks,
  hazards get lifetimes, reaction latency applies at its tier value.
- **Peripheral.** Outside it, two things get through: commander-wide cues (§Cues), and the
  coarse fields — something is THERE, as a red blob on a minimap is, without composition or
  heading. That is the peripheral representation a human has.
- **The allowance** — a `BotDifficulty` parameter: how many focus windows the bot holds and
  how fast one moves. Rudimentary to start (decided 2026-10-06): a window is a disc of radius
  R = 15 world units on the lattice, moving at most one lattice hop per scout period; `EASY`
  holds 1, `MEDIUM` 2, `HARD` 3; `IMPOSSIBLE` has no windows, because its focus is the whole
  map. Retune in testing.
- **Where the focus goes** is already L4's output: the attention list prices what is worth
  looking at, and the human tiers take its top *k* where IMPOSSIBLE takes all of it. Scouting
  (where to send a unit) and focus (where to look) are two consumers of one ranking.

**The tiers and the budget point the same way, and must stay separate.** `EASY`–`HARD` are
human-level, meant to be beaten by players of increasing skill, and they process *k* windows
of a bounded lattice, so their cost is fixed and small by construction. `IMPOSSIBLE` is meant
to be inhumanly good and processes the lattice, bounded by map size; its larger allowance is
its own number in the scheduler's per-tick budget — a ceiling, never an exemption. Attention
is a MODEL budget and the scheduler's work units are a COMPUTE budget: they correlate, but a
tier's attention is never defined as "what fits in the frame", or the bot's skill would
follow the hardware.

---

## Cues: the bot perceives what the presentation layer presents

**L0 subscribes to the channels that present to the player, and to nothing else.** Three
channels exist or are planned:

| channel | what presents it | what L0 reads |
|---|---|---|
| game-wide announcement | nothing yet — see the `cue:` field below | a commander-wide event: a type and a time, a position only if the announcement carries one, no entity |
| rendered piece | fog + `Entity.is_visible_to` (`Stealth`, `fog_clear_at`) | a sighting — today's path |
| transient effect: particles, badges, animation state, sound | `StatusVisuals`, `MeshVisual` channels, `AnimationRig`, the audio players | a LOW-CONFIDENCE sighting, or a state hint on an existing track (reloading, under construction) |

**The stealth shimmer is the case study that proves the rule.** StarCraft II drew a subtle
shimmer for a cloaked unit the player could neither click nor target: the renderer presented
something, so the information was there for anyone who looked, and it disagreed with what the
game otherwise showed. Under this rule, if this game drew such a shimmer the bot would get a
faint sighting — and the fix, if that is unwanted, is to not draw it. **The only way to hide a
thing from the bot is to hide it from the player, and the only way to give the bot a signal
is to give the player one.** (This game does not draw a shimmer; the example is kept because
it fixes the rule.)

### Existence is derived; salience is declared

Whether a human CAN notice an effect — its size, contrast, duration, what else is happening
— is not derivable from code in general. What is derivable is that the effect EXISTS and for
HOW LONG (its node, its `Lifespan`, the clip length). So the two are split:

- **existence and lifetime** come from the code;
- **salience** is a small authored number ON THE THING THAT DRAWS IT — a `StatusVisuals`
  badge, a particle scene, an audio cue — scaling the reaction latency for that cue. Authoring
  lives with the presentation, so adding an effect and declaring how noticeable it is are the
  same edit, and **an effect with no declared salience defaults to imperceptible**, never to
  free information.

With attention in the model, catching a subtle cue costs attention: `HARD` may notice a
shimmer inside its focus, `EASY` never will, `IMPOSSIBLE` always does. That is the human-tier
distinction, falling out of two numbers rather than a special case.

### The `cue:` field

For announcements, the same discipline: a `cue:` field on an ability or emission doc,
validated by the importer, names an announcement every commander receives — a sound, a HUD
flash, both — and is the ONE source both the audio layer and L0 read. The bot then has the
signal iff the player does, by construction. Until the field exists L0 has nothing to read,
and the bot correctly knows nothing a player would not.

> **TODO — the `cue:` schema is undecided**: whether it carries a position, whether it is
> per ability or per emission phase, and which audio/HUD surface plays it. Decide with the
> first ability that needs one (a nuclear launch is the motivating case).

---

## Vision is unoccluded — and the scout grid is not

Found 2026-10-06 while checking this note's claims, and FIXED the same day; kept because the
ontology's placement rule is what it broke, and the record says what the rule costs to miss.

The fog (`fog.gd`) stamps every pixel inside a `VisionRange` footprint with no line-of-sight
test — `_vision_offsets` is a flat shape, and `Entity.is_visible_to` is stealth plus
`fog_clear_at`. But `BotScout._mark_seen_by` (`bot_scout.gd`) casts a physics ray against
`TERRAIN | STRUCTURE_BLOCKER` and stamps a grid point only when the ray is clear. So the
bot's "have I scouted this" is STRICTER than the game's "can I see this": a point behind a
ridge can be fog-cleared, its enemies visible to the player and to `visible_enemies()`,
while the scout grid keeps it unseen and sends scouts back to look at ground the bot already
sees. The bot invented an occlusion the game does not have.

The fix: `BotScout._mark_seen_by` now stamps a grid point when `Commander.has_vision_at` is
true there — the fog's own cleared pixel — and the raycast and its work units are gone. When
the one lattice lands the `sight_age` channel is stamped the same way.

---

## Open decisions

The perception floor's value and attention's shape were open here and are now set, as
arbitrary starting values, in §Time and §Attention; testing retunes them.

> **TODO — where salience is authored.** On the component that draws (a `StatusVisuals`
> badge, a particle scene) or in the piece doc the importer validates? The rule above says
> "with the thing that draws it"; the importer may still be the place that checks it exists.
