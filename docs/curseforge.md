## Gathering routes over the real ground

**Gatherline** turns your GatherMate2 herb and ore nodes into the shortest gathering loop – measured over the real terrain, drawn on your world map and minimap, and ridden with an arrow that leads you round it.

Made for **World of Warcraft: Forever**.

## Routes that know the ground

Pick a zone and what to gather – single nodes like *Peacebloom* or *Copper Vein*, or whole kinds. Gatherline finds the loop.

- **Over the ground, not through it:** with **Shortest Path Forever** installed, every route is measured on the game's own walking maps. Gatherline works out five candidate loops, walks each of them leg by leg, polishes the best ones and keeps the shortest on foot – round mountains, cliffs and lakes instead of straight over them.
- **Never worse than a straight line:** the plain straight-line loop is always one of the candidates. In tests on the real walking maps, routes in mountainous zones like Dun Morogh and Loch Modan came out 20–29% shorter on foot.
- **Lines along the ground:** the route on your map follows the way you'd actually ride.
- **Passes within:** with Find Herbs or Find Minerals on you see a node before you reach it, so the route only has to come that close. It cuts corners, and nodes close together become one stop.

## Ride it

Click **Start** on a route and Shortest Path Forever's arrow and tracker take over:

- From **anywhere** – another zone, another continent – it leads you to the route first, with flights, boats and portals, then round the loop from the nearest stop.
- **Lap after lap**, or a set number of laps, with each lap's time in chat.
- **Your pace:** set how close you need to get before it moves on to the next stop, and how many stops it shows ahead.
- **Stops by name:** call them *Stop 3/42*, by what's there – *Copper Vein ×2, Tin Vein* – or both.
- Ride past a stop toward a later one and it simply carries on from there.
- **Turn a route round** with one click.

## And more

- **No-go areas:** draw parts of a zone on the world map that your routes keep out of.
- **New nodes join by themselves** wherever they add the least walking.
- **Skip list:** right-click poor or wilted nodes to leave them out everywhere.
- **Bring your routes over** from GatherPath Forever.
- A clean, dark window: My routes, New route, Guidance, Map & lines, No-go areas and About – `/gl` opens it.
- **English and German**, following your game client.

## Requirements

- **GatherMate2** (required) – the nodes routes are made from.
- **Shortest Path Forever** with **ForeverCore** (recommended) – walking maps and guidance. Without it routes use straight lines and there's no Start.

## Commands

| Command | What it does |
|---|---|
| `/gl` | Open the window |
| `/gl start`, `/gl stop` | Ride the route shown in your zone / stop |
| `/gl reverse` | Turn the route round |
| `/gl laps N` | Laps to ride (0 = until you stop) |
| `/gl reach N` | How close (yards) before the next stop |
| `/gl names number\|nodes\|both` | What stops are called |
| `/gl show`, `/gl hide` | Show or hide all lines |

## Credits

Gatherline grew out of **GatherPath Forever** by severd8 (MIT) and uses the walking search of **Shortest Path Forever** by cjber (GPL-3.0). Licensed under GPL-3.0. Source: [github.com/Drakner-chio/gatherline](https://github.com/Drakner-chio/gatherline)
