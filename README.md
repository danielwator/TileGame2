# AEONS

A globe-spanning grand-strategy game: one procedurally generated planet, eight ages
(Ancient → Near Future), ~290 technologies, influence-driven borders, war, diplomacy,
trade, fog of war and five victory conditions — built in **Godot 4.4**.

![engine](https://img.shields.io/badge/engine-Godot%204.4-478cbf) ![status](https://img.shields.io/badge/version-0.2.0-e8c15a)

## Play

**Double-click `AEONS.bat`** (or open the `game/` folder with Godot 4.4+ and press Run).

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
AEONS.bat            launcher
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

**Terrain is independent of the tile grid**: climate and plates are simulated on a
medium geodesic field (3× the tile frequency), then barycentrically interpolated and
re-classified per-vertex onto a much denser render mesh (6×/9×/12× the tile frequency —
up to ~830k vertices, chosen via the Terrain Detail menu option, generated across all
CPU cores). Gameplay runs on a coarser Goldberg hex/pentagon tile layer
(2,562 / 4,002 / 5,762 tiles) that samples the field by majority vote.

**World generation** (fully seeded and deterministic): tectonic plates with motion
vectors → boundary stress (mountain belts, island arcs, rifts, trenches, hotspot
chains) → percentile sea level → latitude temperature with altitude lapse →
prevailing-wind moisture advection with orographic rain shadows, ITCZ and horse-latitude
belts → Whittaker biome classification → biome-weighted tile deposits.

## Testing

```
set AEONS_TEST=1 & tools\Godot_v4.4.1-stable_win64_console.exe --headless --path game
```
runs a 19-check integration suite (founding, claiming, building, training, combat,
fog, trade, policies, save/load, 400-tick stability).

Other dev env vars: `AEONS_SEED` (quick-start, skip menu), `AEONS_SIM=<n>` (run n ticks
at startup), `AEONS_SNAP=<path>` (screenshot), `AEONS_UI=tech|diplo|policy`,
`AEONS_QUIT=1`.
