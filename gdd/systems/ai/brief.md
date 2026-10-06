---
title: The bot brief
type: system-note
---

# The bot brief

*Design note for [Dissent Horizon](../../../CLAUDE.md).* Alex's original brief for the CPU
commander, moved here verbatim from the "CPU Bot Behavior Work" task when the task file became
a log (2026-10-06). It is the standing goal [bot-roadmap.md](bot-roadmap.md) plans against;
what is built is [bot-architecture.md](bot-architecture.md). The work item is `gdd/tasks.md`
T-001.

---

I've made significant progress on the implementation of the game since starting the Bot Behavior modules. Now, I would say that the set of possible actions from a player will not change that much, so I'd like to revisit, fix, and improve how it works.
## High Level Goals
- Difficulty: Support various difficulty levels. The current set of difficulties in `player_slot.gd` is fine. The goals are:
	- PASSIVE - should be minimally active, and should never attack the player
	- IMPOSSIBLE - ideally, it works so effectively that a human player will never realistically beat it. With that in mind, it can have highly effective economic planning and execution, frame-perfect micromanagement, etc. The only caution I have is that, ideally, the bot shouldn't play so defensively that two IMPOSSIBLE bots end up in stalemates.
	- EASY, MEDIUM, and HARD can be progressions up to the IMPOSSIBLE difficulty level, with built-in handicaps in its decision-making against a hard opponent.
- Representation of behavior: A lot of stuff is built out already. I was loosely inspired by [this discussion](https://www.youtube.com/watch?v=Bo0X6XMsg6M) - please go through its transcript as research, and give me a summary of how the described framework fits or differs from what's built in this project right now
- Generalization - of course, this game is still in development, so things are subject to change. Many systems are crystallized though, so its in a state where it should be ready to built bot behaviors that can be used to see matches to completion. Some notes on my goals for generalization:
	- Most economic decision-making can be framed as short-term long-term trade-offs of collecting the primary resource (energy). Against a completely passive opponent, it would be most effective to just scour the map for primary resource deposits, take them, and start military production when all on-map resources have been secured. This will be infeasible if the opponent attacks, so the bot must have some sort of habit of scouting the opponent's capabilities, preemptively making military and technology to prepare itself to defend, and sometimes make the decision to attack the opponent
	- The unit counter system is pretty well defined by now. The bot should be able to derive decisions around unit combat effectiveness against other units based on the stats in the game.
	- Some mechanics in the game will probably just be too tricky to generalize for, and I'm okay with having to revisit the bot implementation and potentially hard-code some behaviors, though I think the hardcoding should just pertain to the most minute details of the gameplay decisions. For example, dominion is one of the game's core resources, and the bots should have some sort of model for wanting to acquire more dominion. However, the method of dominion gathering will vary a lot, so I'm okay with changes being needed whenever I introduce a new dominion generation method. The game currently has the following factions, with the mentioned methods:
		- Colonial - capture light infantry units from the map (enemy combatants are neutral units), and bring them to a structure so that they generate dominion
		- Anarchical - build Warlord units, and colocate them with friendly infantry units to generate dominion
	- Some of the properties of this game are very uncalibrated, and I do have to fix a lot of these things, but the decision making of the bot should still be able to correctly make decisions based on the balance of things as configured. For example, Colonial players will start with a Stock Truck, and I intend for it to be an appropriate scouting tool. However, given that the bot is wanting to scout (and it should generally always be doing it with at least one unit, which I think is already implemented), it could be that a different unit makes for a better scout (with more movement speed or better vision range). As such, the bot should use that other hypothetical unit for scouting, and it's on me to reconfigure the game unit's properties if I want a different unit to be what the bot opts for.
## Modeling
- If any particular things are hard to generalize for, I'd like to provide some signal that the bot can use to understand how to use them, rather than hard-coding the bot's use of them. But, surely some details will be so difficult to model to this extent that I'm okay with things being hardcoded and determined with heuristics. Some examples:
	- determining "what makes a good scouting unit" can involve the questions:
		- how much does this unit cost? How long does it take to make?
		- how fast is the unit? What is the unit's vision range?
		- What other responsibilities does this unit have? Are those responsibilities currently applicable to this unit?
			- For example, the stock truck is a good starting unit because it doesn't have any sort of responsibilities at the start of the game. Effectively, its only responsibility is to crush infantry units and bring them back to a Compound for dominion generation. So, the decisions regarding the Stock Truck's are ultimately (in descending priority):
				- If I'm in danger, run away
				- if I can run over nearby enemy units, do so
				- If I'm full of inventory, go back and drop it off
				- otherwise, scout around the map
	- On abilities:
		- I think most abilities (other than building) are best used as often as possible, though there are some tradeoffs to them:
			- If an ability has economic implications (Free resources or units), it should be definitely used all the time
			- If a unit has offensive application, it's probably good to use often, but such abilities are probably also good to save for more impactful moments, or particularly defensive moments
		- For example, the "Dignify" ability is effectively an economic ability (you can convert a cheaper unit into a more expensive unit), but  it can be used offensively and defensively (a warlord might be more appropriate in a given battle)
## Training
- I'm interested in taking an adversarial reinforcement learning approach to test these models and try to optimize them.
	- Some things to explore:
		- As faction X, if I'm playing against faction Y, how many of each production structure should I plan to use?
		- How should I be placing my structures?
		- What heuristics should I be using to aim my abilities?
	- Some thoughts on searching state spaces for bot parameters:
		- When exploring optimization of a particular behavior, it's probably best to constrain parameters for other behaviors so that they're equal. For example, if I'm looking to optimize parameterization of "how much of each production structure should my base have", best to constrain all other behavior parameters (how many units should be scouting, how greedily should I be getting more energy, etc.).
		- For the sake of speeding up such parameter optimizations, it would also make sense to have a harness of test scenarios which could be used to focus on the relevant thing being optimized:
			- Suppose I want to test what units I might want to produce (set X), knowing that my opponent will have a given set of units (set Y). To model and test the validity of a given decision rule, I can just make a scenario that will auto create units set X and Y, have them fight eachother, and see how they did.
			- Suppose I want to test how many units I should be using to scout a map. It doesn't suffice to test this by setting parameter `n`, creating a map to be explored, and seeing how many units `n` would best scout the map, because `n=infinity` is obviously ideal, and the correct number of scouting units is moreso a question of trade-off: how many units can I use to scout so as to see more of the map, and minimize the negative impact of having my scouts be isolated and away from their other responsibilities?
		- I'd be interested in having a harness for using human players as the testing opponents of the bots, though I imagine it would be infeasible to try to model the apparent decision-making of the human player to understand what parameterizations of the bot were ineffective
