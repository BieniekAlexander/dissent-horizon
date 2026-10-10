extends GutTest

## A stealthed piece inside an enemy detector's range is REVEALED whichever of the two ticks
## first, and drops back to STEALTHED once out of range. Tick order is tree order, commander by
## commander, so a rule that worked in only one order hid one side's stealth from the other
## side's detectors entirely (Stealth.REVEAL_FRESH_FRAMES).
##
## Run with:
##   python3 tools/gut_shards/gut_shards.py StealthDetection

const DETECTION_RADIUS: float = 8.0
const INSIDE: Vector3 = Vector3(2.0, 0.0, 0.0)
const OUTSIDE: Vector3 = Vector3(40.0, 0.0, 0.0)
const SNEAK_ID: int = 1
const DETECTOR_ID: int = 2
## Ticks to let both pieces run before reading the state.
const SETTLE_TICKS: int = 3


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A mobile piece with a DetectionRange cylinder of DETECTION_RADIUS, out of the tree.
func _detector() -> Actor:
	var detector: Actor = FakePieces.unit({"speed": 2.0})
	var shape := CylinderShape3D.new()
	shape.radius = DETECTION_RADIUS
	var node := CollisionShape3D.new()
	node.name = "DetectionRange"
	node.shape = shape
	node.disabled = true
	detector.add_child(node)
	return detector


## The stealthed piece and a detector, added in the order asked — the order they tick in.
func _pair(a_sneak_ticks_first: bool, a_detector_id: int = DETECTOR_ID) -> Array[Actor]:
	var sneak: Actor = FakePieces.unit({"speed": 2.0, "stealth": true})
	var detector: Actor = _detector()
	var order: Array = [[sneak, SNEAK_ID], [detector, a_detector_id]]
	if not a_sneak_ticks_first:
		order.reverse()
	for entry: Array in order:
		add_child_autofree(entry[0])
		(entry[0] as Actor).ownership.commander = _commander(entry[1])
	sneak.global_position = INSIDE
	return [sneak, detector]


func _settle() -> void:
	for _i: int in SETTLE_TICKS:
		await get_tree().physics_frame


func test_revealed_when_the_stealthed_piece_ticks_first() -> void:
	var pair: Array[Actor] = _pair(true)
	await _settle()
	assert_eq(pair[0].stealth.state, Stealth.State.REVEALED)


func test_revealed_when_the_detector_ticks_first() -> void:
	var pair: Array[Actor] = _pair(false)
	await _settle()
	assert_eq(pair[0].stealth.state, Stealth.State.REVEALED)


func test_hidden_again_once_out_of_range() -> void:
	var pair: Array[Actor] = _pair(true)
	await _settle()
	pair[0].global_position = OUTSIDE
	await _settle()
	assert_eq(pair[0].stealth.state, Stealth.State.STEALTHED)


func test_a_friendly_detector_reveals_nothing() -> void:
	var pair: Array[Actor] = _pair(true, SNEAK_ID)
	await _settle()
	assert_eq(pair[0].stealth.state, Stealth.State.STEALTHED)
