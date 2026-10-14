class_name LoopbackNetwork
extends RefCounted

## An in-process network for tests: one endpoint (a LoopbackTransport) per peer, with latency,
## loss and duplication injected on a clock the test advances by hand, and every random choice
## drawn from the network's own seeded stream so a test sees the same deliveries every run.
## gdd/systems/commands/netplay.md §Decisions (testing).
##
## Nothing here touches the game's random streams (SU.rng, the global generator): a lossy
## network in a test must not shift what the simulation draws.

## Steps a message takes to arrive. Each message draws its own delay from [min, max], so a
## spread larger than zero also reorders them.
var latency_min: int = 0
var latency_max: int = 0
## The chance a message is never delivered.
var loss: float = 0.0
## The chance a delivered message is delivered twice.
var duplication: float = 0.0

## The current step; messages are delivered when it reaches their due step.
var now: int = 0

var _rng := RandomNumberGenerator.new()
var _endpoints: Dictionary = {}
## Messages in flight: [due_step, sequence, from, to, bytes]. The sequence keeps delivery of
## messages due on the same step in the order they were sent.
var _in_flight: Array = []
var _sequence: int = 0


func _init(a_seed: int = 0) -> void:
	_rng.seed = a_seed


## The endpoint for peer `a_id`, made on first ask. Every endpoint sees every other as a peer.
func endpoint(a_id: int) -> LoopbackTransport:
	if not _endpoints.has(a_id):
		_endpoints[a_id] = LoopbackTransport.new(self, a_id)
	return _endpoints[a_id]


func peer_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _endpoints.keys():
		out.append(id)
	out.sort()
	return out


## Advance the clock `a_steps` and hand every message now due to its endpoint.
func step(a_steps: int = 1) -> void:
	now += a_steps
	var due: Array = []
	var waiting: Array = []
	for message: Array in _in_flight:
		(due if int(message[0]) <= now else waiting).append(message)
	_in_flight = waiting
	due.sort_custom(_delivered_before)
	for message: Array in due:
		var to: LoopbackTransport = _endpoints.get(int(message[3]), null)
		if to != null:
			to._deliver(int(message[2]), message[4])


static func _delivered_before(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	return int(a[1]) < int(b[1])


## How many messages are still in flight.
func in_flight() -> int:
	return _in_flight.size()


func _send(a_from: int, a_to: int, a_bytes: PackedByteArray) -> void:
	if not _endpoints.has(a_to) or a_to == a_from:
		return
	if loss > 0.0 and _rng.randf() < loss:
		return
	var copies: int = 2 if duplication > 0.0 and _rng.randf() < duplication else 1
	for i: int in copies:
		var delay: int = _rng.randi_range(latency_min, maxi(latency_min, latency_max))
		_in_flight.append([now + delay, _sequence, a_from, a_to, a_bytes.duplicate()])
		_sequence += 1
