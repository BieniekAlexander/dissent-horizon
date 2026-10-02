class_name Beacon
extends Node

## Beacon component: its host is a firing solution standing on the map — while one exists,
## its owner's Bombards may drop a shell on it from anywhere, and the shot that uses it
## CONSUMES it.
##
## Two things place one — a [Spotter] unit that walked over and called it in, and the
## Beacon Drop sanction — and both produce the same piece, so the Bombard never has to know
## which. What differs between them is only how long it lasts and whether it can see:
##
## | Placed by | Lifespan | Sight |
## | --- | --- | --- |
## | a Spotter | until consumed, or until the spotter is re-ordered | none (the spotter is standing
## there) |
## | Beacon Drop 1 | 15 seconds | none |
## | Beacon Drop 2 | 15 seconds | radius 2 |
## | Beacon Drop 3 | until consumed | radius 2 |
##
## A beacon may be ATTACHED to a grounded enemy MECH unit (see [method can_carry]): it then
## moves with that unit, so a shell tracking it follows the unit — until the beacon leaves
## play, when the shell lands where the beacon last was. A carrier that dies or leaves the
## map leaves the beacon standing where it last was, as an ordinary point beacon.
##
## A shot does not spend its beacon on FIRING: it MARKS it used (no other battery may spend
## it, and its owner's side sees the change) and the beacon is dismissed when the shell
## lands. Opponents see no change — and a beacon is STEALTHED to them: only a detector shows
## it. See gdd/systems/combat/bombardment.md §Beacons.
##
## The host is a plain Entity so it can be OWNED (the strike check is per-commander), carry
## vision through the ordinary fog path, and be found by a group scan. It has no Defense,
## Selectable or TargetBody, so it cannot be shot, clicked or ordered — killing a beacon is
## done by killing the spotter that called it. A component rather than the host's class, like
## Shelter; `Beacon.of` finds it.

## Every live beacon PIECE, for BombardTargeting's scan. A group rather than a commander-side
## list because a beacon may outlive the thing that placed it.
const GROUP: StringName = &"beacon"

## The scene every placer instantiates. Held here so a Spot command and a Beacon Drop
## sanction cannot drift onto two different beacon scenes.
const SCENE: PackedScene = preload("res://scenes/entities/beacon.tscn")

## How close a bombardment order must land to spend this beacon. A beacon marks a POINT,
## but a player clicking one is aiming at a target beside it, so the strike is allowed
## anywhere within this radius and lands where clicked.
const STRIKE_RADIUS: float = 3.0

## How close to a Beacon Drop's landing point a unit must be for the dropped beacon to
## attach to it rather than stand on the ground.
const ATTACH_RADIUS: float = 1.5

## Opacity of a beacon an opponent's detector has revealed — faint, like a revealed unit.
const REVEALED_OPACITY: float = 0.5

## Fires once when the beacon leaves play for ANY reason — spent by a shot, expired, or
## dropped because its spotter was re-ordered. Spot listens for it to know its work is done.
signal spent

var _has_signalled: bool = false

## The unit this beacon rides on, or null for a point beacon. Untyped: it may hold a freed
## piece.
var _carrier: Variant = null

## Whether a shot has been fired on this beacon. See [method mark_used].
var _is_used: bool = false


func _ready() -> void:
	get_parent().add_to_group(GROUP)


## Ride along with the carrier, and advance stealth — a beacon is not a Commandable, so
## nothing else ticks its Stealth.
func _physics_process(_a_delta: float) -> void:
	var carrier: Entity = carrier()
	if carrier != null:
		host().global_position = carrier.global_position
	elif _carrier != null:
		_carrier = null  # the carrier left play: stand where it last was
	var stealth: Stealth = host().stealth
	if stealth != null:
		stealth.tick()


## Draw for the LOCAL player: hidden from an opponent while stealthed, faint while revealed;
## the used marker only for the owner's side.
func _process(_a_delta: float) -> void:
	var visual: MeshVisual = host().get_node_or_null("MeshVisual") as MeshVisual
	if visual == null:
		return
	var allied: bool = _is_allied_to_local_player()
	var stealth: Stealth = host().stealth
	var opacity: float = 1.0
	if not allied and stealth != null:
		match stealth.state:
			Stealth.State.STEALTHED:
				opacity = 0.0
			Stealth.State.REVEALED:
				opacity = REVEALED_OPACITY
	visual.visible = opacity > 0.0
	visual.set_status_opacity(opacity)
	var used_marker: Node3D = visual.get_node_or_null("UsedMarker") as Node3D
	if used_marker != null:
		used_marker.visible = allied and _is_used


## Whichever way the host goes — dismissed, or freed by a Lifespan running out — the spotter
## hears it. Emitting on the way OUT of memory rather than out of the tree, because a host
## reparented to its commander leaves the tree and comes straight back.
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		_signal_spent()


## `a_node`'s Beacon component, or null. Untyped because a caller may hold a freed reference.
static func of(a_node: Variant) -> Beacon:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Beacon") as Beacon


func host() -> Entity:
	return get_parent() as Entity


## True once the beacon is on its way out, so a scan does not spend it twice.
func is_leaving() -> bool:
	return _has_signalled or host().is_queued_for_deletion()


## True when `a_entity` may carry a beacon: a live, grounded, MECH unit — not a structure,
## not an aircraft, and never BIO (see gdd/design-framework/static-defence.md §The Bombard).
static func can_carry(a_entity: Variant) -> bool:
	if a_entity == null or not is_instance_valid(a_entity) or not (a_entity is Commandable):
		return false
	var unit := a_entity as Commandable
	return (
		unit.is_inside_tree()
		and not unit.is_queued_for_deletion()
		and not unit.structure_is_active()
		and unit.aerial == null
		and unit.live_movement() != null
		and unit.defense != null
		and unit.defense.frame_type == Defense.FrameType.MECH
	)


## The live beacons riding on `a_unit`.
static func carried_by(a_unit: Node) -> Array[Beacon]:
	var out: Array[Beacon] = []
	if a_unit == null or not a_unit.is_inside_tree():
		return out
	for node: Node in a_unit.get_tree().get_nodes_in_group(GROUP):
		var beacon: Beacon = Beacon.of(node)
		if beacon != null and not beacon.is_leaving() and is_same(beacon._carrier, a_unit):
			out.append(beacon)
	return out


## Ride on `a_unit` from now on. False (and nothing changes) when it cannot carry one.
func attach_to(a_unit: Entity) -> bool:
	if not can_carry(a_unit):
		return false
	_carrier = a_unit
	host().global_position = a_unit.global_position
	return true


## The unit carrying this beacon, or null for a point beacon (or one whose carrier is gone).
## A carrier out of the tree — garrisoned, say — does not carry it anywhere.
func carrier() -> Entity:
	var carrier: Variant = _carrier
	if carrier == null or not is_instance_valid(carrier):
		return null
	var entity := carrier as Entity
	return entity if entity.is_inside_tree() and not entity.is_queued_for_deletion() else null


## Mark that a shot has been fired on this beacon: no other battery may spend it, and its
## owner's side sees it as used. Idempotent.
func mark_used() -> void:
	_is_used = true


func is_used() -> bool:
	return _is_used


## Dismiss this beacon when `a_shell` lands: on its first hand-over from its flight phase to
## the next, or when it leaves play, whichever comes first. The shell tracks the beacon until
## then, so the beacon must stand for the whole flight.
func dismiss_on_landing(a_shell: Entity) -> void:
	if a_shell == null:
		dismiss()
		return
	var phased: PhasedLocomotion = a_shell.get_node_or_null("Locomotion") as PhasedLocomotion
	# Method callables, not lambdas: a connection to a method is dropped when this beacon is
	# freed first, so a shell outliving its beacon never calls into a freed object.
	if phased != null:
		phased.phase_entered.connect(_on_shell_phase_entered)
	a_shell.tree_exiting.connect(dismiss)


func _on_shell_phase_entered(a_index: int) -> void:
	if a_index > 0:
		dismiss()


func _is_allied_to_local_player() -> bool:
	var owner_commander: Commander = host().commander
	return (
		owner_commander != null
		and owner_commander.shares_side_with(RTSController.PLAYER_COMMANDER_ID)
	)


## True when a strike aimed at `world_position` may spend this beacon.
func covers(a_world_position: Vector3) -> bool:
	return host().hull().distance_to_point(VU.in_xz(a_world_position)) <= STRIKE_RADIUS


## Take this beacon out of play. One method for every deliberate reason (spent, cancelled)
## because every caller wants the same two things — the signal, then the free. Idempotent, so
## a shot and an expiry landing on one frame cannot double-notify the spotter.
func dismiss() -> void:
	if is_leaving():
		return
	_signal_spent()
	host().queue_free()


func _signal_spent() -> void:
	if _has_signalled:
		return
	_has_signalled = true
	spent.emit()
