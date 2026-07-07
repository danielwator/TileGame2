/* ============================================================
 *  AEONS — Units (42)
 *
 *  class    : civilian | melee | ranged | cavalry | siege | naval | air
 *  cost     : { materials, gold?, oil?, circuits? }
 *  upkeep   : gold per tick
 *  atk/def  : combat strength (attack / defense)
 *  hp       : hit points (armies heal in friendly territory)
 *  move     : tiles per tick (fractional accumulates)
 *  sight    : fog-of-war reveal radius
 *  needs    : deposit id the nation must have improved (null = none)
 *  notes    : special rules
 * ============================================================ */
'use strict';
(function () {
  const U = {}, LIST = [];
  function def(id, name, tech, cls, cost, upkeep, atk, dfn, hp, move, sight, desc, opts = {}) {
    const u = Object.assign({
      id, name, tech, cls, cost, upkeep, atk, def: dfn, hp, move, sight, desc,
      needs: null, notes: null, siege: 1,
    }, opts);
    u.age = tech ? window.TECHS[tech].age : 1;
    if (U[id]) console.error('duplicate unit id', id);
    U[id] = u; LIST.push(u);
  }

  /* ---------- civilians (no tech) ---------- */
  def('settler', 'Settler', null, 'civilian', { materials: 60, gold: 20 }, 0.5,
    0, 1, 10, 0.5, 1,
    'Founds a new city (consumed). The most important unit in the game — escort it.',
    { notes: 'Founds city on any land tile that allows cities, 4+ tiles from another city.' });
  def('scout', 'Scout', null, 'civilian', { materials: 25 }, 0.2,
    1, 1, 15, 1.0, 2,
    'Fast eyes for the early game. Ignores terrain movement penalties.',
    { notes: 'Ignores terrain move costs.' });

  /* ---------- ancient ---------- */
  def('warrior', 'Warrior', 'warbands', 'melee', { materials: 40 }, 0.3,
    5, 5, 30, 0.5, 1, 'Club, hide shield and courage.');
  def('archer', 'Archer', 'archery', 'ranged', { materials: 45 }, 0.3,
    6, 3, 25, 0.5, 2, 'Harasses from a tile away.', { notes: 'Ranged: strikes adjacent tiles without taking counter-damage.' });
  def('spearman', 'Spearman', 'spearcraft', 'melee', { materials: 50 }, 0.3,
    6, 8, 32, 0.5, 1, 'Braced points. +50% defense vs cavalry.', { notes: '+50% vs cavalry.' });
  def('galley', 'Galley', 'sailing', 'naval', { materials: 55 }, 0.4,
    6, 5, 30, 1.0, 2, 'Coast-hugging oars. Cannot enter Ocean until The Compass.');

  /* ---------- classical ---------- */
  def('swordsman', 'Swordsman', 'swordsmanship', 'melee', { materials: 70, gold: 10 }, 0.4,
    10, 8, 38, 0.5, 1, 'Iron discipline. Requires Metal Ore.', { needs: 'metals' });
  def('horseman', 'Horseman', 'horsemanship', 'cavalry', { materials: 75, gold: 15 }, 0.5,
    11, 5, 34, 1.2, 2, 'Fast flanks and faster retreats. Requires Horses.', { needs: 'horses' });
  def('catapult', 'Catapult', 'siegecraft', 'siege', { materials: 85 }, 0.5,
    8, 3, 26, 0.4, 1, 'Stones versus walls.', { siege: 3, notes: '3x damage vs city defenses.' });
  def('trireme', 'Trireme', 'navalRams', 'naval', { materials: 80 }, 0.5,
    10, 7, 36, 1.2, 2, 'A bronze beak at ramming speed.');

  /* ---------- medieval ---------- */
  def('pikeman', 'Pikeman', 'feudalLevies', 'melee', { materials: 100 }, 0.5,
    12, 14, 45, 0.5, 1, 'A hedge of steel. +50% vs cavalry.', { notes: '+50% vs cavalry.' });
  def('knight', 'Knight', 'chivalry', 'cavalry', { materials: 130, gold: 40 }, 0.8,
    17, 10, 48, 1.2, 2, 'Shock aristocracy. Requires Horses and Metal Ore.', { needs: 'horses' });
  def('crossbowman', 'Crossbowman', 'crossbows', 'ranged', { materials: 110 }, 0.6,
    14, 6, 40, 0.5, 2, 'Armor-piercing bolts on a trigger.', { notes: 'Ranged.' });
  def('trebuchet', 'Trebuchet', 'siegeEngines', 'siege', { materials: 140 }, 0.8,
    13, 4, 32, 0.35, 1, 'Gravity as artillery.', { siege: 3, notes: '3x damage vs city defenses.' });
  def('cog', 'War Cog', 'warCogs', 'naval', { materials: 120 }, 0.7,
    14, 12, 48, 1.1, 2, 'Castles at sea.');

  /* ---------- renaissance ---------- */
  def('musketeer', 'Musketeer', 'gunpowder', 'melee', { materials: 170, gold: 30 }, 0.9,
    22, 18, 55, 0.5, 1, 'Pike and shot; the end of the knight.');
  def('cannon', 'Cannon', 'cannonry', 'siege', { materials: 200, gold: 50 }, 1.1,
    22, 6, 38, 0.4, 1, 'Bronze thunder.', { siege: 3, needs: 'metals', notes: '3x vs cities. Requires Metal Ore.' });
  def('cavalier', 'Cavalier', 'cavalryDoctrine', 'cavalry', { materials: 190, gold: 60 }, 1.1,
    26, 14, 58, 1.2, 2, 'Pistols, sabres, panache. Requires Horses.', { needs: 'horses' });
  def('caravel', 'Caravel', 'cartography', 'naval', { materials: 160, gold: 40 }, 0.9,
    16, 14, 50, 1.5, 3, 'The explorer\'s ship — crosses deep ocean.');
  def('frigate', 'Frigate', 'navalGunnery', 'naval', { materials: 220, gold: 60 }, 1.2,
    26, 18, 62, 1.4, 2, 'A broadside that settles arguments.');

  /* ---------- industrial ---------- */
  def('rifleman', 'Rifleman', 'rifling', 'melee', { materials: 300, gold: 60 }, 1.5,
    36, 30, 75, 0.6, 2, 'Bolt-action and khaki.');
  def('gatling', 'Gatling Team', 'gatlingGuns', 'ranged', { materials: 330, gold: 80 }, 1.7,
    38, 20, 65, 0.5, 2, 'Six barrels of arithmetic.', { notes: 'Ranged.' });
  def('artillery', 'Field Artillery', 'modernArtillery', 'siege', { materials: 360, gold: 100 }, 1.9,
    40, 10, 55, 0.45, 1, 'Fires from beyond retaliation.', { siege: 3, notes: '3x vs cities. Ranged.' });
  def('ironclad', 'Ironclad', 'ironclads', 'naval', { materials: 380, gold: 120 }, 2.0,
    40, 34, 85, 1.3, 2, 'Steam and armor plate. Consumes Coal to build.', { needs: 'coalDep' });

  /* ---------- modern ---------- */
  def('infantry', 'Infantry', 'modernInfantry', 'melee', { materials: 500, gold: 120 }, 2.4,
    55, 50, 100, 0.7, 2, 'The universal soldier.');
  def('tank', 'Tank', 'armoredWarfare', 'cavalry', { materials: 620, gold: 180, oil: 15 }, 3.0,
    75, 55, 110, 1.3, 2, 'Breakthrough in steel. Requires Oil.', { needs: 'oilDep' });
  def('fighter', 'Fighter', 'flight', 'air', { materials: 560, gold: 200, oil: 15 }, 3.0,
    65, 40, 80, 2.5, 3, 'Air superiority. Requires an Airfield in the training city.', { needs: 'oilDep', notes: 'Flies over any terrain. Cannot capture tiles.' });
  def('bomber', 'Bomber', 'strategicBombing', 'air', { materials: 680, gold: 240, oil: 20 }, 3.6,
    85, 25, 90, 2.2, 2, 'City-flattening payloads.', { needs: 'oilDep', siege: 4, notes: 'Flies. 4x vs cities. Cannot capture tiles.' });
  def('submarine', 'Submarine', 'submarineWarfare', 'naval', { materials: 600, gold: 200, oil: 15 }, 3.0,
    70, 35, 85, 1.4, 2, 'Invisible until the torpedo wake.', { needs: 'oilDep', notes: 'Hidden from enemies until adjacent.' });
  def('destroyer', 'Destroyer', 'modernNavy', 'naval', { materials: 640, gold: 220, oil: 18 }, 3.2,
    72, 60, 115, 1.6, 3, 'Fast escort, sub-hunter, jack of all trades.', { needs: 'oilDep' });

  /* ---------- information ---------- */
  def('mechInfantry', 'Mechanized Infantry', 'mechanizedInfantry', 'melee', { materials: 900, gold: 300, oil: 20 }, 4.5,
    95, 85, 150, 1.2, 2, 'Infantry at 60 km/h.', { needs: 'oilDep' });
  def('modernArmor', 'Modern Armor', 'compositeArmor', 'cavalry', { materials: 1100, gold: 400, oil: 30, circuits: 15 }, 5.5,
    130, 95, 170, 1.5, 2, 'Composite hulls, computed firing solutions.', { needs: 'oilDep' });
  def('jetFighter', 'Jet Fighter', 'jetAircraft', 'air', { materials: 1000, gold: 400, oil: 30, circuits: 10 }, 5.0,
    115, 70, 120, 3.0, 3, 'Mach 2 sovereignty.', { needs: 'oilDep', notes: 'Flies. Cannot capture tiles.' });
  def('missileLauncher', 'Missile Battery', 'guidedMissiles', 'siege', { materials: 1050, gold: 380, circuits: 15 }, 5.2,
    125, 30, 110, 0.8, 2, 'Precision at postal-code range.', { siege: 4, notes: '4x vs cities. Ranged.' });
  def('carrier', 'Aircraft Carrier', 'carrierGroups', 'naval', { materials: 1400, gold: 500, oil: 40, circuits: 20 }, 6.5,
    120, 90, 200, 1.5, 4, 'A floating airbase and the center of any fleet.', { needs: 'oilDep' });
  def('droneScout', 'Recon Drone', 'droneRecon', 'air', { materials: 700, gold: 250, circuits: 10 }, 3.0,
    20, 20, 60, 3.0, 4, 'Unblinking eyes, no crew to lose.', { notes: 'Flies. Huge sight radius. Cannot capture tiles.' });

  /* ---------- near future ---------- */
  def('exoInfantry', 'Exo-Infantry', 'powerArmor', 'melee', { materials: 1600, gold: 600, circuits: 30 }, 7.5,
    170, 150, 240, 1.3, 3, 'Powered armor squads that shrug off small arms.');
  def('droneSwarm', 'Drone Swarm', 'autonomousWeapons', 'air', { materials: 1500, gold: 550, circuits: 40 }, 7.0,
    180, 90, 160, 3.2, 4, 'A thousand small decisions, all hostile.', { notes: 'Flies. Cannot capture tiles.' });
  def('railgunArtillery', 'Railgun Artillery', 'railguns', 'siege', { materials: 1700, gold: 650, circuits: 40 }, 8.0,
    200, 50, 170, 0.9, 2, 'Hypervelocity slugs; the horizon is a suggestion.', { siege: 5, notes: '5x vs cities. Ranged.' });
  def('aegisCruiser', 'Aegis Cruiser', 'aegisSystems', 'naval', { materials: 1900, gold: 700, oil: 40, circuits: 50 }, 8.5,
    190, 170, 260, 1.7, 4, 'A shield over the whole fleet.', { needs: 'oilDep' });
  def('battleMech', 'Battle Mech', 'battleMechs', 'cavalry', { materials: 2100, gold: 800, circuits: 60 }, 9.5,
    240, 180, 300, 1.4, 3, 'The queen of the late-game battlefield.');

  /* ---- validation ---- */
  for (const u of LIST) {
    if (u.tech && !window.TECHS[u.tech]) console.error('unit ' + u.id + ' requires missing tech ' + u.tech);
    if (u.needs && !window.DEPOSITS[u.needs]) console.error('unit ' + u.id + ' needs missing deposit ' + u.needs);
  }
  for (const t of window.TECH_LIST) {
    if (t.unlockU) for (const id of t.unlockU) {
      if (!U[id]) console.error('tech ' + t.id + ' unlocks missing unit ' + id);
    }
  }

  window.UNITS = U;
  window.UNIT_LIST = LIST;
})();
