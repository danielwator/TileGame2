/* ============================================================
 *  AEONS — Policies (30)
 *
 *  Policies fill limited slots (unlocked by Statecraft techs,
 *  starting with Tribal Council). Enacting costs Influence;
 *  swapping a policy out refunds nothing. Effects use the same
 *  mod vocabulary as technologies and stack with them.
 * ============================================================ */
'use strict';
(function () {
  const P = {}, LIST = [];
  function def(id, name, type, tech, cost, mod, desc) {
    const p = { id, name, type, tech, cost, mod, desc };
    p.age = tech ? window.TECHS[tech].age : 1;
    if (P[id]) console.error('duplicate policy id', id);
    P[id] = p; LIST.push(p);
  }

  /* ---------- economy ---------- */
  def('agrarianFocus', 'Agrarian Focus', 'economy', 'agriculture', 30,
    { food: 0.15, science: -0.05 },
    'Every hand to the harvest. The scribes can wait.');
  def('artisanPatronage', 'Artisan Patronage', 'economy', 'toolmaking', 30,
    { materials: 0.15, gold: -0.05 },
    'State silver flows to the workshops.');
  def('openMarkets', 'Open Markets', 'economy', 'currency', 60,
    { gold: 0.15, def: -0.05 },
    'Low walls and open gates make rich cities — and tempting ones.');
  def('stateGranaries', 'State Granaries', 'economy', 'pottery', 40,
    { popGrowth: 0.15, gold: -0.05 },
    'The crown feeds the people; the people multiply.');
  def('mercantilism', 'Mercantilism', 'economy', 'banking', 90,
    { gold: 0.20, influence: -0.10 },
    'Hoard bullion, tax rivals, apologize never.');
  def('freeEnterprise', 'Free Enterprise', 'economy', 'corporations', 130,
    { gold: 0.15, materials: 0.10, food: -0.05 },
    'The invisible hand works overtime.');
  def('plannedEconomy', 'Planned Economy', 'economy', 'constitution', 130,
    { materials: 0.20, gold: -0.10 },
    'Five-year plans and quota boards.');
  def('exportEconomy', 'Export Economy', 'economy', 'internationalTrade', 170,
    { gold: 0.10, tradeCap: 1 },
    'Everything is for sale, in bulk, FOB.');
  def('greenTransition', 'Green Transition', 'economy', 'renewables', 220,
    { materials: 0.10, food: 0.10, gold: -0.05 },
    'Prosperity that doesn\'t eat its seed corn.');
  def('innovationEconomy', 'Innovation Economy', 'economy', 'ventureCapital', 220,
    { science: 0.15, gold: 0.05, materials: -0.05 },
    'Subsidize the future; expense the past.');

  /* ---------- military ---------- */
  def('warriorCulture', 'Warrior Culture', 'military', 'warbands', 30,
    { atk: 0.10, science: -0.05 },
    'Songs of battle drown out quieter pursuits.');
  def('borderWatch', 'Border Watch', 'military', 'palisades', 30,
    { def: 0.15, gold: -0.05 },
    'Beacons on every hill, eyes on every pass.');
  def('conscription', 'Conscription', 'military', 'citizenship', 60,
    { unitCost: -0.20, food: -0.05 },
    'Every citizen owes a season under arms.');
  def('mercenaryContracts', 'Mercenary Contracts', 'military', 'moneylending', 60,
    { unitCost: -0.10, unitUpkeep: 0.10, atk: 0.05 },
    'Loyalty rented by the campaign.');
  def('standingArmy', 'Standing Army', 'military', 'professionalArmy', 100,
    { unitUpkeep: -0.20, influence: -0.05 },
    'Barracks never empty, borders never bare.');
  def('navalTradition', 'Naval Tradition', 'military', 'shipwrights', 90,
    { navalAtk: 0.20, gold: -0.05 },
    'The sea is a province like any other — ours.');
  def('fortressDoctrine', 'Fortress Doctrine', 'military', 'bastionForts', 100,
    { def: 0.20, moveSpeed: -0.10 },
    'Why march when you can make them come to you?');
  def('totalWarDoctrine', 'Total War Doctrine', 'military', 'totalMobilization', 180,
    { atk: 0.15, unitCost: -0.10, popGrowth: -0.10 },
    'The entire nation is the war effort.');
  def('deterrence', 'Deterrence', 'military', 'guidedMissiles', 220,
    { def: 0.15, influence: 0.10, gold: -0.10 },
    'Peace through visible, expensive readiness.');
  def('rapidDeployment', 'Rapid Deployment', 'military', 'logistics', 150,
    { moveSpeed: 0.25, unitUpkeep: 0.05 },
    'First to arrive writes the terms.');

  /* ---------- society ---------- */
  def('councilOfElders', 'Council of Elders', 'society', 'tribalCouncil', 25,
    { influence: 0.10, atk: -0.05 },
    'Wisdom over vigor; consensus over conquest.');
  def('templeEconomy', 'Temple Economy', 'society', 'stateReligion', 60,
    { influence: 0.15, science: -0.05 },
    'The granary, the mint and the altar are one institution.');
  def('scholarPatronage', 'Scholar Patronage', 'society', 'philosophy', 60,
    { science: 0.15, materials: -0.05 },
    'Genius on retainer.');
  def('guildCharters', 'Guild Charters', 'society', 'guilds', 90,
    { materials: 0.10, gold: 0.05, popGrowth: -0.05 },
    'Quality guaranteed; competition, less so.');
  def('civicFestivals', 'Civic Festivals', 'society', 'drama', 60,
    { influence: 0.10, popGrowth: 0.05, gold: -0.05 },
    'Bread, circuses and belonging.');
  def('enlightenmentSalons', 'Enlightenment Salons', 'society', 'scientificMethod', 120,
    { science: 0.15, influence: 0.05, def: -0.05 },
    'Dangerous ideas served with tea.');
  def('publicWelfare', 'Public Welfare', 'society', 'welfareState', 170,
    { popGrowth: 0.15, gold: -0.10 },
    'No citizen left to the wolves.');
  def('nationalMythos', 'National Mythos', 'society', 'nationalism', 150,
    { influence: 0.15, warWeariness: -0.10, science: -0.05 },
    'A story big enough to die for.');
  def('openBordersCulture', 'Open Society', 'society', 'openSociety', 220,
    { science: 0.10, gold: 0.10, def: -0.05 },
    'Talent immigrates; ideas circulate.');
  def('digitalCitizenship', 'Digital Citizenship', 'society', 'digitalGovernance', 260,
    { influence: 0.15, science: 0.05, gold: -0.05 },
    'The state as a service, citizens as users.');

  for (const p of LIST) {
    if (p.tech && !window.TECHS[p.tech]) console.error('policy ' + p.id + ' requires missing tech ' + p.tech);
  }
  window.POLICIES = P;
  window.POLICY_LIST = LIST;
})();
