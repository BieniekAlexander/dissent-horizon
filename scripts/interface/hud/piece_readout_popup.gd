class_name PieceReadoutPopup
extends PanelContainer

## The depth behind one readout widget: the popup a click on it toggles, listing the fields the
## widget stands for (gdd/systems/ux/ui/piece-readouts.md §Three tiers). Clicking anywhere
## outside it closes it.
##
## ONE POPUP, TWO READERS. For a player its rows are the running piece's values, read-only;
## in debug mode they are the piece's doc, editable through the TuningSession
## (debug-tuning.md). Holding `ui_verbose` adds the deeper fields in both.
##
## Built in code like the widget row that owns it. Every row is a PieceFieldRow, so a field
## is drawn one way wherever it appears.

const WIDTH: float = 400.0
## The share of the viewport's height the popup may take before it scrolls.
const MAX_HEIGHT_FRACTION: float = 0.6
## Space between the popup and the widget it belongs to.
const GAP: float = 6.0
const NOTE_FONT_SIZE: int = 11
const NOTE_COLOR: Color = Color(0.6, 0.63, 0.59)
const ERROR_COLOR: Color = Color(1.0, 0.45, 0.4)
## The phase a debug "add phase" appends: an impact that applies the payload once and ends.
const NEW_PHASE: Dictionary = {"lifespan": 0, "payload": "once"}

var _widget: StringName = &""
var _piece: Actor = null
var _anchor: Control = null
var _rows: VBoxContainer
var _scroll: ScrollContainer
## Whether the content was last built with verbose rows / in debug mode, so it is rebuilt only
## when either changes.
var _built_verbose: bool = false
var _built_debug: bool = false
## Emission scenes instantiated OUT OF TREE to read their payload and phases, one per scene,
## freed when the popup closes. Memoized because a rebuild re-reads them on every verbose toggle.
var _prototypes: Dictionary = {}
var _session: TuningSession = null


func _init() -> void:
	top_level = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(RTSController.SELECTION_BLOCKING_UI_GROUP)
	custom_minimum_size.x = WIDTH
	# Grows with its content up to MAX_HEIGHT_FRACTION of the screen, then scrolls on a bar at
	# its right edge: a projectile's phases unfolded can run far past the screen.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	_scroll.add_child(_rows)


#region Public API
## Whether a click on `a_widget` opens anything: the weapon's specifics always, every other
## widget only for its verbose rows — or for editing, in debug mode.
static func opens(a_widget: StringName, a_is_verbose: bool, a_is_debug: bool) -> bool:
	return a_widget == &"weapon" or a_is_verbose or a_is_debug


## Open the popup for `a_widget` of `a_piece` beside `a_anchor`, or close it if that is what is
## open already.
func toggle(a_widget: StringName, a_piece: Actor, a_anchor: Control) -> void:
	if visible and a_widget == _widget and a_piece == _piece:
		close()
		return
	if not opens(a_widget, _is_verbose(), DebugMode.is_active()):
		close()
		return
	_widget = a_widget
	_piece = a_piece
	_anchor = a_anchor
	if DebugMode.is_active():
		_session = TuningSession.of(self)
		if not _session.changed.is_connected(_on_session_changed):
			_session.changed.connect(_on_session_changed)
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	_widget = &""
	_piece = null
	_clear_rows()
	for scene: Variant in _prototypes:
		(_prototypes[scene] as Node).free()
	_prototypes.clear()


#endregion


#region Lifecycle
func _process(_a_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_piece) or not is_instance_valid(_anchor):
		close()
		return
	if not _anchor.is_visible_in_tree():
		close()
		return
	if _is_verbose() != _built_verbose or DebugMode.is_active() != _built_debug:
		_rebuild()
	_place()


## A press outside the popup — and outside the widget that toggles it — closes it. The press
## is not consumed: it still does whatever it does where it lands.
func _input(a_event: InputEvent) -> void:
	if not visible or not (a_event is InputEventMouseButton) or not a_event.pressed:
		return
	var at: Vector2 = (a_event as InputEventMouseButton).position
	if get_global_rect().has_point(at):
		return
	if is_instance_valid(_anchor) and _anchor.get_global_rect().has_point(at):
		return
	close()


func _on_session_changed() -> void:
	# Rebuilt after the edit settles, and never under a field being typed into.
	if visible and not (get_viewport().gui_get_focus_owner() is LineEdit):
		_rebuild.call_deferred()


#endregion


#region Building
func _rebuild() -> void:
	if not visible or not is_instance_valid(_piece):
		return
	_built_verbose = _is_verbose()
	_built_debug = DebugMode.is_active()
	_clear_rows()
	match _widget:
		&"weapon":
			_build_weapons()
		&"name":
			_build_pools()
		_:
			_build_fields(PieceFields.of_widget(_widget), {"node": _piece}, _piece_address())
	if _rows.get_child_count() == 0:
		_rows.add_child(_note("Nothing more to show here."))
	reset_size()


func _build_fields(a_fields: Array[PieceField], a_ctx: Dictionary, a_address: Dictionary) -> void:
	for field: PieceField in a_fields:
		if field.scope != PieceField.Scope.PIECE or not _shows(field):
			continue
		if not field.is_applicable(a_ctx):
			continue
		_rows.add_child(_row(field, a_ctx, a_address, 0))


func _build_weapons() -> void:
	var loadout: Node = _piece.get_node_or_null("Loadout")
	if loadout == null:
		return
	for weapon: Node in loadout.get_children():
		if weapon is Weapon:
			_build_weapon(weapon as Weapon)


## One weapon, folded under its name and what it deals: its own fields, then the projectile it
## fires.
func _build_weapon(a_weapon: Weapon) -> void:
	var index: int = _doc_weapon_index(a_weapon)
	var key: String = "%s/%s" % [_piece.id, a_weapon.name]
	var type_name: String = PieceFields.enum_name(Damage.Type, a_weapon.per_shot_damage_type())
	var section := CollapsibleSection.make(
		key,
		(
			"%s — ~%s dps, %s"
			% [a_weapon.name, PieceFields._figure(a_weapon.approximate_dps()), type_name.to_lower()]
		),
		true
	)
	_rows.add_child(section)
	var weapon_ctx: Dictionary = {"node": a_weapon, "piece": _piece}
	var weapon_address: Dictionary = (
		_session.weapon_address(_piece.id, index) if _is_editing() else {}
	)
	for field: PieceField in PieceFields.of_scope(PieceField.Scope.WEAPON):
		if _shows(field) and field.is_applicable(weapon_ctx):
			section.body.add_child(_row(field, weapon_ctx, weapon_address, index))
	if a_weapon.projectile_scene != null:
		_build_projectile(section.body, a_weapon, index, key)


## The projectile a weapon fires, reached through the weapon: its payload, then — while verbose
## — the matchup multipliers and its phases.
func _build_projectile(a_into: Container, a_weapon: Weapon, a_index: int, a_key: String) -> void:
	var emission: Node = _prototype(a_weapon.projectile_scene)
	var ctx: Dictionary = {"node": emission}
	var address: Dictionary = _session.emission_address(_piece.id, a_index) if _is_editing() else {}
	var section := CollapsibleSection.make(
		a_key + "/projectile", "projectile: %s" % _projectile_title(emission, address), true, true
	)
	a_into.add_child(section)
	for field: PieceField in PieceFields.of_scope(PieceField.Scope.EMISSION):
		if _shows(field) and (_is_editing() or field.read_raw(ctx) != null):
			section.body.add_child(_row(field, ctx, address, a_index))
	if not _built_verbose:
		return
	section.body.add_child(_note(_multipliers(a_weapon.per_shot_damage_type())))
	if _is_editing() and not address.is_empty():
		_build_editable_phases(section.body, emission, address, a_index, a_key)
	else:
		_build_phases(section.body, emission, a_key)


## A projectile's name: its doc's title while editing, else its id or scene.
func _projectile_title(a_emission: Node, a_address: Dictionary) -> String:
	if not a_address.is_empty():
		var title: Variant = _session.value_at(a_address, ["title"])
		if title != null:
			return str(title)
		return String(_session.emission_id(a_address))
	# The doc's title is not in the game; an inline emission has no id of its own either, so the
	# scene it was built into is the most specific name the running game holds.
	var id: StringName = (a_emission as Entity).id if a_emission is Entity else &""
	if not id.is_empty():
		return String(id).replace("_", " ")
	var scene: String = a_emission.scene_file_path.get_file().get_basename()
	return scene.replace("_", " ") if not scene.is_empty() else String(a_emission.name)


## The phases a player reads: each EmissionPhase of the emission, in the order it runs them,
## each folded under its name inside one folded list.
func _build_phases(a_into: Container, a_emission: Node, a_key: String) -> void:
	var phases: Array = a_emission.get_children().filter(
		func(c: Node) -> bool: return c is EmissionPhase
	)
	var list := CollapsibleSection.make(
		a_key + "/phases", "phases (%d)" % phases.size(), true, true
	)
	a_into.add_child(list)
	for j: int in phases.size():
		var phase: Node = phases[j]
		var section := CollapsibleSection.make(
			"%s/phases/%s" % [a_key, phase.name], "%d. %s" % [j + 1, phase.name], true, true
		)
		list.body.add_child(section)
		var ctx: Dictionary = {"node": phase}
		for field: PieceField in PieceFields.of_scope(PieceField.Scope.PHASE):
			if field.doc_path != ["name"] and field.read.is_valid() and field.is_applicable(ctx):
				section.body.add_child(PieceFieldRow.reading(field, ctx))


## The phases as the doc lists them, each editable and folded (a phase is twenty fields), with
## the list itself editable around them: move, remove, add.
func _build_editable_phases(
	a_into: Container, a_emission: Node, a_address: Dictionary, a_index: int, a_key: String
) -> void:
	var phases: Array = _session.phases_of(a_address)
	var list := CollapsibleSection.make(
		a_key + "/phases", "phases (%d)" % phases.size(), true, true
	)
	a_into.add_child(list)
	for error: String in _session.emission_errors(a_address):
		list.body.add_child(_note(error, ERROR_COLOR))
	for j: int in phases.size():
		var phase_name: String = _session.phase_name(phases, j)
		var section := CollapsibleSection.make(
			"%s/phases/%d" % [a_key, j], "%d. %s" % [j + 1, phase_name], false, true
		)
		_add_phase_controls(section.header, phases, j, a_address)
		list.body.add_child(section)
		var node: Node = a_emission.get_node_or_null(phase_name)
		var ctx: Dictionary = {"node": node} if node is EmissionPhase else {}
		var address: Dictionary = _session.phase_address(a_address, j)
		for field: PieceField in PieceFields.of_scope(PieceField.Scope.PHASE):
			section.body.add_child(
				PieceFieldRow.editing(field, ctx, _session, address, _piece.id, a_index)
			)
	var add := Button.new()
	add.text = "+ add phase"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(func() -> void: _edit_phases(a_address, phases + [NEW_PHASE.duplicate()]))
	list.body.add_child(add)


## Move up, move down and remove, on a phase's title row.
func _add_phase_controls(
	a_header: HBoxContainer, a_phases: Array, a_at: int, a_address: Dictionary
) -> void:
	for spec: Array in [["↑", -1], ["↓", 1], ["✕", 0]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		var step: int = spec[1]
		button.pressed.connect(
			func() -> void:
				var phases: Array = a_phases.duplicate(true)
				if step == 0:
					if phases.size() > 1:
						phases.remove_at(a_at)
				else:
					var to: int = clampi(a_at + step, 0, phases.size() - 1)
					var moved: Variant = phases[a_at]
					phases[a_at] = phases[to]
					phases[to] = moved
				_edit_phases(a_address, phases)
		)
		a_header.add_child(button)


func _edit_phases(a_address: Dictionary, a_phases: Array) -> void:
	var error: String = _session.set_phases(a_address, a_phases)
	if not error.is_empty():
		_rows.add_child(_note(error, ERROR_COLOR))


func _build_pools() -> void:
	var abilities: Abilities = _piece.get_node_or_null("Abilities") as Abilities
	if abilities == null or not _built_verbose:
		return
	for i: int in abilities.groups.size():
		var grants: Array = abilities.groups[i].get("grants", [])
		var section := CollapsibleSection.make(
			"%s/pool/%d" % [_piece.id, i], "charges for %s" % ", ".join(grants), true
		)
		_rows.add_child(section)
		var ctx: Dictionary = {"node": abilities, "index": i}
		var address: Dictionary = _session.pool_address(_piece.id, i) if _is_editing() else {}
		for field: PieceField in PieceFields.of_scope(PieceField.Scope.POOL):
			if _shows(field):
				section.body.add_child(_row(field, ctx, address, i))


#endregion


#region Pieces of the popup
func _row(a_field: PieceField, a_ctx: Dictionary, a_address: Dictionary, a_index: int) -> Control:
	if _is_editing() and not a_address.is_empty():
		return PieceFieldRow.editing(a_field, a_ctx, _session, a_address, _piece.id, a_index)
	return PieceFieldRow.reading(a_field, a_ctx)


## Whether a field's tier is shown: verbose fields only while `ui_verbose` is held.
func _shows(a_field: PieceField) -> bool:
	return a_field.tier != PieceField.Tier.VERBOSE or _built_verbose


func _is_editing() -> bool:
	return _built_debug and _session != null


func _piece_address() -> Dictionary:
	return _session.piece_address(_piece.id) if _is_editing() else {}


## Which `weapons:` item a Loadout weapon is: the doc matches weapons by name. Without a doc,
## its place among the Loadout's weapons.
func _doc_weapon_index(a_weapon: Weapon) -> int:
	if _is_editing():
		var weapons: Variant = _session.value_at(_session.piece_address(_piece.id), ["weapons"])
		if weapons is Array:
			for i: int in (weapons as Array).size():
				if str((weapons[i] as Dictionary).get("name", "")) == String(a_weapon.name):
					return i
	return a_weapon.get_index()


func _prototype(a_scene: PackedScene) -> Node:
	if not _prototypes.has(a_scene):
		_prototypes[a_scene] = a_scene.instantiate()
	return _prototypes[a_scene]


## One damage type against every armour and frame — the matchup table's row for it.
static func _multipliers(a_type: Damage.Type) -> String:
	var parts: Array = []
	for armour: String in Defense.ArmourType:
		parts.append(
			(
				"%s ×%s"
				% [
					armour.to_lower(),
					PieceFields._figure(
						DamageTable.get_armour_multiplier(a_type, Defense.ArmourType[armour])
					)
				]
			)
		)
	for frame: String in Defense.FrameType:
		parts.append(
			(
				"%s ×%s"
				% [
					frame.to_lower(),
					PieceFields._figure(
						DamageTable.get_frame_multiplier(a_type, Defense.FrameType[frame])
					)
				]
			)
		)
	return "multipliers: " + ", ".join(parts)


func _note(a_text: String, a_color: Color = NOTE_COLOR) -> Label:
	var label := Label.new()
	label.text = a_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - GAP * 2
	label.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	label.add_theme_color_override("font_color", a_color)
	return label


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## Above the widget, kept inside the viewport.
func _place() -> void:
	var viewport: Rect2 = get_viewport_rect()
	var height: float = minf(
		_rows.get_combined_minimum_size().y, viewport.size.y * MAX_HEIGHT_FRACTION
	)
	_scroll.custom_minimum_size.y = height
	# Shrunk to its content every frame: a popup that held a longer list keeps its old size
	# otherwise, and is placed by it.
	size = get_combined_minimum_size()
	var anchor: Rect2 = _anchor.get_global_rect()
	var at := Vector2(anchor.position.x, anchor.position.y - size.y - GAP)
	at.x = clampf(at.x, 0.0, maxf(viewport.size.x - size.x, 0.0))
	at.y = clampf(at.y, 0.0, maxf(viewport.size.y - size.y, 0.0))
	global_position = at


static func _is_verbose() -> bool:
	return Input.is_action_pressed("ui_verbose")
#endregion
