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
scene: res://scenes/entities/units/an/warlord.tscn
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
	assert_eq(data["scene"], "res://scenes/entities/units/an/warlord.tscn")


func test_flow_collections() -> void:
	var data: Dictionary = _data("""---
cost: {ore: 250, vigor: 0}
hits: [ground, air]
grid: [1, 2]
---
""")
	assert_eq(data["cost"], {"ore": 250, "vigor": 0})
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
  mode: GROUNDED_DIRECT
  speed: 1.2
  turn_rate: 1080
---
""")
	assert_eq(data["movement"]["mode"], "GROUNDED_DIRECT")
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
