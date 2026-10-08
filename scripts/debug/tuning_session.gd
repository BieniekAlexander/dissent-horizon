class_name TuningSession
extends Node

## The debug tuning editor's model: the spec docs being edited, the live pieces they preview
## on, and the save that writes them back. gdd/systems/ux/ui/debug-tuning.md is the design.
##
## THE DOC IS WHAT IS EDITED. Every edit is written into the doc's text in memory at once
## (FrontmatterWriter), so the editor shows what the doc will say and a shape the writer
## cannot express fails at the edit rather than at the save. The live pieces are a PREVIEW of
## the doc: an edit is converted to the runtime value (PieceFields.from_doc) and written onto
## every piece of that type, and onto every one that enters play after it (`_on_node_added`).
##
## One session per running game, reached through `of()`. It exists only once debug tuning is
## first used; nothing about a normal match touches it.

## Raised after any edit, save or library change, so open readouts re-read their values.
signal changed

## Where the spec docs are. A var so a test can point a session at fixture docs; the game's
## session always reads the project's.
var gdd_root: String = "res://gdd"
## The spec tooling is LOADED, never preloaded: it lives under tools/, and a game script that
## preloaded it would fail to load wherever tools/ is not shipped.
const WRITER_PATH: String = "res://tools/spec_import/frontmatter_writer.gd"
const FRONTMATTER_PATH: String = "res://tools/spec_import/frontmatter.gd"
const REGISTRY_PATH: String = "res://tools/spec_import/spec_registry.gd"
const PHASES_PATH: String = "res://tools/spec_import/emission_phases.gd"
const SPEED_LIBRARY_KIND: String = "SpeedLibrary"
const SHAPE_LIBRARY_KIND: String = "ShapeLibrary"
## The EmissionPhase properties a doc's phase expands to (EmissionPhases.expand), which a
## rebuilt emission is given. Everything the expansion returns except its bookkeeping keys.
const PHASE_BOOKKEEPING: Array[String] = ["name", "visual_roles", "emits"]
## The `motion:` keys that NAME a speed class rather than give a number — the ones
## SpecRegistry._resolve_speed_classes resolves, and only those.
const PHASE_SPEED_KEYS: Array[String] = ["speed", "coast_speed"]
## How a normative rule's refusal names itself in an importer error: "<rule> [normative]:".
const RULE_PATTERN: String = "\\]: (\\w+) \\[normative\\]:"

static var _instance: TuningSession = null

var _writer: GDScript
var _frontmatter: GDScript
## doc path -> {"original": String, "text": String, "data": Dictionary}. Memoized: a doc is
## read once per session, and its text is the edited one from then on.
var _docs: Dictionary = {}
## Discovery, built once: piece / emission id -> doc path, an inline emission's id -> its
## address, and the two libraries' doc paths.
var _ids: Dictionary = {}
var _speed_path: String = ""
var _shape_path: String = ""
## piece id -> [{scope, index, field}]: what has been edited on that type, re-applied to every
## one that enters play. An incremental index, kept because a spawn must not re-read every doc.
var _edits: Dictionary = {}
## Emission id -> its address, for every emission whose doc differs from its scene: rebuilt as
## it enters play.
var _edited_emissions: Dictionary = {}


#region Lifetime
## The running session, made on first use under the scene root.
static func of(a_from: Node) -> TuningSession:
	if is_instance_valid(_instance):
		return _instance
	_instance = TuningSession.new()
	_instance.name = "TuningSession"
	a_from.get_tree().root.add_child(_instance)
	return _instance


## The running session if one exists, else null — for code that only reacts to tuning.
static func current() -> TuningSession:
	return _instance if is_instance_valid(_instance) else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_writer = load(WRITER_PATH)
	_frontmatter = load(FRONTMATTER_PATH)
	_discover()
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


#endregion


#region Addresses
## Where a scope's values live: a doc and the path to the scope's root inside it. Empty when
## the doc is not found (a piece with no spec).
func piece_address(a_id: StringName) -> Dictionary:
	var path: String = _ids.get(String(a_id), "")
	return {} if path.is_empty() else {"path": path, "prefix": []}


func weapon_address(a_piece: StringName, a_index: int) -> Dictionary:
	return _child_address(piece_address(a_piece), ["weapons", a_index])


func pool_address(a_piece: StringName, a_index: int) -> Dictionary:
	return _child_address(piece_address(a_piece), ["abilities", a_index])


## The emission weapon `a_index` fires: inline under its `emits:`, or its own doc.
func emission_address(a_piece: StringName, a_index: int) -> Dictionary:
	var weapon: Dictionary = weapon_address(a_piece, a_index)
	if weapon.is_empty():
		return {}
	var emits: Variant = value_at(weapon, ["emits"])
	if emits is Dictionary:
		return _child_address(weapon, ["emits"])
	if emits is String or emits is StringName:
		return piece_address(StringName(emits))
	return {}


## The id an emission address stands for.
func emission_id(a_address: Dictionary) -> StringName:
	var id: Variant = value_at(a_address, ["id"])
	if id != null:
		return StringName(str(id))
	return StringName(String(a_address.get("path", "")).get_file().get_basename())


func phase_address(a_emission: Dictionary, a_index: int) -> Dictionary:
	return _child_address(a_emission, ["phases", a_index])


static func _child_address(a_parent: Dictionary, a_steps: Array) -> Dictionary:
	if a_parent.is_empty():
		return {}
	return {"path": a_parent["path"], "prefix": (a_parent["prefix"] as Array) + a_steps}


#endregion


#region Reading
## The doc's value at `a_path` under an address, or null where the doc does not say.
func value_at(a_address: Dictionary, a_path: Array) -> Variant:
	if a_address.is_empty():
		return null
	var doc: Dictionary = _doc(a_address["path"])
	return _writer.value_at(doc["data"], (a_address["prefix"] as Array) + a_path)


## What a field's editor shows: the doc's value, or — where the doc leaves it to the default —
## the value the running piece holds, in doc units. {"value": Variant, "is_default": bool}.
func shown_value(a_address: Dictionary, a_field: PieceField, a_ctx: Dictionary) -> Dictionary:
	var authored: Variant = value_at(a_address, a_field.doc_path)
	if authored != null:
		return {"value": authored, "is_default": false}
	var raw: Variant = a_field.read_raw(a_ctx) if not a_ctx.is_empty() else null
	return {"value": PieceFields.to_doc(a_field, raw, speed_ladder()), "is_default": true}


## The speed ladder as the session's docs say it, slowest first: {class: u/s}.
func speed_ladder() -> Dictionary:
	if _speed_path.is_empty():
		return {}
	var speeds: Variant = value_at({"path": _speed_path, "prefix": []}, ["speeds"])
	return speeds if speeds is Dictionary else {}


## Library shape ids starting with `a_prefix`, smallest first.
func shape_ids(a_prefix: String) -> Array:
	var ids: Array = []
	var shapes: Variant = value_at({"path": _shape_path, "prefix": []}, ["shapes"])
	if shapes is Dictionary:
		for id: String in shapes:
			if id.begins_with(a_prefix):
				ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return shape_radius(a) < shape_radius(b))
	return ids


func shape_radius(a_id: String) -> float:
	var radius: Variant = value_at({"path": _shape_path, "prefix": []}, ["shapes", a_id, "radius"])
	return float(radius) if radius != null else -1.0


## An emission's phases as a list, whether the doc writes `phases:` or the flat shorthand.
func phases_of(a_emission: Dictionary) -> Array:
	var phases: Variant = value_at(a_emission, ["phases"])
	if phases is Array:
		return phases
	var spec: Variant = value_at(a_emission, [])
	return load(PHASES_PATH)._shorthand_items(spec) if spec is Dictionary else []


## The name phase `a_index` runs under — its own, or the one the importer gives an unnamed phase,
## which is what its EmissionPhase node is called.
func phase_name(a_phases: Array, a_index: int) -> String:
	var item: Variant = a_phases[a_index]
	if item is Dictionary and (item as Dictionary).has("name"):
		return str(item["name"])
	var defaults: Array = load(PHASES_PATH).DEFAULT_NAMES
	return defaults[a_index] if a_index < defaults.size() else "Phase%d" % a_index


## Everything wrong with an emission's phase grammar, as the importer would say it. A broken
## emission is not previewed: pieces keep firing its last valid form until it is fixed.
func emission_errors(a_emission: Dictionary) -> Array[String]:
	var spec: Variant = value_at(a_emission, [])
	if not (spec is Dictionary):
		return []
	return load(PHASES_PATH).errors_for(_resolved_emission(spec))


## Docs with unsaved edits.
func unsaved_paths() -> Array:
	return _docs.keys().filter(
		func(p: String) -> bool: return _docs[p]["text"] != _docs[p]["original"]
	)


#endregion


#region Editing a piece
## Set a field under an address, and preview it on every piece of `a_piece`'s type. A null
## `a_value` removes the key, returning the field to its default. Returns "" or an error.
func edit(
	a_address: Dictionary, a_field: PieceField, a_value: Variant, a_piece: StringName, a_index: int
) -> String:
	_note_simulation_changed()
	if a_address.is_empty():
		return "this piece has no spec doc"
	var ladder: Dictionary = speed_ladder()
	var old_raw: Variant = PieceFields.from_doc(
		a_field, value_at(a_address, a_field.doc_path), ladder
	)
	var error: String = _write_field(a_address, a_field, a_value)
	if not error.is_empty():
		return error
	var new_raw: Variant = PieceFields.from_doc(
		a_field, value_at(a_address, a_field.doc_path), ladder
	)
	match a_field.scope:
		PieceField.Scope.EMISSION, PieceField.Scope.PHASE:
			_mark_emission(a_address)
		_:
			_remember(a_piece, a_field, a_index)
			if a_field.is_live and a_field.write.is_valid() and new_raw != null:
				for piece: Entity in live_pieces(a_piece):
					var ctx: Dictionary = context_of(piece, a_field.scope, a_index)
					if not ctx.is_empty():
						a_field.write.call(
							ctx, old_raw if old_raw != null else a_field.read_raw(ctx), new_raw
						)
	changed.emit()
	return ""


## Replace an emission's whole phase list — adding, removing or reordering phases.
func set_phases(a_emission: Dictionary, a_phases: Array) -> String:
	_note_simulation_changed()
	var error: String = _convert_shorthand(a_emission)
	if error.is_empty():
		error = _write(a_emission, ["phases"], a_phases)
	if error.is_empty():
		_mark_emission(a_emission)
		changed.emit()
	return error


## Record a waiver for a calibration rule the doc breaks on purpose.
func waive(a_path: String, a_rule: String, a_reason: String) -> String:
	var error: String = _write({"path": a_path, "prefix": []}, ["exceptions", a_rule], a_reason)
	if error.is_empty():
		changed.emit()
	return error


## The `ctx` a PieceField reads and writes through, for one scope of a live piece. Empty when
## the piece has no such weapon or pool.
func context_of(a_piece: Entity, a_scope: PieceField.Scope, a_index: int) -> Dictionary:
	match a_scope:
		PieceField.Scope.PIECE:
			return {"node": a_piece}
		PieceField.Scope.WEAPON:
			var name: Variant = value_at(weapon_address(a_piece.id, a_index), ["name"])
			var weapon: Node = (
				a_piece.get_node_or_null("Loadout/%s" % name) if name != null else null
			)
			return {"node": weapon, "piece": a_piece} if weapon is Weapon else {}
		PieceField.Scope.POOL:
			var abilities: Node = a_piece.get_node_or_null("Abilities")
			return {"node": abilities, "index": a_index} if abilities is Abilities else {}
	return {}


## Every live piece of a type, whoever owns it.
func live_pieces(a_id: StringName) -> Array[Entity]:
	var pieces: Array[Entity] = []
	for node: Node in get_tree().get_nodes_in_group(&"piece"):
		if node is Entity and (node as Entity).id == a_id:
			pieces.append(node)
	return pieces


## A tuning edit changes live pieces, which no player order can: it ends the match's recording.
func _note_simulation_changed() -> void:
	var scenario: Scenario = Scenario.of(self) if is_inside_tree() else null
	if scenario != null:
		scenario.note_debug_change("a piece was retuned")


func _write_field(a_address: Dictionary, a_field: PieceField, a_value: Variant) -> String:
	# Reach written as one id for both layers is split before either layer is changed.
	if a_field.doc_path.size() == 2 and a_field.doc_path[0] == "reach":
		var reach: Variant = value_at(a_address, ["reach"])
		if reach is String:
			var error: String = _write(a_address, ["reach"], {"ground": reach, "air": reach})
			if not error.is_empty():
				return error
	if a_field.scope == PieceField.Scope.PHASE:
		var emission: Dictionary = {
			"path": a_address["path"], "prefix": (a_address["prefix"] as Array).slice(0, -2)
		}
		var error: String = _convert_shorthand(emission)
		if not error.is_empty():
			return error
	# A closed hold admits nothing by order, so its masks go with it (the importer refuses both).
	if a_field.doc_path == ["garrison", "closed"] and a_value == true:
		for mask: String in ["frames", "armours", "movements"]:
			_remove(a_address, ["garrison", mask])
	return _write(a_address, a_field.doc_path, a_value)


func _remember(a_piece: StringName, a_field: PieceField, a_index: int) -> void:
	var edits: Array = _edits.get(a_piece, [])
	for edit: Dictionary in edits:
		if edit["field"] == a_field and edit["index"] == a_index:
			return
	edits.append({"field": a_field, "index": a_index})
	_edits[a_piece] = edits


func _mark_emission(a_address: Dictionary) -> void:
	var emission: Dictionary = a_address
	var prefix: Array = a_address["prefix"]
	var phases_at: int = prefix.find("phases")
	if phases_at >= 0:
		emission = {"path": a_address["path"], "prefix": prefix.slice(0, phases_at)}
	_edited_emissions[emission_id(emission)] = emission
	for node: Node in get_tree().get_nodes_in_group(&"piece"):
		if node is Entity:
			_refresh_shot_profiles_of(node)


#endregion


#region Libraries
## Retune one speed class, and every piece and emission naming it. The ladder stays strictly
## increasing, as the importer requires of it.
func set_speed(a_class: String, a_value: float) -> String:
	_note_simulation_changed()
	var ladder: Dictionary = speed_ladder()
	var names: Array = ladder.keys()
	var at: int = names.find(a_class)
	if at < 0:
		return "%s is not a speed class" % a_class
	if at > 0 and a_value <= float(ladder[names[at - 1]]):
		return "%s must be faster than %s (%s)" % [a_class, names[at - 1], ladder[names[at - 1]]]
	if at < names.size() - 1 and a_value >= float(ladder[names[at + 1]]):
		return "%s must be slower than %s (%s)" % [a_class, names[at + 1], ladder[names[at + 1]]]
	var old: float = float(ladder[a_class])
	var error: String = _write({"path": _speed_path, "prefix": []}, ["speeds", a_class], a_value)
	if not error.is_empty():
		return error
	var speed_field: PieceField = _piece_field(["movement", "speed"])
	for id: String in _ids:
		var address: Dictionary = piece_address(StringName(id))
		if str(value_at(address, ["movement", "speed"])) == a_class:
			_remember(StringName(id), speed_field, 0)
			for piece: Entity in live_pieces(StringName(id)):
				speed_field.write.call({"node": piece}, old, a_value)
		_mark_emissions_naming(address, a_class)
	changed.emit()
	return ""


## Retune one library shape's radius. The shape is ONE resource every piece naming it shares, so
## the change reaches them all at once; what is derived from it is then re-derived.
func set_shape_radius(a_id: String, a_radius: float) -> String:
	_note_simulation_changed()
	if a_radius <= 0.0:
		return "a radius must be more than zero"
	var shape: Shape3D = PieceFields.shape_resource(a_id)
	if shape == null:
		return "%s is not in the shape library" % a_id
	var error: String = _write(
		{"path": _shape_path, "prefix": []}, ["shapes", a_id, "radius"], a_radius
	)
	if not error.is_empty():
		return error
	if shape is CylinderShape3D:
		(shape as CylinderShape3D).radius = a_radius
	elif shape is SphereShape3D:
		(shape as SphereShape3D).radius = a_radius
	var bonus: PieceField = _piece_field(["garrison", "range_bonus"])
	for node: Node in get_tree().get_nodes_in_group(&"piece"):
		if not (node is Entity):
			continue
		var piece: Entity = node
		var pair: Variant = value_at(piece_address(piece.id), ["garrison", "range_bonus"])
		if pair is Dictionary and a_id in (pair as Dictionary).values():
			bonus.write.call({"node": piece}, null, PieceFields.from_doc(bonus, pair))
		piece.refresh_aggro_shapes()
	changed.emit()
	return ""


func _mark_emissions_naming(a_piece: Dictionary, a_class: String) -> void:
	var weapons: Variant = value_at(a_piece, ["weapons"])
	if not (weapons is Array):
		return
	for i: int in (weapons as Array).size():
		var emission: Dictionary = _child_address(a_piece, ["weapons", i, "emits"])
		var emits: Variant = value_at(emission, [])
		if emits is String:
			emission = piece_address(StringName(emits))
			emits = value_at(emission, [])
		if emits is Dictionary and _names_speed(emits, a_class):
			_mark_emission(emission)


## Whether an emission spec flies at `a_class` in its shorthand or in any phase.
static func _names_speed(a_spec: Dictionary, a_class: String) -> bool:
	if str(a_spec.get("speed", "")) == a_class:
		return true
	for item: Variant in a_spec.get("phases", []):
		if item is Dictionary and item.get("motion") is Dictionary:
			for key: String in PHASE_SPEED_KEYS:
				if str(item["motion"].get(key, "")) == a_class:
					return true
	return false


#endregion


#region Play
## A piece or emission entering play takes the session's edits before its own _ready, exactly
## as it would from a re-imported scene. node_added fires before the node's children enter the
## tree, which is what lets an emission's phase children be replaced here.
func _on_node_added(a_node: Node) -> void:
	if not (a_node is Entity):
		return
	var entity: Entity = a_node
	if _edits.has(entity.id):
		_apply_edits(entity)
	if _edited_emissions.has(entity.id):
		_rebuild_emission(entity, _edited_emissions[entity.id])


func _apply_edits(a_piece: Entity) -> void:
	var ladder: Dictionary = speed_ladder()
	for edit: Dictionary in _edits[a_piece.id]:
		var field: PieceField = edit["field"]
		if not field.is_live or not field.write.is_valid():
			continue
		var ctx: Dictionary = context_of(a_piece, field.scope, edit["index"])
		var address: Dictionary = _scope_address(a_piece.id, field.scope, edit["index"])
		var raw: Variant = PieceFields.from_doc(field, value_at(address, field.doc_path), ladder)
		if not ctx.is_empty() and raw != null:
			field.write.call(ctx, field.read_raw(ctx), raw)
	_refresh_shot_profiles_of(a_piece)


func _scope_address(a_piece: StringName, a_scope: PieceField.Scope, a_index: int) -> Dictionary:
	match a_scope:
		PieceField.Scope.WEAPON:
			return weapon_address(a_piece, a_index)
		PieceField.Scope.POOL:
			return pool_address(a_piece, a_index)
	return piece_address(a_piece)


## Give an emission entering play its doc's payload and phases. A doc whose phase grammar is
## broken is skipped: the emission flies as its scene says.
func _rebuild_emission(a_emission: Entity, a_address: Dictionary) -> void:
	var spec: Variant = value_at(a_address, [])
	if not (spec is Dictionary) or not emission_errors(a_address).is_empty():
		return
	var resolved: Dictionary = _resolved_emission(spec)
	var payload: Payload = Payload.of(a_emission)
	if payload != null:
		if resolved.has("damage"):
			payload.base_damage = float(resolved["damage"])
		if resolved.has("damage_type"):
			payload.damage_type = Damage.Type.get(str(resolved["damage_type"]), payload.damage_type)
		for flag: String in ["hitscan", "bio_ground_aim"]:
			if resolved.has(flag):
				payload.set(flag, bool(resolved[flag]))
	var hit_shape: CollisionShape3D = a_emission.get_node_or_null("HitShape") as CollisionShape3D
	if hit_shape != null and resolved.has("blast"):
		var blast: Shape3D = PieceFields.shape_resource(str(resolved["blast"]))
		if blast != null:
			hit_shape.shape = blast
	if resolved.has("status_effects"):
		_rebuild_effects(a_emission, (resolved["status_effects"] as Array).map(str))
	_rebuild_phases(a_emission, load(PHASES_PATH).expand(resolved))


## Make the effects an emission applies exactly the doc's list: each is an instance of the scene
## its status-effect doc names, under the emission's EffectApplicator, as the importer builds it.
func _rebuild_effects(a_emission: Entity, a_ids: Array) -> void:
	var applicator: Node = a_emission.get_node_or_null("EffectApplicator")
	if applicator == null:
		if a_ids.is_empty():
			return
		applicator = EffectApplicator.new()
		applicator.name = "EffectApplicator"
		a_emission.add_child(applicator)
	var have: Array = PieceFields.applied_effects(a_emission)
	for child: Node in applicator.get_children():
		if child is StatusEffect and not a_ids.has(child.scene_file_path.get_file().get_basename()):
			applicator.remove_child(child)
			child.free()
	for id: String in a_ids:
		if have.has(id):
			continue
		var scene_path: Variant = value_at(piece_address(StringName(id)), ["scene"])
		if scene_path != null and ResourceLoader.exists(str(scene_path)):
			applicator.add_child((load(str(scene_path)) as PackedScene).instantiate())


func _rebuild_phases(a_emission: Entity, a_phases: Array[Dictionary]) -> void:
	var existing: Dictionary = {}
	for child: Node in a_emission.get_children():
		if child is EmissionPhase:
			existing[String(child.name)] = child
	var wanted: Array[String] = []
	for phase: Dictionary in a_phases:
		wanted.append(str(phase["name"]))
	for name: String in existing:
		if not wanted.has(name):
			var stale: Node = existing[name]
			a_emission.remove_child(stale)
			stale.free()
	var order: int = 0
	for phase: Dictionary in a_phases:
		var node: EmissionPhase = existing.get(str(phase["name"]))
		if node == null:
			node = EmissionPhase.new()
			node.name = str(phase["name"])
			a_emission.add_child(node)
		for key: String in phase:
			if not PHASE_BOOKKEEPING.has(key):
				node.set(key, phase[key])
		var visuals: Array[NodePath] = []
		for role: Variant in phase["visual_roles"]:
			if a_emission.has_node(str(role)):
				visuals.append(NodePath(str(role)))
		node.visuals = visuals
		# Phases run in tree order, so they are put in the doc's order after every other child.
		a_emission.move_child(node, a_emission.get_child_count() - a_phases.size() + order)
		order += 1


## An emission spec with every speed class swapped for its number — what the importer hands
## EmissionPhases, which reads only numbers.
func _resolved_emission(a_spec: Dictionary) -> Dictionary:
	var spec: Dictionary = a_spec.duplicate(true)
	var ladder: Dictionary = speed_ladder()
	if spec.has("speed") and ladder.has(str(spec["speed"])):
		spec["speed"] = ladder[str(spec["speed"])]
	if spec.get("phases") is Array:
		for item: Variant in spec["phases"]:
			if item is Dictionary and item.get("motion") is Dictionary:
				var motion: Dictionary = item["motion"]
				for key: String in PHASE_SPEED_KEYS:
					if ladder.has(str(motion.get(key, ""))):
						motion[key] = ladder[str(motion[key])]
	return spec


## Point a piece's weapons that fire an edited emission at the doc's damage, so its readout
## and the bot's estimate read the new number.
func _refresh_shot_profiles_of(a_piece: Entity) -> void:
	var weapons: Variant = value_at(piece_address(a_piece.id), ["weapons"])
	if not (weapons is Array):
		return
	for i: int in (weapons as Array).size():
		var emission: Dictionary = emission_address(a_piece.id, i)
		if emission.is_empty() or not _edited_emissions.has(emission_id(emission)):
			continue
		var ctx: Dictionary = context_of(a_piece, PieceField.Scope.WEAPON, i)
		var damage: Variant = value_at(emission, ["damage"])
		var damage_type: Variant = value_at(emission, ["damage_type"])
		if ctx.is_empty() or damage == null:
			continue
		var weapon: Weapon = ctx["node"]
		weapon.set_shot_profile(
			float(damage), Damage.Type.get(str(damage_type), weapon.per_shot_damage_type())
		)


#endregion


#region Saving
## Validate every edited doc as the importer would, then write the ones that pass. Nothing is
## written for a doc that fails; it stays edited in the session so it can be fixed or waived.
## Returns {"saved": [paths], "refused": [{path, id, message, rule}]}; `rule` is the calibration
## rule a waiver could declare, or "".
func save() -> Dictionary:
	var report: Dictionary = {"saved": [], "refused": []}
	var unsaved: Array = unsaved_paths()
	if unsaved.is_empty():
		return report
	var errors: Array = _validate({})
	var failing: Dictionary = {}
	for error: String in errors:
		var path: String = _path_of(error, unsaved)
		if path.is_empty():
			continue
		failing[path] = true
		var rule: RegExMatch = RegEx.create_from_string(RULE_PATTERN).search(error)
		(
			report["refused"]
			. append(
				{
					"path": path,
					"id": path.get_file().get_basename(),
					"message": error.substr(path.length()).strip_edges(),
					"rule": rule.get_string(1) if rule != null else "",
				}
			)
		)
	# What would actually be written is the passing docs beside the failing ones AS THEY ARE ON
	# DISK; validated once more, since one doc's error can depend on another's edit (a library
	# rung). Any error left — or one in a doc nobody edited — blocks the save outright.
	var blocking: Array = errors if failing.is_empty() else _validate(failing)
	blocking = blocking.filter(
		func(e: String) -> bool:
			return _path_of(e, unsaved).is_empty() or not failing.has(_path_of(e, unsaved))
	)
	if not blocking.is_empty():
		for error: String in blocking:
			report["refused"].append({"path": "", "id": "", "message": error, "rule": ""})
		return report
	for path: String in unsaved:
		if failing.has(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			report["refused"].append(
				{"path": path, "id": "", "message": "cannot write the file", "rule": ""}
			)
			continue
		file.store_string(_docs[path]["text"])
		file.close()
		_docs[path]["original"] = _docs[path]["text"]
		report["saved"].append(path)
	changed.emit()
	return report


## The unsaved doc an importer error names, or "".
static func _path_of(a_error: String, a_paths: Array) -> String:
	for path: String in a_paths:
		if a_error.begins_with(path):
			return path
	return ""


## The importer's validation over every doc, with the session's edits in place of the disk's
## except for the docs in `a_from_disk`. Writes nothing: SpecRegistry.build validates and
## records, and the pipeline's writing stages are never run.
func _validate(a_from_disk: Dictionary) -> Array:
	var docs: Array = []
	for path: String in _markdown_paths():
		var is_edited: bool = _docs.has(path) and not a_from_disk.has(path)
		var data: Variant = (
			_docs[path]["data"] if is_edited else _frontmatter.parse_file(path).get("data")
		)
		if data is Dictionary and data.get("kind") != null and not str(data["kind"]).is_empty():
			docs.append({"path": path, "data": (data as Dictionary).duplicate(true)})
	var registry: RefCounted = load(REGISTRY_PATH).new()
	registry.build(docs)
	return registry.errors


#endregion


#region Docs
func _doc(a_path: String) -> Dictionary:
	if not _docs.has(a_path):
		var text: String = FileAccess.get_file_as_string(a_path)
		var parsed: Dictionary = _frontmatter.parse(text)
		_docs[a_path] = {"original": text, "text": text, "data": parsed.get("data", {})}
	return _docs[a_path]


func _write(a_address: Dictionary, a_path: Array, a_value: Variant) -> String:
	if a_value == null:
		return _remove(a_address, a_path)
	var doc: Dictionary = _doc(a_address["path"])
	var result: Dictionary = _writer.set_value(
		doc["text"], (a_address["prefix"] as Array) + a_path, a_value
	)
	return _take(doc, result)


func _remove(a_address: Dictionary, a_path: Array) -> String:
	var doc: Dictionary = _doc(a_address["path"])
	var result: Dictionary = _writer.remove_value(
		doc["text"], (a_address["prefix"] as Array) + a_path
	)
	return _take(doc, result)


func _take(a_doc: Dictionary, a_result: Dictionary) -> String:
	if not a_result["ok"]:
		return str(a_result["error"])
	a_doc["text"] = a_result["text"]
	a_doc["data"] = _frontmatter.parse(a_result["text"])["data"]
	return ""


## Turn an emission's flat `speed:` / `trajectory:` shorthand into the explicit phase list it
## stands for, so one phase can be edited.
func _convert_shorthand(a_emission: Dictionary) -> String:
	if value_at(a_emission, ["phases"]) != null:
		return ""
	var phases: Array = phases_of(a_emission)
	var error: String = _write(a_emission, ["phases"], phases)
	for flat: String in ["speed", "trajectory"]:
		if error.is_empty():
			error = _remove(a_emission, [flat])
	return error


func _piece_field(a_path: Array) -> PieceField:
	for field: PieceField in PieceFields.of_scope(PieceField.Scope.PIECE):
		if field.doc_path == a_path:
			return field
	return null


## Index every spec doc by id, and the inline emissions and libraries inside them. A doc is
## parsed here once; only the ones edited are kept.
func _discover() -> void:
	for path: String in _markdown_paths():
		var parsed: Dictionary = _frontmatter.parse_file(path)
		var data: Variant = parsed.get("data")
		if not (data is Dictionary) or data.get("kind") == null:
			continue
		match str(data["kind"]):
			SPEED_LIBRARY_KIND:
				_speed_path = path
			SHAPE_LIBRARY_KIND:
				_shape_path = path
			_:
				_ids[path.get_file().get_basename()] = path


func _markdown_paths() -> Array:
	var paths: Array = []
	_collect(gdd_root, paths)
	paths.sort()
	return paths


static func _collect(a_dir: String, a_out: Array) -> void:
	for file: String in DirAccess.get_files_at(a_dir):
		if file.get_extension() == "md":
			a_out.append(a_dir.path_join(file))
	for dir: String in DirAccess.get_directories_at(a_dir):
		if not dir.begins_with("."):
			_collect(a_dir.path_join(dir), a_out)
#endregion
