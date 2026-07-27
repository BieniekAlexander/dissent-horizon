---
title: Pacing — the economic shape of a match
type: design-note
---

Planning research for the topic of game pacing. Move this into the `design-framework` section. The economic considerations heavily confound the pacing that results in matches. High-level pacing goals:
- Increasing volatility over time (G3)
	- Players should be incentivized to engage with the opponent as soon as possible:
		- The dominion resource currently suits this goal, as players can seek to acquire the resource basically immediately, and the value of the resource generally increases over time. TODO maybe perform some analysis on the relative value of the resource over time, where the goal is that dominion can provide small benefits in the near term, and will ultimately unlock game-swinging abilities in the long term.
		- I'm still working on how to best approach this with the primary resource.
	- Note: I think G7 is a bit redundant to G3, where the size of a force will increase with time, but later-game tools help to mitigate the reward of better macro-economic plays
	- G8 is also a bit redundant to G3, in a subtle way:
		- a player's "health" can be thought of as the abstract resource governing the player's ability to stay in the game, and different game pieces have varying individual levels of "health"
			- structures have more health, but they're very inflexible, and act more as investments
			- units generally feature less health, but can be used non-defensively, and are basically necessary to interact with the opponent
		- the armor system is designed around this:
			- early game units are generally inert against structures, and some early units might be able to chip away at the opponent's infrastructure to impact the opponent, but it takes a large investment for this to be a realistic threat
			- increasing tech tiers are meant to unlock units with additional damage types, and so such investments are generally gates to the volatility of the late stages of the game
				- Note that SC2 is a notable exception to this, where generally every unit in the game can be used to threaten the opponent's economy (players can even perform worker rushes to destroy the opponent's economy and achieve an early win); for this reason, the primary resource in this project will generally be inert or very resistant to attacks of early units
			- TODO I still just need to calibrate the HP and armor classes of structures for this consideration:
				- should all structures have STRONG armor, or should that be reserved for specific structures? If so, which?
				- I would like a faction's command center to be what a player needs to stay in a match, so that matches can be ended in later stages with risky, highly volatile plays. A player can build more command centers to mitigate this, but:
					- how much should command centers cost?
					- What other purposes might command centers have? Right now, they're planned to perform the low-level faction sanction abilities, and I think this is really well calibrated as a light marginal benefit to additional command centers
					- how much health should they have?
					- how big should they be?
			- In a similar note, just how effective should weapons and abilities be against structures? late-game weapons and structures are definitely designed to be stronger against structures, but the power needs to be carefully calibrated according to costs, cooldown times, etc.
- Positioning should be constantly considered and fought over (G4)
	- In a fighting game context, positioning influences how many options are available to a player. In general, characters will struggle more as they get closer to their "corner", and characters generally prefer to operate from their opponent at a given distance, which may differ from the preferred distance of their opponent (Zangief prefers to stay close to the opponent, for example).
	- In an RTS context, a player generally wants to secure positions in order to support their production capabilities. The considerations are as follows:
		- Energy deposits are in specific locations, and players will generally seek to build structures to collect those resources, and generally seek to place actors near those locations to defend them
		- Factions will also have faction-specific means of collecting dominion, leading to some unique defensive considerations per faction:
			- Colonials will need access to the neutral shelter features, and as currently designed, there's a positional tradeoff in where they'll build gatherer dropoff points
			- Libertarians will have a structure that they need to sparsely spread over the map, which will provide a unique challenge in the risk-reward of investing in, positioning, and defending the structures
		- Players have a myriad of pieces that they can purchase, with unique tradeoffs in reach, application, and mobility:
			- static defenses are commonly available to a player very early, allowing the player to invest in defending a region; the tradeoff is that these things can't move, so they generally only defend investments in a localized area
				- many static defense are designed to scale very poorly over the course of the game, though this is achieved in quite different ways:
					- Starcraft 2 static defenses scale poorly with respect to their effective range, which is appropriate according to the relative sizes of choke points, but means that they are less cost effective as armies get larger and players have more places to defend
					- Age of Empires games feature defenses that are weak, but they're generally very resistant to low-tech units and large numbers of units; they provide a lot of positional protection, but they're generally deprecated when the opponent has the technology to deal with them
					- Command and Conquer static defenses operate very similarly to Age of Empires, as they're cost effective, but they're generally deprecated by artillery and super weapons
			- Games have systems designed to constrain the ability of a player to place structures for positional advantages:
				- In Starcraft 2, static defense isn't available immediately to the player in the tech tree
				- In other Command and Conquer games, players can generally only spread their building construction 
				- in this project, the stagger mechanic is partially designed to mitigate this, allowing a defender to interrupt building construction with a very small presence, so I'm not as concerned about putting defensive structures slightly down the tech path
				- similarly, some other games constrain building 
			- Beyond static defensive structures, some games also feature dynamics that incentivize securing positions with other structures to gain an advantage
				- Some games feature a teleportation mechanics, providing a lot of army mobility to a player than can create the requisite infrastructure:
					- SC2 Zerg has a nydus network that basically teleports units, but it requires a lot of technology and investment, so I believe it's not that commonly used; the Zerg army also features other mechanics that pertain to army mobility, and units seem to generally move across the map very quickly, so it generally doesn't seem that useful
					- SC2 protoss features a mechanic that allows players to construct units at any point on the map, but it requires a small positional investment, and only some units can be built with it
					- Zero Hour GLA has structures that allow units to essentially teleport across the map, and it's quite cheap to set up, but it's appropriate because it's mechanically elastic and it makes up for some mobility shortcomings in the GLA army
				- some unit production structures may be placed aggressively to ignore the defender's advantage conferred by distance between starting positions, and the implications of this are heavily constrained by resource and time investments:
					- In Zero Hour, builders tend to be slow and defenseless, but some faction-specific details still allow for abuse of structure positioning:
						- USA players can use chinooks to fly builder units across the map fairly early on; it's generally a significant investment to do this, but in the USA mirror matchup, it seems hard to address, so the mirror match is generally highly volatile because of this dynamic
						- GLA workers are very cheap, so it's a very cheap investment to send a worker across the map and try to position a tunnel in an advantageous position
					- In SC2, players will sometimes aggressively position unit production structures, but it requires a high level of investment, and it's not available to all factions
- Tuning of short-term and long-term investments (G1)
	- Dominion, as a resource, is designed to not be mutually exclusive from energy, so as to prevent a tradeoff in excessive short-term and long-term value tradeoffs. The energy commitment in dominion collection is meant to be low, and the ability to collect is more determined by the opponent's attempts at preventing the dominion generation
		- This was largely inspired by the super meter resource in fighting games; players basically collect the resource "just by playing the game", but some deliberate actions provide the player with more advantage in generating the resource:
			- In Street Fighter 3: Third Strike, the player can generate the resource by whiffing attacks, acting as a very low risk opportunity to generate the resource, but allowing your opponent to seek very slight advantages in response, providing moment-to-moment interaction
			- In guilty gear, you receive the resource when you advance towards your opponent, incentivizing aggression
		- In this game, the dominion generation methods need to be implemented to reflect the moment-to-moment skirmishing over the resource; I think Anarchical and Libertarian generation methods are trivially well suited to this, but I need the Colonial method to reflect this
	- The primary resource also needs to be tuned to interact interestingly with short-term and long-term investments:
		- What will the relative costs be surrounding production structures, units, and resource-generating structures?
			- In Zero hour:
				- all factions have fast, exhaustible resource generation locations ("primary income", acting as a short term investment) and slow, high investment, infinite, location-independent resource generation actors ("secondary income", acting an an optional long-term investment)
				- Saturation of short-term resource collection spots generally costs between $2100 and $3200, players start near one or two such spots, and a handful of other spots exist on the map
				- Long-term generation methods generally require a lot of investment and allow for the game to continue forever, and I'm not sure how feasible I want that to be in my game; I believe it's fun for some players, but it rewards extremely defensive play, so I'm inclined to tune it so that it's feasible for casual matches but cost-prohibitive for serious matches
				- Oil derricks are also present in the game as inexhaustible secondary income, though they generally require far less investment and generate relatively slowly; such a system is not planned for my game
				- Interesting, the long-term generation methods for some factions have additional applications, which provides significant value for an initial investment in the long-term generation method, and I think that's really attractive from the game design standpoint
		- Across many games, it appears that a unit production structure is worth about two or three of the units which it's able to produce; I'm curious about how to properly calibrate this investment tradeoff
			- some exceptions:
				- airfields have a capacity on how many units it can produce, and they generally cost less than their produced units
				- A game's starting structure can sometimes cost far more than the units it produces, but the implications of this vary a lot:
					- In SC2, the starting structure is an economic structure, and additional ones must be built to scale economically
					- In Zero Hour, there's generally no need to make additional starting structures, and some players even sell their starting structure for a slight resource advantage
		- How much does a player need to invest in higher technology? How important will the higher tech tiers be?
	- How is resource generation calibrated against short-term and long-term investment times?
		- Generally, the "term" of the investment reflects how soon the player will see a payoff, and:
			- units and static defenses are shorter-term investments
			- production structures and resource generation seem to be medium term investments
			- dominion generation and technology seem to be long-term investments
		- If short-term investments are too effective, the game probably results in very quick finishes
		- short-term investments should still provide threats that the opponent has to deal with, but ideally short-term losses still have room for recovery
		- The overhead investments in more resource generation and technology generally create windows in which the player can attack their opponent before gains are realized; I think this is a natural consequence of varying investment strategies, but this game is currently planned to use random map generation so as to prevent highly optimized strategies regarding production times and "timing attacks"
			- In the micro-meso-macro framework of game design, I want to mitigate macro-level solving of games; TODO please add some notes in the `design-framework` document regarding this framework: I want this project to reward Micro and Meso execution, and provide relatively little room for macro optimization, and I expect that this can heavily influence how numbers are tuned; Note that I think the design-framework goals could be reorganized a bit according to this framework, see later section in this document
	- On selling - I don't want my game to feature selling, as I believe it makes the economy complicated, it provides too much mechanical elasticity, and it's too easy to walk back on investments; Additionally, deleting structures might too heavily impact some game dynamics (e.g. veterancy experience acquisition, and the planned Marxist dominion generation method)
- Multi-purpose investments (G6) - keeps a very broad decision space, provides for a lot of player expression, and mitigates pareto-optimality of decisions
- Some open questions for my game:
	- Static defense considerations: (answered 2026-09-28 in [static-defence](static-defence.md))
		- Specificity:
			- How many types of threats will a given static defense be able to address?
		- Cost effectiveness:
			- how much reach will the static defenses have? Given that map layouts will be generally open, the static defenses will probably need to have a relatively large effective range
			- static defenses will likely obstruct each other from attacking, especially depending on how they're sized, so static options will still generally not scale as well as unit investments (even if their effective range is not that small)
		- Mechanical elasticity:
			- How effective are the defenses without mechanical attention, and how far does additional micromanagement go?
				- I think USA overtuned the interactions against infantry, where static defenses are very ineffective against infantry, and pathfinders are gated behind a generals promotion which means that they aren't available for much of the beginning of the match, but they absolutely trump infantry once they're available; relatedly, I think the vulnerability to infantry creates the highly volatile early game of USA mirror matches
				- Superweapon General has EMP patriots, and they're generally effective against enemy vehicles as a baseline, but their mechanical elasticity is enormous
		- counterplay:
			- What will the opponent be able to do to address the defensive options? How much short-term and long-term investment would it require? In this regard, I prefer the approach where long-term investments can trump static defenses (e.g. high tech level units and sanctions)
			- How do you prevent the static defenses from being trumped by a given early option? In Zero Hour, each faction features two static defense options with a pretty high degree of specificity, but they're still quite resilient against their respective non-preferred option, so they're generally a decent early game investment; for example, gatling cannons are not very effective against tanks, but they may be able to take on just one tank
			- static defenses involve a local positional investment, and it's generally a sound response for an opponent to respond by investing in longer term things as a response
		-  How are sizes calibrated? All of the following things in the game fall into size ranges, and they all result in particular interactions:
			- structure sizes (and how much they vary)
			- size of buildable areas
			- unit sizes, and their respective speeds
			- Starting position distances (and degree of variance)
			- Area-of-effect sizes
			- vision ranges and detection ranges

## Design Goal Revision

| Goal  | Subgoal                                                                                                                                                                                                                                                                    | Notes                                                                                                                                                                    |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Micro | Micromanagement provides more effectiveness of units, with carefully tuned effectiveness elasticity                                                                                                                                                                        |                                                                                                                                                                          |
|       | Micromanagement is more relevant the parts of the game that more directly interface with the enemy; Micromanagement influencing mechanics not directly influencing opponents is an anti-pattern                                                                            | Warcraft 3 creep camp antipattern                                                                                                                                        |
|       | Elasticity of micromanagement should be low at the start of the game, and increase over the course of the game                                                                                                                                                             | Later-game sanctions unlock ordnances that are more offensive                                                                                                            |
|       | Micro dynamics should evolve the play space and incentivize back-and-forth interactions ons ons ons                                                                                                                                                                        | TODO I want to identify or create generic mechanics and faction-level mechanics that impact this; Walker husks in Kane's Wrath are a wonderful example of this; vetwranc |
| Meso  | Design against pareto-optimal decisions; RTS games do have enormous decision spaces that ultimately reduce down to a more narrow set of options that are worth pursuing, but the randomness and interaction nuance should ideally mitigate dominance of specific solutions | randomness in the distance and position of resource deposits should add uncertainty to the otherwise straightforward macro decisions                                     |
|       | Uncertainty at the micro level should heavily influence the macro decisions of players; if a player massively succeeds in an engagement, it should have strong implications on the way the rest of the match plays out                                                     | A well placed airstrike may wipe out an army, but the airstrike may have delay, making it tricky to land                                                                 |
|       | There should be many generic and faction-specific mechanics that create uncertainty                                                                                                                                                                                        | e.g. stealth units, fog of war, ambiguous properties of units (does this bunker have units in it?)                                                                       |
| Macro | Macroeconomic decisions should be simple, without much granularity                                                                                                                                                                                                         | Reflect Warcraft 3 over Starcraft, in a sense                                                                                                                            |
|       | Macro decisions should shy away from mutually exclusive outcomes                                                                                                                                                                                                           | e.g. do I spend resources on more military or economy?                                                                                                                   |
|       | Some mechanics should buffer the snowball effects of economic leads                                                                                                                                                                                                        | I never want to feel like I lost the match 5 minutes ago                                                                                                                 |
