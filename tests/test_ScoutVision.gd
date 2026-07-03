extends GutTest

## The Radar Scan ordnance spawns a Scout — a non-Commandable Entity that carries a
## VisionRange. Fog reveal (fog.gd, group-based) always saw it, but the geometric
## vision the blackboard/snapshot memory relies on iterated Commandable children only,
## so a Scout revealed the fog texture yet never triggered the sight checks that record
## structure snapshots. Commander now iterates _owned_vision_sources() (any child with a
## VisionRange) for has_vision_at / visible_enemies, so a Scout contributes real vision.

const SCOUT_SCENE: PackedScene = preload("res://scenes/entities/scout.tscn")

var _cmdr: Commander


func before_each() -> void:
	_cmdr = Commander.new()
	add_child_autofree(_cmdr)  # in-tree so child Entities' @onready shapes resolve


func _add_scout_at(world_xz: Vector2) -> Scout:
	var scout: Scout = SCOUT_SCENE.instantiate()
	_cmdr.add_child(scout)
	scout.global_position = Vector3(world_xz.x, 0.0, world_xz.y)
	return scout


func test_scout_is_an_owned_vision_source() -> void:
	var scout := _add_scout_at(Vector2.ZERO)
	assert_true(_cmdr._owned_vision_sources().has(scout),
		"a Scout child should count as a vision source (it has a VisionRange)")


func test_scout_gives_geometric_vision_within_its_radius() -> void:
	_add_scout_at(Vector2.ZERO)
	# scout.tscn VisionRange radius is 8.
	assert_true(_cmdr.has_vision_at(Vector3(5.0, 0.0, 0.0)),
		"has_vision_at should be true within the Scout's VisionRange")


func test_scout_gives_no_vision_beyond_its_radius() -> void:
	_add_scout_at(Vector2.ZERO)
	assert_false(_cmdr.has_vision_at(Vector3(20.0, 0.0, 0.0)),
		"has_vision_at should be false outside the Scout's VisionRange")


func test_no_vision_source_means_no_vision() -> void:
	assert_false(_cmdr.has_vision_at(Vector3(1.0, 0.0, 0.0)),
		"a commander with no vision sources should see nothing")
