/* ============================================================
 *  AEONS — Resources & tile deposits
 *  Shared by worldgen, game rules and reference.html
 * ============================================================ */
'use strict';

/* ---------- Stockpiled nation resources ---------- */
window.RESOURCES = {
  food: {
    id: 'food', name: 'Food', icon: '🌾', color: '#8fce5e', tier: 'core',
    desc: 'Feeds your population. Each population unit eats 1 Food per tick; surplus fills city growth bars, deficit causes starvation (population loss and unrest).',
  },
  materials: {
    id: 'materials', name: 'Materials', icon: '🪨', color: '#c9a45f', tier: 'core',
    desc: 'Timber, stone and metal. Spent to construct buildings and train units; the universal industry resource.',
  },
  gold: {
    id: 'gold', name: 'Gold', icon: '🪙', color: '#f2c94c', tier: 'core',
    desc: 'The currency. Pays unit and building upkeep, rush-buys production, funds diplomacy and trade deals. A bankrupt nation suffers army desertion.',
  },
  science: {
    id: 'science', name: 'Science', icon: '⚗️', color: '#5eb9ce', tier: 'core',
    desc: 'Research points, generated per tick and invested automatically into the selected technology.',
  },
  influence: {
    id: 'influence', name: 'Influence', icon: '👑', color: '#b48ce0', tier: 'core',
    desc: 'Political reach. Spent to claim tiles, enact policies and make diplomatic proposals. Border tiles cost Influence upkeep that grows with distance from your cities.',
  },
  coal: {
    id: 'coal', name: 'Coal', icon: '⛏️', color: '#4a4a52', tier: 'strategic', unlockAge: 5,
    desc: 'Industrial-era strategic resource, extracted by Coal Mines on Coal deposits. Powers Factories and early industrial units. Becomes tradeable on the world market.',
  },
  oil: {
    id: 'oil', name: 'Oil', icon: '🛢️', color: '#3d3d3d', tier: 'strategic', unlockAge: 6,
    desc: 'Modern-era strategic resource from Oil Wells and Offshore Platforms. Fuels tanks, aircraft and Power Plants. Wars have been started for less.',
  },
  circuits: {
    id: 'circuits', name: 'Circuits', icon: '💾', color: '#5ecfa0', tier: 'strategic', unlockAge: 7,
    desc: 'Advanced manufactured component (not mined!). Chip Fabs convert Materials + Gold into Circuits; fabs need a Rare Earth deposit within your borders. Required by Information/Near-Future buildings and units.',
  },
};
window.RESOURCE_LIST = Object.values(window.RESOURCES);

/* ---------- Tile deposits (spawned by worldgen) ---------- */
/* spawn: { biomeId: weight } — relative chance per eligible tile.
 * revealTech: deposit is hidden on the map until this tech is researched. */
window.DEPOSITS = {
  fertile: {
    id: 'fertile', name: 'Fertile Soil', icon: '🌱',
    effect: '+2 Food to Farms/Plantations on this tile',
    yields: { food: 2 }, worksWith: ['farm', 'plantation', 'verticalFarm'],
    spawn: { grassland: 14, plains: 8, savanna: 8, wetland: 12, volcanic: 20 },
    revealTech: null,
    desc: 'Deep loam or volcanic ash soil. The cradle of every great empire.',
  },
  game: {
    id: 'game', name: 'Wild Game', icon: '🦌',
    effect: '+2 Food to Hunting Camps; +1 Food unimproved',
    yields: { food: 2 }, worksWith: ['huntingCamp'],
    spawn: { forest: 12, boreal: 14, tundra: 8, savanna: 10, rainforest: 8 },
    revealTech: null,
    desc: 'Herds of deer, elk or antelope. Feeds early cities before agriculture scales.',
  },
  fish: {
    id: 'fish', name: 'Fish Shoals', icon: '🐟',
    effect: '+2 Food to Fisheries on this tile',
    yields: { food: 2 }, worksWith: ['fishery', 'trawlerDock'],
    spawn: { coast: 16, lake: 20, ocean: 5 },
    revealTech: null,
    desc: 'Teeming shallows. Coastal nations live and die by them.',
  },
  stone: {
    id: 'stone', name: 'Stone', icon: '🪨',
    effect: '+2 Materials to Quarries on this tile',
    yields: { materials: 2 }, worksWith: ['quarry'],
    spawn: { highlands: 14, mountain: 10, desert: 6, plains: 5, tundra: 5 },
    revealTech: null,
    desc: 'Workable granite, marble or limestone outcrops.',
  },
  metals: {
    id: 'metals', name: 'Metal Ore', icon: '⚙️',
    effect: '+2 Materials to Mines; required for metal-line units at full strength',
    yields: { materials: 2 }, worksWith: ['mine', 'deepMine'],
    spawn: { highlands: 14, mountain: 16, volcanic: 14, desert: 5, tundra: 6, boreal: 4 },
    revealTech: 'bronzeWorking',
    desc: 'Copper, tin and iron veins. Revealed by Bronze Working.',
  },
  horses: {
    id: 'horses', name: 'Horses', icon: '🐎',
    effect: '+1 Food, +1 Gold to Pastures; enables cavalry units at -25% cost',
    yields: { food: 1, gold: 1 }, worksWith: ['pasture'],
    spawn: { steppe: 18, plains: 10, grassland: 8, savanna: 6 },
    revealTech: 'animalHusbandry',
    desc: 'Wild herds. Revealed by Animal Husbandry; the engine of ancient conquest.',
  },
  gems: {
    id: 'gems', name: 'Gems', icon: '💎',
    effect: '+3 Gold to Mines on this tile',
    yields: { gold: 3 }, worksWith: ['mine', 'deepMine'],
    spawn: { mountain: 8, highlands: 6, rainforest: 5, desert: 4, volcanic: 6 },
    revealTech: 'currency',
    desc: 'Precious stones and native gold. Revealed by Currency.',
  },
  coalDep: {
    id: 'coalDep', name: 'Coal Deposit', icon: '⛏️',
    effect: 'Coal Mine here produces +3 Coal/tick',
    yields: { materials: 1 }, worksWith: ['coalMine'],
    spawn: { highlands: 12, mountain: 10, forest: 6, boreal: 8, plains: 4, tundra: 6 },
    revealTech: 'steamPower',
    desc: 'Carboniferous seams. Revealed by Steam Power; the fuel of the Industrial age.',
  },
  oilDep: {
    id: 'oilDep', name: 'Oil Field', icon: '🛢️',
    effect: 'Oil Well here produces +3 Oil/tick',
    yields: {}, worksWith: ['oilWell', 'offshorePlatform'],
    spawn: { desert: 12, tundra: 10, coast: 8, ocean: 6, steppe: 6, wetland: 5 },
    revealTech: 'combustion',
    desc: 'Crude reservoirs. Revealed by Combustion. Deserts and shallow seas hide the richest fields.',
  },
  rareEarth: {
    id: 'rareEarth', name: 'Rare Earths', icon: '🧲',
    effect: 'Required within borders to operate Chip Fabs; +2 Science to Mines here',
    yields: { science: 2 }, worksWith: ['mine', 'deepMine'],
    spawn: { mountain: 8, desert: 6, tundra: 6, volcanic: 8, highlands: 4 },
    revealTech: 'semiconductors',
    desc: 'Neodymium, lithium, cobalt. Revealed by Semiconductors; scarce, strategic, fought over.',
  },
};
window.DEPOSIT_LIST = Object.values(window.DEPOSITS);
