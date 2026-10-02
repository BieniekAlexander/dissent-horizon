extends GutTest

## The cursor diagnostic (`CursorDebugReadout`) — a temporary instrument, tested only so far
## as "it does not crash and it reports the pairs it promises". Delete alongside it.
##
## It earns a test at all because it is the one thing standing between a bug report in prose
## and a bug report in numbers: the cursor cannot be seen from a headless run or from
## `--write-movie`, so if this silently reported nothing, the next round of cursor work would
## be guesswork again.


func test_the_readout_names_every_pair_it_promises() -> void:
	var text: String = CursorDebugReadout.readout(get_viewport(), get_window())
	for label: String in ["viewport", "window", "stretch", "screen"]:
		assert_true(text.contains(label), "the readout carries the %s line" % label)


func test_the_readout_survives_having_no_surfaces() -> void:
	# It runs from _process on a node that can outlive its window during teardown.
	var text: String = CursorDebugReadout.readout(null, null)
	assert_true(text.contains("window"), "what can still be asked is still reported")
	assert_false(text.contains("viewport size"), "and what cannot is simply absent")
