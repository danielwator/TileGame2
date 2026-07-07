/* ============================================================
 *  AEONS — Random Events (40)
 *
 *  Every tick each nation has a small chance of an event roll.
 *  Weights are relative among currently-eligible events.
 *  Flat resource amounts are scaled by era: value x 1.6^(age-1).
 *
 *  Effect ops (engine): res {stockpile deltas}, mod {temp modifiers
 *  for `duration` ticks}, pop (+/- population in a random city),
 *  hostiles (spawn raider units near borders), wreckBuilding
 *  (destroy a random building, optionally biome-filtered),
 *  armyDamage (all armies lose % hp), exhaustDeposit / findDeposit.
 *  `choice` events present two options instead of auto-applying.
 *  cond: atWar | coastal | hasBiome:<id> | hasBuilding:<id> |
 *        hasDeposit:<id> | minCities:<n>
 * ============================================================ */
'use strict';
(function () {
  const E = {}, LIST = [];
  function def(id, name, icon, weight, good, ages, fx, desc, opts = {}) {
    const e = Object.assign({
      id, name, icon, weight, good,
      minAge: ages[0], maxAge: ages[1],
      duration: fx.mod ? (fx.duration || 20) : 0,
      fx, desc, cond: null, choice: null,
    }, opts);
    if (E[id]) console.error('duplicate event id', id);
    E[id] = e; LIST.push(e);
  }

  /* ---------- economy & harvest ---------- */
  def('bumperHarvest', 'Bumper Harvest', '🌾', 10, true, [1, 8],
    { res: { food: 120 } },
    'Perfect rains and a gentle autumn. The granaries overflow.');
  def('drought', 'Drought', '☀️', 8, false, [1, 8],
    { mod: { food: -0.25 }, duration: 18 },
    'The rains fail. Rivers shrink to memory. -25% Food for 18 ticks.');
  def('goldVein', 'Gold Vein Struck', '⛏️', 6, true, [2, 8],
    { res: { gold: 150 } },
    'A miner\'s pick rings against something soft and yellow.',
    { cond: 'hasBuilding:mine' });
  def('tradeBoom', 'Trade Boom', '🪙', 8, true, [2, 8],
    { mod: { gold: 0.30 }, duration: 20 },
    'Foreign markets can\'t get enough of your goods. +30% Gold for 20 ticks.');
  def('recession', 'Recession', '📉', 7, false, [4, 8],
    { mod: { gold: -0.30 }, duration: 20 },
    'Credit tightens; ledgers bleed red. -30% Gold for 20 ticks.');
  def('inflation', 'Currency Debasement', '💸', 6, false, [2, 6],
    { res: { gold: -100 } },
    'Someone has been shaving the coins. Confidence — and treasury — shrink.');
  def('merchantCaravan', 'Wealthy Caravan', '🐪', 8, true, [1, 5],
    { res: { gold: 80, materials: 40 } },
    'A great caravan chooses your roads and pays handsomely for the privilege.');
  def('strike', 'General Strike', '✊', 6, false, [5, 8],
    { mod: { materials: -0.30 }, duration: 15 },
    'Tools down until demands are met. -30% Materials for 15 ticks.',
    { cond: 'hasBuilding:factory' });
  def('oilGlut', 'Oil Glut', '🛢️', 5, true, [6, 8],
    { res: { oil: 40, gold: 100 } },
    'Every well overperforms at once. Tanks brim; prices wobble.',
    { cond: 'hasDeposit:oilDep' });
  def('chipShortage', 'Chip Shortage', '💾', 5, false, [7, 8],
    { mod: { 'b:chipFab': -0.50 }, duration: 15 },
    'One flooded fab on the far side of the world, and everything stalls. -50% Chip Fab output.');

  /* ---------- nature & disaster ---------- */
  def('earthquake', 'Earthquake', '🌋', 5, false, [1, 8],
    { wreckBuilding: 1, res: { materials: -60 } },
    'The ground forgets its manners. A building is reduced to rubble.',
    { cond: 'hasBiome:mountain' });
  def('volcanicEruption', 'Volcanic Eruption', '🌋', 4, false, [1, 8],
    { wreckBuilding: 1, pop: -1, mod: { food: 0.15 }, duration: 30 },
    'Fire from below. Destruction now — but the ash will feed a generation. +15% Food afterward.',
    { cond: 'hasBiome:volcanic' });
  def('wildfire', 'Wildfire', '🔥', 6, false, [1, 8],
    { mod: { materials: -0.20 }, duration: 12 },
    'A wall of flame through the timberlands. -20% Materials for 12 ticks.',
    { cond: 'hasBiome:forest' });
  def('flood', 'Great Flood', '🌊', 6, false, [1, 8],
    { wreckBuilding: 1, res: { food: -60 } },
    'The river reclaims its plain and everything built on it.');
  def('harshWinter', 'Harsh Winter', '❄️', 6, false, [1, 8],
    { mod: { food: -0.15, moveSpeed: -0.25 }, duration: 12 },
    'Snow to the rooftops. Armies freeze in place; stores dwindle.');
  def('plague', 'Plague', '☠️', 6, false, [1, 5],
    { pop: -2, mod: { popGrowth: -0.50 }, duration: 25 },
    'It arrives with the traders and stays for years. Cities empty.',
    { cond: 'minCities:2' });
  def('pandemic', 'Pandemic', '🦠', 4, false, [6, 8],
    { pop: -1, mod: { popGrowth: -0.40, gold: -0.15 }, duration: 20 },
    'Airports spread it faster than rats ever could.');
  def('locustSwarm', 'Locust Swarm', '🦗', 6, false, [1, 6],
    { res: { food: -100 } },
    'The sky darkens and descends on the fields.');
  def('stormAtSea', 'Storm at Sea', '⛈️', 5, false, [1, 8],
    { armyDamage: 0.25 },
    'A once-a-century tempest. Fleets and embarked armies take 25% damage.',
    { cond: 'coastal' });
  def('solarFlare', 'Solar Flare', '☀️', 4, false, [7, 8],
    { mod: { science: -0.25, 'b:dataCenter': -0.50 }, duration: 10 },
    'The sun sneezes; the grid staggers. -25% Science for 10 ticks.');

  /* ---------- society & politics ---------- */
  def('goldenAge', 'Golden Age', '✨', 4, true, [2, 8],
    { mod: { food: 0.15, materials: 0.15, gold: 0.15, science: 0.15, influence: 0.15 }, duration: 25 },
    'Everything works at once. Historians will argue why for centuries. +15% to everything.');
  def('renaissanceFair', 'Grand Festival', '🎪', 8, true, [2, 8],
    { res: { influence: 60 }, mod: { popGrowth: 0.20 }, duration: 15 },
    'Feasting, games and marriages. The nation feels like one family.');
  def('religiousRevival', 'Religious Revival', '🕯️', 7, true, [1, 6],
    { mod: { influence: 0.30 }, duration: 20 },
    'Fervor sweeps the land. +30% Influence for 20 ticks.');
  def('civilUnrest', 'Civil Unrest', '🔥', 6, false, [2, 8],
    { mod: { influence: -0.30, gold: -0.10 }, duration: 15 },
    'Grievances boil over into the streets.');
  def('spyScandal', 'Spy Scandal', '🕵️', 6, false, [4, 8],
    { res: { influence: -80 } },
    'Your ambassador\'s letters, published. Everyone is Shocked.');
  def('refugeeWave', 'Refugee Wave', '🚶', 6, false, [2, 8],
    { }, 'War or famine abroad drives thousands to your borders.',
    { choice: [
      { label: 'Welcome them (+2 pop, -60 Influence)', fx: { pop: 2, res: { influence: -60 } } },
      { label: 'Turn them away (-40 Influence)', fx: { res: { influence: -40 } } },
    ] });
  def('greatThinker', 'A Great Thinker', '🧠', 6, true, [1, 8],
    { res: { science: 100 } },
    'Once in a generation, a mind that moves the whole species forward.');
  def('culturalIcon', 'Cultural Icon', '🎭', 6, true, [3, 8],
    { res: { influence: 80 } },
    'A poet, a painter, a voice — suddenly your nation is fashionable.');
  def('borderDispute', 'Border Dispute', '🚩', 6, false, [2, 8],
    { }, 'Farmers, then soldiers, argue over a boundary stone.',
    { choice: [
      { label: 'Press the claim (-50 Gold, +40 Influence)', fx: { res: { gold: -50, influence: 40 } } },
      { label: 'Concede quietly (-30 Influence)', fx: { res: { influence: -30 } } },
    ] });
  def('dynasticMarriage', 'Dynastic Marriage', '💍', 5, true, [2, 5],
    { res: { influence: 60, gold: 40 } },
    'Two houses joined; a border quietly relaxed.');

  /* ---------- military ---------- */
  def('barbarianRaid', 'Barbarian Raid', '🪓', 8, false, [1, 3],
    { hostiles: 2 },
    'Riders on the horizon, smoke behind them. Raiders spawn near your border.');
  def('piracy', 'Pirate Fleet', '🏴‍☠️', 6, false, [2, 7],
    { hostiles: 2, res: { gold: -60 } },
    'Your sea lanes fly someone else\'s flag today.',
    { cond: 'coastal' });
  def('veteranCadre', 'Veteran Cadre', '🎖️', 6, true, [1, 8],
    { mod: { atk: 0.20, def: 0.20 }, duration: 20 },
    'Old soldiers step forward to train the new. +20% combat strength for 20 ticks.');
  def('desertions', 'Desertions', '🏃', 5, false, [1, 8],
    { armyDamage: 0.15 },
    'Pay is late, boots are thin, home is far. Armies lose 15% strength.',
    { cond: 'atWar' });
  def('warBonds', 'War Bonds', '📜', 6, true, [5, 8],
    { res: { gold: 200 } },
    'The public buys victory on installment.',
    { cond: 'atWar' });
  def('armisticeMovement', 'Peace Movement', '🕊️', 5, false, [5, 8],
    { mod: { warWeariness: 0.30 }, duration: 20 },
    'Crowds fill the squares demanding the boys come home.',
    { cond: 'atWar' });

  /* ---------- discovery ---------- */
  def('newDeposit', 'Prospectors\' Find', '💎', 6, true, [2, 8],
    { findDeposit: true },
    'Surveyors return breathless: there is wealth under your soil. A new deposit appears in your territory.');
  def('depositExhausted', 'Deposit Exhausted', '⛏️', 4, false, [4, 8],
    { exhaustDeposit: true },
    'The seam pinches out. One of your deposits is gone for good.');
  def('ancientRuins', 'Ancient Ruins', '🏺', 6, true, [1, 4],
    { res: { science: 60, gold: 40 } },
    'Under the hill: an older city than yours, and its treasury.');
  def('techEspionage', 'Foreign Blueprints', '📐', 5, true, [4, 8],
    { res: { science: 120 } },
    'A defector arrives with a briefcase. You don\'t ask questions.');

  window.EVENTS = E;
  window.EVENT_LIST = LIST;
})();
