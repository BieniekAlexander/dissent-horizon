@tool
class_name HeightmapGeneratorTool
extends Node3D

## Editor tool that runs a HeightmapGenerator and writes the result into a
## HeightMapShape3D, then rebuilds the visual mesh.
##
## Place this as a sibling of HeightmapMeshGenerator under the terrain StaticBody3D
## (Map/NavigationRegion/Body in s1.tscn).  Assign a generator Resource and the
## shared map.tres shape in the inspector, then click "Generate".

#region Properties
var _generator: HeightmapGenerator

## Re-entrancy guard: writing a random seed back can emit the generator's
## `changed` signal, which (with auto_generate_on_change) would call _do_generate
## again.  This blocks that recursion.
var _busy: bool = false

@export var generator: HeightmapGenerator:
	set(v):
		if _generator != null and _generator.changed.is_connected(_do_generate):
			_generator.changed.disconnect(_do_generate)
		_generator = v
		if _generator != null and auto_generate_on_change:
			_generator.changed.connect(_do_generate)
	get:
		return _generator

@export var shape: HeightMapShape3D

## Optional explicit reference to the HeightmapMeshGenerator that should be
## rebuilt after generation.  When null, falls back to a sibling node named
## "HeightmapMeshGenerator" in the same parent.
@export var mesh_generator: HeightmapMeshGenerator

## When true, re-generates automatically whenever any generator property changes.
@export var auto_generate_on_change: bool = false:
	set(v):
		auto_generate_on_change = v
		if _generator == null:
			return
		if v:
			if not _generator.changed.is_connected(_do_generate):
				_generator.changed.connect(_do_generate)
		else:
			if _generator.changed.is_connected(_do_generate):
				_generator.changed.disconnect(_do_generate)

## When true, each Generate first rolls a fresh random seed, uses it for the
## generation pass, and writes it back into the generator's `seed` field — so you
## can keep generating until you like a map, then turn this off to lock that seed.
## When false, the generator's current seed is used as-is.  No effect on
## generators that don't expose a `seed` property (e.g. the flat generator).
@export var random_next_seed: bool = false

@export_tool_button("Generate")
var _generate_button: Callable = _do_generate
#endregion

#region Private helpers
func _do_generate() -> void:
	if _busy:
		return
	if _generator == null:
		push_warning("HeightmapGeneratorTool: no generator assigned")
		return
	if shape == null:
		push_warning("HeightmapGeneratorTool: no shape assigned")
		return

	_busy = true

	# Roll and persist a new seed first, so it drives this generation pass.
	if random_next_seed:
		_apply_random_seed()

	# The generator's own width/depth drive the output; the shape is sized to match.
	# (Previously this synced the other way — overwriting the generator's width/depth
	# from the shape on every Generate, which silently reset values you'd edited.)
	var data: PackedFloat32Array = _generator.generate()
	shape.map_width = _generator.dimensions.x
	shape.map_depth = _generator.dimensions.y
	shape.map_data = data

	# Rebuild the visual mesh — same path used by HeightPin._on_pin_height_changed.
	var gen: HeightmapMeshGenerator = mesh_generator
	if gen == null:
		gen = get_parent().get_node_or_null("HeightmapMeshGenerator") as HeightmapMeshGenerator
	if gen != null:
		gen.build()

	_busy = false

## Assign a fresh random seed to the generator (when it exposes one) and emit
## `changed` so the inspector shows the new value.  Generators without a `seed`
## property (e.g. the flat generator) are simply left as-is — nothing to roll.
func _apply_random_seed() -> void:
	if not _generator_has_seed():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_generator.set("seed", int(rng.randi()))
	_generator.emit_changed()  # refresh the inspector to show the rolled seed

func _generator_has_seed() -> bool:
	for prop: Dictionary in _generator.get_property_list():
		if prop.get("name", "") == "seed":
			return true
	return false
#endregion
