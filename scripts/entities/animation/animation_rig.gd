class_name AnimationRig
extends Node

## The animation controller: an optional component that turns its host's ActionTracker into
## the clips its model should be playing, through the host kind's AnimationProfile. Each tick
## it asks the profile what every layer should hold and announces any change; each cue it asks
## what plays once. Absent, a piece is simply not animated.
##
## TODO: playback. Nothing plays a request yet. A proposal, not approved: when models carry
## animations, this node hands `held_requests()` and each one-shot to the model's
## AnimationTree, through its two signals. The transitions themselves are live today.
## → gdd/systems/ux/unit-animation.md

## The clips a layer should hold changed.
signal requests_changed(a_requests: Array[AnimationRequest])
## A clip should play once over whatever the layer holds.
signal one_shot_requested(a_request: AnimationRequest)

## How this kind of piece animates. Left empty, the default: one body clip per action.
@export var profile: AnimationProfile = null

var _host: Commandable = null
## Framework-imposed state: what each layer was last told to hold, so an unchanged tick says
## nothing.
var _held: Array[AnimationRequest] = []


func _ready() -> void:
	if profile == null:
		profile = AnimationProfile.new()
	_host = get_parent() as Commandable
	if _host == null:
		return
	_host.action_tracker.cued.connect(_on_cued)


func _physics_process(_a_delta: float) -> void:
	if _host == null or not _host.is_inside_tree():
		return
	refresh(AnimationContext.of(_host))


## Ask the profile what to hold under `a_context`, announcing it when it differs.
func refresh(a_context: AnimationContext) -> void:
	var requests: Array[AnimationRequest] = profile.requests_for(a_context)
	if _same_requests(requests, _held):
		return
	_held = requests
	requests_changed.emit(requests)


func held_requests() -> Array[AnimationRequest]:
	return _held


func _on_cued(a_cue: StringName, _a_source: Object) -> void:
	if _host == null:
		return
	for request: AnimationRequest in profile.requests_for_cue(a_cue, AnimationContext.of(_host)):
		one_shot_requested.emit(request)


static func _same_requests(a: Array[AnimationRequest], b: Array[AnimationRequest]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if not a[i].equals(b[i]):
			return false
	return true
