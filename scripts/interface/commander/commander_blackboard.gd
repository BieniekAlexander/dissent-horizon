class_name CommanderBlackboard
extends RefCounted

## CommanderBlackboard — a commander's persistent, fog-limited BELIEF about the
## enemy, plus the visual memory ("snapshots") of scouted structures.
##
## Owned and ticked by Commander (see Commander._physics_process), so it serves
## BOTH player and bot commanders. Each update folds in what the commander
## currently SEES (Commander.visible_enemies) and remembers it after losing
## sight, so decisions can use believed enemy positions/composition rather than
## only what's on screen this instant. Two retention rules (per the design):
##   • STRUCTURES persist indefinitely (they don't move). A structure belief is
##     dropped only when the commander regains vision of its last-known spot and
##     the structure is no longer there — i.e. verified destroyed on revisit,
##     never by omnisciently checking if the node was freed.
##   • UNITS expire BLACKBOARD_EXPIRATION seconds after their last sighting — an old
##     sighting goes stale because units move (or die) out of view.
##
## Every entry carries the entity's last-known world location.
##
## The Snapshot layer (see Snapshot / _snapshots) is the VISUAL counterpart: for
## each scouted structure-at-a-cell it keeps a duplicated MeshVisual (the entity's
## 3D model) that renders the remembered building while the real one is fogged, and
## is reconciled/deleted when the commander re-scouts that cell. Snapshots carry no
## SELECTION collider, so the cursor and box-select never detect them (the controls
## layer relies on this — a fogged structure must not be targetable).

## Seconds a unit belief survives without a fresh sighting before it lapses.
const BLACKBOARD_EXPIRATION: float = 180.0

## Multiplicative darkening applied to a snapshot's MeshVisual so a remembered (fogged)
## structure reads as dimmed — "under the fog of war" — versus the full-brightness live
## building. Multiplies the snapshot's already-team-tinted albedo, so team colours are kept,
## just darker. ~50% brightness with a slight cool bias, roughly matching the terrain fog's
## explored dimming.
const SNAPSHOT_FOG_TINT: Color = Color(0.45, 0.45, 0.55)


## One remembered enemy entity.
class Entry:
	var instance_id: int
	var type: StringName                # piece id (see EntityIds)
	var is_structure: bool
	var last_known_location: Vector3
	var last_seen_time: float           # seconds (Commander.seconds_elapsed) of last sighting
	var entity: Commandable             # live ref; may become invalid (use is_instance_valid)


## One remembered structure image at a specific grid cell. A single structure may
## have several snapshots (one per cell it was ever scouted at — the "it moved and
## was re-seen elsewhere" case), so snapshots are keyed by (structure_id, cell).
class Snapshot:
	var structure_id: int
	var cell: Vector2i                  # representative grid cell (map.world_to_grid of last-known pos)
	# Live ref to the real structure. Entity (NOT Commandable) — Shelters/Deposits are
	# structures that derive from Entity. is_instance_valid may go false on destruction.
	var entity: Entity
	var node: Node3D                    # duplicated MeshVisual, world-positioned in the container
	# Captured at creation (stays valid after `entity` is freed): a Deposit yields its
	# cell to any structure overlaid on it (a Mine) when both are remembered — see
	# _suppress_overlapping_snapshots.
	var is_deposit: bool


var _commander: Commander
var _entries: Dictionary = {}           # instance_id -> Entry
var _snapshots: Dictionary = {}         # "id:cell" -> Snapshot
## Lazily created Node3D under the map that parents every snapshot MeshVisual. Freed
## by free_visuals() (called from Commander's PREDELETE).
var _snapshot_container: Node3D = null


func _init(a_commander: Commander) -> void:
	_commander = a_commander


## Fold current vision into the belief and age it out. This is the AI-only layer
## (only bots read believed()), and its expensive step — visible_enemies()'s
## physics queries — is why Commander throttles this call to ~5 Hz. The player-
## facing snapshot layer is NOT updated here; see _ensure_snapshots() /
## refresh_snapshots(), both driven every physics frame.
func update() -> void:
	var now: float = _commander.seconds_elapsed()

	# 1. Refresh / add an entry for every enemy currently in view.
	var visible_ids: Dictionary = {}
	for e: Commandable in _commander.visible_enemies():
		visible_ids[e.get_instance_id()] = true
		_upsert(e, now)

	# 2. Age out beliefs. Structures: drop only when we can see their spot and they
	#    aren't there (verified gone). Units: drop once the sighting is stale.
	for id: int in _entries.keys():
		var entry: Entry = _entries[id]
		if entry.is_structure:
			if not visible_ids.has(id) and _commander.has_vision_at(entry.last_known_location):
				_entries.erase(id)
		elif now - entry.last_seen_time > BLACKBOARD_EXPIRATION:
			_entries.erase(id)


## All believed enemy entities (persistent structures + unexpired units).
func believed() -> Array:
	return _entries.values()

## Believed enemy structures (last-known locations; persist until verified gone).
func believed_structures() -> Array:
	return _entries.values().filter(func(e: Entry): return e.is_structure)

## Believed enemy units (last-known locations; expire after BLACKBOARD_EXPIRATION).
func believed_units() -> Array:
	return _entries.values().filter(func(e: Entry): return not e.is_structure)


func _upsert(e: Commandable, now: float) -> void:
	var id: int = e.get_instance_id()
	var entry: Entry = _entries.get(id)
	if entry == null:
		entry = Entry.new()
		entry.instance_id = id
		entry.type = e.id
		entry.is_structure = e.has_node("Structure")
		_entries[id] = entry
	entry.entity = e
	entry.last_known_location = e.global_position
	entry.last_seen_time = now


#region Structure snapshots (visual fog-of-war memory)
## Free every snapshot node and the container. Called from Commander's PREDELETE
## so the visuals don't outlive the commander (the container lives under the map,
## which may outlive this RefCounted).
func free_visuals() -> void:
	_snapshots.clear()
	if _snapshot_container != null and is_instance_valid(_snapshot_container):
		_snapshot_container.queue_free()
	_snapshot_container = null


## Create a snapshot for each currently-scouted foreign structure that lacks one at
## its present cell. Runs EVERY physics frame (from refresh_snapshots), NOT on the
## throttled belief update: creation is cheap (fog-pixel lookups over a handful of
## structures, no physics queries) and player-facing, so a newly-revealed structure
## is remembered the same frame fog shows it — no lag before it can be re-fogged.
## Reads visible_foreign_structures (NOT the enemy belief) so NEUTRAL structures —
## mines, mountains — are remembered too, not just enemy-owned ones.
func _ensure_snapshots() -> void:
	var map: Map = _commander.map
	if map == null:
		return
	for s: Entity in _commander.visible_foreign_structures():
		var cell: Vector2i = map.world_to_grid(VU.inXZ(s.global_position))
		var key: String = _snapshot_key(s.get_instance_id(), cell)
		if not _snapshots.has(key):
			_create_snapshot(s, cell, key)


## Create any missing snapshots, then reconcile every snapshot against present
## vision and set its visibility. Called EVERY physics frame by Commander (cheap —
## a handful of structures), AFTER fog has refreshed each real structure's `visible`.
## A snapshot's visibility is the exact complement of its real counterpart's fog
## state, so the swap is gap-free: the frame fog hides the real structure, the
## snapshot shows; the frame fog reveals it, the snapshot hides. A snapshot is
## deleted once its cell is re-scouted and the real structure is gone (destroyed) or
## has moved off the cell.
func refresh_snapshots() -> void:
	var map: Map = _commander.map
	if map == null:
		return
	# Creation runs here (not on the throttled belief update) so it stays in step
	# with the fog reveal that this same method reconciles against.
	_ensure_snapshots()
	var is_viewer: bool = _commander_is_active_viewer()
	for key: String in _snapshots.keys():
		var snap: Snapshot = _snapshots[key]
		if not is_instance_valid(snap.node):
			_snapshots.erase(key)
			continue
		var real_alive: bool = is_instance_valid(snap.entity) and snap.entity.is_inside_tree()
		if _commander.has_vision_at(snap.node.global_position):
			# The cell is scouted again: keep the memory only while the real structure
			# is still there. Otherwise it's stale — destroyed, or moved away.
			var still_here: bool = real_alive \
				and map.world_to_grid(VU.inXZ(snap.entity.global_position)) == snap.cell
			if not still_here:
				snap.node.queue_free()
				_snapshots.erase(key)
				continue
		# Show the remembered image only for the viewed commander, and only while the
		# real structure is hidden. Keying off the real node's own fog-driven `visible`
		# (rather than recomputing vision) is what guarantees the gap-free swap. When
		# the structure has been destroyed but its cell is still fogged, keep showing.
		if real_alive:
			snap.node.visible = is_viewer and not snap.entity.visible
		else:
			snap.node.visible = is_viewer

	# Structures can stack on one cell (a Mine built on a Deposit), so two remembered
	# images could otherwise render on top of each other. Collapse each cell to a single
	# visible snapshot.
	if is_viewer:
		_suppress_overlapping_snapshots()


## Enforce "at most one visible snapshot per grid cell". Among the snapshots that want
## to show at the same cell this frame, keep only the highest-priority one visible and
## hide the rest — so a Mine's remembered image, not the Deposit it was built on, is
## what renders.
func _suppress_overlapping_snapshots() -> void:
	var winner_by_cell: Dictionary = {}   # Vector2i -> Snapshot
	for key: String in _snapshots:
		var snap: Snapshot = _snapshots[key]
		if not is_instance_valid(snap.node) or not snap.node.visible:
			continue
		var current: Snapshot = winner_by_cell.get(snap.cell)
		if current == null:
			winner_by_cell[snap.cell] = snap
		elif _snapshot_outranks(snap, current):
			current.node.visible = false
			winner_by_cell[snap.cell] = snap
		else:
			snap.node.visible = false


## True when `a` should be the single visible snapshot on a shared cell, beating `b`. A
## Deposit yields to any non-Deposit overlaying it (the Mine wins); equal-rank ties break
## by instance id so the choice is stable frame-to-frame (no flicker).
func _snapshot_outranks(a: Snapshot, b: Snapshot) -> bool:
	var pa: int = 0 if a.is_deposit else 1
	var pb: int = 0 if b.is_deposit else 1
	if pa != pb:
		return pa > pb
	return a.structure_id > b.structure_id


func _create_snapshot(structure: Entity, cell: Vector2i, key: String) -> void:
	var visual := structure.get_node_or_null("MeshVisual") as MeshVisual
	if visual == null:
		return
	if _snapshot_container == null or not is_instance_valid(_snapshot_container):
		_snapshot_container = Node3D.new()
		_snapshot_container.name = "StructureSnapshots_%d" % _commander.id
		_commander.map.add_child(_snapshot_container)

	# Duplicate the MeshVisual subtree (the 3D model, not the whole entity), so the snapshot has
	# no SELECTION collider. On being added, the copy's MeshVisual._ready re-gathers its OWN
	# override materials from the source's already-team-tinted ones, so it keeps the tint without
	# sharing materials with — or being re-driven by — the live structure. Match the real mesh's
	# world transform so the remembered image sits exactly where the structure did (offset/scale/
	# facing). It's a static memory, so stop its per-frame processing.
	var node := visual.duplicate() as MeshVisual
	_snapshot_container.add_child(node)
	node.global_transform = visual.global_transform
	node.set_process(false)
	node.set_physics_process(false)
	node.visible = false
	# Darken it so it reads as "under the fog of war". The copy's captured design albedo is the
	# already-team-tinted colour, so this multiply keeps the team hue and just dims it.
	node.set_team_color(SNAPSHOT_FOG_TINT)

	var snap := Snapshot.new()
	snap.structure_id = structure.get_instance_id()
	snap.cell = cell
	snap.entity = structure
	snap.node = node
	snap.is_deposit = structure is Deposit
	_snapshots[key] = snap


func _snapshot_key(structure_id: int, cell: Vector2i) -> String:
	return "%d:%s" % [structure_id, cell]


## Mirrors fog.gd's active-fog resolution: snapshots render only for the commander
## whose view is currently on screen, and never under the omniscient spectator or
## the hold-Space debug reveal (both of which show real structures directly).
func _commander_is_active_viewer() -> bool:
	var active_id: int = Fog.active_commander_id
	if active_id == -2:
		return false
	if Input.is_action_pressed("debug_info"):
		return false
	var viewer_id: int = active_id if active_id >= 1 else RTSController.PLAYER_COMMANDER_ID
	return _commander.id == viewer_id
#endregion
