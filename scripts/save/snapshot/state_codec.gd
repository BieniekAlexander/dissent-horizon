class_name StateCodec
extends RefCounted

## The SNAPSHOT's codec: turns the run-time state of the simulation's objects into JSON-safe values
## and back, by REFLECTION — every script variable an object declares is carried unless its class
## says otherwise, so a field added later is saved without anyone remembering to. Decided
## 2026-10-27 (Alex); gdd/systems/commands/saved-games.md §The snapshot.
##
## What a class may declare, all optional:
##   * `snapshot_skip() -> Array` — fields that are derived (caches, memos) or rebuilt by the
##     scene, and so are not saved. A subclass appends to `super()`.
##   * `snapshot_fields() -> Array` — the ONLY fields saved, for an object most of whose fields
##     are wiring rather than state (the Scenario).
##   * `snapshot_extra() -> Dictionary` and `restore_snapshot_extra(d: Dictionary)` — what
##     reflection cannot carry: a Callable as a tag, a connection to re-make.
##   * `snapshot_identity_fields() -> Array` — the fields that name an object among others of its
##     kind (a bot job's brain and name), so a saved list is matched to the rebuilt one by them,
##     not by place.
##   * `prepare_snapshot_restore()` — on a node outside a piece, called with the structure, before
##     any field is set: for what a node otherwise builds lazily, which the restore must find
##     built to fill it (a bot brain's managers and jobs).
##   * `finish_snapshot_restore()` — called once the whole world is restored, for what needs all
##     of it in place (SimulationSnapshot): redrawing a remembered image where its structure is.
## Anything else the codec cannot encode — a Callable, a Signal, an RID — fails an assertion: a
## field silently left out is a match that drifts after a load, which is the bug to find.
##
## References: a piece is its spawn serial, a node inside a piece is its serial and path, any
## other node is its path under the Scenario, a commander is its id, a file-backed resource is
## its path, and a catalogue Tool is its command name. Every other object — a command, a
## purchase, a scripted resource built in a scene — goes in an OBJECT TABLE by id, so two fields
## that shared one object share it again after a load.
##
## Decoding fills objects IN PLACE where the freshly built scene already has one of the same
## script (a trigger's condition, a bot's claims), and makes the rest.
##
## A float is written as the hex of its eight bytes, and an int too large for a double as a string:
## a restore must be exact to the bit, and JSON's decimal numbers are not — Godot's reader rounds
## some doubles a bit off (measured 2026-10-27), refuses those near the top of the range, and has
## no form for an infinity. Outside a typed slot, a float is tagged.
## The value types whose components are text, never a float's bits.
const _TEXT_TYPES: Array[int] = [TYPE_NODE_PATH, TYPE_PACKED_STRING_ARRAY]
## The value types whose components are ints.
const _INT_TYPES: Array[int] = [
	TYPE_VECTOR2I,
	TYPE_VECTOR3I,
	TYPE_VECTOR4I,
	TYPE_RECT2I,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
]
## The largest magnitude a double holds as an exact integer.
const _SAFE_INT: int = 1 << 53
## How deep a script's inner classes are searched for a script key. GDScript nests rarely past
## two; the bound only stops a cycle.
const _INNER_DEPTH_MAX: int = 4
const _SCRIPTS_ROOT: String = "res://scripts"

## A script's key, for every script met so far, including the inner classes found by the one
## scan of the project's scripts — loading every script to find an inner class's outer is too
## costly to repeat per object.
static var _keys_by_script: Dictionary = {}
static var _scripts_by_key: Dictionary = {}
static var _inner_classes_scanned: bool = false

## The scenario references resolve against.
var scenario: Scenario
## Spawn serial → entity, pieces and emissions alike, for resolving references while decoding.
## Filled by the snapshot before any field is decoded.
var entities_by_serial: Dictionary = {}
## The object table: id → `{"s": script key, "f": fields}`. Written while encoding, read while
## decoding.
var objects: Dictionary = {}
## Encoding: object → id.
var _ids: Dictionary = {}
## Where the encoder is, as `Class.field` from the outermost object in: what a failed assertion
## names, so a field the codec cannot carry is found by reading the message.
var _path: PackedStringArray = []
## Decoding: id → the object it became, and the objects already standing in for an id.
var _bound: Dictionary = {}
var _adopted: Dictionary = {}
## Decoding: the ids whose saved fields have been set.
var _filled: Dictionary = {}


func _init(a_scenario: Scenario = null) -> void:
	scenario = a_scenario


#region Encoding
## Every saved field of `a_object`, by name.
func fields_of(a_object: Object) -> Dictionary:
	var out: Dictionary = {}
	var label: String = _label_of(a_object)
	for property: Dictionary in saved_properties(a_object):
		var name: StringName = property["name"]
		_path.append("%s.%s" % [label, name])
		out[String(name)] = encode(a_object.get(name), int(property["type"]) != TYPE_NIL)
		_path.remove_at(_path.size() - 1)
	if a_object.has_method(&"snapshot_extra"):
		out["$extra"] = encode(a_object.call(&"snapshot_extra"), false)
	return out


## `a_value` as JSON-safe data. `a_is_typed`: the slot it is read back into declares its type,
## so a number needs no tag.
func encode(a_value: Variant, a_is_typed: bool = false) -> Variant:
	match typeof(a_value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_STRING:
			return a_value
		TYPE_INT:
			var number: int = a_value
			return number if absi(number) < _SAFE_INT else {"$i": str(number)}
		TYPE_FLOAT:
			var bits: String = float_bits(a_value)
			return bits if a_is_typed else {"$f": bits}
		TYPE_STRING_NAME:
			return String(a_value) if a_is_typed else {"$sn": String(a_value)}
		TYPE_ARRAY:
			return _encode_array(a_value)
		TYPE_DICTIONARY:
			return _encode_dictionary(a_value)
		TYPE_OBJECT:
			return _encode_object(a_value)
		TYPE_CALLABLE:
			return _encode_callable(a_value)
		TYPE_SIGNAL, TYPE_RID:
			assert(
				false,
				"StateCodec: a %s cannot be saved, at %s" % [type_string(typeof(a_value)), where()]
			)
			return null
		TYPE_PACKED_BYTE_ARRAY:
			# Godot's encoder refuses an empty array.
			var bytes: PackedByteArray = a_value
			var text: String = "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)
			return {"$t": TYPE_PACKED_BYTE_ARRAY, "v": text}
		_:
			return {"$t": typeof(a_value), "v": _flatten(a_value).map(_plain_component)}


## A method of a savable object, by the object and the method's name; an empty callable as null. A
## lambda or a bound callable carries what it captured, which nothing can name, so it fails.
func _encode_callable(a_callable: Callable) -> Variant:
	if not a_callable.is_valid():
		return null
	if not a_callable.is_standard():
		assert(false, "StateCodec: a lambda cannot be saved, at %s" % where())
		return null
	return {"$m": [_encode_object(a_callable.get_object()), String(a_callable.get_method())]}


func _encode_array(a_array: Array) -> Array:
	var is_typed: bool = a_array.is_typed() and a_array.get_typed_builtin() != TYPE_OBJECT
	return a_array.map(func(item: Variant) -> Variant: return encode(item, is_typed))


func _encode_dictionary(a_dictionary: Dictionary) -> Dictionary:
	var keys_typed: bool = (
		a_dictionary.is_typed_key() and a_dictionary.get_typed_key_builtin() != TYPE_OBJECT
	)
	var values_typed: bool = (
		a_dictionary.is_typed_value() and a_dictionary.get_typed_value_builtin() != TYPE_OBJECT
	)
	var pairs: Array = a_dictionary.keys().map(
		func(key: Variant) -> Array:
			return [encode(key, keys_typed), encode(a_dictionary[key], values_typed)]
	)
	return {"$d": pairs}


func _encode_object(a_object: Variant) -> Variant:
	if a_object == null or not is_instance_valid(a_object):
		return null
	var object: Object = a_object
	if object == scenario:
		return {"$s": "."}
	if object is Entity:
		var serial: int = (object as Entity).spawn_serial
		assert(serial != 0, "StateCodec: an entity with no serial, at %s" % where())
		return {"$p": serial}
	if object is Commander:
		return {"$c": (object as Commander).id}
	if object is Node:
		return _encode_node(object)
	if object is RandomNumberGenerator:
		var rng := object as RandomNumberGenerator
		return {"$rng": [str(rng.seed), str(rng.state)]}
	if object is Tool:
		return _encode_tool(object)
	if object is WeakRef:
		return {"$w": encode((object as WeakRef).get_ref())}
	if object is Script:
		return {"$script": script_key(object)}
	if object is Resource and not is_state_resource(object):
		return {"$r": (object as Resource).resource_path}
	if (object is RefCounted or object is Resource) and object.get_script() != null:
		return {"$o": _table_id(object)}
	assert(false, "StateCodec: a %s cannot be saved, at %s" % [object.get_class(), where()])
	return null


func _encode_node(a_node: Node) -> Dictionary:
	var entity: Entity = Entity.owning(a_node)
	if entity != null:
		return {"$n": entity.spawn_serial, "path": String(entity.get_path_to(a_node))}
	assert(
		scenario != null and scenario.is_ancestor_of(a_node),
		(
			"StateCodec: %s is neither in a piece nor under the scenario, at %s"
			% [a_node.name, where()]
		)
	)
	return {"$s": String(scenario.get_path_to(a_node))}


## A catalogue tool by its command name; a bound one adds its variant's index, which the base
## tool binds again to the same object (Tool.with_variant).
func _encode_tool(a_tool: Tool) -> Dictionary:
	return {"$tool": a_tool.command_name, "variant": a_tool.variant_index()}


## The object table's id for `a_object`, recording it on first sight. The id is taken before its
## fields are encoded, so an object reachable from its own fields is a cycle, not a recursion.
func _table_id(a_object: Object) -> String:
	if _ids.has(a_object):
		return _ids[a_object]
	var id: String = str(_ids.size() + 1)
	_ids[a_object] = id
	var record: Dictionary = {"s": script_key(a_object.get_script())}
	objects[id] = record
	record["f"] = fields_of(a_object)
	return id


## The hex of `value`'s eight bytes, which reads back to the bit (float_from_bits).
static func float_bits(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()


static func float_from_bits(bits: String) -> float:
	return bits.hex_decode().to_float64_array()[0]


## A value type's component as written: a float as its bits, an int past a double's precision as
## text, anything else as it is.
static func _plain_component(component: Variant) -> Variant:
	if component is float:
		return float_bits(component)
	if component is int and absi(component) >= _SAFE_INT:
		return str(component)
	return component


## A component read back for a value type of `type`: text is a float's bits in a float type, and a
## large int in an int type.
static func _component_of(component: Variant, type: int) -> Variant:
	if not (component is String):
		return component
	return str(component).to_int() if _INT_TYPES.has(type) else float_from_bits(component)


## A value type's components, for the types JSON has no form for.
static func _flatten(value: Variant) -> Array:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_RECT2, TYPE_RECT2I:
			return _flatten(value.position) + _flatten(value.size)
		TYPE_AABB:
			return _flatten(value.position) + _flatten(value.size)
		TYPE_PLANE:
			return _flatten(value.normal) + [value.d]
		TYPE_BASIS:
			return _flatten(value.x) + _flatten(value.y) + _flatten(value.z)
		TYPE_TRANSFORM2D:
			return _flatten(value.x) + _flatten(value.y) + _flatten(value.origin)
		TYPE_TRANSFORM3D:
			return _flatten(value.basis) + _flatten(value.origin)
		TYPE_NODE_PATH:
			return [String(value)]
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			return Array(value)
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var flat: Array = []
			for item: Variant in value:
				flat.append_array(_flatten(item))
			return flat
	assert(false, "StateCodec: a %s cannot be saved" % type_string(typeof(value)))
	return []


## The field being encoded, outermost first.
func where() -> String:
	return " > ".join(_path)


static func _label_of(target: Object) -> String:
	var script: Script = target.get_script()
	var global: StringName = script.get_global_name() if script != null else &""
	return String(global) if global != &"" else target.get_class()


#endregion


#region Decoding
## Set every saved field of `a_object` from `a_fields`, as `fields_of` wrote them.
func decode_into(a_object: Object, a_fields: Dictionary) -> void:
	for property: Dictionary in saved_properties(a_object):
		var name: StringName = property["name"]
		if not a_fields.has(String(name)):
			continue
		var value: Variant = decode(
			a_fields[String(name)], a_object.get(name), int(property["type"])
		)
		a_object.set(name, value)
	if a_fields.has("$extra") and a_object.has_method(&"restore_snapshot_extra"):
		a_object.call(&"restore_snapshot_extra", decode(a_fields["$extra"], null, TYPE_NIL))


## `a_encoded` as a value again. `a_current`: what the slot holds now, whose typing (a typed
## array's, an object's script) the decoded value takes. `a_type`: the slot's declared type, or
## TYPE_NIL for a Variant slot.
func decode(a_encoded: Variant, a_current: Variant, a_type: int) -> Variant:
	match typeof(a_encoded):
		TYPE_NIL:
			return Callable() if a_type == TYPE_CALLABLE else null
		TYPE_BOOL:
			return a_encoded
		TYPE_STRING:
			if a_type == TYPE_FLOAT:
				return float_from_bits(a_encoded)
			return StringName(a_encoded) if a_type == TYPE_STRING_NAME else a_encoded
		TYPE_FLOAT, TYPE_INT:
			return float(a_encoded) if a_type == TYPE_FLOAT else int(a_encoded)
		TYPE_ARRAY:
			return _decode_array(a_encoded, a_current)
		TYPE_DICTIONARY:
			return _decode_tagged(a_encoded, a_current)
	assert(false, "StateCodec: cannot decode a %s" % type_string(typeof(a_encoded)))
	return null


func _decode_array(a_items: Array, a_current: Variant) -> Array:
	var current: Array = a_current if a_current is Array else []
	var element_type: int = current.get_typed_builtin() if current.is_typed() else TYPE_NIL
	# Each item against the rebuilt slot's item at the same place, so a list of objects the scene
	# makes again (a bot's jobs) is filled in place rather than replaced.
	var items: Array = []
	for i: int in a_items.size():
		items.append(decode(a_items[i], current[i] if i < current.size() else null, element_type))
	if not current.is_typed():
		return items
	return Array(
		items,
		current.get_typed_builtin(),
		current.get_typed_class_name(),
		current.get_typed_script()
	)


func _decode_dictionary(a_pairs: Array, a_current: Variant) -> Dictionary:
	var current: Dictionary = a_current if a_current is Dictionary else {}
	var key_type: int = current.get_typed_key_builtin() if current.is_typed_key() else TYPE_NIL
	var value_type: int = (
		current.get_typed_value_builtin() if current.is_typed_value() else TYPE_NIL
	)
	var out: Dictionary = {}
	for pair: Array in a_pairs:
		out[decode(pair[0], null, key_type)] = decode(pair[1], null, value_type)
	if not current.is_typed():
		return out
	return Dictionary(
		out,
		current.get_typed_key_builtin(),
		current.get_typed_key_class_name(),
		current.get_typed_key_script(),
		current.get_typed_value_builtin(),
		current.get_typed_value_class_name(),
		current.get_typed_value_script()
	)


func _decode_tagged(a_tagged: Dictionary, a_current: Variant) -> Variant:
	if a_tagged.has("$f"):
		return float_from_bits(str(a_tagged["$f"]))
	if a_tagged.has("$i"):
		return str(a_tagged["$i"]).to_int()
	if a_tagged.has("$sn"):
		return StringName(a_tagged["$sn"])
	if a_tagged.has("$d"):
		return _decode_dictionary(a_tagged["$d"], a_current)
	if a_tagged.has("$t"):
		var type: int = int(a_tagged["$t"])
		var components: Variant = a_tagged["v"]
		if components is Array and not _TEXT_TYPES.has(type):
			components = (components as Array).map(
				func(component: Variant) -> Variant: return _component_of(component, type)
			)
		return unflatten(type, components)
	return _decode_reference(a_tagged, a_current)


## A tagged reference: to a piece, a node, a commander or a random stream.
func _decode_reference(a_tagged: Dictionary, a_current: Variant) -> Variant:
	if a_tagged.has("$p"):
		return _entity(int(a_tagged["$p"]))
	if a_tagged.has("$n"):
		var owner_entity: Entity = _entity(int(a_tagged["$n"]))
		return owner_entity.get_node_or_null(NodePath(a_tagged["path"])) if owner_entity else null
	if a_tagged.has("$s"):
		return scenario.get_node_or_null(NodePath(a_tagged["$s"]))
	if a_tagged.has("$c"):
		return scenario.commanders[int(a_tagged["$c"])]
	if a_tagged.has("$rng"):
		return _decode_rng(a_tagged["$rng"], a_current)
	return _decode_catalogued(a_tagged, a_current)


## A tagged catalogue entry, script, resource, shared object or method.
func _decode_catalogued(a_tagged: Dictionary, a_current: Variant) -> Variant:
	if a_tagged.has("$tool"):
		var base: Tool = Tool.for_name(a_tagged["$tool"])
		var variant: int = int(a_tagged.get("variant", -1))
		return base.with_variant(variant) if base != null and variant >= 0 else base
	if a_tagged.has("$w"):
		var target: Variant = decode(a_tagged["$w"], null, TYPE_NIL)
		return weakref(target) if target != null else WeakRef.new()
	if a_tagged.has("$script"):
		return script_for_key(a_tagged["$script"])
	if a_tagged.has("$r"):
		return _decode_resource(str(a_tagged["$r"]), a_current)
	if a_tagged.has("$o"):
		return _decode_object(str(a_tagged["$o"]), a_current)
	if a_tagged.has("$m"):
		var pair: Array = a_tagged["$m"]
		var target: Variant = decode(pair[0], null, TYPE_NIL)
		return Callable(target, StringName(pair[1])) if target != null else Callable()
	assert(false, "StateCodec: unknown tag in %s" % str(a_tagged).left(200))
	return null


func _entity(a_serial: int) -> Entity:
	var entity: Variant = entities_by_serial.get(a_serial)
	if entity == null and scenario != null:
		entity = scenario.piece_by_serial(a_serial)
	return entity as Entity if is_instance_valid(entity) else null


func _decode_rng(a_pair: Array, a_current: Variant) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = (
		a_current if a_current is RandomNumberGenerator else RandomNumberGenerator.new()
	)
	# The seed first: setting it resets the state.
	rng.seed = str(a_pair[0]).to_int()
	rng.state = str(a_pair[1]).to_int()
	return rng


## A file-backed resource by its path. A built-in one keeps what the rebuilt scene holds when that
## is the same resource; one made at run time with no path is derived (a range shape fitted to its
## reach), so the rebuilt scene's stands.
func _decode_resource(a_path: String, a_current: Variant) -> Resource:
	var current: Resource = a_current as Resource if a_current is Resource else null
	if a_path.is_empty() or (current != null and current.resource_path == a_path):
		return current
	assert(not a_path.contains("::"), "StateCodec: built-in resource %s is gone" % a_path)
	return load(a_path)


## The object with table id `a_id`: the one it already became, the rebuilt scene's own when the
## slot holds one of the same script nothing else has claimed, or a new one.
func _decode_object(a_id: String, a_current: Variant) -> Object:
	var record: Dictionary = objects[a_id]
	if not _bound.has(a_id) and not _try_adopt(a_id, a_current):
		var made: Object = instantiate(script_for_key(record["s"]))
		_bound[a_id] = made
		_adopted[made] = true
	var object: Object = _bound[a_id]
	if not _filled.has(a_id):
		_filled[a_id] = true
		decode_into(object, record["f"])
	return object


## Bind table id `a_id` to `a_current` when it is an object of the record's script that no other
## id has claimed.
func _try_adopt(a_id: String, a_current: Variant) -> bool:
	if not (a_current is Object) or not is_instance_valid(a_current) or _adopted.has(a_current):
		return false
	var current: Object = a_current
	if current.get_script() != script_for_key(objects[a_id]["s"]):
		return false
	_bound[a_id] = current
	_adopted[current] = true
	return true


## The table id `a_object` was encoded under, or "" when nothing referred to it.
func id_of(a_object: Object) -> String:
	return _ids.get(a_object, "")


## Decode the table's `a_id` as `a_object`, whose fields the caller sets itself: an object the
## decode starts from, which something in the table refers back to. No-op for an empty id.
func bind_as(a_id: String, a_object: Object) -> void:
	if a_id.is_empty():
		return
	_bound[a_id] = a_object
	_adopted[a_object] = true
	_filled[a_id] = true


## Every object the decode bound, the rebuilt scene's own and the ones it made.
func restored_objects() -> Array:
	return _bound.values()


## Before anything is decoded, bind every table object to the rebuilt scene's own wherever that
## scene holds one in the same place: walked from `a_object`'s fields down. Done as a pass of its
## own so it does not matter which reference to an object is decoded first — a squad's filter
## names a bot manager before the brain's field holding that manager is reached.
func adopt_fields(a_object: Object, a_fields: Dictionary) -> void:
	for property: Dictionary in saved_properties(a_object):
		var name: String = String(property["name"])
		if a_fields.has(name):
			_adopt(a_fields[name], a_object.get(StringName(name)))


func _adopt(a_encoded: Variant, a_current: Variant) -> void:
	if a_encoded is Array and a_current is Array:
		_adopt_array(a_encoded, a_current)
		return
	if not (a_encoded is Dictionary):
		return
	var tagged: Dictionary = a_encoded
	if tagged.has("$o"):
		var id: String = str(tagged["$o"])
		if not _bound.has(id) and _try_adopt(id, a_current):
			adopt_fields(a_current, objects[id]["f"])
	elif tagged.has("$m") and a_current is Callable and (a_current as Callable).is_standard():
		_adopt(tagged["$m"][0], (a_current as Callable).get_object())
	elif tagged.has("$d") and a_current is Dictionary:
		for pair: Array in tagged["$d"]:
			var key: Variant = (
				decode(pair[0], null, TYPE_NIL)
				if not (pair[0] is Dictionary and _is_reference(pair[0]))
				else null
			)
			if key != null and (a_current as Dictionary).has(key):
				_adopt(pair[1], a_current[key])


## Pair a saved list with the rebuilt one: by the fields the items name as their identity
## (`snapshot_identity_fields`, a bot job's brain and name) where they have them, so a list the
## rebuilt scene built differently is still matched item for item; by place otherwise.
func _adopt_array(a_encoded: Array, a_current: Array) -> void:
	var fields: Array = _identity_fields_of(a_current)
	if fields.is_empty():
		for i: int in mini(a_encoded.size(), a_current.size()):
			_adopt(a_encoded[i], a_current[i])
		return
	var by_identity: Dictionary = {}
	for item: Variant in a_current:
		var object: Object = item
		var values: Array = fields.map(func(field: String) -> Variant: return object.get(field))
		by_identity[_identity_key(values)] = item
	for encoded: Variant in a_encoded:
		if not (encoded is Dictionary and (encoded as Dictionary).has("$o")):
			continue
		var saved: Dictionary = objects[str(encoded["$o"])]["f"]
		var identity: String = _identity_key(
			fields.map(
				func(field: String) -> Variant: return decode(saved.get(field), null, TYPE_NIL)
			)
		)
		if by_identity.has(identity):
			_adopt(encoded, by_identity[identity])


## Identity values as one key, each by its own text: a StringName and the String a save reads it
## back as are the same name.
static func _identity_key(values: Array) -> String:
	return "|".join(values.map(func(value: Variant) -> String: return str(value)))


## The identity fields the objects of `items` declare, or none.
static func _identity_fields_of(items: Array) -> Array:
	for item: Variant in items:
		if item is Object and is_instance_valid(item):
			var object: Object = item
			return (
				object.call(&"snapshot_identity_fields")
				if object.has_method(&"snapshot_identity_fields")
				else []
			)
	return []


## Whether an encoded value names an object, which a key lookup must not decode early.
static func _is_reference(encoded: Dictionary) -> bool:
	for tag: String in ["$o", "$p", "$n", "$s", "$c", "$m", "$w"]:
		if encoded.has(tag):
			return true
	return false


## A blank instance of `a_script`, its constructor given each required argument's empty value: the
## saved fields overwrite whatever the constructor made of them.
static func instantiate(a_script: Script) -> Object:
	var arguments: Array = []
	for method: Dictionary in a_script.get_script_method_list():
		if method["name"] != "_init":
			continue
		var required: int = (
			(method["args"] as Array).size() - (method["default_args"] as Array).size()
		)
		for index: int in required:
			arguments.append(_empty_of(method["args"][index]))
		break
	return a_script.callv(&"new", arguments)


## A stand-in for a required constructor argument: a blank instance of a script class the argument
## names (a command's message), so the constructor has something to touch; the type's empty
## value otherwise.
static func _empty_of(argument: Dictionary) -> Variant:
	var type: int = argument["type"]
	if type != TYPE_OBJECT:
		return null if type == TYPE_NIL else type_convert(null, type)
	var script: Script = _global_class_script(StringName(argument.get("class_name", "")))
	var is_value_object: bool = (
		script != null and ClassDB.is_parent_class(script.get_instance_base_type(), &"RefCounted")
	)
	return instantiate(script) if is_value_object else null


static func _global_class_script(class_id: StringName) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == class_id:
			return load(entry["path"])
	return null


static func unflatten(type: int, value: Variant) -> Variant:
	if type == TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray() if str(value).is_empty() else Marshalls.base64_to_raw(value)
	var v: Array = value
	match type:
		TYPE_VECTOR2:
			return Vector2(v[0], v[1])
		TYPE_VECTOR2I:
			return Vector2i(int(v[0]), int(v[1]))
		TYPE_VECTOR3:
			return Vector3(v[0], v[1], v[2])
		TYPE_VECTOR3I:
			return Vector3i(int(v[0]), int(v[1]), int(v[2]))
		TYPE_VECTOR4:
			return Vector4(v[0], v[1], v[2], v[3])
		TYPE_VECTOR4I:
			return Vector4i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
		TYPE_QUATERNION:
			return Quaternion(v[0], v[1], v[2], v[3])
		TYPE_COLOR:
			return Color(v[0], v[1], v[2], v[3])
		TYPE_RECT2:
			return Rect2(v[0], v[1], v[2], v[3])
		TYPE_RECT2I:
			return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
		TYPE_AABB:
			return AABB(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
		TYPE_PLANE:
			return Plane(Vector3(v[0], v[1], v[2]), v[3])
		TYPE_BASIS:
			return _basis(v, 0)
		TYPE_TRANSFORM2D:
			return Transform2D(Vector2(v[0], v[1]), Vector2(v[2], v[3]), Vector2(v[4], v[5]))
		TYPE_TRANSFORM3D:
			return Transform3D(_basis(v, 0), Vector3(v[9], v[10], v[11]))
		TYPE_NODE_PATH:
			return NodePath(v[0])
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(v.map(func(x: Variant) -> int: return int(x)))
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(v.map(func(x: Variant) -> int: return int(x)))
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(v)
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(v)
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(v)
		TYPE_PACKED_VECTOR2_ARRAY:
			var points2: PackedVector2Array = []
			for i: int in range(0, v.size(), 2):
				points2.append(Vector2(v[i], v[i + 1]))
			return points2
		TYPE_PACKED_VECTOR3_ARRAY:
			var points3: PackedVector3Array = []
			for i: int in range(0, v.size(), 3):
				points3.append(Vector3(v[i], v[i + 1], v[i + 2]))
			return points3
		TYPE_PACKED_COLOR_ARRAY:
			var colors: PackedColorArray = []
			for i: int in range(0, v.size(), 4):
				colors.append(Color(v[i], v[i + 1], v[i + 2], v[i + 3]))
			return colors
	assert(false, "StateCodec: cannot decode a %s" % type_string(type))
	return null


static func _basis(v: Array, offset: int) -> Basis:
	return Basis(
		Vector3(v[offset], v[offset + 1], v[offset + 2]),
		Vector3(v[offset + 3], v[offset + 4], v[offset + 5]),
		Vector3(v[offset + 6], v[offset + 7], v[offset + 8])
	)


#endregion


#region Reflection
## The script-variable properties of `target` that a snapshot carries.
static func saved_properties(target: Object) -> Array[Dictionary]:
	var only: Array = (
		target.call(&"snapshot_fields") if target.has_method(&"snapshot_fields") else []
	)
	var skip: Array = target.call(&"snapshot_skip") if target.has_method(&"snapshot_skip") else []
	var out: Array[Dictionary] = []
	for property: Dictionary in target.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name: StringName = property["name"]
		if (not only.is_empty() and not only.has(name)) or skip.has(name):
			continue
		out.append(property)
	return out


## A file-backed resource is shared data, saved by its path; a scripted resource built into a
## scene or made at run time (a trigger's condition, a duplicated sanction) carries state.
static func is_state_resource(resource: Resource) -> bool:
	var path: String = resource.resource_path
	return resource.get_script() != null and (path.is_empty() or path.contains("::"))


## A key a script can be found by again: its path, or for an inner class its outer script's path
## and its name, `res://a.gd::Outer.Inner`.
static func script_key(script: Script) -> String:
	if script == null:
		return ""
	if not script.resource_path.is_empty():
		return script.resource_path
	if not _keys_by_script.has(script):
		_scan_inner_classes()
	assert(_keys_by_script.has(script), "StateCodec: an inner class not under %s" % _SCRIPTS_ROOT)
	return _keys_by_script.get(script, "")


static func script_for_key(key: String) -> Script:
	if key.is_empty():
		return null
	if _scripts_by_key.has(key):
		return _scripts_by_key[key]
	var parts: PackedStringArray = key.split("::")
	var script: Script = load(parts[0])
	if parts.size() > 1:
		for name: String in parts[1].split("."):
			script = script.get_script_constant_map().get(name)
	_scripts_by_key[key] = script
	_keys_by_script[script] = key
	return script


static func _scan_inner_classes() -> void:
	if _inner_classes_scanned:
		return
	_inner_classes_scanned = true
	for path: String in _script_paths(_SCRIPTS_ROOT):
		var outer: Script = load(path)
		if outer != null:
			_index_inner(outer, path + "::", 0)


static func _index_inner(outer: Script, prefix: String, depth: int) -> void:
	if depth >= _INNER_DEPTH_MAX:
		return
	var constants: Dictionary = outer.get_script_constant_map()
	for name: String in constants:
		var inner: Variant = constants[name]
		if inner is GDScript and (inner as GDScript).resource_path.is_empty():
			var key: String = prefix + name
			_keys_by_script[inner] = key
			_scripts_by_key[key] = inner
			_index_inner(inner, key + ".", depth + 1)


static func _script_paths(directory: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			out.append(directory.path_join(file))
	for sub: String in DirAccess.get_directories_at(directory):
		out.append_array(_script_paths(directory.path_join(sub)))
	return out
#endregion
