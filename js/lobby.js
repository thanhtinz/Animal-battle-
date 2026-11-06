// Giang Hồ Xóm — Bước 1: sảnh (nhập tên, chọn phòng, vào/rời phòng)
// Chỉ lo phần sảnh. Map + nhân vật là Bước 2, gắn vào màn phòng sau.
(function () {
  'use strict';
  var C = window.GHXConfig;

  var els = {
    lobby: document.getElementById('screen-lobby'),
    room: document.getElementById('screen-room'),
    name: document.getElementById('input-name'),
    nameError: document.getElementById('name-error'),
    joinError: document.getElementById('join-error'),
    roomList: document.getElementById('room-list'),
    roomsCount: document.getElementById('rooms-count'),
    btnJoin: document.getElementById('btn-join'),
    btnLeave: document.getElementById('btn-leave'),
    roomTitle: document.getElementById('room-title'),
    roomWelcome: document.getElementById('room-welcome'),
    roomMode: document.getElementById('room-mode')
  };

  var state = { selectedRoomId: null, occupancy: {} }; // occupancy: Bước Online cấp số thật

  function showError(el, msg) { el.textContent = msg || ''; el.hidden = !msg; }

  function renderRooms() {
    els.roomList.innerHTML = '';
    C.ROOMS.forEach(function (room) {
      var occ = state.occupancy[room.id] || 0;
      var full = occ >= room.max;
      var card = document.createElement('button');
      card.type = 'button';
      card.className = 'room-card' + (room.id === state.selectedRoomId ? ' selected' : '') + (full ? ' full' : '');
      card.setAttribute('role', 'option');
      card.setAttribute('aria-selected', room.id === state.selectedRoomId ? 'true' : 'false');
      card.innerHTML =
        '<span class="r-name"></span>' +
        '<span class="r-meta"></span>' +
        '<span class="r-mode"></span>';
      card.querySelector('.r-name').textContent = room.name;
      card.querySelector('.r-meta').textContent = 'Địa bàn ' + room.map + ' · ' + occ + '/' + room.max + ' người' + (full ? ' · Đã đầy' : ' · Vào ngay');
      card.querySelector('.r-mode').textContent = C.MODES[room.mode].name;
      card.addEventListener('click', function () {
        if (full) { showError(els.joinError, 'Phòng ' + room.name + ' đã đầy, chọn phòng khác nhé.'); return; }
        state.selectedRoomId = room.id;
        showError(els.joinError, '');
        renderRooms(); refreshJoin();
      });
      els.roomList.appendChild(card);
    });
    els.roomsCount.textContent = C.ROOMS.length + ' phòng · ' + C.ROOMS[0].map;
  }

  function refreshJoin() {
    var v = C.validateName(els.name.value);
    els.btnJoin.disabled = !(v.ok && state.selectedRoomId);
    return v;
  }

  els.name.addEventListener('input', function () {
    showError(els.nameError, '');
    refreshJoin();
  });
  els.name.addEventListener('blur', function () {
    var v = C.validateName(els.name.value);
    if (els.name.value.trim() && !v.ok) showError(els.nameError, v.error);
  });

  els.btnJoin.addEventListener('click', function () {
    var v = C.validateName(els.name.value);
    if (!v.ok) { showError(els.nameError, v.error); els.name.focus(); return; }
    var room = C.roomById(state.selectedRoomId);
    var join = C.canJoin(room, state.occupancy);
    if (!join.ok) { showError(els.joinError, join.error); return; }

    try { localStorage.setItem('ghx_name', v.name); } catch (e) {}
    els.roomTitle.textContent = room.name;
    els.roomWelcome.textContent = 'Xin chào, ' + v.name + '.';
    els.roomMode.textContent = C.MODES[room.mode].name + ' — ' + C.MODES[room.mode].desc +
      ' Địa bàn ' + room.map + ', tối đa ' + room.max + ' người.';
    els.lobby.hidden = true;
    els.room.hidden = false;
  });

  els.btnLeave.addEventListener('click', function () {
    els.room.hidden = true;
    els.lobby.hidden = false;
  });

  // Khởi tạo: lấy tên đã lưu + phòng từ link rủ bạn (?phong=<id>) nếu có
  try {
    var saved = localStorage.getItem('ghx_name');
    if (saved) els.name.value = saved;
  } catch (e) {}
  var param = new URLSearchParams(location.search).get('phong');
  if (param && C.roomById(param)) state.selectedRoomId = param;
  renderRooms();
  refreshJoin();
})();
