---
kind: Entity
title: Dropship
scene: res://scenes/entities/units/nt/nt_aircraftMedium_transport.tscn
editor_description: Off-map transport flown by the Drop sanction. Cannot be ordered.
flavor:
  description: Off-map transport. Brings a called-in shipment in and flies straight out again.
  verbose: |
    Not a piece anyone builds. It answers a Drop sanction: it crosses the map once with the
    shipment in its hold, releases it under canopy over the target point, and carries on out
    the far side.

    It cannot be selected or ordered — but it can be shot down on the way in, and the
    shipment is lost with it.
defense:
  hp: 250
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: BLAZING, turn_rate: 60, max_acceleration: 3, max_deceleration: -1.5}
aerial: {mode: FLYING}
docking: true
garrison: {capacity: 8, bunker: false, preserve_occupants: false}
---

# Dropship

The aircraft an off-map delivery ability sends. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md)
for the run it flies.

## Not commandable, but attackable
- **Cannot be ordered** — its inherited `Selectable` has `selectable_by_player = false`,
  the same treatment the Recon Drone gets. Godot cannot remove a node an inherited scene
  owns, so the flag is what switches it off; clearing the selection collision layer would
  also make it impossible to right-click, and therefore impossible to attack.
- **Can be shot down** — 250 HP, medium armour, FLYING, so it sits on the anti-air
  targeting layer for the whole run-in. That is the counterplay to the Drop column:
  an opponent with air defence on the approach line takes the shipment out of the sky.

## The hold
`garrison: {capacity: 8, bunker: false, preserve_occupants: false}`.

- **`bunker: false`** — the shipment does not fire out of the aircraft. It is cargo, not a
  gun crew, and a transport whose passengers shot back on the way in would be a gunship.
- **`preserve_occupants: false`** — killing the transport kills what it is carrying. This
  is the whole reward for intercepting it: releasing the shipment from a dying aircraft
  would mean the drop landed anyway, wherever the wreck happened to be, and the interception
  bought nothing. It also avoids evacuating units over ground that may be off the map.
- **Capacity 8** counts OCCUPANCY, not heads. A tier that ships more than the hold takes is
  an authoring error and `EventAirDrop` says so.

## Notes
- No `ui:` key — never built or trained, so it has no command-grid button and its economy
  figures are the importer's placeholder defaults.
- No `weapons:` and `aggro: 0`: it delivers and leaves.
- The model is the Drake's, scaled up — a stand-in until the dropship is drawn.
