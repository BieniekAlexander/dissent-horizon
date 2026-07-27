extends GutTest

## Preloaded (not via class_name) so the test runs even when the global class
## cache hasn't rescanned new files (headless runs don't refresh it).
const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")

## SpecFrontmatter: the YAML-subset frontmatter parser feeding the spec importer.
## Covers the exact shapes the doc schema uses (scalars, flow collections, block
## lists/maps, weapon-style lists of maps, wikilinks, comments) and the loud
## failure modes (unclosed fence, tab indentation).


func _data(a_markdown: String) -> Dictionary:
	var result: Dictionary = SpecFrontmatter.parse(a_markdown)
	assert_true(result["ok"], "expected parse to succeed, got: %s" % result["error"])
	return result["data"]


func test_doc_without_frontmatter_is_ok_and_empty() -> void:
	var result: Dictionary = SpecFrontmatter.parse("# Just prose\nNo fences here.\n")
	assert_true(result["ok"])
	assert_eq(result["data"], {})


func test_unclosed_fence_errors() -> void:
	var result: Dictionary = SpecFrontmatter.parse("---\nkind: unit\n# no closing fence\n")
	assert_false(result["ok"])
	assert_string_contains(result["error"], "never closed")


func test_scalar_typing() -> void:
	var data: Dictionary = _data("""---
kind: unit
hp: 160
speed: 1.2
stealthy: true
grounded: false
note: "quoted: value"
empty: null
scene: res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn
---
body
""")
	assert_eq(data["kind"], "unit")
	assert_eq(data["hp"], 160)
	assert_almost_eq(data["speed"], 1.2, 0.0001)
	assert_eq(data["stealthy"], true)
	assert_eq(data["grounded"], false)
	assert_eq(data["note"], "quoted: value")
	assert_null(data["empty"])
	assert_eq(data["scene"], "res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn")


func test_flow_collections() -> void:
	var data: Dictionary = _data("""---
cost: {energy: 250, infrastructure: 0}
hits: [ground, air]
grid: [1, 2]
---
""")
	assert_eq(data["cost"], {"energy": 250, "infrastructure": 0})
	assert_eq(data["hits"], ["ground", "air"])
	assert_eq(data["grid"], [1, 2])


func test_block_list_and_wikilinks() -> void:
	var data: Dictionary = _data("""---
starts_with:
- stronghold
- "[[warlord]]"
- "[[factions/baladians/pieces/irregular#Stats|the irregular]]"
requires: ["[[stronghold]]"]
---
""")
	assert_eq(data["starts_with"], ["stronghold", "warlord", "irregular"])
	assert_eq(data["requires"], ["stronghold"])


func test_nested_block_map() -> void:
	var data: Dictionary = _data("""---
movement:
  mode: GROUNDED
  speed: 1.2
  turn_rate: 1080
---
""")
	assert_eq(data["movement"]["mode"], "GROUNDED")
	assert_almost_eq(data["movement"]["speed"], 1.2, 0.0001)
	assert_eq(data["movement"]["turn_rate"], 1080)


func test_sequence_of_mappings_weapons_shape() -> void:
	var data: Dictionary = _data("""---
weapons:
  - name: Rocket
    projectile: "[[warlord_rocket]]"
    split_time: 1.5
    reach: {ground: 4, air: 10}
    hits: [ground, air]
  - name: Bayonet
    melee_damage: 10
---
""")
	var weapons: Array = data["weapons"]
	assert_eq(weapons.size(), 2)
	assert_eq(weapons[0]["name"], "Rocket")
	assert_eq(weapons[0]["projectile"], "warlord_rocket")
	assert_almost_eq(weapons[0]["split_time"], 1.5, 0.0001)
	assert_eq(weapons[0]["reach"], {"ground": 4, "air": 10})
	assert_eq(weapons[1]["name"], "Bayonet")
	assert_eq(weapons[1]["melee_damage"], 10)


func test_sequence_items_at_same_indent_as_key() -> void:
	# Obsidian's property editor writes list items unindented (the user's own
	# faction sketch uses this shape).
	var data: Dictionary = _data("""---
name: baladians
starts_with:
- stronghold
- warlord
---
""")
	assert_eq(data["starts_with"], ["stronghold", "warlord"])


func test_comments_are_ignored() -> void:
	var data: Dictionary = _data("""---
# full-line comment
hp: 160 # trailing comment
label: "keep # inside quotes"
---
""")
	assert_eq(data["hp"], 160)
	assert_eq(data["label"], "keep # inside quotes")


func test_tab_indentation_errors() -> void:
	var result: Dictionary = SpecFrontmatter.parse("---\nmovement:\n\tspeed: 1\n---\n")
	assert_false(result["ok"])
	assert_string_contains(result["error"], "tab")


func test_strip_wikilink_forms() -> void:
	assert_eq(SpecFrontmatter.strip_wikilink("[[warlord]]"), "warlord")
	assert_eq(SpecFrontmatter.strip_wikilink("[[dir/sub/warlord]]"), "warlord")
	assert_eq(SpecFrontmatter.strip_wikilink("[[warlord|The Boss]]"), "warlord")
	assert_eq(SpecFrontmatter.strip_wikilink("[[warlord#Stats]]"), "warlord")
	assert_eq(SpecFrontmatter.strip_wikilink("not a link"), "not a link")
	assert_eq(SpecFrontmatter.strip_wikilink("prefix [[warlord]]"), "prefix [[warlord]]")


# --- Block scalars ---------------------------------------------------------------
## Multi-paragraph copy (a sanction's `verbose:`) has to survive the frontmatter, and
## the parser collapses a block scalar into one value before the mapping parser ever
## sees it — so these check the value, not the plumbing.

func _parsed(a_lines: Array[String]) -> Dictionary:
	var result: Dictionary = SpecFrontmatter.parse_yaml(a_lines)
	assert_true(result["ok"], result["error"])
	return result["data"]


func test_a_literal_block_keeps_its_newlines() -> void:
	var data: Dictionary = _parsed(["verbose: |", "  first line", "  second line"])
	assert_eq(data["verbose"], "first line\nsecond line")


func test_a_literal_block_keeps_blank_lines_as_paragraph_breaks() -> void:
	var data: Dictionary = _parsed([
		"verbose: |", "  one", "", "  two",
	])
	assert_eq(data["verbose"], "one\n\ntwo")


func test_trailing_blank_lines_are_dropped() -> void:
	# Chomping indicators are accepted but not honoured; the value is always trimmed.
	var data: Dictionary = _parsed(["verbose: |", "  one", "", ""])
	assert_eq(data["verbose"], "one")


func test_a_folded_block_joins_lines_within_a_paragraph() -> void:
	var data: Dictionary = _parsed([
		"verbose: >", "  one", "  two", "", "  three",
	])
	assert_eq(data["verbose"], "one two\nthree")


func test_a_hash_inside_a_block_is_content_not_a_comment() -> void:
	# Comment stripping must not reach inside prose.
	var data: Dictionary = _parsed(["verbose: |", "  costs 5 # of your energy"])
	assert_eq(data["verbose"], "costs 5 # of your energy")


func test_a_block_ends_at_the_next_key() -> void:
	var data: Dictionary = _parsed([
		"verbose: |", "  prose", "title: Ambush",
	])
	assert_eq(data["verbose"], "prose")
	assert_eq(data["title"], "Ambush")


func test_a_block_scalar_works_inside_a_sequence_item() -> void:
	# The shape sanction docs actually use: `levels:` is a list of mappings, each of
	# which may carry a multi-line `verbose:`.
	var data: Dictionary = _parsed([
		"levels:",
		"  - title: Ambush 1",
		"    verbose: |",
		"      first",
		"      second",
		"  - title: Ambush 2",
	])
	var levels: Array = data["levels"]
	assert_eq(levels.size(), 2)
	assert_eq(levels[0]["verbose"], "first\nsecond")
	assert_eq(levels[1]["title"], "Ambush 2")


func test_relative_indentation_inside_a_block_is_preserved() -> void:
	var data: Dictionary = _parsed([
		"verbose: |", "  top", "    nested",
	])
	assert_eq(data["verbose"], "top\n  nested")


#region Duplicate keys
## YAML's own rule is last-wins, silently. That is the worst answer for a governing spec: the
## value a reader sees first is not the value the game gets, and the two differ precisely when
## somebody edited the wrong line. Validation here is total and loud, so a doc that says two
## things about one key aborts the import.
func test_a_key_written_twice_is_refused() -> void:
	var result: Dictionary = SpecFrontmatter.parse_yaml(["hp: 100", "hp: 250"] as Array[String])
	assert_false(result["ok"], "a repeated key is an error, not a last-wins overwrite")
	assert_string_contains(result["error"], "duplicate key")
	assert_string_contains(result["error"], "hp", "the message names the offending key")


func test_a_duplicate_inside_a_nest_is_refused() -> void:
	# The nested schema means most keys now live one level down, so the check has to hold
	# there too — `build:` carrying two `cost:` lines is the realistic version of this typo.
	var result: Dictionary = SpecFrontmatter.parse_yaml(
		["build:", "  cost: {energy: 100}", "  cost: {energy: 250}"] as Array[String])
	assert_false(result["ok"], "a repeated key inside a nest is refused too")
	assert_string_contains(result["error"], "duplicate key")


func test_the_same_key_in_two_different_nests_is_fine() -> void:
	# Not a duplicate: the rule is per LEVEL, and sibling components legitimately share sub-key
	# names. Refusing this would make the nesting unusable.
	var data: Dictionary = _parsed([
		"build:", "  time: 20", "defense:", "  time: 5",
	] as Array[String])
	assert_eq((data["build"] as Dictionary)["time"], 20)
	assert_eq((data["defense"] as Dictionary)["time"], 5)


func test_the_same_key_in_two_sequence_items_is_fine() -> void:
	# Every weapon has a `name:`; that is the schema working, not a collision.
	var data: Dictionary = _parsed([
		"weapons:", "  - name: A", "  - name: B",
	] as Array[String])
	var weapons: Array = data["weapons"]
	assert_eq(weapons.size(), 2)
	assert_eq((weapons[0] as Dictionary)["name"], "A")
	assert_eq((weapons[1] as Dictionary)["name"], "B")
#endregion


## Every doc in the vault parses. This is the sweep that makes the duplicate-key rule above
## safe to add: a new hard error is only worth having if the roster is already clean of it,
## and this says so per file rather than leaving it to the next import to discover.
##
## Scans all of gdd/, not just specs — a prose note with frontmatter is parsed by the same
## code when the importer walks the tree, so a malformed one is worth catching here.
func test_every_doc_in_the_vault_parses() -> void:
	var broken: Array[String] = []
	for path: String in _all_markdown("res://gdd"):
		var result: Dictionary = SpecFrontmatter.parse(FileAccess.get_file_as_string(path))
		if not result["ok"]:
			broken.append("%s: %s" % [path.get_file(), result["error"]])
	assert_eq(broken, [] as Array[String], "every markdown doc under gdd/ has parseable frontmatter")


func _all_markdown(a_dir: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(a_dir)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".md"):
			found.append("%s/%s" % [a_dir, file])
	for sub: String in dir.get_directories():
		# Obsidian's own config directory carries no specs and no prose worth parsing.
		if not sub.begins_with("."):
			found.append_array(_all_markdown("%s/%s" % [a_dir, sub]))
	return found
