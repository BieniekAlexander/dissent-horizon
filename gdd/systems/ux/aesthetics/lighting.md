---
title: Lighting
type: system-note
---

# Lighting

*Design note for [Dissent Horizon](../../../../CLAUDE.md).* Cheap, standard lighting for an
isometric RTS with a fixed orthographic camera: what is built, the research behind it, and the
options not taken yet. Placeholder values throughout.

## What is built (2026-10-01)

- **A project default Environment** (`resources/environment/default_environment.tres`, set as
  `rendering/environment/defaults/default_environment`): the ambient term for any scene with no
  WorldEnvironment. Ambient comes from a procedural sky used only as a light source — a
  hemispheric ambient (sky-blue from above, warm earth from below) at one sample's cost. Filmic
  tonemapping. The background is a dark neutral, not the project's purple clear colour.
- **A key/fill sun rig** (`scenes/environment/default_lighting.tscn`), added by
  `Scenario._ensure_lighting` to any scenario that authors no `DirectionalLight3D`. The key casts
  shadows and comes from the upper left of the screen at 50° — the illustration convention, so
  shadows fall down-right. The fill is a weak, cool, shadowless light from
  the opposite side so shadowed faces keep their form.
- **Terrain cues that do lighting's job cheaply** — cavity shading from a mipmapped height
  texture, hypsometric tint, height-field normals: [terrain-readability](terrain-readability.md).

**Why it looked broken before.** `skirmish.tscn` and every generated map carried no light and
no WorldEnvironment, and the project set no default Environment — so lit materials got only the
engine's fallback ambient, derived from the purple clear colour. On top of that the grid mesh's
normals pointed down. Maps still carry no lighting by design: lighting belongs to the scenario
([map-generation](../../terrain-and-navigation/map-generation.md) §What a map IS).

## Research: what RTS and isometric games do cheaply

- **A few directional lights plus a flat ambient.** StarCraft II's lighting is a key, a fill and
  a back light, a global ambient colour, per-terrain diffuse/specular multipliers, and tone
  controls; SSAO is an option, not the base ([SC2 editor: Lighting window](https://s2editor-guides.readthedocs.io/New_Tutorials/02_Terrain_Editor/028_Lighting_Window/)).
  The rig here is that, minus the back light.
- **Hemispheric ambient** — blend a sky colour and a ground colour by the normal's up component.
  The standard cheap stand-in for global illumination
  ([discoverthreejs](https://discoverthreejs.com/book/first-steps/ambient-lighting/),
  [XNA tutorial 19](https://digitalerr0r.net/2009/05/09/xna-shader-programming-tutorial-19-hemispheric-ambient-light/)).
- **Precomputed terrain visibility.** Westwood's terrain lighting precomputed per-texel horizon
  angles and sky visibility, so shadows and sky light cost a lookup
  ([Hoffman & Mitchell, GDC 2001](https://renderwonk.com/publications/gdc-2001/hoffmitch.pdf)).
  The cavity term is the cheap runtime cousin: no precompute, one coarse mip lookup.
- **One shadowed directional light, budgeted to the camera.** Godot's PSSM splits are tuned to
  what the camera actually sees; for a fixed top-down camera the shadow distance only has to
  reach the ground, and split blending has a measurable cost
  ([Godot: lights and shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html),
  [blend-splits cost](https://github.com/godotengine/godot-proposals/discussions/9811)).

## Options not taken yet

- TODO: **blob shadows** under units — a decal or soft disc instead of real shadows, the classic
  RTS fallback if a large army's shadow pass costs too much. Not needed until measured.
- TODO: **a rim or back light** for silhouette readability against dark ground — SC2's third
  light, or a fresnel term in the unit shader.
- TODO: **per-map lighting presets** (time of day, biome) once biomes exist
  ([README](README.md) §Art direction).
- TODO: **SSAO** as a Forward+ quality option; the Compatibility renderer has none, so nothing
  may depend on it.
- TODO: whether the purple clear colour in project.godot is meant to show anywhere; the default
  Environment hides it behind a dark background.
