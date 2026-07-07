/* ============================================================
 *  AEONS — RTS globe camera
 *  Drag to rotate (left-drag past a threshold, or middle-drag),
 *  wheel to zoom, WASD/arrows to pan, inertia for a smooth feel.
 *  Rotation speed scales with zoom so close-up control stays fine.
 * ============================================================ */
'use strict';
(function () {

  class GlobeCamera {
    constructor(camera, dom, radius) {
      this.camera = camera;
      this.dom = dom;
      this.R = radius;

      this.theta = 0.6;              // longitude angle
      this.phi = 1.1;                // polar angle (0..PI)
      this.dist = radius * 3.0;
      this.minDist = radius * 1.18;
      this.maxDist = radius * 4.2;

      this.vTheta = 0;               // inertia velocities
      this.vPhi = 0;

      this._dragging = false;
      this._dragButton = -1;
      this._moved = 0;               // px moved since mousedown (click vs drag)
      this._last = { x: 0, y: 0 };
      this._keys = {};

      dom.addEventListener('mousedown', (e) => this._onDown(e));
      window.addEventListener('mousemove', (e) => this._onMove(e));
      window.addEventListener('mouseup', (e) => this._onUp(e));
      dom.addEventListener('wheel', (e) => this._onWheel(e), { passive: false });
      window.addEventListener('keydown', (e) => { this._keys[e.code] = true; });
      window.addEventListener('keyup', (e) => { this._keys[e.code] = false; });
      dom.addEventListener('contextmenu', (e) => e.preventDefault());

      this.update(0);
    }

    /** was the last mouse press a click (not a drag)? */
    wasClick() { return this._moved < 5; }

    _onDown(e) {
      if (e.target !== this.dom) return;
      this._dragging = true;
      this._dragButton = e.button;
      this._moved = 0;
      this._last = { x: e.clientX, y: e.clientY };
    }

    _onMove(e) {
      if (!this._dragging) return;
      const dx = e.clientX - this._last.x;
      const dy = e.clientY - this._last.y;
      this._moved += Math.abs(dx) + Math.abs(dy);
      this._last = { x: e.clientX, y: e.clientY };
      if (this._moved < 5) return; // still a click
      const speed = this._rotSpeed();
      this.theta -= dx * speed;
      this.phi -= dy * speed;
      this.vTheta = -dx * speed;
      this.vPhi = -dy * speed;
      this._clampPhi();
    }

    _onUp() { this._dragging = false; this._dragButton = -1; }

    _onWheel(e) {
      e.preventDefault();
      const f = Math.exp(e.deltaY * 0.0012);
      this.dist = TG.clamp(this.dist * f, this.minDist, this.maxDist);
    }

    _rotSpeed() {
      // closer = slower rotation for precision
      const zoomT = (this.dist - this.minDist) / (this.maxDist - this.minDist);
      return 0.0016 + 0.0068 * zoomT;
    }

    _clampPhi() {
      this.phi = TG.clamp(this.phi, 0.05, Math.PI - 0.05);
    }

    update(dt) {
      // keyboard pan
      const ks = this._keys;
      const kSpeed = this._rotSpeed() * 420 * dt;
      if (ks['KeyA'] || ks['ArrowLeft']) this.theta += kSpeed;
      if (ks['KeyD'] || ks['ArrowRight']) this.theta -= kSpeed;
      if (ks['KeyW'] || ks['ArrowUp']) this.phi -= kSpeed;
      if (ks['KeyS'] || ks['ArrowDown']) this.phi += kSpeed;
      if (ks['KeyQ']) this.dist = TG.clamp(this.dist * (1 + 0.9 * dt), this.minDist, this.maxDist);
      if (ks['KeyE']) this.dist = TG.clamp(this.dist * (1 - 0.9 * dt), this.minDist, this.maxDist);

      // inertia
      if (!this._dragging) {
        this.theta += this.vTheta;
        this.phi += this.vPhi;
        this.vTheta *= 0.90;
        this.vPhi *= 0.90;
        if (Math.abs(this.vTheta) < 1e-5) this.vTheta = 0;
        if (Math.abs(this.vPhi) < 1e-5) this.vPhi = 0;
      }
      this._clampPhi();

      const sp = Math.sin(this.phi), cp = Math.cos(this.phi);
      const st = Math.sin(this.theta), ct = Math.cos(this.theta);
      this.camera.position.set(
        this.dist * sp * ct,
        this.dist * cp,
        this.dist * sp * st
      );
      this.camera.lookAt(0, 0, 0);
    }

    /** smoothly fly the camera to look at a tile center (unit vector) */
    focusOn(centerVec) {
      const [x, y, z] = centerVec;
      this.theta = Math.atan2(z, x);
      this.phi = Math.acos(TG.clamp(y, -1, 1));
      this._clampPhi();
      this.vTheta = 0; this.vPhi = 0;
    }
  }

  TG.GlobeCamera = GlobeCamera;
})();
