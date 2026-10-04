class_name InfoWidgetRow
extends VBoxContainer

## WHAT ONE SELECTED PIECE IS, as a block of small figures: its name, its hit points, what its
## gun does, how fast it moves, how far it sees, what it holds, what it is building. Drawn only
## for a SINGLE selection — a mixed group has no single answer to any of these, and averaging
## them would invent a unit that is not on the field.
##
## **THE BLOCK IS A FIXED GRID OF SLOTS, sized for the piece that has everything.** Name and
## hit points each take a full row, in that order; every other widget has a slot in a
## two-column grid beneath them (SLOT_ROWS). A piece without a property leaves its slot EMPTY
## rather than letting its neighbours grow into it, so a widget is in the same place on every
## piece and the eye learns where to look once. The rows share the block's height, so with
## every slot filled the block fills the panel's Summary column.
##
## THE ROW IS THE SHALLOW TIER AND THE TOOLTIP IS THE DEEP ONE, which is the same two-tier
## idiom the rest of the HUD uses (`ui_verbose`, the economy stack's held rows, the command
## buttons). Each widget shows the ONE figure a player glances at mid-fight; hovering it
## gives the sentence, and holding the verbose key gives the paragraph explaining what the
## property means at all:
##
##   summary   the piece's name          -> its description         -> its verbose description
##   defense   hit points                -> hp, armour, frame       -> what armour and frame DO
##   weapon    damage type               -> rate of fire, reload    -> what the numbers mean
##   movement  speed                     -> speed, mode, size class -> what the size class DOES
##   vision    vision & detection reach  -> (nothing)               -> (nothing)
##   garrison  occupancy / capacity      -> who it admits           -> capacity, bunkers
##   producing what it builds (+eligible)  -> (one line)              -> why the queue is global
##
## **THIS ROW IS FOR THE UBIQUITOUS, and the conditions row below is for the specific.** A
## mechanic various units across the game use — hit points, a gun, movement, sight, a
## garrison — is a WIDGET here, in a fixed order the player learns once. Something particular
## to one faction or one piece is a card in the conditions row instead. That is the rule for
## deciding where a new mechanic goes; see gdd/systems/ux/ui/condition-cards.md §Which row.
##
## **A WIDGET THAT DOES NOT APPLY IS NOT DRAWN.** A structure has no movement speed and a
## worker has no weapon, and a card reading "movement: —" teaches the player that the block is
## full of blanks rather than that this piece is stationary. What is on screen is what the
## piece has; its slot is simply left empty.
##
## The vision widget has no tooltip on purpose. Two numbers that are already both on the
## face have nothing left to say in a sentence — what a player actually wants from them is
## WHERE they reach, and that is the hover reveal below rather than more words.
##
## HOVERING A WIDGET DRAWS ITS RANGES ON THE GROUND (see RangeIndicator): the weapon widget
## shows what it shoots and what it will start a fight over, the vision widget what it sees
## and what it detects. That is why those two widgets exist as separate cards at all — a
## single "stats" blob would have nothing for the pointer to ask.

#region Constants
## Every widget key, as the full-width rows and then the two-column grid draw them. An empty
## key is a slot nothing occupies — the grid's last row has one widget to place.
const FULL_ROWS: Array[String] = ["name", "hp"]
const SLOT_ROWS: Array = [["weapon", "speed"], ["sight", "hold"], ["production", ""]]

## The floor under a row; the rows otherwise share whatever height the block is given.
const WIDGET_HEIGHT: float = 20.0
const NAME_FONT_SIZE: int = 15
const LABEL_FONT_SIZE: int = 13
const CAPTION_FONT_SIZE: int = 10
## Room between a slot's caption and its value, and around them inside the widget.
const WIDGET_PADDING: int = 6
const TEXT_COLOR: Color = Color(0.88, 0.89, 0.88)
const CAPTION_COLOR: Color = Color(0.60, 0.63, 0.59)

## WHAT A PROPERTY MEANS, as against what this piece's value of it is. Game-wide copy, so it
## is written here once rather than per piece — a doc key repeating "armour resists damage
## types" on ninety-four pieces would be ninety-four places for it to go stale.
##
## The rules themselves live in the design notes and this is the pointer a player gets to
## them; keep these to what someone reads mid-game and cannot look up.
const DEFENSE_NOTES: String = (
	"ARMOUR (light / medium / strong) and FRAME (bio / mech) are separate axes.\n"
	+ "Armour is how hard the piece is to hurt; frame is what it is made of, and it decides "
	+ "what can mend it — a mechanic works on MECH, a heal aura on BIO.\n"
	+ "Damage types are matched against the ARMOUR, so a weapon good against light targets is "
	+ "bad against strong ones whatever they are made of."
)
const WEAPON_NOTES: String = (
	"RATE OF FIRE is the gap between shots inside a clip; RELOAD is the pause once the clip "
	+ "is empty. A one-round clip makes the two the same thing.\n"
	+ "The DAMAGE TYPE is what the matchup table is read with — it, not the raw number, is "
	+ "what decides whether this weapon is the right one for the target."
)
## What a garrison IS, and what bunker fire means — both game-wide rules rather than facts
## about one host.
const GARRISON_NOTES: String = (
	"CAPACITY IS OCCUPANCY, not a head count: a bulky occupant fills more of a host than a "
	+ "soldier does, so a capacity-4 transport takes four infantry or two collectives.\n"
	+ "A BUNKER fires its occupants' weapons out of the host, and extends their reach by its "
	+ "own hull — so who is inside decides what it shoots at.\n"
	+ "What may enter is the HOST's business: each one names the frames, armours and "
	+ "locomotion it admits. A closed hold admits nobody by order at all."
)

## What DETECTION is, as against ordinary sight.
const DETECTION_NOTES: String = (
	"SIGHT clears the fog. DETECTION is the separate, usually shorter reach inside which a "
	+ "STEALTHED enemy can be picked out at all.\n"
	+ "A piece with no detection sweep sees a hidden unit not at all, however close it "
	+ "stands — which is why a detector in a group is worth more than its own statline."
)

## "One structure builds one thing at a time" is a surprising rule for anyone arriving from
## another RTS, and the bracketed count is what separates an idle building from a busy one.
const PRODUCTION_NOTES: String = (
	"ONE STRUCTURE BUILDS ONE THING AT A TIME. The commander's purchases wait in one global "
	+ "queue, and the bracketed count is how many of them COULD be made here — eligible here, "
	+ "not owned by it: another producer may take them first."
)

const MOVEMENT_NOTES: String = (
	"The SIZE CLASS is the crush mechanic: a vehicle drives over anything in a smaller class "
	+ "and is stopped by anything in its own or above.\n"
	+ "TURN RATE and the minimum turning speed decide whether a piece can pivot on the spot "
	+ "or has to arc — a unit that keeps speed while turning cannot answer something that got "
	+ "behind it."
)
#endregion

#region Properties
## Raised when the pointer enters a widget that has ranges to show, with the entity and the
## EntityRanges.Kind values it wants drawn. The controller owns the world-space indicator;
## this row only says what is being asked about.
signal ranges_hovered(entity: Entity, kinds: Array)
## Raised when the pointer leaves such a widget.
signal ranges_unhovered

## The piece currently drawn, so an unchanged selection costs no rebuild.
var _drawn: int = 0
## The depth behind a widget, toggled by clicking it (gdd/systems/ux/ui/piece-readouts.md).
## One for the row, made once, and a SIBLING of the row rather than a child: every child of the
## row is a widget.
var _popup: PieceReadoutPopup = null
## The piece the widgets describe, for the popup a click opens.
var _piece: Commandable = null
#endregion


#region Public API
## Redraw for `a_selection`. Anything other than exactly one Commandable empties the row.
##
## The widgets are rebuilt only when the SELECTED PIECE changes; their VALUES are refreshed
## every call, because hit points move without the selection doing anything.
func update(a_selection: Array) -> void:
	var piece: Commandable = a_selection[0] as Commandable if a_selection.size() == 1 else null
	var id: int = piece.get_instance_id() if piece != null else 0
	if id != _drawn:
		_drawn = id
		_rebuild(piece)
	visible = piece != null
	if piece != null:
		_refresh_values(piece)


## The widget drawn for `a_key` (a FULL_ROWS or SLOT_ROWS key), or null when the selected
## piece has none — its slot is empty.
func widget_for(a_key: String) -> VerboseTooltipButton:
	return find_child("Widget_%s" % a_key.capitalize(), true, false) as VerboseTooltipButton


## Every widget currently drawn, in slot order.
func widgets() -> Array[VerboseTooltipButton]:
	var out: Array[VerboseTooltipButton] = []
	for node: Node in find_children("Widget_*", "VerboseTooltipButton", true, false):
		out.append(node as VerboseTooltipButton)
	return out


#endregion


#region Building
func _rebuild(a_piece: Commandable) -> void:
	_piece = a_piece
	_ensure_popup()
	_popup.close()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if a_piece == null:
		return
	_build_slots()

	_add_widget(
		"name", _piece_title(a_piece), a_piece.resolved_description(), a_piece.resolved_verbose()
	)

	if a_piece.defense != null:
		_add_widget("hp", "", _defense_tooltip(a_piece), DEFENSE_NOTES)

	var weapon: Weapon = EntityRanges.first_weapon(a_piece)
	if weapon != null:
		(
			_add_widget("weapon", _weapon_value(weapon), _weapon_tooltip(weapon), WEAPON_NOTES)
			. set_meta(&"range_kinds", EntityRanges.WEAPON_KINDS)
		)

	if a_piece.movement != null:
		_add_widget("speed", "", _movement_tooltip(a_piece.movement), MOVEMENT_NOTES)

	if EntityRanges.has_any(a_piece, EntityRanges.VISION_KINDS):
		# TWO REPRESENTATIONS, ONE WIDGET. Sight and stealth detection are one question — how far
		# can this piece see, and what can it see — so they share a card and one hover paints
		# both rings. A piece with no detection sweep says so by reporting one figure under the
		# plain caption rather than by drawing a second, empty widget.
		var detects: bool = EntityRanges.radius_of(a_piece, EntityRanges.Kind.DETECTION) >= 0.0
		(
			_add_widget(
				"sight",
				"",
				(
					"How far this piece sees, and how close a hidden enemy must come to be spotted."
					if detects
					else "How far this piece sees. It cannot pick out a hidden enemy."
				),
				DETECTION_NOTES,
				"sight · detect" if detects else "sight"
			)
			. set_meta(&"range_kinds", EntityRanges.VISION_KINDS)
		)

	# GARRISON. A ubiquitous mechanic rather than a faction one — transports, bunkers, the
	# Compound and the stock truck's cage are all the same component — so it earns a widget.
	var garrison: Garrison = a_piece.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		(
			_add_widget(
				"hold",
				"",
				_garrison_tooltip(garrison),
				GARRISON_NOTES,
				"bunker" if garrison.bunker else "hold"
			)
			. set_meta(&"range_kinds", EntityRanges.WEAPON_KINDS if garrison.bunker else [])
		)

	if a_piece.production != null:
		_add_widget(
			"production",
			"",
			"What this structure is building now, and how many queued purchases could land here.",
			PRODUCTION_NOTES
		)


## The empty skeleton every piece shares: a slot per widget key, laid out as FULL_ROWS and
## SLOT_ROWS say. Rows expand to share the block's height; slots in a row share its width, so
## a slot's size never depends on which other slots are filled.
func _build_slots() -> void:
	for key: String in FULL_ROWS:
		var slot: Control = _make_slot(key)
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(slot)
	for pair: Array in SLOT_ROWS:
		var row := HBoxContainer.new()
		row.name = "Row_%d" % get_child_count()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", get_theme_constant("separation"))
		for key: String in pair:
			row.add_child(_make_slot(key))
		add_child(row)


static func _make_slot(a_key: String) -> Control:
	var slot := Control.new()
	slot.name = _slot_name(a_key)
	slot.custom_minimum_size = Vector2(0.0, WIDGET_HEIGHT)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


static func _slot_name(a_key: String) -> String:
	return "Slot_%s" % a_key.capitalize() if not a_key.is_empty() else "Slot_Empty"


func _ensure_popup() -> void:
	if _popup != null:
		return
	_popup = PieceReadoutPopup.new()
	_popup.name = "ReadoutPopup"
	if get_parent() != null:
		get_parent().add_child.call_deferred(_popup)
	tree_exiting.connect(func() -> void: _popup.queue_free())


## One widget, placed in its key's slot: a caption naming the topic on the left and the figure
## on the right. The name widget has no caption — the title is its own label.
##
## A VerboseTooltipButton because that IS the project's tooltip system — every hoverable HUD
## element goes through it — even though these are not pressable. The plain pointer says so.
## `a_key` names the widget (and so its slot, and what `_set_value` writes to); `a_caption` is
## what the player reads beside the figure. Two arguments rather than one because a caption may
## VARY with the piece — the sight widget says "sight" or "sight · detect" depending on whether
## there is a detection sweep to report — while the key must not, or the live refresh would
## lose track of its own label.
func _add_widget(
	a_key: String, a_value: String, a_tooltip: String, a_verbose: String, a_caption: String = ""
) -> VerboseTooltipButton:
	var widget := VerboseTooltipButton.new()
	widget.name = "Widget_%s" % a_key.capitalize()
	widget.set_anchors_preset(Control.PRESET_FULL_RECT)
	widget.focus_mode = Control.FOCUS_NONE
	widget.mouse_default_cursor_shape = Control.CURSOR_ARROW
	widget.simple_tooltip = a_tooltip
	widget.verbose_tooltip = a_verbose

	var box := HBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = WIDGET_PADDING
	box.offset_right = -WIDGET_PADDING
	box.add_theme_constant_override("separation", WIDGET_PADDING)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_name: bool = a_key == "name"
	if not is_name:
		var caption: Label = _make_label(
			a_caption if not a_caption.is_empty() else a_key, CAPTION_FONT_SIZE, CAPTION_COLOR
		)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# The caption keeps its whole width — a clipped label reports none, and would vanish —
		# so it is the VALUE that gives way in a narrow slot.
		caption.clip_text = false
		box.add_child(caption)
	var value_label: Label = _make_label(
		a_value, NAME_FONT_SIZE if is_name else LABEL_FONT_SIZE, TEXT_COLOR
	)
	value_label.name = "Value"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if is_name else HORIZONTAL_ALIGNMENT_RIGHT
	)
	box.add_child(value_label)
	widget.add_child(box)

	widget.mouse_entered.connect(_on_widget_entered.bind(widget))
	widget.pressed.connect(func() -> void: _popup.toggle(StringName(a_key), _piece, widget))
	widget.mouse_exited.connect(func() -> void: ranges_unhovered.emit())
	find_child(_slot_name(a_key), true, false).add_child(widget)
	return widget


static func _make_label(a_text: String, a_size: int, a_color: Color) -> Label:
	var label := Label.new()
	label.text = a_text
	label.add_theme_font_size_override("font_size", a_size)
	label.add_theme_color_override("font_color", a_color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	# CLIPPED, not wrapped and not overflowing. A widget is one line tall by construction, so
	# a value longer than its cell has to lose its tail inside the cell rather than run across
	# the neighbour — which is what an unclipped Label does, and it reads as a layout bug.
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


#endregion


#region Live values
## The figures that move while the selection stands still. Rebuilding the widgets for these
## would rebuild them every frame, so the labels are written in place instead.
func _refresh_values(a_piece: Commandable) -> void:
	if a_piece.defense != null:
		_set_value("hp", "%d/%d" % [roundi(a_piece.defense.hp), roundi(a_piece.defense.hp_max)])
	if a_piece.movement != null:
		_set_value("speed", "%.1f" % a_piece.movement.speed)
	_set_value("sight", _sight_value(a_piece))
	var weapon: Weapon = EntityRanges.first_weapon(a_piece)
	if weapon != null:
		_set_value("weapon", _weapon_value(weapon))
	var garrison: Garrison = a_piece.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		_set_value("hold", "%d/%d" % [garrison.occupied_size(), garrison.capacity])
	if a_piece.production != null:
		_set_value("production", _production_value(a_piece))
	_refresh_weapon_state(a_piece)


## A weapon that has to RELOAD greys its widget while it is dry — the same TINT_LOCKED an
## unaffordable button wears, so "you cannot use this right now" looks the same wherever it
## appears.
##
## Only for a weapon that CAN be dry in a way the player can act on: one with a clip to empty
## or a charge to spend. A one-round weapon that reloads between every shot is dry for a
## fraction of a second at a time, and blinking the widget at its rate of fire would be noise
## rather than information.
func _refresh_weapon_state(a_piece: Commandable) -> void:
	var widget: Control = widget_for("weapon")
	if widget == null:
		return
	var weapon: Weapon = EntityRanges.first_weapon(a_piece)
	if weapon == null or not _weapon_can_run_dry(weapon):
		widget.modulate = CommandButtonState.TINT_AVAILABLE
		return
	widget.modulate = (
		CommandButtonState.TINT_LOCKED
		if weapon.is_out_of_ammo()
		else CommandButtonState.TINT_AVAILABLE
	)


static func _weapon_can_run_dry(a_weapon: Weapon) -> bool:
	return a_weapon.charged or a_weapon.clip_size > 1


## Write a widget's figure in place. A no-op for a widget this piece never got, so a caller
## need not repeat the applicability test the rebuild already made.
func _set_value(a_key: String, a_text: String) -> void:
	var widget: VerboseTooltipButton = widget_for(a_key)
	if widget != null:
		(widget.get_node("Box/Value") as Label).text = a_text


#endregion


#region Copy
static func _piece_title(a_piece: Commandable) -> String:
	return String((a_piece as Node).name)


## Vision and detection as one figure, with detection omitted when the piece has none —
## most pieces do not sweep for stealth, and "8 · —" is not a reading.
static func _sight_value(a_piece: Commandable) -> String:
	var vision: float = EntityRanges.radius_of(a_piece, EntityRanges.Kind.VISION)
	var detection: float = EntityRanges.radius_of(a_piece, EntityRanges.Kind.DETECTION)
	if detection < 0.0:
		return "%.0f" % vision if vision >= 0.0 else ""
	return "%.0f · %.0f" % [maxf(vision, 0.0), detection]


static func _defense_tooltip(a_piece: Commandable) -> String:
	var defense: Defense = a_piece.defense
	return (
		"%d/%d hp  ·  %s armour  ·  %s frame"
		% [
			roundi(defense.hp),
			roundi(defense.hp_max),
			_enum_name(Defense.ArmourType, defense.armour_type),
			_enum_name(Defense.FrameType, defense.frame_type),
		]
	)


## Rate of fire and reload are AUTHORED IN TICKS and read here in seconds, because seconds
## are what a human compares (~/.claude/CLAUDE.md §2.2). The conversion is derived from the
## engine's own tick rate rather than typed, so it survives a change to it.
static func _weapon_tooltip(a_weapon: Weapon) -> String:
	var ticks: float = float(TimeUtils.ticks_per_second())
	var parts: Array[String] = [
		"%s damage" % _damage_type_name(a_weapon),
		"a shot every %.1fs" % (float(a_weapon.split_time_ticks) / ticks),
	]
	# A one-round clip makes reload and rate of fire the same pause said twice.
	if a_weapon.clip_size > 1:
		parts.append(
			(
				"%d-round clip, %.1fs reload"
				% [a_weapon.clip_size, float(a_weapon.reload_time_ticks) / ticks]
			)
		)
	return "  ·  ".join(parts)


static func _movement_tooltip(a_movement: Movement) -> String:
	# CRUSH IS ON THE HOVER, not on the face: it is a fact about what happens when this piece
	# meets another one, which is the sort of thing a player looks up rather than glances at.
	var parts: Array[String] = [
		"%.2f speed" % a_movement.speed,
		_enum_name(Movement.Mode, a_movement.mode),
		(
			"%s — drives over anything smaller, stopped by its own class and above"
			% _enum_name(Movement.CrushClass, a_movement.crush_class)
		),
	]
	# GROUNDED only, and only when it is not the default — a piece that pivots on the spot
	# has nothing to say about how it corners.
	if a_movement.mode == Movement.Mode.GROUNDED and a_movement.min_turn_speed_ratio > 0.0:
		parts.append(
			"holds %d%% speed while turning" % roundi(a_movement.min_turn_speed_ratio * 100.0)
		)
	return "  ·  ".join(parts)


## What a host is holding, and whether it fires what it holds.
## What a producer is building — "idle", or the piece's name — and, bracketed, how many of the
## commander's queued purchases could land here.
static func _production_value(a_piece: Commandable) -> String:
	var production: Production = a_piece.production
	var value: String = "idle"
	if production.job_count() > 0:
		var job: Variant = production.job_type(0)
		var tool: Tool = Tool.for_id(StringName(job)) if job != null else null
		value = tool.label if tool != null else (String(job) if job != null else "building")
	var commander: Commander = a_piece.commander
	var waiting: int = (
		commander.production_queue.pending_count_for(a_piece) if commander != null else 0
	)
	return "%s (+%d)" % [value, waiting] if waiting > 0 else value


static func _garrison_tooltip(a_garrison: Garrison) -> String:
	var parts: Array[String] = [
		"holding %d of %d" % [a_garrison.occupied_size(), a_garrison.capacity],
	]
	if a_garrison.bunker:
		parts.append("fires its occupants' weapons")
		if a_garrison.range_bonus > 0.0:
			parts.append("+%.0f reach" % a_garrison.range_bonus)
	if a_garrison.is_closed():
		parts.append("closed — nothing can be ordered in")
	return "  ·  ".join(parts)


## The weapon widget's face: what it deals per second, approximately, and of what type. The
## specifics are its popup's (piece-readouts.md §The weapon widget).
static func _weapon_value(a_weapon: Weapon) -> String:
	return "~%d dps · %s" % [roundi(a_weapon.approximate_dps()), _damage_type_name(a_weapon)]


static func _damage_type_name(a_weapon: Weapon) -> String:
	return _enum_name(Damage.Type, a_weapon.per_shot_damage_type())


## An enum member's own name, lower-cased for prose. Read off the enum rather than a
## hand-kept table so a new member cannot be missing from one.
static func _enum_name(a_enum: Dictionary, a_value: int) -> String:
	for key: String in a_enum:
		if int(a_enum[key]) == a_value:
			return key.to_lower().replace("_", " ")
	return "?"


#endregion


#region Hover
## `has_meta` before `get_meta`: Godot reports a missing key as an ERROR even when a default
## is supplied, and this runs on every hover of every widget that carries no ranges — which
## is most of them.
func _on_widget_entered(a_widget: VerboseTooltipButton) -> void:
	if not a_widget.has_meta(&"range_kinds"):
		ranges_unhovered.emit()
		return
	var kinds: Array = a_widget.get_meta(&"range_kinds") as Array
	if kinds.is_empty():
		ranges_unhovered.emit()
		return
	ranges_hovered.emit(instance_from_id(_drawn) as Entity, kinds)
#endregion
