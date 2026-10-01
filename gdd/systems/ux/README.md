---
title: UX
type: system-index
---

# UX

Everything the player experiences apart from the rules themselves, in two halves:

| Folder | Covers |
|---|---|
| [ui/](ui/) | the **interface**: the concrete panels, buttons, cursor, input and on-screen readouts that are built |
| [aesthetics/](aesthetics/) | the **experience**: art direction, and the quality considerations each asset is judged by |
| [scoring.md](scoring.md) | the arcade grade — numerical underneath, but its job is feedback to the player |

**Belongs here:** how any game state is presented — seen or heard — and what assets the game
must carry to present it.

**Does not belong here:** what a mechanic does. A status effect's rules are
[combat](../combat/); how it is drawn is [ui/condition-visuals.md](ui/condition-visuals.md).

## Pending pieces are shown, as pending

**A preview or readout that describes what the player's pieces do counts the pieces they have
ORDERED as well** — a blueprint still waiting for a builder, a structure going up — and draws
their contribution slightly differently: "this will have this effect, but not yet". A player who
queues several things plans each against the last, and a readout that ignores the queue answers
a question they were not asking.

**"Ordered" means `Commander.pending_pieces()`:** blueprints, structures going up, one-off
purchases still in the production queue, and units a producer has started. A standing queue entry
is a policy rather than an order and is left out. Pieces count for their commander's SIDE
(`Commander.shares_side_with`): allies' pending pieces will show, enemies' never do.
PLANNED — ALLIES: a side is one commander until alliances land.

Where the rule is applied:

| Readout | What pending pieces add |
|---|---|
| Placement grid, dominion claim layer | tiles pending Opticons will claim; paying tiles a planned building will cover ([construction-visuals](ui/construction-visuals.md) §The placement grid) |
| Placement grid, footprint | cells a planned building on our side has claimed read as refused |
| Placement range rings | the reaches of our structures a placement would overlap, pending ones dashed ([construction-visuals](ui/construction-visuals.md) §Range rings while placing) |
| Energy bar | the slice of banked energy queued purchases have promised; the income pending extractors will add ([economy-bars](ui/economy-bars.md)) |
| Infrastructure bar | the capacity and upkeep pending pieces will add, and a deficit they will open or close |
| Dominion bar | the income pending generators and Opticons will add, past the rate projection |
| Docking soft gate (NO_PAD) | ordered aircraft take pads; ordered airfields add them |
| Blueprint badge | a blueprint whose purchase is waiting for energy carries an awaiting-funds badge ([condition-visuals](ui/condition-visuals.md)) |
| Tech gating | a prerequisite on its way makes an order queueable rather than LOCKED ([command-card-and-hotkeys](ui/command-card-and-hotkeys.md) §What a darkened button means) |

TODO — a negative pending change (a planned building over paying Opticon ground) does not show on
the dominion bar; only the claim layer shows it.

### How "pending" looks

TODO — the idiom is a placeholder awaiting a decision. Built today, all from one place
(`PendingStyle`): a bar region in the real colour at reduced opacity, and a world outline
DASHED. The claim layer's own pending tiles use a fainter wash of the same colour. The tenses it
has to stay distinct from:

- **Real** — solid.
- **Preview** (hovered or armed, not yet ordered) — the colour mixed toward the panel background
  and opaque ([economy-bars](ui/economy-bars.md) §Hover previews).
- **Projection** (a forecast over time, the dominion rate region) — the colour at half opacity.
- **Pending** (ordered, not active) — see the options.

Options:

1. **Opacity tiers** (built). Pending is fainter than a projection, which is fainter than real.
   Cheapest and consistent with the committed-energy request, but it leans on one axis for three
   tenses, and pending and projection can be hard to tell apart where they sit side by side.
2. **Hatching for pending.** Diagonal stripes on bars, dashes in the world. Reads as "reserved"
   or "under construction" at a glance and leaves opacity to mean projection. Costs a stripe
   shader or texture on the bars.
3. **Outline only for pending.** A bar region drawn as a bordered empty box, a world area as an
   unfilled outline. Very distinct, but a thin outline on an 18-pixel bar is easy to miss.

### Estimated time to a pending piece

TODO — wanted: an estimate of when a planned piece will be up, shown against it. Undecided, and
cost will decide the detail. What has been considered:

- Per builder with several sites queued: past build durations plus travel time to each site.
  Travel computed ONCE when the plan is placed, and accepted as going stale when the navmesh
  changes, is probably affordable. Tracking navmesh changes is a nice-to-have, but may be
  expensive and could leak knowledge of areas the player has no vision of.
- Waiting on funds: the time until the energy exists at the current income, updated as income
  changes. Folding in income from pending extractors is not needed.

## Tracking asset work: slot kinds, not asset lists

This note tracks what the game must be ABLE to present. It never lists which pieces still
lack art — the implementation reports that.

**A row names a slot KIND, and the game's own data supplies the instances.** "Every unit has a
voice line per line type" rather than "the Warlord's select bark"; "an animation per action a
unit can perform" rather than "harvesting animations". A new piece, action or status effect
therefore adds slots without this table changing. Only a mechanic that adds a new *dimension*
(say, a wake for every hull, once there is water to sail) needs a new row, and that is a
question for scoping the mechanic, not for this file.

**A row is binary.** Either the slot kind exists and something reports on its instances, or
it does not yet exist (`TODO`). Whether a filled slot is any *good* is not tracked here; that
is [aesthetics/](aesthetics/README.md).

### Asset slots

A slot kind that is built is an **`ASSET` rule** in the spec importer
(`tools/spec_import/spec_rules.gd`). Every instance is in one of four states
(`SpecRules.AssetState`):

| State | Meaning |
|---|---|
| `FILLED` | a real asset is present |
| `PLACEHOLDER` | a stand-in is present — the importer's generated model |
| `MISSING` | expected, and nothing is there |
| `EXEMPT` | the piece's doc waives the slot, with a reason |

The importer **assumes every slot is wanted**. Only a waiver in the doc's `exceptions:` block
says otherwise, and the waiver goes `STALE`, failing the import, once the slot is filled. An
unfilled slot is printed in the import summary and is **never an error**, because a missing
asset crashes nothing. The game says nothing about it at runtime either: the importer's
report is the one place a missing asset shows up, so a silent sound table or a
placeholder model is not a runtime fault. The verdict mechanics:
[calibration-rules.md](../authoring/calibration-rules.md).

A slot kind that applies only to some pieces tests a **facet**, never a doc kind. Voice lines
answer orders, so they are asked of units (commandable pieces that move); a structure or a
token has no such slot at all, which is different from being `EXEMPT`.

## The slot kinds

### Pieces

| Slot kind | Instances from | State |
|---|---|---|
| Model | every piece and emission | `ASSET` rule `has_mesh_visual`; placeholders baked by [generated-visual-defaults](ui/generated-visual-defaults.md), per-slot detail from `tools/ui_audit.gd` |
| Look per construction state | structure lifecycle | built — [construction-visuals](ui/construction-visuals.md) |
| Look per condition (effects, veterancy, capacity, unpowered) | status effects, passives | built — [condition-visuals](ui/condition-visuals.md) |
| Selection shape, HP bar | every piece | built — [generated-visual-defaults](ui/generated-visual-defaults.md) |
| Visual per emission phase | `EmissionPhase` children | TODO: `EmissionPhase.visuals` exists, but an empty list means both "nothing belongs here" and "nobody made it"; it wants an `ASSET` rule with a per-phase waiver |
| Animation per action | the actions a piece can carry out (`ActionTracker.Action`) × its model layers | transitions built, playback TODO; action badges stand in meanwhile — [unit-animation](unit-animation.md) |
| Destroyed state | every piece | TODO: nothing is left behind. Structure rubble is the surviving idea ([ideas.md](../../design-framework/ideas.md) §Rubble); unit wrecks are rejected there |
| Model parts and variants | named parts (hull, turret); variant keys (an upgrade, later a cosmetic) | Turret built for one piece — `Weapon.turret_visual_path`, see [combat/turrets](../combat/turrets.md) §The visual. TODO: revisit with the movement and action physics rework, which owns how a part such as a turret aims independently. The schema should not be settled before that |

### Audio

| Slot kind | Instances from | State |
|---|---|---|
| Voice line per line type | every unit × `ControlFeedbackSounds.LineType` | `ASSET` rule `has_voice_lines` |
| Death sound | every piece — a structure's collapse is its death | `ASSET` rule `has_death_sound` |
| Sound per other piece event (a production loop, construction) | pieces × events | TODO |
| Sound per weapon discharge and impact | weapons, emission phases | TODO |
| Sound per interface action and alert | control actions, alerts | TODO |
| Music, ambience per map | game states, maps | TODO |

### World

| Slot kind | Instances from | State |
|---|---|---|
| Surface per tile type | the tile-type catalog | TODO: `deferred.md` 2.7 — `TileType.texture` is reserved and unread |
| Water | water bodies | built — [water-bodies](../terrain-and-navigation/water-bodies.md) |
| Decoration per obstacle kind (mountain model over impassable cells, shoreline) | obstacle kinds: ridges and mountains, chasms and lakes | placeholder doodads and ground paint built; dressing PLANNED per facet — [visual-facets](../terrain-and-navigation/visual-facets.md) §Shortlist |
| Doodad per kind (trees, rocks, shrubs) | `DoodadLibrary.Kind` | PLACEHOLDER: primitive-shape stand-ins built in code |
| Fog of war | — | built — `scripts/maps/fog.gd` |
| Environment per map (sky, light, atmosphere) | scenarios | PLACEHOLDER: one default rig and Environment for every scenario that authors none — [aesthetics/lighting](aesthetics/lighting.md); per-map presets TODO |

### Interface and presentation

The standing HUD is [ui/](ui/README.md), and each of its notes is its own row.

| Slot kind | State |
|---|---|
| Minimap | built — [ui/hud-layout](ui/hud-layout.md) §The minimap |
| Menu screen per entry point (title, match setup, settings, loading, post-match) | TODO: a main menu exists (`scenes/menu/main_menu.tscn`); the rest is unscoped, and the win/lose screen is `deferred.md` 2.9 |
| Campaign presentation (briefings, portraits) | TODO: follows `gdd/modes/campaign/` |
| Accessibility variant per signal (colourblind team palettes, a shape beside every colour) | TODO |

Multiplayer, spectating, replays and cosmetics are not scoped, so they have no rows. Scoping
one of them is what adds its slot kinds here.

- REJECTED — a separate asset catalog with its own asset ids and a hand-kept status column: a
  second id scheme beside the piece ids, and a status the importer already derives.
