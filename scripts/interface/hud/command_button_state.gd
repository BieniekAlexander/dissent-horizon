class_name CommandButtonState
extends RefCounted

## WHY a command-grid button cannot be pressed right now, and what to draw on it.
##
## One classifier for every kind of button the grid holds — train tools, build tools, verbs
## and abilities alike. Before this, purchases had a five-way per-blocker idiom
## (RTSController's TOOL_TINT_* constants) and abilities had two states, on or greyed, so the
## same "you cannot do this" arrived in two vocabularies depending on which half of the grid
## it came from. The player is asking one question of any darkened button — *what would make
## this work?* — and the answer has to look the same wherever it is asked.
##
## THE BLOCKERS ARE ORDERED BY REMEDY, not by severity, because the remedy is the whole
## message: a LOCKED piece needs a building put up, an UNAFFORDABLE one needs nothing but
## time, and a RECHARGING one needs nothing at all.
##
## WAITABLE IS NOT A BLOCKER, it is a property of one. Holding `modifier_additive` turns a
## refusal waiting can clear into an order that waits — for money, a charge, or a prerequisite
## already going up (see gdd/systems/commands/cooldowns-and-preconditions.md, where one flag,
## `CommandMessage.defer_if_unaffordable`, carries all three). So the button answers what the
## CLICK will do: amber without the modifier — possible, but refused unless queued — and lit
## like any pressable button with it, because then clicking works. The blocker is still
## recorded, since the reason has not changed; only its colour gives way.
##
## Pure and static: it reads a selection and a commander and returns a value. Nothing here
## touches a Control, which is what lets it be tested without a HUD.
##
## Full write-up: gdd/systems/ux/ui/command-card-and-hotkeys.md §What a darkened button means.

#region Blockers
enum Blocker {
	## Pressable now.
	NONE,
	## A prerequisite is missing — a structure to be built, a sanction to be unlocked. Reads
	## as "not yet part of your options".
	LOCKED,
	## The price cannot be met. The piece IS one of your options; you cannot pay today.
	UNAFFORDABLE,
	## Every actor that offers this is waiting on a charge. Needs nothing from the player.
	RECHARGING,
	## Affordable, unlocked — but the commander already fields as many charged aircraft as it
	## has pads, so this one would queue for a deck. A WARNING rather than a refusal: clicking
	## is not refused either way (see Commander.has_spare_docking_capacity).
	NO_PAD,
	## The commander owns nothing that can perform this. Distinct from LOCKED: the ability IS
	## yours, and what is missing is a piece to cast it with — you had the caster and it died,
	## or you unlocked something before building what uses it.
	##
	## Only reachable on the ORDNANCE card, which is the one card that draws a button whether
	## or not anything is selected. Everywhere else a button appears only when the selection
	## already offers its command, so "nobody can do this" cannot arise.
	NO_CASTER,
	## The caster is a building its commander cannot power — infrastructure upkeep exceeds
	## capacity, so it is dark (see Commandable.is_unpowered). A third remedy again: not a
	## purchase, not time, but an infrastructure provider. Never queueable — waiting does not
	## close a shortfall.
	UNPOWERED,
	## "You are here" — a radio button for the option already showing. Not a refusal and not a
	## lack: pressing it would simply do nothing, because it is already done. Its own blocker
	## rather than a reuse of LOCKED, whose grey means "go and build something".
	CURRENT,
}
#endregion

#region State
## Why the button is dark, or NONE.
var blocker: int = Blocker.NONE
## True when the blocker is one waiting can clear, so the order could be queued. Meaningless
## when blocker is NONE.
var is_waitable: bool = false
## True when clicking RIGHT NOW would queue the order rather than refuse it: waitable, and the
## additive modifier is down.
var is_queueable: bool = false
## Charges in the pool this command draws on, and its capacity. Both 0 for a command that is
## not charge-based (every purchase, and every verb without an Abilities pool behind it).
## Drawn on the button only when capacity is above one — "1/1" says nothing a lit button does
## not already say.
##
## THE BUTTON is where these belong, and they were briefly on the info panel instead. A charge
## count answers "can I press this", so it goes on the thing being pressed; putting it in a
## summary makes the player look away from the button to find out about the button.
var charges: int = 0
var max_charges: int = 0
## For a TOGGLE (hold fire): the whole selection has it on. Not a blocker — the button stays
## pressable, and pressing it turns the state off again — so it is drawn as a lit edge rather
## than as a tint.
var is_toggled_on: bool = false
## Physics ticks until the next charge lands, or 0 when nothing is recharging. Ticks rather
## than seconds because that is what Abilities counts in; the HUD converts at the boundary
## (see recharge_seconds).
var recharge_ticks: int = 0
#endregion


#region Derived
## Seconds until the next charge, for display. The tick rate is READ rather than typed, so a
## change to the physics rate cannot silently make every timer on screen wrong.
func recharge_seconds() -> float:
	var rate: int = TimeUtils.ticks_per_second()
	return float(recharge_ticks) / float(rate) if rate > 0 else 0.0


## Whether the button should draw its charge pips. One-charge pools are the common case and
## carry no information — the button being lit already says the charge is there.
func shows_charges() -> bool:
	return max_charges > 1


## Whether the button should draw a countdown. True for a partly-filled pool as well as an
## empty one: the question "when is the next charge" is the same either way.
func shows_timer() -> bool:
	return recharge_ticks > 0


#endregion

#region Appearance
## WHAT EACH BLOCKER LOOKS LIKE. The table lives beside the enum on purpose: keeping the
## reasons in one file and the colours in another is exactly how the purchase idiom and the
## ability idiom drifted apart, and a reason with no stated appearance is a reason that will
## be drawn like whatever was nearest.
##
## The colours are chosen so the REMEDY is legible at a glance, which is the only thing a
## player wants from a dark button:
##
##   LOCKED       flat, colourless dim — "not yet one of your options". Go build something.
##   NO_PAD       desaturated blue, and a WARNING rather than a refusal — clicking works, the
##                aircraft will simply queue for a deck.
##   NO_CASTER    dim teal — the ability is yours and there is nothing to cast it with. A
##                third remedy again: not a building to unlock it, not time, but a PIECE.
##   UNPOWERED    dim amber-brown — the caster is standing there dark. The remedy is an
##                infrastructure provider, and no amount of waiting is one.
##   WAITABLE     amber without the modifier, lit with it — for any blocker waiting can clear
##                (an unmet price, a spent charge, a prerequisite on its way). The one colour
##                that says what the CLICK will do rather than why the button is dark.
##                UNAFFORDABLE and RECHARGING are always waitable, so they have no colour of
##                their own; RECHARGING still draws its countdown.
const TINT_AVAILABLE: Color = Color(1.0, 1.0, 1.0)
const TINT_LOCKED: Color = Color(0.45, 0.45, 0.48)
const TINT_NO_PAD: Color = Color(0.62, 0.74, 0.85)
const TINT_NO_CASTER: Color = Color(0.45, 0.68, 0.66)
const TINT_UNPOWERED: Color = Color(0.72, 0.60, 0.38)
const TINT_CURRENT: Color = Color(0.70, 0.70, 0.74)
const TINT_QUEUEABLE: Color = Color(1.0, 0.78, 0.35)


## Waitability wins over the blocker's own colour wherever it applies, because only it changes
## what the click does.
func tint() -> Color:
	if is_waitable:
		return TINT_AVAILABLE if is_queueable else TINT_QUEUEABLE
	match blocker:
		Blocker.LOCKED:
			return TINT_LOCKED
		Blocker.NO_PAD:
			return TINT_NO_PAD
		Blocker.NO_CASTER:
			return TINT_NO_CASTER
		Blocker.UNPOWERED:
			return TINT_UNPOWERED
		Blocker.CURRENT:
			return TINT_CURRENT
	return TINT_AVAILABLE


#endregion


#region Classification
## The state of `a_command_name` for this selection and commander.
##
## `a_defers` is the LIVE reading of the additive modifier, passed in rather than polled so
## this stays testable and so the caller keeps the one rule about how that modifier is read
## (polled, never latched — see RTSController.additive_modifier_held).
static func of(
	command_name: String,
	selection: Array,
	commander: Commander,
	defers: bool,
	current_context: String = ""
) -> CommandButtonState:
	var state := CommandButtonState.new()
	# A CARD control rather than an order: the radio button for the producer already showing is
	# greyed and unpressable, which is what makes "one is always set" visible.
	if command_name == current_context:
		state.blocker = Blocker.CURRENT
		return state
	if command_name == CommandContextParser.HOLD_FIRE_COMMAND:
		state.is_toggled_on = all_hold_fire(selection)
	var tool: Tool = Tool.for_name(command_name)
	if tool != null and commander != null:
		state._classify_purchase(tool, commander, defers)
	else:
		state._classify_ability(command_name, selection, commander, defers)
	return state


## Whether every piece in `selection` that offers hold fire already holds it — and at least
## one does, since an empty "every" would light a button nobody could have pressed.
static func all_hold_fire(selection: Array) -> bool:
	var offered_by_any: bool = false
	for node: Variant in selection:
		var actor := node as Commandable
		if (
			actor == null
			or not is_instance_valid(actor)
			or not CommandContextParser.commands_for(actor).has(
				CommandContextParser.HOLD_FIRE_COMMAND
			)
		):
			continue
		if not actor.is_holding_fire:
			return false
		offered_by_any = true
	return offered_by_any


## A build or train button: the blocker is a price or a prerequisite, and the commander alone
## can answer it — a purchase is commander-global, never per-actor.
func _classify_purchase(a_tool: Tool, a_commander: Commander, a_defers: bool) -> void:
	var need: TechnologySpec.UnmetNeed = a_commander.get_unmet_need_for(a_tool)
	if need == TechnologySpec.UnmetNeed.NONE:
		# Buyable — but say so when there is no pad free for it. Asked only of pieces that dock,
		# so the scan costs nothing on the 99% of buttons that are not aircraft.
		if a_tool.needs_docking and not a_commander.has_spare_docking_capacity():
			blocker = Blocker.NO_PAD
		return
	if Commander.is_deferrable_need(need):
		blocker = Blocker.UNAFFORDABLE
		_set_waitable(a_defers)
		return
	blocker = Blocker.LOCKED
	# LOCKED would be a lie when the prerequisite is already going up: queued, the builder
	# waits at the site for it.
	if (
		need == TechnologySpec.UnmetNeed.MISSING_STRUCTURE
		and a_commander.missing_prerequisites_are_incoming(a_tool.type)
	):
		_set_waitable(a_defers)


## Mark the blocker as one waiting clears; clicking queues when `a_defers` (the modifier) is down.
func _set_waitable(a_defers: bool) -> void:
	is_waitable = true
	is_queueable = a_defers


## A verb or an ability. Charges are read from the SELECTION, because a pool belongs to the
## piece rather than to the commander (see Abilities) — two Operations Centers each have
## their own, and the button speaks for whichever is readiest.
##
## Recharging is reported only when EVERY offering actor is reloading, matching
## selection_precondition's rule that a command is available as soon as anybody can act on
## it. A mixed selection where one battery is loaded can still fire.
func _classify_ability(
	a_command_name: String, a_selection: Array, a_commander: Commander, a_defers: bool
) -> void:
	var ability_id: StringName = _ability_for_command(a_command_name, a_commander)
	if ability_id == &"":
		_classify_plain_verb(a_command_name, a_selection, a_defers)
		return
	# UNLOCKED FIRST, unconditionally, and the order is the whole rule: THE SANCTION IS THE
	# PERMISSION, and nothing else grants it.
	#
	# It is tempting to skip this when the selection already grants the ability — and that is
	# exactly the mistake, twice over. A piece's `Abilities` pool is authored on the PIECE: a
	# Citadel grants Scan, Freeze, Beacon and Promotion the moment it is built, whether or not
	# the commander has ever spent dominion on any of them. So "something selected can cast it"
	# and "the commander may use it" are different facts, and reading the first as the second
	# drew every unbought sanction lit — with nothing selected because owning the caster
	# short-circuited it, and with the Citadel selected because the pool answered directly.
	if not _is_unlocked(ability_id, a_commander):
		blocker = Blocker.LOCKED
		return
	# WHOSE pool the button speaks for: the SELECTED casters when any are selected, and
	# otherwise every caster the commander owns. The second half is the state the ORDNANCE card
	# is normally read in, and the thing a player wants to know about a global ability is
	# whether it can be used AT ALL right now.
	var readiest: Abilities = _readiest_pool(ability_id, a_selection)
	if readiest == null:
		if a_commander != null:
			readiest = _readiest_pool(ability_id, a_commander.casters_of_ability(ability_id))
		if readiest == null:
			# Unlocked, and nothing to cast it with. A different remedy from LOCKED — a PIECE
			# rather than dominion — so a different blocker and a different colour.
			blocker = Blocker.NO_CASTER
			return
	# UNPOWERED BEFORE CHARGES: a dark building can hold a full pool and still cast nothing,
	# and telling the player to wait for a charge they already have is the wrong instruction.
	if not readiest.is_operational():
		blocker = Blocker.UNPOWERED
		return
	charges = readiest.charges_of(ability_id)
	max_charges = readiest.max_charges_of(ability_id)
	# TIME TO THE NEXT CHARGE, whether or not the pool is empty. A pool at 2 of 3 is still
	# refilling, and "when does the third arrive" is a question the player asks of a button they
	# CAN press — so the countdown is a property of the pool rather than of being blocked.
	# Abilities.recharge_remaining is already 0 at capacity, so a full pool says nothing.
	recharge_ticks = readiest.recharge_remaining(ability_id)
	if charges > 0:
		return
	# Nothing left in the readiest pool, so nothing in any of them.
	blocker = Blocker.RECHARGING
	_set_waitable(a_defers)


## The pool with the most charges left among `a_casters`, or null when none of them grants
## the ability. "Most charges" rather than "the first": a button speaks for whichever caster
## could act, matching selection_precondition's rule that a command is available as soon as
## anybody can act on it.
static func _readiest_pool(ability_id: StringName, casters: Array) -> Abilities:
	var readiest: Abilities = null
	for node: Variant in casters:
		if not (node is Node) or not is_instance_valid(node):
			continue
		var pool := (node as Node).get_node_or_null("Abilities") as Abilities
		if pool == null or not pool.grants(ability_id):
			continue
		if readiest == null or pool.charges_of(ability_id) > readiest.charges_of(ability_id):
			readiest = pool
	return readiest


## Whether the commander may use this ability at all. A dominion-unlocked one must have been
## BOUGHT; anything else (a free ability, one bought at a structure) is unlocked by owning the
## piece, which is the question NO_CASTER answers instead.
static func _is_unlocked(ability_id: StringName, commander: Commander) -> bool:
	if not AbilityCatalog.is_dominion_unlocked(ability_id):
		return true
	if commander == null or commander.sanction_grid == null:
		return false
	return commander.sanction_grid.deployable_entry_for(ability_id) != null


## A command with no ability pool behind it — Radiate and Spot, which are still outside the
## ability module, and any verb whose command class implements a cooldown of its own. Asked
## through the command class exactly as before, so nothing that used to grey stops greying.
func _classify_plain_verb(a_command_name: String, a_selection: Array, a_defers: bool) -> void:
	var command: Script = CommandContextParser.command_for_name(a_command_name)
	if command == null or a_selection.is_empty():
		return
	var offered_by_any: bool = false
	for node: Node in a_selection:
		var actor := node as Commandable
		if actor == null or not is_instance_valid(actor):
			continue
		if not CommandContextParser.commands_for(actor).has(a_command_name):
			continue
		offered_by_any = true
		if not command.actor_is_recharging(actor):
			return
	if offered_by_any:
		blocker = Blocker.RECHARGING
		_set_waitable(a_defers)


## The ability a grid command casts, or &"" when it is not an ability command.
##
## TWO ROUTES REACH THE GRID and both have to be asked, because a command name is derived
## differently on each. An ability that names its own command (the Bombard's battery) is
## found in the catalog. A SANCTION's command name is derived from the sanction's title
## (`Sanction.command_name`), so it is found by walking the commander's own sanctions — the
## same source `CommandContextParser.commands_for` walks to put the button there in the first
## place. Neither is a hand-kept table, which is the point: a second map of command name to
## ability is a second place for one fact to live, and it is the copy that goes stale.
static func _ability_for_command(command_name: String, commander: Commander) -> StringName:
	for id: StringName in AbilityCatalog.ids():
		if AbilityCatalog.command_of(id) == command_name:
			return id
	# Every ordnance command, LOCKED OR NOT. It used to walk the commander's DEPLOYABLE
	# sanctions, which resolved an unlocked one to nothing — so a locked button fell through to
	# the plain-verb path, found no cooldown, and was drawn as available. The commander's card
	# exists to show what you cannot use yet, so the lookup has to answer for those too.
	var binding_id: StringName = AbilityBinding.ability_for_command(command_name)
	if binding_id != &"":
		return binding_id
	if (
		commander == null
		or commander.sanction_grid == null
		or not command_name.begins_with(Sanction.COMMAND_PREFIX)
	):
		return &""
	for sanction: Sanction in commander.sanction_grid.deployable_sanctions():
		if sanction.command_name() == command_name:
			return sanction.ability_id
	return &""
#endregion
