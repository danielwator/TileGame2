/* ============================================================
 *  AEONS — Biome definitions
 *  Shared by worldgen, game rules and reference.html
 *
 *  yields   : base per-tile yield when worked (city tile radius)
 *  moveCost : army movement cost multiplier
 *  defense  : combat defense bonus for units standing here
 *  infMul   : influence cost multiplier to claim the tile
 *  allowsCity : can a city center be founded here
 *  passable : land units may enter (mountain/icecap need tech)
 * ============================================================ */
'use strict';
window.BIOMES = {
  /* ---------- Water ---------- */
  deepOcean: {
    id: 'deepOcean', name: 'Deep Ocean', water: true, color: '#27519b',
    yields: { food: 0, materials: 0, gold: 0, science: 0 },
    moveCost: 1, defense: 0, infMul: 3.0, allowsCity: false, passable: false,
    desc: 'Abyssal open water. Only deep-sea vessels (Compass+) may cross. Cannot be claimed until the Modern era.',
  },
  ocean: {
    id: 'ocean', name: 'Ocean', water: true, color: '#2f63b8',
    yields: { food: 1, materials: 0, gold: 0, science: 0 },
    moveCost: 1, defense: 0, infMul: 2.5, allowsCity: false, passable: false,
    desc: 'Open water over the continental slope. Naval units travel freely; fishing fleets can work it late-game.',
  },
  coast: {
    id: 'coast', name: 'Coastal Waters', water: true, color: '#56b6c4',
    yields: { food: 2, materials: 0, gold: 1, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.5, allowsCity: false, passable: false,
    desc: 'Shallow shelf waters. Rich fisheries and the highway of early trade. Claimable next to coastal cities.',
  },
  lake: {
    id: 'lake', name: 'Lake', water: true, color: '#4f9fd8',
    yields: { food: 2, materials: 0, gold: 0, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.0, allowsCity: false, passable: false,
    desc: 'Inland freshwater. Grants +1 Food to adjacent Farms.',
  },

  /* ---------- Cold ---------- */
  iceCap: {
    id: 'iceCap', name: 'Ice Cap', water: true, color: '#eef3f6',
    yields: { food: 0, materials: 0, gold: 0, science: 0 },
    moveCost: 3, defense: 0, infMul: 4.0, allowsCity: false, passable: false,
    desc: 'Permanent polar ice. Impassable until Icebreakers (Modern). Research Stations may be built here in the Information era.',
  },
  tundra: {
    id: 'tundra', name: 'Tundra', water: false, color: '#c9d2bd',
    yields: { food: 1, materials: 1, gold: 0, science: 0 },
    moveCost: 1.5, defense: 0, infMul: 1.4, allowsCity: true, passable: true,
    desc: 'Frozen plains of moss and permafrost. Hard to farm, but hides mineral wealth and, later, Oil.',
  },
  boreal: {
    id: 'boreal', name: 'Boreal Forest', water: false, color: '#5d8a66',
    yields: { food: 1, materials: 2, gold: 0, science: 0 },
    moveCost: 1.5, defense: 0.25, infMul: 1.2, allowsCity: true, passable: true,
    desc: 'Endless taiga. Superb logging country; slow to develop and cold enough to blunt farming.',
  },

  /* ---------- Temperate ---------- */
  grassland: {
    id: 'grassland', name: 'Grassland', water: false, color: '#a9cf7d',
    yields: { food: 3, materials: 0, gold: 0, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.0, allowsCity: true, passable: true,
    desc: 'Fertile lowlands — the breadbasket biome. Farms here outproduce every other terrain.',
  },
  plains: {
    id: 'plains', name: 'Plains', water: false, color: '#c5d68d',
    yields: { food: 2, materials: 1, gold: 0, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.0, allowsCity: true, passable: true,
    desc: 'Dry open flatland. A balanced all-rounder for food and industry.',
  },
  forest: {
    id: 'forest', name: 'Temperate Forest', water: false, color: '#559350',
    yields: { food: 1, materials: 2, gold: 0, science: 0 },
    moveCost: 1.5, defense: 0.25, infMul: 1.1, allowsCity: true, passable: true,
    desc: 'Broadleaf woodland. Lumber Camps thrive; defenders gain cover.',
  },
  wetland: {
    id: 'wetland', name: 'Wetland', water: false, color: '#7cab72',
    yields: { food: 2, materials: 0, gold: 0, science: 1 },
    moveCost: 2, defense: -0.1, infMul: 1.3, allowsCity: false, passable: true,
    desc: 'Marsh and bog. Rich in food and unique flora, but most construction requires Drainage (Medieval).',
  },

  /* ---------- Dry ---------- */
  savanna: {
    id: 'savanna', name: 'Savanna', water: false, color: '#cfc26f',
    yields: { food: 2, materials: 0, gold: 1, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.0, allowsCity: true, passable: true,
    desc: 'Tropical grassland dotted with acacia. Good herding and caravan country.',
  },
  steppe: {
    id: 'steppe', name: 'Steppe', water: false, color: '#c9c78a',
    yields: { food: 1, materials: 1, gold: 1, science: 0 },
    moveCost: 1, defense: 0, infMul: 1.0, allowsCity: true, passable: true,
    desc: 'Arid shortgrass plain. Horse country — mounted units trained in steppe cities are cheaper.',
  },
  desert: {
    id: 'desert', name: 'Desert', water: false, color: '#e9daa4',
    yields: { food: 0, materials: 0, gold: 2, science: 0 },
    moveCost: 1.5, defense: -0.1, infMul: 1.5, allowsCity: true, passable: true,
    desc: 'Sun-blasted waste. Nearly barren — until trade routes, Oil derricks and Solar Farms turn it to gold.',
  },

  /* ---------- Tropical ---------- */
  rainforest: {
    id: 'rainforest', name: 'Rainforest', water: false, color: '#2e7d3d',
    yields: { food: 1, materials: 1, gold: 0, science: 1 },
    moveCost: 2, defense: 0.25, infMul: 1.4, allowsCity: true, passable: true,
    desc: 'Dense equatorial jungle. Slow going and hard to clear, but a wellspring of medicine and science.',
  },

  /* ---------- Rugged ---------- */
  highlands: {
    id: 'highlands', name: 'Highlands', water: false, color: '#b0a482',
    yields: { food: 1, materials: 2, gold: 0, science: 0 },
    moveCost: 1.5, defense: 0.3, infMul: 1.2, allowsCity: true, passable: true,
    desc: 'Rolling hills and plateaus. Prime mining land with a natural defensive edge.',
  },
  mountain: {
    id: 'mountain', name: 'Mountain', water: false, color: '#8f8779',
    yields: { food: 0, materials: 1, gold: 0, science: 1 },
    moveCost: 3, defense: 0.5, infMul: 2.0, allowsCity: false, passable: false,
    desc: 'High peaks. Impassable until Mountaineering (Renaissance). Observatories and deep mines come later.',
  },
  volcanic: {
    id: 'volcanic', name: 'Volcanic', water: false, color: '#7a6358',
    yields: { food: 2, materials: 2, gold: 0, science: 0 },
    moveCost: 2, defense: 0.3, infMul: 1.6, allowsCity: true, passable: true,
    desc: 'Ash-fed soil around active vents. Extremely fertile and mineral-rich — with a chance of eruption events.',
  },
};

window.BIOME_LIST = Object.values(window.BIOMES);
