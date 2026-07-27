extends GutTest

## SanctionGrid turns a faction's sanction GRID into a commander's per-match state.
## Four things are pinned here, because each fails silently in play:
##   • the grid — a cell is addressable by (tier, column), gaps stay gaps;
##   • the two unlock gates — the parent (depth, within one column) and the tier
##     (breadth, two unlocks in the row above);
##   • supersession — an upgrade REPLACES what it upgrades in the deployable set;
##   • the authoring faults, each of which would otherwise present as "that sanction
##     just never becomes available".
##
## Built from hand-made SanctionUnlock resources (no scene needed) against a bare
## Commander.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SanctionGrid.gd -gexit

var _cmdr: Commander


func before_each() -> void:
	_cmdr = Commander.new()
	_cmdr.dominion = 0


func after_each() -> void:
	_cmdr.free()


func _sanction(a_name: String) -> Sanction:
	var o := Sanction.new()
	o.sanction_name = a_name
	return o


## One cell. `parent` is the unlock this one continues; it must share `column`.
##
## `ability` / `ability_level` are what decide SUPERSESSION now — a cell is upgraded out of
## play when a HIGHER LEVEL of the same ability is owned, not when a child of it is (see
## SanctionGrid.is_superseded). `parent` survives only as the unlock GATE. The ability
## defaults to the cell's own name, which is the "each cell is its own ability" case; a
## chain passes the same `ability` with rising `ability_level`.
func _unlock(a_name: String, a_tier: int, a_column: int, a_cost: int = 0,
		a_parent: SanctionUnlock = null, a_ability: String = "", a_ability_level: int = 1) -> SanctionUnlock:
	var u := SanctionUnlock.new()
	u.sanction = _sanction(a_name)
	u.sanction.ability_id = StringName(a_ability if a_ability != "" else a_name.to_snake_case())
	u.sanction.ability_level = a_ability_level
	u.tier = a_tier
	u.column = a_column
	u.dominion_cost = a_cost
	u.parent = a_parent
	return u


func _sanction_grid(a_unlocks: Array) -> SanctionGrid:
	return SanctionGrid.new(_cmdr, a_unlocks)


## Two cells in tier 0, which is the minimum that lets tier 1 ever open. Most tests
## need them only as toll-payers, so they are cheap and unnamed by the assertions.
func _tier0_pair() -> Array:
	return [_unlock("Toll A", 0, 4), _unlock("Toll B", 0, 5)]


func _own_tier0_pair(a_sanction_grid: SanctionGrid) -> void:
	for entry: SanctionGrid.Entry in a_sanction_grid.tier_entries(0):
		if entry.sanction.sanction_name.begins_with("Toll"):
			assert_true(a_sanction_grid.try_unlock(entry), "the toll cell unlocks")


func _entry_named(a_sanction_grid: SanctionGrid, a_name: String) -> SanctionGrid.Entry:
	for entry: SanctionGrid.Entry in a_sanction_grid.entries:
		if entry.sanction.sanction_name == a_name:
			return entry
	return null


# --- The grid -------------------------------------------------------------------

func test_a_cell_is_addressable_by_tier_and_column() -> void:
	var scan1 := _unlock("Scan 1", 0, 1)
	var sanction_grid := _sanction_grid([scan1])

	assert_eq(sanction_grid.cell(0, 1), sanction_grid.entries[0], "the cell holds its entry")
	assert_null(sanction_grid.cell(0, 0), "an unauthored cell is empty, not the next entry along")
	assert_null(sanction_grid.cell(-1, 0), "an out-of-grid cell reads as empty rather than erroring")
	assert_null(sanction_grid.cell(0, SanctionGrid.NUM_COLUMNS), "…at either end")


func test_a_tier_reads_left_to_right_skipping_gaps() -> void:
	# Authored out of order on purpose: the GRID is the layout, not the array.
	var sanction_grid := _sanction_grid([_unlock("Right", 0, 3), _unlock("Left", 0, 0)])
	var row: Array = sanction_grid.tier_entries(0)

	assert_eq(row.size(), 2)
	assert_eq((row[0] as SanctionGrid.Entry).sanction.sanction_name, "Left")
	assert_eq((row[1] as SanctionGrid.Entry).sanction.sanction_name, "Right")


func test_used_columns_reports_occupancy_not_the_ceiling() -> void:
	var sanction_grid := _sanction_grid([_unlock("A", 0, 0), _unlock("B", 0, 2)])
	assert_eq(sanction_grid.used_columns(), 3, "the width worth drawing spans column 2")
	assert_lt(sanction_grid.used_columns(), SanctionGrid.NUM_COLUMNS, "…which is under the ceiling")


func test_two_unlocks_cannot_share_a_cell() -> void:
	# A cell is a slot on screen; the second claimant could not be drawn, so it is
	# dropped loudly rather than disappearing.
	var sanction_grid := _sanction_grid([_unlock("First", 0, 0), _unlock("Second", 0, 0)])

	assert_eq(sanction_grid.entries.size(), 1, "only the first claimant is kept")
	assert_eq(sanction_grid.entries[0].sanction.sanction_name, "First")
	assert_push_error_count(1, "the collision is reported")


func test_an_out_of_grid_slot_is_dropped() -> void:
	var sanction_grid := _sanction_grid([_unlock("Too deep", SanctionGrid.NUM_TIERS, 0)])
	assert_eq(sanction_grid.entries.size(), 0)
	assert_push_error_count(1, "the out-of-range tier is reported")


# --- The parent gate (depth) ----------------------------------------------------

func test_a_family_head_is_available_and_its_child_is_not() -> void:
	# Two LEVELS of one ability — which is what makes the second replace the first. The
	# parent edge only gates buying; supersession reads the levels.
	var freeze1 := _unlock("Freeze 1", 0, 0, 0, null, "freeze", 1)
	var freeze2 := _unlock("Freeze 2", 1, 0, 0, freeze1, "freeze", 2)
	var sanction_grid := _sanction_grid([freeze1, freeze2] + _tier0_pair())

	assert_true(sanction_grid.is_available(_entry_named(sanction_grid, "Freeze 1")),
		"a cell with no parent heads its family and is available")
	assert_eq(sanction_grid.unmet_requirement(_entry_named(sanction_grid, "Freeze 2")),
		SanctionGrid.Requirement.PARENT_LOCKED,
		"the child is blocked by its parent, not by its tier")


func test_a_child_unlocks_once_its_parent_is_owned() -> void:
	_cmdr.dominion = 1000
	var freeze1 := _unlock("Freeze 1", 0, 0, 10)
	var freeze2 := _unlock("Freeze 2", 1, 0, 20, freeze1)
	var sanction_grid := _sanction_grid([freeze1, freeze2] + _tier0_pair())
	_own_tier0_pair(sanction_grid)  # open tier 1

	assert_false(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 2")),
		"the child can't be bought before its parent")
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 1")))
	assert_true(sanction_grid.is_available(_entry_named(sanction_grid, "Freeze 2")),
		"owning the parent opens the child")
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 2")))


func test_a_parent_may_sit_more_than_one_tier_above() -> void:
	# The Colonials' Blizzard is two tiers below Freeze 2. Non-adjacency is the point:
	# continuing a family late still costs the breadth toll to get down there.
	_cmdr.dominion = 1000
	var freeze1 := _unlock("Freeze 1", 0, 0)
	var blizzard := _unlock("Blizzard", 2, 0, 0, freeze1)
	var sanction_grid := _sanction_grid([freeze1, blizzard] + _tier0_pair() + [
		_unlock("Toll C", 1, 4), _unlock("Toll D", 1, 5)
	])
	_own_tier0_pair(sanction_grid)  # open tier 1

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 1")))
	assert_eq(sanction_grid.unmet_requirement(_entry_named(sanction_grid, "Blizzard")),
		SanctionGrid.Requirement.TIER_LOCKED,
		"its parent is owned; only tier 2 is still shut")
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Toll C")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Toll D")))
	assert_true(sanction_grid.is_available(_entry_named(sanction_grid, "Blizzard")),
		"opening tier 2 reaches a cell whose parent is two tiers up")


func test_sharing_a_column_does_not_imply_an_edge() -> void:
	# The Colonials' Gunship sits under Scan 3 without continuing it.
	var sanction_grid := _sanction_grid(_tier0_pair() + [_unlock("Gunship", 1, 4)])
	_own_tier0_pair(sanction_grid)

	assert_true(sanction_grid.is_available(_entry_named(sanction_grid, "Gunship")),
		"a parentless cell needs only its tier, whoever shares its column")


# --- The tier gate (breadth) ----------------------------------------------------

func test_tier_zero_is_open_from_the_start() -> void:
	var sanction_grid := _sanction_grid(_tier0_pair())
	assert_true(sanction_grid.tier_is_open(0))
	assert_eq(sanction_grid.unlocks_needed_to_open(0), 0)


func test_a_tier_opens_on_the_second_unlock_in_the_tier_above() -> void:
	_cmdr.dominion = 1000
	var sanction_grid := _sanction_grid(_tier0_pair() + [_unlock("Deep", 1, 0)])

	assert_false(sanction_grid.tier_is_open(1))
	assert_eq(sanction_grid.unlocks_needed_to_open(1), SanctionGrid.UNLOCKS_TO_OPEN_NEXT_TIER)
	assert_true(sanction_grid.try_unlock(sanction_grid.tier_entries(0)[0]))
	assert_false(sanction_grid.tier_is_open(1), "one is not enough")
	assert_eq(sanction_grid.unlocks_needed_to_open(1), 1, "and the shortfall is reported, not just 'locked'")
	assert_true(sanction_grid.try_unlock(sanction_grid.tier_entries(0)[1]))
	assert_true(sanction_grid.tier_is_open(1), "the second opens it")
	assert_eq(sanction_grid.unlocks_needed_to_open(1), 0)


func test_which_two_is_the_players_choice() -> void:
	# The gate counts unlocks in the tier, never particular ones — that is the whole
	# difference between it and a parent edge.
	_cmdr.dominion = 1000
	var sanction_grid := _sanction_grid([
		_unlock("A", 0, 0), _unlock("B", 0, 1), _unlock("C", 0, 2), _unlock("Deep", 1, 0)
	])

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "B")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "C")))
	assert_true(sanction_grid.tier_is_open(1), "any two in the tier open the next")


func test_a_superseded_cell_still_pays_the_tier_toll() -> void:
	# It stops being deployable but does not stop having been bought — otherwise
	# upgrading a family would shut the tiers it had already opened.
	_cmdr.dominion = 1000
	var scan1 := _unlock("Scan 1", 0, 0, 0, null, "scan", 1)
	var scan2 := _unlock("Scan 2", 1, 0, 0, scan1, "scan", 2)
	var sanction_grid := _sanction_grid([scan1, scan2, _unlock("Other", 0, 1)])

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Scan 1")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Other")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Scan 2")))
	assert_true(sanction_grid.is_superseded(_entry_named(sanction_grid, "Scan 1")))
	assert_true(sanction_grid.tier_is_open(1), "tier 1 stays open with a superseded cell paying for it")


# --- Cost -----------------------------------------------------------------------

func test_unlock_spends_dominion_and_marks_owned() -> void:
	_cmdr.dominion = 25
	var sanction_grid := _sanction_grid([_unlock("Ambush", 0, 0, 10)])
	var entry: SanctionGrid.Entry = sanction_grid.entries[0]

	assert_true(sanction_grid.try_unlock(entry), "affordable + available unlock succeeds")
	assert_true(entry.owned, "the entry is now owned")
	assert_eq(_cmdr.dominion, 15, "the dominion cost was spent")


func test_cannot_unlock_when_unaffordable() -> void:
	_cmdr.dominion = 5
	var sanction_grid := _sanction_grid([_unlock("Ambush", 0, 0, 10)])
	var entry: SanctionGrid.Entry = sanction_grid.entries[0]

	assert_false(sanction_grid.try_unlock(entry), "can't unlock without the dominion")
	assert_false(entry.owned)
	assert_eq(_cmdr.dominion, 5, "no dominion spent on a failed unlock")
	assert_true(sanction_grid.is_available(entry), "…but the gates are open, which is a separate question")


# --- Supersession ---------------------------------------------------------------

func test_an_upgrade_replaces_what_it_upgrades_on_the_bar() -> void:
	_cmdr.dominion = 1000
	# Two LEVELS of one ability — which is what makes the second replace the first. The
	# parent edge only gates buying; supersession reads the levels.
	var freeze1 := _unlock("Freeze 1", 0, 0, 0, null, "freeze", 1)
	var freeze2 := _unlock("Freeze 2", 1, 0, 0, freeze1, "freeze", 2)
	var sanction_grid := _sanction_grid([freeze1, freeze2] + _tier0_pair())
	_own_tier0_pair(sanction_grid)

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 1")))
	var deployable: Array = sanction_grid.deployable_sanctions()
	assert_eq(deployable.size(), 3, "Freeze 1 plus the two toll cells are deployable")

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 2")))
	var names: Array = sanction_grid.deployable_sanctions().map(func(o: Sanction): return o.sanction_name)
	assert_does_not_have(names, "Freeze 1", "the upgraded sanction leaves the deployable set")
	assert_has(names, "Freeze 2", "and its replacement takes the slot")
	assert_true(_entry_named(sanction_grid, "Freeze 1").owned, "it is still owned, just superseded")
	assert_false(sanction_grid.is_deployable(_entry_named(sanction_grid, "Freeze 1")))


func test_an_unowned_child_supersedes_nothing() -> void:
	_cmdr.dominion = 1000
	# Two LEVELS of one ability — which is what makes the second replace the first. The
	# parent edge only gates buying; supersession reads the levels.
	var freeze1 := _unlock("Freeze 1", 0, 0, 0, null, "freeze", 1)
	var freeze2 := _unlock("Freeze 2", 1, 0, 0, freeze1, "freeze", 2)
	var sanction_grid := _sanction_grid([freeze1, freeze2] + _tier0_pair())

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Freeze 1")))
	assert_false(sanction_grid.is_superseded(_entry_named(sanction_grid, "Freeze 1")),
		"merely HAVING an upgrade authored above it changes nothing")
	assert_true(sanction_grid.is_deployable(_entry_named(sanction_grid, "Freeze 1")))


func test_a_whole_chain_collapses_to_its_deepest_owned_cell() -> void:
	_cmdr.dominion = 1000
	var d1 := _unlock("Drop 1", 0, 0, 0, null, "drop", 1)
	var d2 := _unlock("Drop 2", 1, 0, 0, d1, "drop", 2)
	var d3 := _unlock("Drop 3", 2, 0, 0, d2, "drop", 3)
	var sanction_grid := _sanction_grid([d1, d2, d3] + _tier0_pair() + [
		_unlock("Toll C", 1, 4), _unlock("Toll D", 1, 5)
	])
	_own_tier0_pair(sanction_grid)
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Drop 1")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Drop 2")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Toll C")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Toll D")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Drop 3")))

	var names: Array = sanction_grid.deployable_sanctions().map(func(o: Sanction): return o.sanction_name)
	assert_does_not_have(names, "Drop 1")
	assert_does_not_have(names, "Drop 2")
	assert_has(names, "Drop 3", "one button for the family, however deep the player went")


# --- Live instances -------------------------------------------------------------

func test_deployable_sanctions_are_per_commander_duplicates() -> void:
	_cmdr.dominion = 100
	var template := _sanction("Ambush")
	var unlock := SanctionUnlock.new()
	unlock.sanction = template
	unlock.dominion_cost = 10
	var sanction_grid := _sanction_grid([unlock])
	sanction_grid.try_unlock(sanction_grid.entries[0])

	var live: Sanction = sanction_grid.deployable_sanctions()[0]
	assert_ne(live, template, "the sanction grid holds a duplicate, not the authored template")
	# The duplicate still matters, but no longer because of a cooldown: an Sanction keeps
	# none any more — the charge lives on the casting BUILDING (see Abilities). What
	# must not leak back to the shared template is any per-commander edit at all.
	live.sanction_name = "Renamed"
	assert_eq(template.sanction_name, "Ambush", "editing the live copy doesn't touch the template")


# --- Authoring faults -----------------------------------------------------------

func test_a_parent_outside_the_faction_list_is_reported() -> void:
	var orphan := _unlock("Orphan parent", 0, 0)
	var child := _unlock("Child", 1, 0, 0, orphan)
	var sanction_grid := _sanction_grid([child] + _tier0_pair())

	assert_push_error_count(1, "a parent the faction never listed can never be owned")
	assert_eq(sanction_grid.unmet_requirement(_entry_named(sanction_grid, "Child")),
		SanctionGrid.Requirement.PARENT_LOCKED, "and the cell is dead, as reported")


func test_an_upside_down_edge_is_reported() -> void:
	# A parent must sit ABOVE its child. Pointing at a deeper cell would make the family
	# unreachable from the top and supersede the wrong way round. (Same tier, same column
	# is unreachable by construction — it would be the same cell.)
	var deep := _unlock("Deep", 2, 0)
	var shallow := _unlock("Shallow", 1, 0, 0, deep)
	_sanction_grid([deep, shallow, _unlock("Toll A", 0, 4), _unlock("Toll B", 0, 5),
		_unlock("Toll C", 1, 4)])

	assert_push_error_count(1, "a parent below its child is reported")


func test_a_parent_in_a_different_column_is_reported() -> void:
	var scan := _unlock("Scan 1", 0, 1)
	var drop := _unlock("Drop 1", 1, 0, 0, scan)  # crosses families
	_sanction_grid([scan, drop, _unlock("Toll", 0, 5)])

	assert_push_error_count(1, "a cross-column parent breaks the column-is-a-family rule")


func test_a_tier_that_can_never_open_is_reported() -> void:
	# One cell in tier 0 can never pay a two-unlock toll, so tier 1 is walled off.
	_sanction_grid([_unlock("Lonely", 0, 0), _unlock("Unreachable", 1, 0)])

	assert_push_error_count(1, "the unreachable tier is reported when the sanction grid is built")


# --- Supersession is derived from ABILITY LEVELS --------------------------------

func test_a_cell_can_raise_an_ability_it_does_not_sit_under() -> void:
	# The case the parent chain could not express, and the reason it stopped deciding
	# supersession: Colonial Drop 2 grants `drop2` AND upgrades `drop1`. Two cells, three
	# ability levels — a one-parent edge per cell has nowhere to put the second grant.
	_cmdr.dominion = 1000
	var d1 := _unlock("Drop 1", 0, 0, 0, null, "drop1", 1)
	var d2 := _unlock("Drop 2", 1, 0, 0, d1, "drop2", 1)
	# The same cell as Drop 2, expressed as the second thing it grants.
	var d1_up := _unlock("Drop 1+", 1, 1, 0, null, "drop1", 2)
	var sanction_grid := _sanction_grid([d1, d2, d1_up, _unlock("Other", 0, 2)])

	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Drop 1")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Other")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Drop 1+")))

	assert_true(sanction_grid.is_superseded(_entry_named(sanction_grid, "Drop 1")),
		"the level-1 cell is out of play even though nothing PARENTED to it was bought")
	assert_eq(sanction_grid.effective_level(&"drop1"), 2)
	assert_eq(sanction_grid.effective_level(&"drop2"), 0, "an ability nothing unlocked is at level 0")


func test_an_ability_with_no_id_is_never_superseded() -> void:
	# A cell that names no ability (a passive, or one still being authored) has no level to
	# be beaten, so it must not silently drop off the bar.
	_cmdr.dominion = 1000
	var lone := _unlock("Lone", 0, 0)
	lone.sanction.ability_id = &""
	var sanction_grid := _sanction_grid([lone, _unlock("Other", 0, 1)])
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Lone")))
	assert_false(sanction_grid.is_superseded(_entry_named(sanction_grid, "Lone")))


func test_the_lower_level_stays_owned_and_still_pays_its_toll() -> void:
	# Unchanged from the chain rule: buying an upgrade must not shut a tier the earlier cell
	# had already opened.
	_cmdr.dominion = 1000
	var s1 := _unlock("S1", 0, 0, 0, null, "s", 1)
	var s2 := _unlock("S2", 1, 0, 0, s1, "s", 2)
	var sanction_grid := _sanction_grid([s1, s2, _unlock("Other", 0, 1)])
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "S1")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "Other")))
	assert_true(sanction_grid.try_unlock(_entry_named(sanction_grid, "S2")))
	assert_true(_entry_named(sanction_grid, "S1").owned)
	assert_true(sanction_grid.tier_is_open(1))
