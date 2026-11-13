# Gatherline

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
