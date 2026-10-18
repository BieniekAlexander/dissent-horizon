# Challenge 3 — Requisition

Status: draft. Drills requisition: queuing a purchase or ability the player can't afford yet, or whose prerequisite is still being built, so it starts the moment it can.

## Skill

Holding the additive modifier on a purchase or ability queues it rather than refusing it. It's the same key that appends an order or adds to a selection, and it carries the same meaning: "address this when you're free to". The drills cover:

- **Funding:** a queued purchase waits for energy. Purchases commit in the order the player made them, across every queue.
- **Prerequisites:** a building can be ordered while its prerequisite is still going up, as long as that prerequisite is already queued. The builder walks to the site and waits.
- **Charges:** an ability with no charge left can be queued for when it recharges.
- **Reading the queue:** a blocked entry names what it's waiting on (energy or a free producer), and the energy bar shows what's already committed as a pending slice ([economy-bars](../../systems/ux/ui/economy-bars.md)). Each blocker has a different remedy.

Rules: [requisition-as-a-modifier](../../systems/macroeconomics/requisition-as-a-modifier.md), [production-and-economy](../../systems/macroeconomics/production-and-economy.md), [cooldowns-and-preconditions](../../systems/commands/cooldowns-and-preconditions.md).

## Prerequisites

Prologue mission 3 (structure and unit production, the tech tree).

## Drills

- **Without requisition:** a trickle of income and a long build list. Clicking only when each item is affordable works, but it's slow and needs constant attention.
- **With requisition:** the same list queued up front. The player is free to do something else while it fills.
- **A tech chain:**
  - Queue a full prerequisite chain at once (e.g. Safehouse → Chop Shop → Stockpile) and watch each builder wait at its site.
  - Cancel an early link to see what happens to the ones behind it.
- **Commitment order:** queue an expensive structure, then a cheap unit. The unit waits for the structure's turn even though its own price is affordable, which teaches the player to order the queue deliberately.
- **Combined test:** hold off a timed attack while teching up on a tight income. Success needs the right counters queued ahead of the money arriving.

## Pass and score

- **Pass:** survive the combined test's attack.
- **Score:** time to finish the tech chain, and the energy left idle over the challenge (less idle energy is better).

## Pieces

- Anarchist builders and the Tier 0–1 structures
- A scripted income
- A Colonial attack wave

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- **Cancelling.** The queue has a dependency edge list, but nothing uses it yet. Until it does, what should the "cancel an early link" drill show?
