extends GutTest

## Scavenge — the Anarchists' PASSIVE sanction family. Unlocking a cell turns on a
## standing bounty: every enemy you destroy pays back a share of its build cost in energy.
##
## Three things are pinned here, because all three are silent when wrong: a passive must
## stay OFF the deploy bar (a button that does nothing reads as a bug), the rate must
## follow supersession rather than accumulate, and an unpriced or friendly kill must pay
## nothing rather than erroring or funding you.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_KillBounty.gd -gexit

var _cmdr: Commander


func before_each() -> void:
	_cmdr = Commander.new()
	_cmdr.energy = 0
	_cmdr.dominion = 10000


func after_each() -> void:
	_cmdr.free()


func _passive(a_name: String, a_fraction: float, a_tier: int, a_column: int,
		a_parent: SanctionUnlock = null) -> SanctionUnlock:
	var sanction := Sanction.new()
	sanction.sanction_name = a_name
	sanction.passive = true
	sanction.kill_bounty_fraction = a_fraction
	var unlock := SanctionUnlock.new()
	unlock.sanction = sanction
	unlock.tier = a_tier
	unlock.column = a_column
	unlock.parent = a_parent
	return unlock


func _active(a_name: String, a_tier: int, a_column: int) -> SanctionUnlock:
	var sanction := Sanction.new()
	sanction.sanction_name = a_name
	var unlock := SanctionUnlock.new()
	unlock.sanction = sanction
	unlock.tier = a_tier
	unlock.column = a_column
	return unlock


## A three-tier Scavenge column beside two ordinary cells, so tier 1 can actually open.
func _sanction_grid() -> SanctionGrid:
	var s1 := _passive("Scavenge 1", 0.10, 0, 0)
	var s2 := _passive("Scavenge 2", 0.20, 1, 0, s1)
	var filler_a := _active("A", 0, 1)
	var filler_b := _active("B", 0, 2)
	var sanction_grid := SanctionGrid.new(_cmdr, [s1, s2, filler_a, filler_b])
	_cmdr.sanction_grid = sanction_grid
	return sanction_grid


# --- A passive is owned but never deployed ---------------------------------------

func test_a_passive_is_not_deployable() -> void:
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])
	assert_true(sanction_grid.entries[0].owned, "it is owned")
	assert_false(sanction_grid.is_deployable(sanction_grid.entries[0]),
		"but it never reaches the deploy bar")
	assert_eq(sanction_grid.deployable_sanctions().size(), 0)


func test_a_passive_shows_up_as_standing() -> void:
	# deployable_sanctions and standing_sanctions partition the owned, non-superseded
	# set — every cell the player paid for does exactly one of the two things.
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])   # Scavenge 1
	sanction_grid.try_unlock(sanction_grid.entries[2])   # filler A, an ordinary sanction
	assert_eq(sanction_grid.standing_sanctions().size(), 1, "the passive stands")
	assert_eq(sanction_grid.deployable_sanctions().size(), 1, "the active deploys")


func test_activating_a_passive_is_refused() -> void:
	# The refusal lives in Sanction.activate, the choke point the bot walks too — not
	# only in the HUD that keeps the button off the bar.
	var sanction := Sanction.new()
	sanction.passive = true
	assert_false(sanction.activate(Vector3.ZERO, null, null),
		"a passive has no deployment")


# --- The rate --------------------------------------------------------------------

func test_no_bounty_without_a_passive() -> void:
	var sanction_grid := _sanction_grid()
	assert_eq(_cmdr.kill_bounty_rate(), 0.0, "owning nothing pays nothing")
	sanction_grid.try_unlock(sanction_grid.entries[2])  # an ordinary sanction grants no bounty
	assert_eq(_cmdr.kill_bounty_rate(), 0.0)


func test_a_commander_with_no_sanctions_pays_nothing() -> void:
	# Commander 0 (neutral) and any faction-less commander have no sanction grid at all.
	assert_eq(_cmdr.kill_bounty_rate(), 0.0)
	assert_eq(_cmdr.kill_bounty_for(EntityIds.AN_BIO_LIGHT_BUILDER), 0)


func test_unlocking_the_first_tier_sets_the_rate() -> void:
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])
	assert_almost_eq(_cmdr.kill_bounty_rate(), 0.10, 0.001)


func test_the_upgrade_replaces_rather_than_stacks() -> void:
	# Scavenge 2 supersedes Scavenge 1, so the rate becomes 20% — not 30%. A refund
	# larger than the unit's price would print money.
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])
	sanction_grid.try_unlock(sanction_grid.entries[2])  # second tier-0 unlock opens tier 1
	sanction_grid.try_unlock(sanction_grid.entries[1])
	assert_true(sanction_grid.entries[1].owned, "Scavenge 2 is owned")
	assert_almost_eq(_cmdr.kill_bounty_rate(), 0.20, 0.001)


# --- The payout ------------------------------------------------------------------

func test_the_bounty_is_a_share_of_the_pieces_build_cost() -> void:
	# Derived from technology.json rather than hardcoded, so rebalancing a unit's price
	# rebalances its bounty instead of breaking this test.
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])
	var spec: TechnologySpec = _cmdr.technology_mapping.get(EntityIds.AN_BIO_LIGHT_BUILDER)
	assert_not_null(spec, "the Irregular is priced")
	assert_eq(_cmdr.kill_bounty_for(EntityIds.AN_BIO_LIGHT_BUILDER), roundi(spec.energy_cost * 0.10))


func test_an_unpriced_piece_pays_nothing() -> void:
	# Neutral scenery and scenario-only entities have no technology entry. Killing one
	# must pay nothing rather than erroring on a null spec.
	var sanction_grid := _sanction_grid()
	sanction_grid.try_unlock(sanction_grid.entries[0])
	assert_eq(_cmdr.kill_bounty_for(&"no_such_piece"), 0)
