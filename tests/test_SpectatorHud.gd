extends GutTest

## The spectator HUD's per-commander labels repaint on `Commander.resources_changed`, and the
## commander outlives the HUD: a harness frees the HUD, and a structure withdraws infrastructure
## on PREDELETE after its scenario's labels are gone. Freeing the HUD must cut the connection,
## or the next emission passes a freed label to a typed parameter.
##
## The Scenario stays OUT of the tree (its _ready boots a whole session); only the HUD layer it
## builds is moved into the tree, since the disconnect rides the label leaving it.

var _scenario: Scenario
var _commander: Commander
var _hud: Node


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 1
	var neutral := Commander.new()
	neutral.id = 0
	_scenario = Scenario.new()
	_scenario.commanders = [neutral, _commander]
	_scenario._setup_spectator_hud()
	_hud = _scenario.get_node("SpectatorHUD")
	_scenario.remove_child(_hud)
	add_child(_hud)


func after_each() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	for commander: Commander in _scenario.commanders:
		commander.free()
	_scenario.free()


func _label() -> RichTextLabel:
	return _hud.find_child("CommanderLabel_1", true, false) as RichTextLabel


func test_label_repaints_on_resource_change() -> void:
	_commander.add_energy(7)
	assert_string_contains(_label().text, "energy: %d" % _commander.energy)


func test_freeing_the_hud_disconnects_its_labels() -> void:
	assert_eq(_commander.resources_changed.get_connections().size(), 1)
	_hud.free()
	assert_eq(_commander.resources_changed.get_connections().size(), 0)
	# The emission that used to log "Cannot convert argument 1 from Object to Object".
	var before: int = _commander.energy
	_commander.add_energy(1)
	assert_eq(_commander.energy, before + 1)


func test_commander_freed_before_hud_is_harmless() -> void:
	_commander.free()
	_scenario.commanders.erase(_commander)
	_hud.free()
	assert_false(is_instance_valid(_hud))
