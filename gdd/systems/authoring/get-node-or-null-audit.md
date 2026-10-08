# `get_node_or_null` Audit

Re-derived 2026-10-08 against the composed tiers of
[entity-scene-hierarchy](entity-scene-hierarchy.md) §What a piece is entitled to assume. A site's
verdict now asks one question: **does every piece shape that reaches this code get the node from
the composition?** If so, `get_node_or_null` is hiding a scene-setup bug and the node could be
required; if not, null is a real state.

Who reaches the code decides it, not the component:

- `entity.gd` runs for every piece shape — an Actor (`Actor`), a feature (an uncommandable
  fixture on an `Entity` root), a bodiless piece, an emission — and for out-of-tree build
  previews, whose `@onready` fields never resolve. Only `Ownership` is guaranteed to all of them.
- `commandable.gd` runs for Actors only, which are guaranteed `Hurtbox`, `AggroRangeGround` /
  `AggroRangeAir`, `Ownership`, `Defense`, `Veterancy`, `Selectable`, `HPBar`,
  `SelectionIndicator`, `CommandLineIndicator`, `StatusVisuals`, `DebugLabel` and
  `TargetIndicator`; a MOBILE Actor adds `NavigationAgent`, `MovementBody`, `Locomotion`,
  `AltitudeIndicator` and `AvoidanceObstacle`.
- A test fake (`tests/_fake_pieces.gd`) carries only the components a test names, so turning a
  guaranteed site into `$Node` means the fake gains that node too.

**Verdicts:**
- ✅ **Optional** — some shape that reaches the code lacks the node; null is a real state.
- ⚠️ **Guaranteed** — every composed shape that reaches the code has it; `$Node` would do, and a
  null means a hand-edited scene or a fake missing it.
- 🚨 **Wrong** — the lookup can silently disable something that should always work.

## `scripts/entities/entity.gd`

| Line | Node | Who has it | Verdict |
|---|---|---|---|
| 116 | `Defense` | Actors | ✅ a feature or emission takes no damage |
| 119 | `Aerial` | `aerial:` in the doc | ✅ |
| 123 | `Locomotion` | mobile Actors, emissions | ✅ null is "cannot move" (`can_move()`) |
| 159 | `Stealth` | `stealth:` in the doc | ✅ |
| 164 | `DetectionRange` | detectors | ✅ |
| 166 | `VisionRange` | sighted Actors and bodiless pieces | ✅ features and emissions see nothing |
| 171 | `Loadout` | armed pieces | ✅ optional for every shape |
| 177 | `Selectable` | Actors and features | ✅ bodiless pieces and emissions are never selected |
| 186 | `Hurtbox` | Actors and features | ✅ bodiless pieces and emissions are untargetable |
| 207–208 | `AggroRangeGround` / `AggroRangeAir` | Actors | ✅ at this level; guaranteed for every Actor |
| 265, 293, 320, 629 | `Fixture` | fixtures | ✅ its presence IS the fixture question |
| 272, 279, 321 | `Locomotion` as `Movement` | mobile Actors | ✅ a navigated mover is the question |
| 460–462 | `Body`, then `MovementBody` | `Body`: the Recon Drone only; `MovementBody`: mobile Actors | ✅ a fixture measures its footprint instead |
| 503, 514, 542 | `Hurtbox/HurtboxShape` | every piece with a `Hurtbox` | ✅ guarded on the hurtbox already; the shape node ships in `hurtbox.tscn` |
| 873, 892 | `Ownership` | every composed piece and emission | ⚠️ called on out-of-tree previews, where `get_node` works and `@onready` does not, so `get_node("Ownership")` would do |
| 881 | `MeshVisual` | pieces that draw a model (the `has_mesh_visual` waiver removes it) | ✅ |
| 1046 | `ScenarioTriggerManager` on the scene root | scenarios | ✅ a piece can be in a test with no scenario |

## `scripts/entities/actor.gd`

| Line | Node | Who has it | Verdict |
|---|---|---|---|
| 30 | `AvoidanceObstacle` | mobile Actors | ✅ a structure has none |
| 32 | `Production` | producers | ✅ |
| 57 | `EnergyExtractor` | extractors | ✅ |
| 59 | `DominionGenerator` | dominion sources | ✅ |
| 61 | `Garrison` | hosts | ✅ |
| 66 | `DockingBay` | airfields | ✅ |
| 68 | `Docking` | `docking: true` | ✅ |
| 69 | `Interactor` | pieces with interactions | ✅ |
| 70 | `Liberator` | liberators | ✅ |
| 72 | `Deployable` | deployable units | ✅ |
| 106 | `DebugLabel` | every Actor | ⚠️ guaranteed by the composition |
| 371 | `TargetIndicator` | every Actor | ⚠️ guaranteed by the composition |
| 674, 1297 | `MeshVisual` | pieces that draw a model | ✅ waivable |

## Other sites

| Site | Node | Verdict |
|---|---|---|
| `movement.gd:201` `_nav_agent` | `NavigationAgent`, bound for a GROUNDED mover only | ✅ an aircraft never binds it by design; the node is guaranteed with the `Locomotion`, so a grounded mover missing it is a hand-edited scene. TODO: assert when `nav_agent_path` is set and a grounded mover finds nothing |
| `movement.gd:747` `Aerial` | `aerial:` in the doc | ✅ |
| `production.gd:82` `_train_bar` | the bar `train_bar_path` names | ⚠️ an empty path suppresses the bar on purpose; a set path that finds nothing is a broken scene and trains silently |
| `production.gd:289` `TrainBarFill` | a child of a bar already found | 🚨 a bar without its fill never animates and says nothing; should be `get_node` |
| `production.gd:387`, `command_context_parser.gd` (×9) | `DockingBay`, `Loadout`, `Abilities`, `Garrison`, `Production` on an arbitrary piece | ✅ discovery questions asked of any piece |
| `selectable.gd:78` | the node `indicator_path` names | ✅ warns on the wrong type |
| `payload.gd:48, 57, 152` | `Payload`, `HitShape`, `Locomotion` | ✅ `HitShape` is the blast, absent exactly from hitscan emissions; `Payload.of` is a discovery question |
| `weapon.gd:107, 116, 532` | `AttackRangeGround` / `AttackRangeAir` / `AttackRange` | ✅ which shape a weapon has says which layers it reaches |
| `weapon.gd:335` | `turret_visual_path` | ✅ a turret with no visual part to swing |
| `weapon.gd:557` | `Aerial` on the wielder | ✅ |
| `rts_controller.gd:4413` | `Sprite` on a placement source | 🚨 the fallback for a ghost with no `MeshVisual`, and no piece has a node named `Sprite`, so it never finds one: a piece that waived its model gets no ghost at all. TODO: remove the branch, or give a model-less piece a ghost some other way |
| `heightmap_mesh_generator.gd:144` | `GeneratedMesh` | ✅ create-or-update |

## Summary

Of the sites above, the ⚠️ ones are guaranteed by the composition and could be required —
`Ownership` in `entity.gd`, `DebugLabel` and `TargetIndicator` in `commandable.gd`, and
`Production`'s bar when its path is set. The 🚨 ones hide a broken state or are dead:
`TrainBarFill` and the controller's `Sprite` branch. Everything else is a real optional state of
some shape that reaches the code. The rest of the project's ~260 calls are discovery questions
asked of an arbitrary piece (`X.of(piece)`, `has a Garrison?`) and are not listed one by one.
