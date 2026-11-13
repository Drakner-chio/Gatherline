# Gatherline

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
