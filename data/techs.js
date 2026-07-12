/* ============================================================
 *  AEONS — Technology tree  (~290 techs, 8 ages x 6 branches)
 *
 *  Branches: agri (Agriculture), craft (Industry), mil (Military),
 *            com (Commerce), sci (Science), civ (Statecraft)
 *
 *  Each tech chains onto the previous tech of its branch unless
 *  an explicit `pre` override is given; `also` adds extra prereqs.
 *
 *  Effect vocabulary (applied by the game engine):
 *   mod:  { food|materials|gold|science|influence: +frac empire yield,
 *           'b:<buildingId>': +frac building output,
 *           claimCost, borderUpkeep, buildCost, unitCost, unitUpkeep,
 *           atk, def, siegeAtk, moveSpeed, popGrowth, healRate,
 *           warWeariness, eventLuck: +/- frac,
 *           vision, maxPolicies, tradeCap: +integer }
 *   flag: ['embark','oceanTravel','deepOcean','mountainPass','iceTravel',
 *          'buildOnWetland','terraceFarms','desertIrrigation','arcticFarms',
 *          'revealMap','scienceVictory']
 *   unlockB: [buildingIds]   unlockU: [unitIds]
 * ============================================================ */
'use strict';
(function () {
  const BASE = { 1: 30, 2: 65, 3: 130, 4: 260, 5: 520, 6: 950, 7: 1700, 8: 3000 };
  const BRANCHES = {
    agri:  { id: 'agri',  name: 'Agriculture', icon: '🌾', color: '#8fce5e' },
    craft: { id: 'craft', name: 'Industry',    icon: '⚒️', color: '#c9a45f' },
    mil:   { id: 'mil',   name: 'Military',    icon: '⚔️', color: '#e07a6a' },
    com:   { id: 'com',   name: 'Commerce',    icon: '🪙', color: '#f2c94c' },
    sci:   { id: 'sci',   name: 'Science',     icon: '⚗️', color: '#5eb9ce' },
    civ:   { id: 'civ',   name: 'Statecraft',  icon: '👑', color: '#b48ce0' },
  };

  const T = {}, LIST = [];
  const last = {};                 // branch -> id of last defined tech
  const chainIdx = {};             // `${age}:${branch}` -> index within age

  function def(age, branch, id, name, fx, desc, opts = {}) {
    const key = age + ':' + branch;
    const idx = chainIdx[key] || 0;
    chainIdx[key] = idx + 1;
    const pre = opts.pre !== undefined ? opts.pre.slice() : (last[branch] ? [last[branch]] : []);
    if (opts.also) pre.push(...opts.also);
    const t = {
      id, name, age, branch,
      cost: Math.round(BASE[age] * (1 + 0.16 * idx) * (opts.cost || 1)),
      pre,
      mod: fx.mod || null,
      flag: fx.flag || null,
      unlockB: fx.unlockB || null,
      unlockU: fx.unlockU || null,
      desc,
    };
    if (T[id]) console.error('duplicate tech id', id);
    T[id] = t; LIST.push(t);
    last[branch] = id;
  }

  /* ================= AGE 1 — ANCIENT ================= */
  def(1,'agri','hunting','Hunting',{unlockB:['huntingCamp']},'Organized hunts turn wild herds into steady meals.');
  def(1,'agri','agriculture','Agriculture',{unlockB:['farm']},'Deliberate sowing — the single greatest gamble in history.');
  def(1,'agri','animalHusbandry','Animal Husbandry',{unlockB:['pasture']},'Tamed beasts give milk, wool and muscle. Reveals Horses.');
  def(1,'agri','fishing','Fishing',{unlockB:['fishery']},'Nets and weirs harvest the shallows.',{pre:['hunting']});
  def(1,'agri','irrigation','Irrigation',{mod:{'b:farm':0.25}},'Ditches carry the river to the field.',{pre:['agriculture']});
  def(1,'agri','pottery','Pottery',{unlockB:['granary'],mod:{food:0.05,cityTiles:1}},'Sealed jars defeat rot and rats. +1 city tile.');
  def(1,'craft','toolmaking','Toolmaking',{mod:{materials:0.05}},'Flint, bone and antler shaped to purpose.');
  def(1,'craft','woodworking','Woodworking',{unlockB:['lumberCamp']},'Axes bite; timber becomes wall and hull.');
  def(1,'craft','masonry','Masonry',{unlockB:['quarry'],mod:{cityTiles:1}},'Dressed stone outlives its maker. +1 city tile.');
  def(1,'craft','wheel','The Wheel',{mod:{moveSpeed:0.10}},'Everything heavy suddenly rolls.');
  def(1,'craft','bronzeWorking','Bronze Working',{unlockB:['mine'],mod:{materials:0.05}},'Copper and tin marry into weapons-grade metal. Reveals Metal Ore.');
  def(1,'craft','tanning','Tanning',{mod:{def:0.05}},'Hides become armor, straps and tents.');
  def(1,'mil','warbands','Warbands',{unlockU:['warrior'],unlockB:['barracks']},'The first organized violence.');
  def(1,'mil','archery','Archery',{unlockU:['archer']},'Death at a distance changes every argument.');
  def(1,'mil','spearcraft','Spearcraft',{unlockU:['spearman']},'A wall of points stops a charge cold.');
  def(1,'mil','palisades','Palisades',{mod:{def:0.05}},'Sharpened logs buy time when raiders come.');
  def(1,'mil','bronzeArms','Bronze Arms',{mod:{atk:0.10}},'Bronze blades bite deeper than stone.',{also:['bronzeWorking']});
  def(1,'mil','raiding','Raiding',{mod:{unitCost:-0.10}},'War pays for itself — if you win.');
  def(1,'com','barter','Barter',{mod:{gold:0.05}},'Grain for pots, pots for goats.');
  def(1,'com','weightsMeasures','Weights & Measures',{mod:{gold:0.05}},'Honest scales make repeat customers.');
  def(1,'com','tradeCaravans','Trade Caravans',{mod:{tradeCap:1}},'Strings of pack animals link distant peoples.');
  def(1,'com','salting','Salt Preservation',{mod:{food:0.05,gold:0.05}},'Salt turns surplus into wealth that keeps.');
  def(1,'com','tribute','Tribute',{mod:{influence:0.10}},'Lesser chiefs pay for protection — or else.');
  def(1,'com','dyeworks','Dyeworks',{mod:{gold:0.05}},'Purple cloth is worth its weight in silver.');
  def(1,'sci','starGazing','Star Gazing',{mod:{science:0.05}},'Patterns in the night sky repay patient watching.');
  def(1,'sci','counting','Counting',{mod:{science:0.05}},'Tallies on bone become arithmetic.');
  def(1,'sci','herbalism','Herbalism',{mod:{healRate:0.25}},'Which leaf soothes and which one kills.');
  def(1,'sci','writing','Writing',{mod:{science:0.10,researchOptions:1}},'Memory outsourced to clay. Everything changes. +1 research option to choose from.');
  def(1,'sci','sailing','Sailing',{unlockU:['galley'],flag:['embark']},'Wind does the rowing. Land units may embark onto coastal waters.');
  def(1,'sci','calendars','Calendars',{mod:{food:0.10}},'Knowing when to plant is half the harvest.');
  def(1,'civ','tribalCouncil','Tribal Council',{mod:{maxPolicies:1}},'Elders argue so warriors don\'t have to. Unlocks the first policy slot.');
  def(1,'civ','ancestorWorship','Ancestor Worship',{unlockB:['shrine']},'The dead advise the living.');
  def(1,'civ','customLaw','Customary Law',{mod:{influence:0.05}},'Precedent settles quarrels before they fester.');
  def(1,'civ','chiefdom','Chiefdom',{mod:{claimCost:-0.10}},'One voice speaks for the tribe — and its lands.');
  def(1,'civ','ritualBurial','Ritual Burial',{mod:{influence:0.05}},'Shared rites bind the community.');
  def(1,'civ','warriorCode','Warrior Code',{mod:{atk:0.05}},'Honor makes soldiers hold the line.');

  /* ================= AGE 2 — CLASSICAL ================= */
  def(2,'agri','fallowing','Fallowing',{mod:{'b:farm':0.25}},'Rested fields yield double.');
  def(2,'agri','aqueducts','Aqueducts',{unlockB:['aqueduct'],mod:{cityTiles:1}},'Cities drink from mountains a valley away. +1 city tile.');
  def(2,'agri','viticulture','Viticulture',{mod:{food:0.05,gold:0.05}},'Vines turn hillsides into festivals.');
  def(2,'agri','beekeeping','Beekeeping',{mod:{food:0.05}},'Sweetness, wax and better harvests.');
  def(2,'agri','fishSalting','Fish Salting',{mod:{'b:fishery':0.25}},'Fleets can now feed inland cities.');
  def(2,'agri','terraceFarming','Terrace Farming',{flag:['terraceFarms']},'Steps carved into hills. Farms may be built on Highlands.');
  def(2,'craft','ironWorking','Iron Working',{mod:{atk:0.10,'b:mine':0.25}},'Iron is everywhere once you know how to ask.');
  def(2,'craft','carpentry','Carpentry',{mod:{buildCost:-0.05}},'Joinery raises roofs faster and truer.');
  def(2,'craft','concreteWork','Concrete',{unlockB:['workshop']},'Liquid stone poured into any shape.');
  def(2,'craft','glassblowing','Glassblowing',{mod:{gold:0.05}},'Sand becomes windows, vessels and lenses.');
  def(2,'craft','millstones','Millstones',{mod:{food:0.10}},'Grinding grain at scale frees a hundred hands.');
  def(2,'craft','roadBuilding','Road Building',{mod:{moveSpeed:0.15}},'All roads lead somewhere profitable.');
  def(2,'mil','formationTactics','Formation Tactics',{mod:{def:0.10}},'The phalanx is greater than the sum of its spears.');
  def(2,'mil','swordsmanship','Swordsmanship',{unlockU:['swordsman']},'A sidearm becomes a profession.',{also:['ironWorking']});
  def(2,'mil','horsemanship','Horsemanship',{unlockU:['horseman']},'Cavalry arrives before the news of it does.');
  def(2,'mil','siegecraft','Siegecraft',{unlockU:['catapult']},'Walls stop being an answer.');
  def(2,'mil','navalRams','Naval Rams',{unlockU:['trireme']},'Warships built to sink, not just carry.');
  def(2,'mil','fortifications','Fortifications',{unlockB:['walls']},'Stone curtains around everything you love.');
  def(2,'com','currency','Currency',{unlockB:['market'],mod:{gold:0.10}},'Stamped metal that everyone trusts. Reveals Gems.');
  def(2,'com','moneylending','Moneylending',{mod:{gold:0.05}},'Money today for more money tomorrow.');
  def(2,'com','portTrade','Port Trade',{unlockB:['port']},'Harbors where cargo and rumor change hands.');
  def(2,'com','taxation','Taxation',{mod:{gold:0.10}},'The one certainty besides death.');
  def(2,'com','caravanserai','Caravanserai',{mod:{tradeCap:1}},'Safe lodging doubles the caravan routes.');
  def(2,'com','luxuryTrade','Luxury Trade',{mod:{gold:0.05,influence:0.05}},'Silk and spice buy prestige abroad.');
  def(2,'sci','philosophy','Philosophy',{unlockB:['library'],mod:{science:0.10}},'Asking why, professionally.');
  def(2,'sci','mathematics','Mathematics',{mod:{science:0.10}},'The universe turns out to be written in it.');
  def(2,'sci','astronomy','Astronomy',{mod:{science:0.05,moveSpeed:0.05}},'Stars become a map for ships and seasons.');
  def(2,'sci','classicalMedicine','Classical Medicine',{mod:{healRate:0.25}},'Observation replaces exorcism, mostly.');
  def(2,'sci','literature','Literature',{mod:{influence:0.10}},'Epics carry your name past every border.');
  def(2,'sci','engineering','Engineering',{mod:{buildCost:-0.05}},'Cranes, levers and arrogance.');
  def(2,'civ','cityStates','City States',{mod:{claimCost:-0.10,cityTiles:1}},'The city becomes an idea worth dying for. +1 city tile.');
  def(2,'civ','monarchy','Monarchy',{mod:{influence:0.10,maxPolicies:1}},'One crown to answer every question.');
  def(2,'civ','stateReligion','State Religion',{unlockB:['temple']},'The gods take a side — yours.');
  def(2,'civ','citizenship','Citizenship',{mod:{popGrowth:0.10}},'Belonging becomes a legal status worth having.');
  def(2,'civ','drama','Drama & Games',{unlockB:['amphitheater']},'Bread is only half of it.');
  def(2,'civ','republic','Republic',{mod:{maxPolicies:1}},'Power on a rotating schedule.');

  /* ================= AGE 3 — MEDIEVAL ================= */
  def(3,'agri','heavyPlough','Heavy Plough',{mod:{'b:farm':0.25}},'Iron shares turn heavy northern clay to bread.');
  def(3,'agri','cropRotation','Crop Rotation',{mod:{food:0.10}},'Three fields, endless cycle, no famine.');
  def(3,'agri','horseCollar','Horse Collar',{mod:{'b:pasture':0.25}},'A padded strap doubles every draft animal.');
  def(3,'agri','drainage','Drainage',{flag:['buildOnWetland']},'Ditches and dikes. Buildings may be constructed on Wetlands.');
  def(3,'agri','windmills','Windmills',{unlockB:['windmill']},'The sky grinds your grain for free.');
  def(3,'agri','fishponds','Fishponds',{mod:{'b:fishery':0.25}},'Fresh fish on demand, even far from the sea.');
  def(3,'craft','metalCasting','Metal Casting',{unlockB:['forge']},'Molten metal poured into moulds — bells and cannon alike.');
  def(3,'craft','sawmilling','Sawmilling',{unlockB:['sawmill']},'Water-driven blades never tire.');
  def(3,'craft','masonsGuild','Masons\' Guilds',{mod:{buildCost:-0.10}},'Craft secrets, apprentices and cathedral-grade skill.');
  def(3,'craft','shipwrights','Shipwrights',{unlockB:['harbor']},'Purpose-built yards launch bigger hulls.');
  def(3,'craft','charcoalBurning','Charcoal Burning',{mod:{materials:0.10}},'Forests condensed into furnace fuel.');
  def(3,'craft','clockwork','Clockwork',{mod:{science:0.05,gold:0.05}},'Gears that measure time itself.');
  def(3,'mil','feudalLevies','Feudal Levies',{unlockU:['pikeman'],mod:{unitUpkeep:-0.10}},'Land for service — an army you don\'t pay in coin.');
  def(3,'mil','chivalry','Chivalry',{unlockU:['knight']},'Armored aristocracy on horseback.');
  def(3,'mil','crossbows','Crossbows',{unlockU:['crossbowman']},'A week of training defeats a lifetime of armor.');
  def(3,'mil','castles','Castles',{unlockB:['castle'],mod:{cityTiles:1}},'A stone answer to every question of ownership. +1 city tile.');
  def(3,'mil','siegeEngines','Siege Engines',{unlockU:['trebuchet']},'Counterweights hurl the sky at walls.');
  def(3,'mil','warCogs','War Cogs',{unlockU:['cog']},'High-sided merchantmen turned floating forts.');
  def(3,'com','guilds','Guilds',{unlockB:['guildHall'],mod:{cityTiles:1}},'Monopoly, quality control and mutual aid in one charter. +1 city tile.');
  def(3,'com','letterOfCredit','Letters of Credit',{mod:{gold:0.10}},'Paper promises move fortunes past bandits.');
  def(3,'com','fairs','Trade Fairs',{mod:{tradeCap:1,gold:0.05}},'A season of commerce in a fortnight.');
  def(3,'com','silkRoad','Silk Road',{unlockB:['tradePost']},'The desert becomes a highway of silk and spice.');
  def(3,'com','hanse','Merchant Leagues',{mod:{'b:harbor':0.25}},'Port cities band together and set the prices.');
  def(3,'com','mintStandards','Mint Standards',{mod:{gold:0.10}},'Sound coinage everyone can trust.');
  def(3,'sci','monasticism','Monasticism',{unlockB:['monastery']},'Quiet halls copy the wisdom of ages.');
  def(3,'sci','universities','Universities',{unlockB:['university']},'Degrees, debates and dangerous ideas.');
  def(3,'sci','algebra','Algebra',{mod:{science:0.10}},'Unknowns get names and surrender.');
  def(3,'sci','opticLenses','Optic Lenses',{mod:{vision:1}},'Ground glass extends the eye. +1 vision range.');
  def(3,'sci','compass','The Compass',{flag:['oceanTravel']},'A needle that always knows north. Ships may enter Ocean tiles.');
  def(3,'sci','papermaking','Papermaking',{mod:{science:0.10}},'Knowledge gets cheap enough to spread.');
  def(3,'civ','feudalContract','Feudal Contract',{mod:{maxPolicies:1}},'Obligations all the way up and down.');
  def(3,'civ','commonLaw','Common Law',{mod:{influence:0.10,claimCost:-0.05}},'Same rules in every shire.');
  def(3,'civ','royalCourts','Royal Courts',{mod:{influence:0.10}},'Splendor is statecraft.');
  def(3,'civ','pilgrimage','Pilgrimage Routes',{mod:{influence:0.05,gold:0.05}},'Faith travels, and spends.');
  def(3,'civ','heraldry','Heraldry',{mod:{atk:0.05}},'Banners tell soldiers what they fight for.');
  def(3,'civ','magnaCarta','Great Charter',{mod:{influence:0.10}},'Even the crown signs contracts now.');

  /* ================= AGE 4 — RENAISSANCE ================= */
  def(4,'agri','newWorldCrops','New World Crops',{mod:{food:0.15}},'Potatoes and maize rewrite the food math.');
  def(4,'agri','enclosures','Enclosures',{mod:{'b:farm':0.25}},'Hedged fields, higher yields, displaced peasants.');
  def(4,'agri','selectiveBreeding','Selective Breeding',{mod:{'b:pasture':0.25}},'Livestock engineered by patience.');
  def(4,'agri','plantations','Plantations',{unlockB:['plantation']},'Cash crops at colonial scale.');
  def(4,'agri','botany','Botany',{mod:{food:0.05,science:0.05}},'Plants catalogued, crossed and conquered.');
  def(4,'agri','cashCrops','Cash Crops',{mod:{'b:plantation':0.25}},'Sugar, tobacco, cotton — sweet, addictive profit.');
  def(4,'craft','printingPress','Printing Press',{unlockB:['printworks']},'Arguments at industrial volume.');
  def(4,'craft','manufactories','Manufactories',{unlockB:['manufactory'],mod:{cityTiles:1}},'Many hands under one roof, one process. +1 city tile.');
  def(4,'craft','advancedMetallurgy','Advanced Metallurgy',{mod:{materials:0.10}},'Blast furnaces and boring machines.');
  def(4,'craft','shipframes','Ship Framing',{unlockB:['shipyard']},'Skeleton-first construction launches leviathans.');
  def(4,'craft','instrumentMaking','Instrument Making',{mod:{science:0.10}},'Precision tools for precision thoughts.');
  def(4,'craft','waterMills','Water Mills',{mod:{materials:0.10}},'Rivers put to work around the clock.');
  def(4,'mil','gunpowder','Gunpowder',{unlockU:['musketeer']},'Chemistry ends the age of armor.');
  def(4,'mil','cannonry','Cannonry',{unlockU:['cannon']},'Castles become quaint overnight.',{also:['advancedMetallurgy']});
  def(4,'mil','bastionForts','Bastion Forts',{unlockB:['fortress']},'Star-shaped geometry against the cannonball.');
  def(4,'mil','cavalryDoctrine','Cavalry Doctrine',{unlockU:['cavalier']},'Pistol, sabre and shock.');
  def(4,'mil','navalGunnery','Naval Gunnery',{unlockU:['frigate']},'The broadside is diplomacy\'s exclamation mark.');
  def(4,'mil','professionalArmy','Professional Army',{mod:{unitUpkeep:-0.10,atk:0.05}},'Drilled, salaried, always ready.');
  def(4,'com','banking','Banking',{unlockB:['bank']},'Money that earns money while you sleep.');
  def(4,'com','jointStock','Joint-Stock Companies',{mod:{tradeCap:1,gold:0.10}},'Risk chopped into shares and sold.');
  def(4,'com','insurance','Insurance',{mod:{gold:0.10}},'Catastrophe priced by actuaries.');
  def(4,'com','customsAndExcise','Customs & Excise',{unlockB:['customsHouse']},'Every border crossing pays its toll.');
  def(4,'com','tradeCompanies','Chartered Companies',{mod:{claimCost:-0.10}},'Private empires with public flags.');
  def(4,'com','colonialTrade','Colonial Trade',{mod:{gold:0.15}},'Triangle routes and treasure fleets.');
  def(4,'sci','scientificMethod','Scientific Method',{mod:{science:0.15,researchOptions:1}},'Test it or toss it. +1 research option to choose from.');
  def(4,'sci','heliocentrism','Heliocentrism',{unlockB:['observatory']},'The Earth is demoted; science is promoted.',{also:['instrumentMaking']});
  def(4,'sci','anatomy','Anatomy',{mod:{healRate:0.25}},'Medicine finally looks inside.');
  def(4,'sci','cartography','Cartography',{unlockU:['caravel'],flag:['deepOcean']},'Charts tame the abyss. Ships may cross Deep Ocean.');
  def(4,'sci','mechanics','Mechanics',{mod:{science:0.10}},'Force, mass and motion get equations.');
  def(4,'sci','earlyChemistry','Early Chemistry',{mod:{science:0.10}},'Alchemy sobers up.');
  def(4,'civ','renaissanceArt','Renaissance Art',{unlockB:['theater'],mod:{influence:0.10}},'Beauty as a state asset.');
  def(4,'civ','embassies','Embassies',{mod:{influence:0.15}},'Permanent ears in every court.');
  def(4,'civ','absolutism','Absolutism',{mod:{maxPolicies:1}},'L\'état, c\'est moi.');
  def(4,'civ','humanism','Humanism',{mod:{science:0.05,popGrowth:0.05}},'Man becomes the measure.');
  def(4,'civ','tolerance','Religious Tolerance',{mod:{influence:0.10}},'Heretics pay taxes too.');
  def(4,'civ','civilService','Civil Service',{mod:{claimCost:-0.10,borderUpkeep:-0.10,cityTiles:1}},'Exams, files and a state that remembers. +1 city tile.');

  /* ================= AGE 5 — INDUSTRIAL ================= */
  def(5,'agri','seedDrills','Seed Drills',{mod:{'b:farm':0.25}},'Rows, not scatter. Yields jump.');
  def(5,'agri','fertilizers','Fertilizers',{mod:{food:0.15}},'Guano, nitrates and the end of fallow fields.');
  def(5,'agri','canning','Canning',{mod:{food:0.10}},'Armies march on tinned rations.');
  def(5,'agri','refrigeration','Refrigeration',{mod:{food:0.15}},'Distance stops spoiling dinner.');
  def(5,'agri','steamTrawlers','Steam Trawlers',{mod:{'b:fishery':0.25}},'Engines drag the nets now.');
  def(5,'agri','veterinaryScience','Veterinary Science',{mod:{'b:pasture':0.25}},'Herds get doctors of their own.');
  def(5,'craft','steamPower','Steam Power',{unlockB:['coalMine']},'Boiling water moves the world. Reveals Coal.');
  def(5,'craft','factories','Factory System',{unlockB:['factory']},'Steam-driven mass production. Consumes Coal.');
  def(5,'craft','steelmaking','Steelmaking',{unlockB:['steelworks'],mod:{materials:0.10}},'Bessemer\'s converter makes steel cheap as iron.');
  def(5,'craft','railways','Railways',{unlockB:['railDepot'],mod:{moveSpeed:0.25,cityTiles:1}},'The countryside shrinks to a timetable. +1 city tile.');
  def(5,'craft','machineTools','Machine Tools',{mod:{buildCost:-0.10}},'Machines that make machines.');
  def(5,'craft','telegraphy','Telegraphy',{unlockB:['telegraphOffice']},'News outruns the horse at last.');
  def(5,'mil','rifling','Rifling',{unlockU:['rifleman']},'Spin stabilization makes every soldier a marksman.');
  def(5,'mil','modernArtillery','Modern Artillery',{unlockU:['artillery']},'Indirect fire from beyond the horizon.');
  def(5,'mil','ironclads','Ironclads',{unlockU:['ironclad']},'Wooden navies are obsolete by lunchtime.');
  def(5,'mil','gatlingGuns','Gatling Guns',{unlockU:['gatling']},'Arithmetic applied to infantry charges.');
  def(5,'mil','militaryScience','Military Science',{unlockB:['militaryAcademy']},'Staff colleges study war like a subject.');
  def(5,'mil','logistics','Logistics',{mod:{moveSpeed:0.15,unitUpkeep:-0.10}},'Amateurs discuss tactics; professionals discuss supply.');
  def(5,'com','stockExchanges','Stock Exchanges',{unlockB:['stockExchange']},'Capital finds ambition in seconds.');
  def(5,'com','industrialBanking','Industrial Banking',{mod:{gold:0.15}},'Banks big enough to fund railroads.');
  def(5,'com','departmentStores','Department Stores',{mod:{gold:0.10}},'Everything under one gaslit roof.');
  def(5,'com','freeTrade','Free Trade',{mod:{tradeCap:1}},'Tariffs fall; hulls fill.');
  def(5,'com','corporations','Corporations',{mod:{gold:0.15}},'Immortal persons made of paper.');
  def(5,'com','advertising','Advertising',{mod:{gold:0.05,influence:0.05}},'Manufacturing desire itself.');
  def(5,'sci','publicEducation','Public Education',{unlockB:['publicSchool']},'Literacy becomes infrastructure.');
  def(5,'sci','germTheory','Germ Theory',{unlockB:['hospital'],mod:{healRate:0.25,popGrowth:0.10}},'The invisible enemy finally has a name.');
  def(5,'sci','electricity','Electricity',{mod:{science:0.15}},'Lightning in a copper leash.');
  def(5,'sci','thermodynamics','Thermodynamics',{mod:{science:0.10}},'You can\'t win, you can\'t break even.');
  def(5,'sci','naturalHistory','Natural History',{mod:{science:0.10}},'Deep time and descent with modification.');
  def(5,'sci','sanitation','Sanitation',{unlockB:['sewers'],mod:{popGrowth:0.10,cityTiles:1}},'Cities stop poisoning themselves. +1 city tile.');
  def(5,'civ','nationalism','Nationalism',{mod:{influence:0.15,warWeariness:-0.10}},'The tribe, industrialized.');
  def(5,'civ','laborMovements','Labor Movements',{mod:{materials:0.10}},'Eight hours\' work deserves eight hours\' rest.');
  def(5,'civ','constitution','Constitutionalism',{mod:{maxPolicies:1}},'The rules above the rulers.');
  def(5,'civ','emancipation','Emancipation',{mod:{popGrowth:0.10,influence:0.05}},'Liberty extends its franchise.');
  def(5,'civ','journalism','Mass Journalism',{mod:{influence:0.10}},'The fourth estate opens for business.');
  def(5,'civ','imperialDoctrine','Imperial Doctrine',{mod:{claimCost:-0.15}},'Maps colored with entitlement.');

  /* ================= AGE 6 — MODERN ================= */
  def(6,'agri','mechanizedFarming','Mechanized Farming',{unlockB:['mechanizedFarm']},'One tractor replaces forty field hands.');
  def(6,'agri','syntheticFertilizer','Synthetic Fertilizer',{mod:{food:0.15}},'Bread pulled from thin air (and natural gas).');
  def(6,'agri','pesticides','Pesticides',{mod:{food:0.10}},'Chemistry versus the locust.');
  def(6,'agri','industrialFishing','Industrial Fishing',{mod:{'b:fishery':0.25}},'Factory ships that vacuum the sea.');
  def(6,'agri','cropHybrids','Crop Hybrids',{mod:{food:0.15}},'The Green Revolution begins.');
  def(6,'agri','foodProcessing','Food Processing',{mod:{food:0.10,gold:0.05}},'Shelf-stable everything.');
  def(6,'craft','combustion','Combustion Engines',{unlockB:['oilWell']},'Portable power in a steel block. Reveals Oil.');
  def(6,'craft','assemblyLines','Assembly Lines',{mod:{materials:0.15,unitCost:-0.10}},'The product moves; the worker doesn\'t.');
  def(6,'craft','plastics','Plastics',{mod:{materials:0.10}},'Any shape, any color, forever.');
  def(6,'craft','oilRefining','Oil Refining',{unlockB:['refinery']},'Crude cracked into fuel, tar and money.');
  def(6,'craft','electricGrid','Electric Grid',{unlockB:['powerPlant'],mod:{cityTiles:1}},'Power on tap in every district. Consumes Coal. +1 city tile.');
  def(6,'craft','offshoreDrilling','Offshore Drilling',{unlockB:['offshorePlatform']},'Chasing oil beneath the waves.');
  def(6,'mil','modernInfantry','Modern Infantry',{unlockU:['infantry']},'Squad weapons, radios and doctrine.');
  def(6,'mil','armoredWarfare','Armored Warfare',{unlockU:['tank']},'Cavalry reborn in welded steel. Consumes Oil.');
  def(6,'mil','flight','Military Aviation',{unlockU:['fighter'],unlockB:['airfield']},'The high ground rises to 10,000 meters.');
  def(6,'mil','strategicBombing','Strategic Bombing',{unlockU:['bomber']},'War arrives over the factory district.');
  def(6,'mil','submarineWarfare','Submarine Warfare',{unlockU:['submarine']},'Terror by periscope.');
  def(6,'mil','modernNavy','Modern Navy',{unlockU:['destroyer']},'Fast, gray and bristling.');
  def(6,'com','consumerEconomy','Consumer Economy',{unlockB:['mall']},'Prosperity measured in shopping bags.');
  def(6,'com','centralBanking','Central Banking',{mod:{gold:0.15}},'A thermostat for the whole economy.');
  def(6,'com','internationalTrade','International Trade',{mod:{tradeCap:1,gold:0.10}},'Containers standardize the planet.');
  def(6,'com','tourism','Tourism',{mod:{gold:0.10,influence:0.05}},'Your landmarks become industries.');
  def(6,'com','creditSystems','Consumer Credit',{mod:{gold:0.10}},'Buy now, pay later, forever.');
  def(6,'com','petrochemicalMarkets','Petrochemical Markets',{mod:{'b:oilWell':0.25}},'Black gold gets a futures desk.');
  def(6,'sci','radio','Radio',{unlockB:['broadcastTower'],mod:{influence:0.10}},'One voice in a million living rooms.');
  def(6,'sci','atomicTheory','Atomic Theory',{mod:{science:0.15}},'Matter\'s smallest pieces, biggest implications.');
  def(6,'sci','antibiotics','Antibiotics',{mod:{healRate:0.50,popGrowth:0.10}},'Infection loses its death sentence.');
  def(6,'sci','industrialResearch','Industrial R&D',{unlockB:['researchLab']},'Invention becomes a department.');
  def(6,'sci','rocketry','Rocketry',{mod:{science:0.10}},'Pointed at the sky, for now.');
  def(6,'sci','publicHealth','Public Health',{unlockB:['waterTreatment'],mod:{popGrowth:0.10,cityTiles:1}},'Clean water saves more lives than any drug. +1 city tile.');
  def(6,'civ','suffrage','Universal Suffrage',{mod:{influence:0.10,maxPolicies:1}},'Everyone gets a lever.');
  def(6,'civ','propaganda','Propaganda',{mod:{warWeariness:-0.20}},'Morale, manufactured.');
  def(6,'civ','welfareState','Welfare State',{mod:{popGrowth:0.10}},'The state catches those who fall.');
  def(6,'civ','internationalism','Internationalism',{mod:{influence:0.15}},'Leagues, nations, united.');
  def(6,'civ','civilDefense','Civil Defense',{mod:{def:0.10}},'Sirens, shelters and drills.');
  def(6,'civ','totalMobilization','Total Mobilization',{mod:{unitCost:-0.15}},'The whole economy reports for duty.');

  /* ================= AGE 7 — INFORMATION ================= */
  def(7,'agri','precisionAgriculture','Precision Agriculture',{mod:{'b:farm':0.25}},'Satellites plan every furrow.');
  def(7,'agri','gmoCrops','GMO Crops',{mod:{food:0.20}},'The genome becomes farmland.');
  def(7,'agri','aquaculture','Aquaculture',{unlockB:['trawlerDock']},'Fish farmed like wheat.');
  def(7,'agri','coldChain','Global Cold Chain',{mod:{food:0.10}},'Strawberries in winter, everywhere.');
  def(7,'agri','desertIrrigation','Desert Irrigation',{flag:['desertIrrigation']},'Drip lines green the dunes. Farms may be built on Desert.');
  def(7,'agri','sustainableFarming','Sustainable Farming',{mod:{food:0.10,eventLuck:0.05}},'Farming that plans past the quarter.');
  def(7,'craft','semiconductors','Semiconductors',{unlockB:['chipFab']},'Sand that thinks. Reveals Rare Earths; Chip Fabs produce Circuits.');
  def(7,'craft','robotics','Robotics',{mod:{materials:0.15}},'Tireless arms on the factory floor.');
  def(7,'craft','composites','Composite Materials',{mod:{materials:0.10,buildCost:-0.10}},'Lighter than aluminum, stronger than steel.');
  def(7,'craft','recycling','Recycling Systems',{unlockB:['recyclingPlant']},'Yesterday\'s scrap is tomorrow\'s stock.');
  def(7,'craft','renewables','Renewable Energy',{unlockB:['solarFarm','windFarm']},'Power without smoke.');
  def(7,'craft','automation','Industrial Automation',{mod:{'b:factory':0.25,unitCost:-0.10}},'Lights-out manufacturing.');
  def(7,'mil','guidedMissiles','Guided Missiles',{unlockU:['missileLauncher']},'Ordnance with a mailing address.');
  def(7,'mil','jetAircraft','Jet Aircraft',{unlockU:['jetFighter']},'The sound barrier surrenders.');
  def(7,'mil','mechanizedInfantry','Mechanized Infantry',{unlockU:['mechInfantry']},'Riflemen at highway speed.');
  def(7,'mil','compositeArmor','Composite Armor',{unlockU:['modernArmor']},'Layered ceramics shrug off shells. Consumes Oil + Circuits.');
  def(7,'mil','carrierGroups','Carrier Groups',{unlockU:['carrier']},'A mobile piece of national territory.');
  def(7,'mil','droneRecon','Drone Reconnaissance',{unlockU:['droneScout']},'Eyes that never blink or sleep.');
  def(7,'com','electronicBanking','Electronic Banking',{mod:{gold:0.15}},'Money becomes weightless.');
  def(7,'com','globalization','Globalization',{mod:{tradeCap:2,gold:0.10}},'One planet, one supply chain.');
  def(7,'com','ecommerce','E-Commerce',{mod:{gold:0.15}},'The whole bazaar in your pocket.');
  def(7,'com','ventureCapital','Venture Capital',{mod:{science:0.10,gold:0.05}},'Betting big on clever people.');
  def(7,'com','commercialAviation','Commercial Aviation',{unlockB:['airport'],mod:{tradeCap:1}},'Anywhere on Earth by dinnertime.');
  def(7,'com','serviceEconomy','Service Economy',{mod:{gold:0.10}},'Wealth from work you can\'t drop on your foot.');
  def(7,'sci','computers','Computers',{unlockB:['dataCenter'],mod:{science:0.15,researchOptions:1,cityTiles:1}},'Arithmetic at the speed of light. +1 research option to choose from. +1 city tile.');
  def(7,'sci','internet','The Internet',{unlockB:['mediaNetwork'],mod:{science:0.15,influence:0.10}},'Everyone talks to everyone, about everything.');
  def(7,'sci','satellites','Satellites',{mod:{vision:2},flag:['revealMap']},'The whole globe on one screen. Reveals the world map.');
  def(7,'sci','polarScience','Polar Science',{unlockB:['polarResearchStation'],flag:['iceTravel']},'Icebreakers open the last frontier. Units may cross Ice Caps.');
  def(7,'sci','genetics','Genetics',{mod:{healRate:0.25,popGrowth:0.10}},'The instruction manual for life, annotated.');
  def(7,'sci','academicNetworks','Academic Networks',{unlockB:['techCampus']},'Universities merge into research ecosystems.');
  def(7,'civ','massMedia','Mass Media',{mod:{influence:0.15}},'The narrative becomes the territory.');
  def(7,'civ','internationalLaw','International Law',{mod:{influence:0.10,claimCost:-0.10}},'Treaties with teeth, occasionally.');
  def(7,'civ','environmentalism','Environmentalism',{mod:{food:0.05,eventLuck:0.05}},'The planet gets a seat at the table.');
  def(7,'civ','digitalGovernance','Digital Governance',{mod:{maxPolicies:1,cityTiles:1}},'Bureaucracy at broadband speed. +1 city tile.');
  def(7,'civ','softPower','Soft Power',{mod:{influence:0.15}},'Culture conquers where armies can\'t.');
  def(7,'civ','openSociety','Open Society',{mod:{science:0.10,influence:0.05}},'Freedom turns out to be productive.');

  /* ================= AGE 8 — NEAR FUTURE ================= */
  def(8,'agri','verticalFarming','Vertical Farming',{unlockB:['verticalFarm']},'Forty stories of lettuce downtown.');
  def(8,'agri','syntheticProteins','Synthetic Proteins',{mod:{food:0.20}},'Steak without the steer.');
  def(8,'agri','arcticAgriculture','Arctic Agriculture',{flag:['arcticFarms']},'Engineered crops shrug off the frost. Farms may be built on Tundra.');
  def(8,'agri','oceanFarming','Ocean Farming',{mod:{'b:trawlerDock':0.25,food:0.10}},'Kelp forests planted like orchards.');
  def(8,'agri','soilEngineering','Soil Engineering',{mod:{food:0.15}},'Dead dirt brought back to life.');
  def(8,'agri','closedLoopFood','Closed-Loop Food Systems',{mod:{food:0.15}},'Nothing wasted, ever.');
  def(8,'craft','fusionPower','Fusion Power',{unlockB:['fusionPlant']},'A star in a bottle. Consumes Circuits.');
  def(8,'craft','nanomaterials','Nanomaterials',{mod:{materials:0.20}},'Matter engineered atom by atom.');
  def(8,'craft','roboticFactories','Robotic Factories',{unlockB:['roboticFactory']},'Factories that never open the lights.');
  def(8,'craft','deepMining','Deep Crust Mining',{unlockB:['deepMine']},'Boreholes to the mantle\'s doorstep.');
  def(8,'craft','seasteading','Seasteading',{unlockB:['seasteadPlatform']},'Cities that float. Build on Coastal Waters.');
  def(8,'craft','smartGrids','Smart Grids',{mod:{'b:powerPlant':0.25,'b:solarFarm':0.25}},'Every watt routed by algorithm.');
  def(8,'mil','powerArmor','Power Armor',{unlockU:['exoInfantry']},'One soldier, one walking fortress.');
  def(8,'mil','autonomousWeapons','Autonomous Weapons',{unlockU:['droneSwarm']},'The operator is now optional.');
  def(8,'mil','railguns','Railguns',{unlockU:['railgunArtillery']},'Mach 7 answers to strategic questions.');
  def(8,'mil','aegisSystems','Aegis Systems',{unlockU:['aegisCruiser']},'A fleet under one shield.');
  def(8,'mil','battleMechs','Battle Mechs',{unlockU:['battleMech']},'Armor learns to walk.');
  def(8,'mil','orbitalRecon','Orbital Recon',{mod:{vision:2}},'Nothing on the surface hides.');
  def(8,'com','cryptoFinance','Crypto Finance',{mod:{gold:0.15}},'Trust, decentralized and volatile.');
  def(8,'com','fusionEconomy','Fusion Economy',{mod:{gold:0.10,materials:0.10}},'Energy too cheap to argue about.');
  def(8,'com','spaceTourism','Space Tourism',{mod:{gold:0.15,influence:0.10}},'The view is worth the ticket.');
  def(8,'com','automatedLogistics','Automated Logistics',{mod:{tradeCap:2}},'Cargo that routes itself.');
  def(8,'com','postScarcityMarkets','Post-Scarcity Markets',{mod:{gold:0.20}},'Economics after abundance.');
  def(8,'com','orbitalManufacturing','Orbital Manufacturing',{mod:{materials:0.15}},'Zero-g foundries, flawless crystals.');
  def(8,'sci','quantumComputing','Quantum Computing',{unlockB:['quantumLab'],mod:{science:0.20}},'Every answer at once, briefly.');
  def(8,'sci','aiResearch','Artificial Intelligence',{mod:{science:0.20,'b:dataCenter':0.25}},'The tool that improves itself.');
  def(8,'sci','lifeExtension','Life Extension',{mod:{popGrowth:0.15,healRate:0.50}},'Aging, negotiated downward.');
  def(8,'sci','climateEngineering','Climate Engineering',{unlockB:['climateController'],mod:{food:0.10}},'The thermostat of last resort.');
  def(8,'sci','spaceElevator','Space Elevator',{unlockB:['orbitalElevator']},'A ribbon to orbit; the price of space drops to freight.');
  def(8,'sci','unifiedPhysics','Unified Physics',{mod:{science:0.25}},'One equation to bind them all.');
  def(8,'civ','globalGovernance','Global Governance',{mod:{influence:0.20,maxPolicies:1}},'Humanity\'s HOA.');
  def(8,'civ','digitalDemocracy','Digital Democracy',{mod:{influence:0.15}},'The agora, redistributed.');
  def(8,'civ','universalBasicIncome','Universal Basic Income',{mod:{popGrowth:0.10,influence:0.10}},'A floor under every citizen.');
  def(8,'civ','arcologies','Arcologies',{unlockB:['arcology'],mod:{cityTiles:2}},'A city in a single building. +2 city tiles.');
  def(8,'civ','planetaryUnion','Planetary Union',{mod:{claimCost:-0.20,borderUpkeep:-0.20}},'Borders begin to feel old-fashioned.');
  def(8,'civ','ascensionProgram','Ascension Program',{flag:['scienceVictory']},'Begin the Starlight Ark project — the path to Science Victory.');

  /* ---- validation ---- */
  for (const t of LIST) {
    for (const p of t.pre) {
      if (!T[p]) console.error('tech ' + t.id + ' has missing prereq ' + p);
    }
  }

  window.TECHS = T;
  window.TECH_LIST = LIST;
  window.TECH_BRANCHES = BRANCHES;
})();
