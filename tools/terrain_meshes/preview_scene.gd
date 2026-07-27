extends Node3D

## Boots a mesh-terrain test scenario with fog off and its own camera, so the baked surface
## can be LOOKED at. Structural correctness is covered by tests; this answers "does the
## plateau read as vertical", which no assertion can.
##
## Run with (no --headless — this needs a renderer):
##   godot res://tools/terrain_meshes/preview_scene.tscn --write-movie <out.png> \
##     --fixed-fps 30 --quit-after 200 --resolution 1400x790 -- <res://scene.tscn> [overview|closeup]
##
## Uses its own Camera3D rather than the game's RTSCamera3D: that one clamps zoom to twice its
## authored framing and pans inside the play bounds, which is right for play and far too tight
## to frame a whole 160-unit map.

var _scene_path: String = ""
var _view: String = "overview"
var _keep_fog: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene_path = args[0]
	if args.size() >= 2:
		_view = args[1]
	_keep_fog = args.has("fog")
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		push_error("could not load %s" % _scene_path)
		get_tree().quit(2)
		return
	add_child(packed.instantiate())

	# Omniscient fog: -2 is the "No Fog" mode Scenario's own debug row selects. Pass "fog" as
	# the third argument to leave fog ON, for telling a terrain artifact apart from a fog one.
	if not _keep_fog:
		Fog.active_commander_id = -2

	# Let the navmesh build and Skirmish deploy its forces before framing anything.
	for _i: int in 90:
		await get_tree().physics_frame

	# Even ambient light, so the surface reads by its own vertex colours rather than by
	# whatever the scenario's single directional light happens to be doing.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	match _view:
		"profile":
			# Almost at ground level, so a raised plateau is unmistakable in silhouette
			# against the background rather than inferred from shading.
			camera.size = 60.0
			camera.position = Vector3(60.0, 6.0, 0.0)
			camera.look_at_from_position(camera.position, Vector3(0.0, 3.0, 0.0), Vector3.UP)
		"closeup":
			# Low and near, so the plateau wall is seen edge-on rather than from above.
			camera.size = 70.0
			camera.position = Vector3(46.0, 22.0, 46.0)
			camera.look_at_from_position(camera.position, Vector3(0.0, 3.0, 0.0), Vector3.UP)
		_:
			camera.size = 175.0
			camera.position = Vector3(110.0, 110.0, 110.0)
			camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	camera.far = 600.0
	add_child(camera)
	camera.make_current()

	# Hide the HUD so it does not cover the terrain.
	for control: Node in get_tree().get_nodes_in_group("_hud_root"):
		(control as CanvasItem).visible = false
	var layers: Array[Node] = []
	_collect_canvas_layers(get_tree().root, layers)
	for layer: Node in layers:
		(layer as CanvasLayer).visible = false


func _collect_canvas_layers(a_node: Node, a_out: Array[Node]) -> void:
	if a_node is CanvasLayer:
		a_out.append(a_node)
	for child: Node in a_node.get_children():
		_collect_canvas_layers(child, a_out)
