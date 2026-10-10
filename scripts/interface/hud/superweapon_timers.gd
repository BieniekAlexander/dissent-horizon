class_name SuperweaponTimers
extends VBoxContainer
## EVERY SUPERWEAPON IN THE MATCH AND HOW LONG UNTIL IT CAN FIRE — Zero Hour's countdown list,
## top right. One row per finished caster of a `global_alert:` ability, whoever owns it, in its
## owner's colour. Never where it is: the row is not clickable. Hidden while there are none.
## gdd/systems/ux/ui/alerts.md §Global alerts.

#region Constants
const REFRESH_SECONDS: float = 0.25
const WIDTH: float = 260.0
#endregion

#region Properties
var _center: AlertCenter = null
var _since_refresh: float = INF
#endregion


#region Lifecycle
func _ready() -> void:
	name = "SuperweaponTimers"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	visible = false


## Top right, under the scenario timer and the command error line.
func anchor_to_right_edge() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -WIDTH - 24.0
	offset_right = -24.0
	offset_top = 64.0


func _process(a_delta: float) -> void:
	_since_refresh += a_delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	refresh()


#endregion


#region Public API
func bind(a_center: AlertCenter) -> void:
	_center = a_center
	refresh()


## Rebuild the rows from the AlertCenter. Public so a test can step it.
func refresh() -> void:
	var rows: Array[Dictionary] = _center.superweapons() if _center != null else []
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["remaining_ticks"]) < int(b["remaining_ticks"])
	)
	while get_child_count() < rows.size():
		add_child(_make_row())
	while get_child_count() > rows.size():
		var extra: Node = get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()
	for i: int in rows.size():
		_fill_row(get_child(i) as Label, rows[i])
	visible = not rows.is_empty()


## "2:13", "READY" or "READY ×2" for a row.
static func countdown_text(a_row: Dictionary) -> String:
	var charges: int = int(a_row["charges"])
	if charges > 0:
		return "READY" if charges == 1 else "READY ×%d" % charges
	var seconds: int = ceili(TimeUtils.seconds_from_ticks(int(a_row["remaining_ticks"])))
	return "%d:%02d" % [seconds / 60, seconds % 60]


#endregion


#region Private helpers
func _make_row() -> Label:
	var row := Label.new()
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_theme_font_size_override("font_size", 14)
	row.add_theme_color_override("font_outline_color", Color.BLACK)
	row.add_theme_constant_override("outline_size", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A dark plate, as the alert toasts have: a team colour must read on any terrain.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.06, 0.07, 0.09, 0.85)
	plate.content_margin_left = 8.0
	plate.content_margin_right = 8.0
	plate.content_margin_top = 2.0
	plate.content_margin_bottom = 2.0
	row.add_theme_stylebox_override("normal", plate)
	return row


func _fill_row(a_row: Label, a_data: Dictionary) -> void:
	var owner: int = int(a_data["owner"])
	a_row.text = "%s  %s" % [a_data["title"], countdown_text(a_data)]
	a_row.add_theme_color_override(
		"font_color", Entity.TEAM_COLOR_MAP.get(owner, Color.WHITE) as Color
	)
#endregion
