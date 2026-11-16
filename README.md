# Gatherline

Gathering routes for **World of Warcraft: Forever**: the shortest loop through your herb and ore nodes, measured over the real ground, drawn on the world map and the minimap – and a guide that rides you round it.

## Features

- **Routes from your GatherMate2 or GatherLite nodes** (or both – a node both know counts once): pick a zone and what to gather (Peacebloom, Copper Vein, whole kinds…), Gatherline finds the shortest loop
- **Over the real ground:** with Shortest Path Forever installed, routes are measured on the game's walking maps. Five candidate loops are walked leg by leg and polished, the shortest on foot wins – round mountains, cliffs and water instead of over them. Never longer than a straight-line route
- **Lines along the ground:** the route is drawn the way you'd actually ride it
- **Passes within:** with Find Herbs or Find Minerals on, the route only has to come close enough to see each node, so it cuts corners and nodes close together become one stop
- **Start:** ride a route with Shortest Path Forever's arrow and tracker. From another zone or continent it takes you there first (flights, boats, portals), then round the loop – lap after lap or a set number of laps, with lap times in chat
- **Guidance settings:** how close you need to get before the next stop, how many stops are shown ahead, and whether stops are called by number (*Stop 3/42*), by what's there (*Copper Vein ×2*) or both
- **Smart laps:** stops whose nodes you just gathered are skipped until they can be back
- **Statistics per route:** best and average lap, nodes an hour and, with Auctionator, gold an hour
- **Gather with your group:** friends with Gatherline share what they gather (the laps skip what they took) and send each other routes
- **Regrowth learnt** per zone, and how often a route's stops were found empty
- **Ready-made no-go areas:** hostile towns and elite camps (by your level), each switchable – routes keep out
- **Gathering HUD:** compass band, ground lens and lap card while you ride – each one switchable, movable and sizable
- **Tours over several zones:** ride routes one after the other, Shortest Path takes you from zone to zone
- **Routes by skill:** every node shows the skill it needs in skill-up colours; "only what I can gather"; *Where to skill up* finds the best zone for your Herbalism or Mining
- **Share routes** with friends as one line of text, and see which of your routes brings the most
- **Turn a route round** with one click
- **No-go areas:** draw parts of a zone your routes stay out of
- **New nodes join by themselves** where they add the least walking
- **Brings your routes over** from GatherPath Forever or GatherPath Plus
- **Languages:** English and German, following your game client

## Requirements

| Addon | What for | Needed? |
|---|---|---|
| **GatherMate2** or **GatherLite** | The nodes routes are made from (either, or both) | one of them |
| **Shortest Path Forever** (with **ForeverCore**) | Walking maps for routes over the ground, the guidance for Start, tours and the HUD | **yes** – installed with Gatherline by the CurseForge app (without it, routes use straight lines and there's no Start, guidance or HUD) |
| **Auctionator** | What your loot is worth, for gold an hour in the statistics | optional |

The **About** page in the window shows whether everything is there.

## Commands

| Command | What it does |
|---|---|
| `/gl` | Open the window |
| `/gl new` | Make a new route |
| `/gl start`, `/gl stop` | Ride the route shown in your zone / stop |
| `/gl reverse` | Turn the route round |
| `/gl laps N` | Laps Start rides (0 = until you stop) |
| `/gl reach N` | How close (yards) to a stop before the next one |
| `/gl names number\|nodes\|both` | What stops are called |
| `/gl show`, `/gl hide` | Show or hide all lines |
| `/gl skipped` | Nodes on your skip list |
| `/gl empty N` | Minutes a gathered stop is skipped (0 = never) |
| `/gl stats`, `/gl stats reset` | Statistics of the route you ride / start over |
| `/gl stats all` | All your routes, best first |
| `/gl regrowth` | How soon nodes grew back, per zone |
| `/gl tour [name]` | Ride a tour |
| `/gl hud [compass\|lens\|card\|preview]` | The gathering HUD: all, one part, or a preview |
| `/gl skill` | Where to skill up your Herbalism and Mining |
| `/gl share`, `/gl import` | Share the route shown in your zone / add a shared one |
| `/gl walk` | Test the walking search |

## Credits and licence

Gatherline grew out of **GatherPath Forever** by severd8 (MIT), whose route solver it still uses. The walking search in `Routing/` is from **Shortest Path Forever** by cjber (GPL-3.0), and its walking maps come from Shortest Path Forever itself. Gatherline is therefore licensed under **GPL-3.0-or-later** (`LICENSE`); GatherPath Forever's MIT notice is in `LICENSE-MIT-GatherPathForever`. The gathering skill each herb and ore needs (`Skills_Data.lua`, made by `tools/make_skills.py`) comes from **GatherLite** by Wuild (MIT, `LICENSE-MIT-GatherLite`). The ready-made no-go areas (`Hazards_Data.lua`, made by `tools/make_hazards.py`): elite camps from the **CMaNGOS Classic database** (GPL-3.0), hostile towns from **Shortest Path Forever**'s flight masters and town ground (GPL-3.0).

Development notes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
