class_name AlertCenter
extends Node
## THE MATCH'S ALERTS — every happening a commander should be told about, for every commander.
## One per Scenario (Scenario.alerts()), built in code like MatchLog.
##
## Two outputs, and the difference is the whole design:
##   alert_raised      EVERY alert, for every commander it concerns. The game tracks all of them.
##   alert_presented   the subset that survives that commander's AlertThrottle — what a player
##                     is actually shown and told. The HUD (AlertFeed) listens to this one, for
##                     whoever it is showing; it is also the channel a bot's perception would
##                     subscribe to (gdd/systems/ai/ontology.md §Cues: a bot perceives what the
##                     presentation presents). Nothing subscribes a bot yet.
##
## Presentation only: nothing here writes to the simulation or draws from its RNG, so a replay
## raises the same alerts and an alert can never change a match. gdd/systems/ux/ui/alerts.md.

#region Signals
signal alert_raised(a_alert: Alert)
signal alert_presented(a_alert: Alert)
#endregion

#region Constants
## How often polled sources (states, superweapons) are read: three times a second is quick
## enough for a superweapon's launch and cheap enough to scan every structure.
const POLL_SECONDS: float = 1.0 / 3.0

## How many raised alerts `recent()` keeps — the record of what happened, presented or not.
const LOG_SIZE: int = 256
#endregion

#region Properties
var _scenario: Scenario = null
## Commanders by id, index 0 the neutral world (Scenario.commanders). Injected by tests.
var _commanders: Array = []
## Overrides Scenario.tick when set (>= 0) — tests drive time by hand.
var _tick_override: int = -1
var _next_poll_tick: int = 0

## viewer id → AlertThrottle
var _throttles: Dictionary = {}
## commander id → AlertLatch, per state type
var _float_latches: Dictionary = {}
var _strain_latches: Dictionary = {}

## Superweapon casters, by piece instance id → {piece: WeakRef, owner: int, ability: StringName,
## built: bool, charges: int, title: String}
var _casters: Dictionary = {}

## Commander ids whose completion signals are connected.
var _listened: Dictionary = {}
## "pool instance id:pool index" → the charges last seen, for _poll_ability_charges
var _pool_charges: Dictionary = {}

var _log: Array[Alert] = []
#endregion


#region Lifecycle
## Listen to `a_scenario`'s pieces. Its trigger manager is the bus every piece's occurrences
## reach (Entity._fire_entity_occurrence).
func bind(a_scenario: Scenario) -> void:
	_scenario = a_scenario
	_commanders = a_scenario.commanders
	var manager: ScenarioTriggerManager = a_scenario.trigger_manager()
	if manager != null and not manager.entity_occurrence.is_connected(report_occurrence):
		manager.entity_occurrence.connect(report_occurrence)
	_listen_to_commanders()
	var map: Map = a_scenario.find_child("Map", true, false) as Map
	if map != null:
		bind_water_bodies(map.water_bodies)


## For a test: the commanders to address (index = id), and no scenario.
func bind_commanders(a_commanders: Array) -> void:
	_commanders = a_commanders
	_listen_to_commanders()


## Hear each of `a_bodies` (the map's lithium ponds) run dry.
func bind_water_bodies(a_bodies: Array) -> void:
	for body: Variant in a_bodies:
		var pond := body as WaterBody
		if pond != null and not pond.drained.is_connected(_on_pond_drained):
			pond.drained.connect(_on_pond_drained)


func _physics_process(_a_delta: float) -> void:
	var now: int = now_tick()
	if now < _next_poll_tick:
		return
	_next_poll_tick = now + maxi(1, TimeUtils.ticks_from_seconds(POLL_SECONDS))
	poll()


#endregion


#region Public API
## The simulation tick alerts are stamped with.
func now_tick() -> int:
	if _tick_override >= 0:
		return _tick_override
	return _scenario.tick if _scenario != null else 0


## For a test: stamp alerts with `a_tick` from now on.
func set_tick(a_tick: int) -> void:
	_tick_override = a_tick


## The last LOG_SIZE alerts raised for anyone, oldest first.
func recent() -> Array[Alert]:
	return _log.duplicate()


## Every superweapon caster that is up, for the timer panel: Array of {piece, owner, ability,
## title, charges, max_charges, remaining_ticks}. Shown to everyone — that is the convention —
## but never with a position.
func superweapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _casters:
		var entry: Dictionary = _casters[id]
		var piece := (entry["piece"] as WeakRef).get_ref() as Actor
		if piece == null or not entry["built"]:
			continue
		var abilities := piece.get_node_or_null("Abilities") as Abilities
		if abilities == null:
			continue
		var ability: StringName = entry["ability"]
		(
			out
			. append(
				{
					"piece": piece,
					"owner": entry["owner"],
					"ability": ability,
					"title": entry["title"],
					"charges": abilities.charges_of(ability),
					"max_charges": abilities.max_charges_of(ability),
					"remaining_ticks": abilities.recharge_remaining(ability),
				}
			)
		)
	return out


## A piece's lifecycle occurrence, from the trigger manager's bus.
func report_occurrence(a_occurrence: Entity.EntityOccurrence, a_source: Entity) -> void:
	match a_occurrence:
		Entity.EntityOccurrence.ON_RECEIVE_DAMAGE:
			_on_damaged(a_source)
		Entity.EntityOccurrence.ON_EXIT_STEALTH:
			_on_unhidden(a_source)


## Read every polled source once. Called on a timer; public so a test can step it.
func poll() -> void:
	var now: int = now_tick()
	for commander: Variant in _commanders:
		var c := commander as Commander
		if c == null or c.id <= 0:
			continue
		_poll_economy(c, now)
	_poll_superweapons(now)
	_poll_ability_charges(now)


## Raise `a_alert`: record it, then present it if its viewer's throttle admits it.
func raise(a_alert: Alert) -> void:
	_log.append(a_alert)
	if _log.size() > LOG_SIZE:
		_log.pop_front()
	alert_raised.emit(a_alert)
	if _throttle_for(a_alert.viewer_id).admit(a_alert):
		alert_presented.emit(a_alert)


#endregion


#region Event sources
## Units / structures under attack: told to the victim's owner, located. Hurt by its own side
## (splash, a strike of its own) is not an attack and is not announced; an unattributed hit is.
func _on_damaged(a_victim: Entity) -> void:
	if a_victim == null or a_victim.commander_id <= 0:
		return
	var structure: bool = a_victim.is_in_group(&"structure")
	if not structure and not a_victim.is_in_group(&"unit"):
		return
	var attacker: int = a_victim.last_hit_by_commander_id
	if attacker > 0 and a_victim.is_on_side_of(attacker):
		return
	var type := AlertCatalog.Type.UNITS_ATTACKED
	if structure:
		type = _structure_attack_type(a_victim as Actor)
	raise(
		(
			Alert
			. make(type, a_victim.commander_id, now_tick())
			. located_at(a_victim.global_position)
			. about(a_victim)
		)
	)


## A stealthed piece found by a detector: told to every enemy commander who can now see it.
## Unhidden by a fight instead (UNSTEALTHED) is announced as the attack, not here.
func _on_unhidden(a_piece: Entity) -> void:
	var stealth := a_piece.get_node_or_null("Stealth") as Stealth if a_piece != null else null
	if stealth == null or stealth.state != Stealth.State.REVEALED or a_piece.commander_id <= 0:
		return
	for commander: Variant in _commanders:
		var c := commander as Commander
		if c == null or c.id <= 0 or a_piece.is_on_side_of(c.id):
			continue
		if not a_piece.is_visible_to(c.id):
			continue
		var alert := Alert.make(AlertCatalog.Type.STEALTH_DETECTED, c.id, now_tick())
		raise(alert.located_at(a_piece.global_position).about(a_piece))


#endregion


## Which "under attack" a structure's hit is: the command centre and the extractors are their
## own alerts, the rest of the base the general one.
static func _structure_attack_type(a_structure: Actor) -> AlertCatalog.Type:
	if Deployment.is_command_centre(a_structure):
		return AlertCatalog.Type.COMMAND_CENTRE_ATTACKED
	if Extractor.of(a_structure) != null:
		return AlertCatalog.Type.EXTRACTOR_ATTACKED
	return AlertCatalog.Type.STRUCTURES_ATTACKED


func _on_construction_finished(a_structure: Actor, a_commander: Commander) -> void:
	_announce_completion(AlertCatalog.Type.CONSTRUCTION_COMPLETE, a_commander, a_structure)


func _on_unit_trained(a_unit: Actor, a_commander: Commander) -> void:
	_announce_completion(AlertCatalog.Type.UNIT_READY, a_commander, a_unit)


func _on_upgrade_researched(a_id: StringName, a_commander: Commander) -> void:
	var text: String = AlertCatalog.text_of(
		AlertCatalog.Type.RESEARCH_COMPLETE, UpgradeCatalog.title_of(a_id)
	)
	raise(Alert.make(AlertCatalog.Type.RESEARCH_COMPLETE, a_commander.id, now_tick(), text))


func _announce_completion(
	a_type: AlertCatalog.Type, a_commander: Commander, a_piece: Actor
) -> void:
	if a_commander == null or a_commander.id <= 0 or a_piece == null:
		return
	var text: String = AlertCatalog.text_of(a_type, title_of(a_piece))
	var alert := Alert.make(a_type, a_commander.id, now_tick(), text)
	alert.purchase = a_piece.id
	raise(alert.located_at(a_piece.global_position).about(a_piece))


## A lithium pond ran dry: told to whoever was working it, at the pond.
func _on_pond_drained(a_pond: WaterBody) -> void:
	var extractor: Variant = a_pond.extractor if a_pond.has_extractor() else null
	var owner: int = (extractor as Entity).commander_id if extractor is Entity else 0
	if owner <= 0:
		return
	var alert := Alert.make(AlertCatalog.Type.POND_DEPLETED, owner, now_tick())
	raise(alert.located_at(a_pond.global_position).about(a_pond))


#region Polled sources
func _poll_economy(a_commander: Commander, a_now: int) -> void:
	var id: int = a_commander.id
	# The HUD's own definition, so the bar pulsing and the alert speaking can never disagree.
	var floating: bool = ResourcePressure.is_energy_floating(a_commander)
	if _latch(_float_latches, id, AlertCatalog.Type.ENERGY_FLOATING).update(floating, a_now):
		var alert := Alert.make(AlertCatalog.Type.ENERGY_FLOATING, id, a_now)
		alert.key = id
		raise(alert)

	var strained: bool = a_commander.is_infrastructure_strained()
	var latch := _latch(_strain_latches, id, AlertCatalog.Type.INFRASTRUCTURE_STRAINED)
	if latch.update(strained, a_now):
		var alert := Alert.make(AlertCatalog.Type.INFRASTRUCTURE_STRAINED, id, a_now)
		alert.key = id
		raise(alert)


## Find every caster of a `global_alert:` ability and announce what changed since last time:
## begun, finished, charged, fired, gone. Polled rather than signalled because the caster's
## Abilities component has no signals and a superweapon is rare enough that a scan is cheap.
func _poll_superweapons(a_now: int) -> void:
	var alerted: Array[StringName] = AbilityCatalog.global_alert_ids()
	var seen: Dictionary = {}
	if not alerted.is_empty() and is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(&"structure"):
			var piece := node as Actor
			if piece == null or piece.is_planned or piece.commander_id <= 0:
				continue
			var abilities := piece.get_node_or_null("Abilities") as Abilities
			if abilities == null:
				continue
			for ability: StringName in alerted:
				if abilities.grants(ability):
					seen[piece.get_instance_id()] = true
					_track_caster(piece, abilities, ability, a_now)
					break
	for id: int in _casters.keys():
		if not seen.has(id):
			var entry: Dictionary = _casters[id]
			if entry["built"]:
				_announce_to_others(AlertCatalog.Type.SUPERWEAPON_LOST, entry, id, a_now)
			_casters.erase(id)


func _track_caster(
	a_piece: Actor, a_abilities: Abilities, a_ability: StringName, a_now: int
) -> void:
	var id: int = a_piece.get_instance_id()
	var charges: int = a_abilities.charges_of(a_ability)
	if not _casters.has(id):
		_casters[id] = {
			"piece": weakref(a_piece),
			"owner": a_piece.commander_id,
			"ability": a_ability,
			"built": false,
			"charges": charges,
			"title": AbilityCatalog.title_of(a_ability),
		}
		if not a_piece.is_built:
			_announce_to_others(AlertCatalog.Type.SUPERWEAPON_BEGUN, _casters[id], id, a_now)
	var entry: Dictionary = _casters[id]
	# Captured: it is the new owner's now, and announced as theirs from here on.
	entry["owner"] = a_piece.commander_id
	if not entry["built"] and a_piece.is_built:
		entry["built"] = true
		entry["charges"] = charges
		_announce_to_others(AlertCatalog.Type.SUPERWEAPON_BUILT, entry, id, a_now)
		return
	if not entry["built"]:
		return
	var before: int = int(entry["charges"])
	entry["charges"] = charges
	if charges > before:
		_announce_ready(a_piece, entry, id, a_now)
	elif charges < before:
		_announce_to_others(AlertCatalog.Type.SUPERWEAPON_LAUNCHED, entry, id, a_now)


## A charge came back to a pool that authors `alert: true`: told to the caster's owner, at the
## caster. A global-alert ability's pool is skipped — SUPERWEAPON_READY already says it, to
## everyone. Pools register themselves (Abilities.ALERTING_GROUP) so nothing else is scanned.
func _poll_ability_charges(a_now: int) -> void:
	if not is_inside_tree():
		return
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(Abilities.ALERTING_GROUP):
		var pools := node as Abilities
		var piece := pools.get_parent() as Actor if pools != null else null
		if piece == null or piece.commander_id <= 0 or piece.is_planned or not piece.is_built:
			continue
		for i: int in pools.pool_count():
			if not pools.alerts_on_charge(i):
				continue
			var key: String = "%d:%d" % [pools.get_instance_id(), i]
			seen[key] = true
			var charges: int = pools.pool_charges(i)
			var before: int = int(_pool_charges.get(key, charges))
			_pool_charges[key] = charges
			if charges <= before:
				continue
			var ability: StringName = pools.pool_first_grant(i)
			if AbilityCatalog.has_global_alert(ability):
				continue
			var text: String = AlertCatalog.text_of(
				AlertCatalog.Type.ABILITY_CHARGED, AbilityCatalog.title_of(ability)
			)
			var alert := Alert.make(
				AlertCatalog.Type.ABILITY_CHARGED, piece.commander_id, a_now, text
			)
			alert.key = pools.get_instance_id()
			raise(alert.located_at(piece.global_position).about(piece))
	for key: String in _pool_charges.keys():
		if not seen.has(key):
			_pool_charges.erase(key)


## Ready: its owner is told where (it is theirs); everyone else is told only that it is.
func _announce_ready(a_piece: Actor, a_entry: Dictionary, a_key: int, a_now: int) -> void:
	var title: String = a_entry["title"]
	var own := Alert.make(
		AlertCatalog.Type.SUPERWEAPON_READY, int(a_entry["owner"]), a_now, "%s ready" % title
	)
	own.key = a_key
	raise(own.located_at(a_piece.global_position).about(a_piece))
	_announce_to_others(
		AlertCatalog.Type.SUPERWEAPON_READY, a_entry, a_key, a_now, "Enemy %s ready"
	)


## Tell every commander but the caster's owner, never with a position.
func _announce_to_others(
	a_type: AlertCatalog.Type, a_entry: Dictionary, a_key: int, a_now: int, a_format: String = ""
) -> void:
	var owner: int = int(a_entry["owner"])
	var title: String = a_entry["title"]
	for commander: Variant in _commanders:
		var c := commander as Commander
		if c == null or c.id <= 0 or c.id == owner:
			continue
		var text: String = (
			a_format % title if a_format != "" else AlertCatalog.text_of(a_type, title)
		)
		var alert := Alert.make(a_type, c.id, a_now, text)
		alert.about_id = owner
		alert.key = a_key
		raise(alert)


#endregion


#region Private helpers
## The piece's player-facing name: its purchase button's label (the doc title), else its scene
## root's name, else its own node name. Not the node name first: the engine renames a piece
## added beside a same-named sibling to `@CharacterBody3D@123`, which is every second Recruit.
static func title_of(a_piece: Node) -> String:
	var entity := a_piece as Entity
	if entity != null:
		var tool: Tool = Tool.for_id(entity.id)
		if tool != null and tool.label != "":
			return tool.label
	if a_piece.scene_file_path != "":
		var packed := load(a_piece.scene_file_path) as PackedScene
		if packed != null and packed.get_state().get_node_count() > 0:
			return String(packed.get_state().get_node_name(0))
	return String(a_piece.name)


func _listen_to_commanders() -> void:
	for commander: Variant in _commanders:
		var c := commander as Commander
		if c == null or c.id <= 0 or _listened.has(c.id):
			continue
		_listened[c.id] = true
		c.construction_finished.connect(_on_construction_finished.bind(c))
		c.unit_trained.connect(_on_unit_trained.bind(c))
		c.upgrade_researched.connect(_on_upgrade_researched.bind(c))


func _throttle_for(a_viewer_id: int) -> AlertThrottle:
	if not _throttles.has(a_viewer_id):
		_throttles[a_viewer_id] = AlertThrottle.new()
	return _throttles[a_viewer_id]


func _latch(a_table: Dictionary, a_id: int, a_type: AlertCatalog.Type) -> AlertLatch:
	if not a_table.has(a_id):
		a_table[a_id] = AlertLatch.new(
			AlertCatalog.sustain_ticks(a_type), AlertCatalog.repeat_ticks(a_type)
		)
	return a_table[a_id]
#endregion
