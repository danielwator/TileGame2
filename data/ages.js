/* ============================================================
 *  TileGame2 — Ages (eras)
 *  A nation advances to the next age after researching
 *  `techsToAdvance` technologies of its current age — every era
 *  is therefore roughly the same length. The calendar is abstract
 *  and uniform: 1 year per tick, in every era.
 * ============================================================ */
'use strict';
window.AGES = [
  { id: 1, name: 'Ancient Age',      short: 'Ancient',     techsToAdvance: 20, color: '#c9a45f',
    desc: 'First fires, first fields, first walls. Everything is undiscovered and every neighbor is a stranger.' },
  { id: 2, name: 'Classical Age',    short: 'Classical',   techsToAdvance: 20, color: '#d8d0b0',
    desc: 'Philosophy, currency and organized legions. Civilizations begin to see — and covet — one another.' },
  { id: 3, name: 'Medieval Age',     short: 'Medieval',    techsToAdvance: 20, color: '#8f9bb5',
    desc: 'Castles, guilds and crusades. Faith and steel decide the fate of kingdoms.' },
  { id: 4, name: 'Renaissance Age',  short: 'Renaissance', techsToAdvance: 20, color: '#c98fd0',
    desc: 'Printing, gunpowder and tall ships. The whole globe is suddenly within reach.' },
  { id: 5, name: 'Industrial Age',   short: 'Industrial',  techsToAdvance: 20, color: '#a0762e',
    desc: 'Coal smoke over iron rails. Production explodes — and so does the cost of falling behind.' },
  { id: 6, name: 'Modern Age',       short: 'Modern',      techsToAdvance: 20, color: '#5e8fce',
    desc: 'Oil, flight and total war. The world shrinks to a chessboard.' },
  { id: 7, name: 'Information Age',  short: 'Information', techsToAdvance: 20, color: '#5ecfa0',
    desc: 'Silicon minds and instant signals. Circuits become as strategic as steel once was.' },
  { id: 8, name: 'Near Future',      short: 'Near Future', techsToAdvance: 999, color: '#ce5e8f',
    desc: 'Fusion, arcologies and the first steps beyond the cradle. The endgame begins.' },
];
window.AGE_BY_ID = {};
window.AGES.forEach((a) => { window.AGE_BY_ID[a.id] = a; });
