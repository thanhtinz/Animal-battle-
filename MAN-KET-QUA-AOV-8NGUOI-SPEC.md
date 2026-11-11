# Đặc tả: Màn kết quả kiểu AOV + Đấu Thường/Hạng 8 người (Empire Age)

_Soạn 2026-11-11 (proactive research) từ: lệnh Tín 12:42Z "Màn kết quả nghiên cứu của AOV làm theo", luật 8 người đấu tự do (11:54Z), bảng sao theo thứ hạng Tín chốt qua thẻ chọn (11:55Z), và màn kết quả v1 vừa xong (487/487, 12:41Z). File này là đất chuẩn bị cho đợt code đang chạy — phần ghi "ĐỀ XUẤT" chưa phải luật Tín chốt._

## 1. Màn kết quả kiểu Liên Quân (AOV) — áp vào Empire Age

Cấu trúc AOV gốc (đối chiếu mô tả đã thống nhất trong chat 12:42Z): banner kết quả trên cùng → MVP nổi bật kèm chân dung → bảng người chơi dạng hàng ngang (chân dung + tên + các cột chỉ số có icon) → mục phụ bên dưới. Áp vào Empire Age, giữ chuẩn panel hiện hành (thẻ kính navy viền vàng, giữa màn):

1. **Banner trên cùng**: THẮNG / THUA / ĐẦU HÀNG + lý do kết thúc (như v1 đã có). Ở trận 8 người: banner hiện thêm **thứ hạng của mình** (vd "Hạng 3/8") và **sao nhận được** nếu là Đấu Hạng (+2 / +1 / 0 / −1 theo bảng ở §3).
2. **MVP nổi bật**: người có **Điểm tổng cao nhất** (công thức điểm hiện có của panel Thống kê), kèm chân dung nhân vật chính + tên. Huy hiệu "MVP" gắn cả ở thẻ nổi bật lẫn trên hàng của người đó trong bảng.
   - Lưu ý khác AOV: AOV là 5v5 theo đội nên MVP thường thuộc đội thắng; Empire Age đấu tự do thì **thứ hạng sống sót và Điểm tổng là hai thứ khác nhau** — người bị loại sớm vẫn có thể điểm cao. Đặc tả này lấy MVP = Điểm tổng cao nhất bất kể thứ hạng (đúng tinh thần "người chơi giá trị nhất" của AOV); thứ hạng vẫn hiện riêng ở cột Hạng. Nếu Tín muốn MVP phải là người hạng 1 thì đổi một dòng này.
3. **Bảng xếp hạng dạng hàng ngang** — MỘT danh sách duy nhất xếp theo thứ hạng 1→8, KHÔNG chia khối đội (luật "Đội" chỉ ở trận 2v2 thật; 1v1 và đấu tự do không có chữ Đội ở đâu). Mỗi hàng: chân dung nhân vật chính · tên người chơi · màu phe · các cột có icon: **Điểm · Hạ địch · Mất quân · Thu thập · Phá công trình · APM**. Hàng của mình tô sáng viền vàng. Người bị loại hiện trạng thái ở cuối hàng; APM của Máy hiện "—" như giới hạn đã báo ở v1 (không bịa số).
4. **Mục phụ bên dưới**: biểu đồ đường điểm theo thời gian (đã có ở v1, màu theo từng người) dời xuống dưới bảng, thu gọn chiều cao; thẻ chi tiết 4 nhóm (Kinh tế · Quân sự · Công trình · Công nghệ) giữ nguyên từ v1 khi bấm vào một hàng/người.
5. **Nút**: Xem lại (hiện chỉ phòng Custom có mã xem lại — giữ đúng giới hạn này, phòng Thường/Hạng ẩn nút thay vì bấm vào không có gì) · Chơi lại/Về sảnh như hiện hành.

Kiểm chứng bắt buộc theo luật đã chốt của dự án: dựng với **đủ 8 người, tên dài nhất, số 4–5 chữ số** rồi chụp ở kích thước thật xem có tràn hàng/cột không trước khi báo xong (bài học panel tràn khung ở AvatarDK áp dụng chung).

## 2. Đợt 8 người — những điểm hệ thống phải đổi (ngoài màn kết quả)

- Hàng đợi Thường + Hạng: gom **đủ 8** mới mở trận; Custom giữ 2–4 người như cũ.
- **8 điểm xuất phát + 8 màu phe**: luật nhuộm màu đội hiện mới có 4 màu (Đỏ · Xanh dương · Xanh lá · Vàng). ĐỀ XUẤT thêm 4 màu phân biệt rõ ở cỡ pixel thật: **Tím · Cam · Xanh ngọc · Hồng** — cần Tín duyệt vì màu phe là luật cứng; khi cắt/nhuộm phải kiểm tra không lẫn với 4 màu cũ trên minimap.
- Điều kiện loại/về hạng trong trận tự do: thứ hạng = thứ tự bị loại ngược (người sống cuối hạng 1); người đầu hàng xếp ngay dưới nhóm còn đang chơi tại thời điểm đầu hàng; người mất kết nối xử như đầu hàng (theo luật trạng thái "Mất kết nối" đã có ở panel Người chơi).
- Thống kê cuối trận + APM + biểu đồ phải chạy đủ 8 đường/người (đã chuẩn bị ở §1).

## 3. Sao + MMR cho Đấu Hạng 8 người

**Sao (Tín đã chốt 11:55Z)**: hạng 1 **+2** · hạng 2–3 **+1** · hạng 4–5 **giữ nguyên** · hạng 6–8 **−1**. Sàn Tân Binh III 0 sao giữ nguyên.

**Hai điểm CHƯA chốt — cần Tín quyết, đừng tự áp:**
1. **Chuỗi thắng**: luật mùa hiện tại thắng + chuỗi thắng ≥3 được +1 sao thưởng. Ở thể thức 8 người, "thắng" tính là hạng 1, hay hạng 1–3 (nhóm được +sao)? (Trong chat đã nói tạm "hạng 1 tính là thắng" — đó là lời Bé, chưa phải lệnh Tín.)
2. **MMR ẩn**: hệ hiện tại là Elo 1v1 (K=32/16, sàn 100, cửa sổ ghép ±100 nới +50/10s trần ±600) — không áp nguyên sang 8 người được. ĐỀ XUẤT công thức Elo đấu tự do chuẩn: với mỗi người, điểm kỳ vọng = trung bình kỳ vọng Elo khi đấu tay đôi với 7 người còn lại; điểm thực = (8 − hạng)/7; MMR += K × (thực − kỳ vọng), K giữ 32/16 như hiện tại, sàn 100 giữ nguyên. MMR vẫn ẩn, màn kết quả chỉ hiện sao.

## 4. Thứ tự làm đề xuất cho đợt đang chạy

1. Màn kết quả AOV (§1) cho cả 1v1/2v2/Custom hiện tại — không chờ 8 người.
2. Hàng đợi 8 + 8 điểm xuất phát (chờ Tín duyệt 4 màu mới ở §2 nếu muốn chắc).
3. Sao theo thứ hạng (đã chốt) + MMR đấu tự do (chờ Tín duyệt công thức ở §3).
