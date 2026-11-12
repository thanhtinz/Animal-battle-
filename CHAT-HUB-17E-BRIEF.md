# 17E — CHAT HUB (lệnh Tín 2026-11-12, kèm ảnh mẫu khung chat game Avatar)

Nguyên văn ý chính: "Khung chat thêm phần icon, thông báo (bật cái này sẽ hiện tin nhắn dưới dạng thông báo chạy ngang qua màn hình; vật phẩm này không phải lúc nào cũng dùng được — phải có mới được dùng, chỉ phát từ admin), rồi thêm chat voice. Tab trong khung chat giờ bao gồm: hệ thống, thế giới, liên minh, chat riêng. Toàn bộ liên quan tới chat sẽ ở đây, trừ chat trong màn game."

## Phạm vi
Một khung chat DUY NHẤT ngoài trận (mở từ sảnh chính; nút "Chat liên minh" ở màn Liên minh mở đúng khung này tại tab Liên minh — một hệ thống, cửa ngữ cảnh). Chat trong trận giữ nguyên ở màn game, không dời.

### 4 tab
1. **Hệ thống** — luồng thông báo hệ thống (kết quả trận, sự kiện, thông báo server), chỉ đọc.
2. **Thế giới** — kênh chat toàn server cho mọi người đang online (MỚI: server fan-out toàn cục, có rate-limit như chat phòng).
3. **Liên minh** — chat liên minh 17a/17b chuyển về đây (giữ lịch sử 50 tin + [TAG] + danh hiệu <Liên minh vô địch>).
4. **Chat riêng** — nhắn 1-1 (MỚI): danh sách cuộc trò chuyện + luồng theo từng người, server lưu lịch sử theo cặp, mở ra là thấy.

### Ba tính năng trong khung nhập
- **Icon (emoticon)**: nút mặt cười mở bảng icon vẽ tay theo phong cách ảnh mẫu (mặt vàng biểu cảm, ~24 cái: cười, khóc, giận, tim, like/dislike, YES/NO...). Bấm là chèn vào tin nhắn; hiển thị dạng hình ngay trong dòng chat và trong bong bóng chat trên đầu tướng. Đây là nội dung chat do Tín lệnh riêng — không mâu thuẫn luật "UI không emoji" (luật đó áp cho icon giao diện).
- **Thông báo (loa)**: vật phẩm tiêu hao. Có số lượng hiển thị cạnh nút loa (x0 = không có thì không dùng được). Dùng 1 cái → tin nhắn chạy chữ ngang đỉnh màn hình của MỌI người đang online (sảnh + trong trận, chỉ lớp hiển thị). Hàng tồn lưu ở server theo tài khoản. **Chỉ admin phát**: cấp qua cơ chế quản trị server (tài khoản admin chỉ định trong cấu hình server + lệnh cấp; không bán, không tự nhận).
- **Chat voice**: nút micro ghi âm giữ-để-nói, gửi đoạn thoại vào mọi kênh chữ đang mở (thế giới/liên minh/riêng; trong trận để sau nếu cần). Dòng chat hiện bong bóng voice có nút phát + thời lượng. Trần độ dài + rate-limit ở server; server chỉ chuyển tiếp, lưu có trần. Lưu ý kỹ thuật: Godot thu mic qua AudioEffectCapture (Android/desktop OK); sandbox không có mic thật → kiểm chứng bằng clip mẫu tiêm vào pipeline.

## Ngoài phạm vi đợt này
Chat trong trận (giữ nguyên), bong bóng chat (đã ở 17d), observer chat.

## Thứ tự
Làm SAU khi 17d (cài đặt hồ sơ) hoàn tất — hai đợt cùng đụng net.gd/hub chat, không chạy song song trên cùng file.
