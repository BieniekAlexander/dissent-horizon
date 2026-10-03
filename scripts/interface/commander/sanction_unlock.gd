class_name SanctionUnlock extends Resource

## One cell in a faction's sanction GRID: it wraps an Sanction with the dominion cost
## to acquire it, the (tier, column) slot it occupies, and the unlock whose chain it
## continues.
##
## The grid's two axes carry two different rules, and keeping them separate is the
## whole design (all of it enforced in SanctionGrid, never here — these resources
## are read-only authored templates):
##
##   • ROW = TIER, and tiers gate BREADTH. Reaching tier N at all costs
##     SanctionGrid.UNLOCKS_TO_OPEN_NEXT_TIER unlocks at tier N-1, WHICHEVER ones,
##     so the player must spread across the sanction grid rather than rushing one chain.
##
##   • COLUMN = a family of related sanctions (every Scan, every Freeze), and a
##     `parent` edge is DEPTH within one. A sanction continues exactly one family, so
##     `parent` is a single nullable reference rather than a list, and a parent must
##     share its child's column. Sharing a column does NOT imply an edge: the
##     Colonials' Gunship sits under Scan 2 without continuing it.
##
##     A parent must sit in a strictly LOWER tier, but not necessarily the one directly
##     above — Freeze 2 is two tiers below Freeze 1, and Blizzard two below that. The
##     gap is what makes the tier rule bite: continuing a family late means paying the
##     breadth toll to get down there.
##
## An unlock SUPERSEDES its parent: acquiring Freeze 2 replaces Freeze 1 in the
## deployable set rather than sitting beside it (see SanctionGrid.is_superseded), so
## a column is one evolving sanction, not a growing collection of them.
##
## This replaced an "any-of" `prerequisites: Array[SanctionUnlock]`, which expressed
## breadth and depth as one edge list and therefore neither well: breadth had to be
## faked by pointing every deep node at every shallow one, a genuine chain was
## indistinguishable from a fan-in, and nothing said which unlock an upgrade upgraded.

## The sanction this cell grants once unlocked.
@export var sanction: Sanction

## Which sanction grid row this sits in, 0-based. Must be in [0, SanctionGrid.NUM_TIERS).
## Not range-annotated here on purpose — naming the constant would make SanctionUnlock
## and SanctionGrid mutually dependent at parse time.
@export var tier: int = 0

## Which sanction grid column this sits in, 0-based. Must be in [0, SanctionGrid.NUM_COLUMNS).
## One unlock per (tier, column): the cell is a slot on screen, so two unlocks claiming
## it cannot both be drawn.
@export var column: int = 0

## The unlock this one continues and replaces, or null when it heads its family. Must
## also appear in the faction's `sanction_unlocks` (the node set must be closed), sit
## in a strictly lower tier, and share this unlock's column.
@export var parent: SanctionUnlock = null

## Dominion spent to unlock it.
@export var dominion_cost: int = 0
