extends Node3D

## Visual preview harness for the generated visual defaults: one piece per case, damaged so
## every HP bar is showing and selected so every selection ring is drawn. No GUT assertion
## can see a bar buried inside a model or a placeholder standing in the ground, which is
## why this exists (see CLAUDE.md "Seeing the HUD without a screen").
##
##   godot res://tools/visual_defaults_preview.tscn \
##     --write-movie /tmp/vd.png --fixed-fps 30 --quit-after 25 --resolution 1600x600
##
## The last case is the control: a piece whose HP bar is hand-authored, which the importer
## must NOT have touched. If its bar ever lines up with the others, the "never overwrite a
## baked value" rule has stopped holding.
const CASES: Array = [
	"res://scenes/entities/units/an/an_bioMedium_support.tscn",
	"res://scenes/entities/units/an/an_mechMedium_artillery.tscn",
	"res://scenes/entities/units/an/an_aircraftMedium_support.tscn",
	"res://scenes/entities/structures/an/an_barracks.tscn",
	"res://scenes/entities/units/an/an_bioLight_builder.tscn",
	"res://scenes/entities/units/cl/badger.tscn",
	"res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn",
]

## Spacing between cases, in world units — wide enough for the 2x2 structure.
const CASE_SPACING: float = 3.2
## How much of each piece's health to remove, so the bar is part-drained and visible.
const DAMAGE_FRACTION: float = 0.45


func _ready() -> void:
	var commander: Commander = Commander.new()
	commander.id = RTSController.PLAYER_COMMANDER_ID
	add_child(commander)
	var origin: float = -CASE_SPACING * (CASES.size() - 1) / 2.0
	for i: int in CASES.size():
		var piece: Commandable = (load(CASES[i]) as PackedScene).instantiate() as Commandable
		add_child(piece)
		# No Map here, so the physics tick has nothing to run against — this harness only
		# wants the entity DRAWN.
		piece.set_physics_process(false)
		piece.global_position = Vector3(origin + CASE_SPACING * float(i), 0.0, 0.0)
		piece.ownership.commander = commander
		piece.selectable.select()
		var defense: Node = piece.get_node_or_null("Defense")
		if defense != null:
			defense.apply_damage(defense.hp * DAMAGE_FRACTION)
