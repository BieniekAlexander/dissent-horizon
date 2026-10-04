class_name PieceIcons
extends RefCounted

## The picture a unit or structure is drawn as on the HUD — its production button, its
## debug-spawner card, and every CommandableCard (selection, training, queue, occupants).
##
## An icon is found by CONVENTION, not declared: `<ICON_DIRECTORY><piece id>.png`. Every Actor
## has one by the same rule, so a doc key would only repeat the id. A piece with no file has
## no icon, and the HUD falls back to its text label — an icon nobody has drawn yet is an
## unfilled asset slot, which the spec importer REPORTS (`has_hud_icon`) and the game never
## raises (CLAUDE.md §Asset slots).
##
## Today every icon is a PLACEHOLDER: a stock photograph — an animal per unit, a tree per
## structure — fetched by `tools/piece_icons/fetch_placeholder_icons.py`. Which icons are
## placeholders is whatever that script credited (`PLACEHOLDER_CREDITS_PATH`); the importer's
## `hud_icon_is_final` rule reports them until real art replaces them.

## The folder every piece icon lives in. Fixed because the icon is found by convention: a
## second location would be a second place to look, and a piece found in neither would be
## ambiguous between "not drawn yet" and "drawn somewhere else".
const ICON_DIRECTORY: String = "res://assets/icons/pieces/"
const ICON_EXTENSION: String = ".png"
## Written by the fetch script: piece id -> the stock photograph standing in for its icon.
const PLACEHOLDER_CREDITS_PATH: String = ICON_DIRECTORY + "credits.json"


## Where `id`'s icon lives, whether or not anything is there yet.
static func path_for(id: StringName) -> String:
	return ICON_DIRECTORY + String(id) + ICON_EXTENSION


static func has_icon(id: StringName) -> bool:
	return id != &"" and ResourceLoader.exists(path_for(id))


## `id`'s icon, or null when no icon has been made for that piece (its slot is unfilled and
## the caller draws the piece's name instead).
static func for_id(id: StringName) -> Texture2D:
	return load(path_for(id)) as Texture2D if has_icon(id) else null


## Whether `id`'s icon is a stock-photo stand-in rather than art made for the piece. Reads the
## credits file on every call: it is asked by the importer once per piece, never per frame.
static func is_placeholder(id: StringName) -> bool:
	if not FileAccess.file_exists(PLACEHOLDER_CREDITS_PATH):
		return false
	var credits: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PLACEHOLDER_CREDITS_PATH)
	)
	return credits is Dictionary and (credits as Dictionary).has(String(id))
