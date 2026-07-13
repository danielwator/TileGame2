# TileGame2

A globe-spanning grand-strategy game: one procedurally generated planet, eight ages
(Ancient → Near Future), ~290 technologies, influence-driven borders, war, diplomacy,
trade, fog of war and five victory conditions — built in **Godot 4.4**.

![engine](https://img.shields.io/badge/engine-Godot%204.4-478cbf) ![status](https://img.shields.io/badge/version-0.8.0-e8c15a)

Eras are equal-length and research-gated; the calendar is uniform (1 year per tick in
every era) and the pace is deliberately unhurried — use the 2×/4× speed buttons when
you want history to move faster.

## Play

**Double-click `TileGame2.bat`** (or open the `game/` folder with Godot 4.4+ and press Run).

- Drag to rotate the globe, mouse-wheel to zoom, WASD/arrows to pan, Q/E zoom
- **Left-click** selects a tile (panels open for claiming, building, cities, units)
- **Right-click** orders the selected unit to move / attack / settle
- Space pauses, T opens the tech tree, F5 saves, Esc closes windows
- Top bar: resources with live rates, research, date, game speed (pause/1×/2×/4×)

## Reference / Wiki

Open **`reference.html`** in any browser — a searchable wiki of every technology,
building, unit, biome, resource, policy, perk, specialization, random event, victory
condition and game mechanic, plus the **changelog**. It reads the same authored data
the game uses, so it can never drift out of date.

## Architecture

```
TileGame2.bat        launcher
game/                Godot 4.4 project
  data/gamedata.json all game content (generated from data/*.js)
  scripts/core/      seeded worldgen: plates, climate, biomes; sphere grids
  scripts/render/    globe mesh, overlays, borders, markers, camera
  scripts/game/      simulation: economy, borders, combat, diplomacy, fog, events, AI
  scripts/ui/        HUD, tech tree, diplomacy, policies, menus
data/*.js            single authoring source for all game content
reference.html       the wiki (reads data/*.js directly)
index.html + src/    the original browser prototype (kept for reference)
tools/               Godot editor binaries
```

**World generation** is a faithful GDScript port of the original TileGame project's
generator: a seeded 1024×512 equirect grid with domain-warped tectonic plates, ridged
elevation, ITCZ/Hadley moisture with tectonic rain shadows, 25 Whittaker tile types,
lake filling, island culling, coastal shallows, and rivers routed over depression-filled
elevation. The globe re-classifies the fields **per pixel** with the original palette,
so coastlines stay crisp at any zoom. Gameplay runs on an independent Goldberg
hex/pentagon tile layer (2,562 / 4,002 / 5,762 tiles) sampling the grid beneath it.

**Research** is a weighted draw: pick from a hand of 3+ options, weighted toward the
branches your empire is spec'd into (research history, policies, perks, city
specializations); reroll for Influence. **Icons**: the UI renders placeholder boxes —
drop PNGs into `game/assets/icons/` (see its README) to replace them.

**Cities & districts**: only tiles that are *part of a city* can hold buildings. A city
starts as its center tile and grows by **annexing** adjacent owned territory (Materials +
Gold + Influence, scaling with city size), capped by urban research (+1 city tile from
techs like Masonry, Aqueducts, Guilds… up to ~17 by the Near Future). Each city tile
carries **8 building slots** apportioned from the biome mix it spans (70% forest / 20%
ocean / 10% desert → 5 forest + 2 ocean + 1 desert slots); slots gate which buildings
are allowed and apply their own biome multipliers. Plain territory just trickles a small
share of its biome yields and costs steeply more Influence to claim the farther it lies
from your cities.

**Diplomacy & fog**: AI offers of alliance, pacts, trade and peace arrive as proposals
you accept or decline — only war is uninvited. Gifts, tribute demands, denouncements
and pact-breaking round out the toolbox. Vision is live, not permanent: you see around
territory, cities (farther) and units (scouts farther still); the map re-fogs behind you.

## Testing

```
set AEONS_TEST=1 & tools\Godot_v4.4.1-stable_win64_console.exe --headless --path game
```
runs a 39-check integration suite (research draws, annexation, districts, combat,
fog transience, diplomacy proposals, exponential costs, save/load, 500-tick stability).

Other dev env vars (still `AEONS_`-prefixed for compatibility): `AEONS_SEED`
(quick-start, skip menu), `AEONS_SIM=<n>` (run n ticks at startup),
`AEONS_SNAP=<path>` (screenshot), `AEONS_UI=tech|diplo|policy`, `AEONS_QUIT=1`.
