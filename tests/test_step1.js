// Test Bước 1 — chạy: node tests/test_step1.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const C = require('../js/config.js');

let pass = 0;
function ok(name, fn) { fn(); pass++; console.log('PASS', name); }

// --- validateName ---
ok('tên trống bị chặn', () => assert.strictEqual(C.validateName('').ok, false));
ok('tên toàn khoảng trắng bị chặn', () => assert.strictEqual(C.validateName('   ').ok, false));
ok('tên 2 ký tự bị chặn', () => assert.strictEqual(C.validateName('An').ok, false));
ok('tên 15 ký tự bị chặn', () => assert.strictEqual(C.validateName('A'.repeat(15)).ok, false));
ok('tên có ký tự HTML bị chặn', () => assert.strictEqual(C.validateName('<b>Tin</b>').ok, false));
ok('tên hợp lệ qua + gộp khoảng trắng', () => {
  const v = C.validateName('  Tín   Xóm  ');
  assert.strictEqual(v.ok, true); assert.strictEqual(v.name, 'Tín Xóm');
});

// --- rooms ---
ok('đúng 7 phòng', () => assert.strictEqual(C.ROOMS.length, 7));
ok('id phòng không trùng', () => assert.strictEqual(new Set(C.ROOMS.map(r => r.id)).size, 7));
ok('mọi phòng có mode hợp lệ + sức chứa 12/24', () => {
  C.ROOMS.forEach(r => { assert.ok(C.MODES[r.mode]); assert.ok(r.max === 12 || r.max === 24); });
});
ok('có cả 2 chế độ chiếm phố + đấu trường', () => {
  assert.ok(C.ROOMS.some(r => r.mode === 'occupy'));
  assert.ok(C.ROOMS.some(r => r.mode === 'arena'));
});
ok('roomById tìm đúng / sai trả null', () => {
  assert.strictEqual(C.roomById('cho-moi-01').name, 'Chợ Mới 01');
  assert.strictEqual(C.roomById('khong-co'), null);
});
ok('canJoin: chưa chọn phòng bị chặn', () => assert.strictEqual(C.canJoin(null, {}).ok, false));
ok('canJoin: phòng đầy bị chặn', () => {
  const r = C.roomById('cho-moi-01');
  assert.strictEqual(C.canJoin(r, { 'cho-moi-01': 12 }).ok, false);
});
ok('canJoin: phòng còn chỗ thì qua', () => {
  const r = C.roomById('cho-moi-01');
  assert.strictEqual(C.canJoin(r, { 'cho-moi-01': 11 }).ok, true);
});

// --- file wiring ---
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
ok('index.html nạp config.js trước lobby.js', () =>
  assert.ok(html.indexOf('js/config.js') < html.indexOf('js/lobby.js')));
ok('index.html có đủ 2 màn + viewport mobile', () => {
  assert.ok(html.includes('id="screen-lobby"')); assert.ok(html.includes('id="screen-room"'));
  assert.ok(html.includes('viewport-fit=cover'));
});
ok('không emoji trong html/css/js bước 1', () => {
  const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
  ['index.html', 'css/style.css', 'js/config.js', 'js/lobby.js'].forEach(f =>
    assert.ok(!emoji.test(fs.readFileSync(path.join(root, f), 'utf8')), f));
});

console.log('\nBước 1: ' + pass + '/' + pass + ' test PASS');
