# Empire Age — Đặc tả SẢNH / BXH / LỊCH SỬ / REPLAY (bản chốt cuối)

_Gom từ phiên 2026-11-09 22:16–22:34 UTC trong side-chat Empire Age. Các lệnh sửa của Tín về sau THẮNG ảnh mẫu và thắng kế hoạch ban đầu của Bé. File này là nguồn đối chiếu duy nhất cho đợt dựng sảnh; khi có lệnh mới, sửa file này trước rồi mới sửa code._

## 1. Sảnh chính (mẫu: ảnh sảnh Tín gửi 22:16 UTC)

- Nền tranh toàn màn theo BỐ CỤC ảnh mẫu: thành phố ven biển, banner mùa ở phải, hai nút xiên ở dưới.
- Góc trái trên: avatar + tên tài khoản; chỗ "Lv. 45" của mẫu THAY bằng hạng thật (huy hiệu + tên hạng + thanh sao) — game không có cấp độ nhân vật, không để số giả.
- Hai nút xiên lớn: **Đấu Thường** (xanh — vào chọn map / chơi đơn / lập phòng) và **Đấu Hạng** (vàng — vào hàng chờ leo rank mùa hiện tại).
- Banner mùa giải: hiện đúng mùa thật từ server, bấm vào là vào đấu hạng; thêm banner thứ hai cho phòng thường, tự luân phiên.
- Thanh dưới — BẢN CUỐI 4 MỤC: **Thành Tích · Lịch Sử · BXH · Hướng Dẫn**.
  - ~~Bộ Lệnh~~ — Tín lệnh bỏ 22:28 UTC. Màn chuẩn bị trận vẫn vào bằng nút Đấu Thường.
- Góc phải trên — BẢN CUỐI 4 MỤC: **Bạn bè · Thư · Cài đặt · Ping (ping thật)**.
  - ~~Chuông~~ — Tín lệnh bỏ 22:22 UTC. Tin lên hạng / qua mùa đã có trong Thư, bỏ chuông không mất thông tin.
  - Bạn bè: thêm bạn bằng đúng tên tài khoản; danh sách hiện hạng của bạn + đang online hay không.
  - Thư: thư hệ thống thật — chào mừng khi đăng ký, báo mỗi lần lên hạng, tổng kết qua mùa (hạng cũ → hạng mới); badge = số thư chưa đọc, mở xem là hết.
  - Không để nút chết: mục nào chưa có hệ thống thật thì không hiện.

## 2. Bảng xếp hạng (mẫu: ảnh BXH Tín gửi 22:28 UTC — "mình tự thay thông tin vào")

- Khung kính xanh đậm toàn màn trên nền thành phố tối; mũi tên quay lại + tiêu đề vàng "BẢNG XẾP HẠNG".
- 3 tab xiên: **Toàn server** (thang rank) · **Bạn bè** (lọc đúng danh sách bạn của mình) · **Thắng/Thua** (bảng cũ đang có).
  - Tab "Liên minh" trong mẫu KHÔNG dùng — game không có hệ thống liên minh.
- Mỗi hàng: số hạng (top 3 có vòng nguyệt quế vàng/bạc/đồng), avatar khung vàng, tên + dòng nhỏ hạng thật dạng "Kỵ Sĩ II · 2 sao", giữa là huy hiệu bậc + tên hạng của game (Tân Binh → Hoàng Đế), phải là kiếm chéo + điểm xếp hạng viết kiểu Việt Nam (3.268).
  - Tên hạng và "Lv." trong mẫu (Thống Soái / Đại Tướng / Tướng Quân, Lv.45…) là dữ liệu của game mẫu — KHÔNG chép vào.
- Hàng số 1 phủ gradient vàng; cuối bảng có thanh dính "Hạng của tôi" hiện đúng vị trí thật kể cả khi ngoài top 20.

## 3. Lịch sử trận (mẫu: ảnh lịch sử Tín gửi 22:31 UTC — Tín chốt "ok")

- Cùng ngôn ngữ kính xanh đậm / vàng với BXH.
- Mỗi hàng: chế độ (Đấu Hạng / Đấu Thường) + thời gian dạng "12 phút trước"; giữa là **Chiến Thắng** vàng nguyệt quế / **Thất Bại** đỏ; riêng trận hạng thêm dòng nhỏ "+1 sao" ngay dưới kết quả.
- Ô bản đồ: tên map kiểu của game ("Đồng cỏ · Đồng bằng") + chip màu theo vùng đất. Ô người chơi: avatar các người trong trận (hạng 2 người, phòng thường tối đa 4) kèm hạng của họ — KHÔNG kèm "Lv." như mẫu.
- Lọc theo chế độ ở góc phải hoạt động thật; phân trang 5 trận/trang; nút chi tiết (icon danh sách) mở: giờ đấu, thời lượng, các bên, hạng trước → sau.
- Hàng thắng có viền sáng vàng như mẫu.

## 4. Replay (Tín lệnh 22:33 UTC: "Làm luôn replay — nút play xem lại được trận cũ")

- Ghi: server lưu toàn bộ dòng lệnh + hạt giống map + cấu hình trận thành file replay nhẹ, cho cả trận hạng lẫn phòng thường; mỗi dòng Lịch Sử gắn đúng replay của nó.
- Xem: bấm Play dựng lại trận từ hạt giống, chạy lại từng lệnh đúng tick; góc khán giả thấy toàn map, không sương mù; camera tự do; thanh thời gian có tạm dừng, tốc độ 1×/2×/4×, kéo tới đoạn bất kỳ (mô phỏng nhanh tới điểm đó), bảng thông số các người chơi.
- Kiểm chứng bắt buộc trước khi báo xong: phát lại một trận mẫu và đối chiếu checksum cuối trận + kết quả khớp 100% với trận thật.
- Quyền xem: replay trận hạng — tài khoản đăng nhập nào cũng xem được; replay phòng thường — chỉ người trong trận xem.
- Điểm cần làm rõ khi dựng (chưa chốt trong phiên): khách (chưa đăng nhập) ở phòng thường thì lịch sử/replay lưu theo gì, và giữ replay trong bao lâu / bao nhiêu trận gần nhất mỗi tài khoản.

## 5. Hai điểm phụ thuộc / cần Tín chốt

1. **Avatar Vua ở sảnh**: góc trái trên dự kiến dùng avatar Vua, nhưng bản Vua pixel nét (empire_age_king_crisp_v1.png) vẫn đang chờ Tín duyệt từ 21:06 UTC — Tín chưa duyệt trong phiên này (chuyển sang việc sảnh ngay sau đó). Chưa duyệt thì đừng nối Vua vào sảnh như đã duyệt; hoặc dùng avatar tạm và ghi rõ là tạm.
2. **Tông nền sảnh La Mã vs Tây trung cổ**: ảnh mẫu sảnh là thành phố La Mã (đấu trường, lính La Mã), trong khi Tín đã sửa hướng Vua sang Tây trung cổ vì dàn lính là hiệp sĩ Tây (lệnh 2026-11-09, bỏ bản La Mã). Cần phân biệt: ảnh này là mẫu BỐ CỤC (giữ bố cục, đổi tông sang Tây trung cổ) hay mẫu cả phong cách (giữ La Mã)? Chưa chốt — không tự quyết khi dựng nền.

## 6. Những thứ đã bị thay thế — không dựng lại

- Tiêu đề "Chơi mạng" trong panel sảnh phòng: đã gỡ 22:00 UTC, chữ này chỉ còn ở nút mở tại màn chọn map.
- Bộ Lệnh ở thanh dưới sảnh: bỏ.
- Chuông ở góc phải trên sảnh: bỏ.
- Mọi "Lv." / cấp độ nhân vật lấy từ ảnh mẫu: không có trong game, không hiện.
