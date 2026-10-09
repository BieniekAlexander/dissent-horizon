---
title: Hud layout
type: system-note
---

# Hud layout

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The cursor is game art, so every shape the HUD asks for needs art

A `Control` may mark itself clickable with `mouse_default_cursor_shape` — but only with a shape
`RTSController` has registered an image for. Today that is exactly one,
`CURSOR_POINTING_HAND`. A shape with no art behind it makes the OS draw its own pointer for as
long as the mouse is over that control.

Full rule, the delivery mechanism behind it, and the state table:
**[cursor.md](cursor.md)**.

## The HUD is split persistent / selection-owned


One rule decides where a HUD element lives: **it is PERSISTENT iff it answers a question you can ask with nothing selected.** `RTSController._update_selection_owned_panels` applies it every frame.

The command grid itself splits again, into two CARDS — see §The command card's two families.

| Persistent | Selection-owned (hidden with an empty selection) | Nothing-selected only |
| --- | --- | --- |
| `DominionBar`, `EnergyBar`, `InfrastructureBar`, minimap, objectives | `InfoSection` (portrait/stats/cards), `CommandsSection` (the command grid) | `SelectorPanel`, the global `ProductionRail` |

`InfoSection` (and `ControlGroups` sitting on it) is shorter than the minimap and command card
beside it — 80% of their height as a starting point — so the bottom edge dips in the middle and
frames the centre of the screen rather than walling it off.

The third column is the selection-owned panels' complement: each takes the slot of a panel that
is hidden while nothing is selected, so the two alternate in one rect rather than stacking.

The selection-owned panels are hidden WHOLESALE, backgrounds included — `InfoSection/Background` and `CommandsSection/CommandsBorder` are fixed rectangles spanning the bottom, so hiding only their contents would leave an empty bar rather than clear screen. `pointer_over_blocking_ui` already gates on `is_visible_in_tree()`, so hiding also stops them swallowing world clicks over what is now empty terrain.

`SelectorPanel` is anchored to `CommandsSection`'s own rect (bottom-left), not a child of it, precisely so the two can alternate — `not has_selection` against `has_selection` — without either taking the other down. See [economy-bars.md](economy-bars.md) §Why the command card moved.

- **Production** has a section of its own: §Production, below.
- **The three persistent resource bars** (`DominionBar` top-left, `EnergyBar` and
  `InfrastructureBar` stacked — Energy above Infrastructure — above the command card) are
  Energy/Infrastructure/Dominion drawn as non-text gauges: a flat fill colour chosen from
  where the pool sits on a ramp, not text digits. They replaced `EconomyStack`, the panel
  that used to show the same three pools as text. Full write-up, including why
  `SelectorPanel` moving to the command card's rect needed no node to actually relocate:
  **[economy-bars.md](economy-bars.md)**.
- **The passive-ability row** (`PassiveAbilityRow`, along the bottom of `InfoSection`) is the
  only place a PASSIVE ability appears at all. A passive is never fired — no command, no
  charges, no cell on any command card — so before this row the player's only evidence of the
  Anarchists' Scavenge bounty was the dominion arriving. It is the info panel rather than the
  command grid because the grid is a set of things you can PRESS, and a permanently dark
  button there would read as broken; the info panel is where a selection describes itself,
  which is exactly what a passive is. SINGLE SELECTION ONLY, like every other row here (see
  [condition-cards](condition-cards.md) §A multi-selection). Two sources feed it — a passive
  a selected PIECE grants through its own `Abilities` pool, and a passive the COMMANDER'S
  faction offers through a sanction-grid cell (Scavenge, which belongs to the whole army). The second is what makes
  greying mean something: a passive the faction offers is drawn whether or not it has been
  bought, so the player learns it exists, and it borrows
  `CommandButtonState.TINT_LOCKED` so the "unpurchased" idiom cannot drift from the one on an
  ability's own button. A faction with no route to it draws nothing at all — absent means
  "not for you", grey means "work toward it". Tests: `tests/test_PassiveAbilityCards.gd`.
- **The info rows** (the `InfoWidgetRow` block filling the Summary column of `InfoSection`,
  `StatusEffectRow` above the passives) describe ONE selected piece. Both are single-selection
  only: a mixed group has no single answer to "how fast is it", and a row that averaged one
  would describe a unit that is not on the field.
  - **The widget block is a fixed grid of slots, sized for the piece that has everything.**
    Name, then hit points, each take a full row; every other widget (weapon, speed, sight,
    hold, production) has a slot in a two-column grid beneath. The rows share the column's
    height, so a piece with every property fills the column — and a piece without one leaves
    that slot EMPTY rather than letting a neighbour grow into it, so each figure is in the
    same place on every piece. The block is where a single selection's occupancy and
    production status are read; the Summary column's text label repeats none of it.
  - **A widget that does not apply is not drawn.** A structure has no movement speed and a
    Servant has no weapon; a card reading "movement: —" teaches the player that the block is
    full of blanks rather than that this piece is stationary. What is on screen is what the
    piece has.
  - **The row is the shallow tier and the tooltip is the deep one**, the same two-tier idiom
    as everything else on `ui_verbose`. The face carries the ONE figure you glance at
    mid-fight; the tooltip is the sentence; the verbose tooltip explains what the property
    MEANS at all (what armour and frame do, what the crush class is) — game-wide copy, so it
    is written once in `InfoWidgetRow` rather than per piece.
  - **The vision widget has no tooltip on purpose**: both its figures are already on the
    face, and what a player wants from them is WHERE they reach — the hover reveal, not more
    words. See [range-reveal](range-reveal.md).
  - **A status effect's copy lives in its SCENE**, beside `host_tint` and `indicator_icon`
    and for the same reason: `emp` and `bio_stun` are one script separated by a frame mask,
    and "its electronics are dead" is not "it is choking". The `kind: StatusEffect` doc
    stays registration-only.
- **The resource card says when a pool needs acting on**, by changing colour: energy pulses
  yellow past `ENERGY_SURPLUS_THRESHOLD`, dominion pulses red once it covers the dearest
  sanction the grid will currently sell (`SanctionGrid.dearest_available_cost` — the moment
  banking more stops buying anything), and infrastructure warns steady orange past 80% of
  capacity and pulses once upkeep exceeds it. A STUB scoped to this one panel; what is
  settled is which states are worth saying and what each looks like, so the reach can grow
  without the vocabulary being re-decided. Tests: `tests/test_ResourcePressure.gd`.
- **Producer affinity** runs in BOTH directions, and together they recover what a per-structure queue used to show for free — as a live query over the global queue rather than a second data structure. The PRODUCTION page's Details pane shows only the purchases that could land on the selected producers (§Production, answering "what will this building make?"); hovering a queued chip in either copy rings the structures that could build it (`ProducerAffinityIndicator`, answering "where will this purchase go?"). The ring is drawn in `RallyIndicator`'s cyan deliberately — both mark where production is headed, and the shapes are what separate them. `ScenarioHighlight` is the same recipe and is NOT reused: every live one joins the `scenario_highlight` group, which the minimap reads, so borrowing it would paint HUD hover feedback on the minimap as a mission objective.
- **A selected producer names its share of the queue** — "Building Recruit · 2 more can land here" (`InfoView._production_line`, off `ProductionQueue.pending_count_for`). "One structure builds one unit at a time" is a surprising rule for anyone arriving from another RTS, and that sentence is what separates "this building is idle" from "this building is working through a line". The wording is "can land here" rather than "queued here" on purpose: the queue is commander-global, so those purchases are ELIGIBLE at this structure rather than owned by it, and another producer may take them first.
- **`SelectorPanel`** draws the three families as buttons that PREVIEW the matrix cell the modifiers currently put you in, count included, re-rendering every frame. The selector matrix was otherwise a 2×2 documented nowhere on screen; this makes it discoverable by holding a key. Greying follows the CURRENT cell rather than idleness alone, and a greyed button does nothing when pressed — it never widens its own scope to find something.

Key input actions (defined in `project.godot`):
- `isometric_camera_select` (LMB), `move` (RMB)
- **Zoom** is held between `MIN_ZOOM_IN_FACTOR` (0.5×) and `MAX_ZOOM_OUT_FACTOR` (2×) of the `size` the camera was authored with — both captured in `_ready`, so each camera keeps its own framing as the baseline rather than sharing a fixed world size. Applied to the resulting `size` in `_clamp_zoom` rather than inside the zoom callables, so it holds however the zoom was driven
- **Pan limits** (`_clamp_to_map_bounds`, run last in `_process` so one check catches drag, arrow keys, edge pan and any outside `center_on`) keep the view inside `Map.play_area()` grown by `EDGE_OVERSCROLL_RATIO`. Things worth knowing:
  - It bounds against the **authored play rectangle**, not the heightmap. `Map.play_area()` prefers `TerrainData.play_half_extents()` — a rectangle in the screen-aligned (s, t) frame, which is a 45°-rotated rectangle in world XZ — and falls back to the heightmap rect for maps that declare no play bounds. The heightmap's four corners lie outside the rotated rectangle and are dead area; bounding to the heightmap let the camera wander into them.
  - `PlayArea` (`scripts/maps/play_area.gd`) carries a centre, two perpendicular unit axes and per-axis half-extents, because a `Rect2` can only hold the rotated rectangle's bounding box — which is exactly the too-big shape being avoided. The clamp runs in `to_local` space, where the rectangle is just ±half and each axis clamps independently. `play_size`'s two axes ARE independent, so a play area may be oblong, not only square.
  - The view is measured **along the play area's axes** (`visible_half_extents_in`), not in world XZ. At the default camera the view is a diamond in world XZ but axis-aligned in the play frame, so the world-XZ bounding box is ~√2 too large; on s1 the same view measures (11, 13) in the play frame versus 17 in world XZ. Rotating the camera tilts the view relative to that frame again, and it then reports the box around it — bounding slightly early, the conservative direction.
  - It bounds where the camera **looks** (`ground_focus()`, the inverse of `center_on`), not where it is. At a 45° pitch the body sits well behind and above the view, so bounding the position would let the view drift off by a zoom-dependent offset.
  - The overscroll exists **because the HUD covers the bottom of the screen**. Stopped exactly at the map edge, the southern strip of terrain would sit permanently behind the command panels with no way to bring it clear. Expressed as a fraction of the view rather than a world distance so it scales with zoom — at the authored framing it works out to ~6 world units, a little more than the ~18% of screen height the HUD occupies.
  - `visible_ground_half_extents()` measures by projecting the four screen corners onto the ground rather than deriving from `size` and pitch, so it survives zoom, yaw, aspect changes and either projection. It yields an axis-aligned box around a view that is really a rotated quad (the camera looks down the grid's diagonal), which bounds slightly early — the conservative direction.
  - When the view covers a whole axis of the play area (zoomed out on a small map), that axis settles at the **centre** — there is nowhere meaningful to pan along it. Per-axis, so a long thin map can still pan along its long axis while its short one is centred.
- **Edge panning** has no action: `RTSCamera3D._apply_edge_pan` (called from `_process`, since a held cursor produces no events) slides the view when the cursor sits within `EDGE_PAN_MARGIN_PX` of a screen edge. Which BANDS the cursor is in decides the heading, not where it sits relative to screen centre: a vertical edge pans horizontally, a horizontal edge pans vertically, a corner pans diagonally — normalized, so a corner isn't √2 faster than an edge. It is suppressed while drag-panning, while the window is unfocused, while the cursor is outside the window (coordinates keep going past the edge, which would read as a permanent pan), and — via the shared `RTSController.pointer_over_blocking_ui` — while the cursor is over HUD, because the minimap and command panels sit *on* the bottom edge
- **The grid is POSITIONALLY keyed, and the ACTION is the CELL**: cell (x, y) answers to `command_cell_x_y`, bound by default to the key at that position in `QWERTY / ASDFGH / ZXCVBN`. Pressing it runs whatever that cell is currently DRAWING (`RTSController.visible_command_in_cell`) — see §The command card's two families for what follows from that. There is no `command_attack_move` input action any more; that string is a command NAME, and `CommandGrid.action_for_command` maps it to the cell it occupies
- `card_toggle_family` (Tab) — flip between the ACTIVE and PRODUCTION cards. Deliberately NOT `command_*`-prefixed (the dispatcher routes that whole prefix into the grid), same rule as `modifier_narrow` / `modifier_broaden`
- `show_help` (F4) — moved off H when the grid widened to six columns and claimed it for cell (5,1). A grid cell has the stronger claim on a letter than a held overlay, and F4 sits beside the F1–F3 selectors
- `command_additive` (Shift) — queue the next command instead of replacing
- `command_additive` (Shift) also means FRONT OF THE QUEUE when what is being issued is a PURCHASE. Read there by polling (`RTSController._purchase_to_front`) rather than off the `next_command_additive` latch: a purchase is usually issued by CLICKING a HUD button, and the modifier keypress before that click goes to the focused Control first, so a latch fed from `_unhandled_input` can miss it.
- **Standing orders have no key at all.** Right-click on the grid button that would otherwise buy the thing once (`RTSController._on_control_button_alternate_pressed`, wired in `ButtonSpec.create_button_from_spec` off the `gui_input` SIGNAL — overriding `_gui_input` would replace BaseButton's own press handling). This replaced the `purchase_fallback` (Alt) modifier, whose job was the same and which spent a system modifier on it.
- `command_select_army` / `command_select_builder` / `command_select_production` (F1 / F2 / F3) — the three selectors, plus `modifier_narrow` (Alt) and `modifier_broaden` (Ctrl) which broaden them. See §The selector matrix.
- `show_debug_info` (`;`) — toggles the debug view, only in a scenario with `debug_allowed`. See [debug-mode](debug-mode.md).


## Production

One component, `ProductionRail`, draws production in two places, and **never both at once**:

| Where | When | What |
|---|---|---|
| a strip at the bottom centre of `InfoSection`'s rect | NOTHING is selected | the commander's whole queue |
| `InfoSection`'s Details pane | the command card is on its PRODUCTION page | only the current producer context's producers, and the purchases that could land on them |

With something selected and the card on any other page, production appears nowhere — not in
Details, not on screen. The centre of the screen is either what you are holding or what you have
committed to.

**This supersedes a persistent rail on the left edge** (2026-10-04), which drew the global
queue in every selection state on the argument that "what have I committed to" is asked while
doing something else. The accepted cost: while holding an army, the queue is out of sight. A
player asks about it by deselecting, or — for one building's share — by selecting the building,
which opens on its PRODUCTION page. Selecting producers used to DIM the chips that could not land
on them; the scoped copy replaces the dimming with a filter.

**The scope** is `RTSController.production_detail_scope`: the selected producers of the chosen
producer context (every selected producer when the context row is not drawn), the local
player's only. A purchase is in scope when one of its `candidate_producers` is (a BUILD never
is). Off the PRODUCTION page the scope is empty, and an empty scope is what hides the Details
copy; the garrison-occupant cards that otherwise share the pane are hidden while it shows.

**The global copy is a compact strip**, sized to its cards and pinned to the bottom centre of
the info panel's rect (`ProductionSlot`, which never blocks a click itself), with the head and
the chips behind it on one row. With nothing selected the player is looking at the world, so
the strip takes one card's height rather than the panel's. The scoped copy fills the Details
pane and wraps.

**Three columns**, left to right, because both places are wide and short:

- **producing** — one training card per busy producer (a producer builds one thing at a time,
  so its job IS what it is producing), captioned `n / m` when several producers are scoped.
  A unit in training has left the queue, so this is the only place it can be reached.
- **queued** — the one-off tier. Four rules keep it small: only the HEAD carries words
  (head-of-line blocking means the head's status explains the whole queue), blocker glyphs
  appear only when a purchase is actually stuck, runs of identical ADJACENT purchases collapse
  to one chip badged ×N, and the tier is capped with a `+N` overflow chip.
- **standing** — the ring, in authored order, dimmed, with the next-up template at full
  strength and marked `▸`.

Chips run left to right in dispatch order within a column, and the tier boundary is the column
boundary, so reading order is never ambiguous. The global copy drops an empty column, and hides
outright when all three are empty — its absence says nothing is on order. The scoped copy keeps
every column and says "none": the player opened the page to ask. A column's × cancels what that
column SHOWS — the whole tier globally, only the scoped share in Details. Chips and job cards are
`CommandableCard`s, so a queued purchase, a training job and a live unit stay one visual family.

TODO: the global copy shows every busy producer's job in its producing column, which the
request asked for only in Details; kept because it is the same component and reads as
"global production", but drop it if the column is noise there.

Tests: `tests/test_ProductionDetails.gd`; the scope rule in `tests/test_ProducerContextRow.gd`.
Rendered by `tools/hud_panels_preview.tscn` with `--producer` (Details) or `--deselect` (global).

## The minimap

The minimap is drawn screen-aligned, as the camera frames the play area, in two layers:

- **The map layer** (`MinimapLayer`) — one colour per terrain cell: sand ground; impassable
  ground (the terrain grid's steep and blocked cells — ridges, cliffs, obstacle regions) a dark
  earth, so a barrier shows; ponds with a darker rim, shaded from pale (poor) to deep blue
  (rich) by full charge per cell, their deep (impassable) water darkened within that shade; extraction
  sites yellow; shelters green; neutral buildings grey; and each start area tinted with its
  slot's team colour. It is seen through the fog — unchanged in sight, darkened when explored,
  black unseen — and rebuilt only when the terrain grid's cells change, since fixtures come and
  go only through the grid.
- **Actors** on top, in their owner's colour, as before. A NEUTRAL fixture is left to the map
  layer; one a player owns is drawn as theirs.

Neutral fixtures are classed by facet (an `ExtractionSite`, a `Shelter` component, else a
building), never by piece id.

**The debug view (`show_debug_info`) reveals the whole minimap too** — every cell in
sight and every actor drawn — matching what it does to the world.

TODO: the visual details are provisional — they were carried over unchanged from the map
generator's former review images, and want revisiting (symbol shapes, the palette against the
team colours, whether start tints should outlive the opening).

## The look-only HUD

A spectator session — a replay included, which is one (recording-and-replay.md) — is watched
through the player's own HUD scene, `scenes/interface/player_hud.tscn` (the `Controller`
subtree `player.tscn` instances), built look-only by `Scenario._create_look_only_hud` with
`RTSController.is_look_only` set.

- **It drives no commander** (`_commander()` is null), so it gives no orders: no path that
  builds one is reached, no grid key is dispatched, and right-clicks do nothing.
- **What stays where it is:** the unit summary, the unit info panel and the minimap, at their
  match positions. Selection works as it does on the player's own pieces — click, additive,
  box, double-click for the type — for every piece the watcher can see; a double-click takes
  that type from the clicked piece's commander only.
- **The command grid's slot holds the `SpectatorPanel`**: a button per view (No fog, then each
  commander with a Fog — "Player N" for a human slot, "Bot N" otherwise) and, in a replay,
  Pause / Slower / Faster, which are the `ReplayViewer`'s own methods, so its keys and these
  buttons are one control.
- **What goes:** the resource bars, the production rail, the selectors, the sanction bar and the
  debug panels — each shows or spends a commander's means, and a debug piece would change the
  match. The per-commander resource labels stay in the spectator's top-left layer.

## Hiding the HUD

A **Hide HUD** button sits just above the minimap's left edge, on every HUD that has a minimap —
a match's and a look-only one alike (`RTSController._build_hud_toggle`). Pressing it hides the
HUD's layer, which hides every panel in it, and every other CanvasLayer in
`RTSController.HUD_LAYER_GROUP` (the scenario timer, the spectator's labels, the replay banner).
A dialog and the pause menu are not HUD and stay up. Hidden, the one button left is **Show
HUD**, on the bottom edge of the screen at the same horizontal position.

- **Hiding the layer, not the panels:** a panel under a hidden CanvasLayer reads
  `is_visible_in_tree()` false, so it stops blocking world clicks with no per-panel state, and
  the selection-owned panels can keep setting their own visibility underneath.
- **What must outlive it lives on a nested layer** (`HudOverlay`): a CanvasLayer's children are
  hidden with it, but a nested CanvasLayer is not. The button and the drag-selection box are
  there, so selecting still draws its box with the HUD put away.
- The help and debug hints that stack above the minimap (`help_overlay.tscn`) sit one button
  higher to make room.

## A Control built in code is anchored AFTER it is added, never before

`set_anchors_preset(PRESET_FULL_RECT, true)` resolves against the parent's CURRENT size, and a
node that is not in the tree yet has a parent of size zero — so calling it before `add_child`
bakes in a zero-size box that never grows, and the control is present, correct, and invisible.
The order is: configure, `add_child`, THEN anchor and zero the four offsets. This is what made
the pending-selection border (`CommandableCard._pending_border`) fail to appear while every
assertion about the selection passed.

Two neighbours of the same bug, both hit on that one control: a `ReferenceRect` draws NOTHING
at runtime unless `editor_only` is cleared, and any decoration laid over a clickable card wants
`MOUSE_FILTER_IGNORE` or it eats the click it is decorating.

**None of the three is visible to a test that asks the mechanism.** See
[control-matrices](control-matrices.md) §Selecting a unit that does not exist yet for the
verification recipe — crop the widget's own `get_global_rect()` out of a rendered frame.
