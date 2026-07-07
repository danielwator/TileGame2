/* ============================================================
 *  AEONS — Parametric world generation
 *
 *  Pipeline (all seeded, fully deterministic):
 *   1. Tectonic plates      — jittered flood-fill, oceanic/continental,
 *                             per-plate motion vectors
 *   2. Boundary stress      — convergent => mountain belts / island arcs
 *                             divergent => rifts / mid-ocean ridges
 *   3. Elevation            — plate base + fBm noise + stress + hotspots
 *   4. Sea level            — percentile cut at target ocean fraction
 *   5. Temperature          — latitude curve, altitude lapse, noise
 *   6. Moisture             — prevailing wind bands advect ocean moisture
 *                             inland; mountains cast rain shadows
 *   7. Biomes               — Whittaker-style temp x moisture matrix
 *   8. Deposits             — biome-weighted strategic/bonus resources
 * ============================================================ */
'use strict';
(function () {

  const DEFAULT_PARAMS = {
    seed: 'AEONS',
    size: 20,            // hexsphere frequency -> 10n^2+2 tiles
    oceanFraction: 0.62,
    plates: 14,
    temperature: 0,      // -0.15 (ice age) .. +0.15 (hothouse)
    humidity: 0,         // -0.15 (arid)    .. +0.15 (lush)
    resourceRichness: 1, // deposit density multiplier
  };

  /* small vector helpers on [x,y,z] arrays */
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a, b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
  function norm(v) {
    const l = Math.hypot(v[0], v[1], v[2]) || 1;
    return [v[0] / l, v[1] / l, v[2] / l];
  }

  function generateWorld(userParams) {
    const P = Object.assign({}, DEFAULT_PARAMS, userParams);
    const rng = new TG.RNG(P.seed + '|world');
    const noise = new TG.Simplex3(new TG.RNG(P.seed + '|noise'));
    const { tiles } = TG.buildHexsphere(P.size);
    const N = tiles.length;

    /* ================= 1. TECTONIC PLATES ================= */
    const plateCount = P.plates;
    const plates = [];
    // farthest-point-ish seeding: random candidates, keep well separated
    const seedIds = [];
    for (let p = 0; p < plateCount; p++) {
      let best = -1, bestScore = -1;
      for (let c = 0; c < 20; c++) {
        const cand = rng.int(0, N - 1);
        let minD = Infinity;
        for (const s of seedIds) {
          const d = 1 - dot(tiles[cand].center, tiles[s].center); // angular-ish
          if (d < minD) minD = d;
        }
        const score = seedIds.length ? minD : 1;
        if (score > bestScore) { bestScore = score; best = cand; }
      }
      seedIds.push(best);
    }
    for (let p = 0; p < plateCount; p++) {
      const c = tiles[seedIds[p]].center;
      const oceanic = rng.chance(0.55);
      // tangent motion vector: random direction in tangent plane + slight rotation
      const ref = Math.abs(c[1]) < 0.99 ? [0, 1, 0] : [1, 0, 0];
      const t1 = norm(cross(ref, c));
      const t2 = cross(c, t1);
      const ang = rng.range(0, Math.PI * 2);
      const speed = rng.range(0.4, 1.0);
      plates.push({
        id: p,
        oceanic,
        base: oceanic ? rng.range(-0.9, -0.45) : rng.range(0.08, 0.4),
        motion: [
          (Math.cos(ang) * t1[0] + Math.sin(ang) * t2[0]) * speed,
          (Math.cos(ang) * t1[1] + Math.sin(ang) * t2[1]) * speed,
          (Math.cos(ang) * t1[2] + Math.sin(ang) * t2[2]) * speed,
        ],
        growth: rng.range(0.6, 1.5), // flood-fill aggressiveness -> irregular shapes
      });
    }
    // jittered flood fill: priority by distance * growth * noise
    const plateOf = new Int16Array(N).fill(-1);
    const frontier = []; // {tile, plate, prio}
    for (let p = 0; p < plateCount; p++) {
      plateOf[seedIds[p]] = p;
      for (const nb of tiles[seedIds[p]].neighbors) {
        frontier.push({ t: nb, p, prio: rng.next() });
      }
    }
    // simple priority queue via repeated sort chunks (N is small enough)
    while (frontier.length) {
      // pick lowest prio (linear scan is O(F) but F stays modest)
      let bi = 0;
      for (let i = 1; i < frontier.length; i++) if (frontier[i].prio < frontier[bi].prio) bi = i;
      const cur = frontier[bi];
      frontier[bi] = frontier[frontier.length - 1];
      frontier.pop();
      if (plateOf[cur.t] !== -1) continue;
      plateOf[cur.t] = cur.p;
      const g = plates[cur.p].growth;
      for (const nb of tiles[cur.t].neighbors) {
        if (plateOf[nb] === -1) {
          const c = tiles[nb].center;
          const jitter = 0.5 + 0.5 * noise.noise(c[0] * 3.1, c[1] * 3.1, c[2] * 3.1);
          frontier.push({ t: nb, p: cur.p, prio: cur.prio + (0.4 + jitter) / g });
        }
      }
    }

    /* ================= 2. BOUNDARY STRESS ================= */
    // stress > 0 : convergent (uplift). stress < 0 : divergent (rift)
    const stress = new Float32Array(N);
    const isBoundary = new Uint8Array(N);
    const volcanism = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const pi = plateOf[i];
      for (const nb of tiles[i].neighbors) {
        const pj = plateOf[nb];
        if (pj === pi) continue;
        isBoundary[i] = 1;
        // relative velocity of j w.r.t. i projected on the i->j direction:
        // moving toward each other (negative relative separation) = convergent
        const dir = norm(sub(tiles[nb].center, tiles[i].center));
        const rel = sub(plates[pj].motion, plates[pi].motion);
        const conv = -dot(rel, dir); // >0 approaching
        const wi = plates[pi], wj = plates[pj];
        if (conv > 0.08) {
          if (!wi.oceanic && !wj.oceanic) {
            stress[i] += conv * 1.5;                 // Himalaya-style belt
          } else if (wi.oceanic !== wj.oceanic) {
            // subduction: continental side gets arc + volcanoes, oceanic side trench
            if (!wi.oceanic) { stress[i] += conv * 1.1; volcanism[i] += conv; }
            else stress[i] -= conv * 0.5;            // trench
          } else {
            stress[i] += conv * 0.7;                 // island arc
            volcanism[i] += conv * 0.8;
          }
        } else if (conv < -0.08) {
          stress[i] += conv * 0.45;                  // rift / ridge (negative)
          if (wi.oceanic && wj.oceanic) stress[i] += 0.12; // mid-ocean ridge bump
        }
      }
    }
    // diffuse stress inland a few hops so ranges have width
    for (let pass = 0; pass < 3; pass++) {
      const next = Float32Array.from(stress);
      for (let i = 0; i < N; i++) {
        let s = stress[i], cnt = 1;
        for (const nb of tiles[i].neighbors) { s += stress[nb] * 0.55; cnt += 0.55; }
        next[i] = s / cnt;
      }
      stress.set(next);
    }

    /* ================= 3. ELEVATION ================= */
    const elevation = new Float32Array(N);
    const NOISE_SCALE = 1.9;
    for (let i = 0; i < N; i++) {
      const c = tiles[i].center;
      const p = plates[plateOf[i]];
      const fbm = noise.fbm(c[0] * NOISE_SCALE, c[1] * NOISE_SCALE, c[2] * NOISE_SCALE, 5, 2.1, 0.52);
      const detail = noise.noise(c[0] * 6.5, c[1] * 6.5, c[2] * 6.5) * 0.08;
      elevation[i] = p.base + fbm * 0.55 + detail + stress[i] * 0.6;
    }
    // hotspot island chains on oceanic plates
    const hotspots = rng.int(4, 7);
    for (let h = 0; h < hotspots; h++) {
      let t = rng.int(0, N - 1);
      if (!plates[plateOf[t]].oceanic) continue;
      const c0 = tiles[t].center;
      const ref = Math.abs(c0[1]) < 0.99 ? [0, 1, 0] : [1, 0, 0];
      const t1 = norm(cross(ref, c0));
      const t2v = cross(c0, t1);
      const ang = rng.range(0, Math.PI * 2);
      const dir = [
        Math.cos(ang) * t1[0] + Math.sin(ang) * t2v[0],
        Math.cos(ang) * t1[1] + Math.sin(ang) * t2v[1],
        Math.cos(ang) * t1[2] + Math.sin(ang) * t2v[2],
      ];
      const len = rng.int(3, 8);
      let bump = rng.range(0.55, 0.85);
      for (let s = 0; s < len; s++) {
        elevation[t] += bump;
        volcanism[t] += 0.5;
        for (const nb of tiles[t].neighbors) elevation[nb] += bump * 0.3;
        bump *= 0.78;
        // walk along dir
        let best = -1, bestD = -Infinity;
        for (const nb of tiles[t].neighbors) {
          const d = dot(norm(sub(tiles[nb].center, tiles[t].center)), dir);
          if (d > bestD) { bestD = d; best = nb; }
        }
        t = best;
      }
    }

    /* ================= 4. SEA LEVEL ================= */
    const sorted = Float32Array.from(elevation).sort();
    const seaLevel = sorted[Math.floor(N * P.oceanFraction)];
    const maxElev = sorted[N - 1];
    const minElev = sorted[0];
    // hLand in [0,1] above sea, hDepth in [0,1] below
    const hLand = new Float32Array(N);
    const hDepth = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      if (elevation[i] >= seaLevel) hLand[i] = (elevation[i] - seaLevel) / Math.max(1e-6, maxElev - seaLevel);
      else hDepth[i] = (seaLevel - elevation[i]) / Math.max(1e-6, seaLevel - minElev);
    }
    const isLand = new Uint8Array(N);
    for (let i = 0; i < N; i++) isLand[i] = elevation[i] >= seaLevel ? 1 : 0;

    // ocean connectivity -> lakes
    const isLake = new Uint8Array(N);
    {
      const comp = new Int32Array(N).fill(-1);
      let nComp = 0;
      const compSize = [];
      for (let i = 0; i < N; i++) {
        if (isLand[i] || comp[i] !== -1) continue;
        const queue = [i]; comp[i] = nComp; let size = 0, head = 0;
        while (head < queue.length) {
          const cur = queue[head++]; size++;
          for (const nb of tiles[cur].neighbors) {
            if (!isLand[nb] && comp[nb] === -1) { comp[nb] = nComp; queue.push(nb); }
          }
        }
        compSize.push(size); nComp++;
      }
      // only small disconnected water bodies are lakes; big ones are inland seas
      const LAKE_MAX = 12;
      for (let i = 0; i < N; i++) {
        if (!isLand[i] && compSize[comp[i]] <= LAKE_MAX) isLake[i] = 1;
      }
    }

    /* ================= 5. TEMPERATURE ================= */
    const temp = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const latRad = tiles[i].lat * Math.PI / 180;
      const c = tiles[i].center;
      let t = Math.pow(Math.max(0, Math.cos(latRad)), 1.15);        // 1 equator -> 0 poles
      t += noise.noise(c[0] * 2.7 + 31, c[1] * 2.7, c[2] * 2.7) * 0.07;
      t -= hLand[i] * 0.52;                                          // altitude lapse
      t += P.temperature;
      temp[i] = TG.clamp(t, 0, 1);
    }

    /* ================= 6. MOISTURE (wind advection) ================= */
    const moist = new Float32Array(N);
    const windDir = new Array(N); // tangent unit vector per tile
    for (let i = 0; i < N; i++) {
      const c = tiles[i].center;
      const lat = tiles[i].lat;
      const east = norm(cross(c, [0, 1, 0]));            // +lon direction... see below
      // NOTE: cross(pos, up) gives east at the equator for our lon convention
      const northv = norm(cross(east, c));               // toward north pole
      const a = Math.abs(lat);
      let ew, ns;
      if (a < 30)      { ew = -0.85; ns = -0.35 * Math.sign(lat || 1); }  // trade winds -> W, toward equator
      else if (a < 60) { ew = 0.85;  ns = 0.25 * Math.sign(lat || 1); }   // westerlies -> E, poleward
      else             { ew = -0.8;  ns = -0.2 * Math.sign(lat || 1); }   // polar easterlies
      windDir[i] = norm([
        east[0] * ew + northv[0] * ns,
        east[1] * ew + northv[1] * ns,
        east[2] * ew + northv[2] * ns,
      ]);
      if (!isLand[i]) {
        // warm water evaporates more
        moist[i] = TG.clamp(0.55 + temp[i] * 0.55, 0, 1.05);
      }
    }
    // advect: land moisture flows in from upwind neighbors, decays with distance,
    // decays hard when climbing over elevated terrain (rain shadow)
    for (let pass = 0; pass < 26; pass++) {
      let changed = false;
      for (let i = 0; i < N; i++) {
        if (!isLand[i]) continue;
        let best = moist[i];
        for (const nb of tiles[i].neighbors) {
          const carry = dot(windDir[nb], norm(sub(tiles[i].center, tiles[nb].center)));
          if (carry <= 0.15) continue; // wind not blowing from nb toward i
          const climb = Math.max(0, hLand[i] - hLand[nb]);
          const barrier = hLand[i] > 0.45 ? 0.30 : 0;   // mountains wring clouds dry
          const decay = 0.955 - climb * 0.9 - barrier * carry;
          const m = moist[nb] * TG.clamp(decay, 0.3, 0.985) * (0.55 + 0.45 * carry);
          if (m > best) { best = m; changed = true; }
        }
        moist[i] = best;
      }
      if (!changed) break;
    }
    for (let i = 0; i < N; i++) {
      const c = tiles[i].center;
      let m = moist[i] + noise.noise(c[0] * 3.3 - 17, c[1] * 3.3, c[2] * 3.3) * 0.10 + P.humidity;
      // ITCZ boost: equatorial convection rains regardless of wind
      m += Math.exp(-Math.pow(tiles[i].lat / 12, 2)) * 0.14;
      // horse latitudes: descending dry air parches the subtropics (Sahara belt)
      m -= Math.exp(-Math.pow((Math.abs(tiles[i].lat) - 25) / 9, 2)) * 0.16;
      moist[i] = TG.clamp(m, 0, 1);
    }
    // blend with rank-normalized moisture so every world keeps a full
    // dry-to-wet spread (rain shadows survive as relative ranking)
    {
      const landIdx = [];
      for (let i = 0; i < N; i++) if (isLand[i]) landIdx.push(i);
      landIdx.sort((a, b) => moist[a] - moist[b]);
      const L = Math.max(1, landIdx.length - 1);
      const rank = new Float32Array(N);
      landIdx.forEach((tI, r) => { rank[tI] = r / L; });
      for (const tI of landIdx) moist[tI] = TG.clamp(moist[tI] * 0.55 + rank[tI] * 0.45, 0, 1);
    }

    /* ================= 7. BIOMES ================= */
    // percentile-based rugged-terrain cuts: ~8% of land is mountain,
    // ~14% highlands, regardless of how violent this seed's tectonics were
    let mountainCut = 0.52, hillCut = 0.30;
    {
      const hs = world_landHeightsSorted();
      if (hs.length > 20) {
        mountainCut = Math.max(hs[Math.floor(hs.length * 0.92)], 0.28);
        hillCut = Math.max(hs[Math.floor(hs.length * 0.78)], 0.18);
      }
    }
    function world_landHeightsSorted() {
      const a = [];
      for (let i = 0; i < N; i++) if (isLand[i]) a.push(hLand[i]);
      return a.sort((x, y) => x - y);
    }
    const biome = new Array(N);
    for (let i = 0; i < N; i++) {
      const t = temp[i], m = moist[i], h = hLand[i];
      if (!isLand[i]) {
        if (t < 0.12) biome[i] = 'iceCap';                       // sea ice
        else if (isLake[i]) biome[i] = 'lake';
        else if (hDepth[i] < 0.16 && hasLandNeighbor(i)) biome[i] = 'coast';
        else if (hDepth[i] < 0.45) biome[i] = 'ocean';
        else biome[i] = 'deepOcean';
        continue;
      }
      if (h > mountainCut) { biome[i] = 'mountain'; continue; }
      if (volcanism[i] > 0.55 && h > 0.06 && rngStable(i) < 0.5) { biome[i] = 'volcanic'; continue; }
      if (t < 0.13) { biome[i] = 'iceCap'; continue; }           // land glacier
      if (h > hillCut) { biome[i] = 'highlands'; continue; }
      if (t < 0.24) { biome[i] = 'tundra'; continue; }
      if (t < 0.42) { biome[i] = m > 0.42 ? 'boreal' : 'tundra'; continue; }
      // wetland: warm-ish, soaked, low and flat
      if (m > 0.82 && h < 0.08 && t < 0.75 && rngStable(i) < 0.55) { biome[i] = 'wetland'; continue; }
      if (t < 0.70) { // temperate
        if (m < 0.18) biome[i] = 'desert';
        else if (m < 0.34) biome[i] = 'steppe';
        else if (m < 0.50) biome[i] = 'plains';
        else if (m < 0.64) biome[i] = 'grassland';
        else biome[i] = 'forest';
      } else {        // tropical
        if (m < 0.16) biome[i] = 'desert';
        else if (m < 0.42) biome[i] = 'savanna';
        else if (m < 0.60) biome[i] = 'grassland';
        else if (m < 0.78) biome[i] = 'plains';
        else biome[i] = 'rainforest';
      }
    }
    function hasLandNeighbor(i) {
      for (const nb of tiles[i].neighbors) if (isLand[nb]) return true;
      return false;
    }
    // stable per-tile hash rand (deterministic, independent of loop order)
    function rngStable(i) {
      const c = tiles[i].center;
      const x = Math.sin(c[0] * 127.1 + c[1] * 311.7 + c[2] * 74.7) * 43758.5453;
      return x - Math.floor(x);
    }

    /* ================= 8. DEPOSITS ================= */
    const deposit = new Array(N).fill(null);
    const depRng = new TG.RNG(P.seed + '|deposits');
    const DEP_BASE_CHANCE = 0.020 * P.resourceRichness; // per weight unit
    for (let i = 0; i < N; i++) {
      const b = biome[i];
      const candidates = [];
      for (const dep of window.DEPOSIT_LIST) {
        const w = dep.spawn[b];
        if (w) candidates.push({ dep, w });
      }
      if (!candidates.length) continue;
      let totalW = 0;
      for (const cd of candidates) totalW += cd.w;
      if (depRng.chance(TG.clamp(totalW * DEP_BASE_CHANCE, 0, 0.5))) {
        deposit[i] = depRng.weighted(candidates, (cd) => cd.w).dep.id;
      }
    }

    /* ================= assemble ================= */
    const continents = labelContinents();
    function labelContinents() {
      const cont = new Int16Array(N).fill(-1);
      let cId = 0;
      for (let i = 0; i < N; i++) {
        if (!isLand[i] || cont[i] !== -1) continue;
        const q = [i]; cont[i] = cId; let head = 0;
        while (head < q.length) {
          const cur = q[head++];
          for (const nb of tiles[cur].neighbors) {
            if (isLand[nb] && cont[nb] === -1) { cont[nb] = cId; q.push(nb); }
          }
        }
        cId++;
      }
      return cont;
    }

    const world = {
      params: P,
      tiles,
      N,
      plateOf, plates,
      elevation, hLand, hDepth, seaLevel,
      temp, moist, windDir,
      biome, deposit,
      isLand, isLake, isBoundary, volcanism,
      continents,
    };
    world.landTiles = [];
    for (let i = 0; i < N; i++) if (isLand[i]) world.landTiles.push(i);

    /* ---- nation spawn points: fertile, spread out ---- */
    world.pickSpawns = function (count) {
      const score = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        if (!isLand[i]) continue;
        const b = window.BIOMES[biome[i]];
        if (!b.allowsCity) continue;
        let s = (b.yields.food * 2 + b.yields.materials + b.yields.gold * 0.5);
        let coastal = false;
        for (const nb of tiles[i].neighbors) {
          const nbB = window.BIOMES[biome[nb]];
          s += (nbB.yields.food * 1.2 + nbB.yields.materials + nbB.yields.gold * 0.5) * 0.4;
          if (deposit[nb]) s += 1.5;
          if (biome[nb] === 'coast' || biome[nb] === 'lake') coastal = true;
        }
        if (coastal) s += 2.5;
        score[i] = s;
      }
      // candidates: top 20% by score
      const cand = world.landTiles.filter((i) => score[i] > 0)
        .sort((a, b2) => score[b2] - score[a])
        .slice(0, Math.max(count * 12, 120));
      const spawnRng = new TG.RNG(P.seed + '|spawns');
      const picked = [];
      // greedy farthest-point among candidates, seeded by a good random one
      picked.push(cand[spawnRng.int(0, Math.min(9, cand.length - 1))]);
      while (picked.length < count && cand.length) {
        let best = -1, bestD = -1;
        for (const cI of cand) {
          if (picked.includes(cI)) continue;
          let minD = Infinity;
          for (const pI of picked) {
            const d = 1 - dot(tiles[cI].center, tiles[pI].center);
            if (d < minD) minD = d;
          }
          const sc = minD * (1 + score[cI] * 0.01);
          if (sc > bestD) { bestD = sc; best = cI; }
        }
        if (best === -1) break;
        picked.push(best);
      }
      return picked;
    };

    return world;
  }

  TG.generateWorld = generateWorld;
  TG.WORLD_DEFAULTS = DEFAULT_PARAMS;
})();
