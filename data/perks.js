/* ============================================================
 *  AEONS — Nation Perks (24)
 *
 *  Each time a nation advances to a new age it picks 1 perk from
 *  3 random offers (7 picks over a full game). Perks are permanent
 *  and stack with techs and policies.
 * ============================================================ */
'use strict';
(function () {
  const P = {}, LIST = [];
  function def(id, name, icon, mod, desc, opts = {}) {
    const p = Object.assign({ id, name, icon, mod, desc, minAge: 2, flag: null }, opts);
    if (P[id]) console.error('duplicate perk id', id);
    P[id] = p; LIST.push(p);
  }

  def('fertileCrescent', 'Children of the Soil', '🌾',
    { food: 0.15 }, 'Your farmers coax bread from stone. +15% Food, forever.');
  def('forgeMasters', 'Forge Masters', '⚒️',
    { materials: 0.15 }, 'Craft runs in the blood. +15% Materials.');
  def('merchantPrinces', 'Merchant Princes', '🪙',
    { gold: 0.15 }, 'Everything has a price; you set it. +15% Gold.');
  def('philosopherKings', 'Philosopher Kings', '⚗️',
    { science: 0.15 }, 'Rulers who read. +15% Science.');
  def('bornDiplomats', 'Born Diplomats', '👑',
    { influence: 0.15 }, 'Words win what wars would waste. +15% Influence.');
  def('expansionists', 'Expansionists', '🗺️',
    { claimCost: -0.20 }, 'The horizon is a to-do list. -20% tile claim cost.');
  def('frontierSpirit', 'Frontier Spirit', '🏕️',
    { borderUpkeep: -0.25 }, 'Distance means nothing to your settlers. -25% border upkeep.');
  def('greatBuilders', 'Great Builders', '🏛️',
    { buildCost: -0.15 }, 'Monuments rise in months, not decades. -15% construction cost.');
  def('warriorBlood', 'Warrior Blood', '⚔️',
    { atk: 0.10 }, 'Courage is a family heirloom. +10% attack.');
  def('stalwartDefenders', 'Stalwart Defenders', '🛡️',
    { def: 0.15 }, 'Your land fights beside you. +15% defense.');
  def('seafarers', 'Seafarers', '⛵',
    { navalAtk: 0.15, moveSpeed: 0.10 }, 'Salt in the veins. +15% naval attack, +10% movement.');
  def('prolificPeople', 'Prolific People', '👶',
    { popGrowth: 0.20 }, 'Cradles outnumber coffins. +20% population growth.');
  def('drilledLegions', 'Drilled Legions', '🎖️',
    { unitCost: -0.15 }, 'An army production line. -15% unit cost.');
  def('quartermasters', 'Quartermasters', '📦',
    { unitUpkeep: -0.20 }, 'Fed, shod and paid on time. -20% unit upkeep.');
  def('silverTongues', 'Silver Tongues', '🕊️',
    { influence: 0.10, tradeCap: 1 }, 'Trust arrives before your envoys do. +10% Influence, +1 trade route.');
  def('pathfinders', 'Pathfinders', '🧭',
    { vision: 1, moveSpeed: 0.10 }, 'No blank spaces on your maps. +1 vision, +10% movement.');
  def('resilientStock', 'Resilient Stock', '💪',
    { healRate: 0.50, eventLuck: 0.05 }, 'Hard to kill, quick to mend. +50% healing, luckier events.');
  def('goldenHoard', 'Golden Hoard', '🏦',
    { gold: 0.10, upkeepDiscount: 0.10 }, 'Old money, carefully kept. +10% Gold, -10% building upkeep.', { minAge: 3 });
  def('industrialists', 'Industrialists', '🏭',
    { materials: 0.10, 'b:factory': 0.25 }, 'Smoke means progress. +10% Materials, +25% Factory output.', { minAge: 5 });
  def('petroleumBarons', 'Petroleum Barons', '🛢️',
    { 'b:oilWell': 0.50 }, 'You can smell a reservoir from horseback. +50% Oil Well output.', { minAge: 6 });
  def('siliconPioneers', 'Silicon Pioneers', '💾',
    { 'b:chipFab': 0.50, science: 0.05 }, 'The fab is the new cathedral. +50% Chip Fab output, +5% Science.', { minAge: 7 });
  def('memeticCulture', 'Memetic Culture', '📡',
    { influence: 0.20, science: -0.05 }, 'Your jokes conquer continents. +20% Influence.', { minAge: 6 });
  def('warEconomy', 'War Economy', '⚙️',
    { unitCost: -0.10, materials: 0.10, gold: -0.05 }, 'Factories that pivot to arsenals overnight.', { minAge: 5 });
  def('terraformers', 'Terraformers', '🌍',
    { food: 0.10, 'b:farm': 0.25 }, 'No biome is beyond the plough. +10% Food, +25% Farm output.', { minAge: 7 });

  window.PERKS = P;
  window.PERK_LIST = LIST;
})();
