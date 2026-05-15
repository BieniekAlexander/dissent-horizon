# AI Agent Instructions for Dissent Horizon

This repository is a Godot 4.5 game project using GDScript and the GUT test addon.

## What matters most

- The project entrypoint is `project.godot`.
- Game logic is organized under `scripts/`.
- Scenes live under `scenes/`.
- Assets live under `assets/`.
- Tests live under `tests/` and use the `addons/gut/` plugin.
- The repo includes Godot-imported resource metadata (`*.import`) and should not be edited manually.

## Project conventions

- GDScript uses `class_name` and `@export` for exported properties.
- Scene and resource references are typically `res://`-style paths.
- Custom plugin code is under `addons/gut/` and `addons/csv-data-importer/`.

## Preferred workflow for AI tasks

- Use the Godot editor project file as the source of truth.
- For code changes, focus on `scripts/` first, then verify scene/resource integration in `scenes/` and `assets/`.
- For tests, inspect `tests/` and prefer the existing `GUT` conventions. There is no explicit CLI build script in this repository.

## When helping with issues

- If a change touches gameplay or entity behavior, look for related classes in `scripts/entities/`, `scripts/interface/`, and `scripts/maps/`.
- If a change touches UI or input, inspect `scripts/interface/` and `project.godot` input actions.
- If a change touches world layout or scenarios, inspect `scenes/scenarios/`.

## Notes for maintainers

- `README.md` currently has only a placeholder introduction.
- The Godot engine configuration is in `project.godot` and should be considered when updating input mappings or autoloads.
