class_name Emitter
extends RefCounted

## Puts an emission into play: the one call every emitter makes after instantiating an emission
## and initialising it against its owner (Entity.initialize). What it hands over is the
## emission's initial intent — who fired it, at what, and so where its locomotion goes.
##
## An emitted UNIT (the Brood Lord's broodling) is handed a command instead of a flight:
## composition-rework §Emitting, as one interface. What an emission costs and outlives is
## decided there too — nothing, and its emitter.
##
## TODO: only an ABILITY's `emits:` can name a unit today; the importer still requires a
## weapon's `emits:` to be a projectile (SpecRegistry weapon validation, and the projectile
## scene it resolves). Nothing emits a unit yet — see composition-rework §The emitted unit.

## Launch `a_emission`, fired by `a_from` (a Commandable, or null for an unattributed shot) at
## `a_target` — an Entity to pursue, or a Vector3 to land at.
static func launch(a_emission: Entity, a_from: Variant, a_target: Variant) -> void:
	var from: Commandable = a_from if a_from is Commandable else null
	if from != null:
		from.action_tracker.cue(ActionTracker.CUE_EMITTED, a_emission)
	if a_emission is Commandable:
		_command(a_emission as Commandable, a_target)
		return
	var target: Entity = a_target if a_target is Entity else null
	var destination: Vector3 = target.global_position if target != null else a_target
	var origin: Vector3 = a_emission.global_position
	var payload: Payload = Payload.of(a_emission)
	if payload != null and target != null and payload.aims_at_ground_under(target):
		destination = _ground_under(a_emission, target)
		target = null
	if payload != null:
		payload.arm(from, target)
	var excluded: Array[RID] = [a_emission.get_rid()]
	if is_instance_valid(from):
		excluded += _body_rids(from)
	var phased: PhasedLocomotion = a_emission.locomotion_component as PhasedLocomotion
	# A hitscan shot lands on its target whatever it hits, so it flies guided; anything else
	# flies free and has to strike something (projectiles.md §Free flight).
	phased.launch(destination, target, excluded, payload != null and not payload.hitscan)
	var first: EmissionPhase = phased.current_phase()
	if first != null and payload != null and payload.hitscan:
		phased.redirect(payload.aim_error(a_emission.velocity))
	phased.face_velocity()
	var tracer: Tracer = Tracer.of(a_emission)
	if tracer != null:
		tracer.start(origin, destination, first == null or first.speed <= 0.0)


## An emitted unit's initial intent, as an order: attack an Entity it was launched at, or
## attack-move to a point — so it fights on the way, as any unit sent somewhere would.
static func _command(a_unit: Commandable, a_target: Variant) -> void:
	var target: Entity = a_target if a_target is Entity else null
	var command: MoveCommand
	if target != null:
		command = Attack.new(CommandMessage.new(a_unit.map, target, null, target.global_position))
	else:
		var point: Vector3 = a_target
		if a_unit.map != null:
			point = a_unit.map.nearest_navmesh_point(point)
		command = AttackMove.new(CommandMessage.new(a_unit.map, null, null, point))
	a_unit.update_commands(command)
	# Prime the nav target: a fresh agent's defaults to the origin (BotActuator.attack_move).
	a_unit.load_destination(command)


## The ground under `a_target`'s feet, where a shot aimed there lands.
static func _ground_under(a_emission: Entity, a_target: Entity) -> Vector3:
	var at: Vector3 = a_target.global_position
	var map: Map = a_emission.map if a_emission.map != null else a_target.map
	if map != null:
		at.y = map.terrain_height_at(VU.inXZ(at))
	return at


## Every physics body of `a_entity` a ray could strike: its own and its direct children's.
static func _body_rids(a_entity: Entity) -> Array[RID]:
	var rids: Array[RID] = [a_entity.get_rid()]
	for child: Node in a_entity.get_children():
		if child is CollisionObject3D:
			rids.append((child as CollisionObject3D).get_rid())
	return rids
