class_name SanctionGrid extends RefCounted

## A commander's per-match sanction state, built from its Faction's sanction grid
## (Faction.sanction_unlocks). Each SanctionUnlock is wrapped in an Entry that tracks
## whether this commander owns it yet and holds a live, duplicated Sanction instance
## so cooldowns are per-commander.
##
## THE GRID HAS TWO AXES: NUM_TIERS rows by NUM_COLUMNS columns, one unlock per cell,
## with a column holding one family of sanctions and a row being a tier. See
## SanctionUnlock for why the two axes carry different rules. Three things follow, and
## this class is where all three are enforced:
##
##   • UNLOCKING is gated twice. The PARENT (the unlock this one continues) must be
##     owned — a cell with no parent heads its family and passes outright. The TIER
##     must be open — tier 0 always is, and every tier below it opens once
##     UNLOCKS_TO_OPEN_NEXT_TIER cells in the tier above are owned, whichever ones.
##
##   • OWNING AN UPGRADE RETIRES WHAT IT UPGRADES. A cell whose child is owned is
##     SUPERSEDED: still owned, no longer deployable (see is_superseded). Freeze 2
##     replaces Freeze 1 on the sanction bar rather than joining it, so a column is one
##     sanction the player improves — which is also what keeps the deployable bar to
##     roughly one button per column however deep the player goes.
##
##   • AUTHORING FAULTS ARE REPORTED WHEN THE SANCTION GRID IS BUILT, not left to fail
##     silently at runtime as "that sanction never became available" (see
##     _report_authoring_faults).
##
## The SanctionUnlock templates are shared, read-only authored data; all mutable
## ownership state lives here.

## Rows. A faction authors as few as it likes but never past this — the fixed shape is
## what lets the HUD draw one grid and the player learn one sanction grid, rather than each
## faction redefining what a tier means.
const NUM_TIERS: int = 4

## Columns, i.e. how many sanction families a sanction grid can run at once. Six, matching
## the command grid's width (see ControlBinding.GRID_WIDTH), so the game's two HUD
## grids are the same shape on screen.
const NUM_COLUMNS: int = 6

## Unlocks that must be owned in a tier before the NEXT tier opens. Two, so depth costs
## breadth — and any two, so WHICH two stays the player's choice.
const UNLOCKS_TO_OPEN_NEXT_TIER: int = 2

## Why an entry cannot be unlocked right now, or MET. Affordability is deliberately NOT
## one of these — it is asked separately (can_afford), because the remedies differ
## completely: a closed gate needs other unlocks, a price needs time.
enum Requirement {
	MET,  ## unlockable now, dominion permitting
	ALREADY_OWNED,  ## nothing left to buy
	PARENT_LOCKED,  ## the family it continues has not been taken this far
	TIER_LOCKED,  ## too few unlocks owned in the tier above it
}


## One grid cell plus this commander's ownership state for it.
class Entry:
	var unlock: SanctionUnlock  ## shared authored template (slot, parent, cost)
	var sanction: Sanction  ## live per-commander instance (duplicated)
	var owned: bool = false

	func tier() -> int:
		return unlock.tier

	func column() -> int:
		return unlock.column


var _commander: Commander
## Every cell that survived validation. Iteration order is authored order; anything
## that cares about the LAYOUT reads the grid (tier_entries / cell) instead.
var entries: Array[Entry] = []
var _by_unlock: Dictionary = {}  ## SanctionUnlock -> Entry, for parent lookups
var _children: Dictionary = {}  ## SanctionUnlock -> Array[Entry] that supersede it
var _grid: Array[Array] = []  ## [tier][column] -> Entry or null


func _init(a_commander: Commander, a_unlocks: Array) -> void:
	_commander = a_commander
	for _tier: int in NUM_TIERS:
		var row: Array = []
		row.resize(NUM_COLUMNS)  # null-filled
		_grid.append(row)
	for unlock: SanctionUnlock in a_unlocks:
		if unlock == null or unlock.sanction == null:
			continue
		if not _slot_is_usable(unlock):
			continue
		var entry := Entry.new()
		entry.unlock = unlock
		entry.sanction = unlock.sanction.duplicate()
		entries.append(entry)
		_by_unlock[unlock] = entry
		_grid[unlock.tier][unlock.column] = entry
	_index_children()
	_report_authoring_faults()


#region The grid
## The entries in one tier, left to right, skipping empty cells — the HUD's row. An
## out-of-range tier returns empty rather than erroring: the caller is normally a loop
## over NUM_TIERS.
func tier_entries(a_tier: int) -> Array[Entry]:
	var out: Array[Entry] = []
	if a_tier < 0 or a_tier >= NUM_TIERS:
		return out
	for a_column: int in NUM_COLUMNS:
		var entry: Entry = _grid[a_tier][a_column]
		if entry != null:
			out.append(entry)
	return out


## The entry in one cell, or null when the faction authored nothing there. What a grid
## HUD wants: the gaps have to be drawn as gaps, or the columns stop lining up and a
## family reads as belonging to whichever one shifted into its place.
func cell(a_tier: int, a_column: int) -> Entry:
	if a_tier < 0 or a_tier >= NUM_TIERS or a_column < 0 or a_column >= NUM_COLUMNS:
		return null
	return _grid[a_tier][a_column]


## The highest column index the faction actually authored, plus one — the width worth
## drawing. NUM_COLUMNS is the ceiling; this is the occupancy, so a faction using four
## families is not drawn with two empty columns after them.
func used_columns() -> int:
	var width: int = 0
	for entry: Entry in entries:
		width = maxi(width, entry.column() + 1)
	return width


#endregion


#region Unlocking
## How many of one tier's entries this commander owns.
func owned_count_in_tier(a_tier: int) -> int:
	var count: int = 0
	for entry: Entry in tier_entries(a_tier):
		if entry.owned:
			count += 1
	return count


## True when `a_tier`'s entries may be bought at all: tier 0 always, every other tier
## once UNLOCKS_TO_OPEN_NEXT_TIER of the tier above are owned.
func tier_is_open(a_tier: int) -> bool:
	if a_tier <= 0:
		return true
	return owned_count_in_tier(a_tier - 1) >= UNLOCKS_TO_OPEN_NEXT_TIER


## How many more unlocks in the tier above are needed to open `a_tier` (0 = already
## open). What the HUD says instead of a bare "locked", since the player can act on it.
func unlocks_needed_to_open(a_tier: int) -> int:
	if a_tier <= 0:
		return 0
	return maxi(0, UNLOCKS_TO_OPEN_NEXT_TIER - owned_count_in_tier(a_tier - 1))


## What stands between the commander and `entry`, checked parent-first: a cell deep in
## an untaken family is better described by the family than by its tier.
func unmet_requirement(a_entry: Entry) -> Requirement:
	if a_entry.owned:
		return Requirement.ALREADY_OWNED
	if a_entry.unlock.parent != null and not _owns(a_entry.unlock.parent):
		return Requirement.PARENT_LOCKED
	if not tier_is_open(a_entry.tier()):
		return Requirement.TIER_LOCKED
	return Requirement.MET


## True when `entry` can be unlocked next: not yet owned, its family taken this far,
## its tier open.
func is_available(a_entry: Entry) -> bool:
	return unmet_requirement(a_entry) == Requirement.MET


## True when the commander has the dominion to pay for `entry`.
func can_afford(a_entry: Entry) -> bool:
	return _commander.dominion >= a_entry.unlock.dominion_cost


## The dominion price of the DEAREST cell the commander could unlock next, or -1 when the
## grid offers nothing (everything owned, or every remaining cell locked behind a tier or a
## family).
##
## "Available", not "affordable": the question this answers is *is the whole of what is open
## to me now within reach*, which is what makes it worth saying on the resource card — the
## moment the answer turns yes is the moment banking more dominion stops buying anything.
func dearest_available_cost() -> int:
	var dearest: int = -1
	for entry: Entry in entries:
		if is_available(entry):
			dearest = maxi(dearest, entry.unlock.dominion_cost)
	return dearest


## The dominion price of the CHEAPEST cell the commander could unlock next, or -1 when the
## grid offers nothing. The DominionBar's low-water mark (see gdd/systems/ux/ui/economy-bars.md)
## — the moment dominion covers this, saving further is buying the player their first option
## rather than nothing at all.
func cheapest_available_cost() -> int:
	var cheapest: int = -1
	for entry: Entry in entries:
		if is_available(entry):
			cheapest = (
				entry.unlock.dominion_cost
				if cheapest < 0
				else mini(cheapest, entry.unlock.dominion_cost)
			)
	return cheapest


## The dominion it would take to buy every cell this commander does not own yet, gated or not:
## what dominion can still be spent on over the match. 0 for a full or empty grid — a commander
## for whom banking more dominion buys nothing.
func unowned_cost() -> int:
	var total: int = 0
	for entry: Entry in entries:
		if not entry.owned:
			total += entry.unlock.dominion_cost
	return total


## Attempt to unlock `entry`: it must be available and affordable. On success, spends
## the dominion and marks it owned. Returns whether it unlocked.
func try_unlock(a_entry: Entry) -> bool:
	if not is_available(a_entry) or not can_afford(a_entry):
		return false
	_commander.add_dominion(-a_entry.unlock.dominion_cost)
	a_entry.owned = true
	return true


#endregion


#region Deployment
## The highest level of `a_ability_id` this commander has unlocked, or 0 for none.
##
## The single fact supersession is derived from: an ability is cast at the best level you
## have bought, and every lower cell for it is out of play. Derived rather than stored, so
## there is no second thing to keep in step with what the player owns.
func effective_level(a_ability_id: StringName) -> int:
	var best: int = 0
	for entry: Entry in entries:
		if entry.owned and entry.sanction.ability_id == a_ability_id:
			best = maxi(best, entry.sanction.ability_level)
	return best


## True when this cell has been upgraded out of play: a higher level of the same ability is
## unlocked. Still owned — its cell reads as bought and still pays its share of the tier
## toll — but no longer the one that gets cast.
##
## REPLACES the old parent-chain rule, which asked "is a child of this cell owned?". That
## could only ever express a single chain, so a cell that raises SEVERAL abilities at once
## (Colonial Drop 2 grants `drop2` and upgrades `drop1`) had no way to be described. Levels
## say the same thing about the simple case and the compound one alike.
func is_superseded(a_entry: Entry) -> bool:
	if String(a_entry.sanction.ability_id).is_empty():
		return false
	return a_entry.sanction.ability_level < effective_level(a_entry.sanction.ability_id)


## True when `entry`'s sanction is on the bar and can be fired: owned, not upgraded out
## of play, and not a passive (which has no deployment at all — see Sanction.passive).
func is_deployable(a_entry: Entry) -> bool:
	return a_entry.owned and not a_entry.sanction.passive and not is_superseded(a_entry)


## The live Sanctions whose STANDING benefits apply: owned, not upgraded out of play, and
## passive. The counterpart to deployable_sanctions — between them they partition the
## owned, non-superseded set, so every cell the player has paid for is doing exactly one
## of the two things.
func standing_sanctions() -> Array[Sanction]:
	var out: Array[Sanction] = []
	for entry: Entry in entries:
		if entry.owned and entry.sanction.passive and not is_superseded(entry):
			out.append(entry.sanction)
	return out


## Whether this faction's grid has ANY cell granting `a_ability_id`, owned or not — "could
## this commander ever have this", as against `deployable_entry_for`'s "can it use this now".
##
## Derived from the faction's own authored grid rather than from a faction TAG on the
## ability, so the two cannot disagree: what a faction offers IS its grid. Why the ordnance
## card needs this question rather than the other:
## gdd/systems/macroeconomics/sanctions/sanction-grid.md §What a faction offers IS its grid.
func has_route_to(a_ability_id: StringName) -> bool:
	for entry: Entry in entries:
		if entry.sanction != null and entry.sanction.ability_id == a_ability_id:
			return true
	return false


## The one cell of `a_ability_id` currently in play for this commander — owned, not upgraded
## out of play, not passive — or null when the grid holds none. There is at most one by
## construction: supersession is derived from the level, so only the highest owned level
## survives it. This is what the HUD asks when it draws one button per ABILITY rather than
## one per cell.
func deployable_entry_for(a_ability_id: StringName) -> Entry:
	for entry: Entry in entries:
		if entry.sanction.ability_id == a_ability_id and is_deployable(entry):
			return entry
	return null


## The live Sanction instances the commander can actually deploy, in grid order. Every
## consumer — the sanction bar, the bot, cooldown ticking — reads this rather than
## filtering `entries` itself, so nothing can leave a superseded sanction in play.
func deployable_sanctions() -> Array[Sanction]:
	var out: Array[Sanction] = []
	for entry: Entry in entries:
		if is_deployable(entry):
			out.append(entry.sanction)
	return out


#endregion


## The sanctions `a_caster` may cast: deployable (owned, not superseded, not passive) and
## in a family the piece's own Abilities component grants.
##
## The piece is asked, not the sanction — see Sanction.ability_id for why. A piece with no
## Abilities component casts nothing, which is most of the roster, so this is cheap to ask
## of any entity.
func castable_by(a_caster: Commandable) -> Array[Sanction]:
	var out: Array[Sanction] = []
	if a_caster == null or not is_instance_valid(a_caster):
		return out
	var abilities := a_caster.get_node_or_null("Abilities") as Abilities
	if abilities == null:
		return out
	for entry: Entry in entries:
		if is_deployable(entry) and abilities.grants(entry.sanction.ability_id):
			out.append(entry.sanction)
	return out


## Whether `a_sanction` is unlocked and in play for this commander — the sanction grid's half of
## "may this be cast", asked by the command's precondition once it knows the caster.
func is_unlocked(a_sanction: Sanction) -> bool:
	for entry: Entry in entries:
		if entry.sanction == a_sanction:
			return is_deployable(entry)
	return false


func _owns(a_unlock: SanctionUnlock) -> bool:
	var entry: Entry = _by_unlock.get(a_unlock)
	return entry != null and entry.owned


func _children_of(a_unlock: SanctionUnlock) -> Array:
	return _children.get(a_unlock, [])


## Reject a cell that cannot be placed at all — an out-of-grid slot, or one already
## taken. Both would otherwise silently vanish from the HUD.
func _slot_is_usable(a_unlock: SanctionUnlock) -> bool:
	var label: String = a_unlock.sanction.sanction_name
	if a_unlock.tier < 0 or a_unlock.tier >= NUM_TIERS:
		push_error(
			(
				"SanctionGrid: '%s' sits in tier %d, outside [0, %d) — dropped."
				% [label, a_unlock.tier, NUM_TIERS]
			)
		)
		return false
	if a_unlock.column < 0 or a_unlock.column >= NUM_COLUMNS:
		push_error(
			(
				"SanctionGrid: '%s' sits in column %d, outside [0, %d) — dropped."
				% [label, a_unlock.column, NUM_COLUMNS]
			)
		)
		return false
	var sitting: Entry = _grid[a_unlock.tier][a_unlock.column]
	if sitting != null:
		push_error(
			(
				"SanctionGrid: '%s' and '%s' both claim cell (tier %d, column %d) — '%s' dropped."
				% [sitting.sanction.sanction_name, label, a_unlock.tier, a_unlock.column, label]
			)
		)
		return false
	return true


## Index each cell under the parent it supersedes. Built once: `parent` is authored
## data, and only ownership changes during a match.
func _index_children() -> void:
	for entry: Entry in entries:
		var parent: SanctionUnlock = entry.unlock.parent
		if parent == null:
			continue
		if not _children.has(parent):
			_children[parent] = []
		(_children[parent] as Array).append(entry)


## Report the ways a faction's grid can be authored into something no commander could
## walk. Each is silent at runtime — the sanction simply never becomes available — so
## they are named here, once, when the sanction grid is built.
func _report_authoring_faults() -> void:
	for entry: Entry in entries:
		var parent: SanctionUnlock = entry.unlock.parent
		if parent == null:
			continue
		var label: String = entry.sanction.sanction_name
		if not _by_unlock.has(parent):
			push_error(
				(
					(
						"SanctionGrid: '%s' names a parent that is not in the faction's "
						+ "sanction_unlocks — it can never unlock."
					)
					% label
				)
			)
			continue
		if parent.tier >= entry.tier():
			push_error(
				(
					(
						"SanctionGrid: '%s' (tier %d) names a parent in tier %d — a "
						+ "parent must sit in a strictly lower tier."
					)
					% [label, entry.tier(), parent.tier]
				)
			)
		if parent.column != entry.column():
			push_error(
				(
					(
						"SanctionGrid: '%s' (column %d) names a parent in column %d — a "
						+ "parent must share its child's column."
					)
					% [label, entry.column(), parent.column]
				)
			)
	# A tier whose predecessor cannot supply UNLOCKS_TO_OPEN_NEXT_TIER never opens, which
	# walls off every tier below it too.
	for a_tier: int in range(1, NUM_TIERS):
		var here: int = tier_entries(a_tier).size()
		var above: int = tier_entries(a_tier - 1).size()
		if here > 0 and above < UNLOCKS_TO_OPEN_NEXT_TIER:
			push_error(
				(
					(
						"SanctionGrid: tier %d holds %d unlocks but tier %d holds only "
						+ "%d — tier %d can never open (needs %d)."
					)
					% [a_tier, here, a_tier - 1, above, a_tier, UNLOCKS_TO_OPEN_NEXT_TIER]
				)
			)
