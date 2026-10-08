class_name StatusVisuals
extends Node3D

## StatusVisuals — the one place a commandable's CONDITION is turned into a look.
##
## "Condition" means everything about a unit that is true of it right now and can change
## while it stands there: whether stealth is hiding it, which StatusEffects are acting on
## it, and what rank it has earned. Deliberately NOT the construction lifecycle — that is
## Actor._apply_construction_visuals' business, and the two write separate channels
## on MeshVisual (see its STATUS_* constants) precisely so they can never overwrite each
## other. A half-built barracks can be EMP'd; a stealthed unit is no less finished for
## fading.
##
## It owns two kinds of output:
##   • MESH CHANNELS — MeshVisual.set_status_opacity / set_status_tint, composed from the
##     stealth state and from every active effect's `host_tint`.
##   • FLOATING BILLBOARDS — camera-facing icons above the model, in three fixed rows:
##     the veterancy chevrons, then the action badge and one icon per active effect that
##     declares an `indicator_icon` (plus the hold-fire badge), then the CAPACITY PIPS
##     (garrison seats, charged-ammo rounds).
##     The ROWS are billboarded as a whole, not just the icons on them — see
##     _face_rows_at_camera.
##
## THE EFFECTS DO NOT DRAW THEMSELVES. A StatusEffect only DECLARES how it makes its host
## look (`host_tint`, `indicator_icon`, `indicator_blink_hz`; see status_effect.gd), and
## this component composes those declarations. That is what keeps two effects on one unit
## from fighting over the same material — and what lets emp.tscn and bio_stun.tscn, which
## are the same script separated only by a frame mask, look completely different without a
## subclass between them.
##
## This replaces the billboard-sprite era's visual code, which lived inline in
## Actor._process and wrote Sprite.modulate directly — a channel it shared with the
## team tint and the construction fade, which is why that block had to rewrite all three
## every single frame to stop them clobbering one another.

#region Constants
## Veterancy rank art, indexed by Veterancy.Level (NONE has no icon). One chevron, two,
## three — a rank badge is a game-wide constant, not a per-piece authoring decision, so
## these are consts here rather than exports on every unit scene.
const VETERANCY_ICONS: Array[Texture2D] = [
	null,
	preload("res://assets/interface/veterancy_1.svg"),
	preload("res://assets/interface/veterancy_2.svg"),
	preload("res://assets/interface/veterancy_3.svg"),
]

## Capacity pip art. One pair, two meanings — hollow = a slot with nothing in it, solid =
## a slot that is filled — so a garrison and a charged clip read the same way with only
## the token changing. See the CAPACITY PIPS region for what they are and who sees them.
const SLOT_EMPTY: Texture2D = preload("res://assets/interface/slot_empty.svg")
const SLOT_FILLED: Texture2D = preload("res://assets/interface/slot_filled.svg")
const AMMO_EMPTY: Texture2D = preload("res://assets/interface/ammo_empty.svg")
const AMMO_FILLED: Texture2D = preload("res://assets/interface/ammo_filled.svg")

## Hold fire's badge, shared with its condition card (ConditionRow) so the two read as one.
const HOLD_FIRE_ICON: Texture2D = preload("res://assets/interface/status_hold_fire.svg")

## Over a structure its commander cannot power, whose weapons or abilities have gone dark
## (Actor.is_unpowered). See _shows_unpowered.
const UNPOWERED_ICON: Texture2D = preload("res://assets/interface/status_unpowered.svg")

## Over a BLUEPRINT whose purchase is still waiting for energy: the site is ordered, and nothing
## will start there until it is paid for. The one badge a blueprint carries, and only for its
## own side — see _shows_awaiting_funds.
const AWAITING_FUNDS_ICON: Texture2D = preload("res://assets/interface/status_awaiting_funds.svg")

## Action badges: what the unit is DOING, flashing while it does it — the interim stand-in for
## the animations those actions will one day have (see ActionTracker). Game-wide, like the
## rank art. The rate is the one every action badge flashes at, so they read as one family.
const ACTION_BUILD_ICON: Texture2D = preload("res://assets/interface/action_build.svg")
const ACTION_UNLOAD_ICON: Texture2D = preload("res://assets/interface/action_unload.svg")
const ACTION_BLINK_HZ: float = 2.0

## Deploy-stance badges, the same interim stand-in until deploying is animated: a transition
## flashes like an action, the settled deployed stance holds steady.
const STANCE_DEPLOYING_ICON: Texture2D = preload("res://assets/interface/stance_deploying.svg")
const STANCE_DEPLOYED_ICON: Texture2D = preload("res://assets/interface/stance_deployed.svg")
const STANCE_UNDEPLOYING_ICON: Texture2D = preload("res://assets/interface/stance_undeploying.svg")

## Pips wrap onto a new row above this many, so a 12-round Clipper stays readable instead
## of drawing a line two tank-lengths wide.
const PIPS_PER_ROW: int = 8
#endregion

#region Configuration
## Clearance above the model's own top (MeshVisual.model_top_offset) for each of the three
## rows. Measured from the model rather than authored per scene, so a tall structure and a
## crouching infantryman both carry their markers just clear of themselves.
##
## The rows are at FIXED heights whether or not they are drawn: the capacity pips come and
## go with selection, and a badge that jumped down to fill the gap every time you clicked
## would read as the unit changing rather than the selection.
@export var veterancy_margin: float = 0.20
@export var status_margin: float = 0.62
@export var pip_margin: float = 0.98

## World height of a badge / status icon / capacity pip.
@export var veterancy_size: float = 0.32
@export var status_size: float = 0.44
@export var pip_size: float = 0.16

## Horizontal spacing within a row.
@export var status_spacing: float = 0.48
@export var pip_spacing: float = 0.19
#endregion

#region State
var _host: Actor = null
var _mesh_visual: MeshVisual = null
var _veterancy_sprite: Sprite3D = null
## Pool of icon sprites, grown on demand and hidden when unused — a unit gains and loses
## effects constantly, and churning nodes for it would be pure allocation.
var _status_sprites: Array[Sprite3D] = []
var _pip_sprites: Array[Sprite3D] = []
var _last_veterancy_level: int = -1
var _elapsed: float = 0.0
#endregion


#region Lifecycle
func _ready() -> void:
	_host = get_parent() as Actor
	_mesh_visual = get_parent().get_node_or_null("MeshVisual") as MeshVisual


func _process(a_delta: float) -> void:
	if Engine.is_editor_hint() or _host == null:
		return
	_elapsed += a_delta
	_face_rows_at_camera()

	# Hidden entirely: an enemy the player has no way of perceiving, or a blueprint that is
	# not on the map at all. Neither should carry a badge floating in the fog.
	var hidden: bool = _host.is_hidden_by_stealth() or _host.is_planned
	# Scanned once and passed down: this runs per entity per frame, and both consumers
	# below want the same answer.
	var effects: Array[StatusEffect] = _active_effects()

	if _mesh_visual != null:
		_mesh_visual.set_status_opacity(_stealth_opacity())
		_mesh_visual.set_status_tint(_effect_tint(effects))

	_update_veterancy(hidden)
	_update_status_icons(effects, hidden)
	_update_capacity_pips(hidden)


#endregion


#region Mesh channels
## How visible stealth leaves this unit, as a factor on the model's alpha. Carried over
## unchanged from the billboard era, pulse and all:
##   • UNSTEALTHED — fully solid, so the moment it breaks cover reads as a snap.
##   • REVEALED    — the faint pulse, for everyone: a detector has it, but only just.
##   • STEALTHED   — the same faint pulse for its OWNER (who must be able to command what
##                   it cannot be seen doing) and nothing at all for anyone else.
func _stealth_opacity() -> float:
	if _host.stealth == null:
		return MeshVisual.STATUS_OPACITY_NORMAL
	# Physics frames rather than _elapsed so the pulse keeps the cadence it had when this
	# lived in Actor._process, and so every stealthed unit on screen pulses together.
	var pulse: float = 0.3 + 0.1 * sin(Engine.get_physics_frames() / 5.0)
	match _host.stealth.state:
		Stealth.State.UNSTEALTHED:
			return MeshVisual.STATUS_OPACITY_NORMAL
		Stealth.State.REVEALED:
			return pulse
		_:
			return pulse if not _host.is_hidden_by_stealth() else 0.0


## The strongest colour shift any active effect asks for, taken PER CHANNEL as a MINIMUM
## rather than as a product: two effects each halving the host would otherwise quarter it,
## and "what colour does this unit's condition draw it" is a single reading of the unit,
## not a stack of filters. Per channel, so an EMP's black still beats a freeze's blue on
## red and green while the two agree on blue.
func _effect_tint(a_effects: Array[StatusEffect]) -> Color:
	var tint: Color = MeshVisual.STATUS_TINT_NORMAL
	for effect: StatusEffect in a_effects:
		tint = Color(
			minf(tint.r, effect.host_tint.r),
			minf(tint.g, effect.host_tint.g),
			minf(tint.b, effect.host_tint.b)
		)
	return tint


## Every StatusEffect currently acting on the host. Effects are children of the entity
## they act on (see StatusEffect.apply_to), so this is a scan of the host's own children —
## the same shape Actor.is_stunned() uses.
func _active_effects() -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	for child: Node in _host.get_children():
		if child is StatusEffect and (child as StatusEffect).is_active():
			out.append(child as StatusEffect)
	return out


#endregion


#region Orientation
## Point this node's own X axis along the camera's screen-right, so a ROW of icons is
## billboarded as a whole rather than icon by icon.
##
## Each Sprite3D already billboards itself, so a single badge was always correct. A row is
## not: its icons are placed at local X offsets, and this node inherits the entity's yaw —
## so the LINE they sit on swung round with the unit while every icon on it dutifully kept
## facing the camera. A four-pip ammo row read as four pips end-on the moment the aircraft
## banked away.
##
## Only the horizontal axis is taken from the camera. Y stays WORLD up, so the three rows
## keep stacking straight up above the model and the heights measured from
## MeshVisual.model_top_offset() still mean what they say; taking the camera's up as well
## would tilt the whole rig by the camera's pitch. That decomposition is only available
## because an RTS camera has yaw and pitch but no ROLL, which makes its right vector
## horizontal — the flatten below is belt and braces for the day one does.
func _face_rows_at_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var right: Vector3 = camera.global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	# Right-handed, so Z = X × Y. Writing global_basis rather than rotation keeps this
	# independent of whatever the entity's own facing is doing this frame.
	global_basis = Basis(right, Vector3.UP, right.cross(Vector3.UP))


#endregion


#region Floating billboards
func _update_veterancy(a_hidden: bool) -> void:
	var level: int = int(_host.veterancy.level) if _host.veterancy != null else 0
	if level != _last_veterancy_level:
		_last_veterancy_level = level
		if level > 0:
			_ensure_veterancy_sprite().texture = VETERANCY_ICONS[level]
	if _veterancy_sprite == null:
		return
	_veterancy_sprite.visible = level > 0 and not a_hidden
	_veterancy_sprite.position = Vector3(0.0, _model_top() + veterancy_margin, 0.0)


func _update_status_icons(a_effects: Array[StatusEffect], a_hidden: bool) -> void:
	# [texture, blink Hz] per icon: the action badge, every effect that declares one, then
	# hold fire.
	var icons: Array[Array] = []
	if _host.is_planned:
		# A blueprint is not on the map yet: nothing it could be DOING or suffering applies.
		if _shows_awaiting_funds():
			icons.append([AWAITING_FUNDS_ICON, 0.0])
		_place_status_icons(icons, false)
		return
	var action_icon: Texture2D = action_badge(_host.action_tracker.current_action())
	if action_icon != null:
		icons.append([action_icon, ACTION_BLINK_HZ])
	if _host.deployable != null:
		var stance_icon: Array = stance_badge(_host.deployable.stance)
		if not stance_icon.is_empty():
			icons.append(stance_icon)
	for effect: StatusEffect in a_effects:
		if effect.indicator_icon != null:
			icons.append([effect.indicator_icon, effect.indicator_blink_hz])
	if _shows_hold_fire():
		icons.append([HOLD_FIRE_ICON, 0.0])
	if _shows_unpowered():
		icons.append([UNPOWERED_ICON, 0.0])
	_place_status_icons(icons, a_hidden)


## Lay `a_icons` ([texture, blink Hz] each) out in the status row, hiding the pool's spares.
func _place_status_icons(a_icons: Array[Array], a_hidden: bool) -> void:
	var icons: Array[Array] = a_icons
	var y: float = _model_top() + status_margin
	# Centre the row on the unit, so one icon sits directly overhead and two straddle it.
	var x0: float = -0.5 * status_spacing * float(icons.size() - 1)
	for i: int in icons.size():
		var sprite: Sprite3D = _status_sprite(i)
		sprite.texture = icons[i][0]
		sprite.position = Vector3(x0 + status_spacing * float(i), y, 0.0)
		sprite.visible = not a_hidden and _blink_is_on(icons[i][1])
	for i: int in range(icons.size(), _status_sprites.size()):
		_status_sprites[i].visible = false


## The badge an action shows while it lasts, or null for one that shows none. Seen by
## everyone: what a unit is visibly doing is no secret. TODO: REPAIRING shows none — whether
## it shares the hammer or wants its own is undecided.
static func action_badge(action: ActionTracker.Action) -> Texture2D:
	match action:
		ActionTracker.Action.BUILDING:
			return ACTION_BUILD_ICON
		ActionTracker.Action.UNLOADING:
			return ACTION_UNLOAD_ICON
		_:
			return null


## The badge a deploy stance shows, as [texture, blink Hz], or empty for a mobile unit. Seen by
## everyone, like an action badge: a planted unit is plainly planted.
static func stance_badge(a_stance: Deployable.Stance) -> Array:
	match a_stance:
		Deployable.Stance.DEPLOYING:
			return [STANCE_DEPLOYING_ICON, ACTION_BLINK_HZ]
		Deployable.Stance.DEPLOYED:
			return [STANCE_DEPLOYED_ICON, 0.0]
		Deployable.Stance.UNDEPLOYING:
			return [STANCE_UNDEPLOYING_ICON, ACTION_BLINK_HZ]
		_:
			return []


## Hold fire is drawn for its OWNER only, selected or not: the owner needs to see at a glance
## which units will not shoot, and an enemy has no business knowing which will not.
func _shows_hold_fire() -> bool:
	return (
		_host.is_holding_fire
		and _host.commander_id == RTSController.PLAYER_COMMANDER_ID
		and CommandContextParser.offers_hold_fire(_host)
	)


## The unpowered badge shows on a dark structure that has something to lose by it — weapons,
## or an ability pool — and only to the LOCAL player's side: which turrets are dark is the
## enemy's to find out. Production is not switched off by the shortfall (it only slows), so a
## building that merely trains carries no badge.
func _shows_unpowered() -> bool:
	if not _host.is_unpowered():
		return false
	var viewer: Commander = _host.commander
	if viewer == null or not viewer.shares_side_with(RTSController.PLAYER_COMMANDER_ID):
		return false
	if _host.weapon_inventory != null and not _host.weapon_inventory.get_weapons().is_empty():
		return true
	var pool := _host.get_node_or_null("Abilities") as Abilities
	return pool != null and not pool.granted_abilities().is_empty()


## The awaiting-funds badge shows on a blueprint the LOCAL player's side ordered and has not
## paid for. An enemy's plans are never shown to anyone else.
func _shows_awaiting_funds() -> bool:
	var viewer: Commander = _host.commander
	return (
		_host.awaiting_funds
		and viewer != null
		and viewer.shares_side_with(RTSController.PLAYER_COMMANDER_ID)
	)


## Whether a blinking icon is in its ON half this frame. 0 Hz never blinks off — a steady
## icon is a state you can read at a glance, a blinking one is something happening now.
func _blink_is_on(a_hz: float) -> bool:
	if a_hz <= 0.0:
		return true
	return fposmod(_elapsed * a_hz, 1.0) < 0.5


## Local Y of the top of the host's model. 0.0 for an entity with no MeshVisual, which
## puts its markers at its origin rather than nowhere.
func _model_top() -> float:
	return _mesh_visual.model_top_offset() if _mesh_visual != null else 0.0


#endregion


#region Capacity pips
## A row of tokens saying how full something on this unit is: one pip per SLOT, solid for
## a slot that is filled and hollow for one that is not. Two kinds today —
##   • GARRISON SEATS (green circles), off `Garrison.capacity` / `occupied_size()`. Those
##     are OCCUPANCY, not head count, so a Collective riding a truck fills two pips — which
##     is the honest picture of what the transport has left.
##   • CHARGED ROUNDS (yellow bullets), off the loadout's charged clips. This is the piece
##     of information an aircraft's behaviour is otherwise unexplained by: a unit that
##     breaks off mid-fight to fly home is following `Loadout.is_out_of_ammo()`, and
##     without the pips the player sees only that it left.
##
## SHOWN ONLY WHILE SELECTED, and only on the local player's own units. Both are detail a
## player asks for about a specific unit rather than something to be tracked across the
## field, and drawing an enemy transport's remaining seats would hand over exactly the
## scouting information a garrison is meant to hide.
##
## PLANNED — ALLIES. The rule wants to be "yours or an ally's"; alliances are planned
## (gdd/systems/combat/target-acquisition.md §Alliances). Widen `_shows_capacity` when they
## land; it is the only place that decides.
func _update_capacity_pips(a_hidden: bool) -> void:
	var slots: Array = [] if a_hidden or not _shows_capacity() else _capacity_slots()
	var y: float = _model_top() + pip_margin
	var rows: int = int(ceil(float(slots.size()) / float(PIPS_PER_ROW)))
	for i: int in slots.size():
		var sprite: Sprite3D = _pip_sprite(i)
		sprite.texture = slots[i]
		# Row 0 is drawn HIGHEST, so the pips read top-left to bottom-right like text. The
		# slot COUNT never changes for a given unit (a capacity and a clip size are both
		# fixed), so only the textures move — a round spent flips one pip hollow in place.
		var row: int = i / PIPS_PER_ROW
		var in_row: int = mini(PIPS_PER_ROW, slots.size() - row * PIPS_PER_ROW)
		var x0: float = -0.5 * pip_spacing * float(in_row - 1)
		sprite.position = Vector3(
			x0 + pip_spacing * float(i % PIPS_PER_ROW),
			y + pip_size * 1.15 * float(rows - 1 - row),
			0.0
		)
		sprite.visible = true
	for i: int in range(slots.size(), _pip_sprites.size()):
		_pip_sprites[i].visible = false


## Whether the local player is entitled to this readout: it is theirs, and they have it
## selected. Ownership first — the cheaper test, and the one that is true far less often.
func _shows_capacity() -> bool:
	return (
		_host.commander_id == RTSController.PLAYER_COMMANDER_ID
		and _host.selectable != null
		and _host.selectable.is_selected()
	)


## The pip textures to draw, in order: garrison seats then charged rounds. Empty for a
## unit that has neither, which is almost all of them.
func _capacity_slots() -> Array:
	var out: Array = []
	var garrison: Garrison = _host.garrison
	if garrison != null and garrison.capacity > 0:
		var taken: int = garrison.occupied_size()
		for i: int in garrison.capacity:
			out.append(SLOT_FILLED if i < taken else SLOT_EMPTY)
	var loadout: Loadout = _host.weapon_inventory
	if loadout != null and loadout.has_charged_weapons():
		# A blank slot between the two groups, so a host that both carries troops and reloads
		# at an airfield does not read as one run of mismatched tokens. A null texture draws
		# nothing while still taking its place in the row, which is the whole gap.
		if not out.is_empty():
			out.append(null)
		var rounds: int = loadout.charged_ammo()
		for i: int in loadout.charged_clip_size():
			out.append(AMMO_FILLED if i < rounds else AMMO_EMPTY)
	return out


#endregion


#region Sprite pool
func _ensure_veterancy_sprite() -> Sprite3D:
	if _veterancy_sprite == null:
		_veterancy_sprite = _make_sprite(veterancy_size)
	return _veterancy_sprite


func _status_sprite(a_index: int) -> Sprite3D:
	while _status_sprites.size() <= a_index:
		_status_sprites.append(_make_sprite(status_size))
	return _status_sprites[a_index]


func _pip_sprite(a_index: int) -> Sprite3D:
	while _pip_sprites.size() <= a_index:
		_pip_sprites.append(_make_sprite(pip_size))
	return _pip_sprites[a_index]


## One floating icon. Billboarded so it reads from any camera yaw, depth-test-free so a
## marker is never swallowed by the terrain or by the very building the unit is standing
## behind (the unit itself is drawn through those too — see MeshVisual's silhouette), and
## unshaded so the art's own colours survive the scene lighting.
func _make_sprite(a_height: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.render_priority = 12
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The art is authored 64px square, so this resolves to `height` world units tall.
	sprite.pixel_size = a_height / 64.0
	sprite.visible = false
	add_child(sprite)
	return sprite
#endregion
