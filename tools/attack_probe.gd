extends Node3D

## Headless probe for an AERIAL unit's attack run: why an aircraft ordered onto a distant
## target closes in, stops, and then does not shoot.
##
## Prints, per tick, every term `Attack.can_act` is built out of — in range, dive contact,
## facing, weapon ready — beside the unit's altitude and distance, so the one that is
## false is visible rather than inferred.
##
## Run with:
##   godot --headless res://tools/attack_probe.tscn -- [unit_scene] [target_scene] [distance]

const SCENARIO: String = "res://scenes/scenarios/test/nav_straight_line.tscn"
const AIRFIELD: String = "res://scenes/entities/structures/cl/cl_airField.tscn"
const MAX_TICKS: int = 2600
const SAMPLE_EVERY: int = 10

var _unit_scene: String = "res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn"
var _target_scene: String = "res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn"
var _distance: float = 25.0
## Order an AttackMove at the target's position instead of an Attack on the target itself.
var _attack_move: bool = false
## Lateral offset of the attacker from the target's axis, so the approach is a CURVE.
var _offset: float = 0.0
## Send the target driving across the attacker's path, so the bearing keeps changing.
var _target_moves: bool = false
## Start with a spent clip, and/or give a plain MOVE order instead of an attack — the two
## halves of "an empty aircraft still does what it is told".
var _start_empty: bool = false
var _move_order: bool = false
var _defend: bool = false


func _ready() -> void:
	var seen_scene: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			if seen_scene == 0:
				_unit_scene = arg
			else:
				_target_scene = arg
			seen_scene += 1
		elif arg == "--attack-move":
			_attack_move = true
		elif arg.begins_with("off="):
			_offset = float(arg.substr(4))
		elif arg == "--moving-target":
			_target_moves = true
		elif arg == "--empty":
			_start_empty = true
		elif arg == "--move-order":
			_move_order = true
		elif arg == "--defend":
			_defend = true
		elif arg.is_valid_float():
			_distance = float(arg)
	_run.call_deferred()


func _run() -> void:
	var scenario: Node = (load(SCENARIO) as PackedScene).instantiate()
	add_child(scenario)
	await get_tree().physics_frame
	var map: Map = scenario.get_node_or_null("Map") as Map
	var waited: int = 0
	while not map.nav_manager.is_ready() and waited < 600:
		await get_tree().physics_frame
		waited += 1
	for _i: int in 30:
		await get_tree().physics_frame

	var commanders: Array = scenario.get("commanders")
	var player: Commander = scenario.call("local_player")
	var enemy: Commander = null
	for c: Commander in commanders:
		if c != null and c.id != player.id and c.id != 0:
			enemy = c
			break
	if enemy == null:
		# A bare scenario may field only the player and the neutral world; the probe needs
		# somebody to be hostile.
		enemy = Commander.new()
		enemy.id = player.id + 1
		scenario.add_child(enemy)
		await get_tree().physics_frame
	var centre: Vector2 = map.play_area().center

	var target := (load(_target_scene) as PackedScene).instantiate() as Commandable
	target.initialize(map, enemy)
	target.global_position = Vector3(centre.x, 0.0, centre.y)
	await get_tree().physics_frame

	# An airfield BEHIND the attacker, so the return leg has to turn the aircraft around.
	var field := (load(AIRFIELD) as PackedScene).instantiate() as Commandable
	field.initialize(map, player)
	var field_xz := Vector2(centre.x + _distance + 12.0, centre.y)
	field.global_position = Vector3(field_xz.x, 0.0, field_xz.y)
	map.add_structure(field, field_xz)
	await get_tree().physics_frame

	var unit := (load(_unit_scene) as PackedScene).instantiate() as Commandable
	unit.initialize(map, player)
	unit.global_position = Vector3(centre.x + _distance, 6.0, centre.y + _offset)
	await get_tree().physics_frame

	if _target_moves:
		target.update_commands(MoveCommand.new(
			CommandMessage.new(map, null, null, target.global_position + Vector3(0.0, 0.0, 60.0))))
	var weapon: Weapon = unit.weapon_inventory.get_weapons()[0]
	print("attacker %s (%s) reach=%.2f | target %s at %s" % [
		unit.id, _mode_name(unit.movement.mode), weapon.reach_for(target),
		target.id, target.global_position])

	if _start_empty:
		for w: Weapon in unit.weapon_inventory.charged_weapons():
			while w.ammo() > 0:
				w.consume_round()
		print("clip emptied before the order: ammo=%d" % unit.weapon_inventory.charged_ammo())
	# A destination well AWAY from the airfield, so obeying it is distinguishable from
	# being dragged home.
	var away := Vector3(centre.x - 30.0, 0.0, centre.y - 30.0)
	var message := CommandMessage.new(map, null if (_attack_move or _move_order) else target,
		null, away if _move_order else target.global_position)
	var order: MoveCommand
	if _defend:
		order = Defend.new(CommandMessage.new(map, null, null, away))
	elif _move_order:
		order = MoveCommand.new(message)
	elif _attack_move:
		order = AttackMove.new(message)
	else:
		order = Attack.new(message)
	unit.update_commands(order)
	print("--- ordered %s from %.1f units | airfield at %s ---" % [
("Defend" if _defend else ("Move" if _move_order else ("AttackMove" if _attack_move else "Attack"))),
		_distance, field.global_position])

	var start_ammo: int = weapon.ammo()
	var shots: int = 0
	for tick: int in MAX_TICKS:
		await get_tree().physics_frame
		var cmd: MoveCommand = unit.current_command()
		var live := cmd as Attack
		if cmd == null and tick > MAX_TICKS - 2:
			break
		if live == null:
			if tick % 5 == 0:
				print("t%4d pos=(%6.2f,%6.2f) h=%5.2f v=%4.2f | dField=%6.2f docked=%-5s | ammo=%2d %s" % [
					tick, unit.global_position.x, unit.global_position.z,
					unit.height_offset(), VU.inXZ(unit.velocity).length(),
					VU.inXZ(unit.global_position).distance_to(field_xz),
					unit.aerial.is_docked(), weapon.ammo(),
					"%s%s tgt=%s" % [
						cmd.get_script().get_global_name() if cmd != null else "IDLE",
						("/" + Rearm.DockState.keys()[(cmd as Rearm).state]) if cmd is Rearm else "",
						unit.movement.target_position]])
			continue
		if tick % 5 == 0:
			var to_target: Vector2 = VU.inXZ(target.global_position) - VU.inXZ(unit.global_position)
			var bearing: Vector2 = (VU.inXZ(target.global_position) - VU.inXZ(unit.global_position)).normalized()
			var nose: Vector2 = VU.inXZ(unit.movement.get_facing())
			var off_axis: float = rad_to_deg(absf(nose.angle_to(bearing))) if not nose.is_zero_approx() else -1.0
			print("t%4d pos=(%6.2f,%6.2f) d=%6.2f off=%5.1fdeg | range=%-5s facing=%-5s ready=%-5s canact=%-5s | ammo=%d %s" % [
				tick,
				unit.global_position.x, unit.global_position.z,
				to_target.length(),
				off_axis,
				SU.is_in_attack_range(weapon, unit, target),
				unit.movement.is_facing(target.global_position),
				weapon.is_ready(),
				live.can_act(unit),
				weapon.ammo(),
				cmd.get_script().get_global_name(),
			])
		if weapon.ammo() < start_ammo and shots == 0:
			shots = 1
			print("*** FIRED at tick %d ***" % tick)
	print("--- ended: target hp %.1f/%.1f, attacker ammo %d ---" % [
		target.defense.hp, target.defense.hp_max, weapon.ammo()])
	get_tree().quit()


## Movement.Mode is not a dense enum (FLYING is 0x11), so keys() cannot be indexed by value.
func _mode_name(a_mode: int) -> String:
	for name: String in Movement.Mode.keys():
		if Movement.Mode[name] == a_mode:
			return name
	return str(a_mode)
