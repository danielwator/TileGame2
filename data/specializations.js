/* ============================================================
 *  AEONS — City Specializations (10)
 *
 *  A city may adopt one specialization once it reaches 5
 *  population (costs Influence; can be changed for double cost).
 *  Modifiers apply only to that city's buildings.
 * ============================================================ */
'use strict';
(function () {
  const S = {}, LIST = [];
  function def(id, name, icon, cost, mod, desc, opts = {}) {
    const s = Object.assign({ id, name, icon, cost, mod, desc, tech: null }, opts);
    if (S[id]) console.error('duplicate specialization id', id);
    S[id] = s; LIST.push(s);
  }

  def('breadbasket', 'Breadbasket', '🌾', 50,
    { food: 0.30, science: -0.10 },
    'This city feeds the nation. +30% Food, -10% Science here.');
  def('forgeCity', 'Forge City', '⚒️', 50,
    { materials: 0.30, food: -0.10 },
    'Anvils before altars. +30% Materials, -10% Food here.');
  def('tradeNexus', 'Trade Nexus', '🪙', 50,
    { gold: 0.30, def: -0.10 },
    'All roads, one toll booth. +30% Gold, -10% defense here.');
  def('scholarHaven', 'Scholar\'s Haven', '⚗️', 50,
    { science: 0.30, gold: -0.10 },
    'Rents are high, ideas are higher. +30% Science, -10% Gold here.');
  def('holyCity', 'Holy City', '👑', 50,
    { influence: 0.35, materials: -0.10 },
    'Pilgrims arrive; legitimacy radiates. +35% Influence, -10% Materials here.');
  def('bastion', 'Bastion', '🛡️', 60,
    { cityDefense: 0.50, gold: -0.10 },
    'A city built like an argument-ender. +50% city defense, -10% Gold here.');
  def('navalBase', 'Naval Base', '⚓', 60,
    { navalCost: -0.25, gold: 0.10 },
    'Slipways and shore leave. Naval units -25% cost, +10% Gold here. Requires a Port.', { requiresB: 'port' });
  def('garrisonCity', 'Garrison City', '🎖️', 60,
    { unitCostCity: -0.20, food: -0.10 },
    'Every block is a barracks. Units trained here cost -20%.');
  def('culturalJewel', 'Cultural Jewel', '🎭', 70,
    { influence: 0.20, gold: 0.15, materials: -0.10 },
    'The city other nations write poems about. +20% Influence, +15% Gold here.', { tech: 'renaissanceArt' });
  def('techHub', 'Tech Hub', '💾', 80,
    { science: 0.25, gold: 0.15, food: -0.15 },
    'Garages that eat industries. +25% Science, +15% Gold here.', { tech: 'computers' });

  for (const s of LIST) {
    if (s.tech && !window.TECHS[s.tech]) console.error('spec ' + s.id + ' requires missing tech ' + s.tech);
  }
  window.SPECIALIZATIONS = S;
  window.SPEC_LIST = LIST;
})();
