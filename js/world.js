// Giang Hồ Xóm — logic thế giới thuần (Bước 2): di chuyển, va chạm, nhảy, đấm/túm (hiệu ứng ở Bước 4)
// Không phụ thuộc Three.js/DOM để test bằng Node được.
(function (global) {
  'use strict';

  var BOUNDS = { minX: -40, maxX: 40, minZ: -27, maxZ: 27 };
  var PLAYER_R = 0.55;          // bán kính va chạm của nhân vật
  var WALK = 6, RUN = 9.5;       // tốc độ đi / chạy (đơn vị/giây)
  var RUN_AT = 0.85;             // kéo joystick quá mức này thì chạy
  var GRAVITY = -24, JUMP_V = 8.6;
  var PUNCH_TIME = 0.32, GRAB_TIME = 0.45;

  // Vật cản tĩnh: nhà hai bên phố + sạp giữa sân. game3d.js vẽ đúng theo danh sách này.
  // x,z = tâm; hw,hd = nửa rộng / nửa sâu; h = chiều cao nhà (chỉ để vẽ); sign = biển hiệu
  var OBSTACLES = [
    { x: -30, z: -21, hw: 7, hd: 4.5, h: 9, sign: 'TẠP HÓA', color: 0xc9552e },
    { x: -15, z: -21, hw: 7, hd: 4.5, h: 11, sign: 'CHỢ MỚI', color: 0x1f7a6d },
    { x: 0, z: -21, hw: 7, hd: 4.5, h: 8, sign: 'TRÀ ĐÁ', color: 0x8a5fb0 },
    { x: 15, z: -21, hw: 7, hd: 4.5, h: 10, sign: 'TIỆM CƠM', color: 0xb03a2e },
    { x: 30, z: -21, hw: 7, hd: 4.5, h: 9, sign: 'CÀ PHÊ', color: 0x546e7a },
    { x: -30, z: 21, hw: 7, hd: 4.5, h: 10, sign: 'HỦ TIẾU', color: 0xa0522d },
    { x: -15, z: 21, hw: 7, hd: 4.5, h: 8, sign: 'SỬA XE', color: 0x37474f },
    { x: 0, z: 21, hw: 7, hd: 4.5, h: 11, sign: 'TẠP HÓA 2', color: 0x2e7d32 },
    { x: 15, z: 21, hw: 7, hd: 4.5, h: 9, sign: 'BÁNH MÌ', color: 0xd35400 },
    { x: 30, z: 21, hw: 7, hd: 4.5, h: 8, sign: 'NET XÓM', color: 0x283593 },
    { x: -9, z: 6, hw: 2.2, hd: 1.6, h: 2.4, sign: 'SẠP', color: 0x795548 },
    { x: 11, z: -6, hw: 2.2, hd: 1.6, h: 2.4, sign: 'SẠP', color: 0x6d4c41 }
  ];

  function createPlayer(name, x, z) {
    return {
      name: name || 'Người chơi',
      x: x || 0, y: 0, z: (typeof z === 'number' ? z : 10),
      vx: 0, vz: 0, vy: 0,
      heading: Math.PI, // quay mặt về -z (vào phố)
      moving: false, running: false, grounded: true,
      punchT: 0, grabT: 0, animT: 0
    };
  }

  // Joystick: dx,dy theo pixel so với tâm, radius = bán kính đế.
  // Trả {x, y, mag} đã qua vùng chết + chuẩn hoá độ dài <= 1 (y dương = kéo xuống).
  function joystickVector(dx, dy, radius) {
    var len = Math.sqrt(dx * dx + dy * dy);
    if (!radius || radius <= 0 || len < radius * 0.18) return { x: 0, y: 0, mag: 0 };
    var mag = Math.min(1, len / radius);
    return { x: dx / len * mag, y: dy / len * mag, mag: mag };
  }

  function hitsObstacle(x, z) {
    for (var i = 0; i < OBSTACLES.length; i++) {
      var o = OBSTACLES[i];
      if (Math.abs(x - o.x) < o.hw + PLAYER_R && Math.abs(z - o.z) < o.hd + PLAYER_R) return o;
    }
    return null;
  }

  // input: {x: -1..1 (trái/phải), z: -1..1 (lên/xuống theo thế giới), jump: bool}
  function stepPlayer(p, input, dt) {
    if (dt > 0.05) dt = 0.05; // chống giật khi tab bị treo
    var mag = Math.sqrt(input.x * input.x + input.z * input.z);
    if (mag > 1) { input = { x: input.x / mag, z: input.z / mag, jump: input.jump }; mag = 1; }
    p.moving = mag > 0.01;
    p.running = p.moving && mag >= RUN_AT;
    var speed = p.running ? RUN : WALK;
    if (p.moving) p.heading = Math.atan2(input.x, input.z);

    // Di chuyển tách trục để trượt dọc tường thay vì dính cứng
    var nx = p.x + input.x * speed * dt;
    if (!hitsObstacle(nx, p.z)) p.x = nx;
    var nz = p.z + input.z * speed * dt;
    if (!hitsObstacle(p.x, nz)) p.z = nz;
    p.x = Math.max(BOUNDS.minX, Math.min(BOUNDS.maxX, p.x));
    p.z = Math.max(BOUNDS.minZ, Math.min(BOUNDS.maxZ, p.z));
    p.vx = p.moving ? input.x * speed : 0;
    p.vz = p.moving ? input.z * speed : 0;

    // Nhảy + trọng lực
    if (input.jump && p.grounded) { p.vy = JUMP_V; p.grounded = false; }
    if (!p.grounded) {
      p.y += p.vy * dt;
      p.vy += GRAVITY * dt;
      if (p.y <= 0) { p.y = 0; p.vy = 0; p.grounded = true; }
    }

    if (p.punchT > 0) p.punchT = Math.max(0, p.punchT - dt);
    if (p.grabT > 0) p.grabT = Math.max(0, p.grabT - dt);
    if (p.moving && p.grounded) p.animT += dt * (p.running ? 11 : 8);
    return p;
  }

  function startPunch(p) { if (p.punchT <= 0 && p.grabT <= 0) p.punchT = PUNCH_TIME; }
  function startGrab(p) { if (p.grabT <= 0 && p.punchT <= 0) p.grabT = GRAB_TIME; }

  var api = {
    BOUNDS: BOUNDS, OBSTACLES: OBSTACLES, PLAYER_R: PLAYER_R,
    WALK: WALK, RUN: RUN, RUN_AT: RUN_AT, PUNCH_TIME: PUNCH_TIME, GRAB_TIME: GRAB_TIME,
    createPlayer: createPlayer, joystickVector: joystickVector,
    hitsObstacle: hitsObstacle, stepPlayer: stepPlayer,
    startPunch: startPunch, startGrab: startGrab
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.GHXWorld = api;
})(typeof window !== 'undefined' ? window : globalThis);
