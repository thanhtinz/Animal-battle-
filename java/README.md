# Giang Hồ Xóm — bản Java + LibGDX

Bản Java theo lệnh của Tín (2026-11-05, thay hướng JavaScript cho phần client chính).
Cùng lộ trình từng bước như bản web; logic thế giới port trung thành từ `js/world.js` sang `World.java`.

## Trạng thái

- **J1 xong**: khung LibGDX 1.14.0 + hình 3D khu phố (2 dãy nhà có biển hiệu chữ Việt, sạp, cột đèn, cây),
  nhân vật 3D đi/chạy theo joystick, va chạm nhà, nhảy, **nút bấm luôn hiện** (joystick + ĐẤM / NHẢY / TÚM;
  Đấm/Túm mới có hoạt hình tay — hiệu quả trúng đòn ở bước Đấm/Túm/Ném riêng).
  Test logic `WorldTest` 20/20 PASS; tour tự động chụp 4 ảnh kiểm chứng (local `shots/`).
- **J1.5 xong (chỉnh hình chibi theo ảnh mẫu của bản gốc)**: nhân vật chibi đầu to (đầu cầu + tóc, thân capsule,
  mặt vẽ texture có mắt/miệng/má hồng, giày trắng), nhà mái ngói 2 dốc + mái hiên sọc xanh/đỏ + cửa xanh +
  dải gạch chân tường + chậu cây, xe máy + thùng gỗ góc phố, **vòng chiếm đóng** giữa phố có vương miện + cờ.
  Có thêm 1 nhân vật phụ đứng mẫu ở vòng chiếm. Texture phụ sinh bằng `tools/make_textures.py`, đóng gói .b64 như biển hiệu.
  Lưu ý: ảnh tour chụp bằng renderer phần mềm trong sandbox (llvmpipe) — biển hiệu ở xa có vệt sọc do lỗi
  lấy mẫu texture của renderer này; chụp cận cảnh biển nét bình thường, GPU thật không bị.
- **J1.6 xong (AI tạo ảnh mặt tiền)**: Tín chê hình khối xấu, lệnh dùng AI tạo ảnh — đã sinh 4 mẫu mặt tiền
  phong cách đất nặn chibi đúng ảnh mẫu (lưu ở `gen/`), để bảng hiệu TRỐNG rồi ghép tên quán bằng
  `tools/make_facades.py` (font Nunito, dấu tiếng Việt chuẩn) thành 10 texture `assets/facades/f0..f9.png`,
  dán lên mặt trước nhà (tấm lưới 6×4 ô để giảm lỗi nội suy của renderer phần mềm). Nhà thôi dùng biển/hiên/cửa dựng bằng khối.
- **J1.7 xong (nhân vật sprite AI 2.5D)**: Tín chọn vẽ lại nhân vật bằng ảnh AI trước — AI sinh bảng 9 tư thế
  (trước/sau × đứng/đi/đấm + nhảy + ngã choáng) cho bé trai áo cam và bé gái áo teal trên nền magenta,
  `tools/make_chars.py` tách nền bằng connected components + chuẩn hoá chiều cao/đường chân thành 22 sprite.
  Trong game nhân vật là tấm billboard luôn quay về camera, tự chọn mặt trước/sau theo hướng so với camera,
  đổi tư thế theo trạng thái (đi luân phiên 2 khung, đấm, nhảy) + bóng ellipse dưới chân; đã gỡ nhân vật khối 3D.
- **J1.8 mẫu so sánh (Blender 3D)**: Tín lệnh thử Blender — đã cài Blender 4.2.3 vào `~/workspace/tools/blender`,
  script `tools/blender/make_chibi_boy.py` dựng bé trai chibi (mỗi bộ phận 1 object, origin tại khớp vai/hông/cổ),
  xuất `assets/models/boy3d.glb`; game có `MiniGlb.java` (nạp GLB tối giản tự viết vì không tải được thư viện ngoài)
  và cờ môi trường `BOY3D=1` để thay nhân vật chính bằng model 3D (vung tay/chân theo nhịp đi, đấm, nhảy giơ tay).
  Mặc định vẫn dùng sprite AI; chờ Tín chốt hướng.
- Tiếp theo: J2 sảnh Java (nhập tên/chọn phòng) → camera xoay/zoom → đấm/túm hiệu quả → online → chế độ chơi → chat sẵn → bản web TeaVM cho iPhone.

## Chạy

Cần JDK 17. Thư viện LibGDX/LWJGL nằm ở `libs/` (lấy từ kho local, không push lên GitHub).

```sh
python3 tools/restore_assets.py   # giải mã font + biển hiệu từ assets-src/*.b64
./build.sh                        # biên dịch + chạy WorldTest
./build.sh tour                   # chạy tour tự động, chụp ảnh vào shots/
java -cp "build:libs/*" com.giangho.game.DesktopLauncher   # chơi thử bằng WASD/phím (J đấm, K/Space nhảy, L túm)
```

## Cấu trúc

- `src/com/giangho/game/World.java` — logic thuần: map, va chạm, di chuyển, nhảy, đấm/túm
- `src/com/giangho/game/GiangHoGame.java` — dựng 3D + HUD + điều khiển cảm ứng/phím
- `src/com/giangho/game/WorldTest.java` — test logic bằng main()
- `src/com/giangho/game/ScreenshotMain.java` — tour tự động chụp ảnh kiểm chứng
- `tools/make_signs.py` — sinh texture biển hiệu (chữ nướng vào ảnh)
- `assets-src/` — tài sản nhị phân dạng .b64 (đẩy được lên GitHub), `tools/restore_assets.py` giải mã ra `assets/`
