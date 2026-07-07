/* ============================================================
 *  AEONS — Changelog
 *  Newest entries first. Shown in reference.html.
 * ============================================================ */
'use strict';
window.CHANGELOG = [
  {
    version: '0.3.0',
    date: '2026-07-02',
    title: 'High-resolution terrain',
    changes: [
      'Render mesh resolution decoupled from the climate simulation: terrain now renders at 6× / 9× / 12× the tile frequency (up to ~830,000 vertices on a large Ultra world) while plates/climate simulate at 3× and gameplay tiles stay unchanged.',
      'New arithmetic-dedup geodesic builder (corner/edge/interior index math, no hash maps) keeps massive render grids fast to construct.',
      'Climate fields (elevation, temperature, moisture, volcanism, lakes, land proximity) are barycentrically interpolated from the simulation grid onto every render vertex, then biomes are re-classified per vertex — coastlines and biome boundaries are now pixel-crisp instead of tile-blocky.',
      'Extra render-scale relief noise adds coastline wiggle and ridge texture; shorelines get sandy beach blending; terrain speckle replaced with smooth noise grain.',
      'World generation is multithreaded (WorkerThreadPool) across all CPU cores.',
      'New "Terrain Detail" option on the main menu (Standard 6× / High 9× / Ultra 12×); the menu shows progress while forging the world.',
      'Fixed a face-winding bug that made the globe render inside-out (Godot expects clockwise front faces), which could make the planet look see-through.',
    ],
  },
  {
    version: '0.2.0',
    date: '2026-07-02',
    title: 'Godot engine port + high-resolution terrain',
    changes: [
      'Ported the entire game from the browser prototype to Godot 4.4 (native Windows app; run AEONS.bat or open game/ in Godot).',
      'Terrain generation and rendering now use a high-resolution geodesic field at 3x the tile frequency — coastlines, mountain ranges and climate zones are fully independent of the gameplay tile grid, which samples the field by majority vote.',
      'Terrain mesh renders with true vertex relief and accumulated smooth normals; mountains rise from the silhouette.',
      'Tectonic plates now use domain-warped weighted Voronoi assignment (faster and cleaner boundaries at high resolution); mid-ocean ridges kept submarine.',
      'Per-tile fog/political overlay layer with translucent nation tints; border ribbons; selection/hover outlines; 3D city labels, unit tokens with hp pips, and deposit markers.',
      'Full Godot UI: resource top bar with live rates, tile panel (claim / build with placement-rule feedback), city panel (training, specializations), scrollable 8-age tech tree, policies screen, diplomacy screen, event and perk dialogs, victory screen, pause menu, main menu with seed/size/nations/ocean/climate/difficulty.',
      'Integration self-test suite (19 checks: founding, claiming, building, training, combat, fog, trade, policies, save/load, 400-tick stability) — run with AEONS_TEST=1.',
      'Save/load to Godot user:// storage; Continue button on the main menu.',
      'The browser version remains in the repository as a prototype; data/*.js stays the single authoring source, exported to game/data/gamedata.json for the engine and read directly by reference.html.',
    ],
  },
  {
    version: '0.1.0',
    date: '2026-07-01',
    title: 'Initial release',
    changes: [
      'Seeded parametric world generation: tectonic plates with motion vectors, convergent/divergent boundary stress (mountain belts, island arcs, rifts, trenches), hotspot island chains.',
      'Climate model: latitude temperature bands with altitude lapse, prevailing-wind moisture advection (trade winds / westerlies / polar easterlies), orographic rain shadows, ITCZ equatorial rains and horse-latitude deserts.',
      '18 biomes classified from temperature x moisture x elevation, including inland seas, lakes, volcanic soil and polar ice.',
      'Goldberg-polyhedron globe (12 pentagons + hexagons; 2,562 / 4,002 / 5,762 tile world sizes).',
      '8 ages from Ancient to Near Future; age advancement via researched-tech count with a perk pick (1 of 3) at each new age.',
      '288 technologies across 6 branches (Agriculture, Industry, Military, Commerce, Science, Statecraft).',
      '76 buildings with biome placement rules, biome output multipliers, deposit requirements and strategic-resource consumption.',
      '42 units from Warrior to Battle Mech across melee/ranged/cavalry/siege/naval/air classes.',
      'Resources: Food, Materials, Gold, Science, Influence + strategic Coal, Oil and manufactured Circuits.',
      '10 tile deposit types with tech-gated reveals (Metal Ore, Coal, Oil, Rare Earths...).',
      'Influence-based border expansion: claim cost and upkeep scale with distance from cities; capital projects influence 40% further; borders decay when influence runs dry.',
      'Three-state fog of war: unknown / discovered (terrain intel only, dimmed) / visible (full detail from owned tiles +2, units and allies).',
      '30 policies in limited slots, 24 nation perks, 10 city specializations.',
      '40 random events with era scaling, conditions, durations and choice events.',
      'Diplomacy: war/peace, alliances, non-aggression pacts, trade deals, relations with opinion drift, AI proposals.',
      'AI nations with expansion, construction, research, diplomacy and war behaviors across 3 difficulty levels.',
      '5 victory conditions: Domination, Science (Starlight Ark), Economic, Hegemony, Score (year 2200).',
      'RTS controls: drag-rotate globe, wheel zoom, WASD/QE, click select, right-click orders, pause/1x/2x/4x speed.',
      'Save/load to browser storage. Map lenses: terrain, political, biome, elevation, temperature, moisture, plates.',
    ],
  },
];
