/* ============================================================
 *  AEONS — Fog of war
 *
 *  Three states per nation per tile:
 *   0 UNKNOWN    — never seen; rendered near-black
 *   1 DISCOVERED — terrain/deposit/owner intel visible but dimmed;
 *                  units and current activity hidden
 *   2 VISIBLE    — full detail: owned tiles + 2 rings beyond the
 *                  border, unit sight radii, allied shared vision
 * ============================================================ */
'use strict';
(function () {

  class Fog {
    constructor(game) {
      this.game = game;
      const N = game.world.N;
      this.discovered = game.nations.map(() => new Uint8Array(N));
      this.visible = game.nations.map(() => new Uint8Array(N));
      this._scratch = new Int32Array(N);
    }

    /** expand visibility outward from source tiles by `range` hops */
    _spread(vis, sources, range) {
      const tiles = this.game.world.tiles;
      const dist = this._scratch.fill(-1);
      const q = [];
      for (const s of sources) {
        if (dist[s] === -1) { dist[s] = 0; q.push(s); vis[s] = 1; }
      }
      let head = 0;
      while (head < q.length) {
        const cur = q[head++];
        if (dist[cur] >= range) continue;
        for (const nb of tiles[cur].neighbors) {
          if (dist[nb] === -1) {
            dist[nb] = dist[cur] + 1;
            vis[nb] = 1;
            q.push(nb);
          }
        }
      }
    }

    recomputeAll() {
      const g = this.game;
      const N = g.world.N;
      // pass 1: own vision
      for (let n = 0; n < g.nations.length; n++) {
        const nat = g.nations[n];
        const vis = this.visible[n];
        vis.fill(0);
        if (!nat.alive) continue;
        const bonus = nat.modInt('vision');
        // owned territory + 2 rings (+vision bonus)
        const owned = [];
        for (let i = 0; i < N; i++) if (g.owner[i] === n) owned.push(i);
        this._spread(vis, owned, 2 + bonus);
        // units
        for (const u of g.units) {
          if (u.nationId !== n) continue;
          this._spread(vis, [u.tile], window.UNITS[u.type].sight + bonus);
        }
      }
      // pass 2: allied shared vision
      for (let a = 0; a < g.nations.length; a++) {
        for (let b = a + 1; b < g.nations.length; b++) {
          if (g.diplo && g.diplo.status(a, b) === 'alliance') {
            const va = this.visible[a], vb = this.visible[b];
            for (let i = 0; i < N; i++) {
              const u = va[i] | vb[i];
              va[i] = u; vb[i] = u;
            }
          }
        }
      }
      // pass 3: discovery is forever
      for (let n = 0; n < g.nations.length; n++) {
        const d = this.discovered[n], v = this.visible[n];
        for (let i = 0; i < N; i++) if (v[i]) d[i] = 1;
      }
    }

    /** satellites etc: reveal the whole map (terrain intel only) */
    revealAll(nationId) {
      this.discovered[nationId].fill(1);
    }

    stateFor(nationId, tile) {
      if (this.visible[nationId][tile]) return 2;
      if (this.discovered[nationId][tile]) return 1;
      return 0;
    }
  }

  TG.Fog = Fog;
})();
