extends GutTest

## Where the broaden and narrow modifiers sit on each platform: macOS moves them off Ctrl
## (which it turns into a right click) onto Option and Command.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PlatformModifiers.gd -gexit

var _saved: Dictionary = {}


func before_each() -> void:
	for action: StringName in [PlatformModifiers.BROADEN, PlatformModifiers.NARROW]:
		_saved[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)


func _physical_keys(a_action: StringName) -> Array:
	var keys: Array = []
	for event: InputEvent in InputMap.action_get_events(a_action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


func test_macos_puts_broaden_on_option_and_narrow_on_command() -> void:
	var keys: Dictionary = PlatformModifiers.keys_for("macOS")
	assert_eq(keys[PlatformModifiers.BROADEN], KEY_ALT)
	assert_eq(keys[PlatformModifiers.NARROW], KEY_META)


func test_other_platforms_keep_the_project_bindings() -> void:
	for platform: String in ["Windows", "Linux", "Web"]:
		assert_true(PlatformModifiers.keys_for(platform).is_empty(), platform)
		assert_false(PlatformModifiers.apply(platform), platform)


func test_applying_for_macos_rebinds_the_actions() -> void:
	assert_true(PlatformModifiers.apply("macOS"))
	assert_eq(_physical_keys(PlatformModifiers.BROADEN), [KEY_ALT])
	assert_eq(_physical_keys(PlatformModifiers.NARROW), [KEY_META])


func test_applying_twice_does_not_stack_events() -> void:
	PlatformModifiers.apply("macOS")
	PlatformModifiers.apply("macOS")
	assert_eq(_physical_keys(PlatformModifiers.BROADEN).size(), 1)
	assert_eq(_physical_keys(PlatformModifiers.NARROW).size(), 1)


func test_a_non_mac_apply_leaves_the_defaults_alone() -> void:
	var before: Array = _physical_keys(PlatformModifiers.BROADEN)
	PlatformModifiers.apply("Linux")
	assert_eq(_physical_keys(PlatformModifiers.BROADEN), before)
