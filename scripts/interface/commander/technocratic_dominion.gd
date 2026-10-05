class_name TechnocraticDominion
extends DominionRoute

## The Technocratic dominion route: Labs (tc_dominionGen), each built on an extraction site in
## place of an Extractor and paying a flat rate through its own DominionGenerator. Why it works
## this way: gdd/systems/macroeconomics/pacing/sanction-calibration.md §Fungibility.
##
## What makes it its own route rather than the base: a Lab's income does not depend on where it
## stands or on anything feeding it, so EVERY Lab adds a full Lab's income — unlike the base
## route's Compound, where one is as good as two because the prisoners are the limit. Where a
## Lab may stand is the piece's own business (it overlays a site, EnergyExtractor's placement
## rule), so the bot reads that off the piece, not off this route.


#region Public API
## Every Lab pays the same flat rate, so another one always adds income — as long as there is a
## free site to put it on, which the bot finds the way it finds one for an Extractor.
func another_source_adds_income() -> bool:
	return true
#endregion
