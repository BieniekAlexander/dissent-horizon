# Interface idioms

What the control scheme currently *commits to*, written as rules rather than as a keymap, so
the long-term plan can be argued in terms of idioms instead of individual bindings. Every rule
names where it lives in code. The last two sections are the interesting ones for planning: the
constraints that are not negotiable, and the tensions that are still open.

This is a design note, not an importable spec — it carries no `kind` frontmatter and the spec
importer ignores it.

---

## The framing: what a modifier is *for*

In the RTS canon, modifier keys almost universally mean **quantity and sequencing**:

| Convention | Meaning | Examples |
| --- | --- | --- |
| Shift + order | append to the queue | ~every RTS since Warcraft II |
| Shift / Ctrl + buy | ×5, ×10 | StarCraft, Age of Empires, BAR |
| Alt / Ctrl + queue click | insert at front, cancel from the back | Beyond All Reason, Zero-K |

**This project spends its modifiers on two axes the canon doesn't use: ASSIGNMENT — how many
actors an order goes to — and how COMMITTED it is.** Only Shift keeps the conventional meaning.

| Key                                | On a COMMAND                                                       | On a SELECTOR             | Axis                      |
| ---------------------------------- | ------------------------------------------------------------------ | ------------------------- | ------------------------- |
| Shift (`command_additive`)         | append instead of replace — and, on a PURCHASE, front of the queue | add to the selection      | sequencing — conventional |
| Alt (`modifier_narrow`)            | assign to ONE actor                                                | restrict to IDLE members  | restriction               |
| Ctrl (`modifier_broaden`)          | assign to ALL selected actors                                      | take ALL members, not one | quantity                  |
| Backspace (`purchase_requisition`) | toggle: unaffordable purchases queue instead of being refused      | —                         | **commitment**            |

The two modifiers now agree in DIRECTION across both key spaces: `modifier_broaden` means
"take all", `modifier_narrow` means "restrict". *What* is restricted differs — one actor
versus idle-only members — but that it restricts never does, which is what lets a player
predict either space from the other. This retires the recorded inconsistency below.

Shift's second meaning IS the conventional insert-at-front idiom, applied where this project's
queue lives (the commander's, not a structure's). The ×5 idiom is deliberately **unspent** —
quantity is handled by clicking again, one click buying one unit.

Narrow and broaden are **absolute, not relative**: Alt always yields one actor and Ctrl always
yields all, whichever way a command's own default falls, so a modifier applied to a command
already at that extreme is a no-op. Defaults vary per command — Move and Build are both broad,
Train has no assignment meaning at all — and a single flip-the-default modifier would require the
player to know each default before predicting the outcome.

Standing (repeating) purchases cost no key at all: they are the RIGHT-CLICK on the grid button
that would otherwise buy the thing once. Grid buttons had an unspent right-click, and "buy this,
but keep buying it" reads as a variant of the same action. That is what freed Alt, which
`purchase_fallback` used to hold.

---

## The idioms

### I. Hold to reveal information; toggle to change state

Anything that only *shows* you something is held, and springs back on release. Anything that
changes what the game will *do* is a toggle with a visible indicator.

- Held: `ui_verbose` (/) deep tooltips, `show_help` (F4) overlay.
- Toggled: `purchase_requisition` (Backspace), whose indicator IS its toggle button on the
  economy stack. `show_debug_info` (`;`) toggles the debug view — a developer surface, gated
  on `Scenario.debug_allowed`, whose indicator is the view itself.

**A MODE is not a PREFERENCE, and only a mode earns an indicator.** A mode changes what the
game will do this match, so forgetting you are in one loses matches — requisition mode is one.
A preference changes how the interface always behaves and belongs in a settings screen with no
in-match tell: `RTSController.CameraFollow`, which decides whether a selector may move the
camera onto an off-screen pick, is the first of these. The project has no settings system yet
(no `ConfigFile`, nothing under `user://`), so that preference is currently a runtime property
waiting for one.

The stated reason (`help_overlay.gd`) is that hold-to-reveal has **no state to get stuck in** —
release and the screen is clear, so a player can't lose a match behind a panel they forgot was
open. The corollary is that a toggle must earn its indicator: requisition mode has a banner
precisely because you can forget you're in it.

### II. Every information surface has exactly two tiers, on one key

One key (`ui_verbose`, `/`) deepens *everything*: HUD button tooltips swap tier mid-hover
(`VerboseTooltipButton` renders its own popup rather than Godot's so it can re-render live), the
info panel swaps a unit's `description` for its `verbose`, and the help overlay expands.

Only the shallow tier is mandatory, and that is **enforced at runtime**: a button with no simple
tooltip pushes an error naming itself and displays `MISSING_TOOLTIP` ("TODO fill out this
tooltip"). An undescribed control is loud in the error log and visibly unfinished in game, never
silently featureless. Same treatment for `Actor.description` / `verbose`.

### III. Player-facing copy never names a key

Copy writes `{{ action_name }}`; `InputPrompt` substitutes the live binding at *render* time.
Rebinding re-words every tooltip, dialog and banner with no content edit — and it is already
load-bearing per-platform (macOS reports Alt as "Option"). A placeholder naming an action that
resolves to nothing fails `test_ControlBinding`, so typos surface rather than shipping literal
braces. A placeholder may name an InputMap action OR a grid command — the latter resolves
through the cell that command occupies, which is what keeps copy naming verbs now that grid
hotkeys are positional (idiom IX).

Deliberately a straight name-for-name substitution adding no markup: styling is the author's
(`[b]{{ move }}[/b]`).

### IV. Right-click is context-resolved; sub-modes are *armed*, not entered

There is no persistent verb mode. A right-click resolves against the actor and whatever is under
the cursor (`RTSController._resolve_command_class`): enemy → Attack, extraction site → Collect, ground →
Move. A verb key arms `pending_command_name` for exactly one resolution, and issuing (or
re-selecting) clears it.

The one *contextual* mode is `current_context()`: arming Build (B) swaps the grid from
`ACT | TRAIN` to `BUILD` so the structure list can be drilled into, across all three rows of
the ACTIVE card.

### V. Selectors are three keys and two modifiers, off the letters entirely

Three families on F1 / F2 / F3 — army, builder, production. **Two axes, one per modifier, both
absolute**, and they compose:

| | cycle ONE (default) | take ALL (`modifier_broaden`) |
| --- | --- | --- |
| any member (default) | cycle every one you own | every one you own |
| idle only (`modifier_narrow`) | cycle the idle ones | every idle one you own |

Shift adds to the selection on every cell.

**Every selector searches the whole map.** Scope used to be a third axis (on screen / global)
and was dropped, because the on-screen half already has a gesture: a box drag resolves
wherever it ends, HUD included, so "select what I can see" is a drag. Dropping it is what
made the budget close — three axes do not fit in the three keyboard-only modifiers, and two
do.

The unmodified cycle is least-recently-selected over ANY member, deliberately not idle-first.
Idle precedence would be absolute, so the cycle would never leave the idle set while one
member was idle — making the unmodified press identical to `modifier_narrow` exactly when
that modifier would have mattered. Two cells collapsing into one is the same failure the
scope split had. The filter belongs to the modifier; the order belongs to the cycler.

That also removes any need for per-family defaults, which is what used to force the
absolute-versus-relative question here.

This REPLACED "one key can mean two things; the unit command wins" — A/S/D/E/W each carried a
verb and a selector, arbitrated by a precedence rule that was invisible to the player. Moving
selectors off the alphabetical block means the collision cannot occur, so the rule was deleted
rather than refined.

*(Superseded.)* Alt used to broaden here — it meant "reach past the screen edge" — while
narrowing on the command side, and that inconsistency was recorded rather than fixed. Dropping
the scope axis freed Alt to mean RESTRICT in both spaces, so the two now agree in direction and
the exception is gone. Ctrl was always consistent: "take all", whether of actors or of members.

### VI. Selection is spatial and forgiving; the HUD is not a wall

- A **drag resolves wherever it ends, the HUD included** — units behind the command panels are
  under the camera, merely hidden, so a box dragged down over the HUD takes them.
- A **click over the HUD resolves nothing** — that press belongs to the panel, and letting it
  through would clear the world selection on the button-up of every info card.
- Drags are driven per-frame from the live cursor, not from motion events, because HUD Controls
  eat motion and the box used to freeze at the panel's edge.
- Click-vs-drag compares slop **per axis** (a tall narrow drag is a drag, not a click).

### VII. Feedback lands *before* commitment, and every frame

The cursor and the error line are recomputed each frame from the current selection's
preconditions — so a build's validity, an unaffordable order, and a missing prerequisite are all
visible while aiming, not reported after clicking.

Tool buttons carry the same information in four states, distinguishing failures whose remedies
differ: available / **locked** (missing a prerequisite structure — needs a building) /
**requisitionable** (unaffordable, clicking queues it) / **unaffordable** (unaffordable, clicking
is refused).

The same principle in the world: construction reads as two independent channels — *opacity* for
where a structure is in its lifecycle (planned 0.2 / constructing 0.5 / built 1.0) and *shade*
for whether it has been paid for (an unfunded blueprint draws darker).

### VIII. Purchases are commander-global, not per-structure

One train click buys **one** unit and the commander's queue sends it to whichever selected
producer is free soonest — not one unit per selected structure. A build order is one purchase and
one blueprint however many builders were selected, and Build is the single command type excluded
from the per-unit destination spread, because a build has one destination by definition.

### IX. The command grid is positional, and it holds two cards

Every button is a `ControlBinding` at a fixed `grid_position` in a **6x3** grid, in one or
more of `ACT | TRAIN | BUILD`. Several bindings may name the same cell as *alternatives*; at
most one is ever visible. Verb labels/tooltips are authored in `command_grid.gd`; build and
train button text and both tooltip tiers are **synthesized from the piece's gdd doc**, so
renaming or rebalancing a piece re-labels its button with no code edit.

**Hotkeys name a CELL, not a command.** Cell (x, y) answers to the action `command_cell_x_y`,
bound by default to the key at that position in `QWERTY / ASDFGH / ZXCVBN`, and pressing it
runs whatever that cell is currently drawing. Muscle memory attaches to the position, the key
and the button can never disagree, and a rebinding screen has eighteen things to rewrite
rather than one per command. A command therefore has no key of its own — `InputPrompt`
resolves `{{ command_attack_move }}` through the cell that command occupies, so copy goes on
naming commands and re-words itself if a button moves.

**The grid holds two CARDS and draws one** (`ControlBinding.CommandFamily`, toggled with
`card_toggle_family`):

| | row 0 | row 1 | row 2 |
| --- | --- | --- | --- |
| **ACTIVE** | abilities | the generic verbs | abilities |
| **PRODUCTION** | production contexts *(reserved, unbuilt)* | training | upgrades *(none yet)* |

The axis is the **command family, not the entity kind**, and that is the load-bearing
choice. A structure that both shoots and trains (a Warcraft-III ancient) offers commands in
both families and the toggle reaches each in turn; classifying by unit-vs-structure would
leave one of the two with nowhere to be drawn. It also means the rule needs no special case
for a mixed selection: ACTIVE is the resting state, because a group picked up mid-fight is
picked up to be *ordered*.

Consequences worth stating:

- **A card the selection cannot fill is never shown.** The toggle no-ops, and the card
  settles itself whenever the selection changes — so it can be hit blind.
- **A hotkey is gated by the card on show.** Pressing the training row's keys while ACTIVE
  is up does nothing; the HUD is the statement of what is available, and a key that outran
  it would be a rule with no way to learn it. (An opt-in "fall through to the other card"
  is plausible later; it is not the default.)
- **Build stays on the ACTIVE card**, though placing a structure is production in the
  economic sense: it is an order given to a UNIT, mid-fight, beside that unit's other
  orders. Its structure list drills into all three rows of that card. Giving builders their
  own Build card is a live option; it is not taken.
- Rows 0 and 2 of the ACTIVE card are one pool ("abilities") rather than two distinct
  meanings — an acknowledged gap, to be split once there are enough unit abilities to say
  how.

**Structure buttons are laid out by ROLE, the same cell in every faction** — command centre
always (3,0), barracks always (0,1), air field always (2,1) — so the position carries over
when a player changes side. Train buttons take column *n* of row 1 from their position in
their producer's `trains:` list.

Two buttons may share a cell when four things can separate them: different cards, different
contexts, different factions, or **disjoint actors** — no one selection can offer both. That
last one is what fits every faction's training row into six columns, and is derived from the
docs rather than hand-maintained (`ControlBinding.grid_collisions`).

---

## Current bindings

| Action | Binding | Notes |
| --- | --- | --- |
| `isometric_camera_select` | LMB | select / box-drag |
| `move` | RMB, M | the context-resolved order |
| `isometric_camera_drag` | MMB | pan |
| `isometric_camera_zoom_in/out` | Wheel, `=` / `-` | clamped 0.5×–2× of authored framing |
| `isometric_camera_left/right/up/down` | Arrows | edge-panning has **no action** — cursor proximity |
| `isometric_camera_rotate_left/right` | *(unbound)* | implemented, no key |
| `command_additive` | Shift | append instead of replace; front of the queue for a purchase |
| `modifier_narrow` | Alt (macOS: Command) | one actor; past the screen edge on a selector |
| `modifier_broaden` | Ctrl (macOS: Option) | all actors; all rather than one idle on a selector |
| `purchase_requisition` | Backspace | toggle requisition mode |
| `ui_verbose` | `/` | hold for the deep tier |
| `show_help` | F4 | hold for the overlay |
| `show_debug_info` | `;` | toggle the debug view (scenarios with `debug_allowed`) |
| `show_pause_menu` | Escape | |
| `card_toggle_family` | Tab | flip between the ACTIVE and PRODUCTION cards |
| `command_cell_x_y` (18) | `QWERTY / ASDFGH / ZXCVBN` | one per grid cell; runs whatever that cell draws |
| `command_select_army` | F1 | selector |
| `command_select_builder` | F2 | selector |
| `command_select_production` | F3 | selector |

**The grid is positionally keyed**: cell (x, y) takes the key at that position in
`QWERTY / ASDFGH / ZXCVBN`, and the ACTION is named after the cell (`command_cell_3_1`), not
after any command. Attack/Stop/Defend already sat on A/S/D at (0,1)/(1,1)/(2,1), so the scheme
was mostly true by accident; formalising it cost one rebinding (Radiate G→Q, since it is an
ability rather than a generic verb) and gave Evacuate and Land the keys they had never had.

Widening the grid from five columns to six claimed a third column key — Y / H / N — and H
was `show_help`, which moved to **F4**. A grid cell has the stronger claim on a letter than a
held overlay does, and F4 puts help beside the F1–F3 selectors, likewise off the letters.

**Letters spent:** every one in `QWERTY ASDFGH ZXCVBN` (the grid), plus M (move). **Free:**
I J K L O P U — plus every digit, and F5 onward.

Where the grid keys point is now a property of the card on show, not of the key: on the
ACTIVE card A is attack-move, on the PRODUCTION card A trains the first unit in the row.

---

## Constraints that shape the design

1. **macOS turns Ctrl+left-click into a right-click** before the engine sees it. A Ctrl-modified
   click on a HUD button never arrives as a button press. Ctrl is therefore unusable for anything
   modifying a click — which is what pushed `purchase_fallback` onto Alt and requisition onto a
   toggle. (Ctrl pressed *alone* is fine, so a Ctrl toggle would work; Godot's
   `command_or_control_autoremap` also exists for the modifier-flag case.)
   **Resolved for the two click modifiers by remapping them on macOS:** `modifier_broaden` sits on
   Option and `modifier_narrow` on Command there (`PlatformModifiers`), and stay Ctrl and Alt
   elsewhere. The table below names the Windows and Linux keys.
2. **The modifier budget is spent for CLICKS, not for chords.** Constraint 1 rules out Ctrl as a
   *click* modifier bound literally to Ctrl on both platforms — but Godot's
   `command_or_control_autoremap` gives Ctrl-on-Windows / Cmd-on-macOS as one action, and
   Cmd+click is well-behaved. Ctrl is additionally unencumbered for KEYBOARD-ONLY chords on both
   platforms, which is what makes the selector matrix affordable. Two further hazards: many Linux
   window managers bind Alt+drag to "move window" at the compositor level, and Cmd+Q / Cmd+W /
   Cmd+H are OS-reserved on macOS.
3. **The HUD covers the bottom of the screen**, which is why the camera overscrolls past the map
   edge — otherwise the southern strip sits permanently behind the panels.
4. **A purchase is usually issued by clicking a HUD button**, not by clicking the world. Any
   modifier meant to affect purchases has to survive the focus going to a Control first — which is
   why the purchase modifiers are *polled* at purchase time rather than latched from an input
   event — and why standing orders are a right-click on the button rather than a modifier at all.

---

## Open tensions

Worth deciding deliberately rather than by accretion.

- **No control groups.** Every digit is free. This is the largest missing conventional idiom, and
  it interacts with the selector family (idle/on-screen/all) — control groups and "select all
  builders" answer overlapping needs, and committing to both may be committing to redundancy.
- ~~**Tool selection is mouse-only.**~~ **Resolved.** Every cell has a key, including the tool
  cells: an action per cell, running whatever that cell draws. What remains unbuilt is the
  production-context ROW (row 0 of the PRODUCTION card), which is what lets a player with two
  kinds of producer selected choose which one's training row they are looking at. Until it
  lands, that card shows the union of the selection's trainables.
- **Camera rotation is implemented but unbound.** Deciding it's not wanted is as good an outcome
  as binding it; leaving it half-present is not.
- **Requisition is far from the hand.** Backspace is unambiguous and collision-proof, but it is a
  mode toggled mid-fight. Whether a mode is the right shape at all — versus per-purchase intent —
  is worth revisiting once it has some play behind it. Its indicator is no longer a banner: the
  toggle button on `EconomyStack` both shows the mode and flips it, which puts it where its
  consequences are and frees top-centre for objectives and toasts.
- ~~**The queue has no HUD home.**~~ **Resolved.** `ProductionRail` holds the bottom-centre slot while
  nothing is selected, and the Details pane on the PRODUCTION page (hud-layout §Production); committed energy and a clearance estimate sit on `EconomyStack` with the resources. The
  rule that settled it: a HUD element is persistent iff it answers a question you can ask with
  nothing selected — so the info panel and command grid now hide wholesale on an empty selection,
  and what used to squat in that state has a home of its own.
- **Nothing is rebindable in game.** The `{{ action }}` idiom means a rebinding screen would cost
  nothing in copy, which makes it cheap to add later — and cheaper the earlier it is assumed.
  Positional cell actions cut the surface further: eighteen cells and a handful of named
  actions, rather than one binding per command.
- **Hotkey fall-through is not offered.** A key resolves only against the card on show, so
  training keys are inert during ACTIVE. Making that optional per player is plausible; the
  default stays strict, because the HUD showing exactly what the keyboard can do is the
  thing that makes the grid learnable at all.
- **Two generations of the technocracy roster share cells.** `dwelling`/`compound`/`lab`/
  `armory` and the newer `tc_*` set name the same ROLES, so they land in the same cells and
  are the only acknowledged collisions left (`test_ControlBinding`). Retiring one generation
  is what resolves it.
- **Button labels clip at six columns.** Cells are narrower than they were at five, and
  `clip_text` cuts "Attack" to "Attac". Icons were always the intended answer; the labels are
  placeholder art.
