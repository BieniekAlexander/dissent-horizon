extends RefCounted

## A plain object with one field of each kind the snapshot codec carries, for test_StateCodec.
## Prefixed `_` so GUT does not collect it (test_SuiteIntegrity).

var number: int = 0
var big: int = 0
var real: float = 0.0
var untyped: Variant = null
var label: StringName = &""
var vector: Vector3 = Vector3.ZERO
var transform: Transform3D = Transform3D.IDENTITY
var floats: PackedFloat32Array = PackedFloat32Array()
var texts: PackedStringArray = PackedStringArray()
var ints: Array[int] = []
var table: Dictionary = {}
var other: Variant = null
var callback: Callable = Callable()
var skipped: int = 0


func snapshot_skip() -> Array:
	return [&"skipped"]


func ping() -> int:
	return number
