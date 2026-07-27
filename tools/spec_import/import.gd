extends SceneTree

## Spec importer CLI: gdd docs -> Godot. One-way (docs govern; the old
## Godot->YAML export direction is retired).
##
## Run:
##   godot --headless -s res://tools/spec_import/import.gd            # full
##   godot --headless -s res://tools/spec_import/import.gd -- --mode=incremental
##   godot --headless -s res://tools/spec_import/import.gd -- --rebake-visuals
##
## `--rebake-visuals` regenerates the selection shapes and HP bars this importer does not
## own — values that predate the generated-visuals pass. It is the migration for a roster
## authored before that pass existed, NOT part of a routine import: the standing rule is
## that a value already in a scene belongs to whoever put it there, and clearing a slot is
## the only thing that normally asks for a fresh bake. A slot the importer HAS baked, and a
## human has edited since, is left alone even under this flag.
##
## Pipeline: scan gdd/**/*.md -> validate EVERYTHING (abort loudly on any
## error, writing nothing) -> regenerate code/data artifacts -> sync scenes
## (Phase 5). Modes differ only in scene-sync collection handling:
##   full        — spec lists are authoritative; scene-only items are deleted
##   incremental — update/create only; scene-only items are preserved
##
## The editor plugin runs this same pipeline in-process (see ImportPipeline).

## LOADED AT RUN TIME, never preloaded. A file-scope preload compiles the pipeline's whole
## dependency graph while this script itself is being loaded, which is BEFORE Godot registers
## the autoloads as globals. The graph reaches game scripts that name an autoload
## (`DamageTable`, `SceneManager` — e.g. EmissionPhase -> ScenarioTriggerManager -> … ->
## Entity), so every one of them failed with "Identifier not found", the failure cascaded up
## to this script, and the importer could not start at all. By _initialize the autoloads are
## registered, so a load() there compiles cleanly.
const IMPORT_PIPELINE_PATH: String = "res://tools/spec_import/import_pipeline.gd"


## Whether _initialize ran to completion. Read by the backstop below — see there.
var _completed: bool = false


func _initialize() -> void:
	var mode: String = "full"
	var rebake_visuals: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg == "--rebake-visuals":
			rebake_visuals = true
	if mode not in ["full", "incremental"]:
		push_error("import: unknown mode '%s' (full|incremental)" % mode)
		quit(1)
		return

	var pipeline: GDScript = load(IMPORT_PIPELINE_PATH)
	var result: Dictionary = pipeline.run(mode, "res://gdd", rebake_visuals)
	for line in result["log"]:
		print(line)
	_completed = true
	quit(1 if not result["ok"] else 0)


## THE IMPORTER MUST NOT BE ABLE TO HANG. When any script in the pipeline fails to COMPILE,
## the loaded pipeline is a bare GDScript with no `run`, and calling it raises a
## runtime error that ABORTS _initialize — so the quit() above is never reached and a
## headless run spins in Godot's main loop forever, looking for all the world like an
## infinite loop in the sync. (It was a one-line indentation slip in scene_sync.gd.)
##
## Returning true ends the loop after a single frame whatever happened above, so a broken
## pipeline fails loudly and exits instead of wedging CI or a terminal.
func _process(_a_delta: float) -> bool:
	if not _completed:
		push_error("import: aborted before completing — fix the parse errors above")
		quit(1)
	return true
