class_name RTSController extends CanvasLayer

#region Constants
const FREE_CURSOR: Resource = preload("res://assets/interface/cursor_free.png")
const SELECTION_CURSOR: Resource = preload("res://assets/interface/cursor_selection.png")
const ATTACK_CURSOR: Resource = preload("res://assets/interface/cursor_attack.png")
const UNKNOWN_CURSOR: Resource = preload("res://assets/interface/cursor_unknown.png")
const INVALID_CURSOR: Resource = preload("res://assets/interface/cursor_invalid.png")

# The commander id the local human controls. Runtime-set by Scenario from its
# player_slots (the first non-bot slot), so the player can be any commander id —
# or absent entirely (spectator), in which case this is < 1 and
# no human rig (camera/HUD/fog) exists. Read by fog, minimap, and commandable to
# decide the local viewpoint. Was a const; now a static var so it can vary.
static var PLAYER_COMMANDER_ID: int = 1

# Full-panel HUD Controls in this group swallow world-selection clicks: a press or
# release whose cursor sits inside any of them is NOT interpreted as unit selection
# (see _pointer_over_blocking_ui). Add future HUD panels (MapSection, InfoSection,
# CommandsSection, …) to this group in the scene to have them ignored the same way.

const SELECTION_BLOCKING_UI_GROUP: StringName = &"selection_blocking_ui"

## Other HUD layers whose visibility follows this HUD's hide button: the scenario timer, a
## spectator's labels, the replay banner. A dialog and the pause menu are not HUD and stay up.
## gdd/systems/ux/ui/hud-layout.md §Hiding the HUD.
const HUD_LAYER_GROUP: StringName = &"hud_layer"
## The hide button's size, and the gap it keeps above the minimap or the screen's bottom edge.
const HUD_TOGGLE_SIZE: Vector2 = Vector2(96.0, 26.0)
const HUD_TOGGLE_MARGIN: float = 4.0

## Ghosts of a structure that isn't on the map yet — the placement preview under the
## cursor and the blueprints marking claimed sites — are drawn at the "planned" opacity,
## one step fainter than a placed-but-unfinished structure (see MeshVisual's OPACITY_*).
const BUILD_PREVIEW_ALPHA: float = MeshVisual.OPACITY_PLANNED
## Multiplied over the team colour to flag a spot the structure cannot go. The alpha
## carried here is used by the Sprite (billboard) path only; a MeshVisual ghost takes its
## alpha from set_opacity instead.
const BUILD_PREVIEW_VALID_TINT: Color = Color(1.0, 1.0, 1.0, BUILD_PREVIEW_ALPHA)
const BUILD_PREVIEW_INVALID_TINT: Color = Color(1.0, 0.25, 0.25, BUILD_PREVIEW_ALPHA)

const _INDICATOR_POOL_SIZE: int = 16

## Command names for the SELECT-context grid buttons shown when nothing is
## selected. Dispatched via _select_command_handlers (built in _ready), bypassing
## the normal, selection-gated process_command pipeline. Referenced by
## command_grid.gd's SELECT bindings so the strings live in one place.
##
## ONE name per family, not one per cell of the matrix: which set a selector yields is
## decided by the modifiers held when it fires (see _run_selector), so the three families
## are three keys — F1 / F2 / F3, off the alphabetical block entirely.
const CMD_SELECT_ARMY: String = "command_select_army"
const CMD_SELECT_BUILDER: String = "command_select_builder"
const CMD_SELECT_PRODUCTION: String = "command_select_production"

## The two assignment modifiers — Alt and Ctrl — which mean something in BOTH key spaces:
##
## |          | on a command (see _narrowed_actors) | on a selector (see _run_selector) |
## | narrow   | assign to ONE actor                 | reach past the screen edge        |
## | broaden  | assign to ALL selected actors       | take all of them, not one idle    |
##
## They are ABSOLUTE, not relative: narrow always yields one actor and broaden always
## yields all, whichever way the command's own default falls, so a modifier applied to a
## command already at that extreme is a no-op. Defaults vary per command, and a
## flip-the-default modifier would need the player to know each default before predicting
## the outcome.
##
## `narrow` is the acknowledged inconsistency: it narrows on the command side and broadens
## on the selector side, because a selector has nothing narrower than its default. The two
## key spaces are disjoint (mouse commands vs. F-keys). `broaden` is consistent across both
## — it means "drop the restriction to the minimum", whether that minimum is one actor or
## one idle member. If this is ever revisited, the COMMAND side is the fixed point.
##
## Both are POLLED at use time rather than latched from a key event: a selector or a
## purchase can fire from a HUD button press, and the modifier keydown before that click
## goes to the focused Control rather than to _unhandled_input.
##
## Deliberately NOT named `command_*`: the hotkey dispatcher routes every action with that
## prefix to a command, and a modifier is not one.
##
## Neither is a click modifier in the sense constraint 1 in
## gdd/systems/ux/ui/interface-idioms.md rules out — they modify what an already-resolved
## order does, not how the click is delivered — so
## macOS turning Ctrl+LMB into a right-click doesn't reach them. Ctrl is nonetheless read
## by polling, never off the event's modifier flags, for exactly that reason.
const MODIFIER_NARROW: String = "modifier_narrow"
const MODIFIER_BROADEN: String = "modifier_broaden"

## The command name of the Cancel button on the READY card — the only button that card draws.
## Named here rather than in the grid because the controller both offers it and answers it.
const CANCEL_COMMAND: String = "command_cancel"

## The third modifier, and the one with the widest reach: it makes a SELECTION additive, a
## COMMAND queued, and a PURCHASE requisitioned. Those are one idea — "add this to what is
## already asked for, and address it when you are free to" — which is why they share a key
## rather than competing for it.
##
## Named `modifier_*` for the same reason the other two are: the hotkey dispatcher routes
## every `command_*` action to a command, and a modifier is not one. It was
## `command_additive` and was caught only by an explicit branch sitting above the prefix
## test — luck of ordering rather than design.
const MODIFIER_ADDITIVE: String = "modifier_additive"

## Max gap between two clicks on the same unit for them to count as a double-click
## (which selects all on-screen units of that entity type).
const DOUBLE_CLICK_SECONDS: float = 0.3

## Screen-space slop between press and release below which the gesture counts as a CLICK
## rather than a box drag. Compared PER AXIS (see is_click_gesture): Vector2's own `<` is
## lexicographic — x decides unless the two xs are equal — so testing the delta against
## Vector2(10, 10) called a 5×500 drag a click and box-selected nothing.
const CLICK_SLOP_PX: float = 10.0

## The debug view's delete key: everything selected dies. See delete_selection.
const DEBUG_DELETE_ACTION: StringName = &"debug_delete_selection"
#endregion

#region Signals
signal unit_selected(entity: Entity)
signal command_issued(entity: Entity, command_type: Script)
#endregion

#region Properties
@onready var map: Map = _session_root().find_child("Map") as Map
@onready var camera: RTSCamera3D = get_viewport().get_camera_3d()
@onready var _info_view: InfoView = $InfoSection
## The four PERSISTENT panels — visible in every selection state, because each answers a
## question you can ask with nothing selected. Optional (get_node_or_null) so a session
## running without the full HUD rig still works.
## Inside a slot the size of the info panel's rect: the rail sizes itself to its contents and
## sits at the slot's bottom centre, and the slot itself never blocks a click.
@onready var _production_rail: ProductionRail = (
	get_node_or_null("ProductionSlot/ProductionRail") as ProductionRail
)
## The three persistent resource bars — see gdd/systems/ux/ui/economy-bars.md. Optional like
## every other panel here, for the same reason.
@onready var _dominion_bar: DominionBar = get_node_or_null("DominionBar") as DominionBar
@onready var _energy_bar: EnergyBar = get_node_or_null("EnergyBar") as EnergyBar
@onready var _infrastructure_bar: InfrastructureBar = (
	get_node_or_null("InfrastructureBar") as InfrastructureBar
)
## Occupies the same screen rect as InfoSection, as its SIBLING rather than its child, so
## the info panel can hide wholesale — a hidden panel is one that stops blocking world
## clicks (pointer_over_blocking_ui gates on is_visible_in_tree), and a still-visible
## InfoSection wrapping the selectors would keep swallowing clicks over empty screen.
@onready var _selector_panel: SelectorPanel = get_node_or_null("Selectors") as SelectorPanel
## The fourth: "what have I got squadded up" is a question you ask precisely when the current
## selection is WRONG, so it cannot be selection-owned (see ControlGroupPanel).
@onready
var _control_group_panel: ControlGroupPanel = get_node_or_null("ControlGroups") as ControlGroupPanel

var cursor_target: Variant = Vector3.ZERO
var mouse_position: Vector2 = Vector2.ZERO

## The command-grid button currently under the pointer, set/cleared by ButtonSpec's
## mouse_entered/mouse_exited wiring — see gdd/systems/ux/ui/economy-bars.md §Hover previews.
## A NODE rather than a bare command-name string, so a button that gets freed out from under
## a stale hover (the grid rebuilds while the mouse hasn't moved) is caught by
## is_instance_valid() in hovered_command_name() rather than left pointing at nothing.
var hovered_command_button: Control = null


## The name of hovered_command_button, or "" when nothing is hovered or the reference has
## gone stale. The persistent resource bars read this to resolve a Tool to preview.
func hovered_command_name() -> StringName:
	if hovered_command_button == null or not is_instance_valid(hovered_command_button):
		return &""
	return hovered_command_button.name


## The sanction-grid UNLOCK cell currently under the pointer, or null — set/cleared by
## _build_sanction_button's own mouse_entered/mouse_exited (a separate button-building path
## from ButtonSpec, since the sanction menu is its own dialog). Only the UNLOCK button sets
## this, never the deploy/cast one: casting an already-unlocked sanction costs a charge, not
## dominion, so it has nothing for DominionBar to preview. DominionBar is the only reader —
## see gdd/systems/ux/ui/economy-bars.md §Hover previews.
var hovered_sanction_unlock: SanctionGrid.Entry = null


## The Tool a resource bar should preview right now: whatever is hovered in the UI, or —
## failing that — whatever tool is ARMED (command_message.tool, from choosing a Build/Train
## button and not yet placing or cancelling it). Hover wins outright rather than combining
## with an armed tool, so a player who has armed one structure and is now pointing at a
## different button's cost never sees the two added together; an armed tool with nothing
## hovered still gets its preview, since it is exactly as pending a purchase as a hovered one.
func previewed_tool() -> Tool:
	var hovered: Tool = Tool.for_name(String(hovered_command_name()))
	if hovered != null:
		return hovered
	return command_message.tool if command_message != null else null


## The cursor image last handed to the DisplayServer, and a standing demand to hand it over
## again even though it hasn't changed. Both exist for _apply_cursor — see the comment there
## for why re-sending an unchanged cursor is a no-op that has to be forced.
var _applied_cursor: Resource = null
var _cursor_needs_reassert: bool = true

## Titles the card on show and washes the panel behind it in that card's colour. A stub the
## HUD pass can replace outright; nothing reads it back.
var _mode_banner: CardModeBanner = null

@export var selection_box: ColorRect = ColorRect.new()
@onready var command_message: CommandMessage = CommandMessage.new(map)
## The additive modifier as seen by _unhandled_input, LATCHED on its keydown. Selection
## and command-queueing read this; anything issued from a HUD BUTTON press must poll
## instead (see _purchase_defers), because the keydown before a button click goes to the
## focused Control and never reaches us.
@onready var additive_latched: bool = false

var selection: Array[Node] = []
## Where the live box-select drag was pressed, and where its cursor is now. Both are
## viewport coordinates, and `_drag_position` is kept up to date from the LIVE cursor
## rather than from MouseMotion events — see _update_drag.
var select_down_position: Vector2 = Vector2.ZERO
var _drag_position: Vector2 = Vector2.ZERO
## True between the press that starts a box-select and the release that resolves it. The
## authority on whether a drag is live; `selection_box.visible` follows it.
var _dragging: bool = false
var current_command_type: Script = null

## SELECT-context grid command name -> the selection routine it invokes. Built in
## _ready (values are bound to this instance). Drives both the "nothing selected"
## button visibility and the button-press dispatch.
var _select_command_handlers: Dictionary = {}

#region Placement rotation
## How far from the placement point the cursor must be dragged before the drag turns the
## structure, in world units (cells). A plain click, or a wobble, leaves the facing the player
## already chose with the rotate keys.
const PLACEMENT_ROTATE_DEADZONE: float = 1.0

## How the structure about to be placed is turned, as Fixture.quarter_turns (0…3, counter-
## clockwise from above; 0 faces +Z). Held while a Build tool stays armed and put back to 0 when
## it is put down. Written by the rotate keys and by a placement drag; what an order actually
## carries is command_message.quarter_turns, which is this where rotation applies at all.
var placement_quarter_turns: int = 0

## True from the press of `command_armed_issue` that starts placing a structure until it is
## released.
## While it is, the placement point is FROZEN where the press landed (below) and the cursor's job
## is to aim the structure, not to move it.
var _placing: bool = false
var _placing_world: Vector3 = Vector3.ZERO
var _placing_target: Entity = null

## MOVE-LINE DRAG: true from the press of a right click that MIGHT become a line until its release.
## The press is held back rather than issued, because only the release says whether it was a click
## or a drag. See gdd/systems/commands/move-line-drag.md.
var _line_pressing: bool = false
## The order the press would have given, fixed at the press so a cursor that wanders over a unit
## during the drag cannot change what the line means.
var _line_command_type: Script = null
var _line_press_screen: Vector2 = Vector2.ZERO
var _line_start: Vector2 = Vector2.ZERO
var _line_end: Vector2 = Vector2.ZERO
## True only WHILE a line order is being issued, so the destination fan-out knows to use the line.
var _line_issuing: bool = false
var _line_indicator: LineIndicator = null
#endregion

## Double-click tracking: the player unit hit by the previous click and when
## (engine ms) it was clicked. A second click on the same unit within
## DOUBLE_CLICK_SECONDS selects all on-screen units of that type.
var _last_click_target: Entity = null
var _last_click_time_ms: int = -1

## The set of command names available given the current selection — recomputed
## (via CommandContextParser) whenever the selection changes. Used by the HUD
## visibility loop and the hotkey-input gate in process_command(). Replaces
## the merged CommandContext that the controller used to consult.
var _available_commands: Array = []
var available_commands: Array:
	get:
		return _available_commands
	set(value):
		_available_commands = value
		# Settle the card BEFORE drawing: which buttons are visible is filtered by the card on
		# show, so correcting the card afterwards would leave one frame drawn against the old
		# one — and, worse, would leave the hotkeys reading a card the buttons had moved off.
		_settle_command_family()
		_settle_producer_context()
		upate_hud_buttons()

## Which card the command grid is showing (a ControlBinding.CommandFamily value). The grid
## holds two pages — the verbs a unit acts with, and what a producer commits energy to — and
## draws exactly one, so this is the coarsest gate on every button and every grid hotkey.
##
## ACTIVE is the resting state and the one a mixed selection lands on: a group picked up
## mid-fight is picked up to be ORDERED, and having to press a key before you can tell it
## to move would be a tax on the common case to serve the rare one.
##
## Never set directly — go through set_command_family(), which refuses a family the
## selection cannot offer. That is what makes the toggle safe to press blind: it can put
## the card somewhere useless neither by keypress nor by the selection changing under it.
var _command_family: int = ControlBinding.CommandFamily.ACTIVE
var command_family: int:
	get:
		return _command_family

## A hotkey like `command_attack_move` puts the controller into a "pending"
## sub-mode where the next right-click resolves to AttackMove (or Attack on a
## hostile target) instead of the default move/attack. Empty string = no
## pending hotkey; resolve generically based on the cursor target. Replaces
## the old state_maping-based sub-context machinery.
var pending_command_name: String = ""

## THE PENDING SELECTION: queue entries the player has selected on the production rail, whose
## units do not exist yet. Its own channel rather than a member of `selection`, because every
## consumer of that array — the command card's availability gate, the info panel,
## `meets_precondition` on every command — assumes an entity standing in the world.
##
## Selecting a phantom is how you give it orders before it is built: a command issued while
## this is non-empty is stored on the transaction and replayed the moment the unit spawns
## (PurchaseTransaction.queue_player_command). Nothing acts on it in the meantime, which is
## the point — the requisition system already carries the intent.
##
## Mutually exclusive with `selection`, and deliberately: "issue a command" has to have one
## unambiguous recipient set, and a click that ordered both a live squad and a phantom would
## be two orders wearing one gesture.
var pending_selection: Array[PurchaseTransaction] = []

## One WaypointIndicator node per active CommandMessage snapshot, pooled to
## avoid per-command allocations.  All indicator nodes live under the Map node.
var _active_indicators: Dictionary = {}  # CommandMessage -> WaypointIndicator
var _indicator_pool: Array = []  # idle WaypointIndicator nodes

#region Range display
## Draws REACH on the ground — what the player is currently asking "how far does this go?"
## about. Lives under the Map (world coordinates); null when the HUD is being previewed
## without one.
var _range_indicator: RangeIndicator = null
## The terrain grid traced around a structure being placed (see _update_placement_grid).
var _placement_grid: PlacementGridOverlay = null
## What _placement_grid was last drawn for, so it redraws only when that changes — the cursor's
## grid, and the dominion claim layer beneath it, separately.
var _placement_grid_key: Array = []
var _placement_layer_key: Variant = null

## The floating one-liner about whatever the cursor is over in the WORLD. Built in _ready
## rather than authored into player.tscn, so it is one file plus two lines to remove.
var _cursor_readout: CursorReadout = null

## The piece whose ranges an info widget is currently hovered over, and which of its ranges
## that widget asked for. Cleared the moment the pointer leaves.
##
## HOVER STATE, NOT DRAWN STATE: the bands are recomposed from this and from what is armed
## every frame (see range_bands), so no source has to remember to put its own marks
## away. A hover that ended while an ability was armed is exactly the kind of thing that
## otherwise leaves a ring on screen with nothing to explain it.
var _hovered_range_entity: Entity = null
var _hovered_range_kinds: Array = []

## The armed-ability preview's two marks. Deliberately apart from the EntityRanges palette:
## those describe a piece that is standing there, these describe an order about to be given,
## and a player must not read one as the other.
const ARMED_REACH_COLOR: Color = Color(0.96, 0.94, 0.62)
const ARMED_AREA_COLOR: Color = Color(0.98, 0.58, 0.36)
#endregion

## The local commander's sanction sanction grid — its grid of unlockable sanctions and the
## per-match owned/cooldown state (see _setup_commander_sanctions).
var _sanction_grid: SanctionGrid = null
## Sanction armed by the player — the next right-click activates it at that position.
var _pending_sanction: Sanction = null

## Which producer TYPE the PRODUCTION card is currently showing, or &"" for "all of them".
##
## STICKY across selections, deliberately: re-selecting the same pair of building types puts
## the player back on the row they were last using rather than resetting. It is only corrected
## when the selection cannot fill it (see _settle_producer_context), which is the same shape
## the card family already settles by.
var _producer_context: StringName = &""

## True while `_on_deploy_button_pressed` is finding an ability's casters and arming it.
##
## A RE-ENTRANCY GUARD, and it is guarding a genuine cycle rather than a stylistic one: a press
## on the ORDNANCE card routes to the caster-finding path, and that path finishes by ARMING the
## ability through `process_command` — which is the same function, on the same card, for the
## same command name. Without this the second call routed straight back into the first and the
## stack overflowed on the first ordnance the player pressed.
##
## The alternative — splitting the arming half of `process_command` into its own function for
## the deploy path to call — was rejected for now: the two halves share the availability gate,
## the modifier re-stamp and the pending-state bookkeeping, and duplicating that is a worse
## trade than one flag with a stated reason.
var _finding_casters: bool = false
## Top-of-screen bar. The BAR centres; the ROW is the strip of buttons inside it, and is
## what blocks clicks — the bar itself spans the full screen width.
var _sanction_bar: CenterContainer = null
var _sanction_bar_row: HBoxContainer = null
## The toggle that opens the unlock menu; lives at the left end of the bar.
var _sanction_menu_button: Button = null
## The unlock surface — the whole sanction grid, hidden until toggled. The MENU is a
## full-screen, click-through root whose visibility is toggled; the PANEL is the card
## centred inside it, and is what blocks clicks and what the player actually sees.
var _sanction_menu: Control = null
var _sanction_menu_panel: PanelContainer = null
## Buttons paired with the entries they draw, one list per surface. Both panels nest
## their buttons, so neither can be indexed in step with `_sanction_grid.entries`.
## One per ABILITY that authors `hud_button: true`, not one per sanction grid cell — the two
## differ for a free ability, which has no cell. `entry` is the cell currently in play for
## that ability (null for a free one), tracked so the tooltips are rebuilt only when an
## unlock changes which level the button stands for.
# Array of { "button": Button, "ability": StringName, "entry": Entry }
var _deploy_buttons: Array = []
var _unlock_buttons: Array = []  # Array of { "button": Button, "entry": Entry }

@onready var _event_manager: ScenarioTriggerManager = (
	_session_root().find_child("ScenarioTriggerManager") as ScenarioTriggerManager
)

## The session this controller plays in: its local player. Null when this controller is
## previewed outside a real scenario (e.g. bare-instanced in tests).
@onready var _scenario: Scenario = Scenario.of(self)

## Draws rally-point sequences for selected rally-capable structures. Lives under Map,
## same arrangement as the WaypointIndicator pool below.
var _rally_indicator: RallyIndicator = null
## Rings the producers that could fulfil the rail purchase under the cursor. Lives under Map
## like the rally indicator, and is null when there is no Map (standalone HUD preview).
var _producer_affinity_indicator: ProducerAffinityIndicator = null

## While a Build command is armed with a chosen Tool, we show a translucent
## "ghost" of the structure under the cursor, snapped to the cell it would
## occupy — the standard RTS placement preview. The ghost is the structure's own
## MeshVisual (or Sprite3D, for billboard art) duplicated out of the building's
## own scene, so it always matches the real building art. It lives in the 3D
## world under the Map, not on this CanvasLayer. We rebuild it only when the
## chosen structure changes.
var _build_preview: Node3D = null
var _build_preview_tool_type: Variant = null
#endregion

## A LOOK-ONLY HUD: the spectator session's (Scenario._create_look_only_hud), a replay's included,
## and any HUD whose player has detached (Scenario.spectate). It drives no commander, so it gives
## no orders: selection, control groups, the info panel and the minimap work, and the command
## grid's slot holds the SpectatorPanel instead. Set before the HUD enters the tree; afterwards,
## through set_look_only. gdd/systems/ux/ui/hud-layout.md §The look-only HUD.
@export var is_look_only: bool = false

## Whether the hide button has put the HUD away (set_hud_hidden).
var is_hud_hidden: bool = false
## Holds what stays up while the HUD is hidden — the hide button and the drag box — on a layer
## of its own: hiding this layer would otherwise hide them with it.
var _hud_overlay: CanvasLayer = null
var _hud_toggle: Button = null
var _spectator_panel: SpectatorPanel = null
## The HUD nodes a look-only layout put away, each with the visibility it gives back
## (Node -> bool), so leaving look-only restores whatever each was showing.
var _look_only_hidden: Dictionary = {}


#region Lifecycle
func _ready():
	# Keep running while a SimulationClock hold pauses the world. Selection, hotkeys,
	# right-click orders and the whole HUD live in _process / _unhandled_input, so the player
	# can still look around and give orders during a scripted beat — the orders simply don't
	# get carried out until the world resumes (execution is _physics_process work). Every
	# child Control inherits this, which is what keeps the info panel and minimap live too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _order_stream() != null:
		_order_stream().order_applied.connect(_on_order_applied)
	ControlScheme.apply()
	PlatformModifiers.apply()
	_register_hud_cursor()
	_apply_cursor(FREE_CURSOR)
	# Map each SELECT-context grid command to its selection routine. Must be built
	# before the first upate_hud_buttons() (below) since it drives which buttons
	# show while nothing is selected.
	_select_command_handlers = {
		CMD_SELECT_ARMY: select_army,
		CMD_SELECT_BUILDER: select_builders,
		CMD_SELECT_PRODUCTION: select_production_structures,
	}
	# Indexed by SelectorFamily. Shared by the F-keys, the SelectorPanel's buttons and its
	# per-frame preview, so all three read one statement of what a family means.
	_selector_predicates = [
		[_is_army_unit, _is_idle_unit],
		[_is_builder_unit, _is_idle_unit],
		[_is_producer_structure, _is_idle_producer],
	]
	upate_hud_buttons()

	selection_box.visible = false
	if !selection_box.is_inside_tree():
		add_child(selection_box)

	# The info panel's summary cards drive selection changes (left click = select only,
	# shift+click = remove from selection).
	if _info_view != null:
		_info_view.select_only_requested.connect(select_only)
		_info_view.deselect_requested.connect(remove_from_selection)
		_info_view.add_to_selection_requested.connect(add_to_selection)
		_info_view.ranges_hovered.connect(_on_ranges_hovered)
		_info_view.ranges_unhovered.connect(_on_ranges_unhovered)
		_info_view.controller = self

	_bind_commander_panels()
	if _selector_panel != null:
		_selector_panel.controller = self
	if _control_group_panel != null:
		_control_group_panel.controller = self
	# Debug mode can make the player a different commander mid-match (Scenario.play_as).
	if _scenario != null:
		_scenario.local_player_changed.connect(_on_local_player_changed)

	# Waypoint indicators live under Map; skip pooling when there is no Map
	# (e.g. running player.tscn standalone to preview the HUD).
	if map != null:
		for i in range(_INDICATOR_POOL_SIZE):
			_indicator_pool.append(_make_indicator())
		_rally_indicator = RallyIndicator.new()
		map.add_child(_rally_indicator)
		_line_indicator = LineIndicator.new()
		map.add_child(_line_indicator)
		_producer_affinity_indicator = ProducerAffinityIndicator.new()
		map.add_child(_producer_affinity_indicator)
		_range_indicator = RangeIndicator.new()
		_range_indicator.map = map
		map.add_child(_range_indicator)
		_placement_grid = PlacementGridOverlay.new()
		_placement_grid.map = map
		map.add_child(_placement_grid)

	# Deferred: this controller is a child of its Commander, so child _ready() runs
	# BEFORE the parent's. The commander instances its Faction in its own _ready(),
	# so reading commander.faction now would see null. Deferring runs the setup after
	# the whole subtree's _ready() cascade, once the faction exists.
	_setup_commander_sanctions.call_deferred()

	# DIAGNOSTIC, to be removed with the cursor fix. Built in code rather than authored into
	# player.tscn so deleting it is deleting one file and these two lines — see
	# CursorDebugReadout for what it is asking and how to read it.
	add_child(CursorDebugReadout.new())

	# Facts about the GROUND under the cursor, which no HUD control's tooltip_text can carry
	# because nothing is being hovered but terrain. Built in code, like the banner below.
	_cursor_readout = CursorReadout.new()
	add_child(_cursor_readout)

	# Says which of the three cards is on screen. A STUB — see CardModeBanner.
	_mode_banner = CardModeBanner.new()
	$CommandsSection/CommandsBorder.add_child(_mode_banner)
	_mode_banner.set_backdrop($CommandsSection/CommandsBorder as ColorRect)
	_mode_banner.show_family(_command_family)

	if is_look_only:
		_apply_look_only_layout()
	_build_hud_toggle()


## Turn this HUD look-only, or back into a player's, at runtime: the player detached from or
## attached to a commander (Scenario.spectate / play_as).
func set_look_only(a_is_look_only: bool) -> void:
	if a_is_look_only == is_look_only:
		return
	is_look_only = a_is_look_only
	if is_look_only:
		_apply_look_only_layout()
	else:
		_remove_look_only_layout()
	upate_hud_buttons()


## A look-only HUD's layout: everything that shows or spends a commander's means goes — the
## resource bars, the production rail, the selectors, the tuning panel — and the SpectatorPanel
## takes the command grid's slot. The debug menu stays, for its player setting, except in a
## playback, which nothing may change.
func _apply_look_only_layout() -> void:
	var paths: Array[String] = [
		"DominionBar",
		"EnergyBar",
		"InfrastructureBar",
		"ProductionSlot",
		"Selectors",
		"CommandsSection",
		"DebugTuningPanel",
	]
	if _scenario == null or _scenario.is_playback():
		paths.append("DebugPanel")
	for path: String in paths:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node != null:
			_look_only_hidden[node] = node.visible
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var slot: Control = $CommandsSection as Control
	_spectator_panel = SpectatorPanel.new()
	_spectator_panel.name = "SpectatorPanel"
	_spectator_panel.add_to_group(SELECTION_BLOCKING_UI_GROUP)
	add_child(_spectator_panel)
	_spectator_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_spectator_panel.offset_left = slot.offset_left
	_spectator_panel.offset_top = slot.offset_top
	_spectator_panel.offset_right = slot.offset_right
	_spectator_panel.offset_bottom = slot.offset_bottom
	_spectator_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_spectator_panel.bind(_scenario)


## Give back what _apply_look_only_layout put away, and take the SpectatorPanel down.
func _remove_look_only_layout() -> void:
	for node: CanvasItem in _look_only_hidden:
		if is_instance_valid(node):
			node.process_mode = Node.PROCESS_MODE_INHERIT
			node.visible = _look_only_hidden[node]
	_look_only_hidden.clear()
	if _spectator_panel != null:
		remove_child(_spectator_panel)
		_spectator_panel.queue_free()
		_spectator_panel = null


#endregion


#region Hiding the HUD
## The hide button, just above the minimap's left edge — wherever there is a minimap, in a match
## and a look-only HUD alike. Hidden, the HUD leaves this one button at the bottom of the screen,
## at the same horizontal position, to bring it back.
func _build_hud_toggle() -> void:
	var map_section: Control = get_node_or_null("MapSection") as Control
	if map_section == null:
		return
	_hud_overlay = CanvasLayer.new()
	_hud_overlay.name = "HudOverlay"
	_hud_overlay.layer = layer
	add_child(_hud_overlay)
	# The drag box is drawn while the HUD is hidden too: selecting does not stop.
	selection_box.reparent(_hud_overlay, false)
	_hud_toggle = Button.new()
	_hud_toggle.name = "HudToggle"
	_hud_toggle.focus_mode = Control.FOCUS_NONE
	_hud_toggle.add_to_group(SELECTION_BLOCKING_UI_GROUP)
	_hud_toggle.pressed.connect(func() -> void: set_hud_hidden(not is_hud_hidden))
	_hud_overlay.add_child(_hud_toggle)
	_hud_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud_toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place_hud_toggle()


## Put the HUD away, or bring it back. Hiding the controller's own layer hides every panel in
## it — and a hidden panel no longer blocks a world click (pointer_over_blocking_ui reads
## is_visible_in_tree) — so nothing per panel has to remember the state.
func set_hud_hidden(a_hidden: bool) -> void:
	is_hud_hidden = a_hidden
	visible = not a_hidden
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(HUD_LAYER_GROUP):
			if node is CanvasLayer:
				(node as CanvasLayer).visible = not a_hidden
	_place_hud_toggle()


## The toggle's place: above the minimap while the HUD is up, on the bottom edge while it is
## hidden — the same horizontal position, the minimap's left edge, either way.
func _place_hud_toggle() -> void:
	if _hud_toggle == null:
		return
	var map_section: Control = get_node_or_null("MapSection") as Control
	var bottom: float = -HUD_TOGGLE_MARGIN
	if not is_hud_hidden and map_section != null:
		bottom = map_section.offset_top - HUD_TOGGLE_MARGIN
	var left: float = map_section.offset_left if map_section != null else -HUD_TOGGLE_SIZE.x
	_hud_toggle.offset_left = left
	_hud_toggle.offset_right = left + HUD_TOGGLE_SIZE.x
	_hud_toggle.offset_bottom = bottom
	_hud_toggle.offset_top = bottom - HUD_TOGGLE_SIZE.y
	_hud_toggle.text = "Show HUD" if is_hud_hidden else "Hide HUD"
	_hud_toggle.tooltip_text = (
		"Bring the interface back" if is_hud_hidden else "Hide the interface to watch the map"
	)


## The persistent panels that show one commander. Each is a child of this controller, and
## each needs something the scene can't give it: the rail needs the commander, the resource
## bars need both the commander and this controller (for the hover preview — see
## hovered_command_name). Every one of them tolerates being absent — a headless or HUD-less
## session (spectator, tests) just has no panel. Re-run whenever the player becomes another
## commander.
func _bind_commander_panels() -> void:
	var commander: Commander = _commander()
	if _production_rail != null:
		_production_rail.commander = commander
		# The rail also needs this controller: a right-click on a queued purchase selects the
		# phantom it will produce, which is the controller's selection to hold.
		_production_rail.controller = self
	for bar: Variant in [_dominion_bar, _energy_bar, _infrastructure_bar]:
		if bar != null:
			bar.commander = commander
			bar.controller = self
	_bind_deployment(commander.deployment if commander != null else null)


## The player is now another commander, or nobody (debug mode's player setting). Everything this
## controller held on the old one's behalf is put down, the HUD turns look-only or back, and the
## panels follow the new one.
func _on_local_player_changed(a_commander: Commander) -> void:
	set_look_only(a_commander == null)
	if is_debug_piece_armed():
		disarm_debug_piece()
	deselect()
	clear_pending_selection()
	disarm_command()
	_control_groups = _empty_groups()
	_producer_context = &""
	_bind_commander_panels()
	_teardown_commander_sanctions()
	_setup_commander_sanctions()
	_refresh_available_commands()


func _process(a_delta: float) -> void:
	# A piece armed from the debug card is put down with the debug view.
	if is_debug_piece_armed() and not DebugMode.is_active():
		disarm_debug_piece()
	_tick_sanctions(a_delta)
	# Per-frame, not per-MouseMotion: a drag that crosses onto the HUD stops producing
	# motion events here (the panels consume them), and the box has to keep following the
	# cursor anyway. See _update_drag.
	_update_drag()

	var cursor_result: Variant = get_cursor_target(mouse_position)
	cursor_target = cursor_result
	command_message.target = cursor_result if cursor_result is Entity else null
	command_message.world_position = (
		cursor_result if cursor_result is Vector3 else _cursor_ground_point(mouse_position)
	)
	if _placing:
		# The release is normally delivered as an event, but a HUD panel can swallow one; the
		# action itself cannot be intercepted, so polling it is the backstop (see _update_drag).
		if Input.is_action_pressed(ControlScheme.ARMED_ISSUE):
			_update_placing()
		else:
			_finish_placing_structure()
	_update_line_order()
	_update_ability_target()

	var pruned: bool = prune_selection()
	_selection_commands_age += a_delta
	if pruned:
		_refresh_available_commands()
	elif _selection_commands_age >= SELECTION_COMMANDS_REFRESH_SECONDS and not selection.is_empty():
		_selection_commands_age = 0.0
		_refresh_available_commands_if_changed()

	# Stamp the live deferral state on the message BEFORE anything reads a precondition off
	# it. Written every frame rather than at issue time so the cursor and error line below
	# already reflect the modifier being pressed while the player is aiming a build — and so
	# a message reused across frames can never carry a stale reading.
	command_message.defer_if_unaffordable = _purchase_defers()

	# Command resolution only applies to the player's own units; an enemy/neutral
	# selection is info-only, so no command is resolved (or later issued) for it.
	# Resolved across the WHOLE selection (see resolve_command_class_for_selection), so a
	# mixed group reads the click as whatever its capable members can do rather than as
	# whatever selection[0] happens to be able to do.
	current_command_type = (
		resolve_command_class_for_selection(pending_command_name, selection, command_message)
		if _selection_owned_by_player()
		else null
	)

	if command_message.tool == null:
		# However the tool was put down (issued, replaced, cancelled), the next one starts unturned.
		placement_quarter_turns = 0
	command_message.quarter_turns = placement_quarter_turns if _placement_rotation_applies() else 0

	var check: MoveCommand.PreconditionFailureCause = selection_precondition(
		current_command_type, selection, command_message
	)

	$CommandErrorMessage.text = (
		MoveCommand.precondition_message_map[check]
		if not is_drop_armed()
		else _drop_refusal_message()
	)

	_apply_cursor(_cursor_for_precondition(check))

	_update_build_preview(MoveCommand.is_placement_refusal(check))
	_update_conversion_marker()
	_update_placement_grid(MoveCommand.is_placement_refusal(check))
	_update_cursor_readout()
	_update_waypoint_display()
	_update_rally_indicator()
	_refresh_button_availability()
	_info_view.update(selection, _commander(), production_detail_scope())
	_update_range_display()
	_update_selection_owned_panels()
	_update_producer_affinity()


#region Range display
## An info widget is being hovered: remember what it asked about. Nothing is drawn here —
## _update_range_display recomposes the whole picture next frame.
func _on_ranges_hovered(a_entity: Entity, a_kinds: Array) -> void:
	_hovered_range_entity = a_entity
	_hovered_range_kinds = a_kinds


func _on_ranges_unhovered() -> void:
	_hovered_range_entity = null
	_hovered_range_kinds = []


## Repaint the world-space ranges from scratch, every frame. See RangeIndicator for why the
## whole list is recomposed rather than each source pushing and clearing its own marks.
func _update_range_display() -> void:
	if _range_indicator != null:
		_range_indicator.set_bands(range_bands())


## EVERYTHING THE PLAYER IS CURRENTLY ASKING "HOW FAR?" ABOUT: the ranges of a hovered info
## widget, plus the reach and the area of effect of an armed ability. Public so a test can
## read the decision without a rendered frame.
func range_bands() -> Array[RangeIndicator.Band]:
	var bands: Array[RangeIndicator.Band] = []
	if _hovered_range_entity != null and is_instance_valid(_hovered_range_entity):
		bands.append_array(
			RangeIndicator.bands_for_entity(_hovered_range_entity, _hovered_range_kinds)
		)
	bands.append_array(_armed_ability_bands())
	bands.append_array(_placement_bands())
	return bands


## The placer's dominion claim, under ANY structure being placed: covering a claimed tile costs
## income whatever goes on it, and a claim still pending (an Opticon ordered but not standing)
## is drawn fainter, so a player queuing several can place each against the last.
func _update_claim_layer(a_route: DominionRoute) -> void:
	var key: Variant = a_route.claim_key() if a_route != null else null
	if key == _placement_layer_key and _placement_layer_key != null:
		return
	_placement_layer_key = key
	var cells: Dictionary = {}
	var layer: Dictionary = a_route.claim_layer() if a_route != null else {}
	for cell: Vector2i in layer:
		cells[cell] = PlacementGridOverlay.CLAIM_COLORS[layer[cell]]
	_placement_grid.draw_layer(cells)


## While a structure is being placed: its weapons' and detection reaches around the ghost,
## always, and its vision too while the verbose key is held — the question "what will this
## cover from here" is what placing a defence is. Read off the preview instance's own shapes.
##
## Beside each of its reaches, the same KIND of reach of every structure on our side that it
## would overlap from here — the coverage this one joins. Only overlapping ones, per kind: all
## of them would be a web of circles over the whole base. A structure still planned or going up
## draws its ring dashed (PendingStyle).
func _placement_bands() -> Array[RangeIndicator.Band]:
	var bands: Array[RangeIndicator.Band] = []
	var source: Entity = _placement_source()
	if source == null:
		return bands
	var kinds: Array = [EntityRanges.Kind.ATTACK, EntityRanges.Kind.DETECTION]
	if Input.is_action_pressed("ui_verbose"):
		kinds.append(EntityRanges.Kind.VISION)
	var centre: Vector2 = VU.in_xz(_build_preview.global_position)
	var neighbours: Array[Actor] = _placement_neighbours()
	for kind: int in kinds:
		var reach: Array[float] = _distinct_radii(source, kind)
		for radius: float in reach:
			bands.append(
				RangeIndicator.Band.of(
					HighlightShape.circle(centre, radius), EntityRanges.color_of(kind)
				)
			)
		if reach.is_empty():
			continue
		var widest: float = reach.max()
		for neighbour: Actor in neighbours:
			var pending: bool = neighbour.is_planned or not neighbour.is_built
			for radius: float in _distinct_radii(neighbour, kind):
				if centre.distance_to(neighbour.xz_position) < widest + radius:
					bands.append(
						RangeIndicator.Band.of(
							HighlightShape.circle(neighbour.xz_position, radius),
							EntityRanges.color_of(kind),
							false,
							pending
						)
					)
	return bands


## Each distinct reach `a_piece` has of `a_kind` — two weapons that carry equally far, or a
## gun's ground and air reach, would only draw the same circle twice.
func _distinct_radii(a_piece: Entity, a_kind: int) -> Array[float]:
	var out: Array[float] = []
	for node: CollisionShape3D in EntityRanges.shape_nodes_in_group(
		a_piece, EntityRanges.GROUPS[a_kind]
	):
		var radius: float = RangeShapes.xz_radius(node)
		if radius > 0.0 and not out.has(radius):
			out.append(radius)
	return out


## The structures on the placer's side whose coverage a placement might join — standing, going
## up, or only planned.
func _placement_neighbours() -> Array[Actor]:
	var out: Array[Actor] = []
	var placer: Commander = _placement_commander()
	if placer == null:
		return out
	for node: Node in get_tree().get_nodes_in_group("structure"):
		var piece := node as Actor
		if (
			piece != null
			and not piece.is_queued_for_deletion()
			and placer.shares_side_with(piece.commander_id)
		):
			out.append(piece)
	return out


## The out-of-tree instance of the fixture being placed — a Build's structure, or an armed
## deployment drop — while its ghost is on screen; null otherwise, which is what keeps placement
## marks off every other armed order. A drop registers on the grid like a building, so it gets
## the same marks.
func _placement_source() -> Entity:
	if (
		_build_preview == null
		or not is_instance_valid(_build_preview)
		or not _build_preview.visible
	):
		return null
	if is_drop_armed():
		return _drop_source as Entity
	if (
		current_command_type != Build
		or command_message == null
		or command_message.tool == null
		or selection.is_empty()
	):
		return null
	var commander: Commander = (selection[0] as Entity).commander
	return (
		commander.get_build_preview_instance(command_message.tool) as Entity
		if commander != null
		else null
	)


## Where the fixture being placed is aimed, and whose it is — a drop's is the player's own.
func _placement_aim() -> Vector2:
	return _drop_aim() if is_drop_armed() else command_message.xz_position


func _placement_commander() -> Commander:
	return _commander() if is_drop_armed() else (selection[0] as Entity).commander


## Trace the terrain grid under the structure being placed: its footprint (each cell green or
## red by whether it can be built on), MARGIN_CELLS around it, and — for a piece whose worth is
## the ground it claims, the Opticon — its whole claim, with the cells worth nothing washed out.
## Redrawn only when what it shows changes; the claim itself is memoized on the route.
func _update_placement_grid(a_is_invalid_placement: bool) -> void:
	if _placement_grid == null:
		return
	var source: Entity = _placement_source()
	if source == null:
		if not _placement_grid_key.is_empty():
			_placement_grid.clear()
			_placement_grid_key = []
			_placement_layer_key = null
		return
	var obs := source.get_node_or_null("Fixture") as Fixture
	var dims: Vector2i = _placement_dimensions(obs)
	var origin: Vector2i = map.footprint_origin(_placement_aim(), dims)
	var placer: Commander = _placement_commander()
	var route: DominionRoute = placer.dominion_route() if placer != null else null
	if is_drop_armed():
		a_is_invalid_placement = _drop_refusal_message() != ""
	_update_claim_layer(route)
	var key: Array = [
		_build_preview_tool_type,
		origin,
		a_is_invalid_placement,
		route.claim_key() if route != null else null
	]
	if key == _placement_grid_key:
		return
	_placement_grid_key = key
	var footprint: Dictionary = {}
	for w: int in dims.x:
		for l: int in dims.y:
			footprint[origin + Vector2i(w, l)] = true
	var lit: Dictionary = {}
	for cell: Vector2i in PlacementGridOverlay.dilate(footprint, PlacementGridOverlay.MARGIN_CELLS):
		lit[cell] = PlacementGridOverlay.NEUTRAL_COLOR
	var washed: Dictionary = {}
	var claim: Dictionary = (
		route.site_claim(source, VU.in_xz(_build_preview.global_position))
		if route != null and route.structure_sources.has(source.id)
		else {}
	)
	for cell: Vector2i in claim:
		lit[cell] = (
			PlacementGridOverlay.NEUTRAL_COLOR
			if claim[cell]
			else PlacementGridOverlay.WORTHLESS_COLOR
		)
		if not claim[cell]:
			washed[cell] = PlacementGridOverlay.WORTHLESS_COLOR
	# An extractor is judged as a whole (it overlays a site, or takes a pond), so its cells share
	# the order's verdict; anything else is judged cell by cell, as valid_placement does.
	var per_cell: bool = Extractor.of(source) == null and obs != null
	var planned: Dictionary = (
		placer.planned_footprint_cells() if placer != null and not is_drop_armed() else {}
	)
	# What the placer knows, as Build judges it: the grid must not show what the fog hides.
	var knowledge: PlacementKnowledge = PlacementKnowledge.of(placer, map)
	for cell: Vector2i in footprint:
		var ok: bool = (
			(
				Fixture.cell_admits_structure(
					map, cell, obs.allow_uneven, obs.allow_submerged, knowledge
				)
				and not planned.has(cell)
			)
			if per_cell
			else not a_is_invalid_placement
		)
		lit[cell] = PlacementGridOverlay.VALID_COLOR if ok else PlacementGridOverlay.INVALID_COLOR
		# Washed as well as outlined: the ghost stands over these cells, and thin lines under it
		# do not carry the verdict on their own.
		washed[cell] = lit[cell]
	_placement_grid.draw_cells(lit, washed)


## While an ability is armed: the CASTER's reach, and the area of effect under the cursor.
##
## Two marks answering the two questions an aiming player has — *may I put it there* and
## *what will it cover* — and each is omitted when it has no answer:
##
##   * NO REACH RING FOR A GLOBAL ABILITY. A sanction is cast from anywhere its target is
##     legal (UseSanction measures no distance at all), and a ring around the caster would
##     assert a limit that does not exist. Same for a reach that is not a distance — the
##     Bombard's is spotted GROUND, and no ring describes that.
##   * NO AREA RING FOR AN ABILITY THAT COVERS A POINT. A beacon and a scan land on a spot;
##     a circle around it would suggest a blast that is not coming.
##   * NO AREA RING FOR A SINGLE-UNIT CAST. Promotion or Freeze acts on the one unit under
##     the cursor, which the TargetIndicator marks; a circle would suggest a reach it lacks.
func _armed_ability_bands() -> Array[RangeIndicator.Band]:
	var bands: Array[RangeIndicator.Band] = []
	var ability: StringName = armed_ability_id()
	if ability == &"":
		return bands

	if _armed_reach_is_a_distance():
		for caster: Actor in armed_ability_casters():
			bands.append(
				RangeIndicator.Band.of(
					HighlightShape.circle(
						caster.xz_position, AbilityCatalog.range_for(ability, caster)
					),
					ARMED_REACH_COLOR
				)
			)

	var area: float = _armed_effect_radius(ability)
	if area > 0.0 and command_message != null:
		bands.append(
			RangeIndicator.Band.of(
				HighlightShape.circle(VU.in_xz(command_message.world_position), area),
				ARMED_AREA_COLOR,
				true
			)
		)
	return bands


## The ability the armed order casts, or &"" when nothing ability-shaped is armed.
##
## Three routes reach one answer, because three things can arm an ability: a SANCTION names
## its own, a hotkey-armed ability command is looked up through the catalog, and
## `command_launch` carries its id on the message rather than in the table (see
## _resolve_hotkey_command).
func armed_ability_id() -> StringName:
	if _pending_sanction != null:
		return _pending_sanction.ability_id
	if pending_command_name == "":
		return &""
	if pending_command_name == "command_launch":
		return LAUNCH_ABILITY
	for id: StringName in AbilityCatalog.ids():
		if AbilityCatalog.command_of(id) == pending_command_name:
			return id
	return &""


## WHICH SELECTED PIECE THE REACH RING IS DRAWN AROUND: the charged caster nearest the aim
## point. Null when nothing selected can cast the armed ability.
##
## "Nearest to where you are pointing" is the honest reading of *whose range decides this
## click*, and it is what a player wants a ring around when a pair of guns is selected.
##
## TODO — the ISSUE path does not narrow this way. `assign_command_to_units` gives the order
## to EVERY capable caster (only `modifier_narrow` picks one), so with several selected the
## ring describes one of several that will all fire. Right for the single-caster case, which
## is every case today; revisit when a faction fields several of one battery.
func armed_ability_caster() -> Actor:
	var casters: Array[Actor] = _charged_casters(armed_ability_id())
	if casters.is_empty() or command_message == null:
		return null
	var aim: Vector2 = VU.in_xz(command_message.world_position)
	var best: Actor = null
	var best_distance: float = INF
	for actor: Actor in casters:
		var distance: float = aim.distance_squared_to(actor.xz_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


## EVERY caster whose ring the preview should draw: all the charged ones when the click
## would be cast by all of them, and just the one that would take it otherwise.
##
## This is what makes the preview honest. The rings and the pieces that actually fire are
## the same set by construction, so holding `modifier_broaden` over a pair of spotters lights
## both rings AND sends both the order.
func armed_ability_casters() -> Array[Actor]:
	var ability: StringName = armed_ability_id()
	if ability == &"":
		return []
	if armed_cast_arity() == MoveCommand.CastArity.ALL:
		return _charged_casters(ability)
	var one: Actor = armed_ability_caster()
	return [one] as Array[Actor] if one != null else []


## The selected pieces that grant `a_ability` and are holding a charge for it.
func _charged_casters(a_ability: StringName) -> Array[Actor]:
	var out: Array[Actor] = []
	if a_ability == &"":
		return out
	for node: Node in selection:
		var actor := node as Actor
		if actor == null or not is_instance_valid(actor):
			continue
		var pool := actor.get_node_or_null("Abilities") as Abilities
		if pool != null and pool.is_ready(a_ability):
			out.append(actor)
	return out


## Whether the armed order's reach is a DISTANCE from the caster, and so describable as a
## ring. False for a sanction (global) and for a command whose reach means something else.
func _armed_reach_is_a_distance() -> bool:
	if _pending_sanction != null:
		return false
	var command: Variant = HOTKEY_COMMANDS.get(pending_command_name)
	if command == null:
		# `command_launch` is not in the table (it writes to the message instead) and is an
		# ordinary distance-reached ability.
		return pending_command_name == "command_launch"
	return command.has_method("range_closes_by_moving") and command.range_closes_by_moving()


## The radius of what the armed ability puts down, or 0.0 for one that covers a point.
## A sanction states its own; an ability is measured from what it throws.
func _armed_effect_radius(a_ability: StringName) -> float:
	if _pending_sanction != null:
		# A single-unit cast has no area: the TargetIndicator marks the one unit instead. Nor
		# has a delivery: what lands is pieces, spread onto whatever ground is free.
		if _pending_sanction.targets_one_unit() or _pending_sanction.takes_a_payload():
			return 0.0
		return maxf(_pending_sanction.area_radius(), 0.0)
	return EntityRanges.emission_radius(AbilityCatalog.emission_of(a_ability))


#endregion


## The pointer coming back to us, or the window becoming key again, are the moments the OS
## has just decided for itself what the cursor looks like. Whatever it chose, the custom one
## has to be re-stated — see _apply_cursor.
func _notification(a_what: int) -> void:
	match a_what:
		NOTIFICATION_PREDELETE:
			# The armed piece's source instance never entered the tree, so nothing else frees it.
			disarm_debug_piece()
		NOTIFICATION_WM_MOUSE_ENTER, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN:
			_cursor_needs_reassert = true


func _unhandled_input(a_event: InputEvent) -> void:
	if is_look_only:
		_look_only_input(a_event)
		return
	if a_event is InputEventMouseMotion:
		mouse_position = a_event.position
	elif is_command_armed() and ControlScheme.matches(a_event, ControlScheme.ARMED_CANCEL):
		# Which button this is depends on the control scheme (ControlScheme): the left click in
		# the classic one, the right in the swapped one. Either way it puts the order down and
		# changes the selection not at all. A player who has armed the wrong thing wants out of
		# it, and making them find the right key first is the friction this removes. See
		# ui/control-matrices.md §Context 1a and §Armed-order scheme.
		if _armed_press_belongs_to_ui(a_event):
			return
		disarm_command()
	elif is_command_armed() and ControlScheme.matches(a_event, ControlScheme.ARMED_ISSUE):
		if _armed_press_belongs_to_ui(a_event):
			return
		_issue_current_command()
	elif _placing and ControlScheme.matches(a_event, ControlScheme.ARMED_ISSUE, false):
		# BEFORE the plain world_select release below, which would otherwise take it when the
		# armed-issue button is the left one.
		_finish_placing_structure()
	elif a_event.is_action_pressed("world_select"):
		# A press that starts on a HUD panel isn't a world-selection drag — ignore it so
		# the panel's own controls (or nothing) handle the click. Armed presses were taken above.
		if _pointer_over_blocking_ui():
			return
		begin_drag_at(live_pointer_position())
	elif a_event.is_action_released("world_select"):
		# Resolve on the event when it reaches us, which is the common case and the
		# responsive one; _update_drag polls for the release as the backstop for one a HUD
		# panel swallowed (see there).
		end_drag_at(live_pointer_position())
	elif a_event.is_action_pressed(MODIFIER_ADDITIVE):
		additive_latched = true
		# The modifier is what decides whether an unaffordable purchase queues or is refused,
		# and the grid says which by its tint — so pressing or releasing it has to restyle the
		# buttons NOW. Nothing else in the HUD changes on a bare modifier, which is why this
		# is a targeted restyle rather than a full refresh.
		_refresh_button_availability()
	elif a_event.is_action_released(MODIFIER_ADDITIVE):
		additive_latched = false
		_refresh_button_availability()
	elif a_event.is_action_pressed("command_issue"):
		# BEFORE the `command_` prefix branch below, and it has to stay there. That branch
		# routes every action named `command_*` into the grid hotkey dispatcher, and this one
		# is a pointer button rather than a grid command — reaching the dispatcher would make
		# right-click press whatever sits in a command cell. See
		# gdd/systems/ux/ui/input-action-naming.md §The exception the prefix rule now carries.
		#
		# Armed, this button was taken above, whichever scheme it is; what reaches here is the
		# default order, so both schemes agree on it.
		if a_event is InputEventMouseButton and _begin_line_order():
			return
		_issue_current_command()
	elif _line_pressing and a_event.is_action_released("command_issue"):
		_finish_line_order()
	elif a_event.is_action_pressed("rotate_left") and _placement_rotation_applies():
		placement_quarter_turns = posmod(placement_quarter_turns + 1, 4)
	elif a_event.is_action_pressed("rotate_right") and _placement_rotation_applies():
		placement_quarter_turns = posmod(placement_quarter_turns - 1, 4)
	elif a_event.is_action_pressed(DEBUG_DELETE_ACTION) and DebugMode.is_active():
		delete_selection()
	elif _drop_for_event(a_event) >= 0:
		arm_drop(_drop_for_event(a_event) as Deployment.Drop)
	elif a_event.is_action_pressed("card_ordnance"):
		# SETS rather than toggles, and so does Tab — which is what makes the pair predictable:
		# neither key's meaning depends on where you currently are. Backtick always means
		# "ordnances", Tab always means "my selection". See
		# gdd/systems/ux/ui/command-card-and-hotkeys.md §Switching cards.
		set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	elif a_event.is_action_pressed("card_toggle_family"):
		# Deliberately NOT named `command_*`: the branch below routes every action with that
		# prefix into the grid, and flipping the card is not a command the selection carries
		# out. Same reason modifier_narrow / modifier_broaden avoid the prefix.
		toggle_command_family()
	elif get_action_names_by_prefix(a_event, CONTROL_GROUP_ACTION_PREFIX).size() > 0:
		# Deliberately NOT named `command_*` either: a control group changes the selection
		# rather than acting on it, which is the same reason the selectors keep their own
		# names. Placed above the prefix branch so the reading is never ambiguous.
		_dispatch_control_group(get_action_names_by_prefix(a_event, CONTROL_GROUP_ACTION_PREFIX))
	elif get_action_names_by_prefix(a_event, "command_").size() > 0:
		_dispatch_command_hotkey(get_action_names_by_prefix(a_event, "command_"))


#endregion


## A look-only HUD's input: what changes only what the watcher sees — the pointer, selection and
## its additive modifier, control groups. No branch that issues, arms or cancels an order is
## reached, and no grid key is dispatched (the replay keys share them — ReplayViewer).
func _look_only_input(a_event: InputEvent) -> void:
	if a_event is InputEventMouseMotion:
		mouse_position = a_event.position
	elif a_event.is_action_pressed("world_select"):
		if _pointer_over_blocking_ui():
			return
		begin_drag_at(live_pointer_position())
	elif a_event.is_action_released("world_select"):
		end_drag_at(live_pointer_position())
	elif a_event.is_action_pressed(MODIFIER_ADDITIVE):
		additive_latched = true
	elif a_event.is_action_released(MODIFIER_ADDITIVE):
		additive_latched = false
	elif get_action_names_by_prefix(a_event, CONTROL_GROUP_ACTION_PREFIX).size() > 0:
		_dispatch_control_group(get_action_names_by_prefix(a_event, CONTROL_GROUP_ACTION_PREFIX))


#region Issuing the current order
## Whether a press of an armed-scheme button belongs to the HUD under the cursor. Only a click on
## the world counts as the player's answer, and only the left button can land on a panel, so a
## right-button press is never held back.
func _armed_press_belongs_to_ui(a_event: InputEvent) -> bool:
	return a_event.is_action_pressed("world_select") and _pointer_over_blocking_ui()


## Carry out the current order: what the armed tool, sanction, drop or debug piece is for, or the
## default order for the cursor when nothing is armed.
func _issue_current_command() -> void:
	if _begin_placing_structure():
		pass
	elif is_debug_piece_armed():
		_place_debug_piece()
	elif is_drop_armed():
		_place_drop()
	elif _pending_sanction != null:
		_activate_pending_sanction()
	elif not pending_selection.is_empty():
		# A PHANTOM is what is selected, so the order is stored on its purchase rather than
		# issued to anything. See assign_command_to_pending.
		assign_command_to_pending(current_command_type, command_message, additive_latched)
	elif _selection_owned_by_player():
		# Only the player's own units take commands; an enemy/neutral
		# info-selection ignores the move/command click.
		assign_command_to_units(current_command_type, command_message, additive_latched)


#endregion


#region Move-line drag: hold the order button and draw where the group should stand
## The orders a line may be drawn for: a plain move, and the ones that are a move with a purpose.
## Compared by identity, never by `is`, so a command that merely extends MoveCommand does not
## inherit a line it was never meant to have.
static func line_capable(a_command_type: Script) -> bool:
	return (
		a_command_type == MoveCommand
		or a_command_type == AttackMove
		or a_command_type == Patrol
		or a_command_type == Defend
	)


## Whether a press of the default order button may turn into a line, and so be held back until
## the release. Only with `modifier_broaden` held at the press, so a plain right click and a plain
## right drag are exactly what they were. Not armed orders, not placement, and not a press that
## starts over a unit (that is an order AT the unit, which stays one) or over the HUD.
func _line_order_applies() -> bool:
	if not Input.is_action_pressed(MODIFIER_BROADEN):
		return false
	if is_command_armed() or _placing or not pending_selection.is_empty():
		return false
	if not _selection_owned_by_player() or not (cursor_target is Vector3):
		return false
	if _pointer_over_blocking_ui():
		return false
	return line_capable(current_command_type)


## The press. True when it took it, so the caller issues nothing yet.
func _begin_line_order() -> bool:
	if not _line_order_applies():
		return false
	_line_pressing = true
	_line_command_type = current_command_type
	_line_press_screen = live_pointer_position()
	_line_start = VU.in_xz(_cursor_ground_point(_line_press_screen))
	_line_end = _line_start
	return true


## While the button is down: the end of the line follows the cursor, and the preview is redrawn.
func _update_line_order() -> void:
	if not _line_pressing:
		if _line_indicator != null:
			_line_indicator.clear_line()
		return
	# The release is normally an event, but a HUD panel can swallow one; the action itself cannot
	# be intercepted (see _update_drag).
	if not Input.is_action_pressed("command_issue"):
		_finish_line_order()
		return
	var pointer: Vector2 = live_pointer_position()
	_line_end = VU.in_xz(_cursor_ground_point(pointer))
	if _line_indicator == null or is_click_gesture(_line_press_screen, pointer):
		if _line_indicator != null:
			_line_indicator.clear_line()
		return
	var points: Array[Vector3] = []
	for dest: Vector2 in _line_destinations(OrderDispatcher.line_movers(selection)).values():
		points.append(Vector3(dest.x, map.terrain_height_at(dest), dest.y))
	_line_indicator.show_line(
		Vector3(_line_start.x, map.terrain_height_at(_line_start), _line_start.y),
		Vector3(_line_end.x, map.terrain_height_at(_line_end), _line_end.y),
		points
	)


## The release. A press and release within the click slop is the plain click it always was.
func _finish_line_order() -> void:
	if not _line_pressing:
		return
	_line_pressing = false
	if _line_indicator != null:
		_line_indicator.clear_line()
	if is_click_gesture(_line_press_screen, live_pointer_position()):
		_issue_current_command()
		return
	if not _selection_owned_by_player() or not line_capable(_line_command_type):
		return
	# The order is the PRESS's, aimed at the ground: whatever the cursor passed over since is not
	# part of it. The message position is the middle of the line, which is where a Defend region
	# and anything not given a slot of its own point.
	command_message.target = null
	command_message.world_position = _ground_at((_line_start + _line_end) * 0.5)
	_line_issuing = true
	assign_command_to_units(_line_command_type, command_message, additive_latched)
	_line_issuing = false


func _ground_at(a_xz: Vector2) -> Vector3:
	return Vector3(a_xz.x, map.terrain_height_at(a_xz) if map != null else 0.0, a_xz.y)


## Each actor mapped to its own standing point on the line being drawn
## (OrderDispatcher.line_destinations).
func _line_destinations(a_movers: Array) -> Dictionary:
	return OrderDispatcher.line_destinations(a_movers, _line_start, _line_end)


#endregion


#region Placing a structure: press to set it down, drag to turn it, release to order it
## Whether the armed Build tool takes a facing at all. Not a conversion (that upgrades a
## building that already stands, so there is nothing to turn) and not an extractor (which lies on
## the site or pond it is aimed at and takes that ground's orientation, never one of its own).
func _placement_rotation_applies() -> bool:
	if current_command_type != Build or command_message == null or command_message.tool == null:
		return false
	if armed_conversion_target() != null or selection.is_empty():
		return false
	var lead: Entity = selection[0] as Entity
	var commander: Commander = lead.commander if lead != null else null
	if commander == null:
		return false
	return Extractor.of(commander.get_build_preview_instance(command_message.tool)) == null


## The armed structure's footprint on the grid, turned as the player has it.
func _placement_dimensions(a_structure: Fixture) -> Vector2i:
	if a_structure == null:
		return Vector2i.ONE
	return Fixture.oriented_dimensions(a_structure.dimensions, command_message.quarter_turns)


## The press of `command_issue` with a Build tool armed: put the structure DOWN — freeze where it
## stands — and wait for the release to order it, so the drag between the two can turn it. True
## when it took the press, so the caller issues nothing else.
func _begin_placing_structure() -> bool:
	if is_debug_piece_armed() or is_drop_armed() or _pending_sanction != null:
		return false
	if not pending_selection.is_empty() or not _selection_owned_by_player():
		return false
	if (
		current_command_type != Build
		or command_message.tool == null
		or armed_conversion_target() != null
	):
		return false
	_placing = true
	_placing_world = command_message.world_position
	_placing_target = command_message.target
	return true


## While the press is down: keep the placement where it landed, and turn the structure to face the
## cursor.
func _update_placing() -> void:
	_freeze_placement()
	if _placement_rotation_applies():
		_turn_placement_toward(_cursor_ground_point(live_pointer_position()))


## The placement stays where the press put it, whatever the cursor does.
func _freeze_placement() -> void:
	command_message.target = _placing_target if is_instance_valid(_placing_target) else null
	command_message.world_position = _placing_world


## Turn the structure to face `a_point` (a world position the cursor is over). The direction is
## measured from the PRESS point rather than the snapped centre — the centre moves by half a cell
## when a turn swaps an even footprint's axes, and a reference that moves with the answer would
## flicker at the boundary. Inside the dead zone nothing changes, so a click keeps the facing the
## rotate keys gave it.
func _turn_placement_toward(a_point: Vector3) -> void:
	var direction: Vector2 = VU.in_xz(a_point - _placing_world)
	if direction.length() < PLACEMENT_ROTATE_DEADZONE:
		return
	placement_quarter_turns = Fixture.quarter_turns_facing(direction, placement_quarter_turns)
	command_message.quarter_turns = placement_quarter_turns


## The release: order the build as it now stands. A footprint the turn made illegal is REFUSED
## here — nothing is submitted, and the tool stays armed so the player can turn it back or aim
## elsewhere. A press that was disarmed meanwhile never reaches this (disarm_command clears it).
func _finish_placing_structure() -> void:
	_placing = false
	if current_command_type != Build or command_message.tool == null:
		return
	command_message.quarter_turns = placement_quarter_turns if _placement_rotation_applies() else 0
	var check: MoveCommand.PreconditionFailureCause = selection_precondition(
		current_command_type, selection, command_message
	)
	if MoveCommand.is_placement_refusal(check):
		return
	assign_command_to_units(current_command_type, command_message, additive_latched)


#endregion


#region Box-select drag
## Start a box-select at `a_position`. Only ever reached from a press over the world —
## a press on a HUD panel belongs to that panel (see _unhandled_input).
func begin_drag_at(a_position: Vector2) -> void:
	_dragging = true
	select_down_position = a_position
	update_drag_to(a_position)
	selection_box.visible = true


## Move the live drag's far corner to `a_position` and redraw the box around it.
##
## The box is driven from the LIVE cursor once per frame (see _update_drag) rather than
## from MouseMotion events, because a HUD panel under the pointer eats that motion — the
## panels' Controls are MOUSE_FILTER_STOP, so nothing reaches _unhandled_input — and the
## box used to freeze at the top edge of the HUD the moment a drag crossed into it. It is
## the same staleness that makes `mouse_position` unusable for the over-UI test (see
## _pointer_over_blocking_ui).
func update_drag_to(a_position: Vector2) -> void:
	_drag_position = a_position
	var box: Rect2 = Rect2(select_down_position, a_position - select_down_position).abs()
	selection_box.position = box.position
	selection_box.size = box.size


## Finish the drag at `a_position` and resolve what it caught.
##
## A DRAG resolves wherever it ends, the HUD included: the box keeps growing over the
## panels and takes the units drawn behind them, which is the point — those units are
## under the camera, merely hidden by the overlay.
##
## A CLICK over the HUD still resolves nothing. That press belongs to the panel, and
## letting it through would clear or retarget the world selection on the button-up of
## every info-panel card and command button.
func end_drag_at(a_position: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	update_drag_to(a_position)
	selection_box.visible = false
	if is_click_gesture(select_down_position, a_position) and _pointer_over_blocking_ui():
		return
	_handle_select_release(a_position)


## Per-frame drag upkeep: follow the cursor, and notice a release that never reached us.
func _update_drag() -> void:
	if not _dragging:
		return
	update_drag_to(live_pointer_position())
	# The release is delivered to whatever Control sits under the cursor before it reaches
	# _unhandled_input, so over a panel it can be consumed and never arrive. Polling the
	# action itself can't be intercepted — without this the box would stay up forever.
	if not Input.is_action_pressed("world_select"):
		end_drag_at(_drag_position)


## The cursor right now, in viewport coordinates, clamped to the visible rect so a cursor
## dragged out of the window can't grow the box — and the selection — off into
## coordinates the player can't see.
func live_pointer_position() -> Vector2:
	var bounds: Rect2 = get_viewport().get_visible_rect()
	return get_viewport().get_mouse_position().clamp(bounds.position, bounds.end)


## True when a press and its release are within CLICK_SLOP_PX on BOTH axes — a click
## rather than a box drag. Per-axis on purpose; see CLICK_SLOP_PX.
static func is_click_gesture(from: Vector2, to: Vector2) -> bool:
	var delta: Vector2 = (to - from).abs()
	return delta.x < CLICK_SLOP_PX and delta.y < CLICK_SLOP_PX


#endregion


#region Selection
## True when the LIVE cursor position lies inside any visible HUD panel in the
## SELECTION_BLOCKING_UI_GROUP. Clicks over those panels must not drive world selection.
## Grouping (rather than hard-coding the three sections) means any future full-panel UI
## added to that group is ignored automatically.
##
## Reads get_viewport().get_mouse_position() directly rather than the cached
## `mouse_position` field: that field only updates from MouseMotion events that reach
## _unhandled_input, and motion over a HUD panel is swallowed by the panel — so the
## cached value is stale (still a world point) exactly when we need to know we're over UI.
func _pointer_over_blocking_ui() -> bool:
	if not is_inside_tree():
		return false
	return pointer_over_blocking_ui(get_tree(), get_viewport().get_mouse_position())


## The same test against an explicit position, without needing a controller instance.
##
## Static because RTSCamera3D needs the identical answer for edge panning — the HUD panels
## line the bottom of the screen, so "the cursor is near an edge" and "the cursor is on the
## minimap" are the same pixels, and the camera must not pan while the player is aiming at
## the minimap. There should be exactly one definition of "the cursor is over UI".
static func pointer_over_blocking_ui(tree: SceneTree, screen_pos: Vector2) -> bool:
	for node: Node in tree.get_nodes_in_group(SELECTION_BLOCKING_UI_GROUP):
		var panel: Control = node as Control
		if (
			panel != null
			and panel.is_visible_in_tree()
			and panel.get_global_rect().has_point(screen_pos)
		):
			return true
	return false


## Return all Selectable nodes whose projected screen position falls within screen_rect.
func query_box_collisions(a_screen_rect: Rect2) -> Array:
	return get_tree().get_nodes_in_group("selectables").filter(
		func(selectable: Selectable) -> bool:
			return a_screen_rect.has_point(camera.unproject_position(selectable.global_position))
	)


func deselect():
	for c in selection:
		if is_instance_valid(c):
			c.selectable.deselect()
	selection = []
	pending_command_name = ""


## Make `commandable` the sole selection (used by the info panel's summary cards). Clears
## the current selection, selects just this one, and refreshes the HUD to match.
func select_only(a_commandable: Actor) -> void:
	deselect()
	if is_instance_valid(a_commandable) and a_commandable.selectable.select():
		selection.append(a_commandable)
	_refresh_available_commands()
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)


## Add `commandable` to the current selection, keeping what is already there — the additive
## reading of an occupant card's right click. Selecting anything live drops the pending
## selection, the same as every other way of picking a unit.
func add_to_selection(a_commandable: Actor) -> void:
	if (
		a_commandable == null
		or not is_instance_valid(a_commandable)
		or selection.has(a_commandable)
	):
		return
	_select_units([a_commandable])


## Drop `commandable` from the current selection (used by shift+click on a summary card),
## leaving the rest selected, then refresh the HUD.
func remove_from_selection(a_commandable: Actor) -> void:
	if a_commandable in selection:
		if is_instance_valid(a_commandable):
			a_commandable.selectable.deselect()
		selection.erase(a_commandable)
	_refresh_available_commands()


func set_selection(a_selection_start_position: Vector2, a_selection_end_position: Vector2):
	var drag_distance = abs(a_selection_start_position - a_selection_end_position)
	if drag_distance < Vector2(10, 10):
		var click_target = get_cursor_target(a_selection_start_position)
		if click_target is Entity:
			var entity: Entity = click_target as Entity
			if _selects_as_own(entity):
				# Selecting your own unit never keeps an enemy info-selection around.
				if _has_enemy_selected():
					deselect()
				if additive_latched and selection.has(entity):
					entity.selectable.deselect()
					selection.erase(entity)
				elif entity.selectable.select():
					selection.append(entity)
			elif not additive_latched:
				# Enemy/neutral: single-select only (never additively). The
				# non-additive deselect in _handle_select_release already cleared
				# the prior selection, so this becomes the sole selected unit.
				if entity.selectable.select():
					selection.append(entity)
			# A shift-click on an enemy/neutral unit is ignored (falls through).
	else:
		var box := (
			Rect2(a_selection_start_position, a_selection_end_position - a_selection_start_position)
			. abs()
		)
		var boxed: Array = query_box_collisions(box).filter(
			func(s: Selectable) -> bool: return _selects_as_own(s.get_entity())
		)
		# A box that catches any unit skips structures, so dragging over a mixed group
		# selects only the mobile units (structures are picked individually). Consider
		# the current selection too, so an additive box behaves the same.
		var has_unit: bool = (
			selection.any(func(e): return not e.structure_is_active())
			or boxed.any(func(s: Selectable): return not s.get_entity().structure_is_active())
		)
		for selectable: Selectable in boxed:
			var entity := selectable.get_entity()
			if has_unit and entity.structure_is_active():
				continue
			if selectable.select():
				selection.append(entity)

	_refresh_available_commands()
	if not selection.is_empty():
		# Picking anything live puts the phantoms down — see pending_selection.
		clear_pending_selection()
		unit_selected.emit(selection[0] as Entity)


## Select every player-owned unit whose world XZ falls inside `world_rect` (a
## rectangle in the XZ plane, world units). Mirrors the box branch of
## set_selection but tests each unit's world position directly instead of
## projecting it to screen — this is what the minimap's drag-select uses, since a
## minimap drag defines a region in world space, not on the viewport. `additive`
## keeps the current selection (shift-drag) instead of replacing it.
func select_units_in_world_rect(a_world_rect: Rect2, a_additive: bool) -> void:
	# NARROW is a SET DIFFERENCE here exactly as it is on a viewport drag: whatever the
	# rectangle covers comes OUT of the selection. Read before the additive branch because it
	# takes the whole gesture rather than modifying it — see _deselect_gesture.
	if Input.is_action_pressed(MODIFIER_NARROW):
		_deselect_in_world_rect(a_world_rect)
		return
	if not a_additive:
		deselect()
	var boxed: Array = get_tree().get_nodes_in_group("selectables").filter(
		func(s: Selectable) -> bool:
			var e: Entity = s.get_entity()
			return (
				is_player_commandable(e)
				and _is_perceptible(e)
				and a_world_rect.has_point(VU.in_xz(e.global_position))
			)
	)
	# A box that catches any unit skips structures, so a drag over a mixed group
	# selects only the mobile units (mirrors set_selection). Consider the current
	# selection too, so an additive drag behaves the same.
	var has_unit: bool = (
		selection.any(func(e): return not e.structure_is_active())
		or boxed.any(func(s: Selectable): return not s.get_entity().structure_is_active())
	)
	for selectable: Selectable in boxed:
		var entity: Entity = selectable.get_entity()
		if has_unit and entity.structure_is_active():
			continue
		if not selection.has(entity) and selectable.select():
			selection.append(entity)
	_refresh_available_commands()
	if not selection.is_empty():
		# Picking anything live puts the phantoms down — see pending_selection.
		clear_pending_selection()
		unit_selected.emit(selection[0] as Entity)


## Take every selected unit standing inside [a_world_rect] OUT of the selection — the
## `modifier_narrow` reading of a minimap drag, and the world-space twin of _deselect_gesture.
##
## Measured against each unit's own world position rather than against anything under the
## cursor: a minimap pixel covers far too much ground to mean "this unit", which is the whole
## reason the minimap's controls are world-space versions of the viewport's rather than copies
## of them. See ui/control-matrices.md §Context 2.
func _deselect_in_world_rect(a_world_rect: Rect2) -> void:
	for node: Node in selection.duplicate():
		var commandable := node as Actor
		if (
			commandable != null
			and is_instance_valid(commandable)
			and a_world_rect.has_point(VU.in_xz(commandable.global_position))
		):
			remove_from_selection(commandable)
	_refresh_available_commands()


## Whether the local player may select `entity` with the others it commands and give it
## orders: its own pieces, or — while the debug view is up — anyone's (see
## gdd/systems/ux/ui/debug-mode.md §Commanding any piece). The piece keeps its commander.
static func is_player_commandable(a_entity: Entity) -> bool:
	return (
		a_entity != null and (a_entity.commander_id == PLAYER_COMMANDER_ID or DebugMode.is_active())
	)


## Whether `a_entity` is selected the way the player's own pieces are — additively, by box and by
## double-click — rather than as a single info-selection. Only pieces the user owns are, so a
## look-only HUD, which owns nothing, info-selects every piece one at a time, as a player does an
## enemy's. Not is_player_commandable alone: a replay keeps its recorded human as the local player
## (the simulation reads it), and the watcher does not own that player's pieces.
func _selects_as_own(a_entity: Entity) -> bool:
	return not is_look_only and is_player_commandable(a_entity)


## True when the current selection is the player's own — the only selection the
## player can issue commands to. Enemy/neutral selections are info-only.
func _selection_owned_by_player() -> bool:
	return not selection.is_empty() and is_player_commandable(selection[0] as Entity)


## True when the current selection is a single enemy/neutral (non-player) unit.
func _has_enemy_selected() -> bool:
	return not selection.is_empty() and not is_player_commandable(selection[0] as Entity)


## Recomputes the command set for the current selection, and refreshes HUD button
## visibility via the setter. Empty for an enemy selection — the player can look
## but not command it.
func _refresh_available_commands() -> void:
	available_commands = [] if _has_enemy_selected() else selection_commands(selection)


## Re-derive the selection's commands, applying them only if they changed. What a piece offers
## can change with nothing about the selection changing — a unit finishing a deploy, a Sapper
## planting its charge — so this runs on a short interval rather than only on reselection.
func _refresh_available_commands_if_changed() -> void:
	var fresh: Array = [] if _has_enemy_selected() else selection_commands(selection)
	if fresh != _available_commands:
		available_commands = fresh


## How often the selection's commands are re-derived with no selection change. Short enough
## that a button flips as its state does, long enough not to walk a large selection's
## capability table every frame.
const SELECTION_COMMANDS_REFRESH_SECONDS: float = 0.1
var _selection_commands_age: float = 0.0


## The commands `a_selection` offers, as the card draws them: the union over its pieces, less
## PLANT when the selection also offers DETONATE and nothing in it has a Plant charge ready —
## a Sapper whose charge is in play has nothing to plant, so the shared cell reads Detonate.
static func selection_commands(a_selection: Array) -> Array:
	var names: Array = CommandContextParser.commands_for_selection(a_selection)
	if (
		names.has("command_plant")
		and names.has("command_detonate")
		and not a_selection.any(_can_plant_now)
	):
		names.erase("command_plant")
	return names


static func _can_plant_now(a_node: Variant) -> bool:
	return (
		is_instance_valid(a_node)
		and a_node is Actor
		and Plant.meets_precondition(a_node, null) == MoveCommand.PreconditionFailureCause.NONE
	)


#region Command card family
## Which cards the current selection has anything to draw on, as a CommandFamily bitmask.
## Derived from _available_commands rather than from the entities, because the split is
## between COMMANDS: a structure that both shoots and trains contributes to both, and it is
## exactly that case that made the family the right axis (see ControlBinding.CommandFamily).
func available_families() -> int:
	var mask: int = 0
	for command_name: String in _available_commands:
		var binding: ControlBinding = CommandGrid.binding_for(command_name)
		if binding != null:
			mask |= binding.family
	return mask


## The families a settle or a Tab may land on: the SELECTION-owned two. ORDNANCE is the
## commander's card and is reached by its own key, so it is masked out of every path that
## chooses a card on the player's behalf.
func selection_owned_families() -> int:
	return available_families() & ~ControlBinding.CommandFamily.ORDNANCE


## Show `a_family`, if the selection has anything to put on it. Returns whether the card
## changed, which is what makes the toggle's no-op observable to a caller that cares.
##
## Arming Build leaves a pending sub-mode that only means anything on the ACTIVE card, so
## changing cards drops it — otherwise the structure list would still be armed underneath a
## page that isn't showing it, and the next right-click would place a building.
func set_command_family(a_family: int) -> bool:
	if a_family == _command_family:
		return false
	# ORDNANCE is always enterable, even with nothing unlocked. Its buttons are drawn DARK with
	# the reason on them (see CommandButtonState) rather than removed, because "you have none of
	# these yet" is an answer the player asked for by pressing the key — and a key that silently
	# does nothing reads as broken. Every other family still has to have something to draw.
	if (
		a_family != ControlBinding.CommandFamily.ORDNANCE
		and (selection_owned_families() & a_family) == 0
	):
		return false
	_command_family = a_family
	pending_command_name = ""
	_announce_card()
	upate_hud_buttons()
	return true


## Flip to the other card. Bound to `card_toggle_family` (Tab) and to nothing else; a
## no-op when the selection has nothing to show there, which is the whole reason it is safe
## to hit blind while looking at the battlefield.
func toggle_command_family() -> bool:
	# Coming FROM the commander's card, Tab means "back to my selection" — and which of the two
	# selection cards that is, is re-decided from the selection rather than remembered. An
	# ordnance button CHANGES the selection (it picks the casters), so "the card you were last
	# on" would name a selection that is no longer there.
	if _command_family == ControlBinding.CommandFamily.ORDNANCE:
		return _leave_the_ordnance_card()
	return set_command_family(
		(
			ControlBinding.CommandFamily.PRODUCTION
			if _command_family == ControlBinding.CommandFamily.ACTIVE
			else ControlBinding.CommandFamily.ACTIVE
		)
	)


## Land the card on the one the current selection was picked up FOR.
##
## Called from the available_commands setter, so the card belongs to the selection that
## filled it: picking something new re-decides which page is up, and deselecting a barracks
## while the PRODUCTION card was up drops back to ACTIVE on the same frame. Keeping this in
## ONE place is what lets the hotkeys and the buttons read the same field and never
## disagree. The player's own toggle stands until the selection changes, because nothing
## else writes available_commands.
##
## A selection with nothing on either card (an enemy unit, or nothing at all) is left as-is
## rather than flipped about — the panels are hidden in that state anyway, and thrashing the
## field would only mean the card jumped when the player next selected something.
func _settle_command_family() -> void:
	# The commander's card is left when the player picks something that has NO ordnances of its
	# own — selecting a soldier is an act of "I want to command this", and the card should
	# follow. It is NOT left when the new selection does have them, which is what keeps an
	# ordnance button (it selects its own casters) from throwing the player off the card they
	# just pressed it on. An EMPTY selection leaves it alone too: deselecting is not picking
	# something else, and the commander's card is not about the selection in the first place.
	if _command_family == ControlBinding.CommandFamily.ORDNANCE:
		if (
			not selection.is_empty()
			and (available_families() & ControlBinding.CommandFamily.ORDNANCE) == 0
		):
			_leave_the_ordnance_card()
		return
	var families: int = selection_owned_families()
	if families == 0:
		return
	var preferred: int = _preferred_command_family(families)
	if preferred == _command_family:
		return
	_command_family = preferred
	pending_command_name = ""
	_announce_card()


## Tell the banner which card is up. Called from BOTH writers of `_command_family` — the
## explicit set and the settle — because a banner that tracked only one of them would be
## right until the selection changed under it.
func _announce_card() -> void:
	if _mode_banner != null:
		_mode_banner.show_family(_command_family, armed_card_state(), armed_variant_label())


## Which form of the armed piece is chosen, for the banner: the variant's name, or "" when the
## armed tool has none (or nothing is armed).
func armed_variant_label() -> String:
	var armed: Tool = command_message.tool if command_message != null else null
	return armed.variant_label() if armed != null else ""


## How far along the armed order is, for the banner: NONE, PENDING (the card is still asking
## which structure / which cargo), or READY (nothing left to choose — go and aim it).
##
## Derived from the same two predicates the card itself reads, rather than tracked, so the
## banner cannot claim a state the grid is not in.
func armed_card_state() -> CardModeBanner.ArmedState:
	if not is_command_armed():
		return CardModeBanner.ArmedState.NONE
	return (
		CardModeBanner.ArmedState.READY if is_command_ready() else CardModeBanner.ArmedState.PENDING
	)


## Go from the commander's card back to the selection's, and say which. Falls back to ACTIVE
## when the selection has nothing on either card — including when there is no selection at
## all — rather than refusing: pressing Tab has to DO something visible, and landing on an
## empty ACTIVE hides the panel, which is the close gesture. Refusing would leave the player
## on ORDNANCE wondering whether the key had registered.
##
## Bypasses set_command_family's emptiness check for exactly that reason, and is the only
## thing that does.
func _leave_the_ordnance_card() -> bool:
	var families: int = selection_owned_families()
	_command_family = (
		_preferred_command_family(families)
		if families != 0
		else ControlBinding.CommandFamily.ACTIVE
	)
	pending_command_name = ""
	_announce_card()
	upate_hud_buttons()
	return true


## Which card a fresh selection opens on, given what it has to draw.
##
## ACTIVE is the resting state, for the reason stated on `_command_family`: a group picked
## up mid-fight is picked up to be ORDERED. A selection with NOTHING MOBILE in it was not —
## it was picked up to be told what to make — so a stationary producer opens on PRODUCTION.
##
## That second clause is load-bearing rather than a nicety. Every producer offers a rally,
## and a rally is a bare `command_move`; once the plain move got a cell of its own (the Go
## verb) that made every barracks in the game report a ACTIVE command, and preferring ACTIVE
## unconditionally hid every train button behind the toggle. The mobility test is what
## separates "has a ACTIVE command" from "was selected in order to be given one".
func _preferred_command_family(a_families: int) -> int:
	if (
		(a_families & ControlBinding.CommandFamily.PRODUCTION) != 0
		and not _selection_takes_orders()
	):
		return ControlBinding.CommandFamily.PRODUCTION
	return (
		ControlBinding.CommandFamily.ACTIVE
		if (a_families & ControlBinding.CommandFamily.ACTIVE) != 0
		else ControlBinding.CommandFamily.PRODUCTION
	)


## Whether anything in the selection can be sent somewhere — the one question that
## distinguishes a group being commanded from a building being run.
func _selection_takes_orders() -> bool:
	return selection.any(
		func(entity: Node) -> bool: return (entity as Entity).live_movement() != null
	)


#endregion


## Resolves a left-click release into either a double-click (select all on-screen
## units of the clicked unit's type) or a normal single-click / box selection.
##
## `a_end_position` is where the release landed, passed in rather than read off
## `mouse_position`: that field only tracks motion that reaches _unhandled_input, so it is
## stale exactly when the drag ended over the HUD — which is now a case that resolves.
func _handle_select_release(a_end_position: Vector2) -> void:
	# Only a click (not a drag) can be part of a double-click; identify the
	# player unit under the cursor, if any.
	var is_click: bool = is_click_gesture(select_down_position, a_end_position)
	# get_cursor_target returns an Entity, a Vector3 (terrain), or null — only keep
	# the Entity case (guard the cast so a Vector3 isn't cast to Entity).
	var hit: Variant = get_cursor_target(select_down_position) if is_click else null
	var target: Entity = hit as Entity if hit is Entity else null
	var is_player_unit: bool = _selects_as_own(target)

	# NARROW is a SET DIFFERENCE and takes the whole gesture: whatever the box or the click
	# caught comes OUT of the selection and everything else stays. It deliberately ignores
	# additive — "remove these" has no additive reading, and the overlap with shift-clicking
	# a selected unit is accepted (see ui/control-matrices.md §Context 1).
	if Input.is_action_pressed(MODIFIER_NARROW):
		_deselect_gesture(select_down_position, a_end_position, target, is_click)
		_last_click_target = null
		return

	# BROADEN on a click takes every on-screen unit of that type — the double-click's reach,
	# without the timing. On a DRAG it means nothing, so the box runs unmodified.
	if is_click and is_player_unit and Input.is_action_pressed(MODIFIER_BROADEN):
		_select_on_screen_units_of_type(target.id)
		_last_click_target = null
		return

	if is_player_unit and _is_double_click(target):
		_select_on_screen_units_of_type(target.id)
		_last_click_target = null  # reset so a third quick click starts fresh
		return

	if !additive_latched:
		deselect()
	set_selection(select_down_position, a_end_position)
	# Record this click so a matching follow-up click registers as a double-click.
	_last_click_target = target if is_player_unit else null
	_last_click_time_ms = Time.get_ticks_msec()


## Take everything this gesture caught OUT of the selection — the `modifier_narrow` reading of
## a left click or a box drag, and the inverse of what the same gesture does unmodified.
##
## SET DIFFERENCE, not "select these": ten units selected and a box over three of them leaves
## seven. It answers the case a shift-click cannot, which is dropping a whole group from a
## selection in one gesture rather than one unit at a time.
##
## Nothing is selected here, so nothing filters on ownership beyond what the selection already
## holds: a unit that is not in the selection cannot be removed from it, and the removal loop
## is the only ownership rule this needs.
func _deselect_gesture(
	a_start: Vector2, a_end: Vector2, a_target: Entity, a_is_click: bool
) -> void:
	var caught: Array = []
	if a_is_click:
		if a_target != null:
			caught.append(a_target)
	else:
		for selectable: Selectable in query_box_collisions(Rect2(a_start, a_end - a_start).abs()):
			var entity: Entity = selectable.get_entity()
			if entity != null:
				caught.append(entity)
	for entity: Variant in caught:
		var commandable := entity as Actor
		if commandable != null and selection.has(commandable):
			remove_from_selection(commandable)
	_refresh_available_commands()


## True when `target` is the same unit clicked last, within DOUBLE_CLICK_SECONDS.
func _is_double_click(a_target: Entity) -> bool:
	return (
		a_target == _last_click_target
		and _last_click_time_ms >= 0
		and (Time.get_ticks_msec() - _last_click_time_ms) <= int(DOUBLE_CLICK_SECONDS * 1000.0)
	)


## Replaces the selection (or adds, when additive) with every on-screen,
## player-owned commandable whose entity type matches `entity_type`.
func _select_on_screen_units_of_type(a_entity_type: StringName) -> void:
	if !additive_latched:
		deselect()
	var candidates: Array = get_tree().get_nodes_in_group("piece").filter(
		func(c: Variant) -> bool:
			return (
				c is Entity and (c as Entity).id == a_entity_type and _selects_as_own(c as Entity)
			)
	)
	_select_units(commandables_on_screen(candidates))


## Where this controller's map and trigger host are looked up: its scenario, else the running
## scene (a HUD previewed on its own).
func _session_root() -> Node:
	var scenario: Scenario = Scenario.of(self)
	return scenario if scenario != null else get_tree().current_scene


## The Commander this controller drives: the scenario's local player, which debug mode can
## change mid-match. A controller outside a scenario (a test rig, a HUD preview) drives the
## Commander it is a child of (see player.tscn).
func _commander() -> Commander:
	if is_look_only:
		return null
	var local: Commander = _scenario.local_player() if _scenario != null else null
	return local if local != null else get_parent() as Commander


## Kill everything selected, whoever owns it. A DEATH rather than a removal: `_on_death` is
## the one complete teardown (grid cells, commander bookkeeping), and triggers and tallies
## see it as they would any other. A Actor with hit points is killed through them, so
## it dies on its own tick like any other kill; anything else dies at once.
func delete_selection() -> void:
	if _scenario != null and not selection.is_empty():
		_scenario.note_debug_change("debug delete")
	for node: Variant in selection.duplicate():
		var entity: Entity = node as Entity if is_instance_valid(node) else null
		if entity == null:
			continue
		if entity is Actor and entity.defense != null:
			entity.defense.kill()
		else:
			entity.die()
	deselect()
	_refresh_available_commands()


## Whose economy the selection's purchases draw on: its owner's. The local player's own,
## except when the debug view lets them select another commander's pieces.
func _selection_commander() -> Commander:
	var first: Entity = selection[0] as Entity if not selection.is_empty() else null
	return first.commander if first != null and first.commander != null else _commander()


## True while the additive modifier is held: an unaffordable purchase issued right now is
## QUEUED rather than refused, and a command issued right now is appended rather than
## replacing what the actor was doing. One reading, asked at the moment the order is made.
##
## Polled from the LIVE input state rather than read off `additive_latched`, which is
## latched from _unhandled_input. A purchase is normally issued by CLICKING a HUD button,
## and the modifier keypress that precedes that click goes to the focused Control first —
## so a latch can miss it entirely. Polling asks the input singleton directly and can't be
## intercepted.
func _purchase_defers() -> bool:
	return additive_modifier_held()


## How many of a thing one press of its train button buys — BULK_PURCHASE_COUNT while
## `modifier_broaden` is held, one otherwise. Broaden takes the wider action here as it does
## everywhere else; see ui/control-matrices.md §Context 3b.
##
## Polled, not latched, for the reason _purchase_defers polls: this is read on a HUD BUTTON
## press, and the modifier keydown before it goes to the focused Control.
func bulk_purchase_count() -> int:
	return OrderDispatcher.BULK_PURCHASE_COUNT if Input.is_action_pressed(MODIFIER_BROADEN) else 1


## True while the additive modifier is held, asked of the INPUT SINGLETON rather than of
## `additive_latched`. Anything issued from a HUD Control — a grid button's press, the
## minimap's drag-select — has to ask this way: the modifier keypress that precedes the
## click is delivered to the focused Control and never reaches _unhandled_input, so the
## latch can miss it entirely.
func additive_modifier_held() -> bool:
	return Input.is_action_pressed(MODIFIER_ADDITIVE)


## One-shot: the next purchase issued is a STANDING order — an entry that re-issues itself
## forever, always behind every one-off purchase, so idle income has somewhere to go.
##
## Set by a RIGHT-CLICK on the grid button that would otherwise buy the thing once (see
## _on_control_button_alternate_pressed). Grid buttons have an unspent right-click, so this
## costs no key at all — and it replaces the old `purchase_fallback` modifier, whose job
## was the same and which spent Alt to do it. Alt is now free for the selector matrix.
##
## A flag rather than a parameter threaded through process_command → resolve → assign,
## because the purchase is submitted several frames of call stack below the click and only
## the click knows which button was which.
var _next_purchase_standing: bool = false


## Read and clear the standing flag. Cleared on read so an abandoned right-click (a build
## tool armed and then never placed) can't turn a later purchase standing by surprise.
func _take_purchase_standing() -> bool:
	var standing: bool = _next_purchase_standing
	_next_purchase_standing = false
	return standing


## Show the selection-owned panels only while something IS selected, and the selectors and
## the global production readout only while nothing is.
##
## The info panel's cards and the command grid both describe a selection, so with none they
## have nothing to say and are better gone than empty. The global production readout takes the
## info panel's slot in that state: the two are mutually exclusive, so the centre of the screen
## is either what you are holding or what you have committed to (hud-layout.md §Production).
##
## `visible` is what the blocking-UI test reads (see _pointer_over_blocking_ui), so hiding
## these also stops them swallowing world clicks over what is now empty screen.
func _update_selection_owned_panels() -> void:
	var has_selection: bool = not selection.is_empty()
	$InfoSection.visible = has_selection
	# THE ONE EXCEPTION to the selection-owned rule. The command grid is otherwise hidden
	# wholesale on an empty selection, but the ORDNANCE card is the COMMANDER's — its whole
	# point is that you reach an ability without first hunting down something that can cast it,
	# so it has to stand with nothing selected at all.
	$CommandsSection.visible = (
		not is_look_only
		and (has_selection or _command_family == ControlBinding.CommandFamily.ORDNANCE)
	)
	if _selector_panel != null:
		_selector_panel.visible = not has_selection and not is_look_only
	if _production_rail != null:
		_production_rail.is_active = not has_selection


# --- Category predicates (a Actor satisfies the category) ---------------
## "Army" unit: a unit carrying at least one Weapon in its Loadout.
func _is_army_unit(a_c: Actor) -> bool:
	var loadout: Loadout = a_c.get_node_or_null("Loadout") as Loadout
	return a_c.is_in_group("unit") and loadout != null and loadout.has_weapons()


## "Builder" unit: a unit with a Builds component.
func _is_builder_unit(a_c: Actor) -> bool:
	return a_c.is_in_group("unit") and a_c.has_node("Builds")


## "Production structure": a structure that can train units (has Production).
func _is_producer_structure(a_c: Actor) -> bool:
	return a_c.is_in_group("structure") and a_c.production != null and a_c.production.trains_units()


# --- Idle predicates (a Actor in that category has nothing to do) --------
## Idle unit: no active command.
func _is_idle_unit(a_c: Actor) -> bool:
	return a_c._command == null


## Idle production structure: can produce but has neither a job training nor a queued
## purchase waiting to land on it — a structure named by a pending transaction is spoken
## for, not wasted throughput.
func _is_idle_producer(a_c: Actor) -> bool:
	return (
		a_c.production.is_free()
		and (_commander() == null or _commander().production_queue.pending_count_for(a_c) == 0)
	)


# --- The three selectors ------------------------------------------------------
## F1 / F2 / F3. Each takes the whole matrix; the modifiers held decide which cell.
func select_army() -> void:
	_run_selector(_is_army_unit, _is_idle_unit)


func select_builders() -> void:
	_run_selector(_is_builder_unit, _is_idle_unit)


func select_production_structures() -> void:
	_run_selector(_is_producer_structure, _is_idle_producer)


## The selector rules. TWO axes, each owned by one modifier, both ABSOLUTE:
##
## Why it works this way: gdd/systems/ux/ui/selection-and-input.md §How a selector resolves its
## candidate set.
func _run_selector(a_category: Callable, a_idle: Callable) -> void:
	var idle_only: bool = Input.is_action_pressed(MODIFIER_NARROW)
	var predicate: Callable = a_category
	if idle_only:
		predicate = func(c: Actor) -> bool: return a_category.call(c) and a_idle.call(c)
	if Input.is_action_pressed(MODIFIER_BROADEN):
		_select_all_matching(predicate)
		return
	_cycle_one_matching(predicate)


## The three families, as [category, idle] predicate pairs. Indexed by SelectorFamily, and
## built here rather than as a const because the predicates are instance methods.
var _selector_predicates: Array = []

## Which family a selector button drives. Ordered to match _selector_predicates.
enum SelectorFamily { ARMY, BUILDER, PRODUCTION }


## What pressing a family's selector would yield RIGHT NOW, as {count, label}, given the
## modifiers currently held.
##
## This is what lets the selector buttons PREVIEW the cell the player is in — the rules are
## otherwise a 2×2 that exists only in documentation, discoverable by nothing on screen.
## Holding a modifier re-renders the buttons, so the other cells are found by pressing a key
## rather than by reading about it.
##
## Deliberately routed through the same `_owned_matching` the two selection routines use, so
## a preview can never disagree with what the press actually does.
func selector_preview(a_family: int) -> Dictionary:
	if a_family < 0 or a_family >= _selector_predicates.size():
		return {"count": 0, "scope": ""}
	var pair: Array = _selector_predicates[a_family]
	var category: Callable = pair[0]
	var idle: Callable = pair[1]
	var idle_only: bool = Input.is_action_pressed(MODIFIER_NARROW)
	var take_all: bool = Input.is_action_pressed(MODIFIER_BROADEN)
	var predicate: Callable = category
	if idle_only:
		predicate = func(c: Actor) -> bool: return category.call(c) and idle.call(c)
	var count: int = _owned_matching(predicate).size()
	# The VERB matters as much as the number: "cycle 6" and "select 6" are different presses
	# with the same count, and the button is the only place that difference is visible. The
	# label is built HERE rather than in the panel so the two can't drift.
	var verb: String = "select" if take_all else "cycle"
	var subject: String = "idle" if idle_only else ""
	var label: String = (
		("%s %s" % [verb, subject]).strip_edges()
		if count == 0
		else ("%s %d %s" % [verb, count, subject]).strip_edges()
	)
	if count == 0:
		label = "no %s" % ("idle" if idle_only else "members")
	return {"count": count, "label": label}


## Run a family's selector — the button path, matching what its F-key does.
func run_selector_family(a_family: int) -> void:
	if a_family < 0 or a_family >= _selector_predicates.size():
		return
	var pair: Array = _selector_predicates[a_family]
	_run_selector(pair[0] as Callable, pair[1] as Callable)


# --- Shared selection machinery -----------------------------------------------
## Select every player-owned commandable satisfying `predicate` (replacing the current
## selection first unless additive). The "take all" half of the cardinality axis.
func _select_all_matching(a_predicate: Callable) -> void:
	if !additive_latched:
		deselect()
	var candidates: Array = _owned_matching(a_predicate)
	_select_units(candidates)
	_look_at_selection(candidates)


## Every selectable commandable this player owns that satisfies `predicate`.
##
## Always the whole map: scope is no longer a selector axis (see _run_selector). The single
## place that filter is expressed — both selection routines and the button PREVIEW
## (selector_preview) go through it, so a button that says "cycle 3" and the press that
## follows can never be looking at different sets.
func _owned_matching(a_predicate: Callable) -> Array:
	return get_tree().get_nodes_in_group("piece").filter(
		func(node: Variant) -> bool:
			var c: Actor = node as Actor
			return is_player_commandable(c) and c.selectable != null and a_predicate.call(c)
	)


## Selects each commandable in `entities` (skipping already-selected ones) and
## refreshes the HUD / available-command state. Shared selection finalizer.
func _select_units(a_entities: Array) -> void:
	# One recipient set per gesture: picking anything live puts the phantoms down. Here rather
	# than in deselect(), because deselect is also how select_pending clears the live side and
	# the two would chase each other.
	if not a_entities.is_empty():
		clear_pending_selection()
	for entity: Node in a_entities:
		var cmd: Actor = entity as Actor
		if cmd == null or cmd.selectable == null or selection.has(cmd):
			continue
		if cmd.selectable.select():
			selection.append(cmd)
	available_commands = CommandContextParser.commands_for_selection(selection)
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)


## The "cycle one" half of the cardinality axis. Picks one commandable satisfying
## `predicate`, makes it the sole selection (unless additive) and brings the camera to it.
## Returns it, or null if none qualify.
##
## Ordering is purely LEAST-RECENTLY-SELECTED over whatever `predicate` allowed through.
## Selecting bumps Selectable.last_selected_time, so repeated presses walk the group.
##
## Deliberately NOT idle-first. Ranking idle members above busy ones sounds like a free
## improvement and is not: the precedence is absolute, so the cycle never leaves the idle set
## while one member is idle — which makes the unmodified press identical to MODIFIER_NARROW
## exactly whenever that modifier would have mattered. Two cells collapsing into one is the
## failure the old on-screen/global split had, and it is not worth repeating. The filter is
## the modifier's job; the order is this function's.
func _cycle_one_matching(a_predicate: Callable) -> Actor:
	var candidates: Array = _owned_matching(a_predicate)
	var times: Array = []
	for node: Node in candidates:
		times.append((node as Actor).selectable.last_selected_time as float)
	var index: int = cycle_index(times)
	if index < 0:
		return null
	var best: Actor = candidates[index] as Actor

	# Shift adds to the selection rather than replacing it, the same way _select_all_matching
	# reads it — so a cycler can extend a group one member at a time.
	if !additive_latched:
		deselect()
	if not selection.has(best) and best.selectable.select():
		selection.append(best)
	available_commands = CommandContextParser.commands_for_selection(selection)
	unit_selected.emit(best)
	_look_at_selection([best])
	return best


## Which of `a_last_selected_times` the cycler takes: the least-recently-selected, or -1 for
## an empty set. Selecting the pick bumps its time, so repeated presses walk the whole group
## once before returning to the front of it.
##
## Static and node-free so the RULE can be pinned without a live entity, exactly as
## OrderDispatcher.narrowed_index is for the command side.
static func cycle_index(last_selected_times: Array) -> int:
	var best: int = -1
	var best_time: float = 0.0
	for i: int in last_selected_times.size():
		var last_selected: float = last_selected_times[i] as float
		if best == -1 or last_selected < best_time:
			best = i
			best_time = last_selected
	return best


#endregion

#region Control groups
## Ten remembered selections, addressed by the `control_group_N` input actions (N = 1…10).
##
## THE ACTION IS THE BINDING, NOT THE KEY. The defaults are the number row with `0` standing
## for group 10, but nothing outside project.godot names a digit — the same discipline the
## positional cell hotkeys follow (see ControlBinding.CELL_ACTION_PREFIX), so a rebinding
## screen can move any of them without touching this file.
const CONTROL_GROUP_ACTION_PREFIX: String = "control_group_"
const CONTROL_GROUP_COUNT: int = 10

## What a control-group press does. All five cells of the modifier table, named — see
## control_group_gesture for which modifiers reach which.
enum ControlGroupGesture {
	## Replace the selection with the group.
	RECALL,
	## Add the group to the selection, keeping what was already selected.
	EXTEND_SELECTION,
	## Take the current selection OUT of the group. Edits the group; leaves the selection be.
	REMOVE_FROM_GROUP,
	## Make the group be exactly the current selection.
	ASSIGN_GROUP,
	## Add the current selection to the group, keeping what the group already held.
	EXTEND_GROUP,
	## Take the group's members OUT of the selection. Edits the selection; leaves the group be
	## — the mirror of REMOVE_FROM_GROUP, and the one gesture the NUMBER ROW cannot reach.
	## The panel's buttons can, because their LMB/RMB axis frees a modifier up: see
	## control_group_button_gesture.
	REMOVE_FROM_SELECTION,
}

## The ten groups, each an Array of Commandables in the order they were added. Membership
## is remembered state by definition — a control group IS a memory of a selection — which is
## the one thing it can be.
##
## Allocated in the declaration rather than in _ready so every index is addressable from the
## first press, and so the group rules can be exercised on a controller that was never put
## in a scene tree.
var _control_groups: Array = _empty_groups()

## The group last READ by a press, and when (wall-clock ms, a UI timing), so a second press of
## the same group within DOUBLE_CLICK_SECONDS is a double tap. -1: no read to pair with.
var _last_group_tap_index: int = -1
var _last_group_tap_ms: int = 0


static func _empty_groups() -> Array:
	var out: Array = []
	for i: int in CONTROL_GROUP_COUNT:
		out.append([])
	return out


## Which gesture the modifiers currently held ask for.
##
## Two axes, the way the rest of the interface reads these keys: `broaden` / `narrow` decide
## whether the press READS the group or WRITES it, and `additive` decides whether the
## operation replaces or extends. That gives every cell the same meaning it has everywhere
## else — broaden takes the wider action (put the selection INTO the group), narrow the
## restricting one (take it out), additive extends rather than replaces.
##
## Narrow is tested first, so holding both write modifiers removes. They name opposite
## writes rather than composing the way they do on a selector, so one of them has to win;
## this is the table's own row order and nothing more.
##
## Additive is not read on the narrow row — the table leaves that cell unused, and an
## unused cell is better spent doing the row's obvious thing than refusing the press.
static func control_group_gesture(
	is_additive: bool, is_narrow: bool, is_broaden: bool
) -> ControlGroupGesture:
	if is_narrow:
		return ControlGroupGesture.REMOVE_FROM_GROUP
	if is_broaden:
		return ControlGroupGesture.EXTEND_GROUP if is_additive else ControlGroupGesture.ASSIGN_GROUP
	return ControlGroupGesture.EXTEND_SELECTION if is_additive else ControlGroupGesture.RECALL


## Which gesture a CONTROL-GROUP BUTTON press asks for. The panel's table, not the keyboard's.
##
## A button press carries one axis the number row does not: LEFT vs RIGHT. That axis IS the
## read/write axis — which on the keyboard is what `broaden` spends — so the button reads
## `broaden` not at all and gets a whole modifier back. What it buys is the one cell the
## number row has nowhere to put: REMOVE_FROM_SELECTION, the mirror of REMOVE_FROM_GROUP.
##
## |                    | LEFT (reads the group, acts on the selection) | RIGHT (writes the group) |
## |--------------------|-----------------------------------------------|--------------------------|
## | *none*             | RECALL                                        | ASSIGN_GROUP             |
## | `modifier_additive`| EXTEND_SELECTION                              | EXTEND_GROUP             |
## | `modifier_narrow`  | REMOVE_FROM_SELECTION                         | REMOVE_FROM_GROUP        |
##
## Every modifier keeps the direction it carries everywhere else — additive extends rather
## than replaces, narrow restricts — so the table is predictable rather than memorised, which
## is the same claim control_group_gesture makes for the keyboard. Narrow is tested first for
## the same reason it is there: the two writes are opposites and cannot compose.
static func control_group_button_gesture(
	is_write: bool, is_additive: bool, is_narrow: bool
) -> ControlGroupGesture:
	if is_narrow:
		return (
			ControlGroupGesture.REMOVE_FROM_GROUP
			if is_write
			else ControlGroupGesture.REMOVE_FROM_SELECTION
		)
	if is_additive:
		return (
			ControlGroupGesture.EXTEND_GROUP if is_write else ControlGroupGesture.EXTEND_SELECTION
		)
	return ControlGroupGesture.ASSIGN_GROUP if is_write else ControlGroupGesture.RECALL


## The gesture the modifiers currently held ask of a control-group BUTTON, [a_is_write]
## saying which mouse button was used. Polled rather than read off the event, for the reason
## run_control_group polls: a modifier keydown that lands while a HUD Control has focus never
## reaches _unhandled_input, and a HUD button press is exactly that case.
func run_control_group_button(a_index: int, a_is_write: bool) -> void:
	apply_control_group_gesture(
		a_index,
		control_group_button_gesture(
			a_is_write,
			Input.is_action_pressed(MODIFIER_ADDITIVE),
			Input.is_action_pressed(MODIFIER_NARROW)
		)
	)


## The zero-based group `a_action` addresses, or -1 if it is not a control-group action.
## Player-facing numbering is 1…CONTROL_GROUP_COUNT, matching the keys; the storage index
## is one less.
static func control_group_index_from_action(action: String) -> int:
	if not action.begins_with(CONTROL_GROUP_ACTION_PREFIX):
		return -1
	var suffix: String = action.substr(CONTROL_GROUP_ACTION_PREFIX.length())
	if not suffix.is_valid_int():
		return -1
	var number: int = int(suffix)
	return number - 1 if number >= 1 and number <= CONTROL_GROUP_COUNT else -1


## The action addressing group `a_index`. Inverse of control_group_index_from_action.
static func control_group_action(index: int) -> StringName:
	return StringName("%s%d" % [CONTROL_GROUP_ACTION_PREFIX, index + 1])


## Every control-group action the game expects to exist — the list a rebinding screen would
## enumerate, and what test_ControlGroups checks project.godot against.
static func control_group_actions() -> Array:
	var out: Array = []
	for i: int in CONTROL_GROUP_COUNT:
		out.append(control_group_action(i))
	return out


## `a_group` with every member of `a_removed` taken out, by identity.
static func without_members(group: Array, removed: Array) -> Array:
	return group.filter(func(member: Variant) -> bool: return not removed.has(member))


## `a_group` with `a_added` appended, skipping anything already in it. Order-preserving and
## de-duplicating: a unit added to a group twice is in it once.
static func with_members(group: Array, added: Array) -> Array:
	var out: Array = group.duplicate()
	for member: Variant in added:
		if not out.has(member):
			out.append(member)
	return out


## `a_group` minus anything that has died or left the world. Pruned on READ rather than
## watched for: hooking every member's tree_exiting to keep ten arrays exact would be a lot of
## bookkeeping for a filter.
##
## Validity is asked of the untyped member BEFORE any cast: casting a freed object is itself
## an error (CLAUDE.md §A freed object cannot be passed to a typed parameter).
static func live_members(group: Array) -> Array:
	return group.filter(
		func(member: Variant) -> bool:
			return (
				is_instance_valid(member) and member is Node and (member as Node).is_inside_tree()
			)
	)


## The live membership of group `a_index`, or empty for an index out of range.
func control_group(a_index: int) -> Array:
	if a_index < 0 or a_index >= _control_groups.size():
		return []
	return live_members(_control_groups[a_index])


## Run a control-group press: read the modifiers, then apply the gesture they name.
##
## The modifiers are POLLED rather than read off the event, for the reason the selectors
## poll them (see _run_selector): a modifier keydown that lands while a HUD Control has
## focus never reaches _unhandled_input, so the Shift latch can miss it. A control-group
## press is a keyboard press like a selector's, so it reads them the same way.
func run_control_group(a_index: int) -> void:
	apply_control_group_gesture(
		a_index,
		control_group_gesture(
			Input.is_action_pressed(MODIFIER_ADDITIVE),
			Input.is_action_pressed(MODIFIER_NARROW),
			Input.is_action_pressed(MODIFIER_BROADEN)
		)
	)


## Apply one gesture to one group. Split from run_control_group so the effect can be
## exercised without pressing keys.
func apply_control_group_gesture(a_index: int, a_gesture: ControlGroupGesture) -> void:
	if a_index < 0 or a_index >= _control_groups.size():
		return
	# Every gesture starts from the live membership, so a group that has lost members to the
	# fighting is corrected by being used rather than accumulating corpses.
	var group: Array = live_members(_control_groups[a_index])
	_control_groups[a_index] = group
	match a_gesture:
		ControlGroupGesture.ASSIGN_GROUP:
			_control_groups[a_index] = selection.duplicate()
		ControlGroupGesture.EXTEND_GROUP:
			_control_groups[a_index] = with_members(group, selection)
		ControlGroupGesture.REMOVE_FROM_GROUP:
			_control_groups[a_index] = without_members(group, selection)
		ControlGroupGesture.RECALL:
			# An EMPTY group still clears the selection. Pressing a group is a statement about
			# what you want selected, and "nothing, yet" is an answer.
			deselect()
			_select_units(group)
		ControlGroupGesture.EXTEND_SELECTION:
			_select_units(group)
		ControlGroupGesture.REMOVE_FROM_SELECTION:
			# Edits the SELECTION, so no camera move: the player is narrowing what they already
			# have in hand, and nothing new has been picked to look at.
			for member: Variant in group:
				var commandable := member as Actor
				if commandable != null:
					remove_from_selection(commandable)
	# Only a double tap moves the camera: one press selects, the second of the same group goes
	# to look at it (selection-and-input.md §Control groups).
	var is_read: bool = (
		a_gesture == ControlGroupGesture.RECALL or a_gesture == ControlGroupGesture.EXTEND_SELECTION
	)
	var now_ms: int = Time.get_ticks_msec()
	if is_read and is_double_tap(_last_group_tap_index, _last_group_tap_ms, a_index, now_ms):
		_center_camera_on(group)
		_last_group_tap_index = -1
	else:
		_last_group_tap_index = a_index if is_read else -1
		_last_group_tap_ms = now_ms


## Whether a read of group `index` at `now_ms` pairs with the previous read (`last_index` at
## `last_ms`) as a double tap: the same group, within DOUBLE_CLICK_SECONDS.
static func is_double_tap(last_index: int, last_ms: int, index: int, now_ms: int) -> bool:
	return (
		last_index >= 0
		and last_index == index
		and now_ms - last_ms <= int(DOUBLE_CLICK_SECONDS * 1000.0)
	)


## Route a control-group key press. Mirrors _dispatch_command_hotkey: the action names the
## group, and the modifiers decide what happens to it.
func _dispatch_control_group(a_actions: Array) -> void:
	for action_name: String in a_actions:
		var index: int = control_group_index_from_action(action_name)
		if index < 0:
			continue
		run_control_group(index)
		return


#endregion

#region Camera follow
## Whether a selector may move the camera onto what it just picked.
##
## Every selector is GLOBAL now (see _run_selector), so a pick can be anywhere on the map —
## which makes this load-bearing rather than a convenience: selecting something you cannot
## see is worse than selecting nothing. WHEN_NEEDED is therefore the default, and NEVER is
## for players who want the camera under their own control alone.
##
## This is a PREFERENCE, not a mode: it changes how the interface always behaves rather than
## what the game will do this match, so it earns no HUD indicator.
## It has no persistent home yet — the project has no settings system (no ConfigFile, nothing
## under user://), so this is a runtime property waiting for one.
enum CameraFollow {
	## Move only when nothing selected is already visible.
	WHEN_NEEDED,
	## Never move the camera on a selection.
	NEVER,
}

var camera_follow_selection: CameraFollow = CameraFollow.WHEN_NEEDED


## Bring the camera to `a_commandables` if the player would otherwise have selected something
## off screen.
##
## The on-screen test that used to decide WHAT you select now decides whether the camera
## MOVES — same machinery (_selection_shape_in_view), better question. Anything already
## visible leaves the camera alone, so selecting a group you are looking at never jerks the
## view; only a pick you cannot see moves it.
##
## A bulk selection centres on the CENTROID. Known cost: an army split between two fronts
## centres on the empty ground between them. Cycling through subgroups is the feature that
## fixes that properly, and it does not exist yet.
func _look_at_selection(a_commandables: Array) -> void:
	if camera == null or a_commandables.is_empty():
		return
	if camera_follow_selection == CameraFollow.NEVER:
		return
	if not commandables_on_screen(a_commandables).is_empty():
		return
	_center_camera_on(a_commandables)


## Centre the camera on the live members of `a_commandables`, whatever is on screen.
func _center_camera_on(a_commandables: Array) -> void:
	if camera == null:
		return
	var centroid: Vector2 = Vector2.ZERO
	var counted: int = 0
	for node: Node in a_commandables:
		var c: Actor = node as Actor
		if c == null or not is_instance_valid(c):
			continue
		centroid += VU.in_xz(c.global_position)
		counted += 1
	if counted > 0:
		camera.center_on(centroid / float(counted))


#endregion


#region Screen queries
## Returns the subset of `commandables` that are currently on screen. A
## commandable is "on screen" when its selection shape is at all visible in the
## camera's orthographic view — i.e. the projected extent of its Selectable
## sphere overlaps the viewport rectangle (partially-visible units count).
func commandables_on_screen(a_commandables: Array) -> Array:
	if camera == null:
		return []
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return a_commandables.filter(
		func(c: Variant) -> bool:
			return c is Actor and _selection_shape_in_view(c as Actor, viewport_rect)
	)


## True when the commandable's selection shape projects onto `viewport_rect` at
## all (any overlap — a partially-visible shape still counts as on screen).
func _selection_shape_in_view(a_commandable: Actor, a_viewport_rect: Rect2) -> bool:
	if a_commandable == null or a_commandable.selectable == null:
		return false
	var shape_node: CollisionShape3D = _selection_shape_node(a_commandable.selectable)
	if shape_node == null:
		return false
	var center: Vector3 = shape_node.global_position
	# unproject_position is meaningless for points behind the lens; a shape there
	# is not on screen. (An overhead ortho RTS camera never puts field units
	# behind it, but guard anyway.)
	if camera.is_position_behind(center):
		return false

	# World radius of the selection sphere, scaled by the shape's world scale.
	# Non-sphere shapes fall back to a point test (radius 0).
	var world_radius: float = 0.0
	if shape_node.shape is SphereShape3D:
		world_radius = (
			(shape_node.shape as SphereShape3D).radius
			* shape_node.global_transform.basis.x.length()
		)

	# Screen-space radius: project a point one world-radius to the camera's right
	# and measure the pixel gap. This derives the on-screen size without assuming
	# the orthographic projection math directly.
	var center_screen: Vector2 = camera.unproject_position(center)
	var edge_screen: Vector2 = camera.unproject_position(
		center + camera.global_transform.basis.x.normalized() * world_radius
	)
	var screen_radius: float = center_screen.distance_to(edge_screen)

	var shape_rect: Rect2 = Rect2(
		center_screen - Vector2(screen_radius, screen_radius),
		Vector2(screen_radius, screen_radius) * 2.0
	)
	return a_viewport_rect.intersects(shape_rect)


## The CollisionShape3D defining a Selectable's selection area (its first
## CollisionShape3D child), or null.
func _selection_shape_node(a_selectable: Selectable) -> CollisionShape3D:
	for child: Node in a_selectable.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


#endregion


#region Command processing
## The control context(s) currently active for tool/command availability, as a
## ControlBinding.ControlContext bitmask: BUILD while the Build sub-menu is armed, otherwise
## the default ACT|TRAIN page. The single place that interprets the controller's
## mode (pending_command_name) as a ControlBinding.ControlContext — shared vocabulary with
## the Tool registry / command_context_parser.tools_for().
func current_context() -> int:
	if pending_command_name == "command_ability":
		return ControlBinding.ControlContext.BUILD
	return ControlBinding.ControlContext.ACT | ControlBinding.ControlContext.TRAIN


## The sanction whose CARGO MENU is open, or null. A sanction that offers payloads is armed
## in two steps exactly as Build is — the button drills into a list, the pick sets the tool,
## and the right-click delivers it — so the menu is "armed, with nothing chosen yet".
##
## Derived from the armed sanction rather than kept as a second flag: `_pending_sanction` is
## already the one statement of what is armed, and a parallel "menu is open" bool would be a
## second copy of it that could disagree.
func pending_payload_sanction() -> Sanction:
	if _pending_sanction == null or not _pending_sanction.takes_a_payload():
		return null
	return _pending_sanction if command_message.tool == null else null


## The armed sanction when it offers a cargo menu, chosen or not — null otherwise. The menu
## is drawn on both sides of the pick (the pick is a radio button), which is what separates
## this from pending_payload_sanction.
func _armed_cargo_sanction() -> Sanction:
	if _pending_sanction == null or not _pending_sanction.takes_a_payload():
		return null
	return _pending_sanction


## The cargo menu's buttons, as CargoSlotBinding command names — one per piece the armed level
## offers, in its authored order. Empty when no cargo sanction is armed.
func payload_menu_commands() -> Array:
	var sanction: Sanction = _armed_cargo_sanction()
	if sanction == null:
		return []
	var out: Array = []
	for slot: int in mini(sanction.payload_pieces().size(), CargoSlotBinding.all().size()):
		out.append(CargoSlotBinding.command_for_slot(slot))
	return out


## The piece cargo slot `a_slot` stands for under the armed sanction, or &"" when there is
## none.
func cargo_piece_in_slot(a_slot: int) -> StringName:
	var sanction: Sanction = _armed_cargo_sanction()
	if sanction == null or a_slot < 0:
		return &""
	var pieces: Array[StringName] = sanction.payload_pieces()
	return pieces[a_slot] if a_slot < pieces.size() else &""


## Pick the cargo in `a_slot`: the chosen piece becomes the message's tool, which is what
## UseSanction delivers. Re-pickable while armed — the menu stays up.
func choose_cargo(a_slot: int) -> void:
	var tool: Tool = Tool.for_id(cargo_piece_in_slot(a_slot))
	if tool == null:
		return
	command_message.tool = tool
	upate_hud_buttons()


## The cargo slot whose piece is chosen, as its command name, or "" when none is.
func _chosen_cargo_command() -> String:
	if _armed_cargo_sanction() == null or command_message.tool == null:
		return ""
	var chosen: StringName = command_message.tool.type
	for command: String in payload_menu_commands():
		if cargo_piece_in_slot(CargoSlotBinding.slot_of(command)) == chosen:
			return command
	return ""


## Whether `command_name` is a unit command the current selection can act on right
## now — the gate shared by button visibility, the hotkey dispatcher, and
## process_command itself. False when nothing is selected, and false for
## SELECT-context commands (idle army, etc.), which the dispatcher routes
## separately and which are never gated by the selection.
##
## Gate on _available_commands (the union across the whole selection) rather than
## re-checking selection[0] alone, so a hotkey works whenever its button is shown.
## Build tools (command_tool_dwelling, ...) are the exception: they aren't part of
## a unit's base command set, so they only qualify once the Build sub-menu is armed
## (current_context() == BUILD) and only for structures SOME selected unit can place —
## the same union rule, for the same reason (see CommandContextParser.tools_for_selection).
func _command_is_available(a_command_name: String) -> bool:
	# Cancel is offered by the CONTROLLER's state, not by the selection's capabilities — it is
	# drawn exactly when there is something armed to put down, and an empty selection is a
	# state you can still be armed in (a commander-card ordnance). ARMED, not answered: a
	# player half-way through choosing a structure needs the way out as much as one holding a
	# finished order, and needing to finish choosing before you may cancel is absurd.
	if a_command_name == CANCEL_COMMAND:
		return is_command_armed()
	if selection.is_empty():
		return false
	if _available_commands.has(a_command_name):
		# On the card the player can see, or not at all. Pressing the key for a cell that is
		# showing something else must not reach past it to a command the grid is not offering
		# — the HUD is the statement of what is available, and a hotkey that outruns it is a
		# rule with no way to learn it.
		return _command_is_on_current_card(a_command_name)
	if payload_menu_commands().has(a_command_name):
		return true
	return (
		current_context() == ControlBinding.ControlContext.BUILD
		and (
			CommandContextParser
			. tools_for_selection(selection, ControlBinding.ControlContext.BUILD)
			. has(a_command_name)
		)
	)


## Runs the "command_" input action a key press triggered.
##
## Grid keys are POSITIONAL: an action names a CELL, and what it does is whatever that cell
## is drawing (visible_command_in_cell). So one key means different things on the two cards
## — A is attack-move on the ACTIVE card and trains the first unit on the PRODUCTION one —
## and neither the family gate nor the availability gate needs restating on the input side,
## because a key that resolves to no button does nothing.
##
## Selectors keep NAMED actions (F1/F2/F3): they change the selection rather than acting on
## it, so they have no cell and are deliberately off the grid's key space entirely.
##
## The loop still walks the set because one key CAN in principle carry two actions; nothing
## in the current bindings does.
func _dispatch_command_hotkey(a_command_actions: Array) -> void:
	for action_name: String in a_command_actions:
		if _select_command_handlers.has(action_name):
			_select_command_handlers[action_name].call()
			return
		var cell: Vector2i = ControlBinding.position_from_action(action_name)
		if cell.x < 0:
			continue
		var command_name: String = visible_command_in_cell(cell)
		if command_name == "":
			continue
		# A key runs what its cell's BUTTON would, by the same route as the click — so a cell
		# whose button is not an order (a producer's context button) works from its key too,
		# rather than being dropped by the order-availability gate below.
		if (
			command_name.begins_with(ProducerContextBinding.PREFIX)
			or CargoSlotBinding.slot_of(command_name) >= 0
		):
			_on_control_button_pressed(command_name)
			return
		if _command_is_available(command_name):
			process_command(command_name)
			return


func process_command(a_command_name: String) -> void:
	# A press on the COMMANDER's card finds its own casters and arms the ability, exactly as the
	# ordnance bar's buttons do — the player has not selected anything, and being made to hunt
	# for the Operations Center first is the thing that card exists to remove. Placed above the
	# availability gate because that gate asks whether the SELECTION offers the command, which
	# is not the question here.
	if _command_family == ControlBinding.CommandFamily.ORDNANCE and not _finding_casters:
		var ability_id: StringName = ordnance_ability_for(a_command_name)
		if ability_id != &"":
			_finding_casters = true
			_on_deploy_button_pressed(ability_id)
			_finding_casters = false
			return
	if not _command_is_available(a_command_name):
		return

	# Re-stamp rather than trusting _process's write: a train tool fires straight from here
	# on the button press, and this is a POLLED read — the modifier keydown that preceded
	# the click went to the focused Control, so _process's frame may have missed it.
	command_message.defer_if_unaffordable = _purchase_defers()

	if a_command_name == CANCEL_COMMAND:
		disarm_command()
		return
	# A flag, not a command: plainly it flips now; additive, it waits its turn (SetHoldFire).
	if a_command_name == CommandContextParser.HOLD_FIRE_COMMAND:
		_submit_hold_fire()
		return

	var tool: Tool = Tool.for_name(a_command_name)
	if tool != null:
		# Pressing the armed piece again is a choice of ITS next form, not a new order: nothing is
		# issued or queued (whatever the additive modifier says), and the ghost, overlay, prices
		# and banner follow the tool the next frame.
		if _is_variant_cycle_press(tool):
			command_message.tool = command_message.tool.next_variant()
			upate_hud_buttons()
			return
		command_message.tool = tool
	elif a_command_name.begins_with("command"):
		# Hotkey commands either fire immediately (no position needed, e.g.
		# command_stop) or arm a pending sub-mode that the next right-click
		# resolves (e.g. command_attack_move → Attack/AttackMove on click).
		pending_command_name = a_command_name
	else:
		push_error("trying to process unknown action type: %s" % a_command_name)
		return

	# Resolved across the selection, not off its lead: picking a train tool with a soldier
	# first in the selection and a barracks behind it must still resolve Train (the soldier
	# has no Production and would have resolved a plain move, swallowing the order).
	var command: Variant = resolve_command_class_for_selection(
		pending_command_name, selection, command_message
	)

	if command != null and not command.requires_position():
		assign_command_to_units(command, command_message, additive_latched)

	upate_hud_buttons()


## Whether pressing `a_tool` now means "the next form of what is armed": that very piece is
## already armed, bound to one of its variants. A piece without variants is never bound, so
## re-pressing it stays the plain re-arm it always was.
func _is_variant_cycle_press(a_tool: Tool) -> bool:
	var armed: Tool = command_message.tool if command_message != null else null
	return armed != null and armed.is_variant_bound() and armed.type == a_tool.type


## Toggle `commander`'s automatic use of `a_ability_id` — the right-click on its command-card
## button and on its HUD-bar button alike, which is why the setting is the commander's.
func _toggle_autocast(a_ability_id: StringName, a_commander: Commander) -> void:
	if a_commander == null:
		return
	if _order_stream() == null:
		a_commander.toggle_autocast(a_ability_id)
		upate_hud_buttons()
		return
	_order_stream().submit(
		PlayerOrder.new(
			PlayerOrder.Kind.AUTOCAST, a_commander.id, {"ability": String(a_ability_id)}
		)
	)


## Hand the hold-fire toggle over the selection to the simulation, or apply it at once with no
## stream (a bare controller in a test). Plainly it flips a flag and leaves every queue as it was;
## with the additive modifier it waits its turn in each queue (SetHoldFire).
func _submit_hold_fire() -> void:
	if _order_stream() == null:
		OrderDispatcher.hold_fire(selection, additive_modifier_held(), map)
		upate_hud_buttons()
		return
	var commander: Commander = _commander()
	_order_stream().submit(
		PlayerOrder.new(
			PlayerOrder.Kind.HOLD_FIRE,
			commander.id if commander != null else 0,
			{"actors": PlayerOrder.serials_of(selection), "queue": additive_modifier_held()}
		)
	)


## Hotkey name -> the command class arming it selects, for every sub-mode whose answer is
## the same whatever the cursor is over. Two hotkeys are deliberately absent because a name
## alone cannot express them — see _resolve_hotkey_command.
##
## `command_ability` arms Build: an ability placed as a structure goes down the construction
## path, tool and all.
##
## A `static var` rather than a `const` only because a class reference is not a constant
## expression in GDScript. It is read-only authored data all the same — never written after
## this line.
static var HOTKEY_COMMANDS: Dictionary = {
	"command_stop": Stop,
	"command_move": MoveCommand,
	"command_focus_fire": FocusFire,
	"command_patrol": Patrol,
	"command_defend": Defend,
	"command_ability": Build,
	"command_spot": Spot,
	"command_plant": Plant,
	"command_detonate": Detonate,
	"command_bombard": Bombard,
	"command_evacuate": Evacuate,
	# Armed deliberately from the card's H cell as well as reached by right-clicking a
	# damaged friendly. The precondition is the same either way (Repair.repairable_cause),
	# so arming it cannot get a repairer onto a target the right-click would have refused.
	"command_repair": Repair,
	"command_deploy": Deploy,
	"command_undeploy": Undeploy,
	"command_land": Land,
	"command_rearm": Rearm,
}

## The ability `command_launch` arms. Named here rather than written into the hotkey table
## because the id goes on the MESSAGE, not on the returned class.
const LAUNCH_ABILITY: StringName = &"irradiate"

## The branches that ask their own command class whether the order would hold, in the order
## they are asked. Each is checked with `X.meets_precondition(...) == NONE`.
##
## NOTHING RESTATES A RULE HERE, and the order is load-bearing — Repair above Occupy so a
## burning transport is mended rather than boarded, Rearm above Occupy so an aircraft
## clicking its airfield reloads, Embark directly below Occupy. Why each, and what a
## restated rule cost last time: gdd/systems/commands/the-click-ladder.md §The default
## ladder.
##
## `static var` for the same reason HOTKEY_COMMANDS is: a class reference cannot appear in
## a const. Never written after this line.
##
## TaskShelter sits last: its target (a Shelter, no Garrison/Defense of its own) never
## overlaps what any other branch here matches, so its position among them is arbitrary.
static var DELEGATED_BRANCHES: Array = [Repair, Rearm, Occupy, Embark, TaskShelter]


## Picks the concrete Command Script class to instantiate given the controller state, for
## ONE actor. Null means "no valid command right now", which the caller draws as an invalid
## cursor and acts on not at all.
##
## Two questions in order: is a sub-mode armed (the hotkey table), and otherwise what is
## under the cursor (the default ladder). The full ladder, and the reasoning behind its
## order, is gdd/systems/commands/the-click-ladder.md.
static func _resolve_command_class(
	pending: String, actor: Entity, message: CommandMessage
) -> Variant:
	if actor == null:
		return null
	var armed: Variant = _resolve_hotkey_command(pending, message)
	return armed if armed != null else _resolve_target_command(actor, message)


## The class an armed sub-mode selects, or null when no hotkey is armed and the default
## ladder should answer instead. Falling through is also right for `command_tool_*` and the
## other aliases, where a producer holding a tool picks Train.
static func _resolve_hotkey_command(pending: String, message: CommandMessage) -> Variant:
	# TARGET-SENSITIVE: an attack-move onto something attackable is simply an attack.
	if pending == "command_attack_move":
		return (
			Attack
			if message.target is Entity and (message.target as Entity).is_attackable()
			else AttackMove
		)
	# WRITES TO THE MESSAGE, which is why it cannot be a table row: Ability resolves its
	# payload and its charges from the id carried there. (Map further hotkeys to their
	# ability ids here as abilities are added.)
	if pending == "command_launch":
		message.ability_type = LAUNCH_ABILITY
		return Ability
	return HOTKEY_COMMANDS.get(pending)


## The default ladder: no sub-mode armed, so the actor's capabilities and whatever is under
## the cursor decide. Ends in a plain MoveCommand, which stationary can_rally() hosts read
## as a rally point (see Actor._process_commands).
static func _resolve_target_command(actor: Entity, message: CommandMessage) -> Variant:
	var target: Variant = message.target
	var actor_cmd := actor as Actor

	# A producer with a tool selected is deliberately training.
	if actor.has_node("Production") and message.tool != null:
		return Train

	# An interactor-equipped unit targeting an entity it has an interaction for. This
	# generalises the former per-type special cases (technician -> Star PickUp, technician ->
	# Outpost DropOff, vanguard -> Lab collect): what a unit can interact with lives in its
	# Interactor's list, and the Interact precondition gates on encampment availability.
	if (
		actor_cmd != null
		and actor_cmd.interactor != null
		and target is Entity
		and actor_cmd.interactor.can_interact(actor_cmd, message)
	):
		return Interact

	# Builder targeting a friendly under-construction structure -> resume construction. The
	# click is unambiguous (same-commander, not-yet-built, actor can build that type), so it
	# short-circuits ahead of the generic fallthrough.
	var target_cmd := target as Actor
	if (
		target_cmd != null
		and target_cmd.commander_id == actor.commander_id
		and not target_cmd.is_built
		and actor.has_node("Builds")
		and (actor.get_node("Builds") as Builds).can_build(target.id)
	):
		return Assemble

	if actor_cmd != null:
		for branch: Variant in DELEGATED_BRANCHES:
			if (
				branch.meets_precondition(actor_cmd, message)
				== MoveCommand.PreconditionFailureCause.NONE
			):
				return branch

	# Hostile, weapon-matched target. Above the rally fallback so a combatant structure whose
	# can_rally() would otherwise swallow the click still takes an explicit attack order.
	if (
		target is Entity
		and (target as Entity).is_attackable()
		and actor.is_enemy_of(target)
		and actor.weapon_inventory != null
		and actor.weapon_inventory.weapon_for_target(target) != null
	):
		return Attack

	return MoveCommand


## The command class to arm for a whole SELECTION, which is what the player actually has
## in hand — _resolve_command_class answers for ONE actor, and a mixed selection has no
## single actor to speak for it.
##
## Each selected unit resolves the click through its own capabilities, and the most
## specific class any unit can ACTUALLY EXECUTE wins (see _command_specificity). Only a
## unit whose precondition passes gets a vote, so a click is read by the units that can
## carry it out rather than by whoever happens to sit at selection[0]: an infantryman and
## a supply truck right-clicking an enemy is an Attack, and so is a ground soldier and an
## air-capable Warlord right-clicking a helicopter — in both cases the unit that can't
## shoot that target simply doesn't receive the order (see assign_command_to_units).
##
## Falls back to the LEAD unit's resolution when no unit can execute anything, so the
## cursor and the error line still name a concrete reason instead of going blank.
static func resolve_command_class_for_selection(
	pending: String, selection: Array, message: CommandMessage
) -> Variant:
	var best: Variant = null
	var best_rank: int = 0x7FFFFFFF
	var lead_resolution: Variant = null
	for node: Node in selection:
		var actor := node as Actor
		if actor == null or not is_instance_valid(actor):
			continue
		var resolved: Variant = _resolve_command_class(pending, actor, message)
		if resolved == null:
			continue
		if lead_resolution == null:
			lead_resolution = resolved
		if not _can_execute(resolved, actor, message):
			continue
		var rank: int = _command_specificity(resolved)
		if rank < best_rank:
			best = resolved
			best_rank = rank
	return best if best != null else lead_resolution


## How specific a resolved command class is for the purpose of settling a MIXED selection:
## LOWER wins. It only ever decides between DIFFERENT classes resolved by different units,
## so a homogeneous selection (and a single unit) is unaffected by this order entirely —
## a lone truck still deposits its prisoners, a lone technician still plants.
##
## Ordered as the per-actor ladder in _resolve_command_class is, with one deliberate
## inversion: Attack outranks Interact. In a mixed group, right-clicking an enemy means
## "kill it" — a truck's deposit or a technician's demolition charge must not become the
## whole group's order and leave the shooters idle. Select the specialist on its own to get
## its specialty. MoveCommand is the floor: it is what the ladder falls to when nothing
## more specific applied, so anything else outranks it.
##
## Classes not named here — every pending-hotkey command (Stop, Patrol, AttackMove, …),
## which every unit in a selection resolves identically anyway — sit just above the floor,
## so they still beat a plain move without having to be enumerated.
static func _command_specificity(command_type: Script) -> int:
	if command_type == Train:
		return 0
	if command_type == Assemble:
		return 1
	# Directly below Assemble, though the two can't currently both resolve for one target:
	# Assemble's branch requires an UNFINISHED structure and Repair's refuses one. The rank
	# states the intent anyway — if repairing an unfinished structure ever becomes legal,
	# a mixed builder/repairer group clicking a site should finish it, not patch it.
	if command_type == Repair:
		return 2
	# Directly above Occupy, matching the ladder: an airfield that also garrisons is read as
	# an airfield by the aircraft that can dock there.
	if command_type == Rearm:
		return 3
	if command_type == Occupy:
		return 4
	# The same rank as Occupy on purpose: they are one mechanic seen from its two ends, and
	# a tie is resolved by whichever the selection resolved first — which, given the ladder
	# order, is Occupy. Nothing else in a mixed selection should have to rank against them
	# separately.
	if command_type == Embark:
		return 4
	if command_type == Attack:
		return 5
	if command_type == Interact:
		return 6
	if command_type == MoveCommand:
		return 8
	return 7


## Whether `a_actor` could carry out `a_command_type` right now. COMMAND_PENDING_TOOL
## counts: it means "armed, waiting on the player's tool pick", not a failure (see
## MoveCommand.PreconditionFailureCause).
static func _can_execute(command_type: Script, actor: Actor, message: CommandMessage) -> bool:
	var cause: MoveCommand.PreconditionFailureCause = command_type.meets_precondition(
		actor, message
	)
	return (
		cause == MoveCommand.PreconditionFailureCause.NONE
		or cause == MoveCommand.PreconditionFailureCause.COMMAND_PENDING_TOOL
	)


## The failure cause to SHOW for the current selection (cursor + error line): the command
## is issuable, and so reads as valid, as soon as ANY selected unit can execute it — the
## incapable ones are skipped at issue time rather than blocking the order. Only when
## nobody can act do we surface a real cause, taken from the lead unit so the message
## names something concrete.
static func selection_precondition(
	command_type: Script, selection: Array, message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	if command_type == null or selection.is_empty():
		return MoveCommand.PreconditionFailureCause.NONE
	var lead_cause: MoveCommand.PreconditionFailureCause = (
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)
	var have_lead: bool = false
	for node: Node in selection:
		var actor := node as Actor
		if actor == null or not is_instance_valid(actor):
			continue
		var cause: MoveCommand.PreconditionFailureCause = command_type.meets_precondition(
			actor, message
		)
		if (
			cause == MoveCommand.PreconditionFailureCause.NONE
			or cause == MoveCommand.PreconditionFailureCause.COMMAND_PENDING_TOOL
		):
			return cause
		if not have_lead:
			lead_cause = cause
			have_lead = true
	return lead_cause


## The narrowed actor for an order going out right now — the preview's question, answered by
## the dispatcher's rule with the modifiers held. Why it is the NEAREST FREE one:
## gdd/systems/ux/ui/selection-and-input.md §The narrow modifier picks the nearest IDLE actor.
func _narrowed_actors(a_command_type: Script, a_actors: Array, a_message: CommandMessage) -> Array:
	return OrderDispatcher.narrowed(
		a_command_type,
		a_actors,
		a_message,
		cast_arity_for(a_command_type, a_message),
		not Input.is_action_pressed(MODIFIER_BROADEN)
	)


## How many actors an order for `a_command_type` goes to right now, modifiers included.
##
## NARROW IS CHECKED FIRST, so holding both keys still narrows — and broaden then keeps the
## meaning it already had in that pair, dropping the idle preference so the NEAREST actor is
## taken rather than the nearest idle one (see the §narrow modifier note). That composition
## predates arity and is worth keeping: it is the only way to say "that one, right there".
##
## Public, and takes the message, because the aiming preview asks the same question to decide
## how many casters' ranges to draw — the ring the player sees and the actors that fire have
## to be the same answer.
func cast_arity_for(a_command_type: Script, a_message: CommandMessage) -> MoveCommand.CastArity:
	if a_command_type == null:
		return MoveCommand.CastArity.ALL
	return modified_arity(a_command_type.default_cast_arity(a_message))


## Apply the modifiers held now to a default — OrderDispatcher.modified_arity, the ONE statement
## of the rule, so the actors that receive an order and the rings the preview draws agree.
func modified_arity(a_default: MoveCommand.CastArity) -> MoveCommand.CastArity:
	return OrderDispatcher.modified_arity(
		a_default,
		Input.is_action_pressed(MODIFIER_NARROW),
		Input.is_action_pressed(MODIFIER_BROADEN)
	)


## The arity the currently ARMED ability would be cast at.
##
## Asked of the ability directly rather than through a command class, because the preview
## runs before the click that resolves one — and every route to an armed ability
## (`armed_ability_id`) ends in the same authored `cast_by:`.
func armed_cast_arity() -> MoveCommand.CastArity:
	return modified_arity(AbilityCatalog.cast_arity_of(armed_ability_id()))


## Issue `a_command_type` to the selection as one order. The order is built here from the
## selection and the modifiers held, and APPLIED by OrderDispatcher — at the start of the next tick
## through the scenario's OrderStream, or at once where there is none (a bare controller in a
## test). Returns whether any selected actor takes it, by the same rule the dispatcher applies.
## gdd/systems/commands/recording-and-replay.md §The order stream.
func assign_command_to_units(
	a_command_type: Script, a_command_message: CommandMessage, a_add_to_queue: bool
) -> bool:
	selection = selection.filter(func(u): return is_instance_valid(u))
	if selection.size() == 0:
		push_error("no selections")
		_reset_pending_state()
		return false
	if a_command_type == null:
		push_error("supplied a null command")
		_reset_pending_state()
		return false

	if is_look_only:
		_reset_pending_state()
		return false
	var modifiers: Dictionary = _order_modifiers(a_command_type, a_add_to_queue)
	var capable: Array = OrderDispatcher.recipients(
		a_command_type, selection, a_command_message, modifiers
	)
	if capable.is_empty():
		_reset_pending_state()
		return false
	command_issued.emit(capable[0] as Entity, a_command_type)
	_submit_command(a_command_type, a_command_message, modifiers, capable[0] as Entity)

	if _arming_should_end(a_command_type, a_add_to_queue):
		_reset_pending_state()
		command_message.clear()
	return true


## The modifiers an order carries as data, read now: the additive one, narrow and broaden, the
## purchase-standing one-shot (Train only, which is what consumes it), and the line being drawn.
func _order_modifiers(a_command_type: Script, a_add_to_queue: bool) -> Dictionary:
	return {
		"queue": a_add_to_queue,
		"narrow": Input.is_action_pressed(MODIFIER_NARROW),
		"broaden": Input.is_action_pressed(MODIFIER_BROADEN),
		"standing": _take_purchase_standing() if a_command_type == Train else false,
		"line": [_line_start.x, _line_start.y, _line_end.x, _line_end.y] if _line_issuing else [],
	}


## Hand a command to the simulation: as an order on the scenario's stream, or — with no stream —
## applied at once. The message is copied either way: `a_message` is usually the controller's own
## long-lived `command_message`, which is cleared and reused for the next click.
func _submit_command(
	a_command_type: Script, a_message: CommandMessage, a_modifiers: Dictionary, a_lead: Entity
) -> void:
	var stream: OrderStream = _order_stream()
	if stream == null:
		var indicated: Array[CommandMessage] = OrderDispatcher.apply_command(
			map,
			a_command_type,
			selection.duplicate(),
			CommandMessage.deep_copy(a_message),
			a_modifiers
		)
		for snapshot: CommandMessage in indicated:
			_register_indicator(snapshot)
		return
	var commander: Commander = _commander() if _commander() != null else a_lead.commander
	stream.submit(
		PlayerOrder.command(commander.id, a_command_type, selection, a_message, a_modifiers)
	)


func _order_stream() -> OrderStream:
	return _scenario.order_stream if _scenario != null else null


## An order this controller's player gave has been applied: show its waypoints, and refresh the
## card for a toggle, whose state only changes now.
func _on_order_applied(a_order: PlayerOrder, a_results: Array) -> void:
	var commander: Commander = _commander()
	if commander == null or a_order.commander_id != commander.id:
		return
	match a_order.kind:
		PlayerOrder.Kind.COMMAND, PlayerOrder.Kind.PENDING_COMMAND:
			for snapshot: CommandMessage in a_results:
				_register_indicator(snapshot)
		PlayerOrder.Kind.DROP:
			_select_landed(a_results, bool(a_order.data.get("queue", false)))
			upate_hud_buttons()
		_:
			upate_hud_buttons()


## Issue the player's currently-armed right-click action at a world XZ position,
## as if they had right-clicked that point in the 3D world — but resolving a
## POSITION only, never an entity target. This is the minimap's right-click entry
## point: the minimap knows where on the map was clicked, not which unit sits
## there, so target is left null.
##
## Because target is null, _resolve_command_class only ever yields position-based
## commands (Move, AttackMove, Ability, ...); the target-requiring branches
## (Interact, Occupy, Assemble, Repair, Attack-on-unit) all fall through to null or resolve
## to something that fails requires_position(). Either way we bail without
## touching the armed context, so a right-click over the minimap while an
## interact-style command is armed is simply ignored — exactly as specified.
func issue_command_at_world_position(a_world_xz: Vector2) -> void:
	if map == null or is_look_only:
		return
	# An armed sanction targets a position — fire it at the clicked point, matching
	# the "move" right-click handler in _unhandled_input.
	if _pending_sanction != null:
		# A click on the minimap names no unit, so a single-unit cast has nothing to act on.
		if armed_targets_one_unit():
			return
		command_message.world_position = _world_point(a_world_xz)
		_activate_pending_sanction()
		return

	# Only the player's own units take commands; an enemy/neutral info-selection
	# (or an empty selection) ignores the click.
	if not _selection_owned_by_player():
		return

	var msg: CommandMessage = CommandMessage.new(map)
	msg.world_position = _world_point(a_world_xz)
	msg.tool = command_message.tool
	msg.ability_type = command_message.ability_type
	# A FRESH message defaults to deferring (that default serves scenario events and the
	# bot). This one is a player order, so it carries what the player is actually holding —
	# without this a build issued here would queue an unaffordable purchase with no modifier
	# down, which is exactly what the modifier exists to gate.
	msg.defer_if_unaffordable = _purchase_defers()

	var command: Variant = resolve_command_class_for_selection(pending_command_name, selection, msg)
	# Drop anything that isn't a pure position command: null (nothing resolved),
	# or a command that needs a specific entity target (requires_position() == false,
	# e.g. Stop/Occupy/Interact). The armed context is preserved untouched.
	if command == null or not command.requires_position():
		return
	assign_command_to_units(command, msg, additive_latched)


## World point at `world_xz`, lifted onto the terrain so waypoint indicators and
## any Y-sensitive consumers sit at the ground height rather than Y=0.
func _world_point(a_world_xz: Vector2) -> Vector3:
	var p: Vector3 = VU.from_xz(a_world_xz)
	p.y = map.terrain_height_at(a_world_xz)
	return p


## Whether issuing `a_command_type` should put the armed sub-mode and tool DOWN.
##
## Normally yes, unless the additive modifier is held — holding it is also what keeps a tool
## armed for the next placement, so five sites can be laid out with five clicks.
##
## **But only a command that WAITS FOR A CLICK has anything to stay armed for.** One that
## fires the moment it is pressed (Stop, Evacuate, Train — `requires_position()` false) has
## already done everything it is going to do, so leaving it armed leaves the controller in a
## sub-mode the player has no way to spend and did not ask for: the next right-click would
## re-fire it instead of resolving normally. Additive on such a command means only "append to
## the queue", which is what it already did before reaching here.
func _arming_should_end(a_command_type: Script, a_add_to_queue: bool) -> bool:
	return not a_add_to_queue or not a_command_type.requires_position()


## After a command fires (or fails preconditions), drop the controller out of
## any armed sub-mode and refresh the available-commands snapshot. Mirrors
## the old "reset active_command_context to the default for the selection"
## bookkeeping that lived inline at every exit path.
func _reset_pending_state() -> void:
	pending_command_name = ""
	available_commands = CommandContextParser.commands_for_selection(selection)


#region Pending selection
## Select the queue entries `a_transactions`, so the next command is aimed at the units they
## will produce rather than at anything on the map.
##
## **THE LIVE SELECTION IS LEFT ALONE**, and that is load-bearing rather than lax. A phantom is
## reached through a card that is only drawn while its PRODUCER (or its garrison host) is
## selected — so dropping the live selection destroys the card the player just clicked, empties
## the panel, and leaves no sign anything was selected at all. It read exactly like a dead
## button.
##
## The two channels can both be held because the command path is not ambiguous about them:
## `_unhandled_input` prefers `pending_selection` when it is non-empty, which is what the
## player asked for by clicking a phantom's card. Selecting anything LIVE clears the phantoms
## again (see clear_pending_selection), so there is a plain way back.
##
## `a_additive` adds to the pending selection, matching what the modifier means everywhere
## else. Entries that are no longer orderable — cancelled, or already built — are dropped
## rather than selected, so a card the panel has not yet rebuilt cannot select a dead phantom.
func select_pending(a_transactions: Array, a_additive: bool) -> void:
	if not a_additive:
		pending_selection.clear()
	for entry: Variant in a_transactions:
		var transaction := entry as PurchaseTransaction
		if (
			transaction != null
			and transaction.awaits_its_unit()
			and not pending_selection.has(transaction)
		):
			pending_selection.append(transaction)
	upate_hud_buttons()


## Drop the pending selection. Called whenever a LIVE selection is made, so the two channels
## can never both be held — see the field's own note.
func clear_pending_selection() -> void:
	if pending_selection.is_empty():
		return
	pending_selection.clear()
	upate_hud_buttons()


## Whether the pending entry `a_transaction` is currently selected. Read by the rail so a
## selected card can say so.
func is_pending_selected(a_transaction: PurchaseTransaction) -> bool:
	return a_transaction != null and pending_selection.has(a_transaction)


## Aim the armed order at every selected PENDING unit, and report whether anything took it.
##
## The order is STORED, not executed: there is nothing to execute it. `a_add_to_queue` appends
## rather than replacing, exactly as it does for a live unit, so a phantom can be given a
## chain of orders before it exists.
##
## One command instance per transaction, each with its own deep-copied message — the same rule
## live orders follow, and for the same reason: two units sharing a command instance trade
## destinations through it.
func assign_command_to_pending(
	a_command_type: Script, a_command_message: CommandMessage, a_add_to_queue: bool
) -> bool:
	var command_type: Script = a_command_type if a_command_type != null else MoveCommand
	# A purchase stops being orderable once its unit exists (or never will); it is dropped from
	# the selection rather than given an order that would silently never arrive.
	for transaction: PurchaseTransaction in pending_selection.duplicate():
		if not transaction.awaits_its_unit():
			pending_selection.erase(transaction)
	var ordered: bool = not pending_selection.is_empty()
	var stream: OrderStream = _order_stream()
	if ordered and stream == null:
		for snapshot: CommandMessage in OrderDispatcher.apply_pending_command(
			map,
			command_type,
			pending_selection,
			CommandMessage.deep_copy(a_command_message),
			a_add_to_queue
		):
			_register_indicator(snapshot)
	elif ordered:
		var owner: Commander = (pending_selection[0] as PurchaseTransaction).commander
		var order := PlayerOrder.new(
			PlayerOrder.Kind.PENDING_COMMAND,
			_commander().id,
			{
				"owner": owner.id,
				"purchases":
				pending_selection.map(func(t: PurchaseTransaction) -> int: return t.id),
				"command": command_type.resource_path,
				"queue": a_add_to_queue,
				"message": PlayerOrder.message_to_dict(a_command_message),
			}
		)
		stream.submit(order)
	if not a_add_to_queue:
		_reset_pending_state()
	return ordered


#endregion


## Whether the controller is holding an order waiting for a click to land it — a sub-mode, an
## armed sanction, or a chosen tool — as against the DEFAULT state, where a right-click reads
## its order off whatever is under the cursor.
##
## The distinction the whole card state machine turns on: armed, the next click delivers a
## thing the player has already named; unarmed, the click is the question and the answer both.
## `command_message` is @onready, so it is null on a controller that was never put in a tree
## — which is how most of this file's rules are tested. Guarded rather than asserted: "nothing
## armed" is the honest answer for a controller with no message to arm anything on.
func is_command_armed() -> bool:
	return (
		pending_command_name != ""
		or _pending_sanction != null
		or (command_message != null and command_message.tool != null)
		or is_debug_piece_armed()
		or is_drop_armed()
	)


## Whether the armed order has nothing left to ask for — a tool is chosen, or the order takes
## no tool at all. This is the card's READY state; while it is false the card is still a menu
## (the builder's structure list, a sanction's cargo menu) and the player is mid-answer.
func is_command_ready() -> bool:
	if not is_command_armed():
		return false
	if command_message != null and command_message.tool != null:
		return true
	return (
		current_context() != ControlBinding.ControlContext.BUILD
		and payload_menu_commands().is_empty()
	)


## Put every armed thing down: the sub-mode, the tool and the sanction, in one call.
##
## THE ONE STATEMENT OF WHAT "CANCEL" MEANS, so the left click, the Cancel card and its N key
## cannot come to disagree about it. It deliberately does not touch the selection — cancelling
## an order is not a statement about what you have selected.
func disarm_command() -> void:
	pending_command_name = ""
	_pending_sanction = null
	disarm_debug_piece()
	disarm_drop()
	# Nothing is built: a placement press still down when this happens ends with nothing issued
	# (the release finds _placing false), and the next tool starts unturned.
	_placing = false
	placement_quarter_turns = 0
	if command_message != null:
		command_message.tool = null
	available_commands = CommandContextParser.commands_for_selection(selection)
	upate_hud_buttons()


#endregion


#region HUD
## The command whose button is drawn in [a_cell] right now, or "" if the cell is empty.
##
## THE single statement of what the grid is showing — both the buttons and the keyboard read
## it, because a grid hotkey names a CELL rather than a command, so the key and the button it
## fires cannot disagree. At most one button per cell is ever shown; two bindings wanting one
## cell is a collision (ControlBinding.grid_collisions) and the first in
## CommandGrid.bindings() order takes it. Why keying is positional:
## gdd/systems/ux/ui/command-card-and-hotkeys.md.
func visible_command_in_cell(a_cell: Vector2i) -> String:
	var visible_names: Array = _visible_command_names()
	if visible_names.is_empty():
		return ""
	for binding: ControlBinding in CommandGrid.bindings():
		if (
			binding.grid_position == a_cell
			and (binding.family & _command_family) != 0
			and visible_names.has(binding.command_name)
		):
			return binding.command_name
	return ""


func upate_hud_buttons() -> void:
	# Here rather than only at the two family writers: the READY state is a card change the
	# player can cause without touching a card key at all (arming an order, or cancelling one),
	# and a banner that tracked only the family would go stale exactly then.
	_announce_card()
	# Tolerates a controller with no grid under it, the way every other panel lookup here does
	# — a headless or HUD-less session (a test, a spectator) simply has no buttons to restyle.
	var grid: Node = get_node_or_null("CommandsSection/CommandsBorder/CommandsView")
	if grid == null:
		return
	var visible_names: Array = _visible_command_names()
	for child: CommandGrid.Cell in grid.get_children():
		var cell_taken: bool = false
		for subchild: Button in child.get_children():
			# The BUTTON's own family, not its command's: one command may be drawn on two cards
			# from two bindings, and only the one belonging to the card on show may appear.
			var on_this_card: bool = (
				(int(subchild.get_meta(CommandGrid.BUTTON_FAMILY_META, 0)) & _command_family) != 0
			)
			subchild.visible = not cell_taken and on_this_card and visible_names.has(subchild.name)
			if subchild.visible:
				cell_taken = true
				if CargoSlotBinding.slot_of(subchild.name) >= 0:
					_paint_cargo_button(subchild)
				_apply_button_availability(subchild)


## Draw cargo slot `a_button` as the piece it stands for under the armed sanction: the piece's
## picture and how many of it the transport carries. Painted on show rather than built once,
## because a slot means a different piece under each level.
func _paint_cargo_button(a_button: Button) -> void:
	var piece: StringName = cargo_piece_in_slot(CargoSlotBinding.slot_of(a_button.name))
	var tool: Tool = Tool.for_id(piece)
	if tool == null:
		return
	var count: int = _pending_sanction.count_of(piece)
	var icon: Texture2D = PieceIcons.for_id(piece)
	a_button.icon = icon
	a_button.expand_icon = icon != null
	a_button.text = "" if icon != null else tool.label
	var verbose := a_button as VerboseTooltipButton
	if verbose != null:
		verbose.show_count("×%d" % count)
		verbose.simple_tooltip = "Deliver %d × %s" % [count, tool.label]
		verbose.verbose_tooltip = (
			(
				"Load the transport with %d × %s, then click where it should drop them.\n"
				+ "The pick stays changeable until you click."
			)
			% [count, tool.label]
		)


#region Command-button availability
## WHY each visible grid button is dark, and what it draws — delegated whole to
## [CommandButtonState], which is the single vocabulary for it.
##
## It used to live here as two: a five-way per-blocker tint for purchases, and an on-or-grey
## pair for abilities. The same "you cannot do this" therefore looked different depending on
## which half of the grid it came from, and only purchases could say WHY. The classifier,
## its colours and the reasoning for both are in that class.
func _apply_button_availability(a_button: Button) -> void:
	# The card's one "you are here" control: the chosen cargo while a cargo menu is up (the
	# producer row is not drawn then), otherwise the producer on show.
	var current: String = _chosen_cargo_command()
	if current.is_empty():
		current = ProducerContextBinding.PREFIX + String(_producer_context)
	var state: CommandButtonState = CommandButtonState.of(
		a_button.name, selection, _selection_commander(), additive_modifier_held(), current
	)
	# The radio button for the producer on show is not pressable — there is nowhere for it to
	# go. Greying it without disabling it would say "you are here" and still accept the click.
	a_button.disabled = state.blocker == CommandButtonState.Blocker.CURRENT
	var verbose := a_button as VerboseTooltipButton
	if verbose != null:
		verbose.show_availability(state)
	else:
		a_button.modulate = state.tint()


## Restyle the visible buttons without recomputing which ones are visible. Availability
## tracks income and cooldowns, which change continuously with nothing to signal them — so
## this runs per frame from _process, where the rest of the live HUD refresh happens.
func _refresh_button_availability() -> void:
	for child: CommandGrid.Cell in $CommandsSection/CommandsBorder/CommandsView.get_children():
		for subchild: Button in child.get_children():
			if subchild.visible:
				_apply_button_availability(subchild)


#endregion


## The command names whose HUD buttons should be visible for the current state.
##
## Three layers, outermost first:
##   * nothing selected — nothing at all. The command grid is one of the two
##     SELECTION-OWNED panels and is hidden wholesale in that state; the selectors that
##     used to squat here are SelectorPanel now, which is persistent.
##   * "Build" armed (command_ability) — the builder's structure list, which takes over
##     the whole ACTIVE card. Issuing or re-selecting clears pending_command_name (via
##     _reset_pending_state / deselect) and drops back to the flat set.
##   * otherwise — the selection's available commands, NARROWED TO THE CARD ON SHOW. That
##     narrowing is what the two cards are: without it, a barracks' training buttons would
##     be drawn beside a soldier's attack-move, which is the pre-card behaviour where a
##     mixed selection filled empty cells with whatever else was to hand.
func _visible_command_names() -> Array:
	# BEFORE EVERYTHING, including the commander's card: once an order is armed, it has taken
	# the card over, and every other button on it is something the player would have to un-arm
	# to reach. What stays is the order's OWN menu — the builder's structure list, a sanction's
	# cargo — plus Cancel. See ui/control-matrices.md §Context 1a.
	#
	# THE MENU STAYS UP AFTER A PICK, which is the whole of this rule: choosing the wrong
	# structure used to leave the card holding one Cancel button, so changing your mind meant
	# cancelling and re-opening the list. The pick is a radio button, not a door.
	if is_command_armed():
		var armed: Array = armed_card_menu()
		armed.append(CANCEL_COMMAND)
		return armed
	# BEFORE the empty-selection guard: the commander's card is not about the selection, and
	# having nothing selected is the state it is normally read in.
	if _command_family == ControlBinding.CommandFamily.ORDNANCE:
		return ordnance_card_names()
	if selection.is_empty():
		return []
	# Nothing below here can be a build list or a cargo menu: both of those are states the
	# controller is ARMED in, and the branch above has already answered for them.
	var names: Array = _available_commands.filter(_command_is_on_current_card)
	if _command_family == ControlBinding.CommandFamily.PRODUCTION:
		names = _narrow_to_producer_context(names)
		names.append_array(producer_context_names())
	return names


## The MENU an armed order is still offering: the builder's structure list, or a sanction's
## cargo. Empty for an order that asks nothing (every plain verb), which is what makes that
## card one Cancel button.
##
## Drawn whether or not the player has already picked — the pick is a radio button and the
## card is how they change it — so this reads the CONTEXT rather than "is anything chosen".
func armed_card_menu() -> Array:
	var payload_menu: Array = payload_menu_commands()
	if not payload_menu.is_empty():
		return payload_menu
	if current_context() == ControlBinding.ControlContext.BUILD:
		return CommandContextParser.tools_for_selection(
			selection, ControlBinding.ControlContext.BUILD
		)
	return []


## Whether `a_command_name` belongs to the card currently on show. A command with no
## binding in the grid (command_move, command_attack — the ones resolved by right-clicking
## rather than pressed) has no button to draw and is filtered out here, exactly as it was
## before by having no cell to be placed in.
func _command_is_on_current_card(a_command_name: String) -> bool:
	return (CommandGrid.families_for(a_command_name) & _command_family) != 0


## Every ordnance the game has, always — the ORDNANCE card is the one place that draws a
## button for something the player cannot use yet.
##
## Everywhere else a button appears only when the current selection offers its command, which
## is right for an order: a card listing what this unit CANNOT do would be noise. The
## commander's card answers a different question — *what can I call in, and what would it take*
## — and a locked ordnance is part of that answer. It is drawn dark with the reason on it (see
## CommandButtonState: LOCKED for one never bought, NO_CASTER for one with nothing to cast it),
## which is the whole point of having per-blocker colours.
##
## ONE BUTTON PER ABILITY, not per level. A levelled sanction has a binding per level sharing a
## cell, and the one shown is the level the commander actually owns — falling back to the first
## when none is owned, so a locked family still has a face and a cell.
func ordnance_card_names() -> Array:
	var chosen: Dictionary = {}
	for binding: ControlBinding in CommandGrid.bindings():
		var ability := binding as AbilityBinding
		if ability == null or ability.family != ControlBinding.CommandFamily.ORDNANCE:
			continue
		if not _faction_offers_ordnance(ability.ability_id):
			continue
		if not chosen.has(ability.ability_id):
			chosen[ability.ability_id] = ability.command_name
	var commander: Commander = _commander()
	if commander != null and _sanction_grid != null:
		for id: StringName in chosen.keys():
			var entry: SanctionGrid.Entry = _sanction_grid.deployable_entry_for(id)
			if entry != null and entry.sanction != null:
				chosen[id] = entry.sanction.command_name()
	return chosen.values()


## Whether this commander's faction could EVER have `a_ability_id` — whether it belongs on the
## card at all, as against being drawn dark. A FREE ability has no grid cell to be found in and
## is always offered; whether the commander has anything to cast it with is NO_CASTER's
## question. Why the GRID rather than a faction tag on the ability:
## gdd/systems/macroeconomics/sanctions/sanction-grid.md §What a faction offers IS its grid.
func _faction_offers_ordnance(a_ability_id: StringName) -> bool:
	if not AbilityCatalog.is_dominion_unlocked(a_ability_id):
		return true
	return _sanction_grid != null and _sanction_grid.has_route_to(a_ability_id)


## The ability an ORDNANCE-card command casts, or &"" when the name is not one. What routes a
## press on that card to the caster-finding path rather than to the ordinary command pipeline.
func ordnance_ability_for(a_command_name: String) -> StringName:
	for binding: ControlBinding in CommandGrid.bindings():
		var ability := binding as AbilityBinding
		if (
			ability != null
			and ability.family == ControlBinding.CommandFamily.ORDNANCE
			and ability.command_name == a_command_name
		):
			return ability.ability_id
	return &""


## The producer TYPES in the selection that author a context cell, as their binding names.
##
## A SINGLE producer type still draws its button, greyed as the radio that is already set.
## That reads as redundant and is the opposite: a row that appears only when there are two
## kinds of producer is a row that comes and goes under the player's hand, and the greyed
## single button is what says "this is the one you are looking at, and there is nowhere else
## to go". The rule is that the row is drawn whenever the card has a producer to show.
func producer_context_names() -> Array:
	var seen: Dictionary = {}
	for node: Node in selection:
		var entity := node as Entity
		if (
			entity == null
			or not is_instance_valid(entity)
			or entity.get_node_or_null("Production") == null
		):
			continue
		var tool: Tool = Tool.for_id(entity.id)
		if tool != null and tool.context_grid.x >= 0:
			seen[entity.id] = true
	if seen.is_empty():
		return []
	var out: Array = []
	for id: StringName in seen:
		out.append(ProducerContextBinding.PREFIX + String(id))
	return out


## Narrow the card's training buttons to the chosen producer. A no-op when no context is
## chosen or the row is not being drawn, which is what keeps a single-producer selection
## showing everything it can train.
func _narrow_to_producer_context(a_names: Array) -> Array:
	if _producer_context == &"" or producer_context_names().is_empty():
		return a_names
	var producer: Actor = null
	for node: Node in selection:
		var entity := node as Entity
		if entity != null and is_instance_valid(entity) and entity.id == _producer_context:
			producer = entity as Actor
			break
	if producer == null:
		return a_names
	var offered: Array = CommandContextParser.tools_for(
		producer, ControlBinding.ControlContext.TRAIN
	)
	return a_names.filter(
		func(name: String) -> bool: return Tool.for_name(name) == null or offered.has(name)
	)


## The selected producers whose production the info panel's Details pane shows: the ones of the
## current producer context while the card is on its PRODUCTION page, and none otherwise —
## which is what keeps production out of Details off that page. Every selected producer when
## the context row is not being drawn, matching _narrow_to_producer_context. Only the local
## player's own: an enemy's queue is not theirs to read.
func production_detail_scope() -> Array:
	if _command_family != ControlBinding.CommandFamily.PRODUCTION:
		return []
	var is_narrowed: bool = _producer_context != &"" and not producer_context_names().is_empty()
	var own: Commander = _commander()
	return selection.filter(
		# Untyped: a freed piece can still be in `selection`, and a typed parameter would
		# reject it before the validity check could run.
		func(node: Variant) -> bool:
			if not is_instance_valid(node):
				return false
			var producer := node as Actor
			return (
				producer != null
				and producer.commander == own
				and producer.production != null
				and (not is_narrowed or producer.id == _producer_context)
			)
	)


## Show the training of `a_producer_id`. The row is a RADIO: one is always set, and pressing
## the one already set does nothing rather than clearing it — there is no "no producer chosen"
## state to fall into.
func choose_producer_context(a_producer_id: StringName) -> void:
	if a_producer_id == _producer_context:
		return
	_producer_context = a_producer_id
	upate_hud_buttons()


func producer_context() -> StringName:
	return _producer_context


## Correct a context the selection cannot fill, and settle on one when the row is up with
## none chosen. Called from the available_commands setter beside _settle_command_family, for
## the same reason: the card must never outlive the selection that filled it.
##
## The DEFAULT follows the first producer in the selection, matching how the card family lands
## on the first thing introduced.
func _settle_producer_context() -> void:
	var names: Array = producer_context_names()
	if names.is_empty():
		return
	var wanted: String = ProducerContextBinding.PREFIX + String(_producer_context)
	if names.has(wanted):
		return
	_producer_context = StringName(String(names[0]).trim_prefix(ProducerContextBinding.PREFIX))


func _on_control_button_pressed(a_control_name: String) -> void:
	# A context button acts on the CARD, not on the selection, so it never reaches
	# process_command — the same bypass the SELECT-context selectors take below.
	if a_control_name.begins_with(ProducerContextBinding.PREFIX):
		choose_producer_context(
			StringName(a_control_name.trim_prefix(ProducerContextBinding.PREFIX))
		)
		return
	if CargoSlotBinding.slot_of(a_control_name) >= 0:
		choose_cargo(CargoSlotBinding.slot_of(a_control_name))
		return
	# The SELECT-context buttons don't act on the current selection — they change
	# it — so they bypass the selection-gated process_command pipeline.
	if _select_command_handlers.has(a_control_name):
		_select_command_handlers[a_control_name].call()
		return
	process_command(a_control_name)


## Right-click on a grid button: buy the thing as a STANDING order — an entry that
## re-issues itself forever, behind everything else in the queue.
##
## Only tool buttons have anything to make standing. A right-click on a verb or a selector
## does nothing rather than falling through to the left-click behaviour, so the two clicks
## never mean the same thing on a button where only one of them is meaningful.
func _on_control_button_alternate_pressed(a_control_name: String) -> void:
	var autocast_id: StringName = CommandContextParser.autocast_ability_of(a_control_name)
	if autocast_id != &"":
		_toggle_autocast(autocast_id, _selection_commander())
		return
	if Tool.for_name(a_control_name) == null:
		return
	_next_purchase_standing = true
	process_command(a_control_name)
	# A BUILD tool only ARMS here — the purchase happens on the world click that follows,
	# and a repeating build has no meaningful site, so the flag has no business surviving
	# this call. A TRAIN tool has already consumed it inside process_command.
	_next_purchase_standing = false


#endregion


#region Private helpers
## Give the ONE non-arrow shape the HUD uses its own game art, once.
##
## `_apply_cursor` only ever registers against CURSOR_ARROW, so any other shape arrives with
## nothing behind it and the OS draws its own — which is why a HUD control marking itself
## clickable used to throw the game's pointer away. Deliberately the PLAIN pointer rather
## than the current world cursor: the HUD is not somewhere you attack.
## Why: gdd/systems/ux/ui/cursor.md §Whether the OS keeps showing it. Pairing:
## tests/test_CursorArt.gd.
func _register_hud_cursor() -> void:
	Input.set_custom_mouse_cursor(FREE_CURSOR, Input.CURSOR_POINTING_HAND)


## Show [a_cursor], and make sure the OS is actually showing it.
##
## `Input.set_custom_mouse_cursor` is NOT idempotent in the useful direction — the same image
## against the same shape short-circuits before reaching the platform, so calling it every
## frame does not keep the cursor asserted. A null cycle is the one path that erases the
## cache entry, which is what `_cursor_needs_reassert` asks for.
## Why, and what the OS does behind the game's back:
## gdd/systems/ux/ui/cursor.md §Whether the OS keeps showing it.
func _apply_cursor(a_cursor: Resource) -> void:
	if a_cursor == _applied_cursor and not _cursor_needs_reassert:
		return
	if _cursor_needs_reassert:
		Input.set_custom_mouse_cursor(null)
		_cursor_needs_reassert = false
	Input.set_custom_mouse_cursor(a_cursor)
	_applied_cursor = a_cursor


## The cursor for a precondition result — three answers, not two.
##
## The question a player asks of a refusal is "keep looking for a spot, or give up on this
## order?", so a refusal they can clear BY MOVING gets a different cursor from one they
## cannot. The classification is MoveCommand.is_positional_failure, which keeps it a fact
## about the cause rather than a fact about the HUD.
##
## UNKNOWN_CURSOR is a STAND-IN for the positional case, doing double duty as the catch-all.
## The full table and the art that is missing: gdd/systems/ux/ui/cursor.md §3 and §Open.
func _cursor_for_precondition(a_cause: MoveCommand.PreconditionFailureCause) -> Resource:
	if a_cause == MoveCommand.PreconditionFailureCause.NONE:
		return cursor_evaluator(current_command_type, command_message)
	if a_cause == MoveCommand.PreconditionFailureCause.COMMAND_PENDING_TOOL:
		return FREE_CURSOR
	return UNKNOWN_CURSOR if MoveCommand.is_positional_failure(a_cause) else INVALID_CURSOR


## The cursor follows the RESOLVED command, never a re-derived guess about the thing
## under the pointer. A move that resolved to MoveCommand shows a move cursor even
## with an entity under the cursor — notably a NEUTRAL one, which
## _resolve_command_class deliberately does not turn into an Attack. (This branch
## used to answer ATTACK_CURSOR for anything not player-owned, which promised an
## attack the click would not actually issue — for neutrals, and for an unarmed
## actor clicking an enemy.)
static func cursor_evaluator(command_type: Script, command_message: CommandMessage) -> Resource:
	if command_type == null or command_type == MoveCommand:
		if command_message.target == null:
			return FREE_CURSOR
		if command_message.target.commander_id == PLAYER_COMMANDER_ID:
			return SELECTION_CURSOR
		return FREE_CURSOR
	elif command_type == Attack or command_type == AttackMove or command_type == FocusFire:
		return ATTACK_CURSOR
	elif command_type == Embark:
		# A friendly-target order, so it reads as one — the same cursor a plain move at your
		# own unit shows.
		return SELECTION_CURSOR
	else:
		return UNKNOWN_CURSOR


## True when the player can currently perceive `entity` — so the cursor may target
## it. Own units are always known; a fog-tracked Actor is perceptible only
## while it's in sight (in_sight_range is fog.gd's per-tick "fog pixel clear AND not
## stealthed" flag, so this subsumes both fog and stealth). A fogged enemy — or a
## fogged structure's remembered snapshot, which has no SELECTION collider at all —
## is not detected, so a right-click over it resolves to a Move on the terrain
## beneath. Non-Actor map features (e.g. neutral Shelters) aren't fog-managed,
## so fall back to their render state (always drawn → still targetable to liberate).
static func _is_perceptible(entity: Entity) -> bool:
	# A lifted fog draws everything, so everything it draws can be pointed at.
	if Fog.is_lifted():
		return true
	# Own pieces are always known — except a planted charge, which its owner sees only in
	# their own vision (fog.gd draws it on that test), and cannot pick out of it.
	if entity.commander_id == PLAYER_COMMANDER_ID:
		return PlantedCharge.of(entity) == null or entity.visible
	if entity is Actor:
		return (entity as Actor).in_sight_range
	# A beacon's stealth is drawn on its model, not on the root fog toggles, so ask both.
	if Beacon.of(entity) != null:
		return entity.is_visible_to(PLAYER_COMMANDER_ID)
	return entity.visible


## Drop selection entries that are no longer selectable, and report whether any went.
##
## Three reasons to drop, in order, and the ORDER is the point:
##
## 1. **Freed.** A freed instance cannot be touched at all — `is`, `as`, a property read, or
##    even assignment to a TYPED local raises "previously freed instance" before any guard
##    inside the callee runs (CLAUDE.md §A freed object cannot be passed to a typed
##    parameter). So the slot is read UNTYPED and validity is established first. Reading it
##    into `var entity: Node` and asking `entity is Actor` first is exactly the crash
##    this ordering exists to prevent.
## 2. **Off the tree and not held.** A GARRISONED unit is off the tree and is NOT gone — being
##    able to select it is how orders reach it before it comes out. Everything else off the
##    tree has died or left the world.
## 3. **Out of sight.** An enemy/neutral entity is dropped as soon as it leaves player vision.
func prune_selection() -> bool:
	var pruned: bool = false
	for i in range(selection.size() - 1, -1, -1):
		var slot: Variant = selection[i]
		if not is_instance_valid(slot):
			selection.remove_at(i)
			pruned = true
			continue
		var entity: Node = slot
		var held: bool = entity is Actor and (entity as Actor).is_garrisoned()
		if not entity.is_inside_tree() and not held:
			entity.selectable.deselect()
			selection.remove_at(i)
			pruned = true
			continue
		var commandable: Actor = entity as Actor
		if (
			commandable != null
			and is_player_commandable(commandable)
			and not _is_perceptible(commandable)
		):
			commandable.selectable.deselect()
			selection.remove_at(i)
			pruned = true
		elif (
			commandable != null
			and not is_player_commandable(commandable)
			and not commandable.is_visible_to(PLAYER_COMMANDER_ID)
		):
			commandable.selectable.deselect()
			selection.remove_at(i)
			pruned = true
	return pruned


## The entity under the cursor along `from`→`to`, or null.
##
## **A unit outranks a structure, whatever is physically in front.** The camera looks down at
## an angle and structure selection shapes are tall, so a structure routinely covers units
## standing behind it; picking the nearest hit made those units unclickable. The reverse case —
## a structure hidden behind units — is accepted as unreachable in practice and deliberately
## not handled.
##
## Only entities the player can actually perceive are candidates. Fogged/stealthed enemies are
## skipped rather than ending the search, so a visible unit behind an unseen one is still
## pickable; with nothing perceptible the caller falls through to the terrain hit, and a
## right-click resolves to a move instead of an attack on something unseen.
##
## `a_accepts`, when given, is a further filter on each candidate — an armed single-unit
## ability passes the test for "a unit it may act on", so pointing into a mixed group finds
## the unit it can affect rather than stopping at the first one in front.
func _pick_cursor_entity(
	a_ray_origin: Vector3, a_ray_end: Vector3, a_accepts: Callable = Callable()
) -> Entity:
	var candidates: Array[Entity] = []
	for hit: Dictionary in map.line_hits(a_ray_origin, a_ray_end, CollisionLayers.Mask.SELECTION):
		var selectable := hit["collider"] as Selectable
		if selectable == null:
			continue
		var entity: Entity = selectable.get_entity()
		if entity == null or not _is_perceptible(entity):
			continue
		if a_accepts.is_valid() and not a_accepts.call(entity):
			continue
		candidates.append(entity)
	return preferred_cursor_entity(candidates)


## Which of the cursor's candidates wins, given them in ray order (nearest first).
## Separated from the raycast so the RULE is testable without a physics server.
static func preferred_cursor_entity(candidates: Array[Entity]) -> Entity:
	var fallback: Entity = null
	for entity: Entity in candidates:
		if entity == null:
			continue
		if entity.is_in_group("unit"):
			return entity
		if fallback == null:
			fallback = entity
	return fallback


func get_cursor_target(a_mouse_position: Vector2) -> Variant:
	# Cursor picking raycasts against the Map; with no Map (e.g. running
	# player.tscn standalone to preview the HUD) there is nothing to hit.
	if map == null:
		return null
	var ray_origin: Vector3 = camera.project_ray_origin(a_mouse_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(a_mouse_position) * 1000.0

	var picked: Entity = _pick_cursor_entity(ray_origin, ray_end)
	if picked != null:
		return picked

	var terrain_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Mask.TERRAIN)
	if terrain_hit:
		return terrain_hit["position"]

	return null


## The terrain under the cursor, looking THROUGH any piece in front of it; the height-0 plane
## when the ray finds no terrain. The plane alone is wrong on raised ground: it lands the point
## where the ray crosses y = 0, which on a hill is cells beyond what the cursor is over — so a
## drop aimed over a unit drew its ghost off to one side.
func _cursor_ground_point(a_mouse_position: Vector2) -> Vector3:
	if map != null:
		var ray_origin: Vector3 = camera.project_ray_origin(a_mouse_position)
		var ray_end: Vector3 = ray_origin + camera.project_ray_normal(a_mouse_position) * 1000.0
		var terrain_hit: Variant = map.line_hit(ray_origin, ray_end, CollisionLayers.Mask.TERRAIN)
		if terrain_hit != null:
			return (terrain_hit as Dictionary)["position"]
	return camera.get_mouse_world_position(a_mouse_position)


## Refresh the world-under-cursor readout. Recomposed every frame from the cursor result
## rather than pushed by whoever noticed something: the cursor moves off a thing as often as
## it moves onto one, and a readout that has to be told to hide is a readout that gets left
## on screen.
func _update_cursor_readout() -> void:
	if _cursor_readout != null:
		_cursor_readout.show_text(_cursor_readout_text(), mouse_position)


## What the cursor is standing on that is worth a line of text. Water, so far: a body's
## remaining energy, which is the only way to read a lithium pond's charge — the surface
## colour says "charged", not "how much".
##
## FOGGED GROUND SAYS NOTHING. A pond's charge is information about the map, and reading it
## through an unexplored shroud would be the same leak as seeing the pond itself.
func _cursor_readout_text() -> String:
	if map == null or not (cursor_target is Vector3):
		return ""
	var world_xz: Vector2 = VU.in_xz(cursor_target as Vector3)
	var body: WaterBody = map.water_body_at_world(world_xz)
	if body == null:
		return ""
	var fog: Variant = Fog.get_active_fog()
	if fog is Fog and (fog as Fog).terrain_visibility_at(world_xz) == Fog.TerrainVisibility.UNSEEN:
		return ""
	return "energy: %d" % body.energy


## The neutral building the armed Build would convert if issued at the cursor, or null when the
## armed order is not a conversion (or is not a Build at all).
func armed_conversion_target() -> Actor:
	if command_message == null or current_command_type != Build:
		return null
	return Build.conversion_target(_selection_commander(), command_message)


## The energy a conversion at the cursor would cost, or -1 when nothing is being converted or a
## button is hovered (a hover previews ITS purchase outright, see previewed_tool).
func previewed_conversion_energy() -> int:
	if hovered_command_name() != &"":
		return -1
	var target: Actor = armed_conversion_target()
	return Build.conversion_energy(target) if target != null else -1


## The building currently wearing the conversion marker.
var _conversion_marked: Actor = null


## Mark the building the armed Build would convert, using the marker a single-unit ability
## uses for its target: "this is what the order lands on".
func _update_conversion_marker() -> void:
	var target: Actor = armed_conversion_target()
	if target == _conversion_marked:
		return
	if is_instance_valid(_conversion_marked):
		_conversion_marked.set_ability_targeted(false)
	if target != null:
		target.set_ability_targeted(true)
	_conversion_marked = target


## Show / refresh / hide the translucent build-placement ghost. Called every
## frame from _process. The ghost is visible only while the armed command is
## Build and the player has chosen a Tool; it snaps to the same cell the
## structure would be placed in, so the preview matches the real placement.
func _update_build_preview(a_is_invalid_placement: bool) -> void:
	if is_debug_piece_armed():
		_update_debug_preview()
		return
	if is_drop_armed():
		_update_drop_preview()
		return
	# No ghost over a conversion: nothing new is placed there, and a placement verdict drawn on
	# the building would say something false about it (the target's marker says it instead).
	var should_show: bool = (
		current_command_type == Build
		and command_message.tool != null
		and armed_conversion_target() == null
	)
	if not should_show:
		if _build_preview != null and is_instance_valid(_build_preview):
			_build_preview.visible = false
		return

	# (Re)build the ghost sprite when the chosen structure changes.
	if (
		_build_preview == null
		or not is_instance_valid(_build_preview)
		or command_message.tool.preview_key() != _build_preview_tool_type
	):
		_rebuild_build_preview(command_message.tool)

	var lead: Entity = (selection[0] as Entity) if not selection.is_empty() else null
	var commander: Commander = lead.commander if lead != null else null
	if commander == null:
		# No builder selected (or one not yet owned): nothing to source the ghost's art or
		# team colour from.
		_build_preview.visible = false
		return

	# Snap to the footprint centre; hide if any of its cells is off-map so we never
	# index the heightmap out of bounds (grid_to_world reads map_data directly).
	var turns: int = command_message.quarter_turns
	var centroid: Variant = _footprint_centroid(
		commander, command_message.tool, command_message.xz_position, turns
	)
	if centroid == null:
		_build_preview.visible = false
		return
	_build_preview.global_position = centroid
	_build_preview.rotation.y = Fixture.yaw_of(turns)
	_tint_build_preview(Entity.TEAM_COLOR_MAP[commander.id], a_is_invalid_placement)
	_build_preview.visible = true


## Colour the ghost as `a_team_color`, reddened when the placement is invalid.
func _tint_build_preview(a_team_color: Color, a_is_invalid_placement: bool) -> void:
	var tint: Color = (
		a_team_color
		* (BUILD_PREVIEW_INVALID_TINT if a_is_invalid_placement else BUILD_PREVIEW_VALID_TINT)
	)
	for child in _build_preview.get_children():
		if child is MeshVisual:
			# A MeshVisual multiplies this over the model's design albedo and takes its alpha
			# from set_opacity (applied once, at build time), so hand it the opaque colour.
			(child as MeshVisual).set_team_color(Color(tint.r, tint.g, tint.b, 1.0))
		elif child is Sprite3D:
			child.modulate = tint


## World-space centre of the footprint the structure behind `a_tool` would occupy if
## placed at `a_xz`, or null when any of its cells falls off the map.
##
## Resolved through Map.footprint_origin / footprint_centroid — the SAME functions the
## placement check, the blueprint and add_structure use — rather than by re-deriving the
## origin here. It used to be re-derived (`cell - (dims-1)/2`), which agrees with
## Map.footprint_origin only for ODD footprints: an even one (every 2×2 building, which is
## every overlay host in the game) centres on a grid CORNER, so the ghost sat a cell away
## from where the structure actually landed and appeared to jump on confirmation.
##
## Every cell is bounds-checked, not just the centre one, since that can be in bounds
## while the rest of the footprint spills off the edge near a map border.
func _footprint_centroid(
	a_commander: Commander, a_tool: Tool, a_xz: Vector2, a_quarter_turns: int = 0
) -> Variant:
	if map == null or a_tool == null:
		return null
	var source: Node = (
		a_commander.get_build_preview_instance(a_tool) if a_commander != null else null
	)
	return _footprint_centroid_of(source, a_xz, a_quarter_turns)


## As _footprint_centroid, for the structure `a_source` is an out-of-tree instance of.
func _footprint_centroid_of(a_source: Node, a_xz: Vector2, a_quarter_turns: int = 0) -> Variant:
	if map == null:
		return null
	var obs := a_source.get_node_or_null("Fixture") as Fixture if a_source != null else null
	var dims: Vector2i = (
		Fixture.oriented_dimensions(obs.dimensions, a_quarter_turns)
		if obs != null
		else Vector2i.ONE
	)
	var origin: Vector2i = map.footprint_origin(a_xz, dims)
	for w in range(dims.x):
		for l in range(dims.y):
			if not map.grid_coordinates_in_bounds(Vector2i(origin.x + w, origin.y + l)):
				return null
	return map.footprint_centroid(origin, dims)


## Rebuild the ghost's model from the structure's own scene so the preview always matches
## the real building art. The source is the builder's Commander's preview instance (kept
## out of the tree, see Commander.get_build_preview_instance), so we don't re-instantiate
## the scene here; the team colour is applied to the copy each frame by
## _update_build_preview, which also folds in the valid/invalid signal.
func _rebuild_build_preview(a_tool: Tool) -> void:
	_clear_build_preview(a_tool.preview_key())

	var lead: Entity = (selection[0] as Entity) if not selection.is_empty() else null
	var commander: Commander = lead.commander if lead != null else null
	var source: Node = commander.get_build_preview_instance(a_tool) if commander != null else null
	if source == null:
		return
	_add_ghost_visual(_build_preview, source, Entity.TEAM_COLOR_MAP.get(commander.id, Color.WHITE))


## Make sure the ghost node exists, empty it, and record what it is about to show.
func _clear_build_preview(a_key: Variant) -> void:
	if _build_preview == null or not is_instance_valid(_build_preview):
		_build_preview = Node3D.new()
		_build_preview.name = "BuildPreview"
		_build_preview.visible = false
		map.get_parent().add_child(_build_preview)
	for child in _build_preview.get_children():
		child.free()
	_build_preview_tool_type = a_key


## Copy `source`'s visual — its 3D MeshVisual subtree, or its Sprite3D for billboard art —
## under `container` as a translucent, inert ghost: model only, so no colliders, no
## selection shape and no physics come along, and nothing about it can be commanded.
##
## The copy's own MeshVisual._ready gathers fresh override materials off the source's, so
## it never shares (or writes to) the materials of the instance it was copied from. That
## source is the commander's out-of-tree preview instance, whose _ready has never run and
## whose materials are therefore UNTINTED — hence the explicit set_team_color here, rather
## than the tint-inheriting duplicate the fog snapshots take off live structures.
func _add_ghost_visual(a_container: Node3D, a_source: Node, a_tint: Color) -> void:
	var visual := a_source.get_node_or_null("MeshVisual") as MeshVisual
	if visual != null:
		var ghost := visual.duplicate() as MeshVisual
		ghost.set_process(false)
		ghost.set_physics_process(false)
		a_container.add_child(ghost)
		# After add_child: transform is relative to the container (which sits at the
		# footprint centre), and set_opacity/set_team_color only take effect once the
		# copy's _ready has gathered its materials.
		ghost.transform = visual.transform
		ghost.set_team_color(a_tint)
		ghost.set_opacity(MeshVisual.OPACITY_PLANNED)
		return

	var sprite := a_source.get_node_or_null("Sprite") as Sprite3D
	if sprite != null:
		var ghost_sprite := sprite.duplicate() as Sprite3D
		ghost_sprite.modulate = Color(a_tint.r, a_tint.g, a_tint.b, BUILD_PREVIEW_ALPHA)
		a_container.add_child(ghost_sprite)


func _make_indicator() -> WaypointIndicator:
	var ind := WaypointIndicator.new()
	map.add_child(ind)
	ind.visible = false
	return ind


func _register_indicator(a_msg: CommandMessage) -> void:
	if map == null:
		return
	if _indicator_pool.is_empty():
		_indicator_pool.append(_make_indicator())
	var ind: WaypointIndicator = _indicator_pool.pop_back()
	_active_indicators[a_msg] = ind
	a_msg.unreferenced.connect(_on_message_unreferenced.bind(a_msg), CONNECT_ONE_SHOT)


func _on_message_unreferenced(a_msg: CommandMessage) -> void:
	var ind = _active_indicators.get(a_msg)
	if ind == null:
		return
	ind.visible = false
	_active_indicators.erase(a_msg)
	_indicator_pool.append(ind)


## Show waypoint indicators for the current selection.  Called every frame so
## the line from a moving unit to its first waypoint stays accurate.
func _update_waypoint_display() -> void:
	for ind in _active_indicators.values():
		(ind as WaypointIndicator).visible = false

	if selection.is_empty() or _active_indicators.is_empty():
		return

	# Walk every selected unit's chain so the union of all their active
	# indicators is shown, not just the first representative's.
	var configured: Dictionary = {}  # CommandMessage -> true, prevents double-configure
	for entity in selection:
		if not (entity is Actor):
			continue
		var unit := entity as Actor
		var chain := unit.get_command_chain()
		# world_position, not global_position: a garrisoned unit's line starts at its host.
		var prev_pos: Vector3 = unit.world_position()
		for cmd in chain:
			var msg: CommandMessage = cmd.message
			if _active_indicators.has(msg) and not configured.has(msg):
				var ind: WaypointIndicator = _active_indicators[msg]
				ind.configure(msg.position, prev_pos)
				ind.visible = true
				configured[msg] = true
			prev_pos = msg.position


## Ring the structures that could build the queued purchase the cursor is over — the world
## half of producer affinity, answering "where will this purchase go?". Cleared whenever
## nothing is hovered. BUILD purchases are skipped: they have no producers, only a site and
## whichever builders take the order. The other direction, and why this ring shares
## RallyIndicator's cyan: gdd/systems/ux/ui/hud-layout.md §Producer affinity.
func _update_producer_affinity() -> void:
	if _producer_affinity_indicator == null:
		return
	var hovered: PurchaseTransaction = (
		_production_rail.hovered_transaction() if _production_rail != null else null
	)
	if hovered == null and _info_view != null:
		hovered = _info_view.hovered_transaction()
	if hovered == null or hovered.kind != PurchaseTransaction.Kind.TRAIN:
		_producer_affinity_indicator.update_producers([])
		return
	_producer_affinity_indicator.update_producers(hovered.candidate_producers())


## Draw each selected rally-capable STRUCTURE's rally-point sequence, anchored at the
## structure and following whichever chain is currently relevant to it (see
## _rally_commands_to_draw). Called every frame, same cadence as _update_waypoint_display.
func _update_rally_indicator() -> void:
	if _rally_indicator == null:
		return
	var hovered: Array = _info_view.hovered_training_target() if _info_view != null else []
	var chains: Array = []
	for node: Node in selection:
		var structure := node as Actor
		if structure == null or not structure.is_in_group("structure") or not structure.can_rally():
			continue
		var commands: Array = _rally_commands_to_draw(structure, hovered)
		if commands.is_empty():
			continue
		var points: Array = [structure.global_position]
		for command: MoveCommand in commands:
			points.append(command.message.position)
		chains.append(points)
	_rally_indicator.update_chains(chains)


## The command chain to draw for [a_structure] — two cases, and only two: the hovered unit's
## OWN pre-issued chain while the player hovers that unit's production card, and otherwise
## the structure's live `rally_commands`, the rally as CONFIGURED.
##
## The unhovered case deliberately does NOT read the job in progress. Why:
## gdd/systems/commands/construction.md §Rally / release destinations.
func _rally_commands_to_draw(a_structure: Actor, a_hovered: Array) -> Array:
	if a_structure.production != null and a_hovered.size() == 2 and a_hovered[0] == a_structure:
		var job_index: int = a_hovered[1]
		if job_index >= 0 and job_index < a_structure.production.job_count():
			var job_commands: Array = a_structure.production.job_commands(job_index)
			return job_commands if not job_commands.is_empty() else a_structure.rally_commands
	return a_structure.rally_commands


static func get_action_names_by_prefix(event: InputEvent, event_prefix: String) -> Array:
	return (
		InputMap
		. get_actions()
		. filter(func(action_name: String): return event_prefix in action_name)
		. filter(func(action_name: String): return event.is_action_pressed(action_name, true))
	)


#endregion


#region Commander sanctions
## Source the sanction grid from the local commander, so what the player sees and can
## unlock or deploy is faction-driven. The controller is a child of its Commander node (see
## player.tscn).
##
## The grid is drawn across TWO surfaces — an always-up deploy BAR and a toggled unlock
## MENU — because unlocking and deploying are asked at completely different moments.
## Why, and what one bar trying to be both cost:
## gdd/systems/macroeconomics/sanctions/sanction-grid.md §Unlocking and deploying are two
## HUD surfaces.
func _setup_commander_sanctions() -> void:
	var commander: Commander = _commander()
	_sanction_grid = commander.sanction_grid if commander != null else null
	_setup_sanction_bar()
	_setup_sanction_menu()


## Take down both sanction surfaces, so _setup_commander_sanctions can build them for another
## commander.
func _teardown_commander_sanctions() -> void:
	for surface: Control in [_sanction_bar, _sanction_menu]:
		if surface != null:
			remove_child(surface)
			surface.queue_free()
	_sanction_bar = null
	_sanction_menu = null
	_pending_sanction = null


#region The deploy bar
## A full-width CenterContainer holding a shrink-to-fit ROW, rather than one full-width
## HBox. The blocking-UI group tests a Control's whole RECT (see
## pointer_over_blocking_ui), so a full-width bar in that group would deaden the entire
## top strip of the screen; the row's rect is just the buttons.
func _setup_sanction_bar() -> void:
	_sanction_bar = CenterContainer.new()
	_sanction_bar.name = "SanctionBar"
	_sanction_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Offset from the top edge so it doesn't overlap with other UI anchored there. Both
	# offsets, since the height comes from the row's minimum size either way.
	_sanction_bar.offset_top = 8.0
	_sanction_bar.offset_bottom = 8.0
	_sanction_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sanction_bar)
	# Its buttons only ever give orders, which a look-only HUD does not.
	_sanction_bar.visible = not is_look_only

	_sanction_bar_row = HBoxContainer.new()
	_sanction_bar_row.name = "Row"
	_sanction_bar_row.add_theme_constant_override("separation", 8)
	# A press on either surface belongs to that surface: without this a click on an
	# sanction button ALSO reaches the world and clears the selection behind it.
	_sanction_bar_row.add_to_group(SELECTION_BLOCKING_UI_GROUP)
	_sanction_bar.add_child(_sanction_bar_row)

	_sanction_menu_button = Button.new()
	_sanction_menu_button.name = "SanctionMenuButton"
	_sanction_menu_button.text = "Sanctions"
	_sanction_menu_button.focus_mode = Control.FOCUS_NONE
	_sanction_menu_button.custom_minimum_size = Vector2(110.0, 32.0)
	_sanction_menu_button.pressed.connect(toggle_sanction_menu)
	_sanction_bar_row.add_child(_sanction_menu_button)

	_deploy_buttons.clear()
	# ONE BUTTON PER ABILITY THAT ASKS FOR ONE, built once and SHOWN when the commander can
	# actually use it. WHICH abilities get a button is authored (`hud_button:`) rather than
	# derived from being dominion-unlocked, which used to conflate the HUD with the shop and
	# left a global-range ability nobody paid dominion for — the Bombard's battery — with no
	# button at all. The rule of thumb behind the flag is reach: an ability the player cannot
	# walk the map to find a caster for wants one.
	for ability: StringName in AbilityCatalog.ids():
		if not AbilityCatalog.has_hud_button(ability):
			continue
		var btn := VerboseTooltipButton.new()
		btn.custom_minimum_size = Vector2(140.0, 32.0)
		btn.name = AbilityCatalog.title_of(ability)
		btn.visible = false
		btn.pressed.connect(_on_deploy_button_pressed.bind(ability))
		if _has_autocast(ability):
			btn.gui_input.connect(_on_deploy_button_input.bind(btn, ability))
		_sanction_bar_row.add_child(btn)
		_deploy_buttons.append({"button": btn, "ability": ability, "entry": null})
		_refresh_deploy_tooltips(_deploy_buttons[-1])


## Whether `a_ability_id` has an automatic mode its buttons toggle.
static func _has_autocast(a_ability_id: StringName) -> bool:
	return (
		CommandContextParser.autocast_ability_of(AbilityCatalog.command_of(a_ability_id))
		== a_ability_id
	)


## A RIGHT-click on a HUD-bar ability button toggles its automatic mode, as on the command card.
## The `gui_input` signal rather than a _gui_input override, for ButtonSpec's reason.
func _on_deploy_button_input(
	a_event: InputEvent, a_button: Control, a_ability_id: StringName
) -> void:
	var press := a_event as InputEventMouseButton
	if press == null or press.button_index != MOUSE_BUTTON_RIGHT or not press.pressed:
		return
	a_button.accept_event()
	_toggle_autocast(a_ability_id, _commander())


## A VerboseTooltipButton rather than a plain Button, so a sanction tooltip looks and
## behaves like every other HUD tooltip (same delay, same popup, same verbose tier) —
## the command grid builds its buttons the same way, see
## ButtonSpec.create_button_from_spec.
##
## The UNLOCK menu's buttons only. A deploy button stands for an ABILITY rather than for
## one cell, so its copy follows whichever cell is in play (see _refresh_deploy_tooltips).
func _build_sanction_button(a_entry: SanctionGrid.Entry, a_deploys: bool) -> VerboseTooltipButton:
	var btn := VerboseTooltipButton.new()
	btn.custom_minimum_size = Vector2(140.0, 32.0)
	# Named before the tooltip is set so a missing description is reported against the
	# sanction rather than against an anonymous button.
	var label: String = a_entry.sanction.sanction_name if a_entry.sanction != null else "Sanction"
	btn.name = label if a_deploys else "%sUnlock" % label
	# Set once here, not in the per-frame repaint: both tiers are authored data that never
	# changes, while that runs every frame.
	btn.simple_tooltip = a_entry.sanction.description if a_entry.sanction != null else ""
	btn.verbose_tooltip = _sanction_verbose_tooltip(a_entry, a_deploys)
	if a_deploys:
		btn.pressed.connect(_on_deploy_button_pressed.bind(a_entry))
	else:
		btn.pressed.connect(_on_unlock_button_pressed.bind(a_entry))
		# The UNLOCK button is the one that spends dominion — see DominionBar's hover preview
		# (gdd/systems/ux/ui/economy-bars.md §Hover previews). The deploy/cast button never sets
		# this: casting spends a charge, not dominion.
		btn.mouse_entered.connect(func(): hovered_sanction_unlock = a_entry)
		btn.mouse_exited.connect(
			func():
				if hovered_sanction_unlock == a_entry:
					hovered_sanction_unlock = null
		)
	return btn


## The held-key tier for a sanction button: the authored description plus the numbers a
## player weighs it by — what unlocking costs, how often it can be used, how much ground
## it covers. Derived from the sanction grid entry rather than authored a second time, so a
## retuned sanction re-describes itself. The closing line differs by surface, since the
## two buttons do different things to the same sanction.
func _sanction_verbose_tooltip(a_entry: SanctionGrid.Entry, a_deploys: bool) -> String:
	var sanction: Sanction = a_entry.sanction
	if sanction == null:
		return ""
	var lines: Array[String] = []
	# The authored long tier replaces the short one here rather than joining it — it is a
	# fuller telling of the same thing, so showing both would repeat the first sentence.
	# The synthesized number lines below are appended either way.
	var prose: String = (
		sanction.verbose_description
		if not sanction.verbose_description.is_empty()
		else sanction.description
	)
	if not prose.is_empty():
		lines.append(prose)
	if a_entry.unlock != null and a_entry.unlock.dominion_cost > 0:
		lines.append("Unlock: %d dominion" % a_entry.unlock.dominion_cost)
	var area: float = sanction.area_radius()
	lines.append(
		(
			(
				"Cooldown: %ds · effect radius %s"
				% [roundi(sanction.cooldown_duration), String.num(area, 1)]
			)
			if area > 0.0
			else "Cooldown: %ds" % roundi(sanction.cooldown_duration)
		)
	)
	# Only the exception is stated. Needing vision is the rule every sanction follows
	# (see Sanction.needs_vision), so saying so on every button would be noise, while a
	# scan the player CAN aim into the shroud is otherwise only discoverable by trying.
	if not sanction.needs_vision:
		lines.append("Can be aimed into unexplored ground.")
	if a_deploys:
		lines.append(
			"Click to arm, then click the map to aim it. Clicking the button again cancels."
		)
	else:
		lines.append(
			(
				"Tier %d, column %d. Unlocking it replaces whatever it upgrades."
				% [a_entry.tier(), a_entry.column()]
			)
		)
	return "\n".join(lines)


## Per-frame upkeep for both surfaces.
##
## Nothing ticks an Sanction any more: a charge belongs to the BUILDING that would fire it
## (Abilities), so the countdown runs on each caster and the bar only reports it.
func _tick_sanctions(_a_delta: float) -> void:
	for pair: Dictionary in _deploy_buttons:
		_paint_deploy_button(pair)
	# The menu's labels are only worth recomputing while the player can read them.
	if _sanction_grid != null and _sanction_menu != null and _sanction_menu.visible:
		for pair: Dictionary in _unlock_buttons:
			_paint_unlock_button(pair["button"] as Button, pair["entry"] as SanctionGrid.Entry)


## How many of the commander's pieces granted `a_ability_id` are charged, and how many
## exist at all.
func _ability_readiness(a_ability_id: StringName) -> Vector2i:
	var commander: Commander = _commander()
	if commander == null:
		return Vector2i.ZERO
	var casters: Array = commander.casters_of_ability(a_ability_id)
	var ready: int = 0
	for caster: Actor in casters:
		var store := caster.get_node_or_null("Abilities") as Abilities
		if store != null and store.is_ready(a_ability_id):
			ready += 1
	return Vector2i(ready, casters.size())


## A bar button is SHOWN only once the commander owns a piece that can use the ability —
## and, for a DOMINION-unlocked one, once the sanction grid holds a cell of it in play. An
## ability with nowhere to be used from is not an ability the player has.
##
## It reads "Name · ready/total", because the charge is per piece: owning three Operations
## Centers really is three Scans, and the count is how that is sold.
func _paint_deploy_button(a_pair: Dictionary) -> void:
	var btn: Button = a_pair["button"] as Button
	var ability: StringName = a_pair["ability"]
	var entry: SanctionGrid.Entry = (
		_sanction_grid.deployable_entry_for(ability) if _sanction_grid != null else null
	)
	if entry != a_pair["entry"]:
		# The cell in play changed — an unlock, or an upgrade superseding what was there. The
		# tooltips are authored data and are rebuilt HERE rather than every frame.
		a_pair["entry"] = entry
		_refresh_deploy_tooltips(a_pair)
	if AbilityCatalog.is_dominion_unlocked(ability) and entry == null:
		btn.visible = false
		return
	var readiness: Vector2i = _ability_readiness(ability)
	btn.visible = readiness.y > 0
	if not btn.visible:
		return
	var label: String = (
		entry.sanction.sanction_name if entry != null else AbilityCatalog.title_of(ability)
	)
	if entry != null and _pending_sanction == entry.sanction:
		btn.text = "%s [click target]" % label
	elif readiness.x == 0:
		btn.text = "%s (recharging)" % label
	else:
		btn.text = "%s · %d/%d" % [label, readiness.x, readiness.y]
	# Never DISABLED on a spent charge: the order is still worth giving — the caster holds it
	# and fires when it comes up, exactly as a Bombard does.
	btn.disabled = false
	var commander: Commander = _commander()
	if _has_autocast(ability) and commander != null:
		(btn as VerboseTooltipButton).show_toggled(commander.is_autocasting(ability))


## The two authored tiers for a deploy button. A dominion-unlocked ability describes
## itself with the CELL that is in play, since the copy is per level; a free one has only
## its own words.
func _refresh_deploy_tooltips(a_pair: Dictionary) -> void:
	var btn: VerboseTooltipButton = a_pair["button"] as VerboseTooltipButton
	var entry: SanctionGrid.Entry = a_pair["entry"]
	if entry != null:
		btn.simple_tooltip = entry.sanction.description
		btn.verbose_tooltip = _sanction_verbose_tooltip(entry, true)
		return
	var ability: StringName = a_pair["ability"]
	# A LEVELLED ability's copy belongs to the level, not to the ability — "Scan 2" reveals more
	# ground than "Scan 1" and says so — so the ability's own `description` is empty for every
	# sanction. Falling back to the first level's words is what keeps a button from reaching the
	# player with nothing on it, which VerboseTooltipButton reports as an authoring bug.
	var buttons: Array[Dictionary] = AbilityCatalog.buttons_of(ability)
	var copy: Dictionary = buttons[0] if not buttons.is_empty() else {}
	btn.simple_tooltip = str(copy.get("description", AbilityCatalog.description_of(ability)))
	var lines: Array[String] = []
	var prose: String = str(copy.get("verbose", AbilityCatalog.verbose_of(ability)))
	if prose.is_empty():
		prose = btn.simple_tooltip
	if not prose.is_empty():
		lines.append(prose)
	lines.append("Click to arm, then click the map to aim it. Clicking the button again cancels.")
	btn.verbose_tooltip = "\n".join(lines)


## The bar is a SHORTCUT, not a second way to fire. Pressing a button selects every
## building that can cast the ability and arms it, leaving the player one right-click from
## the same order they could have given by selecting the building themselves.
##
## That is the whole reason the bar survived the move to per-building abilities: the
## ability is the unit's now, so a bar that fired it directly would be a hidden second
## caster. Selecting is honest about where the power actually lives.
func _on_deploy_button_pressed(a_ability_id: StringName) -> void:
	var commander: Commander = _commander()
	if commander == null:
		return
	var entry: SanctionGrid.Entry = (
		_sanction_grid.deployable_entry_for(a_ability_id) if _sanction_grid != null else null
	)
	if AbilityCatalog.is_dominion_unlocked(a_ability_id) and entry == null:
		return
	var casters: Array = commander.casters_of_ability(a_ability_id)
	if casters.is_empty():
		return
	deselect()
	for caster: Actor in casters:
		if caster.selectable.select():
			selection.append(caster)
	_refresh_available_commands()
	# The bar has just REPLACED the selection, so the card settled for whatever it picked —
	# and a Citadel settles on PRODUCTION, being an immobile producer. The command about to be
	# armed lives on the other card, and _command_is_available refuses a command the visible
	# card is not drawing. So the grid is turned to the card the ability is on: the bar is a
	# shortcut to a grid button, and it has to leave the grid showing the button it pressed.
	_show_card_for_command(AbilityCatalog.command_of(a_ability_id))
	if entry == null:
		# A free ability is armed as its own grid command, so the right-click that follows
		# resolves through the ordinary command path — the bar has pressed the card button.
		process_command(AbilityCatalog.command_of(a_ability_id))
	elif entry.sanction.needs_target:
		# Arm it, so the next right-click aims.
		_pending_sanction = entry.sanction
		# A cargo menu opens EMPTY. Whatever tool the player last placed a building with must not
		# read as this sanction's chosen payload — see pending_payload_sanction, which asks
		# exactly that question.
		if entry.sanction != null and entry.sanction.takes_a_payload():
			command_message.tool = null
			# The menu is drawn on the ACTIVE card (CargoSlotBinding) — turned to directly, since
			# the armed menu is what the card will show, whatever else the selection offers there.
			_command_family = ControlBinding.CommandFamily.ACTIVE
		process_command(entry.sanction.command_name())
	else:
		# An un-aimed sanction (Global EMP) has nowhere to point, so pressing the button is
		# the whole order — issued to the casters directly.
		_issue_sanction(entry.sanction, Vector3.ZERO)
	upate_hud_buttons()


## Turn the command grid to whichever card `a_command_name` is drawn on, if the current
## selection can fill it. A no-op for a command with no grid binding, and for one already on
## show — set_command_family refuses a family the selection has nothing for, which is what
## keeps this from emptying the card.
func _show_card_for_command(a_command_name: String) -> void:
	# Already on a card that draws it — nothing to turn. Matters for a command drawn on TWO
	# cards (the Bombard): binding_for returns whichever sorts first, so without this, arming it
	# from the commander's card would throw the player onto the other one.
	if _command_is_on_current_card(a_command_name):
		return
	var binding: ControlBinding = CommandGrid.binding_for(a_command_name)
	if binding != null:
		set_command_family(binding.family)


## Give every selected caster the order to cast `a_sanction` at `a_position`.
func _issue_sanction(a_sanction: Sanction, a_position: Vector3) -> void:
	command_message.sanction = a_sanction
	command_message.world_position = a_position
	assign_command_to_units(UseSanction, command_message, additive_latched)
	_pending_sanction = null


#region Single-unit ability targeting
## The unit the armed single-unit ability would act on if issued now — the unit under the
## cursor that the ability accepts — or null. Null too when nothing of that kind is armed.
var ability_target: Actor = null


## Whether the armed order is a cast that acts on exactly one unit (see
## Sanction.targets_one_unit). Such an order is aimed at a UNIT: it has no area to draw, and
## it is not issued while no unit is targeted.
func armed_targets_one_unit() -> bool:
	return _pending_sanction != null and _pending_sanction.targets_one_unit()


## Re-resolve `ability_target` from the cursor, move the marker onto it, and make it the
## message's target — so the precondition, the error line and the cursor all describe the
## unit that would actually be affected. Every frame, like the rest of the cursor state:
## the pointer leaves a unit as often as it arrives on one.
func _update_ability_target() -> void:
	var found: Actor = null
	if armed_targets_one_unit() and map != null and camera != null:
		var sanction: Sanction = _pending_sanction
		var commander: Commander = _commander()
		var origin: Vector3 = camera.project_ray_origin(mouse_position)
		var end: Vector3 = origin + camera.project_ray_normal(mouse_position) * 1000.0
		found = (
			_pick_cursor_entity(
				origin,
				end,
				func(a_entity: Entity) -> bool: return sanction.accepts_target(a_entity, commander)
			)
			as Actor
		)
		command_message.target = found
	if found != ability_target:
		if is_instance_valid(ability_target):
			ability_target.set_ability_targeted(false)
		if found != null:
			found.set_ability_targeted(true)
		ability_target = found


#endregion


## The armed sanction's aiming click. It is now an ORDER to the selected casters rather
## than a commander-level activation, so it goes through the ordinary command path and the
## per-building charge is what decides whether anything happens.
func _activate_pending_sanction() -> void:
	if _pending_sanction == null:
		return
	# A sanction that takes a cargo is not aimed until one is chosen. The click that would
	# otherwise fire it lands while the menu is still up, so it does nothing rather than
	# delivering an empty transport.
	if pending_payload_sanction() != null:
		return
	# A single-unit cast pointed at nothing is not issued: the click does nothing, the ability
	# stays armed, and no charge is spent.
	if armed_targets_one_unit() and ability_target == null:
		return
	_issue_sanction(_pending_sanction, command_message.world_position)


#endregion


#region The unlock menu
## The menu draws the sanction grid AS THE AUTHORED GRID: one row per tier, one column per
## sanction family, empty cells left empty. Alignment is the whole point — a family is
## only legible as a column if the column does not shift where a tier skipped it, which
## is why the gaps get placeholder Controls rather than being packed out.
## LAID OUT BY CONTAINERS, not by arithmetic. A PanelContainer added straight to this
## CanvasLayer has no layout parent, so it took the whole screen height and had to be
## positioned by hand — which put it under the deploy bar and would have needed
## re-centring on every window resize. A full-rect root plus a CenterContainer gives the
## panel its minimum size and keeps it centred for free.
##
## The root is MOUSE_FILTER_IGNORE and only the PANEL joins the blocking-UI group, so an
## open menu swallows clicks on the card and nowhere else — a full-screen blocker would
## make the whole world unclickable while the sanction grid is up.
func _setup_sanction_menu() -> void:
	_sanction_menu = Control.new()
	_sanction_menu.name = "SanctionMenu"
	_sanction_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sanction_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sanction_menu.visible = false
	add_child(_sanction_menu)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sanction_menu.add_child(centre)

	_sanction_menu_panel = PanelContainer.new()
	_sanction_menu_panel.name = "Panel"
	_sanction_menu_panel.add_to_group(SELECTION_BLOCKING_UI_GROUP)
	centre.add_child(_sanction_menu_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_sanction_menu_panel.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "Sanction Sanction grid"
	column.add_child(title)

	_unlock_buttons.clear()
	if _sanction_grid != null:
		column.add_child(_build_sanction_grid())

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = (
		"Own %d in a tier to open the next. An upgrade replaces what it upgrades."
		% SanctionGrid.UNLOCKS_TO_OPEN_NEXT_TIER
	)
	column.add_child(hint)


func _build_sanction_grid() -> GridContainer:
	var width: int = maxi(1, _sanction_grid.used_columns())
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = width + 1  # a tier label, then one cell per family
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for tier: int in SanctionGrid.NUM_TIERS:
		var label := Label.new()
		label.text = "T%d" % tier
		label.custom_minimum_size = Vector2(28.0, 0.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)
		for a_column: int in width:
			var entry: SanctionGrid.Entry = _sanction_grid.cell(tier, a_column)
			if entry == null:
				# A spacer, not a skipped cell: the columns have to stay lined up.
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(140.0, 32.0)
				grid.add_child(gap)
				continue
			var btn: VerboseTooltipButton = _build_sanction_button(entry, false)
			grid.add_child(btn)
			_unlock_buttons.append({"button": btn, "entry": entry})
	return grid


## Show or hide the sanction grid. Arming is dropped on the way in: the menu is a planning
## surface, and a right-click made while it is open should not fire a sanction the
## player armed before opening it.
func toggle_sanction_menu() -> void:
	if _sanction_menu == null:
		return
	_sanction_menu.visible = not _sanction_menu.visible
	if _sanction_menu.visible:
		_pending_sanction = null


## What each cell says. Every locked state NAMES what is missing rather than reading
## "locked", because the player can act on each of them differently: buy the parent,
## buy anything in the tier above, or wait for dominion.
func _paint_unlock_button(a_btn: Button, a_entry: SanctionGrid.Entry) -> void:
	var label: String = a_entry.sanction.sanction_name
	match _sanction_grid.unmet_requirement(a_entry):
		SanctionGrid.Requirement.MET:
			a_btn.text = "%s — %d dom" % [label, a_entry.unlock.dominion_cost]
			a_btn.disabled = not _sanction_grid.can_afford(a_entry)
		SanctionGrid.Requirement.ALREADY_OWNED:
			# "Upgraded" rather than "owned": the cell is bought and off the bar, and the
			# player needs to know which of those two things happened to it.
			if _sanction_grid.is_superseded(a_entry):
				a_btn.text = "%s — upgraded" % label
			else:
				a_btn.text = "%s ✓" % label
			a_btn.disabled = true
		SanctionGrid.Requirement.PARENT_LOCKED:
			a_btn.text = "%s — needs %s" % [label, a_entry.unlock.parent.sanction.sanction_name]
			a_btn.disabled = true
		SanctionGrid.Requirement.TIER_LOCKED:
			a_btn.text = (
				"%s — %d more in T%d"
				% [label, _sanction_grid.unlocks_needed_to_open(a_entry.tier()), a_entry.tier() - 1]
			)
			a_btn.disabled = true


func _on_unlock_button_pressed(a_entry: SanctionGrid.Entry) -> void:
	var stream: OrderStream = _order_stream()
	if stream == null:
		_sanction_grid.try_unlock(a_entry)
		return
	stream.submit(
		PlayerOrder.new(
			PlayerOrder.Kind.UNLOCK_SANCTION,
			_commander().id,
			{"tier": a_entry.tier(), "column": a_entry.column()}
		)
	)


#endregion
#endregion

#region Debug placement
## The roster entry the debug spawner has armed (see DebugRoster), or {} when none. Placing
## it is free, and bypasses the selection entirely: the piece is put down directly rather
## than ordered from anyone. See gdd/systems/ux/ui/debug-mode.md §The piece spawner.
var _debug_piece: Dictionary = {}

## An instance of the armed piece's scene, NEVER added to the tree: what the placement check
## and the ghost read, like Commander's build-preview instances.
var _debug_piece_source: Entity = null


## Arm `a_entry` for placement: the next world command puts one down.
func arm_debug_piece(a_entry: Dictionary) -> void:
	disarm_command()
	var scene: PackedScene = load(a_entry["scene"]) as PackedScene
	_debug_piece_source = scene.instantiate() as Entity if scene != null else null
	if _debug_piece_source == null:
		return
	_debug_piece = a_entry


func is_debug_piece_armed() -> bool:
	return not _debug_piece.is_empty()


## The armed debug piece's roster entry, or {}.
func armed_debug_piece() -> Dictionary:
	return _debug_piece


func disarm_debug_piece() -> void:
	_debug_piece = {}
	if _debug_piece_source != null:
		_debug_piece_source.free()
		_debug_piece_source = null


## The commander a placed piece is given to: the local player, whoever that is at the time.
func debug_placement_owner() -> Commander:
	return _commander()


## Put the armed piece down under the cursor, if it fits there; otherwise nothing happens,
## with no message. The additive modifier keeps it armed for the next one.
func _place_debug_piece() -> void:
	var owner_commander: Commander = debug_placement_owner()
	if (
		map == null
		or owner_commander == null
		or not DebugPlacement.admits(_debug_piece_source, command_message)
	):
		return
	if _scenario != null:
		_scenario.note_debug_change("debug piece placed")
	DebugPlacement.spawn(
		load(_debug_piece["scene"]) as PackedScene,
		map,
		owner_commander,
		command_message.xz_position
	)
	if not additive_latched:
		disarm_command()


## The ghost of an armed debug FIXTURE; a figure has none.
func _update_debug_preview() -> void:
	var owner_commander: Commander = debug_placement_owner()
	var is_fixture: bool = _debug_piece_source.spawns_deployed()
	var centroid: Variant = (
		_footprint_centroid_of(_debug_piece_source, command_message.xz_position)
		if is_fixture
		else null
	)
	if centroid == null or owner_commander == null:
		if _build_preview != null and is_instance_valid(_build_preview):
			_build_preview.visible = false
		return
	var key: String = "debug:" + String(_debug_piece["scene"])
	var team_color: Color = Entity.TEAM_COLOR_MAP.get(owner_commander.id, Color.WHITE)
	if (
		_build_preview == null
		or not is_instance_valid(_build_preview)
		or _build_preview_tool_type != key
	):
		_clear_build_preview(key)
		_add_ghost_visual(_build_preview, _debug_piece_source, team_color)
	_build_preview.global_position = centroid
	_tint_build_preview(team_color, not DebugPlacement.admits(_debug_piece_source, command_message))
	_build_preview.visible = true


#endregion

#region Deployment drops
## The drop armed from the deployment panel or its hotkey, or NO_DROP. Placed like the build
## ghost — right-click lands it, left-click cancels — but with no caster and nothing selected:
## the commander casts it (see Deployment, and starting-formations.md §Presentation and
## targeting).
var _armed_drop: int = NO_DROP
const NO_DROP: int = -1

## An instance of the armed drop's structure, NEVER added to the tree: what the ghost copies,
## like the debug spawner's source.
var _drop_source: Entity = null

## The Deployment the panel and the bars are bound to; tracked so a rebind can disconnect it.
var _bound_deployment: Deployment = null
var _deployment_panel: DeploymentPanel = null

## Hotkey action -> the drop it arms.
const DROP_ACTIONS: Dictionary = {
	&"deploy_command_centre": Deployment.Drop.COMMAND_CENTRE,
	&"deploy_extractor": Deployment.Drop.EXTRACTOR,
}

## What the error line says for a drop that may not land under the cursor.
const DROP_REFUSALS: Dictionary = {
	Deployment.Verdict.OK: "",
	Deployment.Verdict.NO_CHARGE: "No drop left",
	Deployment.Verdict.OUT_OF_VISION: "Must land where you can see",
	Deployment.Verdict.BAD_FOOTPRINT: "Can't land there",
	Deployment.Verdict.UNITS_IN_THE_WAY: "Enemy units in the way",
}


func armed_drop() -> int:
	return _armed_drop


func is_drop_armed() -> bool:
	return _armed_drop != NO_DROP


## Arm `a_drop` if the local player holds a charge of it; the next right-click lands it.
func arm_drop(a_drop: Deployment.Drop) -> void:
	var deployment: Deployment = _bound_deployment
	if deployment == null or not deployment.has_charge(a_drop):
		return
	var scene: PackedScene = deployment.preview_scene(a_drop)
	if scene == null:
		return
	disarm_command()
	_drop_source = scene.instantiate() as Entity
	_armed_drop = a_drop


func disarm_drop() -> void:
	_armed_drop = NO_DROP
	if _drop_source != null:
		_drop_source.free()
		_drop_source = null


## Land the armed drop under the cursor, if it may land there. What it puts in play is selected
## unless the additive modifier is held; the modifier keeps the drop armed only while it has a
## charge left, since it never keeps armed a tool that cannot be used again.
func _place_drop() -> void:
	var drop: Deployment.Drop = _armed_drop as Deployment.Drop
	var stream: OrderStream = _order_stream()
	if stream == null:
		var landed: Array[Actor] = _bound_deployment.drop(drop, _drop_aim())
		if landed.is_empty():
			return
		_select_landed(landed, additive_latched)
		_end_drop_arming(_bound_deployment.charges(drop))
		return
	# Judged now, so a refused click keeps the drop armed and says why; landing is the order's.
	if _bound_deployment.verdict(drop, _drop_aim()) != Deployment.Verdict.OK:
		return
	var aim: Vector2 = _drop_aim()
	stream.submit(
		PlayerOrder.new(
			PlayerOrder.Kind.DROP,
			_commander().id,
			{"drop": int(drop), "aim": [aim.x, aim.y], "queue": additive_latched}
		)
	)
	# The charge is spent when the order lands, so one fewer is what remains after it.
	_end_drop_arming(_bound_deployment.charges(drop) - 1)


## Select what a drop put in play, unless the additive modifier was held when it was given.
func _select_landed(a_landed: Array, a_is_additive: bool) -> void:
	if a_landed.is_empty() or a_is_additive:
		return
	deselect()
	_select_units(a_landed)


## After a drop: the modifier keeps the drop armed only while a charge is left, since it never
## keeps armed a tool that cannot be used again.
func _end_drop_arming(a_charges_left: int) -> void:
	if not additive_latched or a_charges_left <= 0:
		disarm_command()
	else:
		upate_hud_buttons()


## Where the armed drop is aimed: the ground under the cursor, never the unit under it. A drop may
## be aimed over the slot's own units — they step off — so it must not snap to one of them.
func _drop_aim() -> Vector2:
	return VU.in_xz(command_message.world_position)


## The drop a key press arms, or NO_DROP.
func _drop_for_event(a_event: InputEvent) -> int:
	for action: StringName in DROP_ACTIONS:
		if InputMap.has_action(action) and a_event.is_action_pressed(action):
			return DROP_ACTIONS[action]
	return NO_DROP


func _drop_refusal_message() -> String:
	return DROP_REFUSALS[_bound_deployment.verdict(_armed_drop as Deployment.Drop, _drop_aim())]


## The ghost of the armed drop, reddened where it may not land.
func _update_drop_preview() -> void:
	var commander: Commander = _commander()
	var centroid: Variant = _footprint_centroid_of(_drop_source, _drop_aim())
	if centroid == null or commander == null:
		if _build_preview != null and is_instance_valid(_build_preview):
			_build_preview.visible = false
		return
	var key: String = "drop:%d" % _armed_drop
	var team_color: Color = Entity.TEAM_COLOR_MAP.get(commander.id, Color.WHITE)
	if (
		_build_preview == null
		or not is_instance_valid(_build_preview)
		or _build_preview_tool_type != key
	):
		_clear_build_preview(key)
		_add_ghost_visual(_build_preview, _drop_source, team_color)
	_build_preview.global_position = centroid
	_tint_build_preview(team_color, _drop_refusal_message() != "")
	_build_preview.visible = true


## Follow `a_deployment` — the local player's, or null when it deploys some other way: build the
## panel while it holds a drop, and hide the economy bars until its command centre lands.
func _bind_deployment(a_deployment: Deployment) -> void:
	if _bound_deployment != null and _bound_deployment.changed.is_connected(_on_deployment_changed):
		_bound_deployment.changed.disconnect(_on_deployment_changed)
	_bound_deployment = a_deployment
	if _bound_deployment != null:
		_bound_deployment.changed.connect(_on_deployment_changed)
	_on_deployment_changed()


func _on_deployment_changed() -> void:
	var deployment: Deployment = _bound_deployment
	var is_deploying: bool = deployment != null and not deployment.is_spent()
	if is_deploying and _deployment_panel == null:
		_deployment_panel = DeploymentPanel.new()
		_deployment_panel.controller = self
		_deployment_panel.deployment = deployment
		add_child(_deployment_panel)
	elif not is_deploying and _deployment_panel != null:
		_deployment_panel.queue_free()
		_deployment_panel = null
	if _deployment_panel != null:
		_deployment_panel.deployment = deployment
	# A look-only HUD shows no commander's means at all (_apply_look_only_layout).
	var has_economy: bool = (
		not is_look_only and (deployment == null or deployment.has_landed_command_centre())
	)
	for bar: Variant in [_dominion_bar, _energy_bar, _infrastructure_bar]:
		if bar != null:
			bar.visible = has_economy
#endregion
