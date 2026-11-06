// Giang Hồ Xóm — Bước 2: dựng 3D (Three.js), nhân vật, joystick + nút bấm luôn hiện
// Camera cố định bám sau lưng ở Bước 2; xoay/zoom camera là Bước 3.
// Đấm/Túm ở bước này mới có hoạt hình tay; trúng đòn/vật ngã là Bước 4.
(function () {
  'use strict';
  var W = window.GHXWorld;
  var THREE = window.THREE;

  var running = false, raf = 0, renderer = null, scene = null, camera = null;
  var player = null, charGroup = null, parts = null, nameSprite = null;
  var clock = null, camPos = null;
  var joy = { active: false, id: null, x: 0, y: 0, mag: 0 };
  var keys = {};
  var els = {};

  function makeSignTexture(text, bg) {
    var c = document.createElement('canvas'); c.width = 512; c.height = 128;
    var g = c.getContext('2d');
    g.fillStyle = bg || '#20242c'; g.fillRect(0, 0, 512, 128);
    g.strokeStyle = '#ffd98a'; g.lineWidth = 6; g.strokeRect(8, 8, 496, 112);
    g.fillStyle = '#ffd98a'; g.font = 'bold 58px Arial'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, 256, 68);
    var t = new THREE.CanvasTexture(c); return t;
  }

  function makeNameSprite(name) {
    var c = document.createElement('canvas'); c.width = 256; c.height = 64;
    var g = c.getContext('2d');
    g.font = 'bold 34px Arial'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.lineWidth = 8; g.strokeStyle = 'rgba(0,0,0,.65)'; g.strokeText(name, 128, 32);
    g.fillStyle = '#fff'; g.fillText(name, 128, 32);
    var t = new THREE.CanvasTexture(c);
    var m = new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false });
    var s = new THREE.Sprite(m); s.scale.set(3.4, 0.85, 1); s.position.y = 2.65;
    return s;
  }

  function mat(color) { return new THREE.MeshLambertMaterial({ color: color }); }

  function buildStreet() {
    var ground = new THREE.Mesh(new THREE.PlaneGeometry(120, 90), mat(0x8a8d90));
    ground.rotation.x = -Math.PI / 2; ground.position.y = -0.02; scene.add(ground);

    var road = new THREE.Mesh(new THREE.PlaneGeometry(92, 30), mat(0x4a4d52));
    road.rotation.x = -Math.PI / 2; road.position.y = 0; scene.add(road);

    var plaza = new THREE.Mesh(new THREE.PlaneGeometry(26, 18), mat(0xb8a888));
    plaza.rotation.x = -Math.PI / 2; plaza.position.y = 0.01; scene.add(plaza);

    // Vạch giữa đường
    for (var i = -5; i <= 5; i++) {
      var dash = new THREE.Mesh(new THREE.PlaneGeometry(4, 0.5), mat(0xf5d76e));
      dash.rotation.x = -Math.PI / 2; dash.position.set(i * 8, 0.02, 0); scene.add(dash);
    }

    W.OBSTACLES.forEach(function (o) {
      var isStall = o.h < 3;
      var body = new THREE.Mesh(new THREE.BoxGeometry(o.hw * 2, o.h, o.hd * 2), mat(o.color));
      body.position.set(o.x, o.h / 2, o.z); scene.add(body);
      if (isStall) {
        var roof = new THREE.Mesh(new THREE.BoxGeometry(o.hw * 2 + 1, 0.25, o.hd * 2 + 1), mat(0xd8542e));
        roof.position.set(o.x, o.h + 0.5, o.z); scene.add(roof);
      } else {
        var roof2 = new THREE.Mesh(new THREE.BoxGeometry(o.hw * 2 + 0.6, 0.4, o.hd * 2 + 0.6), mat(0x2c2f36));
        roof2.position.set(o.x, o.h + 0.2, o.z); scene.add(roof2);
        var sign = new THREE.Mesh(new THREE.PlaneGeometry(7.5, 1.9),
          new THREE.MeshBasicMaterial({ map: makeSignTexture(o.sign) }));
        var face = o.z < 0 ? 1 : -1;
        sign.position.set(o.x, o.h - 1.6, o.z + face * (o.hd + 0.06));
        if (face < 0) sign.rotation.y = Math.PI;
        scene.add(sign);
        var awn = new THREE.Mesh(new THREE.BoxGeometry(o.hw * 2, 0.18, 2.2), mat(0xd8542e));
        awn.position.set(o.x, o.h - 3.1, o.z + face * (o.hd + 1)); scene.add(awn);
      }
    });

    // Cột đèn + cây hai bên vỉa hè
    for (var x = -36; x <= 36; x += 12) {
      [-14.5, 14.5].forEach(function (z) {
        var pole = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 4.6), mat(0x37474f));
        pole.position.set(x, 2.3, z); scene.add(pole);
        var bulb = new THREE.Mesh(new THREE.SphereGeometry(0.42, 10, 8),
          new THREE.MeshBasicMaterial({ color: 0xffe9a3 }));
        bulb.position.set(x, 4.8, z); scene.add(bulb);
      });
      [-17.5, 17.5].forEach(function (z) {
        var trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.36, 1.8), mat(0x6d4c41));
        trunk.position.set(x + 6, 0.9, z); scene.add(trunk);
        var leaf = new THREE.Mesh(new THREE.SphereGeometry(1.9, 10, 8), mat(0x3e7d3a));
        leaf.position.set(x + 6, 3.4, z); scene.add(leaf);
      });
    }
  }

  function buildCharacter(name) {
    var g = new THREE.Group();
    var skin = mat(0xf0b98a), shirt = mat(0xf0681a), pants = mat(0x263238), hairM = mat(0x212121);
    function box(w, h, d, m, x, y, z) {
      var b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m); b.position.set(x, y, z); g.add(b); return b;
    }
    var legL = box(0.34, 0.85, 0.38, pants, -0.22, 0.43, 0); legL.geometry.translate(0, -0.1, 0);
    var legR = box(0.34, 0.85, 0.38, pants, 0.22, 0.43, 0); legR.geometry.translate(0, -0.1, 0);
    var body = box(0.95, 1.0, 0.55, shirt, 0, 1.32, 0);
    var armL = box(0.3, 0.9, 0.34, shirt, -0.66, 1.62, 0); armL.geometry.translate(0, -0.32, 0); armL.position.y = 1.78;
    var armR = box(0.3, 0.9, 0.34, shirt, 0.66, 1.62, 0); armR.geometry.translate(0, -0.32, 0); armR.position.y = 1.78;
    var head = box(0.62, 0.62, 0.6, skin, 0, 2.18, 0);
    box(0.68, 0.2, 0.66, hairM, 0, 2.55, 0);
    nameSprite = makeNameSprite(name); g.add(nameSprite);
    scene.add(g);
    return { group: g, legL: legL, legR: legR, armL: armL, armR: armR, body: body, head: head };
  }

  function bindControls() {
    els.joyBase = document.getElementById('joy');
    els.knob = document.getElementById('joy-knob');
    var base = els.joyBase;
    function setKnob(dx, dy) { els.knob.style.transform = 'translate(' + dx + 'px,' + dy + 'px)'; }
    function joyMove(e) {
      var r = base.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      var dx = e.clientX - cx, dy = e.clientY - cy;
      var max = r.width / 2 - 8;
      var len = Math.sqrt(dx * dx + dy * dy);
      if (len > max) { dx = dx / len * max; dy = dy / len * max; }
      setKnob(dx, dy);
      var v = W.joystickVector(dx, dy, max);
      joy.x = v.x; joy.y = v.y; joy.mag = v.mag;
    }
    base.addEventListener('pointerdown', function (e) {
      joy.active = true; joy.id = e.pointerId; base.setPointerCapture(e.pointerId); joyMove(e); e.preventDefault();
    });
    base.addEventListener('pointermove', function (e) { if (joy.active && e.pointerId === joy.id) joyMove(e); });
    function joyEnd(e) {
      if (e.pointerId !== joy.id) return;
      joy.active = false; joy.x = 0; joy.y = 0; joy.mag = 0; setKnob(0, 0);
    }
    base.addEventListener('pointerup', joyEnd);
    base.addEventListener('pointercancel', joyEnd);

    function press(id, fn) {
      var b = document.getElementById(id);
      b.addEventListener('pointerdown', function (e) { e.preventDefault(); fn(); });
    }
    press('btn-jump', function () { jumpQueued = true; });
    press('btn-punch', function () { if (player) W.startPunch(player); });
    press('btn-grab', function () { if (player) W.startGrab(player); });

    window.addEventListener('keydown', function (e) {
      keys[e.code] = true;
      if (e.code === 'Space' || e.code === 'KeyK') jumpQueued = true;
      if (e.code === 'KeyJ' && player) W.startPunch(player);
      if (e.code === 'KeyL' && player) W.startGrab(player);
    });
    window.addEventListener('keyup', function (e) { keys[e.code] = false; });
  }
  var jumpQueued = false;

  function readInput() {
    var x = joy.x, z = joy.y; // kéo xuống = đi về phía camera = +z
    if (keys.KeyA || keys.ArrowLeft) x -= 1;
    if (keys.KeyD || keys.ArrowRight) x += 1;
    if (keys.KeyW || keys.ArrowUp) z -= 1;
    if (keys.KeyS || keys.ArrowDown) z += 1;
    var j = jumpQueued; jumpQueued = false;
    return { x: x, z: z, jump: j };
  }

  function animate() {
    if (!running) return;
    raf = requestAnimationFrame(animate);
    var dt = Math.min(0.05, clock.getDelta());
    W.stepPlayer(player, readInput(), dt);

    var g = charGroup;
    g.position.set(player.x, player.y, player.z);
    g.rotation.y = player.heading;
    var swing = player.moving && player.grounded ? Math.sin(player.animT) * 0.65 : 0;
    parts.legL.rotation.x = swing; parts.legR.rotation.x = -swing;
    parts.armL.rotation.x = -swing; parts.armR.rotation.x = swing;
    if (player.punchT > 0) {
      var p = 1 - player.punchT / W.PUNCH_TIME;
      parts.armR.rotation.x = -Math.sin(p * Math.PI) * 1.7;
    }
    if (player.grabT > 0) {
      var q = 1 - player.grabT / W.GRAB_TIME;
      var fwd = -Math.sin(q * Math.PI) * 1.35;
      parts.armL.rotation.x = fwd; parts.armR.rotation.x = fwd;
    }
    if (!player.grounded) { parts.legL.rotation.x = 0.35; parts.legR.rotation.x = -0.25; }

    // Camera bám sau nhân vật (góc cố định ở Bước 2)
    var target = new THREE.Vector3(player.x, player.y + 8.5, player.z + 13.5);
    camPos.lerp(target, 0.08);
    camera.position.copy(camPos);
    camera.lookAt(player.x, player.y + 1.2, player.z - 2);
    renderer.render(scene, camera);
  }

  function onResize() {
    if (!renderer) return;
    var w = els.wrap.clientWidth, h = els.wrap.clientHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h; camera.updateProjectionMatrix();
  }

  // Three.js nạp từ CDN ở index.html; nếu CDN lỗi thì nạp bản đóng gói kèm js/three.min.js
  function ensureThree(cb) {
    if (window.THREE) { THREE = window.THREE; cb(); return; }
    var s = document.createElement('script');
    s.src = 'js/three.min.js';
    s.onload = function () { THREE = window.THREE; cb(); };
    s.onerror = function () { alert('Không tải được thư viện 3D. Kiểm tra mạng rồi thử lại.'); };
    document.head.appendChild(s);
  }

  function start(opts) { ensureThree(function () { initGame(opts); }); }

  function initGame(opts) {
    els.wrap = document.getElementById('game-wrap');
    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    els.wrap.appendChild(renderer.domElement);
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x87b5d9);
    scene.fog = new THREE.Fog(0x87b5d9, 55, 110);
    camera = new THREE.PerspectiveCamera(55, 1, 0.1, 200);
    scene.add(new THREE.HemisphereLight(0xcfe8ff, 0x6b5a44, 0.95));
    var sun = new THREE.DirectionalLight(0xfff2d0, 0.85);
    sun.position.set(20, 32, 14); scene.add(sun);

    buildStreet();
    player = W.createPlayer(opts.name, 0, 10);
    parts = buildCharacter(opts.name); charGroup = parts.group;
    charGroup.position.set(player.x, 0, player.z);
    camPos = new THREE.Vector3(player.x, 8.5, player.z + 13.5);
    clock = new THREE.Clock();
    bindControls();
    onResize();
    window.addEventListener('resize', onResize);
    running = true;
    animate();
  }

  function stop() {
    running = false;
    cancelAnimationFrame(raf);
    window.removeEventListener('resize', onResize);
    if (renderer) { renderer.dispose(); if (renderer.domElement.parentNode) renderer.domElement.parentNode.removeChild(renderer.domElement); }
    renderer = null; scene = null; camera = null; player = null; parts = null; charGroup = null;
    joy.x = 0; joy.y = 0; joy.mag = 0; keys = {};
  }

  window.GHXGame = { start: start, stop: stop, isRunning: function () { return running; } };
})();
