## Abstracts the set of arguments that can be provided to a command
class_name CommandMessage

#region Properties
var map: Map  # the game map, passed for gamestate checks
var target: Entity  # The entity which will be the recipient of the command
## Any potential thing that is used in the fulfillment of a command. Always CONCRETE
## (Tool.resolved):
## a tool whose piece has variants is stored bound to one — the default unless a caller bound
## another —
## so nothing downstream reads a build order and has to ask which variant it means.
var tool: Tool:
	set(value):
		tool = value.resolved() if value != null else null
# The raw position at which the command is requested (NOTE: `target` might not always be relevant)
var world_position: Vector3
var ability_type: Variant  # For Ability commands: which Ability.Type to invoke (null otherwise)
## For UseSanction: WHICH sanction is being cast. Carried on the message rather than baked
## into a command subclass because sanctions are authored data — a faction adds one by
## writing a doc, and one command class serves every one of them.
var sanction: Sanction = null
# Largest aggro shape in the issuing group (Defend); null → each unit uses its own
var aggro_shape: CollisionShape3D

## Where `aggro_shape` is centred, in world space, or null to use the shape node's own
## origin. A Vector3.
##
## It exists because the two are not the same thing for a Defend: the shape is a template
## (often the defender's OWN AggroRange node, which follows the defender around) while the
## region it stands for is pinned to the POST. Attack reads both to leash an engagement to
## the area it was acquired in — see Attack._target_within_leash.
var aggro_center: Variant = null

## Identity token for the one player order this snapshot belongs to (minted per call
## in RTSController.assign_command_to_units), or null. Every per-unit snapshot from
## the same order points at the same object, so `is_same(a.origin, b.origin)`
## identifies sibling units sharing one command — used by MoveCommand's periodic
## destination-swap check to find swap candidates.
##
## NOTHING here reads the token's fields; only its object identity matters. It must
## therefore be an object allocated fresh per order — never a reused, long-lived
## message such as RTSController's own `command_message` member, or separate orders
## become indistinguishable and units swap destinations across unrelated commands.
var origin: CommandMessage = null

## The queued PURCHASE that pays for this command's action, or null when the command
## costs nothing (or was issued outside the production queue). Set on a Build order, and
## deliberately shared by every builder in it — deep_copy carries the same reference into
## each per-unit snapshot — so a multi-select build is one purchase however many units
## walk to the site. Commands holding a transaction register as holders of it (see
## MoveCommand._init), which is what refunds a reserved cost when an order is abandoned.
var transaction: PurchaseTransaction = null

## BUILD only — the blueprint this order raised at its site: a real, owned, selectable
## structure in the PLANNED state (see Actor.plan_construction), which the builder
## commits in place on arrival instead of instantiating a new one. Like `transaction` it
## is SHARED by every builder's snapshot, so one order means one blueprint however many
## units are walking toward it. Null for a build issued outside the HUD (scenario events,
## tests), which instantiate their structure at placement time as before.
var planned_structure: Actor = null

## BUILD only — how the structure is to be turned when it is laid, as Fixture.quarter_turns
## (0…3, counter-clockwise from above; 0 faces +Z). The footprint the order claims is the tool's
## dimensions turned by this. An integer, so a recorded order carries no float. Default 0 is what
## every order that never chose a facing — scenario events, the bot — has always meant.
var quarter_turns: int = 0

## True when an unaffordable purchase issued by this command should be QUEUED rather
## than refused — the ADDITIVE MODIFIER (RTSController._purchase_defers). Read by
## Train/Build.meets_precondition, which passes it to Commander.get_blocking_need.
##
## Carried on the message rather than read from the controller at precondition time
## because preconditions are static and are evaluated for actors that have no route back
## to the HUD — the bot's actuator and scenario events among them. Those build their own
## messages and leave this at its default.
##
## DEFAULTS TO TRUE: everything that isn't a player order through the HUD keeps the
## original always-defer behavior. The controller is the only thing that sets it false.
var defer_if_unaffordable: bool = true

## True when this command was issued as a multi-unit group move that capped every
## capable unit's Movement.speed_cap to the slowest member's speed (see
## RTSController.assign_command_to_units). Informational — the cap itself lives on
## each unit's Movement, not this message.
var match_group_speed: bool = false

## Minimum target priority this command's aggro will engage: a target whose own
## Entity.target_priority ranks WORSE (higher-valued) than this is ignored. Defaults to
## NON_COMBAT_UNITS, so aggro chases armed things and unarmed units but skips unarmed
## structures unless a command explicitly widens it (Defend always does — Defend._init).
## See Actor.get_aggro_near_position.
var target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_UNITS

## When true, the commandable pursues this command to completion regardless of the
## "still worth it?" checks that MoveCommand.get_updated_state runs while `not persist`.
## Defaults false; e.g. idle-aggro acquisition sets it true so a guarding unit
## chases the target it spotted even after the target leaves its aggro range.
var persist: bool = true

## Emitted when the last MoveCommand holding this message releases it, signalling
## that no live commands still reference this snapshot.
signal unreferenced

var _ref_count: int = 0
## Where `target` last stood in the world, or null before it has been read there. Kept because
## a target can leave the tree and come back — a unit garrisoned in a host — and while it is
## held its global_position cannot be read, so a command aimed at it holds where it went.
var _target_last_seen: Variant = null

var position: Vector3:
	get:
		# Keep the target's real Y (its terrain height), not a zeroed ground plane,
		# so position-based renderers (waypoint + command-line indicators) sit at
		# the target's height instead of a constant Y=0. xz_position drops Y anyway,
		# and nav targets snap to the navmesh, so those consumers are unaffected.
		if target == null or not is_instance_valid(target):
			return world_position
		if target.is_inside_tree():
			_target_last_seen = target.global_position
		return _target_last_seen if _target_last_seen != null else world_position

var xz_position: Vector2:
	get:
		return VU.in_xz(position)
#endregion


#region Lifecycle
func _init(
	a_map: Map,
	a_target: Entity = null,
	a_tool: Tool = null,
	a_world_position: Vector3 = Vector3.ZERO,
	a_ability_type: Variant = null
) -> void:
	map = a_map
	target = a_target
	tool = a_tool
	world_position = a_world_position
	ability_type = a_ability_type


#endregion


#region Public API
func retain() -> void:
	_ref_count += 1


func release() -> void:
	_ref_count -= 1
	if _ref_count <= 0:
		unreferenced.emit()


func clear() -> void:
	target = null
	tool = null
	ability_type = null
	transaction = null
	planned_structure = null


static func deep_copy(message: CommandMessage) -> CommandMessage:
	# `target` can go stale: rally_commands are long-lived templates (kept until the player
	# re-authors the rally point — see Actor.rally_commands), so a rallied MoveCommand's
	# target can die and be FREED long before the template is ever duplicated. Unlike a plain
	# null check, passing an already-freed Object straight into CommandMessage.new()'s typed
	# `a_target: Entity` parameter crashes outright ("previously freed... not a subclass of the
	# expected class") rather than just yielding null back — so this has to be resolved before
	# the call, not after. `position` already falls back to `world_position` when target is
	# null, so a copy with a scrubbed target still points somewhere sensible.
	var live_target: Entity = message.target if is_instance_valid(message.target) else null
	var copy := CommandMessage.new(
		message.map, live_target, message.tool, message.world_position, message.ability_type
	)
	copy.persist = message.persist
	copy._target_last_seen = message._target_last_seen
	copy.quarter_turns = message.quarter_turns
	# A region shape can be freed while messages still name it — a Defend region once its last
	# lease is released, a unit's own aggro shape once the unit dies — and assigning a freed
	# object to the typed field errors, so it is scrubbed like `target` above.
	copy.aggro_shape = message.aggro_shape if is_instance_valid(message.aggro_shape) else null
	copy.aggro_center = message.aggro_center
	copy.target_priority = message.target_priority
	copy.origin = message.origin
	copy.match_group_speed = message.match_group_speed
	copy.defer_if_unaffordable = message.defer_if_unaffordable
	copy.sanction = message.sanction
	# Shared, NOT copied: every snapshot of one build order points at the same purchase
	# and at the same blueprint.
	copy.transaction = message.transaction
	copy.planned_structure = message.planned_structure
	return copy
#endregion
