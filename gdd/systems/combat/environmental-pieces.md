---
title: Environmental pieces — hazards and pickups
type: system-note
---

# Environmental pieces: hazards and pickups

*Design note for [Dissent Horizon](../../../CLAUDE.md). Scoped and built 2026-10-16
(`Volatile`, `Pickup`, the `burning` and `cryo_burst` effects, the `volatile:` / `pickup:` doc
keys and the eight neutral pieces); the ordnance depot is §The ordnance depot. Filed under
combat because the blast is an emission; the pickups are cross-linked from
[map-composition](../terrain-and-navigation/map-composition.md).*

Pieces strewn about a map that the player turns on an opponent or picks up: a **hazard** is a
neutral piece whose destruction emits a blast, and a **pickup** is a neutral token a ground unit
collects by walking over it. Authored mainly for campaign scenarios, where they let the player
hurt enemies with the environment; nothing here depends on a faction.

## The rules

**A hazard goes off when its HP reaches zero, by any damage.** The science says a lead bullet
would not set a power cell off; the game says it does, because the player's fantasy is "shoot
it and it blows", not "bring the right weapon". Decided 2026-10-16.

**A hazard has a fuse, and the fuse is the blast's own first phase.** The piece dies as any
piece does; `Volatile` launches its blast emission where it stood (`Emitter.launch`,
unattributed), and that emission's first phase is a motionless lifespan — **0.25 s** (dropped from 1 s on 2026-10-16),
authored per blast doc — before the payout phase. The fuse is what makes a cluster of hazards
cascade *over a short period* rather than in one frame — each blast kills the next cell, whose
own fuse staggers it — and it is the player's reaction window to pull units back. Superseded:
a `fuse_seconds` on the piece that held the wreck in the world; the emission already had a
phase list to say it, and the planted charge's blast is the same shape. **The fuse phase says
`ends_on_arrival: false`**: a motionless phase still arrives at once, and without it the
fuse was one tick long (found by the render probe, 2026-10-16).

**The looks** are shared effect scenes under `scenes/effects/emissions/`, named by each
blast's phase `visuals:` — `plasma_vent` / `plasma_blast`, `cryo_vent` / `cryo_cloud`,
`cask_vent` / `radiation_motes` — plus a `GroundRing` on the two lingering fields. Every one
carries `AreaEffect`, which reads the host's `HitShape` and scales the authored look to it, so
the three plasma sizes share one scene and the burst is always the blast's size. A blast's
impact phase lasts as long as its longest particle (1.8–2.4 s), and the venting is the fuse
phase's own look.

**Blasts are symmetric.** A hazard hurts the commander who fired on it as readily as anyone
else. Neutral pieces draw no aggro (`commander_id == 0`), so a hazard only goes off when someone
*orders* an attack on it, or when a blast or stray fire reaches it. TODO: whether the bot should
ever target a hazard on purpose. Until decided it treats them as terrain, and a human player is
the only one who exploits them.

**Pickups are coins.** The first ground unit whose hull overlaps the token collects it for its
commander — any commander, including a bot — and the token leaves play. Aircraft collect nothing.
Nothing respawns.

**A piece is a hazard or a pickup, never both.** The fuel the pickups hold is stored in a form
that does not explode (below), so a player never has to wonder which one a shot will cause.

## The pieces

All neutral (`default_commander_id: 0`), `commandable: false`. Hazards are features (they claim
their cells); pickups are tokens (walkable, no footprint). Blast radii are
[shape-library](../../shapes/shapes.md) buckets, never bare numbers.

### Hazards

| id | what it is | noun, size | blast | effect |
|---|---|---|---|---|
| `nt_powerCell` | a man-portable storage cell | token, infantry-sized | `aoe_small` (1) | PLASMA damage; structures hit start **burning** |
| `nt_batteryRack` | a rack of cells | 1×1 structure | `aoe_medium` (2.5) | the same |
| `nt_batteryBank` | a settlement's shielded bank of racks | 2×2 structure | `aoe_large` (5, reaches aircraft) | the same |
| `nt_cryoDewar` | a cryogen coolant dewar | token, vehicle-sized | `aoe_small` | **Freeze** on every unit in the burst |
| `nt_activationCask` | a shielded cask of spent reactor internals | token, vehicle-sized | a lingering `aoe_small` field | damage over time to every unit standing in it, whatever its frame |

**The three small hazards are tokens** (decided 2026-10-16): a cell, a dewar or a cask stands
where it is put, claims no cell of the grid and has no means of movement — `commandable:
false` and `defense:` with neither `footprint:` nor `movement:`, the planted charge's shape —
so a mission can strew them through a street a unit still walks. Only the two batteries are
fixtures. A token's size is its model's: `AreaEffect`'s host `HitShape` sizes the burst, and
the importer fits the hurtbox to the generated model.

Damage numbers are tuned in the pieces' docs, not here.

**Burning is a status effect for fixtures**: `burning.tscn`, a `DamageOverTimeStatusEffect`
dealing INCENDIARY for 10 s, that a repair puts out (`StatusEffect.ends_on_heal`, shed by
`Defense.restore` beside the hostile markers). It takes hold on fixtures only through
`StatusEffect.host_filter`, the fixture/figure axis beside the stun's frame mask — so one
blast names it and the units in the blast take the damage alone. The numbers are the scene's;
tune them there. A burning structure does not spread fire to a touching one: the cascade is
the hazards' job.

**The cask's field is the `radiation` emission with a long lifespan** (the Radiate ability's
field lasts 10 s; this one lasts on the order of a minute — authored on the piece), **dealing
INCENDIARY** rather than the Radiate field's LEAD. Decided 2026-10-16 for how it scales: full
against BIO, 0.4 against MECH, and falling off with armour (1.0 / 0.75 / 0.4), so every unit is
hurt but a strong vehicle shrugs most of it off. Superseded: a tenth damage type for radiation,
and PLASMA at a low rate — neither earns a row the tables do not already have.

The dewar's freeze is `cryo_burst.tscn`: the existing `FreezeStatusEffect` (10 s, STRONG
armour immune) in a second scene with `host_filter: FIGURES`, applied through the burst
emission's `status_effects:` — a dewar freezes units, not structures, like a frost field. A
second scene rather than a flag on the Freeze ordnance's, because that one freezes structures
on purpose; a tier is authored data (`bio_stun` / `emp` share a script the same way).

### Pickups

| id                 | what it is                                             | grants                                                                                                             |
| ------------------ | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `nt_fuelCartridge` | one deuterium cartridge                                | 500 energy                                                                                                         |
| `nt_fuelCache`     | a pallet of cartridges                                 | 2000 energy                                                                                                        |
| `nt_courierPod`    | a downed courier capsule (the generic ordnance pickup) | charges of one ordnance, authored per instance (a Mortar Strike by default, so a debug-spawned pod does something) |

**The ordnance pickup is one mechanic with several skins.** `pickup: {ability: <id>, charges: n}`
is authored on the scene instance, so what a pod grants is a map-design decision and never a
property of the piece; a mission can make a Haustori relic hand out a Baladian strike. The skins
exist so the *reason* for support reads on the map — recovering something a broader military
body wants is what earns the favour. Candidate skins, TODO which get a model:

| skin | the artifact | who it reads as |
|---|---|---|
| courier pod | a crashed drop capsule with a sealed dispatch | generic — any off-map command |
| regimental standard | a confederation's colours, lost with the unit that carried them | Haustoria |
| commune archive | a collective's ledger of names, debts and ties, worth more than its stores | Baladian |
| Ward core | a decommissioned Ward's sealed logic core — Wards are opaque to each other, so the core is sovereignty itself | the Warden |

### Where they sit

Settings differ by level; the pieces are pervasive technology, so each setting has its own mix:

| setting | hazards | pickups |
|---|---|---|
| an anarchical stronghold | power cells among the shacks, a dewar at the chop shop | cartridges in stores, a commune archive |
| a military base | battery racks by the hangars, a bank at the core, casks in a fenced yard | a fuel cache, a standard or a Ward core |
| a desolate frontier | a lone battery rack at an abandoned extractor, a wrecked courier | a scattered cartridge or two |

## The ordnance depot

An ordnance's charges live in `Abilities` pools on the commander's PIECES (a Citadel's pool
grants Scan), and a cast is an order a caster carries out. A courier pod's charges have no
piece, so they go into the commander's **depot** (`OrdnanceDepot`, built with every
`Commander`): a purse of free charges that never recharge and are cast by the commander
directly, from nowhere — `Sanction.activate` with no caster, which every off-map event
already allows for (its anchor falls back to the aim point). Decided 2026-10-16 over topping
up an owned piece's pool, which would have made a mission reward silently worthless to a
player with no such piece.

- **A depot charge casts through the commander's own sanction grid when that has a cell for
  the ability**, unlocked or not: the cell in play when one is owned, else the lowest-tier
  cell granting it (`SanctionGrid.entry_for_ability`). **Otherwise it casts through the lowest
  level any faction authors of it** (`OrdnanceDepot.foreign_sanction_for`, read off every
  faction scene once per run), so a Colonial who recovers an Anarchist dispatch calls the
  Mortar in as Mortar 1. Decided 2026-10-16, after the first pod shipped castable only by
  the faction that authored its ordnance: a `Sanction` lives on a faction scene and holds no
  per-commander state, so another faction's template is cast as-is.
- **The commander's command centre stands in as the caster.** An off-map ordnance keys its
  entry edge to the caster, and a cast from nowhere would otherwise arrive over whichever
  edge is nearest the aim point; anchored on the centre it comes over the commander's own
  side like any other call-in. With no centre in play the aim point is the anchor. Superseded:
  an off-screen sentinel piece owning the charge, which would have put the edge nearest a
  place the player never sees.
- **The depot is spent first.** Issuing an ordnance the depot holds spends the free charge
  before any caster's recharging one (`RTSController._issue_sanction`). The cast travels the
  order stream as `PlayerOrder.Kind.CAST_FROM_DEPOT`, so a replay fires it on the same tick.
- **On the card** a depot charge counts as one ready caster, and shows a dominion-locked
  ordnance the grid has no cell of in play, or none at all; pressing it with no caster to
  select arms the depot's sanction on its own, and the right-click fires it from the depot.
- TODO: the bot never casts from its depot.

## The science grounding

The world runs on fusion ([energy-economy-notes](../../setting/energy-economy-notes.md)): every
faction's economy is deuterium and lithium, and hydrogen-isotope handling is as ordinary as
propane. That note already settles two things used here — bulk cryogenic deuterium is violently
explosive, and fuel absorbed into a **metal hydride bed** is stored that way precisely to avoid
energetic release.

**Power cells are superconducting storage — batteries, not reactors.** A cell is a
superconducting coil holding a charge, delivered full and swapped when spent, like a gas
bottle; a rack wires a dozen of them as one and a bank shields a yard of racks. That framing
is the whole answer to the grid problem — a cell is self-contained, so blowing one up
disconnects nothing and the next cell is still live — and it is why these are called
batteries rather than plants: nothing here generates. Their fault is a magnet **quench**: the
coil loses superconductivity in one spot, the current there turns to heat, the normal zone
races along the coil and the stored field — hundreds of megajoules at fusion scale — dumps as
arcs that melt and puncture the vessel. The arc-heated gas and the boiled-off helium coolant
are, literally, a plasma: a blinding blue-white burst with a brief fireball that lights what it
touches. Three sizes are three inventories, not three technologies. Superseded 2026-10-16: the
pieces as fusion power packs and a plant — "plant" said generation, and a pack was unclear.

**The cryo dewar is the coolant that keeps those coils cold** — liquid helium or nitrogen — and
the same cryogenics Haustoria builds weapons from. A ruptured dewar flashes its contents to gas:
a pressure burst, then a dense cold cloud that hugs the ground. In reality the cloud asphyxiates
and frostbites; in the game it is a Freeze.

**The activation cask holds what a reactor's neutrons did to its own walls.** Fusion makes no
fission products, but its neutrons activate the first wall and magnet shielding; spent internals
go into shielded casks to decay (cobalt-60 alone takes decades). A breached cask scatters
activated debris, which irradiates everything near it — organic or mechanical, since gamma
radiation does not care about the frame — and keeps doing so long after the breach. That is
why the brief's "every unit, lingering" is the accurate reading, and why the older bio-only
tritium plume is set aside for this piece.

**The fuel cartridges are inert because the fuel is in a hydride bed.** Deuterium bound into
metal powder cannot BLEVE and does not jet; a punctured cartridge leaks slowly and, at worst,
burns as a powder if lit. So the pickup and the hazard are different objects: the cartridge is
what a power cell is *fed*, and the two should never share a silhouette.

**The courier pod is a drop capsule** of the kind the Colonial `drop` ordnance already lands;
one that came down wrong, with its dispatch intact, is a plausible thing to find on a frontier.

## How it is built

- `Volatile` (`scripts/entities/components/volatile.gd`; doc key `volatile: <emission id>`):
  on its host's `ON_DEATH` it launches the blast where the host stood, owned by the host's
  commander and fired by nobody. Chaining needs nothing of its own — the blast is ordinary
  damage, and `Actor.resolve_death` lands the next death on the tick that dealt it.
- `Pickup` (`scripts/entities/components/pickup.gd`; doc key `pickup: {energy: 500}` or
  `pickup: {ability: <id>, charges: n, radius: r}`): each tick it asks the world for the
  pieces within `radius` of its centre and hands the token to the first ground unit of a
  commander with a purse, in serial order; then `Entity.expire()`, so the token leaves play
  without a death. A pickup doc is composed as a FEATURE-tier plain `Entity` — a hurtbox, a
  model and a selection shape, no cells and no hit points — which is why `pickup:` counts as a
  body in the importer's discriminator rule.
- The eight pieces and five emissions are docs under `gdd/factions/neutral/` (`structures/`,
  `tokens/`, `projectiles/`), their scenes composed by the importer. Their models are generated
  low-poly ones (`tools/structure_models/`, `StructureModels.token_catalog` for the tokens,
  whose extents are authored there since they have no footprint; written to
  `assets/meshes/entities/tokens/`). The debug spawner lists every one of them under Neutral:
  a pickup or a hazard is a token a mission places by hand, so the roster counts it as
  placeable (`SpecGenerators.debug_roster_json`).
- TODO: the bot neither targets a hazard on purpose nor walks to a pickup.
- TODO (deferred 2026-10-16): whether the map generator scatters any of these in skirmish.
