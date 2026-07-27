RTS has a predictability problem
It actually goes back to something I
hear from the Matrix. They're machines
and they have limits and humans can
break the rules or you can always
exploit the machines. RTS AI has a
problem. It gets pattern matched and
exploited the moment you learn its
script.
All you have to do is build a supply
depot. They just can't get through.
This is Marvin Gal and he's been making
games for over 20 years jumping from
console to mobile to PC. It just makes
it not fun once you understand how to do
it.
I counter it and it is failing, but it
it doesn't react. It doesn't go.
Now, for the last 5 years, he's been the
game director for Zero Space, a highly
anticipated new RTS and safe to say a
spiritual successor to Starcraft 2. He
wrote roughly 80% of the game's AI from
scratch with one goal, pure
predictability problem. But I think like
seeing the AI retreat is very human like
it's it's actually goes back to um you
The Failed Experiments
know something I hear from the Matrix is
like you know they're machines and they
have limits and humans can break the
rules but [music] they can be a lot more
creative with with how how they approach
things so that you can always exploit
the machines. And I think it's not from
zerospace itself that I saw this. It's
more from actually playing bots against
Starcraft stuff, right? Even any other
um other types of games basically like
Starcraft, [music]
you have lots of exploits against insane
AI and that's why you sometimes play
against insane AI is they're definitely
stronger than you. They have more
resources than you, [music] but yet you
can still beat them, right?
Was there an AI was there an experience
with an AI you watched with whether or
worked on that really in your mind said
this is the architecture that would
solve this problem? And what was that?
Like what was that moment?
I think like when you when you're
looking at um some of what Starcraft 2
tried to do, which you know I think a
lot of other games didn't even do this
was they actually did build orders,
right? They're like this is going to be
Marauder Marine rush. I'm going to rush
you with Marine. Uh and it's it's it's
random I think based on what it decides
to [music] do um at any point in time,
but it'll it'll stick to that build
order. It'll stick to that time. But
when it does that and it I think that
the moment is when it does that and I I
realize what it's doing. I counter it
and it's and it is failing but it it
will hard commit still to what it's
doing. Um it doesn't it [music] doesn't
react. It doesn't go, hey, he's
countering me. I should probably not do
this. Um it doesn't retreat, right? It's
like like a player would would would see
would see my uh base. Oh, siege tanks.
Marine Marauder might not be the best
way to approach this or something,
right? Um, but those are going to go in,
right?
What was your mindset when it came to
thinking about how you were going to
approach that with zero space?
Yeah, I think I think basically
flexibility, right? Um, because if you
start going down the route of scripting
something, uh, and let's say the meta
changes slightly, we change the game a
little bit, that's a lot of maintenance
you're going to have to do. So, so it's
very rigid and it it just breaks down
really quickly and easily as once new
balance changes come out. So, you really
want flexibility to make your AI
consistent enough. Um, and so it's
really about I don't want I don't want
to babysit the AI uh the code.
So, if scripting is the trap, the
obvious move might seem simple. Just
build one AI smart enough to figure out
the whole thing on its own. Funny
because I did I did try to stick that in
about two years ago. I used Chat GP3 3.5
when it came out. Um I just stuck that
in just to see if it worked. It was
really bad at it.
Basically, it would just forget
everything I'm telling it. And even when
I'm telling something, if I tell too
much, um it it would like I would tell
it like, "Hey, you are already on like
this tech level, like tech level four."
And then it starts building like uh
supply depot again when it doesn't need
it or something. It's just it's really
dumb.
Yeah. And I was I was researching you
know neural networks before LLMs got
popular. And I think like one of the
things I was doing back in the day was
uh there's this thing there's a paper on
sparse uh neural networks um such that
you can run it on CPUs uh with instead
of GPUs. So I got something like that
actually working uh in C++ for a while
and just like oh maybe I'll it's on the
CPU it's not on the GPU right like maybe
I could use this later but I I never I
wasn't I wasn't it's not able I just
never had the time to to completely
utilize that
with that approach then how did you go
about solving that for zero space
because now I know that's what you want
but and like you said it's a very hard
problem to solve right
you're making your life harder for
yourself you're basically fusing those
two things together and you could
separate that. So you parse first,
distill that information. So the big
thing is just separating as many pieces
as possible and letting them talk to
each other through more coordinated uh
uh kind of API.
The 3-Layer Solution
Instead of cramming everything into one
massive brain, Marv broke it apart. A
vision layer to read the map
is where we clust we figure out all the
clusters of units. So clustering
understanding clusters where the enemies
are understanding enemy strength when
they see a cluster how do the AI see um
the map [music] and get funneling that
information into a way that is easy to
parse a strategy layer to pick the plan.
We have a macro strategy layer which
takes this general sense of like where I
am in the text tree, what my opponents
have been doing, a historical
categorization of like uh you know
what's been happening. Am I on the
[music]
do I think I'm on a on a losing uh like
am should I be defending now? Should I
should I be pushing now? Right. A micro
layer to pull the triggers. for every
ability that we have um and for every
unit that we have, we have a we have a
drop down of how the AI is supposed to
effectively utilize that. And so the
micro layer utilizes those abilities
that way and the mastermind on top to
keep them in sync.
And ultimately when you look at
Starcraft, right, um up to GM, it
doesn't matter how you micro. It really
doesn't. You just a move everything. You
could you could get up to GM with just
being efficient on your macro, being
clean on your builds, not wasting time,
right? And making the right strategic
decisions. And macro [music] is
basically the thing that we need to
solve first for our AI to make it at
that level where it could play. And the
micro really doesn't matter that much
like um for the AI until the macro
reaches that level.
But are you giving it the same map and
vision as the player or Okay. Yeah.
Yeah. So, so, so basically the AI has to
process that same like who what units
are visible, right? We're not going off
of So, so we're not going off video.
We're not going off of pixels data,
right?
We're just going off the fact that hey,
this this unit came in vision and we can
still think about it like like a human
would. Um, a human would do the same
thing with the information they're
given, right?
And do you use any kind of like uh heat
map or anything for a to to transition
understand the groups and and the
intensity of danger that comes with that
group because you
versus like say individuals and and
counting.
Yeah. Yeah. Yeah. So the clustering uh
accounts for weapon strength, accounts
for movement speed overall. Um kind of
kind of see where things can end up and
and their general direction of movement.
um so they can yeah basically you have a
good understanding of what where things
could end up and uh also the threat
level of all these things um you know
various various things like that yeah
why did you decide to go that route
because I think it it's really how how
we we organize the data right I think I
think if you want to make an AI that is
uh good at playing RTS you kind of have
to understand RTS game theory. Um and so
you need to understand like RTS is about
snowballing but also like snowballing
comes in many factors in RTS right
expansion is a form of snowballing. So
um you got to expand at some point and
when is that decision point to expand h
when is it the best time to expand right
uh all those all those factors uh come
into making the AI has to know all this
stuff that's like the basic RTS um
principles um where you got to be able
to be tight on your econ uh economy as
well as your build orders. But if you
don't understand that you're not going
to make an AI that can effectively play
against a human, right? So humans would
organize the data, I think, at least I
would the same way uh in my own head as
I'm playing the game, right? It's like,
okay, I I I think there's a big threat
here and then over here there's like a
speedy little threat on the side. I I
got to think about I I want that
information first to even be able to
process it. And if I don't have that
information, if I just have tons of
units spread out all over the map as my
information, I can't really make sense
of it. So I I do have to organize that
and cluster that first before I I can
make decisions. And then I would be
like, okay, my group here, control group
one goes over there, control group two
goes over there. So I organize my own
units, I organize the enemy units, and
then I start interacting. And so you
have fewer pieces to uh think about when
you make the decisions. Um, and you're
not going to get into a space where the
decisions are weird because you're
you're organizing it on the right thing.
But you brought something interesting
The Snowball Effect
that I wanted to highlight.
Explain to me your definition snowball
and how it goes like say RTS like
snowballing in RTS. I know snowballing
in a like a mobile like I get don't get
snowballing in mobile it's really easy.
You have heroes and zero space has
heroes. So I guess there's a level of
which even in Warcraft 3 if anyone's a
Warcraft 3 fan knows like master can be
so meaty.
So is this the same snowballing? Are we
talking about snowballing?
It's not. Actually, it's actually worse
than a MOA. MOBAs actually put
snowballing into their game with uh the
fact that you get XP on hero death and
and how much XP you get is the snowball
you that happens. Actually, if you take
that away, it snowballs a lot less. Um
if let's say everybody rising at the
same exact level, right? Yeah.
And death doesn't actually matter,
there's really not much snowball in a
MOA. So, so yeah, like MOBAs inherently
don't have as much snowball. The reason
why is the number of units, right? So,
um, if you have like, you know, five
units versus three units in an RTS, a
lot of times those five units might win
with all five surviving.
So, five takeway three is not two. Five
take away three in an RTS is five,
right? So, that's called snowball. So
basically it's as if in a fighting game
which doesn't snowball uh when you take
when you punch them and they're at uh
you know five life they have zero damage
right how are you how is your you know
Chun Lee going to come back from you
know one life and zero damage pretty
much right they can't that's not how
fighting games work right but RTS games
work exactly like that when you get
Chunley to to one health she has zero
damage you're just dead right so
inherently it's it's a very tight tight
uh balance and um you know people talk
about APM speed and everything but any
RTS with enough viable strategies at any
point in time and at at any like second
in time where there's like two or three
viable strategies will always benefit
from speed because it's a real-time game
will all so so like my thought is like
you you take Supreme Commander which
people think have you know really good
strategy uh and less ATM intensive.
If you tune that balance such that at
every point in time there's there's like
more viable strategies, you're going to
be racing even more to and you're still
going to be like always like it's it's
going to be sweaty, right? So, um I
think that's why people call RTS a
little bit sweaty because when it's
actually well balanced, when there's a
lot of strategy, you're on the clock.
Does your AI organize it and play in the
way that you would think of it when you
were playing an RTS? Because you
obviously have a lot of experience from
Warcraft 3, Starcraft, whatnot. And like
is there if you are you able to walk me
through the processing of when you're
playing RTS and then how that mirrors
your AI?
Yeah, I think I think it it does reflect
how I organize information when I'm um
playing RTS. I think foundationally you
want to be very good at macro especially
macros so you want to be efficient uh
and clean um because it RTS snowballs so
uh I think sometimes you know there's
this discussion around like some whether
the game has more strategy or less
strategy um but I think regardless if
the game has any branching of viable
strategies if if at any moment in time
three viable strategies are are
possible, right? That means it's usually
a balanced game, but that also means the
timing on those strategies are so
essential um that it can snowball if
you're not doing it at the right time.
So, um, that's already a very important
basis of of of all this. Basically, if
the the art if the AI doesn't time
things correctly, doesn't get things at
the right time, doesn't have the SCV
there, doesn't have the builder where it
needs to be at the right time, um, then
you have these gaps. And when you have
these gaps, the snowball at the end of
the day, like, you know, 10 minutes down
the line, you're just not going to
you're not going to be able to make an
RTS that can compete against even a
base, a a decent human player.
Basically,
you've obviously had a chance to test
this internally with your your team,
yourself, what not like what was your
first impression of that experience with
Playtesting results
your AI?
It was quite good. I think it was quite
good. the AI is not being it's not, you
know, doing rat janky weird things,
right? And it's actually it's actually
being competitive and and even if I can
beat it, it it it feels like it's
playing the game.
Have you watched any of those games and
and gotten a chance to critique or
thought about how that AI responded to a
player?
Um, and did and did it do the behavior
you expected?
Yeah. Yeah. In in in in a lot of cases,
they they they were doing the behavior I
expected. I think um I think in some
cases like uh so there there's this
thing where um one instance where the AI
would be spawning either in waves
or some AI we I was trying to see if I
could just if what if what if it just
keeps
you know throwing stuff at the player
right
oh man did we already lose we are
playing against the grow
oh man
uh versus waves and and so the the
theory is that waves are a little better
actually.
Um, but in reality it's not
um because waves what what happened was
uh when I saw people play against when
the AI collects its its units in waves
um is that it gave the players actually
a little bit more breathing room. So the
players are able to exploit that
breathing room oftentimes if they're
good enough at least. Right. So co so so
actually coming in from more directions
all over the map in a semi- steady
stream was very hard to hold off because
it gave the player a lot less breathing
room and I think for the highle players
it was more fun.
Is that because of the tension of the
back and forth or the player trying
it is it is
and if someone is designing their own AI
because like you know there are tons of
people who are who are working on
designing their own AI what would advice
would you give them? Yeah, I was I would
always approach it in steps always like
what's the first step that you could
make that could that could have the most
uh visible effectiveness. Maybe even the
first AI you should be doing is just
you're you're waiting for a certain
supply count and then a moving to the
enemy base, right? Just like that as a
first thing like and then expand off
that. And motivation is essential to to
to be able to go all the way. And you
want to give yourself that uh runway of
just
iterative dopamine of what you did to be
able to keep pushing.
And what has been your golden rule to
keep to that path from like what has
been your guiding principle?
Keep decision making compartmentalized
in in in the areas that they they need
to be made. like uh don't overwhelm each
subsystem with more things that they
need to than they need to be able to
handle. Right.
What point would you say is the part
that someone will say ah like this is
like this feels the most humanlike. And
so whenever there's a reaction, a double
re like you, the AI comes in, you react
as a player react, the AI reacts back,
that's fun. That's interaction. That's
that's generally how a multiplayer game
[music] is meant to be played with an
opponent, right? But I think like seeing
the AI retreat is very humanike.
Days of walling off a base and watching
a bot break itself are over. New
generation of AI retreats, regroups, and
acts responds to what you're doing.
