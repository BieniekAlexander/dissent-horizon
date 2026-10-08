class_name Actor
extends Entity

## Actor — the unified base for entities that participate in the command
## system. "Units" and "structures" are both just Commandables, differing only in
## their component bags and their group memberships.
##
## - ask `is_in_group("unit")` and `is_in_group("structure")`, never a class check.
##   There is no Unit class, and `Fixture` is the footprint COMPONENT — `is Structure`
##   asks a different question than a reader expects it to. On a Actor, "structure"
##   and "fixture" coincide; code that must also reach FEATURES asks "fixture".
##
## The group memberships are derived by the spec importer from each piece's doc and written
## on its scene, so behaviour that varies between units and structures is gated by
## composition rather than by type.

#region Properties
## The order-taking component, or null on a piece that takes no orders (`commandable: false`):
## every order method below forwards to it, and is a no-op without it.
@onready var orders: Orders = get_node_or_null("Orders") as Orders
## The command queue (Orders.receiver), or null on a piece that takes no orders.
var command_receiver: CommandReceiver:
	get:
		return orders.receiver if orders != null else null
## What this piece is doing, for its animation and its action badge. Not @onready: an emitter
## may cue it before this piece has entered the tree.
var action_tracker: ActionTracker = ActionTracker.new()

## Component references — all optional. Entity declares `ownership`, `movement`,
## `selectable`, and `hurtbox`; Actor adds `production` and the
## command/combat machinery below.
## NavigationObstacle3D used for cross-team one-sided avoidance (see
## AvoidanceAgent3D for the bit-layout). Enabled and sized in _ready for units
## only (movement != null); layers are set in _on_commander_changed.
@onready var _avoidance_obstacle: NavigationObstacle3D = (
	get_node_or_null("AvoidanceObstacle") as NavigationObstacle3D
)
@onready var production: Production = get_node_or_null("Production") as Production

## Infrastructure (the "power" resource) this commandable contributes to its commander. One
## signed int: POSITIVE provides capacity, NEGATIVE consumes upkeep, 0 (the default) is
## neutral. Any commandable may carry it — unit or structure — and it counts while the piece
## is built and in play (see _sync_infrastructure).
@export var infrastructure: int = 0

## The piece this one was BUILT FROM when it is another piece made out of it (an_infrastructure
## out of a neutral building — see Repurposing), or empty. It is what the piece is priced and
## timed by, since its own id names a piece whose listed numbers belong to a different form.
var built_from: StringName = &""


## The piece id whose technology entry prices and times this one.
func pricing_id() -> StringName:
	return built_from if built_from != &"" else id


## The commander currently credited with `infrastructure`, or null. Kept rather than derived
## because the debit must go to whoever was credited, which ownership changes and teardown
## have already moved on from by the time it is due. Untyped: it may hold a freed commander.
var _infrastructure_credited_to: Variant = null

@onready
var energy_extractor: EnergyExtractor = get_node_or_null("EnergyExtractor") as EnergyExtractor
@onready var dominion_generator: DominionGenerator = (
	get_node_or_null("DominionGenerator") as DominionGenerator
)
@onready var garrison: Garrison = get_node_or_null("Garrison") as Garrison
## The airfield component, present only on structures aerial units dock at to rearm.
## Distinct from `garrison` in every way that matters — a docked aircraft stays in the
## tree, visible and selectable on its pad — so the two are separate components and a
## structure may in principle own both. See docking_bay.gd.
@onready var docking_bay: DockingBay = get_node_or_null("DockingBay") as DockingBay
## The unit-side half: present on a piece that docks at airfields. See docking.gd.
@onready var docking: Docking = get_node_or_null("Docking") as Docking
@onready var interactor: Interactor = get_node_or_null("Interactor") as Interactor
@onready var liberator: Liberator = get_node_or_null("Liberator") as Liberator
## Present on a unit that can plant itself (Deploy / Undeploy). See deployable.gd.
@onready var deployable: Deployable = get_node_or_null("Deployable") as Deployable
@onready var veterancy: Veterancy = $Veterancy

## True when the player can currently perceive this commandable — fog pixel is
## clear AND the unit is not stealthed. Written by fog.gd each physics tick for
## non-player entities; always meaningless for player-owned units (the player
## always knows where their own units are, so callers gate on commander_id first).
## Scoped to the player for now; TODO: promote to a per-commander map.
var in_sight_range: bool = false


## True while stealth is hiding this commandable from the LOCAL PLAYER completely — it is
## STEALTHED and not theirs. Its model is drawn at zero alpha, its HP bar is suppressed and
## its floating indicators are hidden, so nothing about it is on screen at all.
##
## Narrower than is_visible_to(): that asks whether a given commander can perceive this
## unit AT ALL (fog included, and answers for bots); this asks only whether STEALTH is what
## is hiding it, which is the question the drawing code has — fog is already handled for it
## by fog.gd toggling `visible`.
func is_hidden_by_stealth() -> bool:
	return (
		stealth != null
		and stealth.state == Stealth.State.STEALTHED
		and commander_id != RTSController.PLAYER_COMMANDER_ID
	)


var _command: MoveCommand:
	get:
		return command_receiver._command if command_receiver != null else null
	set(value):
		if command_receiver != null:
			command_receiver._command = value

@onready var hp_bar_fill: Sprite3D = $HPBar/HPBarFill
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
#endregion

#region Flavor text
## Short blurb shown in the HUD info panel when this is the sole selected unit
## (InfoView._single_unit_text); `verbose` replaces it while the ui_verbose action is
## held. Populated per-piece from the gdd doc's `description:`/`verbose:` keys (see
## tools/spec_import's _sync_flavor_text) — raw, WITH any `{{ action }}` placeholders
## still in place; resolved_description()/resolved_verbose() render those at read time,
## same as DialogPage.
##
## A piece that never got either key written is loud about it rather than silently
## blank: the field is stamped with the matching MISSING_* string, which IS the visible
## complaint — a player or a scene-browsing dev sees "TODO fill out this description" in
## the info panel and knows exactly what's missing, same as VerboseTooltipButton's
## MISSING_TOOLTIP. It deliberately stops there rather than also push_error/push_warning
## like VerboseTooltipButton does: that precedent is safe only because every shipped
## button already carries a tooltip, so the missing-case never fires outside its own
## dedicated test. description/verbose is a brand-new field most of the roster genuinely
## hasn't been given yet (only warlord/irregular so far), so _ready() would hit that path
## on nearly every OTHER scene GUT instantiates — and GUT's error_tracker fails a test on
## push_warning exactly as readily as push_error (both are FAILURE by default; only
## push_error is exempted from counting as an "engine error" on top of that), so there is
## no severity level here that stays loud without breaking every unrelated test that spawns
## an undocumented piece. _report_missing_flavor_text (below) prints instead, purely for a
## developer watching the console — coverage itself is tracked centrally, the same way an
## undocumented `title` already is (the importer refuses a spec with no title):
## the spec importer WARNs on a piece with no flavor text (the unit test for it was cut —
## CLAUDE.md §A unit test does not assert facts about authored content). The setter
## below still push_errors on an explicit empty assignment — that's an authored mistake,
## not a piece simply awaiting its copy, and it matches VerboseTooltipButton exactly
## because (like a button missing its tooltip) it is not expected to happen at all.
const MISSING_DESCRIPTION: String = "TODO fill out this description"
const MISSING_VERBOSE: String = "TODO fill out this verbose description"

## ids already reported this run, so a still-undocumented piece logs its complaint once
## per id rather than once per spawned instance — a cheap unit trained by the dozen would
## otherwise flood the console with the same complaint.
static var _warned_missing_description: Dictionary = {}
static var _warned_missing_verbose: Dictionary = {}

## Assigning "" substitutes MISSING_DESCRIPTION and reports it — catches an explicit
## empty assignment. The far more common case (a scene whose description was simply
## never set) never reaches this setter at all, since Godot only invokes it for a
## property the .tscn actually stores; _ready() below is the backstop for that.
##
## THE DECLARED DEFAULT IS THE PLACEHOLDER, not "", and that is load-bearing rather than
## cosmetic: overriding `script` on a node inherited from a base scene makes Godot
## re-assign every exported property to its declared default before the stored overrides
## land. With "" as the default that construction pass tripped this setter, so every
## instantiation of such a scene reported a spurious empty description — under the BASE
## scene's node name, since the rename had not happened either. `scout.tscn` is exactly
## that shape. Defaulting to the placeholder makes the pass a no-op complaint-wise while
## leaving an AUTHORED `description = ""` as loud as it ever was.
@export var description: String = MISSING_DESCRIPTION:
	set(value):
		if value.is_empty():
			push_error("Actor '%s' was given an empty description" % name)
			description = MISSING_DESCRIPTION
		else:
			description = value

## Same treatment as description, for the ui_verbose-held tier.
@export var verbose: String = MISSING_VERBOSE:
	set(value):
		if value.is_empty():
			push_error("Actor '%s' was given an empty verbose description" % name)
			verbose = MISSING_VERBOSE
		else:
			verbose = value


## `description` rendered through InputPrompt.format() — same "keep placeholders in the
## field, resolve at render time" pattern as DialogPage.resolved_acknowledge_text(). Only
## InputMap action names are recognised as placeholders today.
func resolved_description() -> String:
	return InputPrompt.format(description)


## `verbose` rendered through InputPrompt.format() — see resolved_description().
func resolved_verbose() -> String:
	return InputPrompt.format(verbose)


## Prints the "still undocumented" complaint once per piece id per run rather than once
## per spawned instance (see _warned_missing_description/_warned_missing_verbose). A plain
## print, not push_error/push_warning — see the field docs above for why this path can't
## use Godot's error/warning channel without breaking every unrelated test that happens to
## spawn an undocumented piece.
func _report_missing_flavor_text(a_field: String, a_seen: Dictionary) -> void:
	if a_seen.has(id):
		return
	a_seen[id] = true
	print("Actor id '%s' entered the tree with no %s text" % [id, a_field])


#endregion


#region Command interface
func current_command() -> MoveCommand:
	return orders.current() if orders != null else null


func get_command_chain() -> Array[MoveCommand]:
	return orders.chain() if orders != null else [] as Array[MoveCommand]


## The Garrison currently holding this unit, or null when it is out in the world.
##
## A unit inside a garrison is REMOVED FROM THE TREE, which makes it indistinguishable from a
## unit that has died to anything asking `is_inside_tree()`. It is not the same thing at all —
## one is held and coming back, the other is gone — and this is what tells them apart. Set by
## Garrison.garrison and cleared by every release path.
var garrisoned_in: Garrison = null


## Whether this unit is being held inside a garrison rather than standing in the world.
func is_garrisoned() -> bool:
	return garrisoned_in != null and is_instance_valid(garrisoned_in)


## Where this piece is in the world: its own position, or — held off the tree, where it has
## none — its host's, through any nesting of hosts.
func world_position() -> Vector3:
	if not is_garrisoned():
		return global_position
	var host: Actor = garrisoned_in.get_parent() as Actor
	return host.world_position() if host != null else global_position


func has_command() -> bool:
	return current_command() != null


func clear_command() -> void:
	update_commands(null)


## Give this piece orders (Orders.update_commands); a no-op on a piece that takes none.
func update_commands(
	a_commands: Variant, a_add_to_queue: bool = false, a_prepend: bool = false
) -> void:
	if orders != null:
		orders.update_commands(a_commands, a_add_to_queue, a_prepend)


## `a_commands` — one order or a list of them, as update_commands takes it — as a list.
static func _as_orders(a_commands: Variant) -> Array[MoveCommand]:
	var orders: Array[MoveCommand] = []
	if a_commands is MoveCommand:
		orders.append(a_commands)
	elif a_commands is Array:
		orders.assign(a_commands)
	return orders


func load_destination(a_command: MoveCommand) -> void:
	if orders != null:
		orders.load_destination(a_command)


#endregion


#region Weapons readiness
## Whether this commandable may use its weapons at all right now.
##
## AN AERIAL UNIT ON THE GROUND CANNOT SHOOT, and being harmless on the deck is the other half
## of being a GROUND target while parked there. A FLIGHT-STATE question (`is_airborne`), not a
## targeting one (`Entity.is_air_target`) — the two agree for an aircraft and nowhere else.
## Ground units are untouched: they carry no Aerial.
## Why: gdd/systems/combat/aerial-operations/attack-runs.md §The attack run, and
## gdd/systems/combat/target-acquisition.md.
func can_use_weapons() -> bool:
	if is_unpowered():
		return false
	# A called-in aircraft's guns are cold until it is on station (Sortie).
	var sortie: Sortie = Sortie.of(self)
	if sortie != null and not sortie.can_use_weapons():
		return false
	return aerial == null or aerial.is_airborne()


## True while this piece is a STRUCTURE its commander cannot power — infrastructure upkeep
## exceeds capacity (Commander.is_infrastructure_strained).
##
## An over-subscribed network switches its BUILDINGS off: no weapons, and no abilities
## either, passive or active (see Abilities.is_operational). The building still stands,
## still occupies its cells, is still a target, and still produces at the reduced rate
## strain already imposed — going dark is what the shortfall costs, and building an
## infrastructure provider is the whole remedy.
##
## UNITS ARE UNTOUCHED. Strain is a fact about buildings drawing more than the network
## supplies; an army in the field does not stop shooting because a power plant was lost.
## Why: gdd/systems/macroeconomics/production-and-economy.md §Insufficient infrastructure.
## `ownership` is checked before `commander` is read: an OUT-OF-TREE instance (a build
## preview, a scene instantiated in a test) never ran its @onready, so the component is null
## and the property getter would error rather than answer. Nothing unowned is unpowered.
func is_unpowered() -> bool:
	return (
		is_in_group("structure")
		and ownership != null
		and commander != null
		and commander.is_infrastructure_strained()
	)


## Show or hide the marker saying this unit is what an armed single-unit ability would act on
## (see RTSController._update_ability_target). Optional node: a piece scene that does not
## inherit commandable.tscn simply has no marker.
func set_ability_targeted(a_targeted: bool) -> void:
	var marker := get_node_or_null("TargetIndicator") as Node3D
	if marker != null:
		marker.visible = a_targeted


## An empty unit stands down the order that only made sense with something to shoot —
## pushing it into the queue, not throwing it away, so it resumes once the unit is rearmed.
##
## UNCONDITIONAL — before any question of where to rearm. An Attack this unit cannot carry
## out is worth stopping on its own account, whether or not it owns an airfield to go home
## to; otherwise a dry aircraft with nowhere to rearm flies at its target forever. Ordinary
## units are untouched, since is_out_of_ammo() is false for any loadout with nothing
## CHARGED in it (see Loadout.is_out_of_ammo).
func _defer_unshootable_orders() -> void:
	if weapon_inventory == null or not weapon_inventory.is_out_of_ammo() or orders == null:
		return
	command_receiver.defer_ammo_dependent_commands()


#endregion


#region Rally
## True when units produced or released by this commandable (Production
## training a unit, or Garrison evacuating occupants) should be given an
## initial destination to move toward. Covers structures that train units and
## any commandable — structure or mobile unit — that can hold occupants in a
## Garrison (e.g. a transport).
func can_rally() -> bool:
	return (production != null and production.trains_units()) or garrison != null


## The pre-issued orders a stationary producer hands to what it makes (Orders.rally_commands);
## empty on a piece that takes no orders.
var rally_commands: Array[MoveCommand]:
	get:
		return orders.rally_commands if orders != null else [] as Array[MoveCommand]
	set(value):
		if orders != null:
			orders.rally_commands = value


func set_rally(a_command: MoveCommand) -> void:
	if orders != null:
		orders.set_rally(a_command)


func append_rally(a_command: MoveCommand) -> void:
	if orders != null:
		orders.append_rally(a_command)


func clear_rally() -> void:
	if orders != null:
		orders.clear_rally()


## What a unit produced or released here should inherit (Orders.rally_chain).
func rally_chain() -> Array[MoveCommand]:
	return orders.rally_chain() if orders != null else [] as Array[MoveCommand]


## The heading a produced or released unit is biased toward (Orders.rally_destination).
func rally_destination() -> MoveCommand:
	return orders.rally_destination() if orders != null else null


#endregion

#region Structure state
## These were on Structure before the collapse. Kept on Actor so the
## scene script can stay generic; readers gate on group membership or on the
## presence of the component that exposes the related behavior (e.g. Production).
var build_progress: float = 1.
## Construction progress a freshly-placed structure starts at (see begin_construction).
const INITIAL_BUILD_PROGRESS: float = 0.1
## Fraction of max_health a freshly-placed structure starts with.
const INITIAL_HEALTH_FACTOR: float = 0.1
## Emitted whenever build_progress changes, so visuals (construction alpha / train
## bar) could update reactively rather than polling.
signal build_progress_changed(progress: float)
## True when this entity is fully constructed. Units are always built; structures
## become built once build_progress reaches 1.0 (set to INITIAL_BUILD_PROGRESS by
## Build.fulfill_action, ticked up by Repair, defaulting to 1.0 for editor-placed
## structures).
var is_built: bool:
	get:
		return not is_in_group("structure") or build_progress >= 1.0


## A structure sees only once it is UP — a foundation is not a watchtower yet, however far
## its finished form will see. Same rule as its other powers below.
func grants_vision() -> bool:
	return super() and is_built


## A structure is cover only once it is UP. Same rule as every other thing an unfinished
## building cannot do (fire, produce, admit occupants): it exists — grid-occupying,
## selectable, shootable — but it does not yet act on anything around it.
func blocks_line_of_fire() -> bool:
	return super() and is_built


## Units currently registered as active builders of this structure.
var _active_builders: Array[Actor] = []

## BLUEPRINTS only — true while the purchase that raised this blueprint is still PENDING,
## i.e. the commander has committed to the build but can't pay for it yet. Drawn darker
## (MeshVisual.SHADE_AWAITING_FUNDS) so a site that is merely QUEUED is distinguishable
## at a glance from one a builder can actually start on.
##
## Set by Build.plan_structure from the transaction's state and cleared by
## PurchaseTransaction.fund(); nothing else should write it. Meaningless once the
## structure is placed — commit_construction clears it, since a placed structure has by
## definition been paid for.
var awaiting_funds: bool = false


## Set the awaiting-funds state and repaint. Idempotent, so the funded-in-the-same-frame
## case (see Build.plan_structure) costs nothing.
func set_awaiting_funds(a_awaiting: bool) -> void:
	if awaiting_funds == a_awaiting:
		return
	awaiting_funds = a_awaiting
	_apply_construction_visuals()


## Mark a freshly-instantiated structure as merely PLANNED — the blueprint an issued
## Build order raises at its site, before any builder arrives. Call BEFORE initialize()
## / add_entity: _ready and _on_commander_changed both read `is_planned` to skip the
## line-of-sight, infrastructure and commander-registration that a real structure gets, and the
## collision helpers read it to leave the thing intangible.
##
## What it DOES get is a live node the player can click: ownership, team tint, its
## Selectable area and its Production component — so units can be queued at a building
## that hasn't been started yet, exactly as they can at a half-built one.
func plan_construction() -> void:
	is_planned = true
	build_progress = 0.0
	build_progress_changed.emit(build_progress)


## Turn a planned structure into a real one at `world_center`: this is the moment the
## builder lays the foundation, so everything plan_construction held back switches on —
## grid cells (and the navmesh hole they punch), collision, line of sight, the commander's
## structure registry — and construction starts.
##
## Idempotent-ish: a no-op on a structure that was never planned, so the direct-issue
## build path (scenario events, tests) is unaffected.
func commit_construction(a_map: Map, a_world_center: Vector2) -> void:
	if not is_planned:
		return
	is_planned = false
	# A structure being laid down has been paid for by definition — the builder consumes
	# the reservation to get here. Clear the flag rather than leaving a stale true to
	# darken a structure that is now genuinely under construction.
	awaiting_funds = false

	# Grid registration also positions the structure on its footprint centre, punches the
	# navmesh hole and re-runs refresh_movement_collision (which now, with is_planned
	# false, gives it the layers a placed structure carries).
	if a_map != null:
		a_map.add_structure(self, a_world_center)
	_apply_targetable_layers()
	if vision_range_shape != null and not is_in_group("los"):
		add_to_group("los")

	# Commander bookkeeping deferred from _on_commander_changed: the structure counts
	# toward the tech tree only now that it exists (tech itself still gates on is_built, so
	# proc_technology won't credit it until construction finishes). Infrastructure is NOT
	# credited here — a foundation isn't a working relay or a load-bearing upkeep yet; see
	# advance_build_progress(), which credits it on the tick construction actually finishes.
	if commander != null:
		commander.add_structure(self)

	# Per-tick logic (production, aggro, death checks) was off while planned.
	set_physics_process(true)
	begin_construction()
	if defense != null:
		defense.hp = defense.hp_max * INITIAL_HEALTH_FACTOR
		defense.hp_changed.emit(defense.hp, defense.hp_max)


## Mark a freshly-instantiated structure as just-started construction. Call before
## add_entity so _ready → add_structure → proc_technology see is_built = false.
## HP is initialized to INITIAL_HEALTH_FACTOR * hp_max in Actor._ready(),
## after Defense._ready() has set it to hp_max, so we don't touch it here.
func begin_construction() -> void:
	build_progress = INITIAL_BUILD_PROGRESS
	build_progress_changed.emit(build_progress)


## Advance construction by `delta`, clamped at 1.0 (fully built). Returns true on
## the single tick construction first reaches completion, so callers run their
## one-time finish logic (tech re-eval, builder XP) exactly once.
## Also scales hp proportionally so health tracks build progress during construction
## (Task 4): each unit of build progress adds delta * hp_max * (1 - INITIAL_HEALTH_FACTOR).
func advance_build_progress(a_delta: float) -> bool:
	var was_built: bool = build_progress >= 1.0
	var old_progress: float = build_progress
	build_progress = minf(build_progress + a_delta, 1.0)
	var actual_delta: float = build_progress - old_progress
	if defense != null and actual_delta > 0.0 and not was_built:
		defense.hp = minf(
			(
				defense.hp
				+ (
					actual_delta
					* defense.hp_max
					* (1.0 - INITIAL_HEALTH_FACTOR)
					/ (1.0 - INITIAL_BUILD_PROGRESS)
				)
			),
			defense.hp_max
		)
		defense.hp_changed.emit(defense.hp, defense.hp_max)
	build_progress_changed.emit(build_progress)
	var just_built: bool = not was_built and build_progress >= 1.0
	if just_built:
		# The finished building becomes cover on this tick. Done here rather than in Assemble
		# so every route that finishes a structure (Capture, a scenario event) agrees.
		_apply_targetable_layers()
		# Infrastructure counts from the tick the piece is WORKING, not from the tick its
		# foundation was laid (see commit_construction).
		_sync_infrastructure()
		if commander != null:
			commander.construction_finished.emit(self)
	return just_built


func _on_build_progress_changed(_a_progress: float) -> void:
	_apply_construction_visuals()


## Draw the 3D model according to construction state, on two independent channels: OPACITY
## (how far along the lifecycle) and SHADE (whether it has been paid for).
## Why two rather than one scale, and how they compose with StatusVisuals' pair:
## gdd/systems/ux/ui/construction-visuals.md §Two channels, not one four-step scale.
func _apply_construction_visuals() -> void:
	var mesh_visual := get_node_or_null("MeshVisual") as MeshVisual
	if mesh_visual == null:
		return
	mesh_visual.set_opacity(construction_opacity())
	mesh_visual.set_shade(construction_shade())


## The opacity this commandable's art should be drawn at, by construction state.
func construction_opacity() -> float:
	if is_planned:
		return MeshVisual.OPACITY_PLANNED
	return MeshVisual.OPACITY_BUILT if is_built else MeshVisual.OPACITY_CONSTRUCTING


## How dark this commandable's art should be drawn — normal, or the darker
## awaiting-funds shade while a blueprint's purchase is still waiting to be paid for.
func construction_shade() -> float:
	return MeshVisual.SHADE_AWAITING_FUNDS if awaiting_funds else MeshVisual.SHADE_NORMAL


## Register `unit` as an active builder of this structure. Connects to tree_exiting
## so a dead or removed builder is automatically unregistered. Safe to call multiple
## times with the same unit (idempotent).
func register_builder(a_unit: Actor) -> void:
	if _active_builders.has(a_unit):
		return
	_active_builders.append(a_unit)
	a_unit.tree_exiting.connect(unregister_builder.bind(a_unit), CONNECT_ONE_SHOT)


## Remove `unit` from the active-builder list. Called explicitly when a Repair
## command ends, and automatically via tree_exiting when a builder dies.
func unregister_builder(a_unit: Actor) -> void:
	_active_builders.erase(a_unit)


## How much each extra builder past the first counts toward the site's build RATE, as a
## fraction of the first one. ZERO by deliberate balance choice: piling workers onto one
## structure must not buy tempo. Multiple builders are still supported for redundancy — a
## staggered or killed one leaves the others working — so this is a rate factor rather than
## a refusal to take the order.
##
## Set it to 1.0 to restore the plain AOE2 curve (each builder counting in full), which is
## what the code did before the balance pass. Intermediate values are meaningful too:
## 0.5 gives half-credit for every builder after the first.
const MARGINAL_BUILDER_EFFICIENCY: float = 0.0

## Build time in ticks assumed for a site whose type has no technology entry — a scenario-
## placed structure the tech tree does not price.
const UNPRICED_BUILD_TIME_TICKS: int = 600


## Per-builder-per-tick build progress increment, from the AOE2 formula
##   effective_build_time = 3 * base_build_time / (effective_n + 2)
## with the raw builder count replaced by an EFFECTIVE count that discounts every builder
## past the first by MARGINAL_BUILDER_EFFICIENCY. Each of the n registered builders calls
## this once per tick, so the site's total per-tick progress is n times this — i.e.
## 1/effective_build_time when all of them are acting, and proportionally less while some
## are staggered.
func effective_build_increment() -> float:
	var n: int = maxi(1, _active_builders.size())
	var effective_n: float = 1.0 + MARGINAL_BUILDER_EFFICIENCY * float(n - 1)
	var spec: TechnologySpec = (
		commander.technology_mapping.get(pricing_id()) if commander != null else null
	)
	var base_build_time: int = spec.creation_time if spec != null else UNPRICED_BUILD_TIME_TICKS
	return (effective_n + 2.0) / (3.0 * float(base_build_time) * float(n))


var map_cells: Set:
	get:
		return map.structure_cell_map.get(self, null) if map != null else null


## Whether this structure currently has a whole side reachable from walkable ground —
## NavPlacement's rule 2 (scripts/maps/nav_placement.gd), asked of a footprint already on the
## grid rather than a candidate one. Build.meets_precondition keeps a NEW production
## structure from ever failing this; a structure can still end up here later — terrain
## changing under it, or one authored into a pocket — which is what Train.meets_precondition
## asks this to refuse.
##
## True whenever there is nothing real to ask — no map, no terrain grid, or no footprint
## registered yet (a blueprint still PLANNED, an out-of-tree preview, a test double). This
## check only ever REFUSES a structure the grid can show is actually sealed in; it is not the
## thing that decides whether Train may fire at all.
func has_navmesh_access() -> bool:
	if map == null or map.terrain_grid == null:
		return true
	var footprint: Array = map.structure_cell_map.get(self, [])
	if footprint.is_empty():
		return true
	return NavPlacement.has_navmesh_side(map.terrain_grid, footprint)


#endregion

#region Grid placement


#region Static helpers
## These were Structure.<method> before the collapse. A future GridUtils
## module is the right home, but moving them onto Actor keeps the
## existing `Fixture.get_arrangement_cells(...)` call shape working as
## `Actor.get_arrangement_cells(...)`.
static func get_grid_coordinates(center: Vector2i, dimensions) -> Array:
	var ret: Array = []
	var ox: int = (dimensions.x - 1) / 2
	var oy: int = (dimensions.y - 1) / 2
	for w in range(dimensions.x):
		for h in range(dimensions.y):
			ret.append(Vector2(center.x - ox + w, center.y - oy + h))
	return ret


static func get_arrangement_cells(map: Map, point: Vector2, dimensions: Vector2i) -> Set:
	var center_coords: Vector2i = map.world_to_grid(point)
	var neighbor_coordinates = get_grid_coordinates(center_coords, dimensions)

	if neighbor_coordinates.any(func(c: Vector2i): return not map.grid_coordinates_in_bounds(c)):
		return Set.EMPTY
	else:
		return Set.new(
			neighbor_coordinates.map(func(coords): return map.cell_grid[coords.x][coords.y])
		)


## valid_placement moved to Entity (any grid-occupying entity, incl. non-commandable
## structures like ExtractionSite, can be placement-checked) — call Entity.valid_placement.
#endregion

#endregion

#region Combat
## HOLD FIRE: while true this piece never acquires a target ON ITS OWN — no idle pickup, no
## retaliation, and nothing for Defend or Patrol to engage (get_aggro_near_position answers
## null). Explicit orders are untouched, and an Attack or Attack-move RELEASES the hold
## (MoveCommand.releases_hold_fire, applied in update_commands). Set by the player's
## hold-fire command, by the bot's kamikaze hold, and by gaining stealth (Stealth._ready).
##
## A flag on the piece rather than a command, so setting it leaves the queue as it was: a
## held drone standing at home with an empty queue is the state the bot asserts.
## Why: gdd/design-framework/commitment-and-movement.md §Action timing.
var is_holding_fire: bool = false


## Whether an enemy has stuck anything on this piece that a heal would take off — a beacon or
## a planted charge riding on it (Defense.restore sheds them).
func has_hostile_markers() -> bool:
	return (
		Beacon.carried_by(self).any(func(b: Beacon) -> bool: return is_enemy_of(b.host()))
		or PlantedCharge.carried_by(self).any(
			func(c: PlantedCharge) -> bool: return is_enemy_of(c.host())
		)
	)


## Take off every enemy beacon and planted charge riding on this piece. A charge is removed
## without going off. Called by a heal (Defense.restore).
func shed_hostile_markers() -> void:
	for beacon: Beacon in Beacon.carried_by(self):
		if is_enemy_of(beacon.host()):
			beacon.dismiss()
	for charge: PlantedCharge in PlantedCharge.carried_by(self):
		if is_enemy_of(charge.host()):
			charge.remove()


## Widen Entity.is_armed(): a Actor also counts as armed while it is a bunker
## garrison ACTIVELY holding an occupant that carries a weapon, since bunker fire
## propagates that occupant's shots (making e.g. a garrisoned shelter a COMBAT_STRUCTURES
## target). Capability alone — an empty bunker — does not qualify.
func is_armed() -> bool:
	return super() or (garrison != null and garrison.bunker and garrison.has_armed_occupants())


## How many candidates one aggro scan considers per layer before filtering. The nearest
## few are all a pick ever needs, and the physics query cost grows with this.
const AGGRO_SCAN_MAX_RESULTS: int = 10


## This piece's reach on a layer, widened by a bunker's occupants: a bunker fires through the
## units inside it, so it picks fights at the range they can shoot from.
func reach_on_layer(a_layer: int) -> float:
	var best: float = super(a_layer)
	if garrison != null and garrison.bunker:
		best = maxf(best, garrison.occupant_reach_on_layer(a_layer))
	return best


## Whether this piece is ON RAILS: it moves, but on a course nobody may order it off — a
## called-in aircraft flying its sortie. It takes no order whose point is to go somewhere
## (Sortie.admit), so the command card offers none, and an attack-move clicked on ground is
## refused; one clicked on a target is still the Attack it resolves to.
func is_on_rails() -> bool:
	return Sortie.of(self) != null


## Whether this piece FIGHTS FROM ITS ORBIT: a weapon of its measures reach from the centre of
## the orbit it flies (Weapon.RangeOrigin.ORBIT). Moving never closes such a range, so an Attack
## changes only what it shoots at — never where it flies, nor the point it circles — and its
## targets are picked up from the orbit's centre rather than from where it is.
## Rules: gdd/systems/combat/range-buckets.md §Where a reach is measured from.
func fights_from_orbit() -> bool:
	return (
		weapon_inventory != null
		and weapon_inventory.get_weapons().any(
			func(w: Weapon) -> bool: return w.orbit_origin(self) is Vector3
		)
	)


## Hostile pieces inside any of this piece's orbit-measured range shapes, each standing at the
## orbit's centre — the pickup for a piece that fights from its orbit.
func _hostiles_in_orbit_range() -> Array[Entity]:
	var found: Array[Entity] = []
	for weapon: Weapon in weapon_inventory.get_weapons():
		var origin: Variant = weapon.orbit_origin(self)
		if not origin is Vector3:
			continue
		for pass_spec: Array in [
			[weapon.attack_range_shape_ground, CollisionLayers.Mask.TARGETABLE_GROUND],
			[weapon.attack_range_shape_air, CollisionLayers.Mask.TARGETABLE_AIR]
		]:
			var range_node: CollisionShape3D = pass_spec[0]
			if range_node == null:
				continue
			for hostile: Entity in SU.entities_touched_by(
				get_world_3d(),
				range_node.shape,
				origin,
				CollisionLayers.hostile_mask(pass_spec[1], commander_id)
			):
				if not found.has(hostile):
					found.append(hostile)
	return found


## Default weapon patterns for unit-grouped commandables. Structures default to
## no patterns. Subclasses (e.g. Vanguard) override get_weapon_evaluation_patterns
## as an instance method to provide custom weapons.
func get_aggro_near_position(
	a_center: Variant = null,
	a_shape: CollisionShape3D = null,
	min_target_priority: TargetPriority = TargetPriority.NON_COMBAT_UNITS
) -> MoveCommand:
	if is_holding_fire or (deployable != null and not deployable.can_use_weapons()):
		return null
	var is_bunker: bool = garrison != null and garrison.bunker and garrison.garrisoned_count() > 0
	if aggro_shapes().is_empty() or (weapon_inventory == null and not is_bunker):
		return null

	var center: Vector3
	if a_center == null:
		center = global_position
	elif a_center is Node3D:
		center = a_center.global_position
	else:
		center = a_center as Vector3

	# A caller-supplied region (Defend's area) is one shape for both layers, measured from its
	# centre POINT; otherwise the scan runs once per layer with that layer's own aggro radius,
	# measured from this piece's footprint. Either way the query asks only for hostile sides,
	# so allies cannot fill AGGRO_SCAN_MAX_RESULTS.
	var found: Array[Entity] = []
	if a_shape != null:
		found = _hostiles_in_region(a_shape, center, CollisionLayers.TARGETABLE_ANY)
	elif a_center != null:
		# A post with no region shape (Defend): each layer's aggro radius around the post.
		for pass_spec: Array in [
			[aggro_shape_ground, CollisionLayers.Mask.TARGETABLE_GROUND],
			[aggro_shape_air, CollisionLayers.Mask.TARGETABLE_AIR]
		]:
			if pass_spec[0] != null:
				found.append_array(_hostiles_in_region(pass_spec[0], center, pass_spec[1]))
	elif fights_from_orbit():
		found = _hostiles_in_orbit_range()
	else:
		found = hostiles_in_aggro(AGGRO_SCAN_MAX_RESULTS)
	var vs: Array[Entity] = found.filter(
		func(t: Entity) -> bool:
			# An attackable enemy this actor (or its garrison, when a bunker) can fire on,
			# ranked at least as important as the command's minimum target priority.
			if not t.is_attackable():
				return false
			if t.target_priority > min_target_priority:
				return false
			if not is_enemy_of(t):
				return false
			if not t.is_visible_to(commander_id):
				return false
			if weapon_inventory != null and weapon_inventory.weapon_for_target(t) != null:
				return true
			return is_bunker and garrison.any_garrison_can_target(t)
	)

	# Prefer higher-priority targets (lower TargetPriority value), breaking ties by the
	# nearest so a unit still engages the closest of the most important targets.
	var self_xz: Vector2 = VU.in_xz(global_position)
	vs.sort_custom(
		func(a: Entity, b: Entity) -> bool:
			if a.target_priority != b.target_priority:
				return a.target_priority < b.target_priority
			return (
				self_xz.distance_squared_to(VU.in_xz(a.global_position))
				< self_xz.distance_squared_to(VU.in_xz(b.global_position))
			)
	)

	if vs.is_empty():
		return null
	var msg := CommandMessage.new(map, vs[0], null)
	msg.persist = false
	return Attack.new(msg)


## Enemy targetables on `a_layers` within the region `a_shape` names, centred on
## `a_center`: the gap from the centre POINT to each footprint within the region's radius —
## the same test Attack._target_within_leash releases by.
func _hostiles_in_region(
	a_shape: CollisionShape3D, a_center: Vector3, a_layers: int
) -> Array[Entity]:
	if a_shape.shape == null:
		return []
	var exclude: Array = [hurtbox.get_rid()] if hurtbox != null else []
	return SU.entities_within(
		get_world_3d(),
		Hull.point(VU.in_xz(a_center)),
		a_shape.shape,
		a_center,
		CollisionLayers.hostile_mask(a_layers, commander_id),
		exclude,
		AGGRO_SCAN_MAX_RESULTS
	)


func receive_damage(a_damage: Damage, a_from: Actor = null) -> void:
	super(a_damage, a_from)
	# Any hit staggers the unit: refresh the timer so channeled actions (Build, Repair,
	# certain interactions) are suppressed for STAGGER_SECONDS. See is_staggered / the
	# gate in CommandReceiver._process_commands and MoveCommand.blocked_by_stagger.
	_stagger_ticks = STAGGER_SECONDS * TimeUtils.ticks_per_second()
	# Being attacked breaks stealth: force the timed UNSTEALTHED window.
	if stealth != null:
		stealth.unstealth()
	# Retaliation: only a piece with nothing to do answers, so an order is never overridden.
	if (
		defense != null
		and defense.hp > 0
		and orders != null
		and command_receiver.is_idle()
		and a_from != null
	):
		var attack_cmd: MoveCommand = _retaliation_against(a_from)
		if attack_cmd != null:
			update_commands(attack_cmd)


#endregion

#region Stagger
## Seconds a unit stays staggered after taking damage. While staggered, commands whose
## action opts in (MoveCommand.blocked_by_stagger — Build, Repair, PLANT
## interactions) suppress their completion: the unit still moves into range but waits to
## act until the stagger clears. It is a lightweight universal mechanic — a per-unit
## countdown rather than a StatusEffect node, since it fires on every damage instance.
const STAGGER_SECONDS: int = 3

## Remaining stagger duration in physics ticks; 0 when not staggered. Refreshed to full
## in receive_damage, counted down each tick in _physics_process.
var _stagger_ticks: int = 0


## True while the unit is staggered (recently damaged). A stagger-blocked command holds
## instead of completing its action while this is true.
func is_staggered() -> bool:
	return _stagger_ticks > 0


#endregion


#region Stun
## True while a StunStatusEffect is active on this unit — a harder stop than stagger:
## CommandReceiver._process_commands() returns immediately while this is true, so a
## stunned unit neither moves nor acts, full stop. No local timer: the child
## StatusEffect node owns its own duration and frees itself, so this just asks "is one
## attached right now" rather than tracking a second copy of the countdown.
func is_stunned() -> bool:
	for child: Node in get_children():
		if child is StunStatusEffect and (child as StunStatusEffect).is_active():
			return true
	return false


#endregion


#region Retaliation
## An Attack on `a_attacker`, the piece that just hit this one, or null when this one should
## not answer: it is holding fire, is garrisoned, cannot fire on the attacker (its own weapons
## nor, for a bunker, its occupants'), or its SIDE cannot see the attacker — an attacker in
## fog or under stealth is not answered, the same vision gate as idle aggro
## (gdd/systems/combat/target-acquisition.md). Aggro distance plays no part: this is what
## answers fire from past aggro. A piece that cannot move answers only what it already
## reaches, since it could never close on anything else.
func _retaliation_against(a_attacker: Actor) -> MoveCommand:
	if is_holding_fire or not is_inside_tree() or not can_use_weapons():
		return null
	if (
		not is_instance_valid(a_attacker)
		or not a_attacker.is_inside_tree()
		or not is_enemy_of(a_attacker)
		or not a_attacker.is_visible_to(commander_id)
	):
		return null
	var message := CommandMessage.new(map, a_attacker, null)
	if Attack.meets_precondition(self, message) != MoveCommand.PreconditionFailureCause.NONE:
		return null
	if not can_move() and not _reaches(a_attacker):
		return null
	return Attack.new(message)


## Whether this piece could fire on `a_target` from where it stands, loaded or not — through
## its own weapon or, as a bunker, through an occupant's.
func _reaches(a_target: Entity) -> bool:
	var weapon: Weapon = (
		weapon_inventory.weapon_for_target(a_target) if weapon_inventory != null else null
	)
	if weapon != null and SU.is_in_attack_range(weapon, self, a_target):
		return true
	return garrison != null and garrison.can_reach(self, a_target)


#endregion


#region Lifecycle
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		# Drop the command chain while this actor is still fully valid. Each MoveCommand's
		# PREDELETE resets our Movement.speed_cap (group-move cleanup), so it must run
		# before our own destructor frees Movement and our script members — otherwise it
		# dereferences a half-freed actor and hard-crashes. Commands normally clear
		# themselves on completion; the ones that outlive it (e.g. held while staggered)
		# are torn down here. See MoveCommand._notification.
		if orders != null:
			orders.receiver.update_commands(null)
			orders.rally_commands.clear()
		# Not every exit is a death — a consumed captive, a garrison's occupants killed with
		# it, an expiry — so the free itself is what finally withdraws the contribution.
		_withdraw_infrastructure()


func _ready() -> void:
	super()
	# Catches the far more common case above: a scene whose description/verbose was
	# simply never set, so the setters never ran at all (see the field docs).
	# Compared against the PLACEHOLDER as well as "", since that is now the declared default
	# (see the field docs) — a scene that never set its copy arrives holding it.
	if description.is_empty() or description == MISSING_DESCRIPTION:
		description = MISSING_DESCRIPTION
		_report_missing_flavor_text("description", _warned_missing_description)
	if verbose.is_empty() or verbose == MISSING_VERBOSE:
		verbose = MISSING_VERBOSE
		_report_missing_flavor_text("verbose", _warned_missing_verbose)

	# Establish the root's movement-collision layer now (map is still null, so this
	# resolves to MOVEMENT_OBSTRUCTION) — bounding_radius() below reads it, and it
	# runs before initialize() would otherwise set it. The Hurtbox's targetable and
	# STRUCTURE_BLOCKER layers are handled in Entity._ready (via super() above).
	refresh_movement_collision()
	attributes = Set.new(attributes_list)

	# Drive the HP-bar fill geometry off damage events rather than recomputing it
	# every frame. Visibility still depends on selection (see _process), but the
	# fill scale/offset only move when hp moves.
	if defense != null:
		defense.hp_changed.connect(_on_hp_changed)
		# Defense._ready() initializes hp to hp_max. For structures placed by
		# Build.fulfill_action (begin_construction called before _ready), override
		# hp to match the construction starting fraction (Task 4). A merely PLANNED
		# structure keeps full hp — it can't be damaged, and a part-full bar would read
		# as a damaged building; commit_construction drops it when the foundation is laid.
		if is_in_group("structure") and not is_built and not is_planned:
			defense.hp = defense.hp_max * INITIAL_HEALTH_FACTOR
		_on_hp_changed(defense.hp, defense.hp_max)

	# Construction fade: a structure placed but not finished is drawn translucent, and
	# snaps to full opacity the tick it completes. Driven off the progress signal (plus
	# this initial call, since begin_construction fires before we're in the tree) rather
	# than polled every frame. Structures placed in the editor start built, so this is a
	# no-op for them; units are always built.
	build_progress_changed.connect(_on_build_progress_changed)
	_apply_construction_visuals()

	# A planned structure runs no per-tick logic: nothing to produce (the queue holds
	# its orders until it's built), nothing to shoot, nothing to die. commit_construction
	# switches this back on when the builder lays it down.
	if is_planned:
		set_physics_process(false)

	# Wire Movement → physics handler for any entity carrying one. Wired on the COMPONENT,
	# live or not, so a two-form piece that starts deployed is ready the moment it undeploys;
	# the obstacle broadcasts only while the component is live (Movement.set_active).
	if movement_component != null:
		movement_component.velocity_ready.connect(_on_velocity_computed)
		var body_radius: float = bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		movement_component.set_agent_radius(body_radius)
		# Size the obstacle to match the unit's footprint and hand the reference
		# to Movement so suppress/restore_avoidance_layers can silence it too.
		# avoidance_layers is set when ownership is established (see _on_commander_changed).
		if _avoidance_obstacle != null:
			_avoidance_obstacle.radius = body_radius
			_avoidance_obstacle.avoidance_enabled = movement_component.is_active
			movement_component.avoidance_obstacle = _avoidance_obstacle
		# NOTE: avoidance team is configured in _on_commander_changed, not here.
		# During initialize() add_child() (→ _ready) runs BEFORE the commander is
		# assigned, so `commander` is null at this point; the team must be set
		# when ownership is actually established.


func _on_commander_changed(a_old_commander: Commander, a_new_commander: Commander) -> void:
	super(a_old_commander, a_new_commander)

	# Turn on RVO avoidance once ownership is established. This is the first point
	# at which the commander is known for dynamically-spawned units (initialize()
	# assigns the commander after add_child/_ready); without it the agent keeps
	# its scene-default avoidance_layers/mask of 0 and avoids nothing.
	# Also update the NavigationObstacle3D layer so enemies steer around this
	# unit one-sidedly (cross-team one-sided avoidance — see AvoidanceAgent3D).
	if movement_component != null and a_new_commander != null:
		var obstacle_layers: int = AvoidanceAgent3D.obstacle_bit(a_new_commander.id)
		if (
			_avoidance_obstacle != null
			and not (deployable != null and deployable.hold_obstacle_layers(obstacle_layers))
		):
			_avoidance_obstacle.avoidance_layers = obstacle_layers
		if movement != null:
			movement.enable_avoidance(a_new_commander.id)

	_sync_infrastructure()
	_follow_upgrades(a_old_commander, a_new_commander)
	if not is_in_group("structure"):
		return
	# A PLANNED structure is owned (it's tinted, selectable and takes train orders) but it
	# is not one of the commander's buildings yet: it doesn't belong in the structure
	# registry the tech tree and the AI read. commit_construction
	# runs this registration when the builder actually lays it down.
	if is_planned:
		return
	if a_old_commander != null:
		a_old_commander.remove_structure(self)
	if a_new_commander != null:
		a_new_commander.add_structure(self)


## Track the owning commander's upgrades: apply what it owns now, and what it researches later.
## A captured piece trades the old owner's upgrades for the new one's.
func _follow_upgrades(a_old_commander: Commander, a_new_commander: Commander) -> void:
	if a_old_commander != null and a_old_commander.upgrade_researched.is_connected(_on_upgrade):
		a_old_commander.upgrade_researched.disconnect(_on_upgrade)
	if a_new_commander != null:
		a_new_commander.upgrade_researched.connect(_on_upgrade)
	_apply_upgrades()


func _on_upgrade(_a_id: StringName) -> void:
	_apply_upgrades()


## The upgrade effects that live on the piece rather than being asked for at each read: today
## only the hit-point maximum (Defense.set_hp_factor says why it is stored).
func _apply_upgrades() -> void:
	if defense != null:
		defense.set_hp_factor(UpgradeCatalog.factor_for(self, UpgradeCatalog.HP_FACTOR))


func initialize(a_map: Map, a_commander: Commander):
	super(a_map, a_commander)
	if orders != null:
		orders.receiver.initialize(self)
	# `map` is now set (super assigned it), for both dynamically-spawned and
	# scene-placed units — unlike _on_commander_changed, which fires during _ready
	# (before initialize) for scene-placed units. Derive the unit's size class from
	# its MovementBody footprint and point the agent at the navmesh for that class.
	if movement_component != null and map != null:
		movement_component.configure_for_map(
			map, map.nav_manager, bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		)
	# Structure registration is handled by _on_commander_changed, which fires
	# from Entity._ready() when Ownership migrates the pre-tree _commander value.


## Push command state into the MeshVisual component: map the current situation
## to a high-level animation state. The animation call is a no-op until an
## AnimationTree is authored.
##
## Facing is NOT pushed here anymore. The root node's rotation.y is now the
## single source of truth for facing (Movement rotates it toward the direction
## of travel / aim — see Movement.get_facing, which treats +Z as the mesh's
## visual front), and MeshVisual is a child that inherits that rotation.
## Driving MeshVisual.face_direction as well would rotate the mesh a SECOND time
## on top of the root, compounding the two into a doubled, offset yaw that
## snaps for large turns.
func _drive_mesh_visual(a_mesh_visual: MeshVisual) -> void:
	var state: MeshVisual.AnimationState = MeshVisual.AnimationState.IDLE
	if has_command() and current_command() is Attack:
		state = MeshVisual.AnimationState.ATTACK
	elif movement != null and Vector2(velocity.x, velocity.z).length_squared() > 0.0001:
		state = MeshVisual.AnimationState.MOVE
	a_mesh_visual.set_animation_state(state)


func _process(_a_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# HP bar visibility (visible while damaged or selected, and never on a unit stealth is
	# hiding from us — an enemy whose model is drawn at zero alpha must not be given away
	# by a floating bar). The fill geometry is driven separately by _on_hp_changed, since
	# it only moves when hp moves.
	$HPBar.visible = (
		defense != null
		and (defense.hp < defense.hp_max or selectable.is_selected())
		and not is_hidden_by_stealth()
	)

	# Movement-driven animation state.
	var mesh_visual := get_node_or_null("MeshVisual") as MeshVisual
	if mesh_visual != null:
		_drive_mesh_visual(mesh_visual)

	# Debug label: show active command name while the debug view is up.
	if _debug_label != null:
		var show_debug: bool = DebugMode.is_active()
		_debug_label.visible = show_debug
		if show_debug:
			_debug_label.text = (
				current_command().get_script().get_global_name() if has_command() else "NULL"
			)

	# Train bar. Was Fixture._process.
	if production != null:
		production.update_bar(scale.x)


## Resize/offset the HP-bar fill to match the current hp fraction. Connected to
## Defense.hp_changed, so it runs only when hp actually changes.
## Drives the HP bar's fill: how much of it shows, where it is anchored, and what
## color it is. Called on damage/heal rather than every frame (see _ready).
##
## The bar shrinks by CROPPING the quad (region_rect) and re-anchors with `offset` —
## never by scaling or moving the NODE. Both of those live in the sprite's own 2D
## plane, so they are carried along when the billboard turns the quad to face the
## camera. `position` is not: it feeds the model matrix's translation, which a
## billboard preserves in WORLD space, so a leftward nudge marched the fill along
## world −X while the quad faced elsewhere — on this game's isometric camera that
## reads as the fill drifting up and off the bar as damage accumulates.
func _on_hp_changed(a_hp: float, a_hp_max: float) -> void:
	if hp_bar_fill == null or hp_bar_fill.texture == null or a_hp_max <= 0:
		return
	# Clamped because hp goes negative for a tick before _on_death runs, and nothing
	# stops a heal exceeding hp_max; both must land on an end of the bar, not past it.
	var fraction: float = clampf(a_hp / a_hp_max, 0.0, 1.0)
	var size: Vector2 = hp_bar_fill.texture.get_size()
	hp_bar_fill.region_enabled = true
	hp_bar_fill.region_rect = Rect2(0.0, 0.0, size.x * fraction, size.y)
	# Half the width the crop removed, shifting the (still centred) quad left so its
	# LEFT edge stays put and the bar drains rightward. Zero at full health.
	hp_bar_fill.offset = Vector2(-size.x * (1.0 - fraction) / 2.0, 0.0)
	# The fill texture is white; all of its color comes from here (see HealthBarGradient).
	hp_bar_fill.modulate = HealthBarGradient.color_for(fraction)


func _on_velocity_computed(a_velocity: Vector3) -> void:
	# a_velocity is the RVO avoidance-adjusted velocity from the NavigationAgent3D.
	# We simply apply it; same-team avoidance keeps units from overlapping, so we
	# no longer cancel commands on contact — the agents steer around each other
	# instead of giving up when they touch.
	velocity = a_velocity

	if velocity != Vector3.ZERO:
		move_and_slide()

	# Snap Y to terrain after each move so height tracks the final XZ this tick,
	# not the XZ from before the move (which is what _physics_process saw).
	if map != null:
		_snap_height_to_terrain()


## Stand the body at its height for this tick: the terrain under it — the eased contour an
## aircraft follows (Aerial.follow_y) rather than the raw one — plus its height above that.
func _snap_height_to_terrain() -> void:
	var terrain_y: float = map.terrain_height_at(VU.in_xz(global_position))
	var base_y: float = aerial.follow_y(terrain_y) if aerial != null else terrain_y
	global_position.y = base_y + height_offset()


func _update_state() -> void:
	if defense != null and defense.hp <= 0:
		_on_death()
		return

	# Before anything else this tick: an aircraft with nothing left to fire stands down the
	# order that assumed it would shoot, and then — only if that leaves it with nothing else
	# worth doing — takes itself home. Ahead of the idle-aggro check on purpose, so a dry
	# unit cannot pick up a new target it could only stand over.
	_defer_unshootable_orders()
	# Ahead of the rearm check: an aircraft whose airfield has just been destroyed is not
	# parked any more, and maybe_auto_rearm reads "parked" as "already home".
	if docking != null:
		docking.release_lost_dock()
		docking.maybe_auto_rearm()
		docking.release_runway()
		docking.aim_parked_at_runway()

	# The command half of the tick — idle target pickup and the queue (Orders.tick).
	if orders != null:
		orders.tick()

	# Command processing above may remove this unit from the tree mid-tick (e.g.
	# garrisoning into a Garrison); the remaining per-tick work touches world/
	# physics state that is invalid while orphaned, so stop here.
	if not is_inside_tree():
		return

	# Per-tick production. No-op for non-producing entities or unbuilt structures.
	if production != null and is_built:
		production.tick()
	# Service whatever is parked on this airfield's pads. Driven from the STRUCTURE rather
	# than from each docked aircraft, so the bay's charge_rate is applied in one place and a
	# parked unit needs no per-tick branch of its own.
	if docking_bay != null and is_built:
		docking_bay.tick_recharge()
	tick_collection()
	# Passive conversion: any neutral unit inside LiberationRange changes sides.
	if liberator != null:
		liberator.tick()

	# Detection: reveal enemy stealth units within DetectionRange this tick.
	if detection_range != null:
		_detect_stealthed_units()
	# Stealth: advance the unstealthing countdown on this entity.
	if stealth != null:
		stealth.tick()


func _physics_process(_a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _stagger_ticks > 0:
		_stagger_ticks -= 1
	_update_state()
	# A command fulfilled during _update_state() (e.g. garrisoning into a
	# Garrison) may remove this unit from the tree mid-tick; touching
	# global_position while orphaned warns, so skip the rest of the tick.
	if not is_inside_tree():
		return
	# Keep units glued to terrain height each tick.  The navmesh is 3D (built
	# from HeightMapShape3D data) but the velocity computation zeroes Y to keep
	# avoidance stable, so Y tracking must happen here instead.
	if (movement != null or aerial != null) and map != null:
		_snap_height_to_terrain()
	# Who yields to whom in same-team RVO: a unit firing from where it stands yields to nobody,
	# a traveller outranks a stander. Per-tick because the ranking follows what the unit is
	# doing right now — see Movement.
	if movement != null:
		var command: MoveCommand = current_command()
		movement.update_avoidance_priority(command != null and command.holds_ground(self))
	# Immediately after the height above: whether this piece is an air or a ground target is
	# a question about the Y just written, so the two must not be a tick apart.
	refresh_targetable_altitude()
	_tick_crush()


#region Crush
## The scan sphere, KEPT between ticks. A Shape3D owns a physics-server RID, so building one
## per tick per crusher churns server resources for a value that almost never changes —
## this is the object-pool case, not premature caching. Rebuilt only when the agent's
## neighbour distance actually differs, so a reconfigured agent still gets the right volume.
var _crush_scan_shape: SphereShape3D = null


## Both halves of the crush mechanic, skipped wholesale for anything that cannot
## crush at all — no Movement, or a crush_class too low to outrank even TINY, which
## is the large majority of pieces. Nothing here needs a dedicated node: crushers are
## rare enough to pay for their own queries, where a persistent Area3D would have sat
## in the broadphase on every commandable in the game.
##
## A crusher carrying a hold takes prisoners with the same contact — see
## _run_over_overlapping_units.
func _tick_crush() -> void:
	if movement == null or not movement.can_crush_anything():
		return
	_update_crush_avoidance_exclusions()
	_run_over_overlapping_units()


## The "don't detour around it" half: recompute which foreign obstacle channels
## (AvoidanceAgent3D.obstacle_bit) this unit's avoidance mask should ignore — any
## commander with a nearby unit this one can run over (_can_run_over) is walked through
## rather than steered around. The NEUTRAL channel is in scope: a carrier that steered
## around a Shelter's Terrestrials could never make contact to take one.
##
## SCANNED WITHIN THE AGENT'S OWN RVO NEIGHBOURHOOD, not within AggroRange. Aggro range
## answers "how far will I pick a fight", which is a different question and one a peaceful
## crusher deliberately declines to answer: a dominion generator, a transport and a truck
## all have no aggro volume at all, and every one of them must still drive over infantry.
## Scoping the scan to AggroRange meant those units excluded nothing, ever, and steered
## politely around the soldiers they outweigh — the bug this pass fixes, seen with a
## `cl_mechLight_dominionGen` detouring around an enemy `cl_bioLight_builder`. It was
## invisible to a reader because the guard was on the aggro NODE, which every piece
## inherits from commandable.tscn, while the scan needs the aggro SHAPE, which a piece
## without an aggro range does not have.
##
## `neighbor_distance` is the region RVO reacts within BY DEFINITION, so it is exactly the
## set of neighbours there is anything to exclude about — outside it the agent was never
## going to steer around them anyway. Queried on MOVEMENT_OBSTRUCTION, the same layer the
## run-over half uses, so both halves of the mechanic look at the same population.
##
## No-op without an AvoidanceAgent3D-backed nav agent. (Aerial units never reach here at
## all — _tick_crush bails on them via can_crush_anything, which is also why
## avoidance_agent() being null in those modes no longer matters.)
##
## See the _crush_excluded_obstacles caveat on AvoidanceAgent3D: obstacle channels are
## per-commander, not per-unit, so this stays a team-wide approximation.
func _update_crush_avoidance_exclusions() -> void:
	var agent: AvoidanceAgent3D = movement.avoidance_agent()
	if agent == null:
		return
	var excluded: int = 0
	for e: Entity in SU.query_shape_for_entities(
		get_world_3d(),
		_crush_avoidance_scan_shape(agent),
		Transform3D(Basis.IDENTITY, global_position),
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		[get_rid()]
	):
		var other := e as Actor
		if other == null or not _can_run_over(other):
			continue
		excluded |= AvoidanceAgent3D.obstacle_bit(other.commander_id)
	agent.set_crush_excluded_obstacles(excluded)


## The volume to look for crushable neighbours in: a sphere of the agent's RVO neighbour
## distance, centred on this unit.
func _crush_avoidance_scan_shape(a_agent: AvoidanceAgent3D) -> SphereShape3D:
	if _crush_scan_shape == null:
		_crush_scan_shape = SphereShape3D.new()
	if not is_equal_approx(_crush_scan_shape.radius, a_agent.neighbor_distance):
		_crush_scan_shape.radius = a_agent.neighbor_distance
	return _crush_scan_shape


## Whether driving into [a_other] would come to anything: this unit outsizes it AND the
## contact has a consequence — a kill if it is an enemy, a capture if it is prey this unit has
## room for. Both halves of the mechanic ask this, so a unit is only walked through when
## walking through it does something. A NEUTRAL qualifies only via the capture arm, which is
## why this is not simply is_enemy_of. `can_crush()` already rules out every aerial pairing,
## so no altitude test is needed. Why:
## gdd/systems/combat/garrison-and-transport.md.
func _can_run_over(a_other: Actor) -> bool:
	if a_other.movement == null or not movement.can_crush(a_other.movement):
		return false
	return is_enemy_of(a_other) or Garrison.can_capture(self, a_other)


## The "drive over the smaller unit" half. Every unit overlapping this one's own movement
## body that it outsizes is either TAKEN PRISONER — if this unit has a hold with room and
## the pairing is a capture (Garrison.can_capture) — or, failing that, killed if it is an
## enemy.
##
## The order matters and the fallthrough is the point: capacity gates the CAPTURE, never the
## crush. A full truck still flattens the soldier it drives over. A neutral it cannot take
## is simply left alone, since neutrals were never crushed.
##
## Queried against the movement collider, NOT the (much wider, result-capped) aggro
## shape scanned above: a crusher ploughing through a swarm is exactly the case where
## an aggro-sized query truncates, and truncating here would drop kills. A
## footprint-sized query only ever holds real contacts, so the cap never bites.
func _run_over_overlapping_units() -> void:
	if collider == null or collider.shape == null:
		return
	for e: Entity in SU.query_shape_for_entities(
		get_world_3d(),
		collider.shape,
		collider.global_transform,
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		[get_rid()]
	):
		var other := e as Actor
		if other == null or not _can_run_over(other):
			continue
		if garrison != null and Garrison.can_capture(self, other):
			garrison.garrison(other)
			continue
		if not is_enemy_of(other):
			continue
		if other.defense != null and other.defense.hp > 0:
			other.defense.kill()


#endregion


## A two-form piece is one of its commander's structures exactly while it is deployed. A
## PLANNED one is registered by commit_construction instead, as every structure is.
func _on_form_changed(a_deployed: bool) -> void:
	if commander == null or is_planned:
		return
	if a_deployed:
		commander.add_structure(self)
	else:
		commander.remove_structure(self)


## Route the current command (Orders.process). CommandReceiver calls this, never its own
## _process_commands, so a structure's Train becomes a purchase on its way through.
func _process_commands() -> void:
	if orders != null:
		orders.process()


func _on_death() -> void:
	# Return or kill garrisoned occupants before queue_free() voids the host's map
	# reference and orphans them permanently. This is also how PRISONERS get out: a
	# destroyed stock truck or Compound is a garrison like any other, and each
	# occupant is released to its OWN commander (see Garrison._return_to_commander).
	if garrison != null and garrison.garrisoned_count() > 0:
		if garrison.preserve_occupants:
			garrison.evacuate(map)
		else:
			garrison.kill_occupants()
	# Refund whatever this producer still owed the player. Two separate pots:
	#   * jobs already handed to this Production queue — paid for, so cancel() returns
	#     each one's cost here (nothing else watches this queue);
	#   * purchases still sitting in the commander's global queue that named this
	#     structure as a producer — those are dropped and refunded by ProductionQueue's
	#     own prune once this node is freed (a producer that no longer exists leaves the
	#     transaction with no candidates).
	# A destroyed barracks must not swallow the energy for the units it never trained.
	if production != null:
		while production.job_count() > 0:
			production.cancel(production.job_count() - 1)
	# Commander/economy teardown for owned structures. The grid teardown
	# (map.remove_structure) is handled in Entity._on_death via super().
	if is_in_group("structure") and commander != null:
		commander.remove_structure(self)
	_withdraw_infrastructure()
	super()


#endregion


#region Private helpers
## Credit `infrastructure` to the commander it should count for now, moving it off whoever
## held it before. It counts for the owner while the piece is built and not merely planned —
## never by whether the piece is a structure. A zero contribution registers nothing, so the
## commander is not told about every rifleman that comes and goes.
func _sync_infrastructure() -> void:
	var target: Commander = (
		commander if is_built and not is_planned and infrastructure != 0 else null
	)
	if _infrastructure_credited_to == target:
		return
	_withdraw_infrastructure()
	if target != null:
		target.add_infrastructure(infrastructure)
		_infrastructure_credited_to = target


func _withdraw_infrastructure() -> void:
	var credited: Variant = _infrastructure_credited_to
	_infrastructure_credited_to = null
	if credited != null and is_instance_valid(credited):
		(credited as Commander).remove_infrastructure(infrastructure)


## Stamp reveal() on every enemy within DetectionRange, measured between footprints like
## every range (SU.entities_within). Queries the STEALTH layer, so only entities that opted
## into it (i.e. those with a Stealth node) are considered.
func _detect_stealthed_units() -> void:
	var targets: Array[Entity] = SU.entities_within(
		get_world_3d(),
		hull(),
		detection_range.shape,
		detection_range.global_position,
		CollisionLayers.Mask.STEALTH,
		[self],
		20
	)
	for target in targets:
		if target.stealth == null:
			continue
		# Only reveal enemies — neutral (id 0) and own units are skipped.
		if not is_enemy_of(target):
			continue
		target.stealth.reveal()


## One tick of this piece's steady income: its EnergyExtractor and its DominionGenerator. Both
## are gated on is_built, so a blueprint still going up pays nothing — a flat generator (the
## Technocratic Lab) would otherwise earn through its whole construction. The commander's rate
## readouts already skip unbuilt pieces (Commander._rate_over), so this keeps the payout and the
## figure that explains it in agreement. Public so a test can drive it without a full tick.
func tick_collection() -> void:
	if not is_built:
		return
	if energy_extractor != null:
		energy_extractor.tick()
	if dominion_generator != null:
		dominion_generator.tick()

#endregion
