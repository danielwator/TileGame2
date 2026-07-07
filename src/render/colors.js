/* ============================================================
 *  AEONS — tile display colors
 *  Terrain painting + map lenses + fog-of-war shading + owner tint
 * ============================================================ */
'use strict';
(function () {

  const SNOW = [0.94, 0.95, 0.97];
  const URBAN = [0.80, 0.77, 0.70];

  // deterministic small per-tile variation so terrain doesn't look flat
  function jitter(world, i) {
    const c = world.tiles[i].center;
    const x = Math.sin(c[0] * 91.7 + c[1] * 233.1 + c[2] * 47.9) * 24634.63;
    return (x - Math.floor(x)) * 0.09 - 0.045;
  }

  const biomeRgbCache = {};
  function biomeRgb(id) {
    if (!biomeRgbCache[id]) biomeRgbCache[id] = TG.hexToRgb(window.BIOMES[id].color);
    return biomeRgbCache[id];
  }

  /** natural terrain color of a tile */
  function terrainColor(world, i) {
    const b = world.biome[i];
    let rgb = biomeRgb(b).slice();
    const deep = biomeRgb('deepOcean');

    if (!world.isLand[i]) {
      if (b === 'coast') {
        rgb = TG.mixRgb(rgb, biomeRgb('ocean'), TG.clamp(world.hDepth[i] * 3.5, 0, 0.55));
      } else if (b === 'ocean') {
        rgb = TG.mixRgb(rgb, deep, TG.smoothstep(0.16, 0.5, world.hDepth[i]));
      } else if (b === 'deepOcean') {
        rgb = TG.mixRgb(rgb, TG.scaleRgb(deep, 0.72), TG.smoothstep(0.5, 1, world.hDepth[i]));
      } else if (b === 'iceCap') {
        rgb = TG.mixRgb(rgb, [0.8, 0.87, 0.93], 0.25);
      }
      return rgb;
    }

    // land: altitude & cold shading
    const h = world.hLand[i], t = world.temp[i];
    if (b === 'mountain') {
      rgb = TG.mixRgb(rgb, SNOW, TG.smoothstep(0.55, 0.9, h + (0.24 - Math.min(t, 0.24))));
    } else if (b === 'highlands') {
      rgb = TG.mixRgb(rgb, biomeRgb('mountain'), TG.smoothstep(0.30, 0.52, h) * 0.5);
    }
    if (t < 0.20 && b !== 'iceCap') {
      rgb = TG.mixRgb(rgb, SNOW, (0.20 - t) / 0.20 * 0.55);   // frost dusting
    }
    const j = jitter(world, i);
    rgb = [TG.clamp(rgb[0] + j, 0, 1), TG.clamp(rgb[1] + j, 0, 1), TG.clamp(rgb[2] + j, 0, 1)];
    return rgb;
  }

  /* ---------- lenses ---------- */
  const PLATE_COLORS = [
    '#e6194b', '#3cb44b', '#ffe119', '#4363d8', '#f58231', '#911eb4', '#46f0f0',
    '#f032e6', '#bcf60c', '#fabebe', '#008080', '#e6beff', '#9a6324', '#fffac8',
    '#800000', '#aaffc3', '#808000', '#ffd8b1', '#000075', '#808080',
  ].map(TG.hexToRgb);

  function ramp(t, stops) {
    t = TG.clamp(t, 0, 1) * (stops.length - 1);
    const k = Math.min(Math.floor(t), stops.length - 2);
    return TG.mixRgb(stops[k], stops[k + 1], t - k);
  }
  const ELEV_STOPS = [[0.05, 0.1, 0.35], [0.2, 0.45, 0.75], [0.5, 0.75, 0.55], [0.85, 0.8, 0.4], [0.6, 0.3, 0.15], [1, 1, 1]];
  const TEMP_STOPS = [[0.75, 0.85, 1], [0.4, 0.6, 0.95], [0.5, 0.85, 0.5], [0.95, 0.85, 0.3], [0.9, 0.3, 0.15]];
  const MOIST_STOPS = [[0.85, 0.7, 0.35], [0.75, 0.8, 0.45], [0.45, 0.75, 0.5], [0.25, 0.55, 0.8], [0.1, 0.25, 0.7]];

  const LENSES = ['terrain', 'political', 'biome', 'elevation', 'temperature', 'moisture', 'plates'];

  /**
   * Final display color for a tile, given the app state
   * (lens, fog of war for the human player, nation tint, cities).
   */
  function tileDisplayColor(app, i) {
    const world = app.world;
    const game = app.game;

    // fog state for the human player: 0 unknown, 1 discovered, 2 visible
    let fog = 2;
    if (game && game.fog && !app.revealAll) fog = game.fog.stateFor(game.humanId, i);
    if (fog === 0) return [0.028, 0.034, 0.05];

    let rgb;
    switch (app.lens) {
      case 'biome':
        rgb = biomeRgb(world.biome[i]).slice(); break;
      case 'elevation':
        rgb = ramp(world.isLand[i] ? 0.35 + world.hLand[i] * 0.65 : 0.35 - world.hDepth[i] * 0.35, ELEV_STOPS); break;
      case 'temperature':
        rgb = ramp(world.temp[i], TEMP_STOPS); break;
      case 'moisture':
        rgb = ramp(world.moist[i], MOIST_STOPS); break;
      case 'plates':
        rgb = PLATE_COLORS[world.plateOf[i] % PLATE_COLORS.length].slice();
        if (world.isBoundary[i]) rgb = TG.scaleRgb(rgb, 0.55);
        break;
      case 'political': {
        rgb = TG.mixRgb(terrainColor(world, i), [0.6, 0.6, 0.6], 0.55);
        if (game) {
          const o = game.ownerOf(i);
          if (o >= 0) rgb = TG.mixRgb(rgb, game.nations[o].rgb, 0.75);
        }
        break;
      }
      default: { // terrain (main game view)
        rgb = terrainColor(world, i);
        if (game) {
          const o = game.ownerOf(i);
          if (o >= 0) rgb = TG.mixRgb(rgb, game.nations[o].rgb, 0.13);
          const city = game.cityAt(i);
          if (city !== null && fog === 2) rgb = TG.mixRgb(rgb, URBAN, 0.6);
          else if (fog === 2 && game.buildingAt(i)) rgb = TG.mixRgb(rgb, URBAN, 0.22);
        }
      }
    }

    if (fog === 1) {
      // discovered but not visible: darkened, slightly desaturated
      const g = (rgb[0] + rgb[1] + rgb[2]) / 3;
      rgb = TG.mixRgb(rgb, [g, g, g], 0.35);
      rgb = TG.scaleRgb(rgb, 0.45);
    }
    return rgb;
  }

  TG.terrainColor = terrainColor;
  TG.tileDisplayColor = tileDisplayColor;
  TG.LENSES = LENSES;
})();
