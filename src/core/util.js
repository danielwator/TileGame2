/* ============================================================
 *  AEONS — core utilities
 *  Global namespace: TG
 *  Seeded RNG (xmur3 hash -> sfc32), math helpers, misc.
 * ============================================================ */
'use strict';
window.TG = window.TG || {};

(function () {

  /* ---------- Seeded RNG ---------- */

  // String hash -> 4x 32-bit seeds
  function xmur3(str) {
    let h = 1779033703 ^ str.length;
    for (let i = 0; i < str.length; i++) {
      h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    return function () {
      h = Math.imul(h ^ (h >>> 16), 2246822507);
      h = Math.imul(h ^ (h >>> 13), 3266489909);
      return (h ^= h >>> 16) >>> 0;
    };
  }

  function sfc32(a, b, c, d) {
    return function () {
      a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
      let t = (a + b) | 0;
      a = b ^ (b >>> 9);
      b = (c + (c << 3)) | 0;
      c = (c << 21) | (c >>> 11);
      d = (d + 1) | 0;
      t = (t + d) | 0;
      c = (c + t) | 0;
      return (t >>> 0) / 4294967296;
    };
  }

  /** Seeded PRNG. `new TG.RNG('my seed')` */
  class RNG {
    constructor(seed) {
      const s = xmur3(String(seed));
      this._next = sfc32(s(), s(), s(), s());
      // burn a few values (sfc32 warm-up)
      for (let i = 0; i < 12; i++) this._next();
    }
    /** float in [0,1) */
    next() { return this._next(); }
    /** float in [min,max) */
    range(min, max) { return min + (max - min) * this._next(); }
    /** int in [min,max] inclusive */
    int(min, max) { return min + Math.floor(this._next() * (max - min + 1)); }
    /** true with probability p */
    chance(p) { return this._next() < p; }
    /** pick a random element */
    pick(arr) { return arr[Math.floor(this._next() * arr.length)]; }
    /** weighted pick: items = [{w: weight, ...}] or weightFn */
    weighted(items, weightFn) {
      const wf = weightFn || ((it) => it.w);
      let total = 0;
      for (const it of items) total += wf(it);
      let r = this._next() * total;
      for (const it of items) {
        r -= wf(it);
        if (r <= 0) return it;
      }
      return items[items.length - 1];
    }
    /** Fisher-Yates shuffle in place, returns arr */
    shuffle(arr) {
      for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(this._next() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
      }
      return arr;
    }
    /** approx normal via sum of 4 uniforms, mean 0 sd ~1 */
    gauss() {
      return (this._next() + this._next() + this._next() + this._next() - 2) * 1.732;
    }
  }

  /* ---------- Math helpers ---------- */

  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smoothstep = (a, b, t) => {
    t = clamp((t - a) / (b - a), 0, 1);
    return t * t * (3 - 2 * t);
  };

  /* ---------- Color helpers ---------- */

  function hexToRgb(hex) {
    const n = parseInt(hex.replace('#', ''), 16);
    return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
  }
  function mixRgb(c1, c2, t) {
    return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];
  }
  function scaleRgb(c, s) { return [c[0] * s, c[1] * s, c[2] * s]; }

  /* ---------- Misc ---------- */

  function fmt(n) {
    if (n === undefined || n === null) return '0';
    const neg = n < 0; n = Math.abs(n);
    let s;
    if (n >= 1e6) s = (n / 1e6).toFixed(1) + 'M';
    else if (n >= 1e4) s = (n / 1e3).toFixed(1) + 'k';
    else s = Math.floor(n).toString();
    return (neg ? '-' : '') + s;
  }
  function fmtSigned(n) {
    const v = Math.round(n * 10) / 10;
    return (v >= 0 ? '+' : '') + v;
  }

  function randomSeedString() {
    const words = ['AZURE','TERRA','ORION','DELTA','EMBER','FROST','GALE','IONIA','KRONO','LUMEN',
      'MIRA','NOVA','ONYX','PYRRH','QUARTZ','RIFT','SOLIS','TITAN','UMBRA','VELA'];
    const r = Math.random;
    return words[(r() * words.length) | 0] + '-' + Math.floor(r() * 9000 + 1000);
  }

  TG.RNG = RNG;
  TG.clamp = clamp;
  TG.lerp = lerp;
  TG.smoothstep = smoothstep;
  TG.hexToRgb = hexToRgb;
  TG.mixRgb = mixRgb;
  TG.scaleRgb = scaleRgb;
  TG.fmt = fmt;
  TG.fmtSigned = fmtSigned;
  TG.randomSeedString = randomSeedString;
})();
