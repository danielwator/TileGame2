/* ============================================================
 *  AEONS — Victory Conditions (5)
 * ============================================================ */
'use strict';
window.VICTORIES = {
  domination: {
    id: 'domination', name: 'Domination Victory', icon: '⚔️',
    desc: 'Capture or control every rival capital. A nation whose capital falls survives, diminished — but a nation that holds them all rules everything that matters.',
    check: 'Own all original capital cities (yours included).',
  },
  science: {
    id: 'science', name: 'Science Victory', icon: '🚀',
    desc: 'Research the Ascension Program (Near Future Statecraft), build an Orbital Elevator, then fund the five-stage Starlight Ark project (each stage costs 2,000 Science + 1,500 Materials + 50 Circuits, paid from stockpiles). Launch the Ark to win.',
    check: 'Complete 5 Starlight Ark stages after building the Orbital Elevator.',
  },
  economic: {
    id: 'economic', name: 'Economic Victory', icon: '🪙',
    desc: 'Accumulate 75,000 Gold in your treasury while maintaining at least 5 active trade agreements. Money talks — eventually it gives orders.',
    check: 'Treasury ≥ 75,000 Gold and ≥ 5 active trade deals.',
  },
  hegemony: {
    id: 'hegemony', name: 'Hegemony Victory', icon: '👑',
    desc: 'Control 40% of the world\'s land tiles. When the map is mostly your color, the argument is over.',
    check: 'Own ≥ 40% of all land tiles.',
  },
  score: {
    id: 'score', name: 'Score Victory', icon: '🏆',
    desc: 'If no one has won by the year 2200, the nation with the highest score takes the crown of history. Score = population x3 + tiles x1 + techs x5 + buildings x2 + gold/100.',
    check: 'Highest score at year 2200.',
  },
};
window.VICTORY_LIST = Object.values(window.VICTORIES);
