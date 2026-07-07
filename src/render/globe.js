/* ============================================================
 *  AEONS — Globe renderer
 *  One BufferGeometry fan-triangulated from tile polygons,
 *  per-vertex colors, tile edge lines, nation border ribbons,
 *  selection/hover outlines, raycast picking.
 * ============================================================ */
'use strict';
(function () {

  const R = 100; // globe radius

  class Globe {
    constructor(scene, world) {
      this.scene = scene;
      this.world = world;
      this.R = R;

      const tiles = world.tiles;
      const N = world.N;

      /* ---- per-tile radii (subtle relief) ---- */
      this.tileRadius = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        this.tileRadius[i] = R * (1 + (world.isLand[i] ? world.hLand[i] * 0.035 : 0));
      }

      /* ---- shared-corner radius smoothing (avoid cracks) ---- */
      // corner key -> accumulated radius + count
      const cornerKey = (p) =>
        (Math.round(p[0] * 1e5)) + ',' + (Math.round(p[1] * 1e5)) + ',' + (Math.round(p[2] * 1e5));
      const cornerRad = new Map();
      for (let i = 0; i < N; i++) {
        for (const c of tiles[i].corners) {
          const k = cornerKey(c);
          const e = cornerRad.get(k);
          if (e) { e.sum += this.tileRadius[i]; e.n++; }
          else cornerRad.set(k, { sum: this.tileRadius[i], n: 1 });
        }
      }
      this.cornerRadius = (p) => {
        const e = cornerRad.get(cornerKey(p));
        return e ? e.sum / e.n : R;
      };

      /* ---- neighbor edge lookup: tile i + neighbor j -> [cornerA, cornerB] ---- */
      // corner key -> tiles using it
      const cornerTiles = new Map();
      for (let i = 0; i < N; i++) {
        tiles[i].corners.forEach((c, ci) => {
          const k = cornerKey(c);
          if (!cornerTiles.has(k)) cornerTiles.set(k, []);
          cornerTiles.get(k).push([i, ci]);
        });
      }
      // for each tile, edgeOfNeighbor: Map(neighborId -> [ci1, ci2]) where ci are
      // consecutive corner indices in this tile's winding
      this.edgeOfNeighbor = new Array(N);
      for (let i = 0; i < N; i++) {
        const m = new Map();
        const cs = tiles[i].corners;
        const L = cs.length;
        for (let ci = 0; ci < L; ci++) {
          const c1 = cs[ci], c2 = cs[(ci + 1) % L];
          // the neighbor sharing corners c1 & c2
          const t1 = cornerTiles.get(cornerKey(c1)).map((x) => x[0]);
          const t2 = cornerTiles.get(cornerKey(c2)).map((x) => x[0]);
          for (const tj of t1) {
            if (tj !== i && t2.includes(tj)) { m.set(tj, [ci, (ci + 1) % L]); break; }
          }
        }
        this.edgeOfNeighbor[i] = m;
      }

      /* ---- main tile mesh ---- */
      let vertCount = 0, triCount = 0;
      for (let i = 0; i < N; i++) {
        vertCount += 1 + tiles[i].corners.length;
        triCount += tiles[i].corners.length;
      }
      const positions = new Float32Array(vertCount * 3);
      const colors = new Float32Array(vertCount * 3);
      const indices = new Uint32Array(triCount * 3);
      this.triToTile = new Int32Array(triCount);
      this.tileVertStart = new Int32Array(N); // first vertex index of tile
      this.tileVertCount = new Int32Array(N);

      let vp = 0, ip = 0, tp = 0;
      for (let i = 0; i < N; i++) {
        const t = tiles[i];
        const rC = this.tileRadius[i];
        const baseV = vp / 3;
        this.tileVertStart[i] = baseV;
        this.tileVertCount[i] = 1 + t.corners.length;
        positions[vp++] = t.center[0] * rC;
        positions[vp++] = t.center[1] * rC;
        positions[vp++] = t.center[2] * rC;
        for (const c of t.corners) {
          const rr = this.cornerRadius(c);
          positions[vp++] = c[0] * rr;
          positions[vp++] = c[1] * rr;
          positions[vp++] = c[2] * rr;
        }
        const L = t.corners.length;
        for (let k = 0; k < L; k++) {
          indices[ip++] = baseV;
          indices[ip++] = baseV + 1 + k;
          indices[ip++] = baseV + 1 + ((k + 1) % L);
          this.triToTile[tp++] = i;
        }
      }

      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
      geo.setIndex(new THREE.BufferAttribute(indices, 1));
      geo.computeVertexNormals();
      this.colorAttr = geo.getAttribute('color');

      const mat = new THREE.MeshLambertMaterial({ vertexColors: true });
      this.mesh = new THREE.Mesh(geo, mat);
      this.mesh.name = 'globe';
      scene.add(this.mesh);

      /* ---- tile edge lines (subtle) ---- */
      {
        const segs = [];
        const seen = new Set();
        for (let i = 0; i < N; i++) {
          const cs = tiles[i].corners;
          for (let k = 0; k < cs.length; k++) {
            const a = cs[k], b = cs[(k + 1) % cs.length];
            const ka = cornerKey(a), kb = cornerKey(b);
            const ek = ka < kb ? ka + '|' + kb : kb + '|' + ka;
            if (seen.has(ek)) continue;
            seen.add(ek);
            const ra = this.cornerRadius(a) + 0.03, rb = this.cornerRadius(b) + 0.03;
            segs.push(a[0] * ra, a[1] * ra, a[2] * ra, b[0] * rb, b[1] * rb, b[2] * rb);
          }
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(segs), 3));
        this.edgeLines = new THREE.LineSegments(
          g, new THREE.LineBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.13 })
        );
        scene.add(this.edgeLines);
      }

      /* ---- nation border ribbons (rebuilt on change) ---- */
      this.borderMesh = null;

      /* ---- selection / hover outlines ---- */
      this.selLine = this._makeOutline(0xffffff, 0.95, 2);
      this.hoverLine = this._makeOutline(0xffe66d, 0.6, 1);

      /* ---- raycaster ---- */
      this._raycaster = new THREE.Raycaster();
    }

    _makeOutline(color, opacity) {
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(21 * 3), 3));
      const line = new THREE.LineLoop(
        g, new THREE.LineBasicMaterial({ color, transparent: true, opacity })
      );
      line.visible = false;
      this.scene.add(line);
      return line;
    }

    _setOutlineTile(line, tileId, lift) {
      if (tileId == null || tileId < 0) { line.visible = false; return; }
      const t = this.world.tiles[tileId];
      const pos = line.geometry.getAttribute('position');
      const L = t.corners.length;
      for (let k = 0; k < L; k++) {
        const c = t.corners[k];
        const r = this.cornerRadius(c) + lift;
        pos.setXYZ(k, c[0] * r, c[1] * r, c[2] * r);
      }
      line.geometry.setDrawRange(0, L);
      pos.needsUpdate = true;
      line.visible = true;
    }

    setSelection(tileId) { this._setOutlineTile(this.selLine, tileId, 0.25); }
    setHover(tileId) { this._setOutlineTile(this.hoverLine, tileId, 0.18); }

    /** recolor every tile: colorFn(tileId) -> [r,g,b] (0..1) */
    rebuildColors(colorFn) {
      const arr = this.colorAttr.array;
      const N = this.world.N;
      for (let i = 0; i < N; i++) {
        const [r, g, b] = colorFn(i);
        const start = this.tileVertStart[i];
        const cnt = this.tileVertCount[i];
        for (let v = 0; v < cnt; v++) {
          const o = (start + v) * 3;
          arr[o] = r; arr[o + 1] = g; arr[o + 2] = b;
        }
      }
      this.colorAttr.needsUpdate = true;
    }

    /** recolor a single tile */
    setTileColor(i, rgb) {
      const arr = this.colorAttr.array;
      const start = this.tileVertStart[i];
      const cnt = this.tileVertCount[i];
      for (let v = 0; v < cnt; v++) {
        const o = (start + v) * 3;
        arr[o] = rgb[0]; arr[o + 1] = rgb[1]; arr[o + 2] = rgb[2];
      }
      this.colorAttr.needsUpdate = true;
    }

    /**
     * Rebuild nation border ribbons.
     * ownerOf(i) -> nation id or -1 ; colorOf(nationId) -> [r,g,b]
     * visibleFn(i) -> bool (fog: hide borders on unknown tiles)
     */
    setBorders(ownerOf, colorOf, visibleFn) {
      if (this.borderMesh) {
        this.scene.remove(this.borderMesh);
        this.borderMesh.geometry.dispose();
        this.borderMesh = null;
      }
      const tiles = this.world.tiles;
      const N = this.world.N;
      const pos = [], col = [], idx = [];
      const INSET = 0.22, LIFT = 0.35;
      for (let i = 0; i < N; i++) {
        const o = ownerOf(i);
        if (o === -1 || o === undefined) continue;
        if (visibleFn && !visibleFn(i)) continue;
        const rgb = colorOf(o);
        const t = tiles[i];
        for (const nb of t.neighbors) {
          if (ownerOf(nb) === o) continue; // internal edge
          const edge = this.edgeOfNeighbor[i].get(nb);
          if (!edge) continue;
          const c1 = t.corners[edge[0]], c2 = t.corners[edge[1]];
          const r1 = this.cornerRadius(c1) + LIFT, r2 = this.cornerRadius(c2) + LIFT;
          const rc = this.tileRadius[i] + LIFT;
          // outer edge points
          const p1 = [c1[0] * r1, c1[1] * r1, c1[2] * r1];
          const p2 = [c2[0] * r2, c2[1] * r2, c2[2] * r2];
          // inner points pulled toward tile center
          const ctr = [t.center[0] * rc, t.center[1] * rc, t.center[2] * rc];
          const q1 = [TG.lerp(p1[0], ctr[0], INSET), TG.lerp(p1[1], ctr[1], INSET), TG.lerp(p1[2], ctr[2], INSET)];
          const q2 = [TG.lerp(p2[0], ctr[0], INSET), TG.lerp(p2[1], ctr[1], INSET), TG.lerp(p2[2], ctr[2], INSET)];
          const base = pos.length / 3;
          pos.push(...p1, ...p2, ...q2, ...q1);
          for (let k = 0; k < 4; k++) col.push(rgb[0], rgb[1], rgb[2]);
          idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
        }
      }
      if (!pos.length) return;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pos), 3));
      g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(col), 3));
      g.setIndex(idx);
      const m = new THREE.MeshBasicMaterial({
        vertexColors: true, transparent: true, opacity: 0.85,
        depthWrite: false, side: THREE.DoubleSide,
      });
      this.borderMesh = new THREE.Mesh(g, m);
      this.scene.add(this.borderMesh);
    }

    /** returns tileId under NDC mouse coords, or -1 */
    pick(ndcX, ndcY, camera) {
      this._raycaster.setFromCamera({ x: ndcX, y: ndcY }, camera);
      const hits = this._raycaster.intersectObject(this.mesh, false);
      if (!hits.length) return -1;
      return this.triToTile[hits[0].faceIndex];
    }

    /** world-space position slightly above tile center (for markers) */
    tileWorldPos(i, lift = 0) {
      const t = this.world.tiles[i];
      const r = this.tileRadius[i] + lift;
      return new THREE.Vector3(t.center[0] * r, t.center[1] * r, t.center[2] * r);
    }
  }

  TG.Globe = Globe;
  TG.GLOBE_RADIUS = R;
})();
