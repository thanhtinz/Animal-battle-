# ĐẶC TẢ PANEL LIÊN MINH (ĐÃ XÂY ở mục 17a — Tín chốt Hướng B hai cột 2026-11-12; các số mặc định trong bản xây chờ Tín chốt, xem KE-HOACH-MVP.md §17a)

Trang "Liên minh" dùng đúng vỏ trang thông tin hiện có: nền navy đặc
(PageShell), nút quay lại + tiêu đề "Liên minh", thẻ navy viền vàng,
nút chính vàng chữ tối, icon Font Awesome. Mở từ: hàng "Liên minh" ở
Hồ sơ, tab "Liên minh" ở Bảng xếp hạng (cả hai hiện là trạng thái
trống trung thực), và một điểm vào ở sảnh sẽ chốt khi xây.

Dữ liệu trong ảnh mockup là dữ liệu mẫu (liên minh "Đoàn Kỵ Sĩ
Aurelion", 24/30 thành viên) để Tín duyệt bố cục.

## Hai trạng thái

### Trạng thái 1 — Chưa có liên minh (mock_join)
- Thẻ giới thiệu "Bạn chưa tham gia liên minh" + nút **Tạo liên minh**
  (mở form: tên liên minh, chọn huy hiệu/màu khiên, chế độ tuyển:
  Mở / Duyệt đơn / Đóng).
- Ô **tìm kiếm** theo tên + nút Tìm.
- Danh sách liên minh đang tuyển: mỗi hàng gồm huy hiệu, tên, cấp,
  số thành viên (x/30), tên Hội trưởng, chế độ tuyển, nút **Xin vào**
  (liên minh "Mở" vào thẳng; "Duyệt đơn" chuyển nút thành **Đã gửi**,
  bấm lần nữa để huỷ đơn).
- Ghi chú: mỗi người chỉ ở 1 liên minh tại một thời điểm.

### Trạng thái 2 — Đã có liên minh (mockA / mockB, hai hướng)
Phần tử chung cả hai hướng:
- **Thẻ đầu liên minh**: huy hiệu khiên, tên, nhãn Cấp, thanh XP liên
  minh kèm số (vd 4.250/6.200), Hội trưởng, số thành viên, hạng toàn
  server, điểm tuần.
- **Danh sách thành viên**: avatar, tên hiển thị (+ vương miện ở Hội
  trưởng), cấp người chơi, nhãn vai trò (Hội trưởng vàng / Phó xanh /
  Thành viên mờ), đóng góp tuần, chấm trạng thái (xanh = trực tuyến,
  xám = lần cuối online). Hàng của chính mình viền vàng.
- **Yêu cầu gia nhập** (chỉ Hội trưởng/Phó thấy): avatar, tên, cấp,
  thời gian gửi, lời nhắn, nút **Duyệt** / **Từ chối**.
- **Nút hành động**: Mời bạn bè · Chat liên minh · Cài đặt liên minh ·
  Rời liên minh (nút nguy hiểm viền đỏ; Hội trưởng bấm Rời phải
  chuyển quyền hoặc giải tán — xem câu hỏi mở).

**Hướng A — "Thẻ tổng quan"** (một cột cuộn): thẻ đầu → hàng nút →
thẻ Thành viên (xem trước 4 người + "Xem tất cả") → thẻ Yêu cầu ở
dưới. Đơn giản, giống nhịp các trang hiện tại; đổi lại yêu cầu gia
nhập nằm dưới danh sách thành viên, Hội trưởng phải cuộn mới thấy.

**Hướng B — "Hai cột"**: cột trái cố định là thẻ hồ sơ liên minh
(huy hiệu lớn, khối số liệu: cấp, thành viên, điểm tuần, hạng, Hội
trưởng, ngày lập) + 4 nút hành động xếp dọc; cột phải là vùng thẻ
tab **Thành viên / Yêu cầu (có huy hiệu số đơn chờ) / Hoạt động**.
Xem được 7 thành viên cùng lúc, đơn chờ luôn thấy ở tab; đổi lại
cột trái chiếm diện tích cố định, hợp màn hình ngang của game.

Tab **Hoạt động** (chỉ có ở B; A cuộn xuống dưới Yêu cầu): dòng sự
kiện — ai gia nhập/rời, ai lên vai trò, mốc cấp liên minh, đóng góp
lớn — kèm thời gian tương đối.

## Vai trò & quyền

| Việc | Hội trưởng | Phó | Thành viên |
|---|---|---|---|
| Duyệt / từ chối đơn | Có | Có | Không |
| Mời bạn bè | Có | Có | Có |
| Đuổi thành viên | Có (cả Phó) | Chỉ thành viên | Không |
| Đổi tên / huy hiệu / chế độ tuyển | Có | Không | Không |
| Phong / giáng Phó | Có | Không | Không |
| Chuyển quyền Hội trưởng | Có | Không | Không |
| Giải tán liên minh | Có | Không | Không |
| Chat liên minh | Có | Có | Có |
| Rời liên minh | Phải chuyển quyền trước | Có | Có |

## Dữ liệu server cần có (chưa xây — mới là thiết kế)

- **Liên minh**: id, tên (duy nhất, kiểm tra độ dài/ký tự như tên
  hiển thị), huy hiệu (màu khiên + biểu tượng), cấp + XP, chế độ
  tuyển, ngày lập, id Hội trưởng. Lưu qua interface Store hiện có.
- **Thành viên**: account id, liên minh id, vai trò, đóng góp tuần
  (reset theo tuần server), thời điểm gia nhập. Trạng thái online
  lấy từ kết nối hiện tại của server, không lưu riêng.
- **Đơn xin vào**: account id, liên minh id, lời nhắn, thời gian;
  tạo/huỷ/duyệt/từ chối; duyệt khi đầy 30 phải bị từ chối kèm lý do.
- **Hoạt động**: nhật ký sự kiện theo liên minh (giới hạn số dòng).
- **Chat liên minh**: một kênh chat theo liên minh id, đi lại cùng
  hạ tầng chat hiện có (chỉ thành viên đọc/gửi).
- **Điểm & hạng**: điểm tuần = tổng đóng góp tuần của thành viên;
  hạng liên minh trên Bảng xếp hạng (tab Liên minh đang chờ dữ liệu
  này) sắp theo điểm tuần hoặc XP — chốt ở câu hỏi mở.
- Khách (chưa đăng nhập) không tạo/xin vào được — dẫn về luồng tài
  khoản như các tính năng tài khoản khác.

## Câu hỏi mở — chờ Tín chốt

1. **Sức chứa 30 người** mỗi liên minh có đúng ý không, hay ít hơn
   (20) / nhiều hơn (50)?
2. **XP liên minh lấy từ đâu**: đóng góp tuần của thành viên quy ra
   XP (thắng trận, số trận, khai thác...)? Bé đề xuất: XP chỉ từ
   đóng góp của thành viên để hai con số không tách rời nhau.
3. **Đóng góp tuần tính bằng gì**: số trận thắng cùng liên minh, mọi
   trận, hay cả hoạt động thường? Cần một nguồn duy nhất, đo được ở
   server.
4. **Chat liên minh**: chỉ chữ như chat trận, mở thành panel riêng
   hay dùng lại khung Chat hiện có thêm một tab "Liên minh"?
5. **Tạo liên minh có tốn gì không** (Vàng trong trận thì không hợp;
   nếu tốn thì là tài nguyên tài khoản nào)? Bé đề xuất tạo miễn
   phí, chống spam bằng yêu cầu cấp tài khoản tối thiểu.
6. **Hội trưởng rời liên minh**: bắt buộc chuyển quyền cho Phó/
   thành viên trước, hay tự động chuyển cho Phó lâu nhất? Giải tán
   khi còn thành viên có cần xác nhận hai bước?
7. **Huy hiệu**: chọn từ bộ khiên/màu có sẵn (như mockup) hay để
   người chơi tự ghép biểu tượng + màu trong một bộ giới hạn?

## Mockup

- `godot/shots/empire_age_alliance_mockA_v1.png` — Hướng A.
- `godot/shots/empire_age_alliance_mockB_v1.png` — Hướng B.
- `godot/shots/empire_age_alliance_mock_join_v1.png` — Chưa gia nhập.
- Công cụ dựng (throwaway, không phải code game):
  `godot/tests/capture_alliance_mock.gd` + `.tscn` — dựng bằng đúng
  PageShell/palette/font icon của game, chụp qua Xvfb như mọi
  capture khác của dự án.
