/* ============================================================
 *  AEONS — Buildings (~76)
 *
 *  Every building occupies one tile inside your borders within
 *  range 3 of one of your cities. One building per tile.
 *  Each building needs 1 population in its city to work at 100%.
 *
 *  Fields:
 *   tech     : required technology (null = available from start)
 *   cost     : { materials, gold?, coal?, oil?, circuits? } to build
 *   time     : build time in ticks
 *   upkeep   : gold per tick
 *   yields   : output per tick at 100% (before biome & tech modifiers)
 *   consumes : inputs per tick (building idles if unpaid)
 *   place    : { on:[biomes] | 'land' | 'water', coastalOnly?, deposit? }
 *              'land' = any passable land biome a city can use;
 *              tech flags can extend placement (see techFlags)
 *   biomeMul : per-biome output multiplier (default 1)
 *   techFlags: { biomeId: flag } — biome allowed only with tech flag
 *   defense  : added city defense when in city radius
 *   housing  : +max population for the owning city
 *   unique   : 'city' = one per city, 'nation' = one per nation
 * ============================================================ */
'use strict';
(function () {
  const B = {}, LIST = [];
  function def(id, name, tech, cost, time, upkeep, yields, place, desc, opts = {}) {
    const b = Object.assign({
      id, name, tech, cost, time, upkeep, yields, place, desc,
      consumes: null, biomeMul: null, techFlags: null,
      defense: 0, housing: 0, unique: null,
    }, opts);
    b.age = tech ? window.TECHS[tech].age : 1;
    if (B[id]) console.error('duplicate building id', id);
    B[id] = b; LIST.push(b);
  }
  const LAND = 'land';

  /* ---------- special ---------- */
  def('cityCenter', 'City Center', null, { materials: 0 }, 0, 0,
    { food: 2, materials: 2, gold: 1, science: 1, influence: 0.5 }, { on: LAND },
    'The beating heart of a settlement. Founded by Settlers; produces a little of everything and claims the surrounding tiles.',
    { defense: 10, housing: 5, unique: 'city' });

  /* ================= ANCIENT ================= */
  def('huntingCamp', 'Hunting Camp', 'hunting', { materials: 25 }, 6, 0.1,
    { food: 2 }, { on: ['forest', 'boreal', 'tundra', 'savanna', 'rainforest', 'steppe'] },
    'Smokehouses and snare lines. Best where Wild Game roams.',
    { biomeMul: { boreal: 1.25, savanna: 1.25 } });
  def('farm', 'Farm', 'agriculture', { materials: 30 }, 6, 0.1,
    { food: 3 }, { on: ['grassland', 'plains', 'savanna', 'volcanic'] },
    'Tilled fields. The foundation of every empire — but only where soil and rain allow.',
    { biomeMul: { grassland: 1.3, volcanic: 1.4, savanna: 0.85, desert: 0.6, highlands: 0.7, wetland: 1.1, tundra: 0.5 },
      techFlags: { highlands: 'terraceFarms', wetland: 'buildOnWetland', desert: 'desertIrrigation', tundra: 'arcticFarms' } });
  def('pasture', 'Pasture', 'animalHusbandry', { materials: 30 }, 6, 0.1,
    { food: 2, materials: 1 }, { on: ['grassland', 'plains', 'steppe', 'savanna', 'tundra', 'highlands'] },
    'Herds on the hoof. Steppe nomads swear by it; a Horses deposit makes it strategic.',
    { biomeMul: { steppe: 1.3, tundra: 0.75 } });
  def('fishery', 'Fishery', 'fishing', { materials: 30 }, 6, 0.1,
    { food: 3 }, { on: ['coast', 'lake'] },
    'Boats, nets and drying racks on a water tile. Fish Shoals double the catch.');
  def('quarry', 'Quarry', 'masonry', { materials: 35 }, 7, 0.2,
    { materials: 3 }, { on: ['highlands', 'plains', 'desert', 'tundra', 'steppe', 'volcanic'] },
    'Cut stone for walls and wonders. Stone deposits boost it further.',
    { biomeMul: { highlands: 1.25 } });
  def('lumberCamp', 'Lumber Camp', 'woodworking', { materials: 30 }, 6, 0.1,
    { materials: 3 }, { on: ['forest', 'boreal', 'rainforest'] },
    'Axes and log flumes. Boreal forests are the best timberland on the planet.',
    { biomeMul: { boreal: 1.3, rainforest: 0.8 } });
  def('granary', 'Granary', 'pottery', { materials: 40 }, 8, 0.2,
    { food: 1 }, { on: LAND },
    'Sealed storage against rot and raiders. +2 max population.',
    { housing: 2, unique: 'city' });
  def('shrine', 'Shrine', 'ancestorWorship', { materials: 35 }, 7, 0.2,
    { influence: 1 }, { on: LAND },
    'A sacred site binding the people to their land and leaders.');
  def('barracks', 'Barracks', 'warbands', { materials: 45 }, 8, 0.3,
    { }, { on: LAND },
    'Drill yards and armories. Land units trained in this city start with +25% experience and cost 10% less.',
    { unique: 'city', defense: 3 });
  def('mine', 'Mine', 'bronzeWorking', { materials: 45 }, 8, 0.3,
    { materials: 4 }, { on: ['highlands', 'mountain', 'volcanic', 'desert', 'tundra'] },
    'Shafts chasing veins into the dark. Requires rugged terrain; Metal Ore, Gems and Rare Earths all boost it.',
    { biomeMul: { mountain: 1.3, volcanic: 1.2 }, techFlags: { mountain: 'mountainPass' } });

  /* ================= CLASSICAL ================= */
  def('aqueduct', 'Aqueduct', 'aqueducts', { materials: 60 }, 10, 0.4,
    { food: 1 }, { on: LAND },
    'Fresh water for fountains and fields. +3 max population.',
    { housing: 3, unique: 'city' });
  def('workshop', 'Workshop', 'concreteWork', { materials: 65 }, 10, 0.4,
    { materials: 4 }, { on: LAND },
    'Artisans under one roof turning raw stock into finished goods.');
  def('walls', 'City Walls', 'fortifications', { materials: 80 }, 12, 0.4,
    { }, { on: LAND },
    'Stone fortifications. +15 city defense.',
    { defense: 15, unique: 'city' });
  def('market', 'Market', 'currency', { materials: 60 }, 10, 0.3,
    { gold: 3 }, { on: LAND },
    'Stalls, scales and haggling. The tax base begins here.',
    { biomeMul: { desert: 1.25, steppe: 1.2 } });
  def('library', 'Library', 'philosophy', { materials: 70 }, 11, 0.5,
    { science: 3 }, { on: LAND },
    'Scrolls and scholars. Knowledge compounds like interest.');
  def('temple', 'Temple', 'stateReligion', { materials: 75 }, 11, 0.5,
    { influence: 2 }, { on: LAND },
    'Marble devotion. Faith legitimizes borders like nothing else.');
  def('amphitheater', 'Amphitheater', 'drama', { materials: 70 }, 11, 0.5,
    { influence: 1.5, gold: 1 }, { on: LAND },
    'Spectacle keeps citizens loyal and visitors spending.',
    { unique: 'city' });
  def('port', 'Port', 'portTrade', { materials: 70 }, 11, 0.4,
    { gold: 2, food: 1 }, { on: ['coast'] },
    'Wharves and warehouses on a coastal water tile. Naval units may be trained by this city.');

  /* ================= MEDIEVAL ================= */
  def('windmill', 'Windmill', 'windmills', { materials: 90 }, 12, 0.5,
    { food: 2, materials: 1 }, { on: ['plains', 'grassland', 'steppe', 'coast'] },
    'Grinds grain wherever the wind blows steady.',
    { biomeMul: { plains: 1.25 } });
  def('sawmill', 'Sawmill', 'sawmilling', { materials: 95 }, 12, 0.5,
    { materials: 5 }, { on: ['forest', 'boreal', 'rainforest'] },
    'Water-powered blades. Upgrade over the lumber camp.',
    { biomeMul: { boreal: 1.25, rainforest: 0.8 } });
  def('forge', 'Forge', 'metalCasting', { materials: 100 }, 13, 0.6,
    { materials: 5 }, { on: LAND },
    'Bellows and anvils. Metal Ore within your borders makes it +25% productive.');
  def('castle', 'Castle', 'castles', { materials: 140 }, 16, 0.8,
    { influence: 1 }, { on: LAND },
    'Feudal power in stone. +25 city defense and a statement to the neighbors.',
    { defense: 25, unique: 'city' });
  def('guildHall', 'Guild Hall', 'guilds', { materials: 100, gold: 30 }, 13, 0.6,
    { gold: 4 }, { on: LAND },
    'Charters, monopolies and member dues.',
    { unique: 'city' });
  def('monastery', 'Monastery', 'monasticism', { materials: 95 }, 12, 0.5,
    { science: 2, influence: 1 }, { on: LAND },
    'Scriptoria in quiet places. Thrives in remote terrain.',
    { biomeMul: { highlands: 1.25, tundra: 1.25, boreal: 1.2 } });
  def('university', 'University', 'universities', { materials: 130, gold: 40 }, 15, 0.8,
    { science: 5 }, { on: LAND },
    'Lecture halls and rivalries. The engine of the late game starts here.',
    { unique: 'city' });
  def('harbor', 'Harbor', 'shipwrights', { materials: 110 }, 13, 0.6,
    { gold: 3, food: 2 }, { on: ['coast'] },
    'Deep moorings and cranes. Upgrade over the port for oceangoing trade.');
  def('tradePost', 'Trade Post', 'silkRoad', { materials: 90, gold: 30 }, 12, 0.4,
    { gold: 4 }, { on: ['desert', 'steppe', 'savanna', 'tundra'] },
    'A caravanserai on the long routes. Deserts turn from obstacle to asset.',
    { biomeMul: { desert: 1.5, steppe: 1.25 } });

  /* ================= RENAISSANCE ================= */
  def('plantation', 'Plantation', 'plantations', { materials: 150, gold: 50 }, 15, 0.8,
    { gold: 4, food: 1 }, { on: ['savanna', 'rainforest', 'grassland', 'plains'] },
    'Cash crops in ordered rows. Fertile Soil boosts it; rainforests suit it best.',
    { biomeMul: { rainforest: 1.3, savanna: 1.2 } });
  def('printworks', 'Printing Works', 'printingPress', { materials: 160 }, 16, 0.9,
    { science: 4, influence: 2 }, { on: LAND },
    'Movable type spreads your ideas — and your propaganda.',
    { unique: 'city' });
  def('manufactory', 'Manufactory', 'manufactories', { materials: 180 }, 18, 1.0,
    { materials: 7 }, { on: LAND },
    'Pre-industrial mass production under one roof.');
  def('observatory', 'Observatory', 'heliocentrism', { materials: 160, gold: 40 }, 16, 0.9,
    { science: 5 }, { on: ['highlands', 'mountain'] },
    'Clear high-altitude skies. Mountains become temples of science.',
    { biomeMul: { mountain: 1.4 }, techFlags: { mountain: 'mountainPass' } });
  def('shipyard', 'Shipyard', 'shipframes', { materials: 170 }, 17, 0.9,
    { materials: 3, gold: 2 }, { on: ['coast'] },
    'Slipways for warships. Naval units from this city are 20% cheaper.');
  def('fortress', 'Fortress', 'bastionForts', { materials: 220 }, 20, 1.2,
    { }, { on: LAND },
    'Star-fort geometry. +40 city defense.',
    { defense: 40, unique: 'city' });
  def('bank', 'Bank', 'banking', { materials: 170, gold: 80 }, 16, 0.8,
    { gold: 6 }, { on: LAND },
    'Vaults, ledgers and compound interest.',
    { unique: 'city' });
  def('customsHouse', 'Customs House', 'customsAndExcise', { materials: 150, gold: 60 }, 15, 0.8,
    { gold: 5 }, { on: LAND },
    'Every crossing pays. Coastal cities profit most.',
    { biomeMul: { } });
  def('theater', 'Theater', 'renaissanceArt', { materials: 160, gold: 50 }, 16, 0.9,
    { influence: 3, gold: 1 }, { on: LAND },
    'Culture with box-office receipts.',
    { unique: 'city' });

  /* ================= INDUSTRIAL ================= */
  def('coalMine', 'Coal Mine', 'steamPower', { materials: 240 }, 18, 1.2,
    { coal: 3, materials: 1 }, { on: LAND, deposit: 'coalDep' },
    'Shafts into the carboniferous. Requires a Coal deposit; feeds factories and fleets.');
  def('factory', 'Factory', 'factories', { materials: 300 }, 22, 1.5,
    { materials: 10 }, { on: LAND },
    'Steam-driven mass production. Consumes 1 Coal per tick — idle without it.',
    { consumes: { coal: 1 } });
  def('steelworks', 'Steelworks', 'steelmaking', { materials: 320 }, 22, 1.5,
    { materials: 8, gold: 2 }, { on: LAND },
    'Bessemer converters. Consumes 1 Coal; Metal Ore within borders boosts output 25%.',
    { consumes: { coal: 1 } });
  def('railDepot', 'Rail Depot', 'railways', { materials: 280 }, 20, 1.4,
    { gold: 4, materials: 3 }, { on: LAND },
    'A junction of iron roads. Units trained in this city move 15% faster.',
    { unique: 'city' });
  def('stockExchange', 'Stock Exchange', 'stockExchanges', { materials: 260, gold: 150 }, 20, 1.2,
    { gold: 9 }, { on: LAND },
    'Fortunes made and unmade by the closing bell.',
    { unique: 'city' });
  def('publicSchool', 'Public School', 'publicEducation', { materials: 240, gold: 80 }, 18, 1.2,
    { science: 7 }, { on: LAND },
    'Universal literacy: the greatest research multiplier ever built.',
    { unique: 'city' });
  def('hospital', 'Hospital', 'germTheory', { materials: 260, gold: 100 }, 20, 1.4,
    { food: 1 }, { on: LAND },
    'Wards and antiseptics. +4 max population and faster army healing nearby.',
    { housing: 4, unique: 'city' });
  def('militaryAcademy', 'Military Academy', 'militaryScience', { materials: 280, gold: 120 }, 20, 1.4,
    { }, { on: LAND },
    'Officers with diplomas. Units from this city start with +50% experience.',
    { unique: 'city', defense: 10 });
  def('sewers', 'Sewers', 'sanitation', { materials: 220 }, 18, 1.0,
    { }, { on: LAND },
    'Unglamorous, undefeated. +4 max population.',
    { housing: 4, unique: 'city' });
  def('telegraphOffice', 'Telegraph Office', 'telegraphy', { materials: 200, gold: 80 }, 16, 1.0,
    { influence: 3, science: 2 }, { on: LAND },
    'Orders and news at lightspeed (minus the last mile).',
    { unique: 'city' });

  /* ================= MODERN ================= */
  def('oilWell', 'Oil Well', 'combustion', { materials: 380 }, 22, 2.0,
    { oil: 3 }, { on: LAND, deposit: 'oilDep' },
    'A derrick nodding over an Oil Field. The strategic resource of the century.');
  def('offshorePlatform', 'Offshore Platform', 'offshoreDrilling', { materials: 520, gold: 200 }, 26, 2.5,
    { oil: 4 }, { on: ['coast', 'ocean'], deposit: 'oilDep' },
    'Drilling through the seabed. Requires an offshore Oil Field.');
  def('powerPlant', 'Power Plant', 'electricGrid', { materials: 450 }, 25, 2.2,
    { materials: 8, gold: 4, science: 2 }, { on: LAND },
    'Coal-fired electricity. Consumes 1 Coal; every district hums.',
    { consumes: { coal: 1 } });
  def('refinery', 'Oil Refinery', 'oilRefining', { materials: 420, gold: 150 }, 24, 2.2,
    { gold: 8, materials: 4 }, { on: LAND },
    'Crude in, money out. Consumes 1 Oil per tick.',
    { consumes: { oil: 1 } });
  def('researchLab', 'Research Laboratory', 'industrialResearch', { materials: 420, gold: 180 }, 24, 2.4,
    { science: 10 }, { on: LAND },
    'White coats and patent filings.',
    { unique: 'city' });
  def('broadcastTower', 'Broadcast Tower', 'radio', { materials: 360, gold: 120 }, 22, 1.8,
    { influence: 5 }, { on: LAND },
    'Your anthem on every frequency.',
    { unique: 'city', biomeMul: { mountain: 1.3, highlands: 1.2 }, techFlags: { mountain: 'mountainPass' } });
  def('airfield', 'Airfield', 'flight', { materials: 400 }, 24, 2.0,
    { }, { on: ['plains', 'grassland', 'steppe', 'desert', 'savanna', 'tundra'] },
    'Runways and hangars. Required to train air units; extends unit vision +2 around it.',
    { unique: 'city' });
  def('mechanizedFarm', 'Mechanized Farm', 'mechanizedFarming', { materials: 380, gold: 100 }, 22, 1.8,
    { food: 8 }, { on: ['grassland', 'plains', 'savanna', 'steppe'] },
    'Tractors and combine harvesters. Consumes 1 Oil per tick.',
    { consumes: { oil: 1 }, biomeMul: { grassland: 1.25 } });
  def('mall', 'Shopping Mall', 'consumerEconomy', { materials: 380, gold: 200 }, 22, 2.0,
    { gold: 10 }, { on: LAND },
    'Climate-controlled commerce.',
    { unique: 'city' });
  def('waterTreatment', 'Water Treatment Plant', 'publicHealth', { materials: 340 }, 20, 1.6,
    { }, { on: LAND },
    'Clean water at municipal scale. +5 max population.',
    { housing: 5, unique: 'city' });

  /* ================= INFORMATION ================= */
  def('chipFab', 'Chip Fabricator', 'semiconductors', { materials: 800, gold: 400 }, 30, 4.0,
    { circuits: 2 }, { on: LAND },
    'Cleanrooms etching silicon. Consumes 4 Materials + 2 Gold per tick and requires a Rare Earth deposit inside your borders. The only source of Circuits.',
    { consumes: { materials: 4, gold: 2 }, requiresNationDeposit: 'rareEarth' });
  def('dataCenter', 'Data Center', 'computers', { materials: 700, gold: 300, circuits: 20 }, 28, 3.5,
    { science: 14 }, { on: LAND },
    'Racks of humming knowledge. Cold climates halve the cooling bill (+25% in Tundra/Boreal).',
    { biomeMul: { tundra: 1.25, boreal: 1.25 } });
  def('techCampus', 'Tech Campus', 'academicNetworks', { materials: 650, gold: 350, circuits: 15 }, 28, 3.2,
    { science: 10, gold: 5 }, { on: LAND },
    'Where startups and seminars share a parking lot.',
    { unique: 'city' });
  def('solarFarm', 'Solar Farm', 'renewables', { materials: 550, circuits: 10 }, 24, 2.0,
    { materials: 6, gold: 6 }, { on: ['desert', 'savanna', 'steppe', 'plains'] },
    'Mirrors drinking sunlight. Deserts become power-houses.',
    { biomeMul: { desert: 1.5, savanna: 1.2 } });
  def('windFarm', 'Wind Farm', 'renewables', { materials: 550, circuits: 10 }, 24, 2.0,
    { materials: 6, gold: 4 }, { on: ['coast', 'plains', 'highlands', 'steppe', 'tundra'] },
    'Turbines on ridge and shore.',
    { biomeMul: { coast: 1.3, highlands: 1.25 } });
  def('recyclingPlant', 'Recycling Plant', 'recycling', { materials: 500, gold: 200 }, 24, 2.2,
    { materials: 9 }, { on: LAND },
    'The landfill becomes a mine.',
    { unique: 'city' });
  def('mediaNetwork', 'Media Network', 'internet', { materials: 600, gold: 300, circuits: 15 }, 26, 3.0,
    { influence: 8 }, { on: LAND },
    'Every screen in the world is your embassy.',
    { unique: 'city' });
  def('polarResearchStation', 'Polar Research Station', 'polarScience', { materials: 650, gold: 250, circuits: 10 }, 26, 3.0,
    { science: 12 }, { on: ['iceCap', 'tundra'] },
    'Science at the end of the world — the only building possible on Ice Caps.',
    { biomeMul: { iceCap: 1.3 } });
  def('airport', 'International Airport', 'commercialAviation', { materials: 700, gold: 400 }, 28, 3.5,
    { gold: 12, influence: 3 }, { on: ['plains', 'grassland', 'steppe', 'desert', 'savanna', 'tundra'] },
    'Hub status: achieved. +1 trade route capacity for your nation.',
    { unique: 'city' });
  def('satelliteUplink', 'Satellite Uplink', 'satellites', { materials: 600, gold: 300, circuits: 20 }, 26, 3.0,
    { science: 8, influence: 4 }, { on: LAND },
    'Dishes tracking a private constellation.',
    { unique: 'city' });
  def('trawlerDock', 'Trawler Dock', 'aquaculture', { materials: 520, gold: 150 }, 24, 2.2,
    { food: 10 }, { on: ['coast', 'ocean'] },
    'Industrial aquaculture pens. Fish Shoals double the harvest.');

  /* ================= NEAR FUTURE ================= */
  def('fusionPlant', 'Fusion Plant', 'fusionPower', { materials: 1400, gold: 600, circuits: 60 }, 36, 5.0,
    { materials: 14, gold: 10, science: 5 }, { on: LAND },
    'A tokamak sunrise. Consumes 2 Circuits per tick and outproduces every other power source.',
    { consumes: { circuits: 2 } });
  def('verticalFarm', 'Vertical Farm', 'verticalFarming', { materials: 1100, gold: 400, circuits: 40 }, 32, 4.0,
    { food: 16 }, { on: LAND },
    'Crops stacked to the sky. Works in any climate — the end of famine.',
    { consumes: { circuits: 1 } });
  def('roboticFactory', 'Robotic Factory', 'roboticFactories', { materials: 1300, gold: 500, circuits: 50 }, 34, 4.5,
    { materials: 20 }, { on: LAND },
    'Zero workers, zero breaks. Consumes 2 Circuits per tick.',
    { consumes: { circuits: 2 } });
  def('quantumLab', 'Quantum Lab', 'quantumComputing', { materials: 1300, gold: 600, circuits: 60 }, 34, 5.0,
    { science: 22 }, { on: LAND },
    'Refrigerators colder than deep space, thoughts faster than light.',
    { consumes: { circuits: 1 }, unique: 'city' });
  def('deepMine', 'Deep Crust Mine', 'deepMining', { materials: 1200, gold: 400, circuits: 40 }, 32, 4.5,
    { materials: 16, gold: 4 }, { on: ['mountain', 'highlands', 'volcanic'] },
    'Kilometers down, past every exhausted seam. Any deposit on this tile yields double.',
    { techFlags: { mountain: 'mountainPass' } });
  def('seasteadPlatform', 'Seastead Platform', 'seasteading', { materials: 1200, gold: 500, circuits: 40 }, 34, 4.5,
    { food: 8, gold: 8, materials: 6 }, { on: ['coast'] },
    'A floating district anchored offshore. The sea becomes suburbia.',
    { housing: 3 });
  def('climateController', 'Climate Controller', 'climateEngineering', { materials: 1500, gold: 700, circuits: 80 }, 40, 6.0,
    { food: 10, influence: 5 }, { on: LAND },
    'Weather by committee. Shields your nation from climate-type random events.',
    { unique: 'nation' });
  def('arcology', 'Arcology', 'arcologies', { materials: 1600, gold: 800, circuits: 80 }, 40, 6.0,
    { food: 6, materials: 6, gold: 6, science: 6, influence: 4 }, { on: LAND },
    'A vertical city of a million souls. +10 max population.',
    { housing: 10, unique: 'city' });
  def('orbitalElevator', 'Orbital Elevator', 'spaceElevator', { materials: 2200, gold: 1200, circuits: 150 }, 50, 8.0,
    { science: 15, gold: 10, influence: 8 }, { on: LAND },
    'The stairway to the stars — and a prerequisite of the Starlight Ark. One per nation; must stand within 15° of the equator.',
    { unique: 'nation', equatorial: true });

  /* ---- validation ---- */
  for (const b of LIST) {
    if (b.tech && !window.TECHS[b.tech]) console.error('building ' + b.id + ' requires missing tech ' + b.tech);
  }
  // every tech unlockB must exist
  for (const t of window.TECH_LIST) {
    if (t.unlockB) for (const id of t.unlockB) {
      if (!B[id]) console.error('tech ' + t.id + ' unlocks missing building ' + id);
    }
  }

  window.BUILDINGS = B;
  window.BUILDING_LIST = LIST;
})();
