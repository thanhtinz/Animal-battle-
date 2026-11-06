// Giang Hồ Xóm — cấu hình dùng chung (Bước 1: sảnh)
// Viết từ đầu. Mỗi bước sau chỉ thêm vào đây, không sửa ngược dữ liệu cũ.
(function (global) {
  'use strict';

  // Hai chế độ chơi
  var MODES = {
    occupy: { id: 'occupy', name: 'Chiếm phố', desc: 'Lập nhóm, giữ từng góc phố trong 15 phút.' },
    arena: { id: 'arena', name: 'Đấu trường', desc: 'Vào là đấm tự do, ai trụ lâu nhất thắng.' }
  };

  // 7 phòng như cấu trúc mẫu đã khảo sát: phòng nhỏ 12 người, phòng lớn 24 người
  var ROOMS = [
    { id: 'cho-moi-01', name: 'Chợ Mới 01', map: 'Chợ Mới', mode: 'occupy', max: 12 },
    { id: 'cho-moi-02', name: 'Chợ Mới 02', map: 'Chợ Mới', mode: 'occupy', max: 12 },
    { id: 'cho-moi-03', name: 'Chợ Mới 03', map: 'Chợ Mới', mode: 'occupy', max: 24 },
    { id: 'tap-hoa-01', name: 'Tạp Hóa 01', map: 'Tạp Hóa', mode: 'occupy', max: 12 },
    { id: 'tap-hoa-02', name: 'Tạp Hóa 02', map: 'Tạp Hóa', mode: 'occupy', max: 24 },
    { id: 'dau-truong-01', name: 'Đấu Trường 01', map: 'Đấu Trường', mode: 'arena', max: 24 },
    { id: 'dau-truong-02', name: 'Đấu Trường 02', map: 'Đấu Trường', mode: 'arena', max: 12 }
  ];

  var NAME_MIN = 3;
  var NAME_MAX = 14;

  // Kiểm tra tên người chơi. Trả {ok:true, name} hoặc {ok:false, error}
  function validateName(raw) {
    var name = String(raw == null ? '' : raw).trim().replace(/\s+/g, ' ');
    if (!name) return { ok: false, error: 'Chưa nhập tên. Nhập tên của bạn để vào chơi.' };
    if (name.length < NAME_MIN) return { ok: false, error: 'Tên ngắn quá, cần ít nhất ' + NAME_MIN + ' ký tự.' };
    if (name.length > NAME_MAX) return { ok: false, error: 'Tên dài quá, tối đa ' + NAME_MAX + ' ký tự.' };
    if (/[<>&"'`\\]/.test(name)) return { ok: false, error: 'Tên có ký tự không hợp lệ, đổi tên khác nhé.' };
    return { ok: true, name: name };
  }

  function roomById(id) {
    for (var i = 0; i < ROOMS.length; i++) if (ROOMS[i].id === id) return ROOMS[i];
    return null;
  }

  // Phòng còn vào được không (occupancy do bước Online cấp sau; bước 1 luôn 0)
  function canJoin(room, occupancy) {
    if (!room) return { ok: false, error: 'Chưa chọn phòng.' };
    var occ = occupancy && typeof occupancy[room.id] === 'number' ? occupancy[room.id] : 0;
    if (occ >= room.max) return { ok: false, error: 'Phòng ' + room.name + ' đã đầy (' + occ + '/' + room.max + ').' };
    return { ok: true };
  }

  var api = {
    MODES: MODES, ROOMS: ROOMS, NAME_MIN: NAME_MIN, NAME_MAX: NAME_MAX,
    validateName: validateName, roomById: roomById, canJoin: canJoin
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.GHXConfig = api;
})(typeof window !== 'undefined' ? window : globalThis);
