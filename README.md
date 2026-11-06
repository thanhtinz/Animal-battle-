# Giang Hồ Xóm

Game đánh nhau khu phố kiểu hoạt hình, chơi trên điện thoại (web, màn hình ngang) — viết từ đầu, từng bước một: xong bước nào, test bước đó mới viết tiếp.

Mẫu tham khảo cơ chế: Giang Hồ Online (play.giangho.online) — vào nhanh không cần tài khoản, chọn phòng, lập nhóm giữ góc phố / đấu trường, điều khiển cảm ứng Đấm / Nhảy / Túm, chat câu soạn sẵn.

## Thiết bị đích

- Web mobile: iPhone (Safari, thêm vào Màn hình chính để full màn hình) + Android.
- Máy tính chơi bằng phím, để test nhanh.

## Lộ trình từng bước

1. **Khung dự án + sảnh** — nhập tên, chọn phòng (7 phòng, 2 chế độ Chiếm phố / Đấu trường), vào / rời phòng. ✅ Xong, test 17/17 PASS.
2. **Map khu phố 3D + nhân vật + joystick + nút bấm luôn hiện** — phố 2 dãy nhà có biển hiệu, sạp, đèn, cây; nhân vật đi/chạy theo độ kéo cần, va chạm nhà, nhảy; nút ĐẤM / NHẢY / TÚM luôn hiện (Đấm/Túm mới có hoạt hình tay, hiệu quả trúng đòn ở Bước 4). ✅ Xong, test 20/20 PASS.
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

- `index.html` — 2 màn: sảnh + trong phòng (game 3D)
- `css/style.css` — giao diện sảnh + HUD + nút bấm
- `js/config.js` — dữ liệu phòng / chế độ + kiểm tra tên (dùng chung, test bằng Node)
- `js/lobby.js` — logic sảnh, nối vào game
- `js/world.js` — logic thế giới thuần: di chuyển, va chạm, nhảy, đấm/túm (test bằng Node)
- `js/game3d.js` — dựng 3D bằng Three.js (`js/three.min.js` r149 đóng gói kèm), joystick + nút bấm
- `tests/` — test từng bước
