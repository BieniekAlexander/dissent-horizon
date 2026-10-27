class_name SnapshotDiff
extends RefCounted

## Where two snapshots differ, field by field — what a restore that missed something looks like,
## named down to the piece and the field (SimulationSnapshot). Used by the round-trip test and the
## save-and-load probe (tools/snapshot/).

## The navigation server's report for an agent, which a restore SETS but the server takes up only
## at its next step: not comparable at the instant of a restore, only once the match has run on.
const SERVER_READS: Array[String] = ["server_position", "server_velocity", "server_field"]
## How a node is made again, which says nothing about its state: a node handed back to its piece
## in play is made in play, and the same node in a rebuilt piece is the scene's. Never compared.
const HOW_MADE: Array[String] = ["new"]


## A snapshot as it reads back from a save: through JSON, so a live capture and a loaded one
## compare.
static func normalised(snapshot: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(snapshot, "", true, true))


## Every difference between `actual` and `expected`, as `path: actual != expected`, leaving out
## any field named in `ignored`.
static func differences(
	actual: Variant, expected: Variant, ignored: Array[String] = []
) -> Array[String]:
	var out: Array[String] = []
	_walk(actual, expected, "", out, ignored + HOW_MADE)
	return out


static func _walk(
	actual: Variant, expected: Variant, at: String, out: Array[String], ignored: Array[String]
) -> void:
	if typeof(actual) != typeof(expected):
		out.append("%s: %s != %s" % [at, _short(actual), _short(expected)])
		return
	if actual is Dictionary:
		var keys: Dictionary = {}
		for key: Variant in (actual as Dictionary).keys() + (expected as Dictionary).keys():
			keys[key] = true
		for key: Variant in keys:
			if not ignored.has(str(key)):
				_walk(actual.get(key), expected.get(key), "%s.%s" % [at, key], out, ignored)
	elif actual is Array:
		var a: Array = actual
		var e: Array = expected
		if a.size() != e.size():
			out.append("%s: %d items != %d" % [at, a.size(), e.size()])
		for i: int in mini(a.size(), e.size()):
			_walk(a[i], e[i], "%s[%s]" % [at, _label(a[i], i)], out, ignored)
	elif actual != expected:
		out.append("%s: %s != %s" % [at, _short(actual), _short(expected)])


## An entity record's serial, or a node record's path, so a difference names what it is in.
static func _label(item: Variant, index: int) -> String:
	if item is Dictionary and (item as Dictionary).has("serial"):
		return "#%d" % int(item["serial"])
	if item is Array and (item as Array).size() == 2 and item[0] is String:
		return str(item[0])
	return str(index)


static func _short(value: Variant) -> String:
	return str(value).left(120)


## The first part two SimulationDigest state strings differ in, or "" when they agree.
static func first_state_difference(actual: String, expected: String) -> String:
	if actual == expected:
		return ""
	var a: PackedStringArray = actual.replace(";", "|").split("|")
	var e: PackedStringArray = expected.replace(";", "|").split("|")
	for i: int in mini(a.size(), e.size()):
		if a[i] != e[i]:
			return "\n  got      %s\n  expected %s" % [a[i], e[i]]
	return "%d parts != %d" % [a.size(), e.size()]
