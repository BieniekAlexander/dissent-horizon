---
title: Condition visuals
type: system-note
---

# Condition visuals

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Condition visuals (`StatusVisuals`)


**How a unit LOOKS is split by which question the look answers**, and the two halves never
touch each other's channels:

| Half | Written by | Says |
| --- | --- | --- |
| CONSTRUCTION | `Actor._apply_construction_visuals`, off `build_progress_changed` | how REAL this thing is — planned / building / built, paid for or not |
| CONDITION | `StatusVisuals`, every frame | what is happening to it RIGHT NOW — stealth, status effects, rank |

`MeshVisual` carries a channel for each (`set_opacity`/`set_shade` versus
`set_status_opacity`/`set_status_tint`) and multiplies them in `_reapply`
(`effective_opacity()` / `effective_tint()`). One combined channel cannot work: a
half-built barracks can be EMP'd, and a stealthed unit is no less finished for fading, so
an event-driven construction write and a per-frame condition write would overwrite each
other in whichever order they happened to land. **The composed value — not the
construction one — is what decides transparency and the x-ray silhouette**, since either
channel alone dropping below 1.0 makes the material translucent, and a translucent
material writes no stencil for the x-ray pass to test against.

The status setters early-out on an unchanged value. They are written every frame for every
entity in the game, and without that guard each one would rewrite all of its surface
materials each frame to say nothing had changed.

### An effect declares its look; it never draws

`StatusEffect` carries three exports — `host_tint`, `indicator_icon`,
`indicator_blink_hz` — and `StatusVisuals` composes whatever the host's attached effects
declare. Two reasons this is data on the effect rather than code in a subclass:

- **One script, two looks.** `emp.tscn` and `bio_stun.tscn` are both a bare
  `StunStatusEffect` separated only by a frame mask, and an EMP'd machine has to read as
  dead while a gassed soldier does not. Same reasoning as the sanction payloads: a tier is
  authored data, not a subclass.
- **Two effects on one unit compose into one look**, rather than two systems writing the
  same material. The tint is the **per-channel MINIMUM** over active effects, not the
  product — "what colour does this unit's condition draw it" is a single reading of the
  unit, and two effects each halving it would otherwise quarter it.

**The channel is a COLOUR and not a brightness, and freeze is why.** An EMP drains a
machine toward black, but cryo coats its host in protective ice — draining a frozen unit
would say the opposite of what happened to it, so `host_tint` has to be able to say
"colder" rather than only "darker". The cost is that a multiply can never add warmth: an
orange burn tint pushed hard turns this game's cyan-lit models GREEN, so `lazer_burn`
authors barely any tint and lets its flickering flame badge carry the meaning.

Authored today: `emp` (near-black + bolt), `bio_stun` (sickly green + biohazard),
`freeze` (cryo blue + snowflake), `lazer_burn` (flame), `slow` (hourglass, no tint).
`EventGlobalEmp` instantiates `emp.tscn` and `EventFreeze` instantiates `freeze.tscn`
rather than newing the effect up, so no two code paths can construct what is meant to be
one effect; each overrides only `duration_ticks`. **Nothing applies a `SlowStatusEffect`
yet** — `slow.tscn` is the authored template an `EffectApplicator` would point at.

### Floating billboards, and what gates them

Camera-facing `Sprite3D`s created by `StatusVisuals`, in three rows at FIXED heights above
the model — fixed because the top row comes and goes with selection, and a badge that
dropped to fill the gap every time you clicked would read as the unit changing rather than
the selection:

| Row | Shows | Seen by |
| --- | --- | --- |
| veterancy | one/two/three gold chevrons (`veterancy_{1,2,3}.svg`) | everyone |
| status | the current action's badge, flashing ([unit-animation](../unit-animation.md) §Action badges) | everyone |
| status (same row) | one icon per active effect that declares one | everyone |
| status (same row) | the hold-fire badge (`status_hold_fire.svg`) | the owner, selected or not — and only on a piece offered hold fire (armed); an unarmed stealthed piece holds fire with nothing to show for it |
| status (same row) | the unpowered badge (`status_unpowered.svg`): a STRUCTURE whose weapons or abilities have gone dark because its commander's infrastructure is short (`Actor.is_unpowered`). A building that only trains carries none — production slows under strain but does not stop | the owner's side |
| status, on a BLUEPRINT | the awaiting-funds badge (`status_awaiting_funds.svg`): ordered, not paid for | the owner's side |
| capacity pips | garrison seats and charged-ammo rounds | the owner, while selected |

- **A ROW is billboarded as a whole, not icon by icon** (`_face_rows_at_camera`). Every
  `Sprite3D` already faces the camera on its own, which is enough for a single badge and
  wrong for a row: the icons sit at local X offsets and `StatusVisuals` inherits the
  entity's yaw, so the LINE swung round with the unit while each icon on it dutifully kept
  facing front — a four-pip ammo row went end-on the moment the aircraft banked away. The
  node takes its X from the camera's screen-right and keeps Y as WORLD up, so rows stay
  level across the screen while still stacking straight up above the model. That
  decomposition works only because an RTS camera has yaw and pitch but no ROLL, which is
  what makes its right vector horizontal.
- **Height comes from `MeshVisual.model_top_offset()`**, the model's own AABB top measured
  once and cached — so a tall structure and a crouching infantryman both carry their markers
  just clear of themselves. Contrast the HP bar, which predates this and is positioned by
  hand in every single unit scene.
- **A blink means "this is happening to the unit right now"**; 0 Hz is a state you read at a
  glance and must never flicker. It is per-effect (`indicator_blink_hz`), not a property of
  indicators in general.
- **Everything is hidden by `Actor.is_hidden_by_stealth()` or `is_planned`**, except
  the awaiting-funds badge, which is the one thing a blueprint shows: nothing it could be doing
  or suffering applies to a piece not on the map yet. Fog
  already hides an entity wholesale by toggling `visible`, but a STEALTHED enemy is drawn at
  zero ALPHA with `visible` still true — so without this gate a badge or a bolt would float
  in empty air over the unit the fade is hiding. The same call suppresses the HP bar in
  `Actor._process`.
- **`Veterancy` owns no art.** It counts XP and holds a level; `StatusVisuals` reads that
  level. The old numeric `Label3D` is gone, and with it a component that had a node in the
  scene and no way to gate it on any of the above.

### Capacity pips are a readout, so they are gated on selection

One pip per SLOT, solid for a slot that is filled and hollow for one that is not — green
circles for `Garrison` seats, yellow bullets for charged-ammo rounds. One pair of tokens
per kind rather than a number: a count has to be read, and a row of pips is taken in at a
glance, which is the whole reason to draw it in the world rather than in the info panel.

- **Garrison pips count OCCUPANCY, not heads** (`Garrison.capacity` / `occupied_size()`),
  so a Collective riding a truck fills two of them — the honest picture of what the
  transport has left.
- **Ammo pips are summed across the loadout's charged weapons**
  (`Loadout.charged_ammo()` / `charged_clip_size()`), because the rearm mechanic already
  treats the loadout as one thing: an aircraft flies home when EVERY charged weapon is dry
  and sits on the pad until ALL of them are full. They are also the only explanation the
  player gets for an aircraft breaking off mid-fight to fly home.
- **Shown only while SELECTED, and only on the local player's own units**
  (`StatusVisuals._shows_capacity`). Both are detail you ask for about one unit rather
  than something to track across the field, and drawing an enemy transport's remaining
  seats would hand over exactly the scouting information a garrison exists to hide.
- **Rows wrap at `PIPS_PER_ROW` (8)**, filling from the top down so adding a round never
  shuffles the pips already drawn. The Clipper's 12-round clip is the piece this exists
  for; one line of 12 is two tank-lengths wide.

> **PLANNED — ALLIES.** The rule wants to be "yours or an ally's". Alliances are planned
> ([target-acquisition](../../combat/target-acquisition.md) §Alliances) and not built;
> `_shows_capacity` is the single place that decides, so widening it is a one-line change
> when they land.

### What this replaced

All of it used to live inline in `Actor._process`, writing `Sprite.modulate` — a
single channel shared by the team tint, the construction fade and the stealth pulse, which
is why that block had to rewrite all three every frame to stop them clobbering one another.
The billboard-sprite era is over for units and structures (`MeshVisual` is on
`unit.tscn` and `abstract_structure.tscn`), so that code, the `Sprite` fallback in
`Entity._apply_team_tint`, the `flip_h`/`hframes` animation hack and the `TeamTint`
editor-preview component were all removed.

**`TeamTint` has no replacement yet.** It was an editor-only `@tool` child that previewed a
scene-placed entity's team colour by writing `Sprite.modulate`, and it had been silently
doing nothing since the mesh migration. Porting it to `MeshVisual` means writing surface
override materials from the editor, which Godot serialises into the scene file — so the
preview would BAKE a team tint into the saved `.tscn`. Left out rather than shipped with
that hazard.

Tests: `tests/test_StatusVisuals.gd`. The visual check is `tools/status_visuals_preview.gd`
— one unit per state, rendered offscreen (see §Seeing the HUD without a screen), which is
how the chevron sizes and the blink were actually confirmed.

---
