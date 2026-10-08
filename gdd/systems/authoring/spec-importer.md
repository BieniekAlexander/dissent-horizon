---
title: Spec importer
type: system-note
---

# Spec importer

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## `Tool` wiring and the spec importer


`Tool` (`scripts/entities/tools/tool.gd`): a ControlBinding with `type: StringName` (a piece id) and `packed_scene`. `Tool.command_tool_map` is BUILT FROM GENERATED DATA at startup (`resources/generated/tools.json`, derived from each piece doc's `ui:` frontmatter). Command names follow `command_tool_<id>`. To add a buildable/trainable piece: give its gdd doc a `ui:` key and re-run the importer — no code edit. `Tool.Faction` masks are button-grid layout metadata (collision review), never gameplay gating.

A tool's `ui.grid` cell decides both WHERE its button is drawn and, through how the piece is acquired, WHICH CARD (a built piece — one with a footprint that no producer trains — is BUILD/ACTIVE, a trained one TRAIN/PRODUCTION — `Tool` derives `family` from the context so it is never authored twice). The generated registry also carries `producers` per train tool, derived from every structure's `trains:` list, which is what the grid collision review uses to tell two buttons apart (see §The command card's two families).

A tool button's **text is the doc's `title`** and its two tooltip tiers are **synthesized from the same doc's stats** (`SpecGenerators.tool_tooltip` / `tool_verbose_tooltip`), so renaming or rebalancing a piece re-labels and re-describes its button. There is no `ui.label` — a doc carrying one is a hard error. It existed as a SECOND display name and drifted from `title` exactly as you'd expect: docs whose label was still the raw id put `an_command_center` on a button whose piece is called Stronghold. A piece with no title (or one that just repeats its id) is warned about at import and falls back to the raw id, so an unwritten name looks unwritten. `ui.tooltip` / `ui.verbose` override a synthesized tier when a piece wants authored words.

### The doc's shape

**A doc's key order and nesting are part of the schema**, not layout.
`tools/spec_import/schema.gd` (`SpecSchema`) holds the canonical order and the nests; this
section holds only what the code cannot say.

- **One top-level key per component; its sub-keys are that component's authored values**,
  read top to bottom, so a doc's outline IS its component set. The discriminating keys
  (`movement:`, `footprint:`, `weapons:`, …) stay flat: a `components:` umbrella would add a
  level that says nothing.
- **Each departure is where authoring comfort beat the node tree.** `build:` is named for the
  macroeconomic TRANSACTION, which no single component owns (`technology.json`, the tooltip
  and the Scavenge bounty all read it). `senses:` groups three independent root volumes
  because they answer one question and calibration rules compare them. `body:` puts
  `movement_radius` beside `hurtbox_radius` rather than beside `speed`. `flavor:` is the same
  copy at two lengths. `exceptions:` is last because it is commentary on the numbers above it.
- **`commandable` is derived, not defaulted**: true for a doc naming `footprint:` or
  `movement:`, false for one naming `phases:`, so it lives with the discriminators that decide
  everything else. The key is an override, and a redundant one is permitted and silent —
  changing the derivation is big enough that every spec gets revisited anyway, so policing
  agreement would only stop people writing down what they mean. `build.completes_as` defaults
  to `STRUCTURE`.
- **Order is never a validation failure.** The importer rewrites frontmatter into canonical
  order in the pass that already writes docs — a second visit would race Obsidian Sync. The
  rewrite is idempotent, keeps unknown keys (sorted to the end of their level), moves whole
  key blocks rather than re-serialising values, and hands back unchanged any level it cannot
  order safely.
- **Two vocabularies, one seam.** `SpecSchema.normalize` lifts the authored nests onto the
  flat internal names the rest of the importer uses, which is why nesting moved no other code.
  Messages name keys the author's way (`SpecSchema.doc_key`); a retired flat spelling is a
  hard error naming its replacement. PLANNED: the composition rework retires the internal
  names.

`commandable:` decides the `"unit"` group, which the importer writes on every piece's root
(`SpecSchema.derived_groups`). PLANNED — `build.completes_as:` has no consumer yet, and the `has_mesh_visual` opt-out
removes only the importer's placeholder; now that scenes are composed (composition-rework
§Step 4) it can remove the `MeshVisual` itself, which is step 5.

TODO: `tools/balance/gdd_to_balance.py` parses the docs itself and mirrors `SpecSchema.NESTS`
in its own `flatten()` — two copies of one table; it should derive from the schema.

### What belongs in a doc, and what stays editor work

The dividing line is **spatial vs. not**. A value you would type the same way whether or not the editor were open belongs in the doc; anything you would place, drag, or eyeball stays in the scene. Art, collision-shape POSITIONS, VFX and `DockingPad` placement are editor work by that rule; a capacity, a rate, a bitmask and a radius are not.

Two capabilities were scene-only for longer than they should have been, and both said so in prose — `cl_bioLight_stealth.md` carried "hand-added `Stealth` node on `sleeper.tscn`", `cl_mechMedium_antiLight.md` carried a capacity annotated "(a guess; not specified)". A doc describing what someone did in the editor is exactly the drift the importer exists to prevent, so both are now keys:

| Key | Component | Shape |
| --- | --- | --- |
| `stealth: true` | `Stealth` | a bare flag, like `repairs:` — presence IS the mechanic, since the component has no exports at all |
| `senses.detection: detection_small` | `DetectionRange` | a library shape, like `senses.vision:` — but the node is NOT on the commandable base scene, so the importer creates it on demand |
| `garrison: {…}` | `Garrison` | a mapping; `false` removes the component, `true` is refused |
| `occupancy_size: 2` | `Entity` | how much of a host's capacity this piece consumes |

They pair up, and that is why they landed together: `detection` is what SEES a `stealth` unit, and `occupancy_size` is the other half of `garrison.capacity` — which counts OCCUPANCY, not heads, so a capacity-8 transport holds eight soldiers or four Collectives.

**The `garrison:` mapping keeps the component's two questions apart**, exactly as `Garrison` does. WHO may enter is three enum-name lists (`frames` / `armours` / `movements`) assembled into the occupancy bitmasks; HOW MUCH room there is is `capacity`. The lists are NAMES rather than raw ints because `occupiable_frames = 1` in a doc says nothing to a reader and everything to a bug, and `movements` reuses `movement.mode`'s exact spelling so there is one locomotion vocabulary.

**`closed: true` is the closed hold** (`Garrison.is_closed`) rather than three empty lists. The domain already has the name, so the schema uses it — and clearing the masks by hand is easy to get HALF right, which yields a garrison that is quietly not a hold at all. Naming `closed` beside any occupancy list is a hard error rather than one silently winning.

**`blast:` on a projectile is the AREA of a weapon, and ONE shape governs both halves.** It names the `aoe_*` library shape put on the projectile's `HitShape`, and `Payload.apply` resolves the entities that shape overlaps EXACTLY ONCE, then damages that set and seeds its `EffectApplicator`s with the same set. So widening a blast widens what is hurt and what is EMP'd/slowed/burned together, and the two can never drift apart — a status effect cannot reach further than the damage, or vice versa. Friendly units in the radius are included (the query is `TARGETABLE_ANY`): area weapons friendly-fire, by construction rather than by a flag.

Three things follow, and each has bitten already:

- **Splash damage is NOT a missing feature**, and a search for "splash"/"aoe"/"radius" in `payload.gd` will convince you otherwise — the mechanic is spelled `hit_shape` and lives in a `SU.query_shape_for_entities` call. Every non-hitscan projectile with a hit shape is an area weapon; the Kamikaze's blast has been doing 2.0-radius friendly-fire splash since it was written.
- **It is rejected alongside `hitscan: true`.** A hitscan shot resolves onto the single target it was fired at and never consults its shape, so a blast on one is a number that silently does nothing. The importer hard-errors on the pair, which is where that combination is actually caught.

- **A hitscan emission has no `HitShape` at all**: the sync removes it, so the shape's presence IS the blast (`Payload.has_blast()`) — see [projectiles](../combat/projectiles.md) §The shape's presence is the blast, which also records why this once had to be a `disabled` flag with `hitscan` authoritative. Tests: `tests/test_ProjectileBlast.gd`.
- **An emptied (or `false`) `senses.vision` removes the `VisionRange` node**, and composition never gives such a piece one. The removal convention, and which keys accept an empty value, are in [`tools/spec_import/README.md`](../../../tools/spec_import/README.md) under `kind: Entity`.
- **The sync resets the `HitShape`'s transform to identity.** Several emission scenes scale that node to 0.05, so their shapes would be 20× smaller than the library says; without the reset, one bucket would mean two sizes.

**`movement:` carries the chassis knobs too** — `max_acceleration`, `max_deceleration` (both unbounded by default, so a doc naming neither keeps the old instant-stop behaviour) and `crush_class`, an enum spelled by NAME like every other enum in the schema. These were used by three anarchical docs for a while and SILENTLY IGNORED, the importer syncing only `mode`/`speed`/`turn_rate`; a doc key that reads as authoritative and does nothing is the exact drift this pipeline exists to prevent.

Still scene-only, and each for a reason worth knowing: `DockingBay` pads (spatial by design — capacity IS the pad count), `Interactor.interactions` (an array of sub-resources, not scalars), `Repairs.repair_rate`, `Movement`'s orbit/dive knobs, `Shelter`, `Liberator`/`Liberatable`, `EnergyExtractor.energy_rate`, `DominionGenerator.dominion_rate`, and `Inventory.initial_abilities`. All but the first two are plain scalars and could be added the same way when a piece needs to differ.

**Spec importer** (`tools/spec_import/`, full docs in its README): the gdd docs govern numeric/economy data, and the importer carries them into the project one way. The docs have two writers: a person editing text, and the debug tuning editor's Save ([ux/ui/debug-tuning](../ux/ui/debug-tuning.md)); neither writes a scene. `godot --headless -s res://tools/spec_import/import.gd` (or the "Spec Import" editor toolbar menu) validates every doc (loud, total, no fuzzy matching), syncs scenes via text-level .tscn edits (never `PackedScene.pack()` — it flattens inheritance), creates skeleton scenes for docs without `scene:`, and regenerates `scripts/generated/{entity_ids,status_effect_ids}.gd` + `resources/generated/{technology,tools}.json`. Full mode deletes scene-only collection items; incremental preserves them. Balance analysis derives from the same docs via `tools/balance/gdd_to_balance.py`.

**The doc's FILE NAME is its id** (`power_plant.md` → `power_plant`): snake_case, unique across the whole tree, and there is no `id:` frontmatter key — a doc carrying one is a hard error. Keep names generic and flavor-neutral (`anarchical.md`, not `baladians.md`); renaming a doc re-keys the piece and leaves its old scene behind with a stale `id`. Every spec also carries a user-facing `title` — the piece's ONE display name (`name` is reserved on Godot nodes, so `title`): a faction's syncs to its scene `faction_name`, and a grid piece's is the text on its command-grid button. There is also an optional `editor_description` (copied to the scene root node's Godot-native `editor_description`).

**One stun script, two effects, told apart by a frame mask.** `StunStatusEffect` carries `affects_frames` (a bitmask over `Defense.FrameType`, reusing `Garrison`'s own `FRAME_*` constants so there is one frame/bit mapping in the project) plus `duration_ticks`. `bio_stun` is that script with the BIO bit set; `emp` is the same script with the MECH bit. A host outside the mask is left alone — the effect removes itself in `_on_apply` rather than sitting inert, so `is_active()` never lies about a target being stunned.

The mask lives on the EFFECT, not on the `EffectApplicator`, and deliberately: the applicator `duplicate()`s its templates per recipient, so the effect already IS the per-recipient object, and a second copy of the rule on the applicator could only ever disagree with it. A stun is a HARD stop (`Commandable.is_stunned()` gates all command processing) — "disabled but still mobile" would be a different effect type and does not exist.

**Ownership can change hands two ways, and which one applies is decided by what the target IS.** `Capture` is for STRUCTURES (a neutral building, worked on until `build_progress` completes); `Interaction.Type.HIJACK` is for MECH-frame UNITS (the Anarchists' Hijacker, expended in the act). They are deliberately separate rather than one generalised "take this over": a structure changing owner drags the structure registry, infrastructure accounting and the terrain grid with it — all of which `Commandable._on_commander_changed` gates on the `"structure"` group — while a unit changing owner is a reparent plus a set of RVO avoidance layers. HIJACK's precondition therefore excludes anything with a `Structure` component outright rather than trying to cover both.

Two things a unit handover must do that assigning `commander` does not:

- **Drop the prize's orders first.** It is mid-execution of its previous owner's command queue, and a hijacked tank that kept its old attack order would turn on its new owner the same tick.
- **Expend the actor through `defense.kill()`, never `queue_free()`.** The normal death path owns the teardown — spatial-partition removal, garrison release, production refunds — and skipping it strands stale grid entries. The kamikaze's self-destruct is the other "unit consumed by its own action", and both carry the same accepted cost: the ON_DEATH occurrence fires and the death bark plays, so a scenario counting deaths counts a successful hijack too.

**Known gap:** a hijacked unit stays in its former owner's HUD selection until they reselect — `RTSController` prunes its selection on validity, not on ownership. Nothing could change hands before HIJACK existed, so the case had never arisen. Tests: `tests/test_HijackInteraction.gd`.

`Structure` (`scripts/entities/components/structure.gd`): the node-child that marks an entity as a structure and declares `dimensions: Vector2i` — the footprint in grid cells (doc key `footprint`). `Map.add_structure` reads this to register all occupied cells.

`Repairs` (`scripts/entities/components/repairs.gd`) is one of the two PRESENCE-ONLY components the importer syncs (`Stealth` is the other): its doc key is a bare `repairs: true` rather than a list, because the Repair command asks nothing of the actor but that the node exists. `true` creates it, `false` removes one the scene owns, an omitted key leaves the scene alone. The rate (`Repairs.repair_rate`) is scene-authored and not doc-governed yet — give the key a mapping form when the first unit needs to differ.

---
