class_name ShelterStructure
extends Entity

## A neutral, terrain-grid-occupying world structure that factions interact with
## (see [Shelter] / [Interactor] / [Interaction] / [Interact]). Like [Deposit], it
## derives from Entity rather than Commandable: it takes no commands, trains
## nothing, and isn't attackable. The Shelter component child holds the
## availability countdown that gates interactions; LIBERATE resets it on
## completion.
