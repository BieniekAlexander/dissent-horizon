extends GutTest

## The snapshot codec (StateCodec) carries every field it is given back to the bit, keeps shared
## objects shared, fills an object the slot already holds rather than replacing it, and leaves
## out what a class says it does not carry. Driven against a plain fixture, through JSON as a save
## is. gdd/systems/commands/saved-games.md §The snapshot.

const Fixture = preload("res://tests/_codec_fixture.gd")


func test_every_kind_of_field_comes_back_to_the_bit() -> void:
	var source: RefCounted = Fixture.new()
	source.number = 42
	source.big = (1 << 62) + 7
	source.real = 0.1 + 0.2
	source.other = 1.0 / 3.0
	source.label = &"warlord"
	source.vector = Vector3(1.0 / 7.0, -0.0, 1e-300)
	source.transform = Transform3D(
		Basis.from_euler(Vector3(0.3, 1.1, -0.7)), Vector3(5.5, 2.25, -9.0)
	)
	source.floats = PackedFloat32Array([0.5, 1.0 / 3.0])
	source.texts = PackedStringArray(["0123456789abcdef", "plain"])
	source.ints.assign([3, 1, 2])
	source.untyped = PackedInt64Array([(1 << 62) + 3, -5])
	source.table = {7: "seven", "b": INF, &"c": Vector2i(2, 3)}
	var target: RefCounted = _round_trip(source)
	assert_eq(target.number, 42)
	assert_eq(target.big, (1 << 62) + 7, "an int past a double's precision")
	assert_eq(target.real, 0.1 + 0.2, "a float to the bit")
	assert_true(target.other is float and target.other == 1.0 / 3.0, "a float in a Variant slot")
	assert_eq(target.untyped, PackedInt64Array([(1 << 62) + 3, -5]), "large ints in a packed array")
	assert_eq(target.label, &"warlord")
	assert_eq(target.vector, source.vector)
	assert_eq(target.transform, source.transform)
	assert_eq(target.floats, source.floats)
	assert_eq(target.texts, source.texts, "text that looks like a float's bits stays text")
	assert_eq(target.ints, [3, 1, 2])
	assert_eq(target.ints.get_typed_builtin(), TYPE_INT, "a typed array stays typed")
	assert_eq(target.table.keys(), [7, "b", &"c"], "keys keep their types and order")
	assert_eq(target.table[&"c"], Vector2i(2, 3))
	assert_true(is_inf(target.table["b"]))


func test_a_shared_object_stays_shared_and_a_cycle_closes() -> void:
	var source: RefCounted = Fixture.new()
	var shared: RefCounted = Fixture.new()
	shared.number = 9
	shared.other = source
	source.other = shared
	source.untyped = shared
	var target: RefCounted = _round_trip(source)
	assert_eq(target.other.number, 9)
	assert_same(target.other, target.untyped, "two fields naming one object name one again")
	assert_same(target.other.other, target, "an object reachable from itself")


func test_an_object_the_slot_already_holds_is_filled_in_place() -> void:
	var source: RefCounted = Fixture.new()
	var inner: RefCounted = Fixture.new()
	inner.number = 5
	source.other = inner
	var target: RefCounted = Fixture.new()
	var standing: RefCounted = Fixture.new()
	target.other = standing
	_round_trip(source, target)
	assert_same(target.other, standing, "the object the rebuilt scene made is kept")
	assert_eq(standing.number, 5, "and given the saved fields")


func test_a_method_callable_names_its_object_again() -> void:
	var source: RefCounted = Fixture.new()
	var owner_object: RefCounted = Fixture.new()
	owner_object.number = 11
	source.other = owner_object
	source.callback = owner_object.ping
	var target: RefCounted = _round_trip(source)
	assert_true(target.callback.is_valid())
	assert_eq(target.callback.call(), 11)
	assert_same(target.callback.get_object(), target.other)


func test_an_empty_callable_stays_empty() -> void:
	var target: RefCounted = _round_trip(Fixture.new())
	assert_false(target.callback.is_valid())


func test_a_skipped_field_is_not_carried() -> void:
	var source: RefCounted = Fixture.new()
	source.skipped = 3
	var fields: Dictionary = StateCodec.new().fields_of(source)
	assert_false(fields.has("skipped"))
	assert_true(fields.has("number"))


## `a_source` through the codec and JSON into `a_target` (a new fixture by default).
func _round_trip(a_source: RefCounted, a_target: RefCounted = null) -> RefCounted:
	var encoder := StateCodec.new()
	var saved: Dictionary = SnapshotDiff.normalised(
		{"fields": encoder.fields_of(a_source), "objects": encoder.objects}
	)
	var target: RefCounted = a_target if a_target != null else Fixture.new()
	var decoder := StateCodec.new()
	decoder.objects = saved["objects"]
	# The source's own record stands in the table as the target, so a cycle back to it closes.
	decoder.bind_as(_root_id(encoder, a_source), target)
	decoder.adopt_fields(target, saved["fields"])
	decoder.decode_into(target, saved["fields"])
	return target


func _root_id(a_encoder: StateCodec, a_source: RefCounted) -> String:
	return a_encoder.id_of(a_source)
