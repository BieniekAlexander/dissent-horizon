extends GutTest

## The debug tuning session: an edit is written into the doc's text and previewed on every live
## piece of that type, and on every one that enters play after it. The docs are fixtures written
## to user://, never the project's.

const ROOT: String = "user://test_tuning_session"
const PIECE_DOC: String = (
	"---\n"
	+ "kind: Entity\n"
	+ "title: Fixture\n"
	+ "defense:\n"
	+ "  hp: 100\n"
	+ "movement: {speed: SLOW, turn_rate: 360}\n"
	+ "---\n"
)
const SPEEDS_DOC: String = (
	"---\n"
	+ "kind: SpeedLibrary\n"
	+ "title: Speeds\n"
	+ "speeds:\n"
	+ "  ZERO: 0\n"
	+ "  SLOW: 2\n"
	+ "  FAST: 4\n"
	+ "---\n"
)

var _session: TuningSession


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_doc("fake_tuned.md", PIECE_DOC)
	_write_doc("speeds.md", SPEEDS_DOC)
	_session = TuningSession.new()
	_session.gdd_root = ROOT
	add_child_autofree(_session)


func after_each() -> void:
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))


func _write_doc(a_name: String, a_text: String) -> void:
	var file: FileAccess = FileAccess.open(ROOT.path_join(a_name), FileAccess.WRITE)
	file.store_string(a_text)
	file.close()


func _piece(a_options: Dictionary = {}) -> Actor:
	var piece: Actor = FakePieces.unit(
		{"id": &"fake_tuned", "hp": 100.0, "speed": 2.0}.merged(a_options, true)
	)
	add_child_autofree(piece)
	piece.set_physics_process(false)
	return piece


func _field(a_path: Array) -> PieceField:
	for field: PieceField in PieceFields.of_scope(PieceField.Scope.PIECE):
		if field.doc_path == a_path:
			return field
	return null


func _edit(a_path: Array, a_value: Variant) -> void:
	var address: Dictionary = _session.piece_address(&"fake_tuned")
	assert_eq(_session.edit(address, _field(a_path), a_value, &"fake_tuned", 0), "")


func test_an_edit_is_written_into_the_doc() -> void:
	_edit(["defense", "hp"], 150)
	var address: Dictionary = _session.piece_address(&"fake_tuned")
	assert_eq(_session.value_at(address, ["defense", "hp"]), 150)
	assert_eq(_session.unsaved_paths(), [ROOT.path_join("fake_tuned.md")])


func test_an_edit_reaches_every_live_piece_of_the_type() -> void:
	var first: Actor = _piece()
	var second: Actor = _piece()
	var other: Actor = _piece({"id": &"fake_other"})
	_edit(["defense", "hp"], 150)
	assert_eq(first.defense.hp_max, 150.0)
	assert_eq(second.defense.hp_max, 150.0)
	assert_eq(other.defense.hp_max, 100.0, "another type is untouched")


func test_a_piece_entering_play_after_an_edit_takes_it() -> void:
	_edit(["defense", "hp"], 150)
	var late: Actor = _piece()
	assert_eq(late.defense.hp_max, 150.0)
	assert_eq(late.defense.hp, 150.0, "it arrives at full health, as from a re-imported scene")


func test_a_speed_is_edited_as_its_class() -> void:
	var piece: Actor = _piece()
	_edit(["movement", "speed"], "FAST")
	assert_eq(
		_session.value_at(_session.piece_address(&"fake_tuned"), ["movement", "speed"]), "FAST"
	)
	assert_almost_eq((piece.get_node("Locomotion") as Movement).speed, 4.0, 0.001)


func test_retuning_a_class_retunes_every_piece_naming_it() -> void:
	var piece: Actor = _piece()
	assert_eq(_session.set_speed("SLOW", 3.0), "")
	assert_almost_eq((piece.get_node("Locomotion") as Movement).speed, 3.0, 0.001)
	var late: Actor = _piece()
	assert_almost_eq((late.get_node("Locomotion") as Movement).speed, 3.0, 0.001)


func test_the_speed_ladder_stays_increasing() -> void:
	assert_ne(_session.set_speed("SLOW", 5.0), "", "SLOW may not pass FAST")
	assert_ne(_session.set_speed("FAST", 1.0), "", "FAST may not fall below SLOW")
	assert_eq(_session.speed_ladder()["SLOW"], 2, "a refused edit changes nothing")


func test_a_value_the_doc_leaves_unsaid_shows_the_running_value() -> void:
	var piece: Actor = _piece()
	var shown: Dictionary = _session.shown_value(
		_session.piece_address(&"fake_tuned"), _field(["defense", "armour"]), {"node": piece}
	)
	assert_eq(shown, {"value": "LIGHT", "is_default": true})


func test_save_writes_an_edited_doc_that_validates() -> void:
	_edit(["defense", "hp"], 150)
	var report: Dictionary = _session.save()
	assert_eq(report["refused"], [], "nothing refused")
	assert_eq(report["saved"], [ROOT.path_join("fake_tuned.md")])
	assert_true(
		FileAccess.get_file_as_string(ROOT.path_join("fake_tuned.md")).contains("  hp: 150")
	)
	assert_eq(_session.unsaved_paths(), [], "a saved doc has nothing left unsaved")


func test_save_refuses_a_doc_the_importer_would_refuse_and_writes_nothing() -> void:
	var address: Dictionary = _session.piece_address(&"fake_tuned")
	# A movement key the importer refuses outright: it is not one of MOVEMENT_KEYS.
	var bad := PieceField.new()
	bad.scope = PieceField.Scope.PIECE
	bad.doc_path = ["movement", "not_a_key"]
	bad.kind = PieceField.Kind.NUMBER
	bad.is_live = false
	assert_eq(_session.edit(address, bad, 1, &"fake_tuned", 0), "")
	var report: Dictionary = _session.save()
	assert_eq(report["saved"], [])
	assert_eq(report["refused"].size() > 0, true, "the doc is refused")
	assert_eq(FileAccess.get_file_as_string(ROOT.path_join("fake_tuned.md")), PIECE_DOC)


#region Projectiles
const SHELL_DOC: String = (
	"---\n"
	+ "kind: Entity\n"
	+ "title: Fake shell\n"
	+ "damage: 10\n"
	+ "damage_type: LEAD\n"
	+ "hitscan: false\n"
	+ "phases:\n"
	+ "  - name: Flight\n"
	+ "    motion: {speed: FAST}\n"
	+ "    lifespan: 2\n"
	+ "  - name: Impact\n"
	+ "    lifespan: 0\n"
	+ "    payload: once\n"
	+ "---\n"
)


func _emission_field(a_scope: PieceField.Scope, a_path: Array) -> PieceField:
	for field: PieceField in PieceFields.of_scope(a_scope):
		if field.doc_path == a_path:
			return field
	return null


func _shell_address() -> Dictionary:
	_write_doc("fake_shell.md", SHELL_DOC)
	_session.free()
	_session = TuningSession.new()
	_session.gdd_root = ROOT
	add_child_autofree(_session)
	return _session.piece_address(&"fake_shell")


func test_a_projectile_entering_play_takes_its_edited_payload() -> void:
	var shell: Dictionary = _shell_address()
	var damage: PieceField = _emission_field(PieceField.Scope.EMISSION, ["damage"])
	assert_eq(_session.edit(shell, damage, 25, &"fake_unit", 0), "")
	var fired: Entity = FakePieces.emission()
	add_child_autofree(fired)
	assert_eq(Payload.of(fired).base_damage, 25.0)


func test_a_projectile_entering_play_takes_its_edited_phases() -> void:
	var shell: Dictionary = _shell_address()
	var phases: Array = _session.phases_of(shell)
	phases.insert(1, {"name": "Coast", "motion": {"speed": "SLOW"}, "lifespan": 1})
	assert_eq(_session.set_phases(shell, phases), "")
	var fired: Entity = FakePieces.emission()
	add_child_autofree(fired)
	var names: Array = (
		fired
		. get_children()
		. filter(func(c: Node) -> bool: return c is EmissionPhase)
		. map(func(c: Node) -> String: return String(c.name))
	)
	assert_eq(names, ["Flight", "Coast", "Impact"], "phases run in the doc's order")
	assert_almost_eq((fired.get_node("Coast") as EmissionPhase).speed, 2.0, 0.001)


func test_a_projectile_entering_play_takes_its_edited_status_effects() -> void:
	var effect := StatusEffect.new()
	effect.name = "FakeStun"
	var packed := PackedScene.new()
	packed.pack(effect)
	effect.free()
	ResourceSaver.save(packed, ROOT.path_join("fake_stun.tscn"))
	_write_doc(
		"fake_stun.md",
		(
			"---\nkind: StatusEffect\ntitle: Fake stun\nscene: %s\n---\n"
			% ROOT.path_join("fake_stun.tscn")
		)
	)
	var shell: Dictionary = _shell_address()
	var effects: PieceField = _emission_field(PieceField.Scope.EMISSION, ["status_effects"])
	assert_eq(_session.edit(shell, effects, ["fake_stun"], &"fake_unit", 0), "")
	var fired: Entity = FakePieces.emission()
	add_child_autofree(fired)
	assert_eq(PieceFields.applied_effects(fired), ["fake_stun"])


func test_a_status_effect_list_reads_out_as_names() -> void:
	var effects: PieceField = _emission_field(PieceField.Scope.EMISSION, ["status_effects"])
	assert_eq(PieceFields.display(effects, ["bio_stun", "emp"]), "bio stun, emp")
	assert_eq(PieceFields.display(effects, []), "none")


#endregion


func test_a_folded_section_stays_folded_when_it_is_rebuilt() -> void:
	var first := CollapsibleSection.make("test/fold", "Fold", true)
	first.set_open(false)
	first.free()
	var again := CollapsibleSection.make("test/fold", "Fold", true)
	assert_false(again.is_open(), "the reader's fold outlives the nodes")
	again.free()
