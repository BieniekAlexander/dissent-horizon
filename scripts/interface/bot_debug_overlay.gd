class_name BotDebugOverlay
extends Node3D

## In-world debug visualisation of a single bot's internal state, one CATEGORY of signals at a
## time: world marks drawn by the category's BotDebugLayer, and its scalars as a text readout in
## the top-right corner.
##
## Gated two ways, matching the rest of the game's debug HUD:
##   1. Only drawn while the debug view is up (DebugMode.is_active()) — the same gate
##      that reveals unit command labels.
##   2. Only ever shows ONE bot: the one currently selected by the bot-view toggle
##      (Fog.active_commander_id, the spectator POV button). When the active view isn't a
##      specific bot (player view / omniscient), nothing is drawn.
##
## Which category shows is `active_category`, chosen from the spectator HUD's
## BotDebugCategoryBar. Created once per session by Scenario._ready. A new category is an enum
## member, a label, and a layer in `_layers`; the catalogue of what each will carry is
## gdd/systems/ai/debug-signals.md.

enum Category {
	OFF,
	SCOUTING,
	ENEMY_PICTURE,
	BASE_DEFENCE,
	ARMY,
	ECONOMY,
	UNIT_CONTROL,
	INTERNALS,
}

const CATEGORY_LABELS: Dictionary = {
	Category.OFF: "Off",
	Category.SCOUTING: "Scouting",
	Category.ENEMY_PICTURE: "Enemy picture",
	Category.BASE_DEFENCE: "Base defence",
	Category.ARMY: "Army",
	Category.ECONOMY: "Economy",
	Category.UNIT_CONTROL: "Unit control",
	Category.INTERNALS: "Bot internals",
}
## What a session starts on: the scout coverage the overlay drew before it had categories.
const DEFAULT_CATEGORY: Category = Category.SCOUTING
## Seconds between readout refreshes. The marks redraw every frame; the text reads derived
## figures (the counter-demand map), which need not cost a frame's worth each.
const READOUT_PERIOD_SECONDS: float = 0.25
## Gap between the readout panel and the screen's right edge, in pixels.
const READOUT_MARGIN: float = 8.0
## Gap above the readout panel, in pixels: enough to clear the match clock in that corner.
const READOUT_TOP_MARGIN: float = 48.0

## The category being drawn. Static, like Fog.active_commander_id and DebugMode, because its
## writer (the spectator HUD) and this overlay share nothing but the session; reset on exit so
## it never outlives one.
static var active_category: Category = DEFAULT_CATEGORY

## The scenario this overlay belongs to; supplies the commander list. Set on creation.
var scenario: Scenario

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
## Category → its layer. Layers are stateless; built once rather than per frame.
var _layers: Dictionary = {
	Category.SCOUTING: BotDebugScoutingLayer.new(),
	Category.ENEMY_PICTURE: BotDebugEnemyPictureLayer.new(),
	Category.BASE_DEFENCE: BotDebugBaseDefenceLayer.new(),
	Category.ARMY: BotDebugArmyLayer.new(),
	Category.ECONOMY: BotDebugEconomyLayer.new(),
	Category.UNIT_CONTROL: BotDebugUnitControlLayer.new(),
	Category.INTERNALS: BotDebugInternalsLayer.new(),
}
var _readout_panel: PanelContainer
var _readout_label: Label
## Seconds since the readout last refreshed, and what it was refreshed for: a change of category
## or bot refreshes it at once rather than at the next period.
var _readout_age: float = INF
var _readout_key: Vector2i = Vector2i(-1, -1)


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
	_build_readout()


func _exit_tree() -> void:
	active_category = DEFAULT_CATEGORY


func _process(a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_mesh.clear_surfaces()
	var layer: BotDebugLayer = _layers.get(active_category)
	# Gate 1: the shared debug view. Gate 2: a specific bot must be the active view.
	var bot: Bot = _active_bot() if DebugMode.is_active() else null
	_readout_panel.visible = layer != null and bot != null
	if not _readout_panel.visible:
		return
	var pen := BotDebugPen.new()
	layer.draw(bot, pen)
	pen.flush(_mesh, global_transform.affine_inverse())
	_refresh_readout(layer, bot, a_delta)


## The readout text currently shown, header included; empty while nothing is drawn.
func readout_text() -> String:
	return _readout_label.text if _readout_panel.visible else ""


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


# ─── READOUT ─────────────────────────────────────────────────────────────────


func _build_readout() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Readout"
	add_child(canvas)
	_readout_panel = PanelContainer.new()
	_readout_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_readout_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_readout_panel.offset_right = -READOUT_MARGIN
	_readout_panel.offset_top = READOUT_TOP_MARGIN
	_readout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_panel.visible = false
	canvas.add_child(_readout_panel)
	_readout_label = Label.new()
	_readout_panel.add_child(_readout_label)


func _refresh_readout(a_layer: BotDebugLayer, a_bot: Bot, a_delta: float) -> void:
	var key := Vector2i(active_category, a_bot.id)
	_readout_age += a_delta
	if key == _readout_key and _readout_age < READOUT_PERIOD_SECONDS:
		return
	_readout_key = key
	_readout_age = 0.0
	var lines: PackedStringArray = a_layer.readout(a_bot)
	lines.insert(0, "Bot %d — %s" % [a_bot.id, CATEGORY_LABELS[active_category]])
	_readout_label.text = "\n".join(lines)
