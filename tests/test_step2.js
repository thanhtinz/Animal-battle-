// Test Bước 2 — chạy: node tests/test_step2.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const W = require('../js/world.js');

let pass = 0;
function ok(name, fn) { fn(); pass++; console.log('PASS', name); }
const DT = 1 / 60;
function run(p, input, seconds) { const n = Math.round(seconds / DT); for (let i = 0; i < n; i++) W.stepPlayer(p, input, DT); }

// --- joystick ---
ok('joystick trong vùng chết = đứng yên', () => {
  const v = W.joystickVector(3, 2, 56); assert.strictEqual(v.mag, 0);
});
ok('joystick kéo hết cỡ: mag = 1, hướng đúng', () => {
  const v = W.joystickVector(100, 0, 56); assert.ok(Math.abs(v.mag - 1) < 1e-9); assert.ok(v.x > 0.99);
});
ok('joystick kéo nửa: mag ~0.5', () => {
  const v = W.joystickVector(0, 28, 56); assert.ok(Math.abs(v.mag - 0.5) < 1e-9); assert.ok(v.y > 0.49);
});

// --- di chuyển ---
ok('đứng yên khi không input', () => { const p = W.createPlayer('A'); run(p, { x: 0, z: 0 }, 1); assert.strictEqual(p.x, 0); });
ok('đi bộ: kéo nửa cần 1 giây đi đúng nửa tốc độ WALK, không chạy', () => {
  const p = W.createPlayer('A'); p.z = 0; run(p, { x: 0.5, z: 0 }, 1);
  assert.ok(Math.abs(p.x - W.WALK * 0.5) < 0.2, 'x=' + p.x); assert.strictEqual(p.running, false);
});
ok('kéo hết cỡ thì chạy nhanh hơn đi bộ', () => {
  const p = W.createPlayer('A'); p.z = 0; // mag của input (1,0) = 1 >= RUN_AT
  run(p, { x: 1, z: 0 }, 0.5);
  assert.strictEqual(p.running, true);
});
ok('input chéo được chuẩn hoá, không nhanh hơn input thẳng', () => {
  const a = W.createPlayer('A'); a.z = 0; run(a, { x: 1, z: 0 }, 1);
  const b = W.createPlayer('B'); b.z = 0; run(b, { x: 1, z: 1 }, 1);
  const da = Math.hypot(a.x, a.z), db = Math.hypot(b.x, b.z);
  assert.ok(Math.abs(da - db) < 0.25, da + ' vs ' + db);
});
ok('nhân vật quay mặt theo hướng đi', () => {
  const p = W.createPlayer('A'); run(p, { x: 1, z: 0 }, 0.1);
  assert.ok(Math.abs(p.heading - Math.PI / 2) < 1e-6);
});

// --- giới hạn map + va chạm ---
ok('không đi ra ngoài biên map', () => {
  const p = W.createPlayer('A'); run(p, { x: -1, z: 0 }, 20);
  assert.ok(p.x >= W.BOUNDS.minX);
});
ok('nhà chặn: đi thẳng vào nhà TẠP HÓA phía bắc thì bị chặn trước tường', () => {
  const house = W.OBSTACLES[0];
  const p = W.createPlayer('A', house.x, 0); run(p, { x: 0, z: -1 }, 10);
  assert.ok(p.z > house.z + house.hd, 'z=' + p.z); // không xuyên qua nhà
  assert.ok(Math.abs(p.z - (house.z + house.hd + W.PLAYER_R)) < 0.6, 'dừng sát tường, z=' + p.z);
});
ok('trượt dọc tường: bị chặn 1 trục vẫn đi được trục kia', () => {
  const house = W.OBSTACLES[1];
  const p = W.createPlayer('A', house.x - 3, 0); run(p, { x: 0.7, z: -1 }, 6);
  assert.ok(p.x > house.x - 3 + 1, 'vẫn trượt sang ngang, x=' + p.x);
  assert.ok(p.z > house.z + house.hd - 0.01, 'không xuyên nhà, z=' + p.z);
});
ok('hitsObstacle: giữa phố trống, trong nhà thì có', () => {
  assert.strictEqual(W.hitsObstacle(0, 0), null);
  assert.ok(W.hitsObstacle(W.OBSTACLES[2].x, W.OBSTACLES[2].z));
});

// --- nhảy ---
ok('nhảy: rời đất rồi rơi xuống chạm đất lại', () => {
  const p = W.createPlayer('A');
  W.stepPlayer(p, { x: 0, z: 0, jump: true }, DT);
  assert.strictEqual(p.grounded, false); assert.ok(p.vy > 0);
  let maxY = 0; for (let i = 0; i < 120; i++) { W.stepPlayer(p, { x: 0, z: 0 }, DT); maxY = Math.max(maxY, p.y); }
  assert.ok(maxY > 1, 'nhảy cao > 1 đơn vị, maxY=' + maxY);
  assert.strictEqual(p.grounded, true); assert.strictEqual(p.y, 0);
});
ok('đang trên không không nhảy đôi được', () => {
  const p = W.createPlayer('A');
  W.stepPlayer(p, { x: 0, z: 0, jump: true }, DT);
  const vy1 = p.vy;
  W.stepPlayer(p, { x: 0, z: 0, jump: true }, DT);
  assert.ok(p.vy < vy1, 'trọng lực kéo xuống tiếp, không nạp lại lực nhảy');
});

// --- đấm / túm (trạng thái cho Bước 4 dùng) ---
ok('đấm: bật timer rồi tự hết, không đấm chồng khi đang đấm', () => {
  const p = W.createPlayer('A'); W.startPunch(p);
  assert.ok(p.punchT > 0); const t = p.punchT;
  W.startPunch(p); assert.strictEqual(p.punchT, t);
  run(p, { x: 0, z: 0 }, 1); assert.strictEqual(p.punchT, 0);
});
ok('túm và đấm không chạy cùng lúc', () => {
  const p = W.createPlayer('A'); W.startPunch(p); W.startGrab(p);
  assert.strictEqual(p.grabT, 0);
});

// --- nối file ---
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
ok('index nạp world + three (CDN r149) + game3d trước lobby', () => {
  assert.ok(html.indexOf('js/world.js') < html.indexOf('js/game3d.js'));
  assert.ok(html.includes('cdnjs.cloudflare.com/ajax/libs/three.js/0.149.0/three.min.js'));
  assert.ok(html.indexOf('three.min.js') < html.indexOf('js/game3d.js'));
  assert.ok(html.indexOf('js/game3d.js') < html.indexOf('js/lobby.js'));
});
ok('game3d có nạp dự phòng three.min.js đóng gói khi CDN lỗi', () => {
  const g = fs.readFileSync(path.join(root, 'js/game3d.js'), 'utf8');
  assert.ok(g.includes('ensureThree') && g.includes("s.src = 'js/three.min.js'"));
});
ok('nút bấm luôn hiện có đủ: joystick + ĐẤM + NHẢY + TÚM', () => {
  ['id="joy"', 'id="btn-punch"', 'id="btn-jump"', 'id="btn-grab"'].forEach(s => assert.ok(html.includes(s), s));
});
ok('three.min.js có mặt và là bản Three.js', () => {
  const t = fs.readFileSync(path.join(root, 'js/three.min.js'), 'utf8');
  assert.ok(t.length > 500000 && t.includes('Three.js'));
});
ok('không emoji trong file bước 2', () => {
  const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
  ['js/world.js', 'js/game3d.js'].forEach(f => assert.ok(!emoji.test(fs.readFileSync(path.join(root, f), 'utf8')), f));
});

console.log('\nBước 2: ' + pass + '/' + pass + ' test PASS');
