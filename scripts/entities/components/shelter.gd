class_name Shelter
extends Node
## Shelter component — the neutral structure that houses the land's inhabitants.
##
## A shelter slowly repopulates itself: every [spawn_interval] seconds it produces a
## neutral Terrestrial ([terrestrial_scene]) placed on the navmesh beside the building
## and issues it a [Wander] anchored on the shelter's centre, so its residents mill
## around outside without ever pathing through the footprint (a structure's cells are
## excluded from the navmesh).
##
## Every produced resident is REGISTERED here and stays registered until it leaves the
## world in any way — killed, taken prisoner by a Stock Truck, liberated into an Irregular
## by a Warlord, or captured by some future mechanic. The spawn timer parks (stops
## decrementing) while [capacity] residents are registered, so a shelter left alone
## settles at a steady population and only starts producing again once a player takes
## someone away.
##
## The shelter itself is no longer a target for interactions — factions capitalize on
## its residents, not on the building (see [Liberator] for the anarchical route and
## Garrison.can_capture for the colonial one).

#region Properties
## The neutral unit produced. Authored per scene; production is a no-op when null.
@export var terrestrial_scene: PackedScene

## Seconds between productions.
@export var spawn_interval: float = 30.0

## How many living residents this shelter sustains. The countdown holds at its
## current value while this many are registered.
@export var capacity: int = 3

## Seconds remaining until the next production. Initialised to [spawn_interval] on
## ready and decremented each physics tick, except while at capacity.
var _remaining: float = 0.0

## The living residents this shelter has produced. Entries are dropped when the unit
## leaves the tree (death / capture / liberation) or changes hands.
var _residents: Array[Commandable] = []
#endregion


#region Public API
## Living residents currently attributed to this shelter (read-only view — callers must
## not mutate the returned array). What [TaskShelter] claims from, oldest-registered first.
func residents() -> Array[Commandable]:
	return _residents


## Living residents currently attributed to this shelter.
func resident_count() -> int:
	return _residents.size()


## True while the shelter is at capacity — the state in which the spawn timer parks.
func is_full() -> bool:
	return _residents.size() >= capacity


## Attribute [a_resident] to this shelter. Idempotent. The unit is dropped again the
## moment it leaves the scene tree, which covers every way it can be taken out of
## play: killed (queue_free), captured (removed from the tree into a Garrison), or
## liberated (freed and replaced by an Irregular).
func register(a_resident: Commandable) -> void:
	if a_resident == null or not is_instance_valid(a_resident) or _residents.has(a_resident):
		return
	_residents.append(a_resident)
	a_resident.tree_exiting.connect(unregister.bind(a_resident), CONNECT_ONE_SHOT)


## Stop attributing [a_resident] to this shelter, freeing a slot for the next
## production. Safe to call for a unit that was never registered.
func unregister(a_resident: Commandable) -> void:
	_residents.erase(a_resident)


#endregion


#region Lifecycle
func _ready() -> void:
	_remaining = spawn_interval


func _physics_process(a_delta: float) -> void:
	_prune()
	var host: Entity = _host()
	# Scene-placed structures self-initialize deferred, so `map` is null for the
	# first frames — don't burn the countdown before a production could happen.
	if host == null or host.map == null:
		return
	if is_full():
		return
	_remaining = maxf(0.0, _remaining - a_delta)
	if _remaining <= 0.0:
		_produce_resident(host)
		_remaining = spawn_interval


@onready
var temp_label: Label3D = get_parent().find_child("TempLabel") if get_parent() != null else null


func _process(_a_delta: float) -> void:
	if temp_label != null:
		temp_label.text = "Shelter %d/%d (%ds)" % [resident_count(), capacity, int(_remaining)]


#endregion


#region Private helpers
func _host() -> Entity:
	return get_parent() as Entity


## Drop residents that were freed without a tree_exiting we saw, or that changed
## hands (a capture that leaves the unit in place rather than replacing it) — either
## way they are no longer this shelter's population.
func _prune() -> void:
	var host_id: int = _commander_id_of(_host())
	_residents = _residents.filter(
		func(r: Commandable) -> bool: return is_instance_valid(r) and _commander_id_of(r) == host_id
	)


## Owning commander id of [a_node], resolved through its Ownership child rather than
## the Entity.commander_id shim — the shim reads an @onready that never resolves for an
## out-of-tree instance (same reason Entity._apply_team_tint resolves it this way).
static func _commander_id_of(node: Node) -> int:
	var own := node.get_node_or_null("Ownership") as Ownership if node != null else null
	return own.commander_id if own != null else 0


## Place one Terrestrial on the navmesh beside the shelter, register it, and set it
## wandering around the building. add_entity snaps the spawn to the nearest navigable
## point, so the resident never lands inside the footprint.
func _produce_resident(a_host: Entity) -> void:
	if terrestrial_scene == null:
		return
	var resident := terrestrial_scene.instantiate() as Commandable
	if resident == null:
		push_error("Shelter: terrestrial_scene is not a Commandable")
		return
	var anchor: Vector3 = a_host.global_position
	a_host.map.add_entity(resident, VU.inXZ(anchor), a_host.commander)
	register(resident)
	resident.update_commands(Wander.new(CommandMessage.new(a_host.map, null, null, anchor)))
#endregion
