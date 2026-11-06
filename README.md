# Giang Hồ Xóm

Game đánh nhau khu phố kiểu hoạt hình, chơi trên điện thoại (web, màn hình ngang) — viết từ đầu, từng bước một: xong bước nào, test bước đó mới viết tiếp.

Mẫu tham khảo cơ chế: Giang Hồ Online (play.giangho.online) — vào nhanh không cần tài khoản, chọn phòng, lập nhóm giữ góc phố / đấu trường, điều khiển cảm ứng Đấm / Nhảy / Túm, chat câu soạn sẵn.

## Thiết bị đích

- Web mobile: iPhone (Safari, thêm vào Màn hình chính để full màn hình) + Android.
- Máy tính chơi bằng phím, để test nhanh.

## Lộ trình từng bước

1. **Khung dự án + sảnh** — nhập tên, chọn phòng (7 phòng, 2 chế độ Chiếm phố / Đấu trường), vào / rời phòng. ✅ Xong, test 17/17 PASS.
2. Map khu phố 3D + nhân vật di chuyển bằng joystick.
3. Camera xoay / zoom + nút Nhảy.
4. Đấm / Túm / ném + vật ngã.
5. Online đồng bộ nhiều người cùng phòng.
6. Chế độ Chiếm phố + Đấu trường: giờ trận, điểm.
7. Chat câu soạn sẵn + link rủ bạn.
8. Deploy live + kiểm chứng khung iPhone.

## Chạy local

```sh
python3 -m http.server 8931
# mở http://127.0.0.1:8931/
node tests/test_step1.js
```

## Cấu trúc

- `index.html` — 2 màn: sảnh + phòng chờ
- `css/style.css` — giao diện sảnh
- `js/config.js` — dữ liệu phòng / chế độ + kiểm tra tên (dùng chung, test bằng Node)
- `js/lobby.js` — logic sảnh
- `tests/` — test từng bước
