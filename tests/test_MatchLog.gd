extends GutTest

## The match event log, against a bare commander: what each purchase stage and a finished
## construction write, and that the log survives a round trip through JSON lines and gzip.

const PRICE: int = 50

var _log: MatchLog
var _commander: Commander


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 3
	_commander.energy = 1000
	_commander.set_physics_process(false)
	add_child_autofree(_commander)
	_log = MatchLog.new()
	add_child_autofree(_log)
	_log.listen_to(_commander)


func _transaction(a_kind: PurchaseTransaction.Kind, a_type: StringName) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.new()
	transaction.commander = _commander
	transaction.kind = a_kind
	transaction.type = a_type
	transaction.energy_cost = PRICE
	return transaction


func _of_type(a_type: String) -> Array:
	return _log.events.filter(func(e: Dictionary) -> bool: return e["type"] == a_type)


func test_funding_a_purchase_records_what_and_what_it_cost() -> void:
	_transaction(PurchaseTransaction.Kind.TRAIN, &"soldier").fund()
	var funded: Array = _of_type(MatchLog.PURCHASE_FUNDED)
	assert_eq(funded.size(), 1)
	assert_eq(funded[0]["commander"], 3)
	assert_eq(funded[0]["piece"], "soldier")
	assert_eq(funded[0]["kind"], MatchLog.KIND_UNIT)
	assert_eq(funded[0]["energy"], PRICE)


func test_a_build_is_a_structure() -> void:
	_transaction(PurchaseTransaction.Kind.BUILD, &"depot").fund()
	assert_eq(_of_type(MatchLog.PURCHASE_FUNDED)[0]["kind"], MatchLog.KIND_STRUCTURE)


func test_a_refund_is_recorded_and_a_free_cancel_is_not() -> void:
	var funded: PurchaseTransaction = _transaction(PurchaseTransaction.Kind.TRAIN, &"soldier")
	funded.fund()
	funded.cancel()
	_transaction(PurchaseTransaction.Kind.TRAIN, &"soldier").cancel()  # never paid for
	assert_eq(_of_type(MatchLog.PURCHASE_REFUNDED).size(), 1)


func test_completion_is_recorded_once_with_the_purchase_it_closes() -> void:
	var transaction: PurchaseTransaction = _transaction(PurchaseTransaction.Kind.TRAIN, &"soldier")
	transaction.fund()
	transaction.complete()
	transaction.complete()
	var completed: Array = _of_type(MatchLog.PURCHASE_COMPLETED)
	assert_eq(completed.size(), 1)
	assert_eq(completed[0]["purchase"], _of_type(MatchLog.PURCHASE_FUNDED)[0]["purchase"])


func test_a_finished_construction_is_recorded() -> void:
	var structure: Commandable = FakePieces.structure({"id": &"depot"})
	add_child_autofree(structure)
	_commander.construction_finished.emit(structure)
	var finished: Array = _of_type(MatchLog.CONSTRUCTION_FINISHED)
	assert_eq(finished.size(), 1)
	assert_eq(finished[0]["piece"], "depot")


func test_every_event_is_stamped_and_ordered() -> void:
	_log.record("anything", {"x": 1})
	var event: Dictionary = _log.events[0]
	assert_true(event.has("tick") and event.has("t") and event["type"] == "anything")
	assert_eq(event["x"], 1)


func test_the_log_round_trips_through_json_lines() -> void:
	_transaction(PurchaseTransaction.Kind.TRAIN, &"soldier").fund()
	_log.end(3)
	var parsed: Array[Dictionary] = MatchLog.parse_jsonl(_log.to_jsonl())
	assert_eq(parsed.size(), _log.events.size())
	assert_eq(parsed[0]["piece"], "soldier")
	assert_eq(int(parsed[-1]["winner"]), 3)


func test_the_gzip_file_is_plain_gzip_of_the_json_lines() -> void:
	_log.record("anything")
	var path: String = "user://test_match_log.jsonl.gz"
	assert_eq(_log.write_gzip(path), OK)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var text: String = (
		bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	)
	assert_eq(text, _log.to_jsonl())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_match_ends_once() -> void:
	_log.end(3)
	_log.end(4)
	assert_true(_log.is_ended())
	assert_eq(_of_type(MatchLog.MATCH_ENDED).size(), 1)
	assert_eq(_of_type(MatchLog.MATCH_ENDED)[0]["winner"], 3)
