class_name BotDebugOverlay
extends Node3D

## In-world debug visualisation of a single bot's internal state.
##
## Gated two ways, matching the rest of the game's debug HUD:
##   1. Only drawn while the "debug_info" action (hold Spacebar) is held — the same gate
##      that reveals unit command labels.
##   2. Only ever shows ONE bot: the one currently selected by the bot-view toggle
##      (Fog.active_commander_id, the spectator POV button). When the active view isn't a
##      specific bot (player view / omniscient), nothing is drawn.
##
## Created once per session by Scenario._ready. Extend _draw_overlay() to add more bot-debug
## layers later; for now it renders the scout coverage grid.
##
## Scout coverage: a flat marker at each scout-grid point, coloured by how recently the bot
## last saw it — green (just scouted) → red (stale, about to expire) — with never-seen
## points drawn grey. A short stick rises from each so the markers read from the iso camera.

#region Tuning
## Half-size (world units) of each ground marker.
const MARKER_HALF: float = 0.35
## Height of the stick rising from each marker.
const STICK_HEIGHT: float = 0.8
## Lift markers slightly off the terrain so they don't z-fight the ground.
const Y_LIFT: float = 0.1

const COLOR_FRESH: Color = Color(0.2, 1.0, 0.3)   # just scouted
const COLOR_STALE: Color = Color(1.0, 0.2, 0.2)   # about to expire
const COLOR_NEVER: Color = Color(0.45, 0.45, 0.5) # never in line of sight
#endregion

## The scenario this overlay belongs to; supplies the commander list. Set on creation.
var scenario: Scenario

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	# Unshaded vertex colours, drawn over the terrain — same recipe as CommandLineIndicator.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_mesh.clear_surfaces()
	# Gate 1: the shared "hold to show debug" action.
	if not Input.is_action_pressed("debug_info"):
		return
	# Gate 2: a specific bot must be the active view.
	var bot: Bot = _active_bot()
	if bot == null:
		return
	_draw_overlay(bot)


## Draw every enabled debug layer for [bot]. Add more layers here as they're built.
func _draw_overlay(bot: Bot) -> void:
	_draw_scout_coverage(bot)


# ─── ACTIVE BOT RESOLUTION ───────────────────────────────────────────────────

## The bot currently selected by the bot-view toggle, or null when the active view isn't a
## specific bot (player view = -1, omniscient = -2) or that commander isn't a Bot.
func _active_bot() -> Bot:
	if scenario == null:
		return null
	var id: int = Fog.active_commander_id
	if id < 1:
		return null
	for c: Commander in scenario.commanders:
		if c.id == id and c is Bot:
			return c as Bot
	return null


# ─── SCOUT COVERAGE LAYER ────────────────────────────────────────────────────

func _draw_scout_coverage(bot: Bot) -> void:
	var brain: BotBrain = bot.get_node_or_null("BotBrain") as BotBrain
	if brain == null:
		return
	var scout: BotScout = brain.get_scout()
	if scout == null:
		return  # managers not built yet (before the first think)

	var now: float = bot.seconds_elapsed()
	var points: Array = scout.debug_points()
	if points.is_empty():
		return

	# One surface for the filled ground markers (translucent quads)...
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Dictionary in points:
		_add_marker_quad(p["position"], _recency_color(p["last_seen"], p["ever_seen"], now))
	_mesh.surface_end()

	# ...and one for the opaque sticks, so the points read against the terrain.
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for p: Dictionary in points:
		var color: Color = _recency_color(p["last_seen"], p["ever_seen"], now)
		color.a = 1.0
		_add_stick(p["position"], color)
	_mesh.surface_end()


## Green (just scouted) → red (stale at SCOUT_EXPIRATION_TIMER); grey if never seen.
func _recency_color(last_seen: float, ever_seen: bool, now: float) -> Color:
	if not ever_seen:
		return COLOR_NEVER
	var age: float = now - last_seen
	var t: float = clampf(age / BotScout.SCOUT_EXPIRATION_TIMER, 0.0, 1.0)
	var c: Color = COLOR_FRESH.lerp(COLOR_STALE, t)
	c.a = 0.55
	return c


## A flat square centred on `world_pos`, slightly lifted, as two triangles.
func _add_marker_quad(world_pos: Vector3, color: Color) -> void:
	var c: Vector3 = to_local(world_pos) + Vector3(0.0, Y_LIFT, 0.0)
	var a: Vector3 = c + Vector3(-MARKER_HALF, 0.0, -MARKER_HALF)
	var b: Vector3 = c + Vector3(MARKER_HALF, 0.0, -MARKER_HALF)
	var d: Vector3 = c + Vector3(MARKER_HALF, 0.0, MARKER_HALF)
	var e: Vector3 = c + Vector3(-MARKER_HALF, 0.0, MARKER_HALF)
	_mesh.surface_set_color(color)
	for v: Vector3 in [a, b, d, a, d, e]:
		_mesh.surface_add_vertex(v)


## A short vertical line rising from `world_pos`.
func _add_stick(world_pos: Vector3, color: Color) -> void:
	var base: Vector3 = to_local(world_pos) + Vector3(0.0, Y_LIFT, 0.0)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(base)
	_mesh.surface_add_vertex(base + Vector3(0.0, STICK_HEIGHT, 0.0))
