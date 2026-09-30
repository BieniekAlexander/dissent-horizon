extends GutTest

## Whether an emission damages an AREA or only the thing it was aimed at: exactly when it
## carries a HitShape, which only a non-hitscan emission has. The importer removes a hitscan
## emission's HitShape, and the Payload reads presence alone (Payload.has_blast).
##
## The rule once had to be "hitscan wins, and a DISABLED shape counts as none", because every
## emission inherited a HitShape it could not remove — and before that, an assertion on the
## combination crashed the game the moment a hitscan emission fired. Both are covered below on
## fake emissions (tests/_fake_pieces.gd), not on any shipped piece.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProjectileBlast.gd -gexit


func _payload_of(a_options: Dictionary) -> Payload:
	var emission: Entity = FakePieces.emission(a_options)
	add_child_autofree(emission)
	return Payload.of(emission)


func test_a_hitscan_emission_can_be_instantiated_and_has_no_blast() -> void:
	# Entering the tree runs _ready — the crash, reduced.
	var payload: Payload = _payload_of({"hitscan": true, "hit_shape": false})
	assert_true(payload.hitscan)
	assert_null(payload.hit_shape(), "it carries no HitShape")
	assert_false(payload.has_blast(), "so it resolves onto its target alone")


func test_a_non_hitscan_emission_with_a_shape_has_a_blast() -> void:
	var shell: Payload = _payload_of({"hitscan": false, "hit_shape": true})
	assert_false(shell.hitscan, "a shell is not hitscan")
	assert_true(shell.has_blast(), "so its shape is its blast")
