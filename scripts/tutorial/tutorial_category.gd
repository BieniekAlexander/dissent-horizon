@tool
class_name TutorialCategory
extends Node

## One topic of the How to Play library: a heading and its notes, in reading order. A child of the
## TutorialLibrary scene.

## The heading the player reads.
@export var title: String = ""
## DialogPage scenes, in reading order.
@export var notes: Array[PackedScene] = []


## The notes with empty inspector rows dropped.
func valid_notes() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for note: PackedScene in notes:
		if note != null:
			out.append(note)
	return out
