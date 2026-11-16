# Gatherline

## v1.10.0

- **Best gold?** on *New route*: what every zone's herbs and ores you can gather are worth, at
  Auctionator's prices – what a node yields on average comes from the Classic database – the best
  zones in chat, and the best one picked with its most valuable nodes on. (Needs Auctionator with
  prices scanned.) *Where to skill up* is now *Skill up?* next to it.
- **Bags filling up:** while you ride, a warning in chat (with a sound) and on the lap card once
  your bags are down to 4 free slots (*Gathering HUD → Warn at free bag slots*, 0 = never).
- **Tracking button:** a HUD button shows the search the stop ahead needs (Find Herbs, Find
  Minerals) and lights up when it isn't on; a click switches. It has a key in *Key Bindings →
  Gatherline*. Like the other parts it can be moved, sized and switched off.

## v1.9.0

- **Gather with your group:** Gatherline users in a group tell each other what they gather, so
  the smart laps also skip a stop your friend just picked clean. Routes can be sent straight to
  your group or a player from *Share*; they're asked whether to add it. *Guidance → Smart laps →
  Gather with my group* (on to start with).
- **Regrowth learnt:** Gatherline notes how soon a node you or your group gathered was there to
  gather again, per zone, and the smart laps skip a stop no longer than that – never longer
  than the minutes you set. `/gl regrowth` shows what it has learnt.
- **Found empty:** a stop you reach with nodes no one in your group gathered lately, where you
  gather nothing, counts as found empty – someone else was there first. The route's statistics
  show it (*35 % found empty*) once five stops were reached, so you see which routes are crowded.

## v1.8.0

- **Ready-made no-go areas** on the *No-go areas* page, under your own:
  - **Hostile towns:** the other faction's towns with a flight master (Southshore, Astranaar …),
    as far as the game counts them to the town – on for you automatically.
  - **Elite camps:** about 900 places in the open world where elites, rare elites and bosses
    stand (Hogger, the Defias at Moonbrook, Tyr's Hand …), with their levels. They keep routes
    out until you're well above them (*Elite camps open from this many levels below you*,
    5 to start with); as you level, camps open by themselves.
  - Switch each one on or off by hand, a whole zone at once, or each kind; *Automatic* puts a
    zone's switches back. They show orange on the world map.
  - Routes worked out from then on keep out of the ones that are on; *Rebuild routes here*
    works a zone's routes out again.
- No other addon is needed for this: the data is built into Gatherline (elite camps from the
  CMaNGOS Classic database, hostile towns from Shortest Path Forever, both GPL-3.0).

## v1.7.4

- If Gatherline ever can't read Shortest Path Forever's walking maps (Shortest Path Forever
  updated ahead of it), it now says so once in chat and uses straight lines until `/reload`,
  instead of a stream of Lua errors.

## v1.7.3

- Switching *Move the parts* off now ends the HUD preview it started too.

## v1.7.2

- **Fixed: "PathGrid.lua:60: attempt to perform arithmetic on field '?'"** after updating
  Shortest Path Forever to 1.37. It now stores its walking maps in a new format (3); Gatherline's
  copy of the walking search is updated to read it. Should Shortest Path Forever change the format
  again, Gatherline draws straight lines until it catches up instead of throwing errors.
- **Each route shows which way it is ridden:** the round arrow on its card is clockwise or
  anticlockwise, and a click turns the route round. The global *Reverse direction* switch is gone –
  if you had it on, your routes were turned round once so you ride them as before.
- **New icons** on the route and tour cards (share, direction, edit, rebuild, delete), in
  Gatherline's own look.

## v1.7.1

- **Each HUD part its own look:** compass band, ground lens and lap card each keep their
  own size, text size and opacity (*Gathering HUD → Look*, pick the part first).
- While *Move the parts* is on, the mouse wheel over a part makes it bigger or smaller.
- *Back to their places* also puts sizes, text sizes and opacity back.

## v1.7.0

- **Line width in halves:** world map and minimap line widths now go in steps of 0.5,
  from 0.5 up – for really fine lines.
- **Line style:** routes can be drawn as a solid line, dashes or dots, set apart for the
  world map and the minimap (*Map & lines → Style*). Dots and dashes run on evenly round
  the corners; the width sets how thick the dashes and how big the dots are.

## v1.6.1

- The compass band no longer lies on top of Shortest Path Forever's own compass: while
  that one shows, the band sits under it (unless you've moved it yourself).
- Stops that line up far off no longer pile up on the band as a heap of rings.

## v1.6.0

- **Gathering HUD** while you ride a route or a tour, in three parts you switch on and off
  one by one (*Gathering HUD* page, `/gl hud`):
  - **Compass band** at the top: the way you face, the stop you head for as a diamond, the
    next ones numbered and empty ones hollow; under it the stop's name, how far, which
    way, and the lap so far.
  - **Ground lens**: a tilted disc round you that turns with you, with the route's line
    along the ground and the stops on it (off to start with).
  - **Lap card** at the bottom: the stop you head for (yards and seconds), a dot for every
    stop of the lap (done, skipped, empty), the lap time against your best, nodes and gold
    an hour.
- Size, opacity and the lens's reach can be set; *Move the parts* lets you drag each part
  where you like, *Preview* shows the HUD with made-up stops to try it without riding.
  It can step aside in combat.

## v1.5.0

- **Tours over several zones:** the new *Tours* page puts routes together – for example the
  Barrens, then Stonetalon, then Ashenvale. *Start* rides the laps of one route, then
  Shortest Path Forever leads you on to the next one, flights, boats and portals included.
  Set the laps on each route and whether the tour starts over at the end. It begins with
  its route in your zone if it has one.
- The route you ride shows where in the tour you are (*tour 2/3*). Stop, or starting a
  single route, ends the tour. `/gl tour [name]` starts one from chat.

## v1.4.0

- **Routes by skill:** on *New route* every herb and ore shows the skill it needs, in the
  game's colours for your Herbalism or Mining – red you can't gather yet, orange and yellow
  raise your skill, green a little, grey no more.
- **Only what I can gather:** a switch under the node list hides what your skill isn't high
  enough for.
- **Where to skill up:** a button next to *My zone* (and `/gl skill`) looks through every
  zone for the nodes that still raise your skill, lists the best zones in chat and picks the
  best one with those nodes on – one click to *Make route*.
- Skill data for herbs and ores comes from GatherLite (MIT), in every language it has.

## v1.3.0

- **Share routes:** the new *Share* button on a route's card gives you one line of text
  with the route in it. Send it to a friend; they click *Import* (next to *New route*) and
  paste it, and get exactly your loop – the same stops, the lines along the ground, its
  colour and pass distance. A route whose name is taken in that zone gets a number.
  `/gl share` and `/gl import` do the same.
- **Your best route:** once two routes in a zone are ridden for at least 10 minutes each,
  the one that brings the most an hour (gold with Auctionator, else nodes) is marked
  *best here* on its card. `/gl stats all` lists all your routes, best first.

## v1.2.0

- **Smart laps:** Gatherline notes where you gather (Herb Gathering, Mining). A stop whose
  nodes you all gathered within the last few minutes is left out of the next laps, so you
  don't ride past nodes that can't be back yet. *Guidance → Smart laps* sets how long
  (default 5 minutes, 0 = never); `/gl empty N` does too. The lap line in chat says how many
  stops were skipped. If every stop is empty, the ride goes on as usual.
- **Statistics per route:** each lap you ride counts – best and average lap, nodes gathered
  an hour and, with **Auctionator**, what the loot is worth an hour. They show on the route's
  card and with `/gl stats`; `/gl stats reset` starts over.
- A lap is now timed from its first stop to the next lap's first stop, so the way to the
  route no longer counts towards the first lap.

## v1.1.0

- **GatherLite support:** Gatherline now makes routes from GatherLite's nodes too –
  including the WoW Forever node database GatherLite comes with. GatherMate2 is no longer
  required: either one is enough. With both, a node both know counts once.
- New nodes GatherLite records join your routes like GatherMate2's do.
- GatherLite's ignored nodes stay out of routes.
- The About page shows which node sources were found.

## v1.0.1

- Fixed Lua errors in `Routing/PathGrid.lua` ("bad argument #1 to 'byte'") while a route was
  worked out: Gatherline's walking search and Shortest Path Forever's own one shared the
  decoded walking maps, and each dropped pieces the other was still reading. That could
  break Shortest Path Forever's own directions too. Gatherline now keeps its own.

## v1.0.0 – first release

**Gatherline** turns your GatherMate2 herb and ore nodes into the shortest gathering loop,
measured over the real ground with Shortest Path Forever's walking maps, drawn on the world
map and the minimap, and ridden with Shortest Path Forever's arrow and tracker.
Made for World of Warcraft: Forever.

- Routes over the ground: five candidate loops walked leg by leg and polished, the shortest
  on foot wins – never longer than a straight-line route
- Lines along the ground, "passes within" for Find Herbs / Find Minerals
- Start: guidance from anywhere to the route and round it, laps, lap times, stop names
- Turn a route round, no-go areas, skip list, new nodes join by themselves
- English and German

Before 1.0.0 Gatherline was a private fork of GatherPath Forever called GatherPath Plus.
Its routes, no-go areas and skip list come over by themselves the first time Gatherline
starts (with GatherPath Plus or GatherPath Forever still switched on), or with
*Bring routes over* on the About page.
