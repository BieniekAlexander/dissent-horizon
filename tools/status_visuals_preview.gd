extends Node3D

## Visual preview harness for StatusVisuals: lines up one unit per state so the floating
## billboards and the mesh channels can be LOOKED AT, which no GUT assertion can do.
## Render it with:
##   godot res://tools/status_visuals_preview.tscn \
##     --write-movie /tmp/sv.png --fixed-fps 30 --quit-after 25 --resolution 1600x560
## See CLAUDE.md "Seeing the HUD without a screen".

const TANK: String = "res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn"
const TRUCK: String = "res://scenes/entities/units/cl/supply_truck.tscn"
const PLANE: String = "res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn"

const EFFECTS: Dictionary = {
	"emp": "res://scenes/entities/status_effects/emp.tscn",
	"freeze": "res://scenes/entities/status_effects/freeze.tscn",
	"burn": "res://scenes/entities/status_effects/lazer_burn.tscn",
	"slow": "res://scenes/entities/status_effects/slow.tscn",
}

## [scene, veterancy level, effect key or "", select it, yaw]
##
## The yaws are the point of the last two rows: a pip row used to be laid out along the
## unit's own X axis, so it went end-on as the unit turned. Turn them here and the rows
## must stay dead level across the screen.
const CASES: Array = [
	[TANK, Veterancy.Level.NONE, "", false, 0.0],
	[TANK, Veterancy.Level.VETERAN, "", false, 0.0],
	[TANK, Veterancy.Level.ELITE, "", false, 0.0],
	[TANK, Veterancy.Level.HEROIC, "", false, 0.0],
	[TANK, Veterancy.Level.NONE, "emp", false, 0.0],
	[TANK, Veterancy.Level.NONE, "freeze", false, 0.0],
	[TANK, Veterancy.Level.NONE, "burn", false, 0.0],
	[TANK, Veterancy.Level.ELITE, "slow", false, 0.0],
	[TRUCK, Veterancy.Level.NONE, "", true, PI / 2.0],
	[PLANE, Veterancy.Level.VETERAN, "", true, PI / 4.0],
]

func _ready() -> void:
	var commander := Commander.new()
	commander.id = RTSController.PLAYER_COMMANDER_ID
	add_child(commander)
	for i: int in CASES.size():
		var unit := (load(CASES[i][0]) as PackedScene).instantiate() as Commandable
		add_child(unit)
		# No Map here, so the physics tick (terrain snapping, navigation) has nothing to run
		# against — this harness only wants the entity DRAWN.
		unit.set_physics_process(false)
		unit.global_position = Vector3(-9.0 + 2.0 * float(i), 0.0, 0.0)
		unit.rotation.y = CASES[i][4]
		unit.ownership.commander = commander
		unit.veterancy.set_level(CASES[i][1])
		if CASES[i][2] != "":
			(load(EFFECTS[CASES[i][2]]) as PackedScene).instantiate().apply_to(unit)
		if CASES[i][3]:
			unit.selectable.select()
