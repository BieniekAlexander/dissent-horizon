extends GutTest

## Whether an emission damages an AREA or only the thing it was aimed at: exactly when it
## carries a HitShape, which only a non-hitscan emission has. The importer removes a hitscan
## emission's HitShape, and the Payload reads presence alone (Payload.has_blast).
##
## The rule once had to be "hitscan wins, and a DISABLED shape counts as none", because every
## emission inherited a HitShape it could not remove — and before that, an assertion on the
## combination crashed the game the moment one of six hitscan pieces fired. Those six are kept
## below as the regression.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProjectileBlast.gd -gexit

## Every hitscan emission that once carried an inherited HitShape.
const FORMERLY_INHERITED_HITSCAN: Array = [
	"res://scenes/entities/projectiles/cl/sloop_bullet.tscn",
	"res://scenes/entities/projectiles/cl/clipper_bullet.tscn",
	"res://scenes/entities/projectiles/cl/constable_bullet.tscn",
	"res://scenes/entities/projectiles/cl/avalanche_shell.tscn",
	"res://scenes/entities/projectiles/an/juggernaut_bullet.tscn",
	"res://scenes/entities/projectiles/an/shock_trooper_arc.tscn",
]

## An emission that genuinely wants a blast.
const BLAST_PROJECTILE: String = "res://scenes/entities/projectiles/cl/cannon_shell.tscn"


func _instantiate(a_path: String) -> Payload:
	var emission: Node = (load(a_path) as PackedScene).instantiate()
	add_child_autofree(emission)
	return Payload.of(emission)


func test_a_hitscan_emission_can_be_instantiated_and_has_no_blast() -> void:
	# Entering the tree runs _ready — the crash, reduced.
	for path: String in FORMERLY_INHERITED_HITSCAN:
		var payload: Payload = _instantiate(path)
		assert_true(payload.hitscan, "%s is hitscan" % path)
		assert_null(payload.hit_shape(), "%s carries no HitShape" % path)
		assert_false(payload.has_blast(), "%s resolves onto its target alone" % path)


func test_the_sloop_is_the_piece_that_reported_this() -> void:
	# cl_mechMedium_antiLight crashed on its first shot: hitscan weapon, inherited shape.
	var sloop: Node = load("res://scenes/entities/units/cl/cl_mechMedium_antiLight.tscn").instantiate()
	autofree(sloop)
	var weapon := sloop.get_node_or_null("Loadout/BallisticWeapon") as Weapon
	assert_not_null(weapon, "the Sloop still has its weapon")
	if weapon != null and weapon.projectile_scene != null:
		var emission: Node = weapon.projectile_scene.instantiate()
		add_child_autofree(emission)
		var shot: Payload = Payload.of(emission)
		assert_true(shot.hitscan)
		assert_false(shot.has_blast())


func test_a_non_hitscan_emission_with_a_shape_has_a_blast() -> void:
	var shell: Payload = _instantiate(BLAST_PROJECTILE)
	assert_false(shell.hitscan, "a shell is not hitscan")
	assert_true(shell.has_blast(), "so its shape is its blast")
