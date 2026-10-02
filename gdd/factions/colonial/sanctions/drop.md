---
kind: AbilityDefinition
title: Drop
ui: {grid: [0, 1], factions: [colonial]}
hud_button: true
column: 0
levels:
  - title: Drop 1
    tier: 1
    cost: 500
    cooldown: 60
    description: Flies 3 × {{ cl_bioLight_antiLight }} in and drops them on the target point.
    verbose: |
      The cheapest way to put bodies somewhere they are not expected — reinforcing a
      collapsing defence, or opening a second front behind the enemy line.

      It is a FLIGHT, not a spawn. A transport crosses the map from your side of the
      board, releases the squad under canopy over the point you clicked, and flies on
      out the far side. Shoot the transport down on the way in and the shipment goes
      with it.
    payloads:
      - {piece: cl_bioLight_antiLight, count: 3}
  - title: Drop 2
    tier: 2
    cost: 1200
    cooldown: 60
    description: Flies in a shipment of your choosing — 5 × {{ cl_bioLight_antiLight }}, or a {{ cl_mechMedium_antiLight }}.
    verbose: |
      The level that turns Drop into a CHOICE. Pressing it opens a cargo menu the way Build
      opens a structure list; pick the shipment, then click where it goes.

      It replaces Drop 1 outright rather than joining it — a column is one sanction you
      improve — and improving it here means both a bigger squad than Drop 1 flew and a
      vehicle it could not carry at all.
    payloads:
      - {piece: cl_bioLight_antiLight, count: 5}
      - {piece: cl_mechMedium_antiLight, count: 1}
  - title: Drop 3
    tier: 3
    cost: 2000
    cooldown: 60
    description: Flies in a shipment of your choosing, up to a {{ cl_mechMedium_antiMech }}.
    verbose: |
      The heaviest shipment the Colonials can call in, and the reason to take the Drop
      column to its end. Every option Drop 2 offered arrives in greater numbers, and the
      {{ cl_mechMedium_antiMech }} is added to the menu.
    payloads:
      - {piece: cl_bioLight_antiLight, count: 7}
      - {piece: cl_mechMedium_antiLight, count: 2}
      - {piece: cl_mechMedium_antiMech, count: 1}
---
# Drop

## Mechanic
An **off-map ability**, and the elaborate one: nothing appears at the target point. A
[[nt_aircraftMedium_transport]] enters from beyond the play-area perimeter nearest the CASTER with the
shipment in its hold, flies to the target, tips the cargo out under canopy, and continues
along the same line until it is off the map again, where it despawns. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md).

Three consequences the old instant spawn did not have:

- **The drop takes time.** The transport has to fly in, so the reinforcement lands seconds
  after the click rather than on it.
- **The drop can be intercepted.** The transport is a FLYING piece on the anti-air
  targeting layer for the whole run-in, and its hold does not `preserve_occupants`: killing
  it kills the shipment.
- **Where you cast from matters.** The run-in comes over the edge nearest the caster, so a
  forward Operations Center and a home one send the transport along different lines.

The units fall under a canopy (see `Movement.begin_parachute_descent`) and take no orders
until they touch down — orders GIVEN to them in the air are kept and acted on the moment
they land.

## Progression
**A level is a MENU, not a single cargo.** Drop 1 flies a squad and nothing else; Drop 2
offers a bigger squad or a light vehicle; Drop 3 adds a medium one and raises the counts
again. Pressing the button opens that menu — the same two-step arming Build uses — and the
pick is what the transport carries.

Supersession is what makes "upgrading" free: the level that replaces its parent carries the
same pieces at higher counts, so a column is still one sanction the player improves rather
than a growing collection of buttons. All three levels are one `EventAirDrop`; the cargo is
`payloads:` data, resolved at cast time, rather than a different scene per tier.
