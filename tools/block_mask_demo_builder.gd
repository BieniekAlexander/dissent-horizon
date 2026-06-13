extends RefCounted

## Builds a review scene for the blocked-mask layer: one GraphPlateau terrain with
## a connectivity-safe BlockMaskGenerator mask, rendered as the terrain mesh plus a
## red box per blocked cell.  Plain RefCounted so it runs from the editor wrapper
## or a headless harness.
##
## Preload and call: DemoBuilder.new().build()

const OUTPUT_DIR: String = "res://resources/block_mask_demo"
const SEED: int = 7
# Large 120×120 map.  cells_per_region keeps the plateau size we tuned earlier
# (~84 cells/region => the rc≈10 look at 30×30) so the bigger map gets MORE
# plateaus of the same size rather than a few giant ones.  Ramp width/length are
# absolute, so they stay proportional to those constant-size plateaus.
const MAP_SIZE: int = 120
const CELLS_PER_REGION: int = 84
const HEIGHT_LEVELS: int = 3
const HEIGHT_STEP: float = 1.0
const RAMP_HALF_WIDTH: float = 5.0
const RAMP_RUN: int = 5


func build() -> Dictionary:
	_ensure_dir()

	var w: int = MAP_SIZE
	var d: int = MAP_SIZE

	# Terrain.
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = w
	gen.depth = d
	gen.cells_per_region = CELLS_PER_REGION
	gen.height_levels = HEIGHT_LEVELS
	gen.height_step = HEIGHT_STEP
	gen.ramp_half_width = RAMP_HALF_WIDTH
	gen.ramp_run = RAMP_RUN
	gen.seed = SEED
	var heights: PackedFloat32Array = gen.generate()

	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = d
	shape.map_data = heights
	ResourceSaver.save(shape, OUTPUT_DIR + "/terrain.tres")

	# Blocked mask — blob COUNT scales with map area so coverage stays consistent;
	# blob sizes stay absolute (plateaus are a constant size).
	var num_cells: int = (w - 1) * (d - 1)
	var bm := BlockMaskGenerator.new()
	bm.seed = SEED
	bm.blob_count = maxi(6, roundi(6.0 * float(num_cells) / 841.0))
	bm.min_blob_size = 6
	bm.max_blob_size = 28
	var mask: PackedByteArray = bm.generate(heights, w, d)
	var blocked: int = 0
	for b: int in mask:
		if b != 0:
			blocked += 1

	# Scene: terrain mesh + red blocked-cell overlay + light + camera.
	var root := Node3D.new()
	root.name = "BlockMaskDemo"

	var mesh_gen := HeightmapMeshGenerator.new()
	mesh_gen.shape = shape
	mesh_gen.build()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh_gen.mesh
	mesh_gen.free()
	root.add_child(terrain)
	terrain.owner = root

	root.add_child(_build_block_overlay(heights, mask, w, d))
	root.get_child(root.get_child_count() - 1).owner = root

	_add_light_and_camera(root, w, d)

	var packed := PackedScene.new()
	packed.pack(root)
	var scene_path: String = OUTPUT_DIR + "/block_mask_demo.tscn"
	var err: int = ResourceSaver.save(packed, scene_path)
	root.free()

	return {"scene_path": scene_path, "ok": err == OK, "blocked": blocked, "cells": (w - 1) * (d - 1)}


## A MultiMeshInstance3D of red boxes, one per blocked cell, sitting on the surface.
func _build_block_overlay(heights: PackedFloat32Array, mask: PackedByteArray, w: int, d: int) -> MultiMeshInstance3D:
	var gw: int = w - 1
	var gh: int = d - 1
	var half_w: float = (w - 1) * 0.5
	var half_d: float = (d - 1) * 0.5

	var transforms: Array[Transform3D] = []
	for z: int in gh:
		for x: int in gw:
			if mask[z * gw + x] == 0:
				continue
			var hc: float = (heights[z * w + x] + heights[z * w + x + 1]
				+ heights[(z + 1) * w + x] + heights[(z + 1) * w + x + 1]) * 0.25
			var pos := Vector3(x + 0.5 - half_w, hc + 0.15, z + 0.5 - half_d)
			transforms.append(Transform3D(Basis.IDENTITY, pos))

	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.25, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.1, 0.1)
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BlockedCells"
	mmi.multimesh = mm
	return mmi


func _add_light_and_camera(root: Node3D, w: int, d: int) -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	light.light_energy = 1.1
	root.add_child(light)
	light.owner = root

	var cam := Camera3D.new()
	cam.name = "DemoCamera"
	cam.position = Vector3(0.0, float(maxi(w, d)) * 0.9, float(d) * 0.9)
	cam.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	cam.current = true
	root.add_child(cam)
	cam.owner = root


func _ensure_dir() -> void:
	var abs_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var e: int = DirAccess.make_dir_recursive_absolute(abs_path)
	if e != OK and e != ERR_ALREADY_EXISTS:
		push_error("BlockMaskDemo: could not create %s (error %d)" % [abs_path, e])
