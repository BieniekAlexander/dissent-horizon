---
title: Command card and hotkeys
type: system-note
---

# Command card and hotkeys

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The command card's families


The grid is **6 wide × 3 tall** (`ControlBinding.grid_width/height`) and holds **two cards**,
drawing exactly one. `ControlBinding.CommandFamily` is the axis, `RTSController.command_family`
is the state, and Tab (`card_toggle_family`) flips it.

| | row 0 | row 1 | row 2 |
| --- | --- | --- | --- |
| **ACTIVE** | abilities | the generic verbs — attack-move, stop, defend, fire, go | abilities |
| **PRODUCTION** | production contexts — one radio button per producer type | training | upgrades ([upgrades](../../macroeconomics/upgrades.md)) |
| **ORDNANCE** | minor | mid | major |

**ORDNANCE's rows are POWER TIERS**, following how deep an ability sits in the tech tree and
in the sanction grid — the Anarchists' Global EMP is top tier, so it is on ZXCVBN. The
`SanctionGrid` is 5 tiers × 6 columns and the command grid is 3 × 6, so **the widths match**:
the card is the unlock grid compressed vertically, column preserved, five tiers banded into
three rows. The player learns one layout and reads it in two places.

**The family is ACTIVE, and deliberately not "combat".** A Servant's Build, a transport's
Evacuate and an airframe's Land are all on this card and none of them is fighting, while a
stationary gun that shoots but never moves is on it too. What the card holds is **what an
existing commandable does** — orders and abilities — as against what a producer commits
energy to. `ControlBinding.CommandFamily.ACTIVE`.

**The axis is the COMMAND FAMILY, not the entity kind**, and that is the whole design. A
structure that both shoots and trains (a Warcraft-III-style ancient) offers commands in both
families, so the toggle reaches its attacks and its training in turn; a units-vs-structures
flag would leave one of the two with nowhere to be drawn.

**Which card a fresh selection OPENS on is a separate question from which cards it can fill,**
and it is answered by mobility rather than by the command set (`_preferred_command_family` /
`_selection_takes_orders`):

> ACTIVE, unless nothing in the selection can move and PRODUCTION has something to draw.

ACTIVE is the resting state because a group picked up mid-fight is picked up to be *ordered*,
and a mixed selection is such a group — a structure coming along with it does not change what
you reached for it to do. But a selection with **nothing mobile in it** was not picked up to be
ordered; it was picked up to be told what to make.

That second clause is load-bearing, not a nicety. Every producer offers a rally, and a rally is
a bare `command_move`. The moment the plain move got a cell of its own (the **Go** verb), every
barracks in the game began reporting a ACTIVE command — so preferring ACTIVE unconditionally
opened a barracks on a card holding one Go button and hid every train button behind Tab. The
mobility test is what separates *"has a ACTIVE command"* from *"was selected in order to be
given one"*. `test_CommandCard.gd` pins all three cases.

The preference is re-applied whenever `available_commands` is written, which is on selection
change and nowhere else — so the player's own Tab stands for as long as the selection does. A
card choice belongs to a selection, not to the session.

Consequences, each with the place it lives:

- **A card the selection cannot fill is never shown.** `available_families()` is derived from
  `_available_commands` (via each command's binding), and `_settle_command_family()` — called
  from the `available_commands` SETTER, before the buttons are drawn — corrects the card the
  instant the selection changes. `set_command_family()` refuses a family with nothing on it, so
  `toggle_command_family()` no-ops rather than emptying the card. That ordering is load-bearing:
  settling after drawing would leave one frame drawn against the old card, and the hotkeys
  reading a card the buttons had moved off.
- **A hotkey is gated by the card on show, with no separate rule.** `visible_command_in_cell()`
  is the single statement of what the grid is drawing, and both the buttons and
  `_dispatch_command_hotkey` read it. A key that resolves to no visible button does nothing, so
  training keys are simply inert while ACTIVE is up. "Fall through to the other card" is a
  plausible future preference; it is not the default, because the HUD showing exactly what the
  keyboard can do is what makes the grid learnable.
- **Build stays on the ACTIVE card** even though placing a structure is production in the
  economic sense: it is an order given to a UNIT, mid-fight, beside that unit's other orders.
  Its structure list (`ControlContext.BUILD`) takes over all three rows of that card.
- **The build sub-menu is a UNION across the selection, and the order that reaches the units is
  filtered per actor.** Both halves are the standing mixed-selection rule — *any member can
  offer it, only the members that can carry it out receive it* — and they had drifted apart.
  The menu asked `selection[0]` alone, so a builder and a soldier offered structures or nothing
  depending on which was clicked FIRST, while the Build button itself was on show either way
  (it comes from the union). The order in which a player assembles a group is not a statement
  about what they want to do with it. The issue half then had no per-actor gate at all: every
  other check `Build` makes — placement, price, tech — is commander-wide, so a soldier passed
  them all and was handed a Build it has no `Builds` component to execute. The menu now reads
  `CommandContextParser.tools_for_selection`, and `Build.meets_precondition` refuses an actor
  that cannot build the chosen tool, which is what routes the order to the builders alone
  (`assign_command_to_units` filters on that precondition). Tests:
  `tests/test_BuildContextSelection.gd`.
- Rows 0 and 2 of ACTIVE are one pool ("abilities") rather than two meanings — an acknowledged
  gap, to be split once there are enough unit abilities to say how. Radiate moved from (4,1) to
  (0,0) for it: it belongs to whichever units carry a charge, so it is an ability, not a verb.
  Spot took (0,0) — `Q` — on 2026-10-06, and Radiate moved to (1,0), `W`.
- **The verb row is now A S D F G**, filled left to right: attack-move, stop, defend, Fire
  (`command_focus_fire`), Go (`command_move`). Evacuate moved out of it to (3, 2) — `V`,
  beside Land and Rearm — on the same test Radiate was moved on: it needs a `Garrison`, so it
  belongs to whoever carries the component rather than to every unit, which makes it an
  ability. Row 1 is full. `N` (5, 2) is hold fire on the ordinary card
  and Cancel on the READY card, which is drawn alone, so the two never meet; hold fire is a
  verb by meaning and sits in the ability pool only for want of room. It is a pseudo-command
  and a TOGGLE — it sets `Commandable.is_holding_fire` across the armed selection, or clears it
  when all of them already hold, and touches no queue. While all hold it draws a lit top edge
  (`CommandButtonState.is_toggled_on`) and stays pressable: an "on" state is not a blocker.
  The Spot and Bombard buttons draw the same edge while the commander has automatic Bombard fire on, the toggle its
  RIGHT-click sets ([bombardment](../../combat/bombardment.md) §Automatic fire). What Go and Fire are FOR is
  [commands/saying-it-plainly](../../commands/saying-it-plainly.md).
- **Deploy / Undeploy share `Z` (0, 2) with Land, and outrank it** — one button in two states,
  drawn ahead of Land, so a selection that could do both issues Deploy alone. Which state is
  drawn, and why: [commands/deploying](../../commands/deploying.md) §The command card.
- **Plant / Detonate share `R` (3, 0)** — one button in two states, Plant placed first; when it
  steps aside: [combat/planted-explosives](../../combat/planted-explosives.md) §The command card.
- **Not every command earns a cell.** Occupy and Embark name their subject by hovering it, so
  a button would need the same hover to mean anything and would buy nothing the right-click
  does not already give. `CommandGrid.binding_for` returning null is the supported case, and
  `_command_is_on_current_card` filters such a command out of the visible set.

**Structure buttons are laid out by ROLE, at the same cell in every faction** — command centre
(3,0), infrastructure (1,0), dominion (2,0), extractor (0,0), barracks (0,1), war factory (1,1), air field
(2,1), tech (3,1)/(4,1) — so position carries over when the player changes side. Train buttons
take column *n* of row 1 from their index in their producer's `trains:` list. All of it lives in
the docs' `ui.grid`, not in code.

`ControlBinding.grid_collisions()` reports two buttons sharing a cell only when **four** things
fail to separate them: family, context, faction, and **actor** (`actor_ids()` — the producers a
train tool can be drawn by, derived by the importer from every `trains:` list). The actor rule
is what fits each faction's training row into six columns without a wall of hand-written
acknowledgements; `is_orphaned()` is its companion, marking a train button no producer offers so
it cannot collide with anything. Fixing the missing `ControlBinding.Faction` members
(`colonial`, `libertarian`, `marxist`, `theocratic` all silently fell through to `FACTION_ANY`)
took the unreviewed-collision count from **216 to 2**; the importer now rejects an unknown
faction name so the enum can't fall behind the docs again.

**The importer refuses a shared cell.** A cell draws only the first button it holds, so a
collision is not cosmetic: the hidden piece cannot be built or trained at all, and nothing on
screen says why. Every button the docs author (tools, and the producer-context buttons of
`ui.context_grid`) is reviewed by that same `grid_collisions()` before anything is written, and
any collision fails the import naming the docs to edit. It is built from the run's own docs,
never from the `Tool` registry, which still holds the previous run's `tools.json`. Verbs and
ability buttons are reviewed only by `test_ControlBinding`, since verbs are authored in code.

**HUD buttons are `FOCUS_NONE`** (`VerboseTooltipButton._ready`). A focused Control eats the
keys the game listens for before `_unhandled_input` sees them: Tab would move focus instead of
flipping the card, and Space (the fog view) and Enter would re-press whichever button was last
clicked.

## Three cards, two keys

`ControlBinding.CommandFamily` has three members and the grid draws exactly one.

| card | holds | owned by |
| --- | --- | --- |
| **ACTIVE** | what an existing commandable DOES — the verbs, its abilities, Build and the structure list it drills into | the selection |
| **PRODUCTION** | training and research: what a producer commits energy to | the selection |
| **ORDNANCE** | the COMMANDER's reach — abilities you cannot walk a unit to | the **commander** |

**Two keys, three destinations, and both keys SET rather than toggle.** That is the whole
reason the arrangement is predictable: neither key's meaning depends on where you currently
are. Backtick always means "ordnances"; Tab always means "my selection".

| key | does |
| --- | --- |
| `` ` `` (`card_ordnance`) | set the card to ORDNANCE |
| Tab (`card_toggle_family`) | set the card to the selection's; pressing again flips ACTIVE ↔ PRODUCTION |

A three-way ROTATION was rejected: skipping cards with nothing to draw makes the rotation
change LENGTH with the selection — two presses with a soldier, three with a barracks — so
"get me to production" becomes a different gesture depending on what you have. A binary flip
never changes, and is its own reverse.

### ORDNANCE is the one card the selection does not own

It is reachable with **nothing selected at all** — that is the point of it, since you should
not have to find a caster before you can invoke something with global reach. Four rules follow,
and each of them was a bug first:

- `_update_selection_owned_panels` keeps `CommandsSection` on screen while ORDNANCE is up. It
  is the single exception to the selection-owned rule.
- `set_command_family` lets ORDNANCE be entered **unconditionally**, even with nothing
  unlocked. Its buttons are drawn dark with the reason on them rather than removed — "you have
  none of these yet" is an answer the player asked for by pressing the key, and a key that
  silently does nothing reads as broken.
- **Nothing settles ONTO it.** `selection_owned_families()` masks it out of every path that
  picks a card on the player's behalf, so no selection change can land there.
- **Two things take you OFF it.** Tab, which goes to the selection's card — falling back to
  ACTIVE when the selection has nothing on either, rather than refusing, because the press has
  to do something visible and an empty ACTIVE hides the panel, which is the close gesture. And
  selecting a piece **that has no ordnances of its own**, which is an act of "I want to command
  THIS". Selecting *nothing* is not, and leaves the card alone; nor does selecting a piece that
  DOES have ordnances, which is what stops an ordnance button — it picks its own casters —
  from throwing the player off the card they just pressed it on.

### The commander's card shows everything

**Every ordnance has a button on the ORDNANCE card at all times** — unlocked or not, castable
or not, whatever is selected. It is the one place in the grid that draws a button for something
the player cannot use.

Everywhere else a button appears only when the current selection offers its command, which is
right for an ORDER: a card listing what this unit CANNOT do is noise. The commander's card
answers a different question — *what can I call in, and what would it take* — and a locked
ordnance is part of that answer. It is drawn dark with the reason on it, which is the whole
point of having per-blocker colours.

Three rules fall out of that, and each was a bug first:

- **The empty-selection guard must not reach it.** `_visible_command_names` returns nothing
  when the selection is empty; the ORDNANCE branch sits ABOVE that, because "nothing selected"
  is the state this card is normally read in.
- **Only what the faction OFFERS.** Another faction's ordnances are not locked — they are not
  on offer at all, and drawing them dark would tell the player they could work toward
  something their faction cannot reach. Asked of the faction's own authored **sanction grid**
  (`SanctionGrid.has_route_to`), not of the ability's faction tag: that tag exists for the
  grid-collision review, and `Faction.faction_name` is flavour text — "Haustoria", not
  "colonial" — so keying on it silently matched nothing and put every faction's ordnances on
  every card. What a faction offers IS its grid. A FREE ability (the Bombard's battery) has no
  cell to be found in and is always offered; whether you own a gun is `NO_CASTER`'s question.
- **THE SANCTION IS THE PERMISSION, and a piece's ability pool is not.** The unlock is checked
  FIRST and unconditionally. A Citadel grants Scan, Freeze, Beacon and Promotion the moment it
  is built, whether or not the commander ever spent dominion on any of them — the pool is
  authored on the PIECE. So *"something can cast it"* and *"the commander may use it"* are
  different facts, and reading the first as the second drew every unbought sanction lit. It did
  so by **two** routes before the check was made unconditional: with nothing selected, because
  finding one of the commander's own casters short-circuited it; and with the caster SELECTED,
  because its pool was read as already answering the question.
- **A press must not re-enter.** The routing sends a press to the caster-finding path, which
  finishes by ARMING the ability through `process_command` — the same function, same card,
  same command name. `_finding_casters` guards it; without the flag the first ordnance the
  player pressed overflowed the stack.
- **A locked command still has to resolve to its ability.** The lookup walked the commander's
  DEPLOYABLE sanctions, so an unbought one resolved to nothing, fell through to the plain-verb
  path, found no cooldown and was drawn lit. `AbilityBinding.ability_for_command` answers for
  every ordnance command whether or not it is unlocked.

**One button per ABILITY, not per level.** A levelled sanction has a binding per level sharing
a cell; the one shown is the level the commander owns, falling back to the first so a locked
family still has a face and a cell.

**A press finds its own casters.** It selects every piece that can cast the ability and arms
it, exactly as the old ordnance bar's buttons did — the player has not selected anything, and
being made to hunt for the Operations Center first is what this card exists to remove. Routed
at the top of `process_command`, above the availability gate, because that gate asks whether
the SELECTION offers the command and that is not the question here.

### Where an ordnance button comes from

`AbilityBinding` is the third kind of binding beside the plain verbs and `Tool`, and it is
GENERATED: the cell, the label and both tooltip tiers arrive from the ability's own doc, so
adding an ordnance is writing markdown and re-running the importer.

- **The cell is authored**, `ui: {grid: [x, y], factions: [...]}` on the `kind: AbilityDefinition` doc —
  the same `ui:` block a tool uses, so the grid has one vocabulary rather than one per kind of
  doc. The importer REJECTS an ordnance with no cell, which makes a missing `ui.grid` mean
  "this is a LOCAL ability" rather than "somebody forgot".
- **One ability is several bindings, all in one cell.** A dominion-unlocked ability is armed as
  its own LEVEL's command, so Scan 1, 2 and 3 are three commands — and supersession keeps
  exactly one in the commander's hands, which is the "alternatives in a cell" rule the grid
  already applies everywhere else. `ControlBinding.exclusion_group()` is what tells the
  collision review so, and it is generic rather than an ability check: the next thing with
  mutually exclusive variants gets it free.
- **The copy is the LEVEL's, not the ability's**, and an ability with levels has NO copy of
  its own — so anything drawing a button for one has to reach for a level's words.
  `AbilityCatalog.buttons_of` is that reach; skipping it is how the sanction bar shipped a
  button with an empty tooltip, which `VerboseTooltipButton` reports as an authoring bug.
  "Scan 2" reveals more ground than "Scan 1" and its button says so. `{{ piece_id }}` placeholders are rendered at IMPORT
  (`SpecGenerators.render_placeholders`, shared with the scene sync) so the game does no
  lookup and a piece rename re-renders every description mentioning it.
- **The command name is DERIVED once.** `Sanction.command_name_for` is called both by a live
  sanction and by the binding built from a level title, so a button and the command it fires
  cannot come to disagree.

### One ability, two cards

**An ordnance may claim a second cell on the ACTIVE card**, with `ui.active_grid` beside
`ui.grid`. The Bombard is why and is currently the only one: it is genuinely both things — an
ORDER you give a selected gun, and a strike the commander calls in without selecting anything.

Two cells rather than one cell carrying both families, because **a cell free on one card is
spoken for on the other**: (0, 0) is the Bombard on ORDNANCE and Spot on ACTIVE. So it is
two bindings with one command name, and pressing either does the same thing.

That makes it the first command with more than one binding, and it moved a rule:
**button visibility is decided per BINDING, not per command name.** Each button carries its own
family (`CommandGrid.BUTTON_FAMILY_META`, stamped at construction) and
`CommandGrid.families_for()` ORs across a name for the hotkey gate. Looking a button's card up
by name returns whichever binding sorts first, which would have drawn the Bombard on top of
Spot at ACTIVE's (0, 0).

It also retired the hand-written verb binding Bombard used to have. Two SOURCES for one
command — one authored in `command_grid.gd`, one generated from the doc — is how a cell moves
on one card and not the other.

### A sanction that takes a tool

**A sanction may offer a CARGO MENU**, and it is armed in two steps exactly as Build is:
pressing its button drills into a list, picking one sets `CommandMessage.tool`, and the
right-click that follows delivers it. Drop is the one that has them.

`payloads:` is authored **per LEVEL**, as `{piece: <id>, count: <int>}`:

| level | offers |
| --- | --- |
| Drop 1 | 3 × Recruit |
| Drop 2 | 5 × Recruit, or 1 × sloop |
| Drop 3 | 7 × Recruit, 2 × sloop, or 2 × Matilda |

**Per level is what makes "upgrading" free.** Supersession already replaces a level with its
successor, so a level that carries the same piece at a higher count IS the upgrade — no second
mechanism, and a column stays one sanction the player improves rather than a growing
collection of buttons. Adding a piece to the list is an unlock; raising its count is an
upgrade; both are one edit to one list.

What is worth knowing about how it is wired:

- **The menu is its own row of buttons** (`CargoSlotBinding`): slot *n* is the armed level's
  *n*-th piece, left to right along row 0, painted with that piece's picture and count while
  the menu is up, on the ACTIVE card — arming a cargo sanction turns the grid there from
  whichever card armed it, the commander's included. A level lists its
  pieces in the order of the level below it, so a piece keeps its key across an upgrade. The
  importer refuses a level offering more than a row's worth.
- **The menu stays up after a pick**, as it does for Build: the pick is a radio button, the
  chosen slot greys as CURRENT, and a different slot re-picks until the right-click lands.
- REJECTED: reusing each piece's own train button as its payload button. A train button
  lives on the PRODUCTION card at its producer's cell, so it was filtered off the ACTIVE card
  the menu opens on, and two pieces from two producers share a training cell — the menu
  never drew at all, and Drop could not be cast.
- **"Still choosing" is derived, not a second flag.** `pending_payload_sanction()` is "a
  payload sanction is armed AND nothing is chosen yet", read off the state that already exists.
  A parallel `menu_is_open` bool would be a copy that could disagree.
- **The cast is refused until a cargo is chosen.** The click that would fire it lands while the
  menu is still up; firing then would send an empty transport.
- **The scene carries piece IDS, never PackedScenes.** A resource-valued export inside a
  `Resource` crashes the Godot inspector, and the id is enough — the scene is resolved at cast
  time through the Tool registry, which is already the project's one id-to-scene map. The
  consequence to know: **a droppable piece must be reachable as a Tool.**

The cargo reaches the event through the same optional-property idiom `caster` and
`sanction_name` already use (`event.set(...)`), so only `EventAirDrop` takes it and an event
with its own authored cargo keeps it when nothing was chosen.

### A piece with several forms cycles on re-press

A build button whose piece is made from one of several underlying forms (the Anarchical
infrastructure, built from a neutral building) is still ONE button and ONE hotkey. The first press
arms the default form; pressing it again while it is armed arms the next form, and past the last
wraps to the first. Pressing any other tool arms that tool as ever, and re-pressing a piece with a
single form stays a plain re-arm.

- **A cycle is a choice, not an order.** Nothing is issued or queued, whatever the additive
  modifier says, and Cancel still puts the whole Build down.
- **The button and the key are one path**, so they cannot disagree about what a press means.
- **Which form is armed is said in the armed banner** ("READY · <form>"), because the button
  looks the same whichever form it would build. The ghost, the placement grid, the prices and the
  button's availability all follow the form the frame after a press.

### Sub-contexts

Only PRODUCTION has them: one context per producer TYPE in the selection, on row 0, as radio
buttons. Exactly one is always set; the active one is greyed and unpressable, and a context
with nothing to draw stays PRESENT but dimmed so the row never jumps under muscle memory.

**A producer's context cell is a STATIC property of its piece**, authored as
`ui.context_grid`. A SECOND cell, not a reuse of `ui.grid` — that one is where the piece's own
BUILD button sits on a builder's menu, a different button in a different list.

**And it is authored on the PRODUCER, never on what it trains.** `ProducerContextBinding`
discovers producers by walking each trainee's `producers` list, but reads the cell from
`Tool.for_id(producer_id).context_grid` — the producer's own entry. So two units trained by
one barracks have no way to disagree about where the barracks' button goes; there is one
place the answer can come from, and the trainees are only the route to finding the producer.

The corollary is that the key is INERT anywhere else: a `ui.context_grid` on a piece that
trains nothing is a button that can never be built, because nothing's `producers` list will
ever name it. Deliberately not validated — omitting `trains:` obviously means a piece trains
nothing, and a doc that has not been given its trainees yet is mid-write rather than wrong.
Note that a mobile producer would want a context cell like any other, so the question is
always `trains:` and never whether the piece has a footprint.

Static rather than packed left per selection, and the reason is the whole positional-hotkey
scheme: a key that trains from a barracks in one selection and a war factory in another is
exactly what it exists to prevent. **A barracks is always W.**

**Left-alignment is an authoring convention, never a rule.** A faction's producers are
assigned cells so that they are left-aligned *collectively* — Command Center, Barracks, War
Factory and Airfield at Q W E R — which means a selection holding only the War Factory shows
one button at E with Q and W empty. That is correct and is not to be compacted; nothing
enforces the alignment programmatically.

**The row is drawn iff there is a choice to make** — two or more producer TYPES selected. Two
barracks are one type and draw no row; a row of one button is noise, and a row that appears
and disappears is a moving target. `RTSController.producer_context_names()` states it once.

**Radio semantics, and there is no "none chosen" state.** `_settle_producer_context` runs from
the `available_commands` setter beside the card's own settle, for the same reason: the context
must never outlive the selection that filled it. It corrects a context the selection cannot
fill and picks one when the row appears, defaulting to the first producer in the selection —
matching how the card family lands on the first thing introduced. The chosen button is greyed
(`CommandButtonState.Blocker.CURRENT`) **and disabled**: greying alone would say "you are here"
and still accept the click.

**The context is STICKY across selections**, so re-selecting the same pair of building types
puts the player back on the row they were last using. It is a `ProducerContextBinding`, the
fourth binding kind and the only one that acts on the CARD rather than the selection — which
is why its name does not carry the `command_` prefix that routes an action into the grid's
dispatcher as an order.

ACTIVE has no sub-context. It was designed with one, to make room for global abilities, and
the third card removed the need — which also freed Y.

## What is in the grid, and what a fifth separator is for

`CommandGrid.bindings()` is every binding in placement order: verb commands, then tools, then
the ORDNANCE card's abilities, then the producer-context row.

**Bombard is not among the verbs.** It is an ordnance — global reach, so the player cannot
walk to a caster — and an ordnance is drawn on its own card from its own doc's `ui.grid`. A
hand-written verb binding beside the generated one would have put the same command in two
cells on two cards.

**Repair sits at (5, 1) — the H cell — and the button says REPAIR, not "heal".** H is only
the mnemonic the cell's key gives it. One order mends a dented tank and a burning barracks
alike, and the Colonials' Servants work on BIO and MECH frames both, so "heal" would name
half of what the button does. It arms the same `Repair` command a right-click on a damaged
friendly resolves (`RTSController.HOTKEY_COMMANDS`) — the button is a way to aim a repairer
deliberately and a way for the card to say the capability exists, not a second, weaker route
to the order.

**Row 0 was vacated.** The three SELECT-context selector bindings that used to sit there are
now `SelectorPanel`, a persistent panel of their own: a selector is reached for precisely when
the current selection is WRONG, so gating it on the selection being empty was backwards. What
row 0 is now available for is the production contexts, which is the one thing that genuinely
varies with the selection.

**`ControlBinding.exclusion_group()` is a fifth separator for the collision review**, beside
family, context, faction and `actor_ids`. It exists for LEVELS: a dominion-unlocked ability is
armed as its own level's command, so Scan 1, 2 and 3 are three bindings in one cell, and
supersession (`SanctionGrid.is_superseded`) guarantees the commander holds exactly one at a
time. Without it the review reported every levelled ordnance as colliding with itself — noise
that would train a reader to ignore the report. It is deliberately GENERIC rather than an
ability-id check: the base class knows nothing about abilities, and the next thing with
mutually exclusive variants gets the same hook for free.

## What a darkened button means

**One vocabulary, every button.** `CommandButtonState` classifies why any command-grid button
cannot be pressed and what it should draw — train tools, build tools, verbs and abilities
alike. `RTSController._apply_button_availability` is the only caller.

It replaced two idioms that had drifted apart: purchases had a five-way per-blocker tint,
abilities had on-or-greyed. The same refusal therefore looked different depending on which
half of the grid it came from, and only a purchase could say *why*. A player is asking one
question of any dark button — **what would make this work?** — and the answer has to look the
same wherever it is asked.

| blocker | colour | remedy the colour is naming |
| --- | --- | --- |
| `NONE` | white | — |
| `LOCKED` | flat neutral dim | go build something; not yet one of your options |
| `UNAFFORDABLE` | always waitable — see below | you cannot pay today |
| `RECHARGING` | always waitable — see below | nothing, but time |
| `NO_PAD` | desaturated blue | a WARNING, not a refusal — the aircraft will queue for a deck |
| `NO_CASTER` | dim teal | the ability is yours; build (or replace) something that can cast it |
| `UNPOWERED` | dim amber-brown | the caster is standing there dark — build an infrastructure provider |
| `CURRENT` | pale grey | "you are here"; pressing it would do nothing, because it is already done |

**`UNPOWERED` is not `RECHARGING` in another colour.** A dark building can be holding a full
pool and still cast nothing, so telling the player to wait for a charge they already have is
the wrong instruction — and unlike every waitable blocker, waiting never clears this one. See
[production and economy](../../macroeconomics/production-and-economy.md) §Insufficient
infrastructure.

**WAITABLE is not a blocker; it is a property of one, and the colour follows the CLICK.** A
blocker waiting can clear (an unmet price, a spent charge, a prerequisite already on its way)
can be queued: `modifier_additive` turns the refusal into an order that waits, and one flag
carries all three (`CommandMessage.defer_if_unaffordable` — see
[cooldowns-and-preconditions](../../commands/cooldowns-and-preconditions.md)). So:

- **Modifier up:** amber — possible, but clicking is refused unless queued.
- **Modifier down:** lit like any button that works, because clicking does work.

The blocker is still recorded, because the reason has not changed; only its colour gives way.
This is why `UNAFFORDABLE` and `RECHARGING` have no colour of their own: both are always
waitable. A recharging button still draws its countdown. `LOCKED` stays grey unless its
prerequisite is on its way, in which case it is waitable like the others.

This replaced amber-while-held, where amber marked what the modifier WOULD queue and a refused
click was red (price) or violet (charge). Settled 2026-09-28: the button says what the click does
now, and the modifier makes a queueable order look ordinary.

**Both live on the BUTTON**, not in the info panel's summary — they were briefly there, and it
makes the player look away from the button to find out about the button. A charge count answers
"can I press this", so it goes on the thing being pressed.

**Two overlays**, both full-rect Controls that align their text inside the button rather than
computing a corner box. That is not fussiness: a sized-and-offset overlay is exactly the bug
that drew every status bar BELOW its `CommandableCard` for months (CLAUDE.md §Seeing the HUD
without a screen), and full-rect leaves no arithmetic to get wrong.

- **Charge pips**, bottom-right, `"2/3"` — drawn only above a capacity of one, because "1/1"
  says nothing a lit button does not already say.
- **Countdown**, centred, seconds to the next charge — drawn for a PARTLY-FILLED pool as well
  as an empty one. It is a property of the pool rather than of being blocked: a pool at 2 of 3
  is still refilling, and "when does the third arrive" is asked of a button you can press. For
  an empty pool it answers the only question a greyed ability actually raises — not *why*, but
  *how long*. One decimal under ten seconds and whole
  seconds above it: hundredths on a minute-long cooldown are noise, and a short cooldown
  rounded to a whole second reads as stalled.

Ticks are what `Abilities` counts in and seconds are what a player reads; the factor is READ
from the project's physics-rate setting (`TimeUtils`) rather than typed, so a change to the physics rate
cannot silently make every timer on screen wrong.

**Resolving a command back to its ability takes two routes and both are asked**, because a
command name is derived differently on each: an ability naming its own command (the Bombard's
battery) is found in `AbilityCatalog`, while a SANCTION's name is derived from its title
(`Sanction.command_name`) and is found by walking the commander's own sanctions — the same
source that put the button there. Neither is a hand-kept table, deliberately: a second map from
command name to ability is a second place for one fact to live, and the copy is what goes stale.

**`NO_CASTER`** — "you own nothing that can do this" — is distinct from LOCKED, which is "you
never bought this". Different remedies: a piece versus dominion. It is only reachable on the
ORDNANCE card, and reaching it needed a second rule: **a button speaks for the SELECTED casters
when any are selected, and otherwise for every caster the commander owns.** That second half is
what the commander's card is read in — its buttons stand with nothing selected, and the thing a
player wants to know about a global ability is whether it can be used at all right now.

Tests: `tests/test_CommandButtonState.gd`.

## The selector matrix


Three families on **F1 / F2 / F3** — army, builder, production — off the alphabetical block
entirely. **Two axes, one per modifier, both ABSOLUTE**, and they compose
(`RTSController._run_selector`):

| | cycle ONE (default) | take ALL (`modifier_broaden`, Ctrl) |
| --- | --- | --- |
| any member (default) | cycle every one you own, least-recently-selected | every one you own |
| idle only (`modifier_narrow`, Alt) | cycle the idle ones | every idle one you own |

Plus Shift (`command_additive`) to add rather than replace, on every cell.

**Every selector searches the whole map.** Scope was a third axis (on screen / global) and was
dropped: the on-screen half already has a gesture, since a box drag resolves wherever it ends,
HUD included (see §Box-select drags). That is what made the budget close — three axes do not
fit in the three keyboard-only modifiers, and two do.

**The unmodified cycle is NOT idle-first**, deliberately. Idle precedence is absolute, so the
cycle would never leave the idle set while one member was idle, making the unmodified press
identical to `modifier_narrow` exactly when that modifier would have mattered — two cells
collapsing into one, which is the same failure the scope split had. The filter belongs to the
modifier; the ordering (`RTSController.cycle_index`, a static over last-selected times,
mirroring `narrowed_index`) belongs to the cycler.

**The two modifiers agree in DIRECTION across both key spaces**: `modifier_broaden` means
"take all" (all actors / all members) and `modifier_narrow` means "restrict" (to one actor /
to idle only). What is restricted differs; that it restricts never does. This retires the old
recorded inconsistency, in which Alt narrowed on the command side and broadened here.

Both modifiers are POLLED, not latched, because a selector can also fire from a HUD button
press. Neither is a click modifier, so the macOS Ctrl+LMB problem doesn't reach them; and
neither is named `command_*`, so `_dispatch_command_hotkey` can't mistake a modifier for a
command.

The rule is stated ONCE, in `RTSController._owned_matching` — both selection routines and
`selector_preview` (which `SelectorPanel`'s buttons render from) go through it, so a button
reading "cycle 3" and the press that follows can never be looking at different sets.

**The camera jump is load-bearing, not a convenience.** With every selector global, a pick can
be anywhere, and selecting something you cannot see is worse than selecting nothing.
`_look_at_selection` centres on the pick — or on a bulk selection's CENTROID — and only when
nothing selected is already visible, so re-selecting a group you are looking at never jerks the
view. The on-screen test that used to decide WHAT you select now decides whether the camera
MOVES: same `_selection_shape_in_view` machinery, better question. Known cost of the centroid:
an army split between two fronts centres on the empty ground between them; subgroup cycling is
the feature that fixes that, and it does not exist.

`RTSController.CameraFollow` (WHEN_NEEDED / NEVER) gates it. It is a **preference, not a mode**
— it changes how the interface always behaves rather than what the game will do this match, so
unlike requisition mode it earns no HUD indicator. It has no persistent home: the project has
no settings system (no `ConfigFile`, nothing under `user://`), so it is a runtime property
awaiting one.

**This retires the old "one key can mean two things; the unit command wins" rule.** A/S/D/E/W
each used to carry both a verb and a selector, resolved by an invisible precedence rule.
Selectors are off the letters now, so the collision cannot occur and the rule was deleted
rather than refined. The three SELECT-context grid bindings are gone too — the buttons are
`SelectorPanel` (see §The HUD is split), which is what vacated command-grid row 0 for the
production contexts. Tests: `tests/test_SelectorBindings.gd`.
