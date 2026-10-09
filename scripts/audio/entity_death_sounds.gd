class_name EntityDeathSounds

## Per-entity death sound, played once from Entity._on_death() for whichever entity
## just died — unlike ControlFeedbackSounds, this isn't player-command feedback, so
## it fires regardless of who owns the entity or who is currently selecting it.
##
## Every piece: a structure's collapse is its death sound, not a separate event. A piece with
## no entry is silent at runtime; the spec importer reports it as an unfilled asset slot
## (`has_death_sound`), and a piece that means to die silently says so with an `exceptions:`
## waiver in its doc, never with an empty entry here.
## TODO: no structure has a death sound yet — deferred; the importer lists each one.

#region Constants
const _DEATH := preload("res://assets/audio/barks/death.otterbahn.wav")

## Each unit's entry is written out individually (rather than shared off one
## constant) so a future piece can get its own death clip without restructuring
## this file, even though every unit currently points at the same one.
## Which clip plays is the audio's own draw, never the simulation's (see AU.shuffle).
static var _rng := RandomNumberGenerator.new()

static var lines: Dictionary[StringName, Array] = {
	EntityIds.CL_BIO_LIGHT_ANTI_MECH: [_DEATH],
	EntityIds.LB_AIRCRAFT_LIGHT_BUILDER: [_DEATH],
	EntityIds.AN_AIRCRAFT_LIGHT_TRANSPORT: [_DEATH],
	EntityIds.AN_MECH_STRONG_TRANSPORT: [_DEATH],
	EntityIds.LB_AIRCRAFT_LIGHT_ANTI_MECH: [_DEATH],
	EntityIds.AN_BIO_LIGHT_BUILDER: [_DEATH],
	EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH: [_DEATH],
	EntityIds.CL_AIRCRAFT_LIGHT_ANTI_LIGHT: [_DEATH],
	EntityIds.CL_BIO_LIGHT_ANTI_LIGHT: [_DEATH],
	EntityIds.AN_BIO_LIGHT_ANTI_STRUCTURE: [_DEATH],
	EntityIds.LB_AIRCRAFT_MEDIUM_ANTI_BIO: [_DEATH],
	EntityIds.AN_BIO_LIGHT_ANTI_BIO: [_DEATH],
	EntityIds.CL_BIO_LIGHT_BUILDER: [_DEATH],
	EntityIds.CL_MECH_LIGHT_DOMINION_GEN: [_DEATH],
	EntityIds.TC_BIO_LIGHT_BUILDER: [_DEATH],
	EntityIds.NT_BIO_LIGHT_TERRESTRIAL: [_DEATH],
	EntityIds.TC_BIO_LIGHT_ANTI_MECH: [_DEATH],
	EntityIds.AN_BIO_MEDIUM_DOMINION_GEN: [_DEATH],
	EntityIds.CL_MECH_MEDIUM_ANTI_MECH: [_DEATH],
	EntityIds.CL_MECH_STRONG_SUPPORT: [_DEATH],
	EntityIds.AN_AIRCRAFT_MEDIUM_SUPPORT: [_DEATH],
	EntityIds.AN_BIO_STRONG_ANTI_LIGHT: [_DEATH],
	EntityIds.AN_BIO_MEDIUM_ANTI_MECH: [_DEATH],
	EntityIds.AN_MECH_LIGHT_TRANSPORT: [_DEATH],
	EntityIds.AN_MECH_MEDIUM_ANTI_BIO: [_DEATH],
	EntityIds.AN_MECH_MEDIUM_ARTILLERY: [_DEATH],
	EntityIds.CL_AIRCRAFT_MEDIUM_ANTI_MECH: [_DEATH],
	EntityIds.CL_BIO_LIGHT_STEALTH: [_DEATH],
	EntityIds.CL_MECH_MEDIUM_ANTI_LIGHT: [_DEATH],
	EntityIds.AN_BIO_MEDIUM_SUPPORT: [_DEATH],
	# The Drop sanction's off-map transport. It has the bark: being shot down on the
	# run-in is the counterplay to the whole Drop column, and it should be audible.
	EntityIds.NT_AIRCRAFT_MEDIUM_TRANSPORT: [_DEATH],
}
#endregion


#region Public interface
## Plays `entity_id`'s death clip (if it has one) as a fresh, non-positional
## one-shot under `tree`'s current scene, freeing itself when done. An entity with no
## entry plays nothing.
static func play_for(entity_id: StringName, tree: SceneTree) -> void:
	if tree == null or tree.current_scene == null:
		return
	var clips: Array = lines.get(entity_id, [])
	if clips.is_empty():
		return
	var player := AudioStreamPlayer.new()
	player.stream = AU.pick_random(clips, _rng)
	player.finished.connect(player.queue_free)
	tree.current_scene.add_child(player)
	player.play()


## Whether `entity_id` has a death clip — its death-sound slot is filled. Asked by the spec
## importer, never at runtime.
static func has_clip(entity_id: StringName) -> bool:
	return not (lines.get(entity_id, []) as Array).is_empty()
#endregion
