extends RefCounted

## Builds a self-contained editor scene for generating heightmaps interactively:
##   scenes/tools/heightmap_workbench.tscn
##
## The scene wires a HeightmapGeneratorTool to a GraphPlateauHeightmapGenerator
## and a 120×120 HeightMapShape3D, plus a HeightmapMeshGenerator to show the
## result and a framed camera + light.  Open the scene, select the
## "HeightmapGeneratorTool" node, edit the generator's params in the inspector,
## and click the "Generate" button to (re)build the terrain.  Save terrain.tres
## (or drag it onto Map.height_map) to use the result in the game.
##
## Plain RefCounted so it runs from the editor wrapper or a headless harness.

const OUTPUT_DIR: String = "res://resources/heightmap_workbench"
const SCENE_PATH: String = "res://scenes/tools/heightmap_workbench.tscn"
const GENERATOR_PATH: String = OUTPUT_DIR + "/graph_plateau.tres"
const TERRAIN_PATH: String = OUTPUT_DIR + "/terrain.tres"
const MESH_PATH: String = OUTPUT_DIR + "/terrain_mesh.res"

const MAP_SIZE: int = 120
const CELLS_PER_REGION: int = 84
const SEED: int = 7


func build() -> Dictionary:
	_ensure_dirs()

	# 1. Generator resource (saved + reloaded so the scene references it as a
	#    shared ExtResource the user can edit in the inspector).
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = MAP_SIZE
	gen.depth = MAP_SIZE
	gen.cells_per_region = CELLS_PER_REGION
	gen.height_levels = 3
	gen.height_step = 1.0
	gen.ramp_half_width = 5.0
	gen.ramp_run = 5
	gen.seed = SEED
	ResourceSaver.save(gen, GENERATOR_PATH)
	var gen_res: GraphPlateauHeightmapGenerator = ResourceLoader.load(GENERATOR_PATH)

	# 2. Shape resource, pre-generated so the scene shows terrain on open.
	var shape := HeightMapShape3D.new()
	shape.map_width = MAP_SIZE
	shape.map_depth = MAP_SIZE
	shape.map_data = gen_res.generate()
	ResourceSaver.save(shape, TERRAIN_PATH)
	var shape_res: HeightMapShape3D = ResourceLoader.load(TERRAIN_PATH)

	# 3. Pre-build the visual mesh, saved as its own .res so it is referenced (not
	#    embedded — a 120×120 mesh embedded would bloat the .tscn to megabytes).
	var mesh_tmp := HeightmapMeshGenerator.new()
	mesh_tmp.shape = shape_res
	mesh_tmp.build()
	ResourceSaver.save(mesh_tmp.mesh, MESH_PATH)
	mesh_tmp.free()
	var mesh: ArrayMesh = ResourceLoader.load(MESH_PATH)

	# 4. Assemble the scene.
	var root := Node3D.new()
	root.name = "HeightmapWorkbench"

	var terrain := Node3D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root

	var meshgen := HeightmapMeshGenerator.new()
	meshgen.name = "HeightmapMeshGenerator"
	meshgen.shape = shape_res
	terrain.add_child(meshgen)
	meshgen.owner = root
	meshgen.mesh = mesh  # shown on open; HeightmapGeneratorTool rebuilds it on Generate

	var gen_tool := HeightmapGeneratorTool.new()
	gen_tool.name = "HeightmapGeneratorTool"
	gen_tool.generator = gen_res
	gen_tool.shape = shape_res
	gen_tool.mesh_generator = meshgen
	terrain.add_child(gen_tool)
	gen_tool.owner = root

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)
	sun.owner = root

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, MAP_SIZE * 1.05, MAP_SIZE * 1.15)
	cam.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
	cam.far = MAP_SIZE * 6.0
	cam.current = true
	root.add_child(cam)
	cam.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	var err: int = ResourceSaver.save(packed, SCENE_PATH)
	root.free()

	return {"scene_path": SCENE_PATH, "ok": err == OK, "generator": GENERATOR_PATH, "terrain": TERRAIN_PATH}


func _ensure_dirs() -> void:
	for dir: String in [OUTPUT_DIR, "res://scenes/tools"]:
		var abs_path: String = ProjectSettings.globalize_path(dir)
		var e: int = DirAccess.make_dir_recursive_absolute(abs_path)
		if e != OK and e != ERR_ALREADY_EXISTS:
			push_error("HeightmapWorkbench: could not create %s (error %d)" % [abs_path, e])
