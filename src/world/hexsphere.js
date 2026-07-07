/* ============================================================
 *  AEONS — Hexsphere (Goldberg polyhedron)
 *
 *  Subdivide an icosahedron at frequency n, then take the dual:
 *  every geodesic vertex becomes a tile (12 pentagons at the
 *  original icosa vertices, hexagons everywhere else).
 *
 *  Tile counts: 10*n^2 + 2   (n=16 -> 2562, n=20 -> 4002, n=24 -> 5762)
 * ============================================================ */
'use strict';
(function () {

  const PHI = (1 + Math.sqrt(5)) / 2;

  // Icosahedron: 12 vertices, 20 faces
  const ICO_VERTS = [
    [-1,  PHI, 0], [1,  PHI, 0], [-1, -PHI, 0], [1, -PHI, 0],
    [0, -1,  PHI], [0, 1,  PHI], [0, -1, -PHI], [0, 1, -PHI],
    [ PHI, 0, -1], [ PHI, 0, 1], [-PHI, 0, -1], [-PHI, 0, 1],
  ];
  const ICO_FACES = [
    [0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
    [1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
    [3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
    [4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1],
  ];

  function normalize(v) {
    const l = Math.hypot(v[0], v[1], v[2]);
    return [v[0] / l, v[1] / l, v[2] / l];
  }

  /**
   * Build the hexsphere.
   * @param {number} n subdivision frequency
   * @returns {{tiles:Array, meshData:Object}}
   *
   * Each tile: {
   *   id, center:[x,y,z] (unit), corners:[[x,y,z]...] (unit, wound CCW
   *   seen from outside), neighbors:[tileId...], isPentagon, lat, lon
   * }
   */
  function buildHexsphere(n) {
    /* ---- 1. geodesic subdivision ---- */
    const verts = [];              // [x,y,z] unit vectors (tile centers)
    const cache = new Map();       // quantized pos -> vertex index
    function addVert(v) {
      const p = normalize(v);
      const key = (Math.round(p[0] * 1e5)) + ',' + (Math.round(p[1] * 1e5)) + ',' + (Math.round(p[2] * 1e5));
      let idx = cache.get(key);
      if (idx !== undefined) return idx;
      idx = verts.length;
      verts.push(p);
      cache.set(key, idx);
      return idx;
    }

    const faces = []; // [a,b,c] vertex indices
    for (const f of ICO_FACES) {
      const A = ICO_VERTS[f[0]], B = ICO_VERTS[f[1]], C = ICO_VERTS[f[2]];
      // grid of points P(i,j) = A + (i/n)(B-A) + (j/n)(C-A), i+j <= n
      const grid = [];
      for (let i = 0; i <= n; i++) {
        grid.push([]);
        for (let j = 0; j <= n - i; j++) {
          const p = [
            A[0] + (i / n) * (B[0] - A[0]) + (j / n) * (C[0] - A[0]),
            A[1] + (i / n) * (B[1] - A[1]) + (j / n) * (C[1] - A[1]),
            A[2] + (i / n) * (B[2] - A[2]) + (j / n) * (C[2] - A[2]),
          ];
          grid[i].push(addVert(p));
        }
      }
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n - i; j++) {
          faces.push([grid[i][j], grid[i + 1][j], grid[i][j + 1]]);
          if (j < n - i - 1) {
            faces.push([grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]);
          }
        }
      }
    }

    /* ---- 2. adjacency ---- */
    const nV = verts.length;
    const vertFaces = Array.from({ length: nV }, () => []);
    const neighborSets = Array.from({ length: nV }, () => new Set());
    for (let fi = 0; fi < faces.length; fi++) {
      const [a, b, c] = faces[fi];
      vertFaces[a].push(fi); vertFaces[b].push(fi); vertFaces[c].push(fi);
      neighborSets[a].add(b); neighborSets[a].add(c);
      neighborSets[b].add(a); neighborSets[b].add(c);
      neighborSets[c].add(a); neighborSets[c].add(b);
    }

    /* ---- 3. face centroids (tile corners) ---- */
    const centroids = new Array(faces.length);
    for (let fi = 0; fi < faces.length; fi++) {
      const [a, b, c] = faces[fi];
      centroids[fi] = normalize([
        verts[a][0] + verts[b][0] + verts[c][0],
        verts[a][1] + verts[b][1] + verts[c][1],
        verts[a][2] + verts[b][2] + verts[c][2],
      ]);
    }

    /* ---- 4. tiles: order corners around each vertex ---- */
    const tiles = new Array(nV);
    for (let vi = 0; vi < nV; vi++) {
      const c = verts[vi];
      // tangent basis at c
      let up = Math.abs(c[1]) < 0.99 ? [0, 1, 0] : [1, 0, 0];
      // t1 = normalize(up x c), t2 = c x t1
      let t1 = normalize([
        up[1] * c[2] - up[2] * c[1],
        up[2] * c[0] - up[0] * c[2],
        up[0] * c[1] - up[1] * c[0],
      ]);
      const t2 = [
        c[1] * t1[2] - c[2] * t1[1],
        c[2] * t1[0] - c[0] * t1[2],
        c[0] * t1[1] - c[1] * t1[0],
      ];
      const fcs = vertFaces[vi];
      const withAngle = fcs.map((fi) => {
        const p = centroids[fi];
        const dx = p[0] - c[0], dy = p[1] - c[1], dz = p[2] - c[2];
        const u = dx * t1[0] + dy * t1[1] + dz * t1[2];
        const v = dx * t2[0] + dy * t2[1] + dz * t2[2];
        return { fi, ang: Math.atan2(v, u) };
      });
      withAngle.sort((a, b) => a.ang - b.ang);
      let corners = withAngle.map((w) => centroids[w.fi]);

      // ensure CCW winding seen from outside (normal ~ center):
      // cross(c1-c0, c2-c0) . center should be > 0
      if (corners.length >= 3) {
        const [p0, p1, p2] = corners;
        const e1 = [p1[0]-p0[0], p1[1]-p0[1], p1[2]-p0[2]];
        const e2 = [p2[0]-p0[0], p2[1]-p0[1], p2[2]-p0[2]];
        const nx = e1[1]*e2[2]-e1[2]*e2[1], ny = e1[2]*e2[0]-e1[0]*e2[2], nz = e1[0]*e2[1]-e1[1]*e2[0];
        if (nx*c[0] + ny*c[1] + nz*c[2] < 0) corners = corners.reverse();
      }

      tiles[vi] = {
        id: vi,
        center: c,
        corners,
        neighbors: Array.from(neighborSets[vi]),
        isPentagon: corners.length === 5,
        lat: Math.asin(TG.clamp(c[1], -1, 1)) * 180 / Math.PI,
        lon: Math.atan2(c[2], c[0]) * 180 / Math.PI,
      };
    }

    return { tiles };
  }

  /** great-circle distance in "tile units" — BFS hop distance helper */
  function bfsDistances(tiles, sourceIds, maxDist = Infinity, passable = null) {
    const dist = new Int16Array(tiles.length).fill(-1);
    const queue = [];
    for (const s of sourceIds) { dist[s] = 0; queue.push(s); }
    let head = 0;
    while (head < queue.length) {
      const cur = queue[head++];
      const d = dist[cur];
      if (d >= maxDist) continue;
      for (const nb of tiles[cur].neighbors) {
        if (dist[nb] === -1 && (!passable || passable(nb))) {
          dist[nb] = d + 1;
          queue.push(nb);
        }
      }
    }
    return dist;
  }

  TG.buildHexsphere = buildHexsphere;
  TG.bfsDistances = bfsDistances;
})();
