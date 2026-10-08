extends GutTest

## A SCAN'S DETECTOR IS QUERY GEOMETRY, NEVER A BODY. EventRadarScan gives its scout a
## DetectionRange that Commandable._detect_stealthed_units scans with. The shape is a child
## of the scout's root CharacterBody3D, which stands on MOVEMENT_OBSTRUCTION, so a live shape
## would make the drone a cylinder of that radius to every spawn and placement probe.
##
## Run with:
## godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd \
##   -gtest=res://tests/test_RadarScanDetection.gd -gexit

const DETECTION_RADIUS: float = 16.0
## Inside the detection radius, well clear of the scout's own body.
const PROBE_OFFSET: float = DETECTION_RADIUS * 0.5
const PROBE_RADIUS: float = 0.3


func _scout_with_detection() -> Commandable:
	var scan := EventRadarScan.new()
	autofree(scan)
	scan.detection_radius = DETECTION_RADIUS
	var scout := FakePieces.unit()
	scan._add_detection(scout)
	add_child_autofree(scout)
	scout.set_physics_process(false)
	scout.refresh_movement_collision()
	return scout


func test_the_scout_still_has_a_detector() -> void:
	var scout := _scout_with_detection()
	assert_not_null(scout.detection_range, "the scan's tier detects stealth")
	assert_eq((scout.detection_range.shape as CylinderShape3D).radius, DETECTION_RADIUS)


func test_the_detector_does_not_obstruct_the_ground_around_the_scout() -> void:
	var scout := _scout_with_detection()
	assert_true(
		scout.collision_layer & CollisionLayers.Mask.MOVEMENT_OBSTRUCTION != 0,
		"precondition: the scout's body is on the layer spawn probes test"
	)
	await get_tree().physics_frame
	var probe := SphereShape3D.new()
	probe.radius = PROBE_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis(), Vector3(PROBE_OFFSET, 0.0, 0.0))
	params.collision_mask = CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
	var hits: Array = scout.get_world_3d().direct_space_state.intersect_shape(params, 1)
	assert_eq(hits.size(), 0, "ground inside the detection radius is free")
