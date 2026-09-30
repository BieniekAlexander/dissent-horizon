extends GutTest

## StatusVisuals: how a commandable's CONDITION — stealth, active status effects, earned
## rank — is turned into a look. Two outputs, tested separately:
##   • MeshVisual's STATUS channels, which are a SECOND pair of factors alongside the
##     construction ones and must compose with them rather than overwrite them.
##   • the floating billboards, which must be gated on the same "can this even be seen"
##     rule the model itself is.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_StatusVisuals.gd -gexit


func _unit() -> Commandable:
	# load(), not a file-scope preload: a preload of an entity scene runs at PARSE time and
	# can fire Tool's static registry initialiser before the registry exists (see CLAUDE.md).
	var scene: PackedScene = load("res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn")
	var unit := scene.instantiate() as Commandable
	add_child_autofree(unit)
	return unit


func _visual(a_unit: Node) -> MeshVisual:
	return a_unit.get_node("MeshVisual") as MeshVisual


func _status_visuals(a_unit: Node) -> StatusVisuals:
	return a_unit.get_node("StatusVisuals") as StatusVisuals


func _emp() -> StatusEffect:
	return (load("res://scenes/entities/status_effects/emp.tscn") as PackedScene).instantiate() as StatusEffect


#region The two channels compose
## The whole reason the status channel exists: a half-built structure can be EMP'd, and a
## stealthed unit is no less finished for fading. Neither channel may clobber the other.
func test_construction_shade_and_status_tint_multiply() -> void:
	var unit: Commandable = _unit()
	var visual: MeshVisual = _visual(unit)
	visual.set_team_color(Color.WHITE)
	visual.set_shade(0.5)
	visual.set_status_tint(Color(0.2, 0.4, 1.0))
	assert_eq(visual.shade(), 0.5, "the construction channel still reads back on its own")
	assert_eq(visual.status_tint(), Color(0.2, 0.4, 1.0), "and so does the status channel")
	var effective: Color = visual.effective_tint()
	assert_almost_eq(effective.r, 0.1, 0.0001, "the model is drawn at the product")
	assert_almost_eq(effective.b, 0.5, 0.0001, "per channel, so a colour survives a shade")


func test_construction_and_status_opacities_multiply() -> void:
	var unit: Commandable = _unit()
	var visual: MeshVisual = _visual(unit)
	visual.set_opacity(MeshVisual.OPACITY_CONSTRUCTING)
	visual.set_status_opacity(0.4)
	assert_eq(visual.opacity(), MeshVisual.OPACITY_CONSTRUCTING,
		"opacity() keeps meaning the CONSTRUCTION fade — its callers ask nothing else")
	assert_almost_eq(visual.effective_opacity(), 0.2, 0.0001)


## A status fade makes the material translucent, and a translucent material writes no
## stencil — so the x-ray silhouette has to drop for it exactly as it does for a
## construction fade. Leaving it on paints the WHOLE model as though it were hidden.
func test_a_status_fade_suppresses_the_silhouette() -> void:
	var unit: Commandable = _unit()
	var visual: MeshVisual = _visual(unit)
	assert_false(visual._surfaces.is_empty(), "the model has a tintable surface to check")
	visual.set_status_opacity(0.3)
	for rec: Dictionary in visual._surfaces:
		assert_eq((rec["mat"] as BaseMaterial3D).stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED)
	visual.set_status_opacity(MeshVisual.STATUS_OPACITY_NORMAL)
	for rec: Dictionary in visual._surfaces:
		assert_eq((rec["mat"] as BaseMaterial3D).stencil_mode, BaseMaterial3D.STENCIL_MODE_XRAY)
#endregion


#region Effects declare, StatusVisuals composes
func test_an_emp_darkens_its_host_and_lets_go_when_it_ends() -> void:
	var unit: Commandable = _unit()
	var sv: StatusVisuals = _status_visuals(unit)
	var effect: StatusEffect = _emp()
	effect.apply_to(unit)
	assert_true(unit.is_stunned(), "the matilda is MECH, so the EMP takes hold")
	sv._process(0.0)
	assert_lt(_visual(unit).status_tint().v, 0.5, "an EMP'd machine is drawn near-black")

	effect.remove()
	sv._process(0.0)
	assert_eq(_visual(unit).status_tint(), MeshVisual.STATUS_TINT_NORMAL,
		"and its colour comes back the moment the effect ends")


## An effect the host is immune to removes ITSELF in _on_apply (StunStatusEffect's frame
## mask), so a bio unit must never pick up the tint of a stun that never took hold.
func test_an_effect_that_refuses_its_host_changes_nothing() -> void:
	var scene: PackedScene = load("res://scenes/entities/units/an/an_bioLight_builder.tscn")
	var unit := scene.instantiate() as Commandable
	add_child_autofree(unit)
	_emp().apply_to(unit)
	assert_false(unit.is_stunned(), "the irregular is BIO — an EMP slides off it")
	_status_visuals(unit)._process(0.0)
	assert_eq(_visual(unit).status_tint(), MeshVisual.STATUS_TINT_NORMAL)


## The MINIMUM, not the product: "how dark does this unit's condition draw it" is one
## reading of the unit, and two effects each halving it would otherwise quarter it.
func test_two_effects_do_not_compound_into_black() -> void:
	var unit: Commandable = _unit()
	var sv: StatusVisuals = _status_visuals(unit)
	var emp: StatusEffect = _emp()
	emp.apply_to(unit)
	# A second, distinct kind of effect (StatusEffect matches "already on this host" by
	# SCRIPT, so a second bare one would be discarded as a duplicate) asking for a milder
	# shade than the EMP's.
	var milder := SlowStatusEffect.new()
	milder.host_tint = Color(0.5, 0.5, 0.5)
	milder.duration_ticks = 0
	milder.apply_to(unit)
	sv._process(0.0)
	assert_almost_eq(_visual(unit).status_tint().r, emp.host_tint.r, 0.0001,
		"the strongest effect wins outright — the product would be far blacker than either")


## The whole reason the status channel is a Colour: cryo RAISES the host's armour, so it
## has to read as cold rather than as drained.
func test_a_freeze_tints_its_host_blue_rather_than_dark() -> void:
	var effect := (load("res://scenes/entities/status_effects/freeze.tscn") as PackedScene).instantiate() as StatusEffect
	autofree(effect)
	assert_gt(effect.host_tint.b, effect.host_tint.r, "blue survives where red is drained")
	assert_gt(effect.host_tint.b, 0.9, "and it is barely dimmed at all on that channel")


func test_the_emp_scene_declares_the_visual_it_is_known_by() -> void:
	var effect: StatusEffect = _emp()
	autofree(effect)
	assert_lt(effect.host_tint.v, 1.0, "an EMP'd machine goes dark")
	assert_not_null(effect.indicator_icon, "and carries the lightning bolt")
	assert_gt(effect.indicator_blink_hz, 0.0, "which blinks, because it is happening now")
#endregion


#region Billboards
func test_veterancy_raises_a_chevron_badge_only_once_promoted() -> void:
	var unit: Commandable = _unit()
	var sv: StatusVisuals = _status_visuals(unit)
	sv._process(0.0)
	assert_null(sv._veterancy_sprite, "an unranked unit never even builds the sprite")

	unit.veterancy.set_level(Veterancy.Level.ELITE)
	sv._process(0.0)
	assert_not_null(sv._veterancy_sprite, "a promoted one gets a badge")
	assert_true(sv._veterancy_sprite.visible)
	assert_eq(sv._veterancy_sprite.texture, StatusVisuals.VETERANCY_ICONS[Veterancy.Level.ELITE],
		"two chevrons for the second rank")


func test_an_effect_with_an_icon_raises_one_sprite_and_drops_it_again() -> void:
	var unit: Commandable = _unit()
	var sv: StatusVisuals = _status_visuals(unit)
	var effect: StatusEffect = _emp()
	effect.apply_to(unit)
	effect.indicator_blink_hz = 0.0  # steady, so the assertion isn't racing the blink
	sv._process(0.0)
	assert_eq(sv._status_sprites.size(), 1, "one icon, one sprite")
	assert_true(sv._status_sprites[0].visible)
	assert_eq(sv._status_sprites[0].texture, effect.indicator_icon)

	effect.remove()
	sv._process(0.0)
	assert_eq(sv._status_sprites.size(), 1, "the sprite is pooled, not churned")
	assert_false(sv._status_sprites[0].visible, "but nothing is drawn once the effect ends")


## A blink is what says "this is happening TO the unit right now"; a 0 Hz icon is a state
## you read at a glance and must never flicker.
func test_blinking_turns_the_icon_off_and_on() -> void:
	var unit: Commandable = _unit()
	var sv: StatusVisuals = _status_visuals(unit)
	assert_true(sv._blink_is_on(0.0), "0 Hz is always on")
	sv._elapsed = 0.0
	assert_true(sv._blink_is_on(1.0), "the first half-second of a 1 Hz blink is on")
	sv._elapsed = 0.75
	assert_false(sv._blink_is_on(1.0), "the second half is off")
	sv._elapsed = 1.25
	assert_true(sv._blink_is_on(1.0), "and it comes back")


## An enemy stealth is hiding is drawn at zero alpha — a badge or a bolt floating over it
## would give away the very unit the fade is hiding.
func test_nothing_floats_over_a_unit_stealth_is_hiding() -> void:
	var scene: PackedScene = load("res://scenes/entities/units/cl/cl_bioLight_stealth.tscn")
	var unit := scene.instantiate() as Commandable
	add_child_autofree(unit)
	assert_not_null(unit.stealth, "the sleeper is the stealth unit")
	# Owned by SOMEBODY ELSE, explicitly. Leaving it unowned would read as commander 0 and
	# usually work, but PLAYER_COMMANDER_ID is a mutable static that other suites move —
	# so the enemy has to be an enemy by construction, not by arithmetic on that value.
	var enemy := Commander.new()
	enemy.id = RTSController.PLAYER_COMMANDER_ID + 1
	add_child_autofree(enemy)
	unit.ownership.commander = enemy
	unit.veterancy.set_level(Veterancy.Level.VETERAN)
	var sv: StatusVisuals = _status_visuals(unit)
	sv._process(0.0)
	assert_true(unit.is_hidden_by_stealth(), "an enemy sleeper at rest is invisible")
	assert_eq(_visual(unit).status_opacity(), 0.0, "its model is drawn at nothing")
	assert_false(sv._veterancy_sprite.visible, "and its rank badge is not on screen either")


## Its OWNER still sees the faint pulse — they have to be able to command what the enemy
## cannot see. Carried over unchanged from the billboard-sprite era.
func test_its_owner_still_sees_a_stealthed_unit_faintly() -> void:
	var scene: PackedScene = load("res://scenes/entities/units/cl/cl_bioLight_stealth.tscn")
	var unit := scene.instantiate() as Commandable
	add_child_autofree(unit)
	var player := Commander.new()
	player.id = RTSController.PLAYER_COMMANDER_ID
	add_child_autofree(player)
	unit.ownership.commander = player
	assert_false(unit.is_hidden_by_stealth(), "it is ours, so it is not hidden from us")
	_status_visuals(unit)._process(0.0)
	var alpha: float = _visual(unit).status_opacity()
	assert_gt(alpha, 0.0, "the owner sees something")
	assert_lt(alpha, 0.5, "but only just — it is a pulse, not a solid unit")
#endregion


#region Capacity pips
func _owned(a_path: String) -> Commandable:
	var unit := (load(a_path) as PackedScene).instantiate() as Commandable
	add_child_autofree(unit)
	var player := Commander.new()
	player.id = RTSController.PLAYER_COMMANDER_ID
	add_child_autofree(player)
	unit.ownership.commander = player
	return unit


## A transport draws one pip per SEAT, solid for the seats that are taken. Capacity is
## OCCUPANCY rather than head count, so this is also what a size-2 occupant fills.
func test_a_selected_transport_counts_out_its_seats() -> void:
	var truck: Commandable = _owned("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn")
	var sv: StatusVisuals = _status_visuals(truck)
	truck.selectable.select()
	sv._process(0.0)
	var drawn: Array[Sprite3D] = _visible_pips(sv)
	assert_eq(drawn.size(), truck.garrison.capacity, "one pip per seat")
	for sprite: Sprite3D in drawn:
		assert_eq(sprite.texture, StatusVisuals.SLOT_EMPTY, "an empty truck draws them hollow")


## The information a rearming aircraft's behaviour is otherwise unexplained by.
func test_a_selected_charged_aircraft_counts_out_its_rounds() -> void:
	var plane: Commandable = _owned("res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn")
	var sv: StatusVisuals = _status_visuals(plane)
	assert_true(plane.weapon_inventory.has_charged_weapons(), "the drake reloads at an airfield")
	plane.selectable.select()
	sv._process(0.0)
	var drawn: Array[Sprite3D] = _visible_pips(sv)
	assert_eq(drawn.size(), plane.weapon_inventory.charged_clip_size(), "one pip per round")
	assert_eq(drawn[0].texture, StatusVisuals.AMMO_FILLED, "a fresh clip draws them solid")


## Selection-only: both are detail you ask for about one unit, not a readout to track
## across the field.
func test_pips_are_drawn_only_while_the_unit_is_selected() -> void:
	var truck: Commandable = _owned("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn")
	var sv: StatusVisuals = _status_visuals(truck)
	sv._process(0.0)
	assert_eq(_visible_pips(sv).size(), 0, "nothing while deselected")
	truck.selectable.select()
	sv._process(0.0)
	assert_gt(_visible_pips(sv).size(), 0, "and the row appears on selection")
	truck.selectable.deselect()
	sv._process(0.0)
	assert_eq(_visible_pips(sv).size(), 0, "and goes again")


## Drawing an enemy transport's remaining seats would hand over exactly the scouting
## information a garrison exists to hide.
func test_an_enemy_transport_never_shows_its_seats() -> void:
	var truck := (load("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn") as PackedScene).instantiate() as Commandable
	add_child_autofree(truck)
	var enemy := Commander.new()
	enemy.id = RTSController.PLAYER_COMMANDER_ID + 1
	add_child_autofree(enemy)
	truck.ownership.commander = enemy
	truck.selectable.select()
	_status_visuals(truck)._process(0.0)
	assert_eq(_visible_pips(_status_visuals(truck)).size(), 0)


## Almost every unit in the game has neither a garrison nor a charged clip, and must pay
## nothing for this.
func test_an_ordinary_unit_draws_no_pips_at_all() -> void:
	var unit: Commandable = _owned("res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn")
	unit.selectable.select()
	var sv: StatusVisuals = _status_visuals(unit)
	sv._process(0.0)
	assert_eq(sv._capacity_slots().size(), 0, "no seats, no charged rounds, no row")


## A 12-round clip on one line would be two tank-lengths wide.
func test_a_long_clip_wraps_onto_a_second_row() -> void:
	var plane: Commandable = _owned("res://scenes/entities/units/cl/cl_aircraftLight_antiLight.tscn")
	# No shipped piece carries a clip this long, so make the fixture rather than read one from
	# authored content: a charged weapon whose clip needs more than one row.
	var weapon: Weapon = plane.weapon_inventory.get_weapons()[0]
	weapon.charged = true
	weapon.clip_size = StatusVisuals.PIPS_PER_ROW + 4
	var sv: StatusVisuals = _status_visuals(plane)
	assert_gt(plane.weapon_inventory.charged_clip_size(), StatusVisuals.PIPS_PER_ROW,
		"the fixture's clip is longer than a row")
	plane.selectable.select()
	sv._process(0.0)
	var heights: Array[float] = []
	for sprite: Sprite3D in _visible_pips(sv):
		if not heights.has(sprite.position.y):
			heights.append(sprite.position.y)
	assert_eq(heights.size(), 2, "the row wrapped exactly once")


func _visible_pips(a_sv: StatusVisuals) -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for sprite: Sprite3D in a_sv._pip_sprites:
		if sprite.visible:
			out.append(sprite)
	return out
#endregion


#region Row orientation
## A row of icons is billboarded AS A ROW. Each sprite already faced the camera on its
## own, but the LINE they sit on inherited the entity's yaw, so a four-pip ammo row went
## end-on the moment the aircraft banked away.
func test_a_pip_row_lies_along_the_camera_and_ignores_the_units_facing() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()

	var truck: Commandable = _owned("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn")
	var sv: StatusVisuals = _status_visuals(truck)
	truck.selectable.select()

	var spread_at := func(yaw: float) -> Vector3:
		truck.rotation.y = yaw
		sv._process(0.0)
		var pips: Array[Sprite3D] = _visible_pips(sv)
		assert_gt(pips.size(), 1, "the truck draws more than one seat")
		return pips[pips.size() - 1].global_position - pips[0].global_position

	var facing_forward: Vector3 = spread_at.call(0.0)
	var turned: Vector3 = spread_at.call(PI / 2.0)
	assert_almost_eq(facing_forward.length(), turned.length(), 0.0001,
		"the row is the same width however the truck is pointing")
	assert_almost_eq((facing_forward - turned).length(), 0.0, 0.0001,
		"and it runs in the same world direction — the unit's yaw does not carry it round")

	var right: Vector3 = camera.global_basis.x
	assert_almost_eq(absf(facing_forward.normalized().dot(right)), 1.0, 0.0001,
		"that direction is the camera's screen-right")


## Y stays WORLD up: taking the camera's up as well would tilt the whole rig by the
## camera's pitch, and the row heights are measured from the model's own top.
func test_the_rows_still_stack_straight_up() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	camera.rotation = Vector3(-PI / 4.0, PI / 3.0, 0.0)

	var truck: Commandable = _owned("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn")
	var sv: StatusVisuals = _status_visuals(truck)
	truck.veterancy.set_level(Veterancy.Level.VETERAN)
	truck.selectable.select()
	sv._process(0.0)

	var badge: Vector3 = sv._veterancy_sprite.global_position
	var pip: Vector3 = _visible_pips(sv)[0].global_position
	assert_almost_eq(badge.x, truck.global_position.x, 0.0001, "the badge sits over the unit")
	assert_almost_eq(badge.z, truck.global_position.z, 0.0001)
	assert_gt(pip.y, badge.y, "and the pip row sits above the badge, not behind it")
#endregion
