extends GutTest

## OrdnanceArsenal turns a faction's ordnance DAG into a commander's per-match state:
## availability follows the any-of prerequisite rule, unlocking is gated on dominion,
## and owned ordnances are per-commander duplicates. Built here from hand-made
## OrdnanceUnlock resources (no scene needed) against a bare Commander.

var _cmdr: Commander


func before_each() -> void:
	_cmdr = Commander.new()
	_cmdr.dominion = 0


func after_each() -> void:
	_cmdr.free()


func _ordnance(a_name: String) -> Ordnance:
	var o := Ordnance.new()
	o.ordnance_name = a_name
	return o


func _unlock(a_name: String, cost: int, prereqs: Array = []) -> OrdnanceUnlock:
	var u := OrdnanceUnlock.new()
	u.ordnance = _ordnance(a_name)
	u.dominion_cost = cost
	var typed: Array[OrdnanceUnlock] = []
	typed.assign(prereqs)
	u.prerequisites = typed
	return u


func _arsenal(unlocks: Array) -> OrdnanceArsenal:
	return OrdnanceArsenal.new(_cmdr, unlocks)


func test_root_is_available_dependent_is_locked() -> void:
	var ambush := _unlock("Ambush", 10)
	var irradiate := _unlock("Irradiate", 20, [ambush])
	var arsenal := _arsenal([ambush, irradiate])

	assert_true(arsenal.is_available(arsenal.entries[0]), "a node with no prerequisites is available")
	assert_false(arsenal.is_available(arsenal.entries[1]), "a dependent node is locked until its prerequisite")


func test_unlock_spends_dominion_and_marks_owned() -> void:
	_cmdr.dominion = 25
	var arsenal := _arsenal([_unlock("Ambush", 10)])
	var entry := arsenal.entries[0]

	assert_true(arsenal.try_unlock(entry), "affordable + available unlock succeeds")
	assert_true(entry.owned, "the entry is now owned")
	assert_eq(_cmdr.dominion, 15, "the dominion cost was spent")


func test_cannot_unlock_when_unaffordable() -> void:
	_cmdr.dominion = 5
	var arsenal := _arsenal([_unlock("Ambush", 10)])
	var entry := arsenal.entries[0]

	assert_false(arsenal.try_unlock(entry), "can't unlock without the dominion")
	assert_false(entry.owned)
	assert_eq(_cmdr.dominion, 5, "no dominion spent on a failed unlock")


func test_cannot_unlock_until_prerequisite_owned() -> void:
	_cmdr.dominion = 1000
	var ambush := _unlock("Ambush", 10)
	var irradiate := _unlock("Irradiate", 20, [ambush])
	var arsenal := _arsenal([ambush, irradiate])

	assert_false(arsenal.try_unlock(arsenal.entries[1]), "the dependent can't be bought first")
	assert_true(arsenal.try_unlock(arsenal.entries[0]), "unlock the prerequisite")
	assert_true(arsenal.is_available(arsenal.entries[1]), "now the dependent is available")
	assert_true(arsenal.try_unlock(arsenal.entries[1]), "and can be unlocked")


func test_prerequisites_are_any_of_not_all_of() -> void:
	_cmdr.dominion = 1000
	var a := _unlock("A", 10)
	var b := _unlock("B", 10)
	var c := _unlock("C", 10, [a, b])  # gated by EITHER a or b
	var arsenal := _arsenal([a, b, c])

	assert_false(arsenal.is_available(arsenal.entries[2]), "c is locked while neither prerequisite is owned")
	assert_true(arsenal.try_unlock(arsenal.entries[0]), "own just one prerequisite (a)")
	assert_true(arsenal.is_available(arsenal.entries[2]), "owning ANY prerequisite unlocks c")


func test_owned_ordnances_are_per_commander_duplicates() -> void:
	_cmdr.dominion = 100
	var template := _ordnance("Ambush")
	var unlock := OrdnanceUnlock.new()
	unlock.ordnance = template
	unlock.dominion_cost = 10
	var arsenal := _arsenal([unlock])
	arsenal.try_unlock(arsenal.entries[0])

	var live: Ordnance = arsenal.owned_ordnances()[0]
	assert_ne(live, template, "the arsenal holds a duplicate, not the authored template")
	live.tick(5.0)  # would mutate cooldown state; must not touch the template
	assert_eq(template.cooldown_remaining(), 0.0, "ticking the live copy doesn't affect the template")
