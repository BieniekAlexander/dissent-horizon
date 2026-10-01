extends Node

## Renders a map at the game's camera angle and writes PNGs, so terrain, lighting and
## decoration changes can be reviewed without opening the editor. Needs a real renderer (not
## --headless); on a machine with no display, xvfb plus the Compatibility renderer works:
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1600x900 res://tools/terrain_visuals/visual_preview.tscn \
##     -- scene=res://scenes/scenarios/generated/gen_01.tscn out=/tmp/preview
##
## Arguments (after `--`):
##   scene=   a map scene (root is a Map) or a scenario scene (its `Map` child is taken out
##            and shown alone, so no commander, HUD or bot boots)
##   out=     output directory; one PNG per shot, named <shot>.png
##   shots=   semicolon-separated `name:x,z,size` (world XZ focus, orthographic size);
##            defaults to a whole-map overview plus a game-zoom shot at the map centre
##   rig=     0 to render with no lighting rig added (the scene's own lights only)
##   facets=  1 to draw MapDecorator's facet markers (where later dressing would go)
##
## A tool, not a test: what it checks is whether the picture reads, which only a person can
## judge (CLAUDE.md "Seeing the HUD without a screen" is the same idea for the HUD).

## Frames to let the scene settle (deferred initialisation, first navmesh, shader compile)
## before the first capture.
const SETTLE_FRAMES: int = 8
## How much of the map's larger extent the overview shot frames.
const OVERVIEW_FRAMING: float = 0.75
## The player camera's authored orthographic size (scenes/player.tscn), i.e. game zoom.
const GAME_ZOOM_SIZE: float = 15.0
## Far enough back that no terrain or tall model on the map crosses the near plane.
const CAMERA_DISTANCE: float = 150.0
const DEFAULT_RIG: String = "res://scenes/environment/default_lighting.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var map: Map = _load_map(String(args.get("scene", "")))
	if map == null:
		push_error("visual_preview: could not load a Map from scene=%s" % args.get("scene", ""))
		get_tree().quit(1)
		return
	var holder := Node3D.new()
	holder.name = "Preview"
	add_child(holder)
	holder.add_child(map)
	if String(args.get("facets", "0")) == "1" and map.decorator != null:
		map.decorator.show_facet_markers = true
		map.rebuild_decoration()
	if String(args.get("rig", "1")) != "0" and ResourceLoader.exists(DEFAULT_RIG):
		holder.add_child((load(DEFAULT_RIG) as PackedScene).instantiate())

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 2000.0
	holder.add_child(camera)
	camera.make_current()

	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame

	var out_dir: String = String(args.get("out", "user://visual_preview"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	for shot: Dictionary in _shots(args, map):
		_frame(camera, map, shot.focus, shot.size)
		for _i: int in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = out_dir.path_join("%s.png" % shot.name)
		get_viewport().get_texture().get_image().save_png(path)
		print("visual_preview: wrote ", path)
	get_tree().quit(0)


func _load_map(a_path: String) -> Map:
	var packed := load(a_path) as PackedScene
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	if node is Map:
		return node as Map
	var map := node.get_node_or_null("Map") as Map
	if map == null:
		node.free()
		return null
	node.remove_child(map)
	# The scenario shell is never entered into the tree, so freeing it runs no game logic.
	node.free()
	_strip_owner(map, map)
	return map


## Children taken out of a scene keep their old owner; re-own them so nothing dangles.
static func _strip_owner(node: Node, new_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = new_owner
		_strip_owner(child, new_owner)


func _shots(a_args: Dictionary, a_map: Map) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	if a_args.has("shots"):
		for spec: String in String(a_args.shots).split(";", false):
			var parts: PackedStringArray = spec.split(":")
			var nums: PackedStringArray = parts[1].split(",")
			shots.append({
				"name": parts[0],
				"focus": Vector2(float(nums[0]), float(nums[1])),
				"size": float(nums[2]),
			})
		return shots
	var bounds: Rect2 = a_map.world_bounds()
	shots.append({"name": "overview", "focus": bounds.get_center(),
		"size": maxf(bounds.size.x, bounds.size.y) * OVERVIEW_FRAMING})
	shots.append({"name": "game_zoom", "focus": bounds.get_center(), "size": GAME_ZOOM_SIZE})
	return shots


## Place the camera at the game's pitch and yaw (RTSCamera3D's constants), looking at the
## terrain under the focus point.
static func _frame(a_camera: Camera3D, a_map: Map, a_focus: Vector2, a_size: float) -> void:
	var target := Vector3(a_focus.x, a_map.terrain_height_at(a_focus), a_focus.y)
	var offset: Vector3 = RTSCamera3D.initial_position().normalized() * CAMERA_DISTANCE
	a_camera.size = a_size
	a_camera.global_position = target + offset
	a_camera.look_at(target, Vector3.UP)


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in args:
		var eq: int = arg.find("=")
		if eq > 0:
			parsed[arg.substr(0, eq)] = arg.substr(eq + 1)
	return parsed
