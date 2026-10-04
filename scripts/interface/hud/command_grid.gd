class_name CommandGrid
extends GridContainer

## Data-driven command grid. EVERY button is a ControlBinding placed at its
## grid_position: verb commands are the plain ControlBindings in _VERB_BINDINGS
## below (no entity payload); tool buttons come from the Tool registry. bindings()
## is the single source the grid builds from — and the same set the collision
## review (ControlBinding.grid_collisions) is checked against in tests.
##
## Several bindings may name the same cell — they are alternatives, and at most one of
## them is ever on screen: RTSController.upate_hud_buttons() shows the first one the
## current selection calls for and leaves the rest hidden. Whether two of them being
## applicable at once is a real problem is reviewed by ControlBinding.grid_collisions().
##
## The grid is strictly uniform: every cell is exactly one GRID_WIDTH-th of the grid
## rect wide and one GRID_HEIGHT-th of it tall, whatever its buttons would rather be —
## see Cell and _fit_cells_uniformly().


## One grid slot, holding the button(s) placed in that cell. Each of them gets the
## cell's whole rect (see _fill_with_children), and the cell reports NO minimum size of
## its own — which is why it isn't a stock container. A GridContainer sizes each column
## to the widest minimum in it, and Control.set_size refuses to shrink a Control back
## under its minimum, so a cell that passed its buttons' appetite upward (a long label,
## or the 19 bindings stacked in cell (2, 0)) would widen its column past its
## 1/GRID_WIDTH share and _fit_cells_uniformly() could not undo it. A stock container
## computes that minimum in C++ and ignores a script's _get_minimum_size, so the sort
## is reimplemented here instead. Sizing runs strictly the other way: the cell is
## HANDED its share of the grid rect, and a button too wide for it is clipped.
class Cell:
	extends Container

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO

	func _notification(a_what: int) -> void:
		if a_what == NOTIFICATION_SORT_CHILDREN:
			_fill_with_children()

	## Every button in the cell gets the WHOLE cell — never a share of it, since a
	## button narrowed to fit a neighbour is exactly what this grid is not allowed to
	## do. They can do that because only ONE of them is ever visible at a time:
	## RTSController.upate_hud_buttons() shows the first button in a cell that the
	## current selection calls for and leaves the rest hidden, so the buttons a cell
	## holds are alternatives rather than co-tenants.
	func _fill_with_children() -> void:
		for child in get_children():
			var control: Control = child as Control
			if control != null:
				fit_child_in_rect(control, Rect2(Vector2.ZERO, size))


## ── Row idioms ──
##
## The grid is 6 wide and 3 tall, and it holds TWO cards (ControlBinding.CommandFamily);
## the player flips between them with `card_toggle_family` and exactly one is on screen.
## Each row means something, per card, so a cell's position tells the player what KIND of
## thing lives there before they read the button:
##
##   ACTIVE      row 0  abilities
##               row 1  the generic verbs — attack-move, stop, defend, fire, go, repair
##               row 2  abilities
##   PRODUCTION  row 0  production contexts: which selected producer the card is showing
##                      (ProducerContextBinding — radio buttons, one per producer TYPE)
##               row 1  training
##               row 2  upgrades (none exist yet)
##
## Rows 0 and 2 of the ACTIVE card are one pool rather than two distinct meanings; that is
## an acknowledged gap, to be split once there are enough unit abilities to say how.
##
## Build is on the ACTIVE card and not the PRODUCTION one, though placing a structure is
## plainly production in the economic sense. It is an order given to a UNIT, mid-fight,
## alongside that unit's other orders, and putting it on the other card would mean flipping
## cards to tell a builder what to do. The structure list it drills into (ControlContext
## .BUILD) takes over the whole ACTIVE card, all three rows — those cells are laid out by
## the pieces' own docs, not here.
##
## ── Verb commands ──
##
## Plain ControlBindings (ACT context, no entity payload, ACTIVE family by default).
## _init args: command_name, label, grid_position, control_context, simple_tooltip,
## verbose_tooltip, family.
##
## Every binding carries BOTH tooltip tiers: the one-liner a player reads in passing,
## and the paragraph they get by holding the verbose key (see VerboseTooltipButton). The
## copy names its keys with `{{ action }}` placeholders — ButtonSpec resolves them
## against the live InputMap, so a rebinding re-words the tooltip instead of dating it
## (see InputPrompt).
static var _VERB_BINDINGS: Array = [
	ControlBinding.new(
		"command_ability",
		"Build",
		Vector2i(4, 2),
		ControlBinding.ControlContext.ACT,
		"Place a structure ({{ command_ability }})",
		(
			"Open this builder's list of structures. Pick one, then click a site to "
			+ "place it.\nThe purchase joins the commander's production queue and the "
			+ "builder walks over to raise it. Its blueprint goes up straight away — "
			+ "you can select the blueprint and queue units at it before construction "
			+ "even starts.\nHold {{ modifier_additive }} while placing to REQUISITION "
			+ "it: a site you cannot afford yet is queued instead of refused, and the "
			+ "builder waits there until its turn for funds comes round."
		)
	),
	ControlBinding.new(
		"command_attack_move",
		"Attack",
		Vector2i(0, 1),
		ControlBinding.ControlContext.ACT,
		"Advance and engage ({{ command_attack_move }})",
		(
			"Move on a point and attack anything hostile met along the way, resuming "
			+ "the advance once it is dead.\nRight-clicking directly on an enemy "
			+ "attacks that one target instead. Hold {{ modifier_additive }} to queue "
			+ "this behind the orders already given."
		)
	),
	ControlBinding.new(
		"command_stop",
		"Stop",
		Vector2i(1, 1),
		ControlBinding.ControlContext.ACT,
		"Cancel current orders ({{ command_stop }})",
		(
			"Drop every queued order and hold position.\nUnits still defend "
			+ "themselves where they stand; they stop advancing, chasing and building."
		)
	),
	ControlBinding.new(
		"command_defend",
		"Defend",
		Vector2i(2, 1),
		ControlBinding.ControlContext.ACT,
		"Hold a position ({{ command_defend }})",
		(
			"Send the selection to a post and keep it there on guard.\nDefenders "
			+ "answer threats near the POST rather than near themselves, so the whole "
			+ "group reacts to one incursion together and a single baited unit can't "
			+ "be peeled away from the line."
		)
	),
	ControlBinding.new(
		"command_focus_fire",
		"Fire",
		Vector2i(3, 1),
		ControlBinding.ControlContext.ACT,
		"Shoot at a place ({{ command_focus_fire }})",
		(
			"Fire on a POINT rather than on a target: the selection walks into "
			+ "range, turns to face it, and keeps shooting there until told "
			+ "otherwise.\nWhat that achieves depends on the weapon — a shell with a "
			+ "blast lands and splashes whatever is standing there, while a rifle "
			+ "round put into bare dirt hits nothing. Only weapons that can do "
			+ "something to a point are offered it."
		)
	),
	# "H for heal" is the mnemonic the cell's key gives it, but REPAIR is the word: the same
	# order mends a dented tank and a burning barracks, and the Colonials' Servants work on
	# BIO and MECH frames alike — "heal" would name half of what the button does.
	ControlBinding.new(
		"command_repair",
		"Repair",
		Vector2i(5, 1),
		ControlBinding.ControlContext.ACT,
		"Mend a damaged friendly ({{ command_repair }})",
		(
			"Send the selection to repair a damaged friendly unit or building, "
			+ "restoring its hit points until it is whole.\nOffered only by units that "
			+ "CAN repair (the Kobold and the Sapper), and only onto a target that is "
			+ "finished, yours, and actually hurt — an intact building falls through "
			+ "to whatever the right-click would otherwise have read.\nRight-clicking "
			+ "a damaged friendly already does this; the button is here so a repairer "
			+ "can be aimed deliberately, and so the card says the capability exists."
		)
	),
	ControlBinding.new(
		"command_move",
		"Go",
		Vector2i(4, 1),
		ControlBinding.ControlContext.ACT,
		"Move, and nothing else ({{ command_move }})",
		(
			"Order a plain move, overriding whatever the right-click would otherwise "
			+ "have read the target as.\nRight-clicking resolves the most specific "
			+ "order the selection can carry out — attack an enemy, board a transport, "
			+ "mend a damaged building. This says none of that: go to that point, or "
			+ "follow that unit. It is how you drive a truck THROUGH something rather "
			+ "than around it, and how a scout shadows an enemy without opening fire."
		)
	),
	# An ABILITY of whatever happens to own a garrison, not an order every unit answers to,
	# so it belongs in an ability row beside Land and Rearm rather than in the verb row. It
	# was at (3, 1) and answered to F, which the Fire verb now holds.
	ControlBinding.new(
		"command_evacuate",
		"Evacuate",
		Vector2i(3, 2),
		ControlBinding.ControlContext.ACT,
		"Turn out the garrison ({{ command_evacuate }})",
		(
			"Order every occupant out of the selected building or transport.\nWhat "
			+ "comes out is what went in: a stock truck's prisoners are released as "
			+ "themselves, back to the commander they were taken from. Turning one "
			+ "into a Servant is the Compound's doing, and only a delivery there does "
			+ "it — so a cage emptied in the field is a capture thrown away.\nUse the "
			+ "info panel's occupant cards to let just one out."
		)
	),
	# An ABILITY, not a generic verb — it belongs to whichever units happen to be carrying a
	# charge — so it sits in an ability row rather than in row 1 beside Stop and Defend. It
	# vacated (4, 1) for the row idioms; the Go verb holds that cell now.
	ControlBinding.new(
		"command_spot",
		"Spot",
		Vector2i(1, 0),
		ControlBinding.ControlContext.ACT,
		"Call in a firing solution",
		(
			"Send this unit to mark a point for the artillery. It walks into range, "
			+ "holds still while it calls the strike in, and leaves a beacon standing "
			+ "there.\nIt then STAYS on the beacon until a Bombard spends it — that "
			+ "commitment is what the artillery is paying for. Orders queued behind "
			+ "this one wait for the shot. Giving it any other order cancels the "
			+ "solution and removes the beacon."
		)
	),
	# ONE CELL, TWO STATES: a Sapper plants until its charge is in play, then sets it off. Plant
	# is placed first, and the controller drops it from a selection that also offers Detonate
	# and in which no Sapper has a charge ready (RTSController.selection_commands) — so the
	# cell reads Plant while anything selected could plant, and Detonate after that. At R
	# because Q and W hold Radiate and Spot, abilities of other pieces that a selection with a
	# Sapper in it could still draw.
	ControlBinding.new(
		"command_plant",
		"Plant",
		Vector2i(3, 0),
		ControlBinding.ControlContext.ACT,
		"Plant a charge ({{ command_plant }})",
		(
			"Walk to a point or a vehicle or building and rig a charge there. A "
			+ "charge on a vehicle or building rides with it; anywhere else it stands "
			+ "on the ground, where it can be shot.\nThe Sapper has one charge, and "
			+ "gets it back 30 seconds after the last one it planted has gone off or "
			+ "been removed. If the Sapper dies, its charge is lost without going off."
		)
	),
	ControlBinding.new(
		"command_detonate",
		"Detonate",
		Vector2i(3, 0),
		ControlBinding.ControlContext.ACT,
		"Set off the charge ({{ command_detonate }})",
		(
			"Set off the charge this Sapper planted, or the selected charge itself — "
			+ "anywhere on the map, whether or not you can see it.\nA charge also goes "
			+ "off if what it rides on is destroyed, or if it is destroyed where it "
			+ "stands. An enemy can remove it by repairing it, or the vehicle it is on."
		)
	),
	ControlBinding.new(
		"command_launch",
		"Radiate",
		Vector2i(0, 0),
		ControlBinding.ControlContext.ACT,
		"Lay down a radiation field ({{ command_launch }})",
		(
			"Spend one of the unit's radiation charges on a point within range, "
			+ "leaving a radiation field there.\nOffered only while the unit is "
			+ "carrying the ability and has a charge left."
		)
	),
	# DEPLOY OUTRANKS LAND in their shared cell, and Undeploy is the same button in its other
	# state: placed ahead of Land, so a selection that can do both draws Deploy and its key
	# issues Deploy alone — no unit in it is told to land (ControlBinding.wins_its_cell).
	# Deploy is placed ahead of Undeploy, so a selection with anything not yet planted
	# deploys the rest, and only an all-planted selection is offered Undeploy.
	ControlBinding.new(
		"command_deploy",
		"Deploy",
		Vector2i(0, 2),
		ControlBinding.ControlContext.ACT,
		"Plant where you stand ({{ command_deploy }})",
		(
			"Deploy the selected units where they stand. It takes a few seconds, "
			+ "during which they cannot move or fire; once deployed they cannot move "
			+ "at all, and are harder to hurt.\nUnits already deployed are left as "
			+ "they are, so pressing it on a mixed selection deploys the rest. Once "
			+ "all of them are deployed, this button becomes Undeploy."
		)
	),
	ControlBinding.new(
		"command_undeploy",
		"Undeploy",
		Vector2i(0, 2),
		ControlBinding.ControlContext.ACT,
		"Pack up and move again ({{ command_undeploy }})",
		(
			"Undeploy the selected units. They give up the deployed protection at "
			+ "once and cannot fire until they are packed up; after that they move as "
			+ "normal.\nOffered only when every selected unit that can deploy already "
			+ "has."
		)
	),
	ControlBinding.new(
		"command_land",
		"Land",
		Vector2i(0, 2),
		ControlBinding.ControlContext.ACT,
		"Set down on the ground",
		(
			"Bring the selected aircraft down, where it moves and is shot at as a "
			+ "ground unit.\nOffered only for units that hover and are not already "
			+ "grounded."
		)
	),
	# Beside Land, because the two are the aerial pair: one sets an aircraft down anywhere,
	# the other sends it to a deck. Both are abilities of the airframe rather than generic
	# verbs, so both sit in an ability row rather than in row 1.
	ControlBinding.new(
		"command_rearm",
		"Rearm",
		Vector2i(1, 2),
		ControlBinding.ControlContext.ACT,
		"Send to an airfield to reload",
		(
			"Fly the selected aircraft to an airfield, park on a free pad and refill "
			+ "its ammunition.\nOffered only for aircraft whose weapons do not reload "
			+ "in the field. They fly home on their own once dry and resume the order "
			+ "they broke off from, so this is for topping up before a run rather than "
			+ "a rescue."
		)
	),
	# A TOGGLE, and a verb by meaning, but row 1 is full. It shares N with Cancel, which is
	# drawn only on the READY card and so never beside it (see the note on Cancel below).
	ControlBinding.new(
		CommandContextParser.HOLD_FIRE_COMMAND,
		"Hold",
		Vector2i(5, 2),
		ControlBinding.ControlContext.ACT,
		"Hold fire ({{ command_hold_fire }})",
		(
			"The selection stops picking targets on its own: it will not open fire "
			+ "on what comes into range, shoot back when hit, or engage from a Defend "
			+ "or Patrol. Its orders are left exactly as they were.\nAn Attack or "
			+ "Attack-move order lifts the hold. Units that gain stealth hold fire "
			+ "automatically, so they are not given away by the first thing that "
			+ "wanders past.\nA toggle: lit along its top edge while everything "
			+ "selected is holding, and pressing it then lets them all fire again. "
			+ "With only some holding, it sets the rest."
		)
	),
	# THE READY CARD'S ONLY BUTTON. It is drawn ALONE, and only while an order is armed and
	# fully answered (RTSController.is_command_ready), so it never shares the card with
	# anything and cannot collide with the cell's ordinary occupant — which is why
	# ControlBinding.grid_collisions skips it outright. Bottom-right because that is where a
	# cancel belongs and because the cell's positional hotkey is already N.
	ControlBinding.new(
		RTSController.CANCEL_COMMAND,
		"Cancel",
		Vector2i(5, 2),
		ControlBinding.ControlContext.ACT,
		"Put the armed order down ({{ command_cell_5_2 }})",
		(
			"Cancel the order you have armed and go back to the ordinary command "
			+ "card. Nothing is issued and the selection is left exactly as it is.\nA "
			+ "left click anywhere on the map does the same thing — this button is "
			+ "here so the card always says so."
		)
	),
	# NOT here, deliberately: Embark — the other direction of Evacuate's door — has no cell.
	# It is a right-click default, like Occupy: the player says who is being called in by
	# hovering them, so a button would need the same hover to mean anything and would buy
	# nothing the right-click does not already give.
]

## Metadata key carrying a button's own CommandFamily (see _place_button).
const BUTTON_FAMILY_META: StringName = &"command_family"


## The families a command is drawn on, OR'd across every binding that names it. A command
## with several bindings is on every card any of them claims — which is how the Bombard is
## both an order to a selected gun and a strike on the commander's card.
static func families_for(command_name: String) -> int:
	var mask: int = 0
	for binding: ControlBinding in bindings():
		if binding.command_name == command_name:
			mask |= binding.family
	return mask


## Every binding in the grid, in placement order: verb commands, then tools, then the
## ORDNANCE card's abilities, then the producer-context row.
## What is deliberately NOT here — Bombard, and the old row-0 selectors:
## gdd/systems/ux/ui/command-card-and-hotkeys.md §What is in the grid.
static func bindings() -> Array:
	return (
		_VERB_BINDINGS
		+ Tool.command_tool_map.values()
		+ AbilityBinding.all()
		+ ProducerContextBinding.all()
		+ CargoSlotBinding.all()
	)


## The binding a command name belongs to, or null. Linear over ~70 bindings and called
## from button construction and tooltip rendering rather than per frame, so it is not
## worth an index that could go stale against the Tool registry's lazy load.
static func binding_for(command_name: String) -> ControlBinding:
	for binding: ControlBinding in bindings():
		if binding.command_name == command_name:
			return binding
	return null


## The InputMap action that fires `a_command_name`'s button, or &"" if the command has no
## place in the grid.
##
## Hotkeys are positional (see ControlBinding.CELL_ACTION_PREFIX), so a command has no key
## of its own — it has a CELL, and the cell has the key. This is what lets copy go on
## naming commands: `{{ command_attack_move }}` still resolves, via the cell that command
## currently occupies, so moving a button re-words its own tooltip. InputPrompt calls it
## for any placeholder that isn't an action name.
static func action_for_command(command_name: String) -> StringName:
	var binding: ControlBinding = binding_for(command_name)
	return ControlBinding.cell_action(binding.grid_position) if binding != null else &""


#region Lifecycle
func _ready() -> void:
	columns = ControlBinding.GRID_WIDTH

	# One Cell per grid slot, row-major (index = y*width + x) — the order
	# _fit_cells_uniformly() reads them back in.
	var cells: Array = []
	for i in ControlBinding.GRID_WIDTH * ControlBinding.GRID_HEIGHT:
		var cell := Cell.new()
		add_child(cell)
		# No custom_minimum_size, deliberately: a floor here is a floor Control.set_size
		# refuses to go under, so it would defeat the uniform fit the moment the grid's
		# rect divided into anything smaller than it.
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# A button clamped to its own theme minimum can still be laid out wider than the
		# slot it was given (the cell can't shrink it either); clipping keeps that inside
		# the cell instead of over the neighbouring button.
		cell.clip_contents = true
		cells.append(cell)

	for binding: ControlBinding in bindings():
		_place_button(cells, binding)


## GridContainer sizes each column to the widest minimum size in it, then shares the
## leftover space out — so ONE fat cell (a long label, or two bindings stacked in the
## same cell) makes its column wider than the rest and the uniform 5x3 grid breaks.
## Re-fitting every cell to an exact 1/columns x 1/rows share of the grid rect is what
## makes the layout independent of what the buttons ask for. Runs after
## GridContainer's own sort: the C++ handler is notified before the script one, so
## these rects are the ones that stick.
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_SORT_CHILDREN:
		_fit_cells_uniformly()


#endregion


#region Private helpers
## Lays the cells out on a strict grid: cell (x, y) gets the x-th of `GRID_WIDTH`
## equal column widths and the y-th of `GRID_HEIGHT` equal row heights, separators
## taken out first. Cells are placed by their index in the child list, which is the
## same row-major order _ready() created them in.
func _fit_cells_uniformly() -> void:
	var h_separation: int = get_theme_constant("h_separation")
	var v_separation: int = get_theme_constant("v_separation")
	var cell_size: Vector2 = Vector2(
		(size.x - h_separation * (ControlBinding.GRID_WIDTH - 1)) / ControlBinding.GRID_WIDTH,
		(size.y - v_separation * (ControlBinding.GRID_HEIGHT - 1)) / ControlBinding.GRID_HEIGHT
	)
	for i in get_child_count():
		var cell: Control = get_child(i) as Control
		if cell == null:
			continue
		var cell_position: Vector2i = Vector2i(
			i % ControlBinding.GRID_WIDTH, i / ControlBinding.GRID_WIDTH
		)
		fit_child_in_rect(
			cell,
			Rect2(
				Vector2(
					cell_position.x * (cell_size.x + h_separation),
					cell_position.y * (cell_size.y + v_separation)
				),
				cell_size
			)
		)


func _place_button(a_cells: Array, a_binding: ControlBinding) -> void:
	if not ControlBinding.position_in_bounds(a_binding.grid_position):
		push_error(
			(
				"CommandGrid: '%s' has out-of-bounds grid cell %s"
				% [a_binding.command_name, a_binding.grid_position]
			)
		)
		return
	var spec := ButtonSpec.new(
		a_binding.command_name,
		a_binding.label,
		a_binding.simple_tooltip,
		a_binding.verbose_tooltip
	)
	# A button that stands for a piece — a tool that trains or places one, a producer's radio
	# button — is drawn as that piece's picture; anything without one (a verb, an ability, a
	# piece nobody has drawn yet) keeps its label.
	if a_binding is Tool:
		spec.icon = PieceIcons.for_id((a_binding as Tool).type)
	elif a_binding is ProducerContextBinding:
		spec.icon = PieceIcons.for_id((a_binding as ProducerContextBinding).producer_id)
	var b: Button = ButtonSpec.create_button_from_spec(spec)
	# Clip long labels so a button's text can't inflate its minimum size past its
	# grid cell (e.g. "Idle Builder" wants ~97px) — Button zeroes its text's width
	# contribution when clip_text is on, and the label is drawn cut off instead.
	b.clip_text = true
	# No custom_minimum_size either: a floor is a size Control.set_size won't go under,
	# so a button carrying one would keep it when the grid divides into cells smaller
	# than that and spill over its neighbour. The cell's uniform rect (see
	# _fit_cells_uniformly) is the only thing that decides how big a button is.
	b.custom_minimum_size = Vector2.ZERO
	# Fill the cell, so a button is exactly as big as the cell it was placed in.
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The CARD this particular button belongs to, stamped on the button itself. One command may
	# now have SEVERAL bindings — an ability claiming a cell on two cards, a sanction's three
	# levels — so a button's card can no longer be looked up from its name. See
	# RTSController.upate_hud_buttons.
	b.set_meta(BUTTON_FAMILY_META, a_binding.family)
	a_cells[ControlBinding.cell_index(a_binding.grid_position)].add_child(b)
#endregion
