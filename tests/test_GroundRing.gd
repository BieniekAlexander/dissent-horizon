extends GutTest

## GroundRing marks an area effect's edge: its size comes from the host's HitShape, so the ring
## and the area are one number. Rules: gdd/systems/combat/shields.md §Frost fields.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_GroundRing.gd -gexit


func _host(a_shape: Shape3D) -> Node3D:
	var host: Node3D = add_child_autofree(Node3D.new())
	var hit := CollisionShape3D.new()
	hit.name = "HitShape"
	hit.shape = a_shape
	host.add_child(hit)
	return host


func _ring_on(a_host: Node3D) -> GroundRing:
	var ring := GroundRing.new()
	a_host.add_child(ring)
	return ring


func test_the_ring_spans_the_hit_shape_exactly() -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 7.0
	var ring := _ring_on(_host(cylinder))
	assert_eq(ring.radius(), 7.0)
	assert_eq(ring.size.x, 14.0)
	assert_eq(ring.size.z, 14.0)
	assert_not_null(ring.texture_albedo)


func test_a_sphere_hit_shape_reads_too() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	assert_eq(_ring_on(_host(sphere)).radius(), 3.0)


func test_with_no_hit_shape_nothing_is_drawn() -> void:
	var ring := _ring_on(add_child_autofree(Node3D.new()))
	assert_eq(ring.radius(), 0.0)
	assert_null(ring.texture_albedo)


func test_the_line_is_the_same_width_on_any_size_of_field() -> void:
	# The ring's outer edge is the texture's edge; the line's inner edge moves in by
	# width / radius, so a fixed world width is a smaller fraction of a larger field.
	var small := GroundRing.ring_texture(5.0, 0.25, Color.WHITE).gradient
	var large := GroundRing.ring_texture(10.0, 0.25, Color.WHITE).gradient
	assert_almost_eq(1.0 - small.offsets[2], 0.25 / 5.0, 0.0001)
	assert_almost_eq(1.0 - large.offsets[2], 0.25 / 10.0, 0.0001)
	assert_eq(small.offsets[4], 1.0, "the outside of the line is the radius")
