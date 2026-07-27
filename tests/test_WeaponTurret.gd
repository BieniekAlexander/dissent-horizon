extends GutTest

## TURRETS — a weapon that aims on its own yaw rather than with its carrier's body.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_WeaponTurret.gd -gexit
##
## What is pinned: the turret swings at turret_turn_rate and lands exactly on the bearing;
## its yaw is relative to the body, so it compensates for the body turning; it holds its last
## bearing for TURRET_REST_DELAY_SECONDS once nothing aims it, then drifts home at
## TURRET_REST_RATE_FACTOR of its aiming speed; the model part named by turret_visual_path
## shows turret_yaw, aiming and resting alike; and Attack holds a turret weapon's fire until
## the TURRET is aimed, without turning the body — while a non-turret weapon keeps the old rule.

## A Commandable with the children Entity/Commandable resolve with a hard `$` — the stub
## shape tests/test_HoldFire.gd uses — carrying a Loadout with one Weapon. No Movement, so
## the body cannot turn: whatever aiming happens here is the turret's.
class StubPiece:
	extends Commandable

	var stub_layers: int = CollisionLayers.Mask.TARGETABLE_GROUND

	static func make(a_turret: bool, a_with_visual: bool = false) -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [["Ownership", Ownership.new()],
				["AvoidanceObstacle", NavigationObstacle3D.new()],
				["Veterancy", Veterancy.new()]]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		var loadout := Loadout.new()
		loadout.name = "Loadout"
		var weapon := Weapon.new()
		weapon.name = "Gun"
		weapon.turret = a_turret
		if a_with_visual:
			# A stand-in model: a hull with the turret part under it, as an imported model has.
			var hull := Node3D.new()
			hull.name = "Hull"
			var part := Node3D.new()
			part.name = "Turret"
			hull.add_child(part)
			piece.add_child(hull)
			weapon.turret_visual_path = NodePath("../../Hull/Turret")
		var reach := CollisionShape3D.new()
		reach.name = "AttackRange"
		weapon.add_child(reach)
		loadout.add_child(weapon)
		piece.add_child(loadout)
		return piece

	## Targetable on the ground layer without a TargetBody, so a weapon will pick it.
	func targetable_layers() -> int:
		return stub_layers

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


var _commander: Commander


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func _piece(a_turret: bool = true, a_at: Vector3 = Vector3.ZERO,
		a_with_visual: bool = false) -> StubPiece:
	var piece: StubPiece = StubPiece.make(a_turret, a_with_visual)
	_commander.add_child(piece)
	piece.ownership.commander = _commander
	piece.global_position = a_at
	return piece


func _gun(a_piece: Commandable) -> Weapon:
	return a_piece.get_node("Loadout/Gun") as Weapon


## Run the weapon's own per-tick update `a_ticks` times, without the rest of the physics loop.
func _idle(a_weapon: Weapon, a_ticks: int) -> void:
	for i in a_ticks:
		a_weapon._physics_process(1.0 / TimeUtils.ticks_per_second())


func _deg(a_radians: float) -> float:
	return rad_to_deg(a_radians)


func test_it_swings_at_its_turn_rate_and_lands_exactly_on_the_bearing() -> void:
	var piece: StubPiece = _piece()
	var gun: Weapon = _gun(piece)
	var right: Vector3 = Vector3(10, 0, 0)   # +X is 90 degrees from the body's +Z forward
	gun.aim_turret_toward(piece, right)
	assert_almost_eq(_deg(gun.turret_yaw), 12.0, 0.001, "one tick of 360 deg/s at 30 tps")
	assert_false(gun.is_turret_aimed_at(piece, right), "not aimed partway round")
	for i in 7:
		gun.aim_turret_toward(piece, right)
	assert_almost_eq(_deg(gun.turret_yaw), 90.0, 0.0001, "the last partial step snaps exactly")
	assert_true(gun.is_turret_aimed_at(piece, right), "exact alignment, no arc")


func test_the_turn_rate_is_the_weapons_own() -> void:
	var piece: StubPiece = _piece()
	var gun: Weapon = _gun(piece)
	gun.turret_turn_rate = 90.0
	gun.aim_turret_toward(piece, Vector3(10, 0, 0))
	assert_almost_eq(_deg(gun.turret_yaw), 3.0, 0.001, "90 deg/s is 3 deg a tick")


func test_it_takes_the_short_way_round() -> void:
	var piece: StubPiece = _piece()
	var gun: Weapon = _gun(piece)
	gun.aim_turret_toward(piece, Vector3(-10, 0, 0))   # 90 degrees the OTHER way
	assert_almost_eq(_deg(gun.turret_yaw), -12.0, 0.001)


func test_its_yaw_is_relative_to_the_body() -> void:
	var piece: StubPiece = _piece()
	piece.rotation.y = PI / 2.0   # the body already faces +X
	var gun: Weapon = _gun(piece)
	var right: Vector3 = Vector3(10, 0, 0)
	assert_true(gun.is_turret_aimed_at(piece, right), "a centred turret points where the body does")
	gun.aim_turret_toward(piece, right)
	assert_almost_eq(gun.turret_yaw, 0.0, 0.0001, "nothing to swing")
	piece.rotation.y = 0.0   # the body turns away underneath it
	assert_false(gun.is_turret_aimed_at(piece, right), "a turret turns with its hull")
	for i in 8:
		gun.aim_turret_toward(piece, right)
	assert_true(gun.is_turret_aimed_at(piece, right), "and aiming makes it up")


func test_it_holds_its_bearing_for_the_rest_delay_then_drifts_home() -> void:
	var piece: StubPiece = _piece()
	var gun: Weapon = _gun(piece)
	for i in 8:
		gun.aim_turret_toward(piece, Vector3(10, 0, 0))
	var delay: int = TimeUtils.ticks_from_seconds(Weapon.TURRET_REST_DELAY_SECONDS)
	_idle(gun, delay)
	assert_almost_eq(_deg(gun.turret_yaw), 90.0, 0.0001, "still on the lost target's bearing")
	_idle(gun, 1)
	assert_almost_eq(_deg(gun.turret_yaw), 90.0 - 12.0 * Weapon.TURRET_REST_RATE_FACTOR, 0.001,
		"then swings back at a fraction of its aiming speed")
	_idle(gun, 100)
	assert_almost_eq(gun.turret_yaw, 0.0, 0.0001, "and comes to rest facing forward")


func test_aiming_holds_off_the_rest_swing() -> void:
	var piece: StubPiece = _piece()
	var gun: Weapon = _gun(piece)
	var right: Vector3 = Vector3(10, 0, 0)
	var delay: int = TimeUtils.ticks_from_seconds(Weapon.TURRET_REST_DELAY_SECONDS)
	for i in delay * 2:
		gun.aim_turret_toward(piece, right)
		_idle(gun, 1)
	assert_true(gun.is_turret_aimed_at(piece, right), "a turret being aimed never goes home")


func test_a_non_turret_weapon_never_moves_its_yaw() -> void:
	var gun: Weapon = _gun(_piece(false))
	_idle(gun, 200)
	assert_eq(gun.turret_yaw, 0.0)


func test_attack_holds_a_turret_weapons_fire_until_the_turret_is_on_target() -> void:
	var piece: StubPiece = _piece(true)
	var victim: StubPiece = _piece(false, Vector3(10, 0, 0))
	var attack := Attack.new(CommandMessage.new(null, victim))
	assert_false(attack._is_aimed_at_target(piece),
		"a body with no facing to wait on used to pass outright; a turret must aim")
	for i in 8:
		attack._update_facing(piece)
	assert_true(attack._is_aimed_at_target(piece), "aimed once the turret has swung round")
	assert_almost_eq(piece.rotation.y, 0.0, 0.0001, "the body never turned")


func test_attack_with_a_non_turret_weapon_keeps_the_body_rule() -> void:
	var piece: StubPiece = _piece(false)
	var victim: StubPiece = _piece(false, Vector3(10, 0, 0))
	var attack := Attack.new(CommandMessage.new(null, victim))
	assert_true(attack._is_aimed_at_target(piece),
		"no Movement and no turret: nothing to wait on, as before")


func test_the_turret_visual_follows_the_aim() -> void:
	var piece: StubPiece = _piece(true, Vector3.ZERO, true)
	var gun: Weapon = _gun(piece)
	var part: Node3D = piece.get_node("Hull/Turret") as Node3D
	for i in 3:
		gun.aim_turret_toward(piece, Vector3(10, 0, 0))
	assert_almost_eq(_deg(part.rotation.y), 36.0, 0.001, "the model shows the aim tick by tick")
	assert_almost_eq(part.rotation.y, gun.turret_yaw, 0.0001)


func test_the_turret_visual_follows_the_rest_swing_too() -> void:
	var piece: StubPiece = _piece(true, Vector3.ZERO, true)
	var gun: Weapon = _gun(piece)
	var part: Node3D = piece.get_node("Hull/Turret") as Node3D
	for i in 8:
		gun.aim_turret_toward(piece, Vector3(10, 0, 0))
	_idle(gun, TimeUtils.ticks_from_seconds(Weapon.TURRET_REST_DELAY_SECONDS) + 1)
	assert_almost_eq(part.rotation.y, gun.turret_yaw, 0.0001)
	assert_lt(_deg(part.rotation.y), 90.0, "it is on its way home")


func test_a_turret_without_a_visual_still_aims() -> void:
	var piece: StubPiece = _piece(true)
	var gun: Weapon = _gun(piece)
	gun.aim_turret_toward(piece, Vector3(10, 0, 0))
	assert_almost_eq(_deg(gun.turret_yaw), 12.0, 0.001, "no model part is not an error")
