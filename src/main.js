/* ============================================================
 *  AEONS — application bootstrap & render loop
 * ============================================================ */
'use strict';
(function () {

  const App = (TG.App = {
    renderer: null, scene: null, camera: null, ctrl: null,
    world: null, globe: null, game: null, markers: null,
    lens: 'terrain',
    hoverTile: -1, selectedTile: -1,
    revealAll: false,
    colorsDirty: true,
    bordersDirty: true,
  });

  function initThree() {
    const canvas = document.getElementById('c');
    App.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    App.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    App.renderer.setSize(window.innerWidth, window.innerHeight);
    App.renderer.setClearColor(0x05070d);

    App.scene = new THREE.Scene();
    App.camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 1, 20000);

    App.scene.add(new THREE.AmbientLight(0xffffff, 0.78));
    App.sun = new THREE.DirectionalLight(0xffffff, 0.45);
    App.scene.add(App.sun);

    // starfield
    {
      const n = 1600, pos = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        const v = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5)
          .normalize().multiplyScalar(6000 + Math.random() * 2000);
        pos.set([v.x, v.y, v.z], i * 3);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      App.scene.add(new THREE.Points(g, new THREE.PointsMaterial({
        color: 0x8899bb, size: 2.2, sizeAttenuation: false, transparent: true, opacity: 0.7,
      })));
    }

    window.addEventListener('resize', () => {
      App.camera.aspect = window.innerWidth / window.innerHeight;
      App.camera.updateProjectionMatrix();
      App.renderer.setSize(window.innerWidth, window.innerHeight);
    });
  }

  /* ---------- picking / input ---------- */
  let lastPickAt = 0;
  function initPicking() {
    const canvas = App.renderer.domElement;
    canvas.addEventListener('mousemove', (e) => {
      const now = performance.now();
      if (now - lastPickAt < 30 || !App.globe) return;
      lastPickAt = now;
      const t = pickAt(e);
      if (t !== App.hoverTile) {
        App.hoverTile = t;
        App.globe.setHover(t);
        if (TG.UI) TG.UI.onHoverTile(t, e);
      } else if (TG.UI) TG.UI.moveTooltip(e);
    });
    canvas.addEventListener('mouseup', (e) => {
      if (!App.globe || !App.ctrl.wasClick()) return;
      const t = pickAt(e);
      if (e.button === 0) {
        App.selectedTile = t;
        App.globe.setSelection(t);
        if (TG.UI) TG.UI.onSelectTile(t);
      } else if (e.button === 2) {
        if (TG.UI) TG.UI.onRightClickTile(t);
      }
    });
  }
  function pickAt(e) {
    const r = App.renderer.domElement.getBoundingClientRect();
    const x = ((e.clientX - r.left) / r.width) * 2 - 1;
    const y = -((e.clientY - r.top) / r.height) * 2 + 1;
    return App.globe.pick(x, y, App.camera);
  }

  /* ---------- game start ---------- */
  function startGame(params) {
    // tear down previous session if any
    if (App.globe) { App.scene.remove(App.globe.mesh, App.globe.edgeLines); }
    document.getElementById('menu').classList.add('hidden');
    document.getElementById('hud').classList.remove('hidden');

    App.world = TG.generateWorld(params);
    App.globe = new TG.Globe(App.scene, App.world);
    App.ctrl = App.ctrl || new TG.GlobeCamera(App.camera, App.renderer.domElement, TG.GLOBE_RADIUS);

    if (TG.Game) {
      App.game = new TG.Game(App.world, params);
      App.game.onDirty = () => { App.colorsDirty = true; App.bordersDirty = true; };
      if (TG.Markers) App.markers = new TG.Markers(App.scene, App.globe, App.game);
      const cap = App.game.nations[App.game.humanId].capitalTile;
      if (cap != null) App.ctrl.focusOn(App.world.tiles[cap].center);
    }
    if (TG.UI) TG.UI.init(App);

    App.colorsDirty = true;
    App.bordersDirty = true;
  }
  TG.startGame = startGame;

  function refreshColorsIfNeeded() {
    if (App.colorsDirty && App.globe) {
      App.globe.rebuildColors((i) => TG.tileDisplayColor(App, i));
      App.colorsDirty = false;
    }
    if (App.bordersDirty && App.globe && App.game) {
      App.globe.setBorders(
        (i) => App.game.ownerOf(i),
        (o) => App.game.nations[o].rgb,
        (i) => App.revealAll || App.game.fog.stateFor(App.game.humanId, i) > 0
      );
      App.bordersDirty = false;
    }
  }

  /* ---------- main loop ---------- */
  // requestAnimationFrame stalls in hidden/background tabs, so the game
  // falls back to a coarse setInterval driver to keep simulating.
  let lastT = 0;
  let hiddenTimer = null;
  function loop(t) {
    if (!document.hidden) requestAnimationFrame(loop);
    const dt = Math.min(0.1, (t - lastT) / 1000 || 0.016);
    lastT = t;
    if (App.ctrl) {
      App.ctrl.update(dt);
      App.sun.position.copy(App.camera.position).multiplyScalar(1.2);
    }
    if (App.game) App.game.update(dt);
    refreshColorsIfNeeded();
    if (App.markers) App.markers.update();
    if (TG.UI && App.game) TG.UI.update(dt);
    App.renderer.render(App.scene, App.camera);
  }

  function startLoopDriver() {
    if (document.hidden) {
      if (!hiddenTimer) hiddenTimer = setInterval(() => loop(performance.now()), 100);
    } else {
      if (hiddenTimer) { clearInterval(hiddenTimer); hiddenTimer = null; }
      requestAnimationFrame(loop);
    }
  }

  window.addEventListener('DOMContentLoaded', () => {
    initThree();
    initPicking();
    document.addEventListener('visibilitychange', startLoopDriver);
    startLoopDriver();
    const q = new URLSearchParams(location.search);
    if (TG.Menu && !q.get('seed')) {
      TG.Menu.show();
    } else {
      // dev / quick-start mode: ?seed=FOO&size=20
      startGame({ seed: q.get('seed') || TG.randomSeedString(), size: parseInt(q.get('size')) || 20 });
    }
  });
})();
