class_name CommandContextParser

## Maps boolean-valued predicates over Entity to the names of commands that
## may be issued to entities matching the predicate. Replaces the previous
## CommandContextRegistry (which keyed pre-built CommandContexts by
## Entity.Type) and CommandContextProvider (whose only job was to look up
## that registry from a component node).
##
## Each rule is a 2-tuple of [predicate, command_name]:
##   - predicate: Callable taking a single Entity and returning bool. The
##     predicate decides whether `command_name` is applicable to that entity.
##     Predicates are intentionally free-form about *what* they inspect — type
##     enum, has_node(...) for a component, group membership, inventory, etc.
##     The contract is just "given an Entity, return a bool", which keeps the
##     table easy to refactor later if we standardize on one signal.
##   - command_name: String. The command's conventional name. Verb commands
##     (e.g. "command_attack_move") match the controller's input actions; tool
##     names (e.g. "command_tool_irregular") are HUD/registry ids defined in Tool
##     and are NOT input actions. Non-hotkey commands (Attack, Train, Interact,
##     ...) are also listed under "command_<verb>" names so the parser is the
##     single source of truth for the command set a unit supports.
##
## Example entry shape:
##   [func(e: Entity): return e.live_movement() != null, "command_attack_move"]

## Tool names come from the Tool registry, filtered per control context +
## per-entity capability by tools_for(entity, context) below (ControlBinding.ControlContext
## is the single build/train/act vocabulary, shared with RTSController). They used
## to be hardcoded here as two name lists; the registry is the source of truth.

## HOLD FIRE is a pseudo-command: no class, never queued. Pressing it sets
## Commandable.is_holding_fire on each armed piece in the selection and nothing else. Named
## here because the controller answers it and the button classifier reads it.
const HOLD_FIRE_COMMAND: String = "command_hold_fire"


## The ability whose AUTOCAST a right-click on `command_name`'s button toggles, or &"" for a
## button whose right-click means something else. Only the Bombard today — the one ability a
## piece fires without an order of its own (Bombard.autofire_on) — reached from its own
## buttons and from Spot's, the order whose beacon it answers.
static func autocast_ability_of(command_name: String) -> StringName:
	return Bombard.ABILITY_ID if command_name in ["command_bombard", "command_spot"] else &""


#region Private helpers
## Built lazily on first lookup to match the lazy pattern the old
## CommandContextRegistry used (script-class resolution order is fragile at
## static-var init time). Note that the structures' *train tools* are no longer
## in this table — they're sourced per-entity from the Production component via
## tools_for(entity, ControlContext.TRAIN), folded into commands_for() below.
static var _rules: Array


## Whether `a_entity` has something to shoot WITH — a Loadout actually holding a Weapon, or
## a bunker garrison whose occupants' fire it propagates (Commandable.is_armed).
##
## Reads the NODE rather than `Entity.weapon_inventory`, which is `@onready` and so still
## null for an entity that has never entered the tree — a build preview, a test fixture. A
## predicate in this table must answer for those too.
## Whether `entity` is offered hold fire — it has something to hold. Asked by the button and
## by every place that draws the hold, so an unarmed piece holding fire (stealth sets it on
## anything) shows nothing, the same way it is offered no button.
static func offers_hold_fire(entity: Entity) -> bool:
	return _is_armed(entity)


static func _is_armed(a_entity: Entity) -> bool:
	var loadout := a_entity.get_node_or_null("Loadout") as Loadout
	if loadout != null and loadout.has_weapons():
		return true
	var commandable := a_entity as Commandable
	return commandable != null and commandable.is_armed()


## Whether `a_entity` can be sent somewhere: it moves, and is not on rails
## (Commandable.is_on_rails).
static func _goes_where_ordered(a_entity: Entity) -> bool:
	var commandable := a_entity as Commandable
	return (
		a_entity.live_movement() != null and not (commandable != null and commandable.is_on_rails())
	)


static func _build_rules() -> Array:
	return [
		[CommandContextParser._goes_where_ordered, "command_move"],
		[
			func(e: Entity): return e.live_movement() != null or e.has_node("Loadout"),
			"command_stop"
		],
		[func(e: Entity): return e.has_node("Loadout"), "command_attack"],
		# ATTACK-MOVE NEEDS SOMETHING TO SHOOT WITH, not merely a Loadout node. An unarmed
		# vehicle carries an empty one, and offering it an attack-move handed it an order it
		# could never carry out: the click resolves to Attack the moment it lands on a
		# Commandable (RTSController._resolve_hotkey_command), and Attack on a weaponless actor
		# can never act and never moves, so the unit stood still holding a dead order.
		#
		# CRUSHING IS NOT A WEAPON. A truck flattens what it drives over as a physics contact,
		# with no aim, no range and no intent — so it must not read as a reason to offer an
		# attack order. See Commandable._tick_crush.
		#
		# TODO: `command_attack` and `command_defend` above/below still gate on the Loadout NODE
		# and have the same defect — an unarmed truck is offered an Attack button that does
		# nothing. Not changed here because only attack-move was asked for, and because the
		# bunker case needs a decision first: Commandable.is_armed() counts a garrison holding
		# armed occupants, so gating those two on _is_armed would make a shelter's attack button
		# appear and disappear as it is loaded and emptied.
		# Offered on rails too: there the button only attacks a TARGET, since the ground click
		# is refused (AttackMove.meets_precondition) — the one way to order an attack on a piece
		# a plain click would not attack, such as a friendly.
		[CommandContextParser._is_armed, "command_attack_move"],
		# Anything with a weapon can hold its fire; an offensive ABILITY is not a weapon.
		[CommandContextParser._is_armed, HOLD_FIRE_COMMAND],
		# Shooting at a PLACE needs more than a Loadout: the weapon has to be allowed at the
		# ground layer and has to deliver its damage with a projectile, since melee damage has
		# no entity at a bare point to land on (see Weapon.can_fire_at_ground).
		[CommandContextParser._can_focus_fire, "command_focus_fire"],
		[CommandContextParser._goes_where_ordered, "command_patrol"],
		[
			func(e: Entity):
				return CommandContextParser._goes_where_ordered(e) and e.has_node("Loadout"),
			"command_defend"
		],
		[func(e: Entity): return e.has_node("Production"), "command_train"],
		# NO rally entry for Production. A producer accepts a bare MoveCommand as a RALLY
		# (Commandable._absorb_rally_commands) and always did, but that is resolved by the
		# right-click ladder, which never consults this table — so advertising `command_move`
		# here only ever put a GO BUTTON on the card of a building that cannot go anywhere.
		# It also made every stationary producer report an ACTIVE command, which is what put a
		# barracks on a card holding one dead button and hid its training behind the toggle.
		# A producer that CAN move gets `command_move` from the Movement rule above, like
		# anything else that moves, so a mobile producer still reaches both cards.
		[func(e: Entity): return e.has_node("Builds"), "command_ability"],
		[func(e: Entity): return e.has_node("Builds"), "command_build"],
		# Finishing a placed structure is the second half of a build order, so it belongs to
		# the same component — a unit that can raise a building can also walk over and finish
		# one a co-builder started.
		[func(e: Entity): return e.has_node("Builds"), "command_assemble"],
		# Mending a damaged friendly is its own capability (see Repairs). Presence of the
		# component is the whole per-ACTOR question; WHICH targets it applies to is decided
		# per-target in Repair.repairable_cause, the same division Occupy uses below.
		[func(e: Entity): return e.has_node("Repairs"), "command_repair"],
		# Colonial bombardment: a Spotter calls solutions in; a battery spends them. Neither
		# is offered to the other. The battery half is an ABILITY rather than a component of
		# its own, so the question is what the piece is granted, not what nodes it carries.
		[CommandContextParser._can_spot, "command_spot"],
		# Plant and Detonate share a cell: a Sapper offers Plant while it has no charge in play,
		# and Detonate while it has; a planted charge offers Detonate. Which one the SELECTION
		# draws is the controller's (RTSController.selection_commands).
		[CommandContextParser._can_plant, "command_plant"],
		[CommandContextParser._can_detonate, "command_detonate"],
		[CommandContextParser._can_bombard, "command_bombard"],
		[CommandContextParser._can_irradiate, "command_launch"],
		# Any unit with an Interactor advertises the generalised interact command;
		# the specific targets it applies to come from the interactor's list
		# (replaces the former per-type pick_up / drop_off / collect rules).
		[func(e: Entity): return e.has_node("Interactor"), "command_interact"],
		# Occupy applies to anything that can move (see _can_occupy); WHICH garrisons will
		# take it is the target garrison's own occupancy masks, checked per-target in
		# Occupy.meets_precondition rather than per-actor here.
		[CommandContextParser._can_occupy, "command_occupy"],
		# The other side of the same mechanic: a commandable that HOLDS units can call one in.
		# This is the ENTRY direction, so it asks is_closed() and NOT the question Evacuate
		# asks — the two directions of the door are separate statements (the Compound takes
		# nobody by order and still lets its Servants out). WHICH unit it will take is the
		# host's masks, per-target in Embark.meets_precondition.
		[CommandContextParser._can_embark, "command_embark"],
		# Commandables whose occupants may be ordered OUT can order an evacuation
		# (Garrison.can_release — see _can_evacuate).
		[CommandContextParser._can_evacuate, "command_evacuate"],
		# A unit that can plant itself offers ONE of Deploy and Undeploy, by the form it is
		# heading for: so a selection holding any unit not planted draws Deploy, and a
		# selection all planted draws Undeploy (the two share a cell — CommandGrid).
		[CommandContextParser._can_deploy, "command_deploy"],
		[CommandContextParser._can_undeploy, "command_undeploy"],
		# HOVERING units that are not already permanently grounded can land.
		[CommandContextParser._can_land, "command_land"],
		# Aerial units whose weapons must be recharged externally can be sent to an airfield.
		[CommandContextParser._can_rearm, "command_rearm"],
		# A standing order to keep working a Shelter (see unit-tasking.md). This predicate only
		# asks "could this entity ever hold captives at all"; WHICH Shelter it can be tasked on
		# is a target question, per-order in TaskShelter.meets_precondition.
		[CommandContextParser._can_task_shelter, "command_task_shelter"],
	]


## Radiate and Spot are ordinary granted abilities, asked the same way Bombard is. Both used
## to have a component of their own — an `Inventory` of `ToolSpec`s for one, a bare `Spotter`
## marker for the other — which is what the ability module fold retired.
static func _can_irradiate(e: Entity) -> bool:
	return _grants(e, &"irradiate")


static func _can_spot(e: Entity) -> bool:
	return _grants(e, &"spot")


static func _can_plant(e: Entity) -> bool:
	return _grants(e, Plant.ABILITY_ID) and PlantedCharge.planted_by(e) == null


static func _can_detonate(e: Entity) -> bool:
	return e is Commandable and Detonate.charge_of(e as Commandable) != null


static func _grants(e: Entity, ability_id: StringName) -> bool:
	var abilities := e.get_node_or_null("Abilities") as Abilities
	return abilities != null and abilities.grants(ability_id)


## Bombard applies to a piece granted the bombard ability. Whether it is LOADED is a
## separate question, asked per-order in Bombard.meets_precondition — an empty pool greys
## the button rather than removing it (see cooldowns-and-preconditions.md).
static func _can_bombard(e: Entity) -> bool:
	var abilities := e.get_node_or_null("Abilities") as Abilities
	return abilities != null and abilities.grants(Bombard.ABILITY_ID)


## Occupy applies to entities that can move at all. The mode no longer gates it here:
## a garrison declares which locomotion styles it accepts (Garrison.occupiable_movements),
## so whether a specific host will take this unit is decided against that host in
## Occupy.meets_precondition. This predicate only answers "could this entity ever
## occupy something", which is what the HUD button's visibility is about.
static func _can_occupy(e: Entity) -> bool:
	return e.live_movement() != null


## Embark applies to a garrison a unit could be ordered INTO — anything but a closed hold.
## The entry half of the door Evacuate opens from the other side; the two are asked
## separately because a hold can take nobody by order and still let its occupants go.
static func _can_embark(e: Entity) -> bool:
	var garrison := e.get_node_or_null("Garrison") as Garrison
	return garrison != null and not garrison.is_closed()


## Evacuate applies to a garrison whose occupants can be let out by order — `releasable`,
## which is a different question from is_closed(). Which occupants leave is per-occupant
## (Garrison.can_release_occupant): the host's own side, never a captive.
static func _can_evacuate(e: Entity) -> bool:
	var garrison := e.get_node_or_null("Garrison") as Garrison
	return garrison != null and garrison.can_release()


## FocusFire applies to anything carrying a weapon that can be aimed at bare ground. The
## Loadout is walked here rather than trusting `has_node("Loadout")` because an unarmed
## bunker and a melee-only unit both have one and neither can shell a point.
static func _can_focus_fire(e: Entity) -> bool:
	var loadout := e.get_node_or_null("Loadout") as Loadout
	return loadout != null and loadout.can_fire_at_ground()


static func _can_deploy(e: Entity) -> bool:
	var deployable: Deployable = Deployable.of(e)
	return deployable != null and not deployable.settles_deployed()


static func _can_undeploy(e: Entity) -> bool:
	var deployable: Deployable = Deployable.of(e)
	return deployable != null and deployable.settles_deployed()


static func _can_land(e: Entity) -> bool:
	var aerial: Aerial = Aerial.of(e)
	return (
		aerial != null
		and aerial.mode == Movement.Mode.HOVERING
		and not aerial.is_permanently_grounded()
	)


## Rearm applies to airfield-using aircraft carrying at least one CHARGED weapon — the ones
## that cannot reload themselves and must dock. Only the capability is asked here, as
## everywhere in this table; WHICH airfield will take the unit is the target bay's own
## question, answered per-target in Rearm.meets_precondition.
static func _can_rearm(e: Entity) -> bool:
	if Docking.of(e) == null or Aerial.of(e) == null:
		return false
	var loadout := e.get_node_or_null("Loadout") as Loadout
	return loadout != null and loadout.has_charged_weapons()


## TaskShelter applies to anything with a Garrison that can hold captives at all — the same
## capacity check TaskShelter.meets_precondition asks of the actor.
static func _can_task_shelter(e: Entity) -> bool:
	var garrison := e.get_node_or_null("Garrison") as Garrison
	return garrison != null and garrison.capacity > 0


static func _rules_table() -> Array:
	if _rules == null or _rules.is_empty():
		_rules = _build_rules()
	return _rules


#endregion

#region Command identity
## The command NAME each MoveCommand subclass answers to — the inverse of the rules
## table above, and the only place a live command can be turned back into the name the
## predicates are keyed by.
##
## It lives here rather than as a static on each command class for the reason stated at
## the top of this file: the parser is the single source of truth for the command set a
## unit supports, and a name declared on the class would be a second, drifting copy of
## the same fact. Built lazily for the same reason `_rules` is — referencing the command
## classes at static-init time is fragile.
##
## Commands absent from the table (Wander, Capture) have no entry in the rules table
## either: nothing offers them as a player-issuable capability, so there is no
## capability question to ask about them. `name_for` returns "" and `actor_can_perform`
## treats that as portable.
static var _command_names: Dictionary


static func _build_command_names() -> Dictionary:
	return {
		MoveCommand: "command_move",
		Stop: "command_stop",
		Attack: "command_attack",
		AttackMove: "command_attack_move",
		FocusFire: "command_focus_fire",
		Patrol: "command_patrol",
		Defend: "command_defend",
		Train: "command_train",
		Build: "command_build",
		Assemble: "command_assemble",
		Repair: "command_repair",
		Ability: "command_ability",
		Interact: "command_interact",
		Occupy: "command_occupy",
		Embark: "command_embark",
		Evacuate: "command_evacuate",
		Deploy: "command_deploy",
		Undeploy: "command_undeploy",
		Land: "command_land",
		Rearm: "command_rearm",
		Spot: "command_spot",
		Plant: "command_plant",
		Detonate: "command_detonate",
		Bombard: "command_bombard",
		TaskShelter: "command_task_shelter",
	}


static func _command_names_table() -> Dictionary:
	if _command_names == null or _command_names.is_empty():
		_command_names = _build_command_names()
	return _command_names


## The rules-table name for a live command, or "" when it has none.
static func name_for(command: MoveCommand) -> String:
	if command == null:
		return ""
	return _command_names_table().get(command.get_script(), "")


## The command CLASS a rules-table name belongs to, or null. The other direction of
## `name_for`, for callers holding a button rather than a command — the HUD asking whether
## the ability a button offers is recharging.
static func command_for_name(name: String) -> Script:
	for script: Script in _command_names_table():
		if _command_names_table()[script] == name:
			return script
	return null


## Whether `a_actor` is CAPABLE of carrying out `a_command` — a question about the actor's
## components alone, deliberately NOT about whether it could succeed right now. A command
## whose target has wandered off or whose site is momentarily blocked is still one this
## unit can perform; `meets_precondition` answers that other question and is the wrong
## test for portability.
##
## This is what makes a unit TRANSFORMATION able to carry its orders across (see
## CommandReceiver.portable_chain_for): a Warlord has no Builds component, so an
## Irregular's queued Build is not portable, while its queued Move is.
static func actor_can_perform(actor: Commandable, command: MoveCommand) -> bool:
	var name: String = name_for(command)
	if name.is_empty():
		return true
	return commands_for(actor).has(name)


#endregion


#region Public API
## Returns the deduplicated list of command names applicable to a single
## entity, preserving the order they appear in the rules table. Returns an
## empty array for a null / invalid entity rather than erroring — callers
## (the HUD, the controller's hotkey gate) treat "no entity → no commands"
## as the non-selection state.
static func commands_for(entity: Entity) -> Array:
	var result: Array = []
	if entity == null or not is_instance_valid(entity):
		return result
	for rule in _rules_table():
		var predicate: Callable = rule[0]
		var command_name: String = rule[1]
		if not result.has(command_name) and predicate.call(entity):
			result.append(command_name)
	# Sanction abilities are per-COMMANDER data, not a static capability of the piece: the
	# same Operations Center offers Scan only once its commander has unlocked it. So they
	# cannot live in the rules table above (predicates see only the Entity) and are appended
	# here, read off the commander's sanction grid.
	# Ordered so the CHEAP, always-safe checks come first: Entity.commander reads through
	# the Ownership component, which a bare out-of-tree node has not resolved yet.
	var caster := entity as Commandable
	if (
		caster != null
		and caster.get_node_or_null("Abilities") != null
		and caster.ownership != null
		and caster.commander != null
	):
		for sanction: Sanction in caster.commander.sanctions_castable_by(caster):
			var sanction_command: String = sanction.command_name()
			if not result.has(sanction_command):
				result.append(sanction_command)

	# The train tools a producer offers come from its Production component, not a
	# static type table — so a structure advertises exactly what it can build.
	for tool_name in tools_for(entity, ControlBinding.ControlContext.TRAIN):
		if not result.has(tool_name):
			result.append(tool_name)
	return result


## Union of `commands_for` across a selection. A command is available to the
## selection if *any* member can issue it — matches the original
## CommandContext.merge behavior, which OR'd evaluators across selected
## types.
static func commands_for_selection(entities: Array) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for e in entities:
		if not (e is Entity) or not is_instance_valid(e):
			continue
		for command_name in commands_for(e):
			if not seen.has(command_name):
				seen[command_name] = true
				result.append(command_name)
	return result


## Convenience predicate the controller calls for the HUD-button visibility
## check and the "is this hotkey allowed right now" gate inside
## process_command(). Equivalent to `command_name in commands_for(entity)`
## but written out for readability at call sites.
static func command_available(command_name: String, entity: Entity) -> bool:
	return commands_for(entity).has(command_name)


## The tool command names available to `a_entity` in the given control context(s),
## in menu order. Single context-filtered query that replaces the former
## build_tools_for / train_tools_for split:
##   - candidate tools are those whose control_context intersects `a_context`
##     (Tool.tools_in_context);
##   - each is then gated by the component that owns that capability — BUILD tools
##     by the entity's Builds (via Build.tool_applies_to), TRAIN tools by its
##     Production (can_produce) — so the menu can never advertise a tool the
##     command would reject.
## The gate DISPATCH lives here; the gate logic itself stays in Build / Production.
## Returns empty for a null/invalid entity, or one lacking the relevant component.
static func tools_for(entity: Entity, context: int) -> Array:
	var result: Array = []
	if entity == null or not is_instance_valid(entity):
		return result
	var production := entity.get_node_or_null("Production") as Production
	for tool: Tool in Tool.tools_in_context(context):
		if (tool.control_context & ControlBinding.ControlContext.BUILD) != 0:
			if Build.tool_applies_to(tool.command_name, entity):
				result.append(tool.command_name)
		elif (tool.control_context & ControlBinding.ControlContext.TRAIN) != 0:
			if production != null and production.can_produce(tool.type):
				result.append(tool.command_name)
	return result


## Union of `tools_for` across a selection, in menu order — the same "any member can" rule
## `commands_for_selection` applies to verbs.
##
## The build sub-menu has to be answered for the SELECTION, not for whichever entity
## happens to sit at selection[0]. Asking the lead alone made the menu depend on click
## ORDER: a builder picked first listed its structures, the same builder picked second
## listed none, and the Build button was on show either way. The order in which a player
## assembles a group is not a statement about what they want to do with it.
##
## Ordering follows the Tool registry (tools_for walks it), so the menu is stable however
## the selection was assembled — it is a de-duplicating union, not a concatenation.
static func tools_for_selection(entities: Array, context: int) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for e in entities:
		if not (e is Entity) or not is_instance_valid(e):
			continue
		for tool_name in tools_for(e as Entity, context):
			if not seen.has(tool_name):
				seen[tool_name] = true
				result.append(tool_name)
	return result
#endregion
