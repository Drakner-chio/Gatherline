# Gatherline

Sammelrouten für **WoW: Forever**: die kürzeste Runde durch deine Kräuter- und Erzvorkommen, gemessen über das echte Gelände, gezeichnet auf Weltkarte und Minimap, und auf Wunsch mit Pfeil und Tracker abgeritten.

`/gl` öffnet das Fenster, `/gl help` zeigt alle Befehle. Die Oberfläche folgt der Spielsprache (Deutsch oder Englisch).

## Was du brauchst

| Addon | Wofür | Pflicht? |
|---|---|---|
| **GatherMate2** | Die Vorkommen, aus denen Routen entstehen | ja |
| **Shortest Path Forever** (mit **ForeverCore**) | Die Laufkarten fürs Gelände und die Führung (Pfeil, Tracker) | empfohlen: ohne geht es nur mit Luftlinie und ohne Start |
| GatherPath Forever / GatherPath Plus | – | **nein**. Nur einmal eingeschaltet lassen, wenn du deine alten Routen übernehmen willst |

Ob alles da ist, zeigt die Seite **Info** im Fenster.

## Installation

1. Den Ordner `Gatherline` nach `Interface\AddOns\` kopieren.
2. Hast du schon Routen in GatherPath Plus: das Addon für diesen einen Login noch eingeschaltet lassen. Gatherline übernimmt die Routen beim ersten Start von selbst (oder per **Routen übernehmen** auf der Seite Info).
3. Danach GatherPath Plus ausschalten oder löschen. Beide gleichzeitig zeichnen sonst dieselben Routen doppelt.

## Das Fenster

- **Meine Routen**: deine Runden als Karten. Links der Farbstreifen (anklicken ändert die Farbe), daneben der Name; rechts **Start**, Umkehren, Bearbeiten, Neu berechnen, Löschen. Darunter Vorkommen, Länge zu Fuß, Rundenzeit.
- **Neue Route**: Zone, Vorkommen, Abstand („Route kommt heran bis auf“) und **Dem Gelände folgen**.
- **Führung**: ab wie viel Metern zum nächsten Wegpunkt geschaltet wird, wie viele Wegpunkte im Voraus, Rundenzahl, wie die Wegpunkte heißen (Nummer, was dort ist, oder beides), Pfeile und Linie zur Route.
- **Karte & Linien**: Linien auf Weltkarte und Minimap, Farben, Reichweitenkreis, Minimap-Knopf.
- **Sperrzonen**: Gebiete, aus denen sich Routen heraushalten.
- **Info**: was Gatherline braucht und ob es da ist, Routen übernehmen, woraus es entstanden ist.

## Befehle

| Befehl | Was es macht |
|---|---|
| `/gl` | Fenster öffnen |
| `/gl new` | Neue Route anlegen |
| `/gl start`, `/gl stop` | Die angezeigte Route in deiner Zone abreiten / aufhören |
| `/gl reverse` | Route umkehren |
| `/gl laps N` | Runden für Start (0 = endlos) |
| `/gl reach N` | Ab wie vielen Metern zum nächsten Wegpunkt geschaltet wird |
| `/gl names number\|nodes\|both` | Wie die Wegpunkte heißen |
| `/gl show`, `/gl hide` | Alle Linien zeigen / ausblenden |
| `/gl skipped` | Ausgelassene Vorkommen |
| `/gl walk` | Test der Wegsuche |

## Herkunft und Lizenz

Gatherline ist aus **GatherPath Forever** von severd8 (MIT) entstanden und nutzt noch dessen Routenberechnung. Die Wegsuche in `Routing/` stammt aus **Shortest Path Forever** von cjber (GPL-3.0). Deshalb steht Gatherline unter GPL-3.0 (`LICENSE`); der MIT-Hinweis von GatherPath Forever liegt bei (`LICENSE-MIT-GatherPathForever`). Fenster, Look, Texte und Logo sind Gatherlines eigene.

## Tests

```sh
lua5.1 tests/run.lua
luajit tests/walk_spec.lua ../shortest-path-forever
```
