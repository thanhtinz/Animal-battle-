# EMPIRE AGE — THIẾT KẾ 4 NHÂN VẬT CHÍNH MỚI (SỐ 5–8)

**Trạng thái: ĐÃ VÀO GAME (đợt 14c, 2026-11-11).** Cả bốn đã cài đầy đủ: sprite 8 hướng + rig hoạt hoạ cùng chuẩn 4 nhân vật gốc (vũ khí vẽ trong cùng hệ pixel: song đao cong · thiết phiến đen · trường cung · chùy đá), chân dung avatar + bản đóng khung cho Bộ sưu tập, 12 icon chiêu theo chuẩn v6, 12 SFX tổng hợp, kit chiêu theo đúng số trong tài liệu này (hào quang + Chiêu 1/2/Ulti; Phong Linh là hero đánh xa bắn tên như cung thủ; Nham Tường của Thạch Sơn là vật cản 3 ô/300 HP/12 giây — chặn đường + chặn chọn mục tiêu như công trình nhưng KHÔNG tính công trình: không điểm phá, không tính điều kiện lên đời, hết hạn tự sụp; lốc xoáy của Phong Linh kéo địch bằng bước cố định 16px/0.5s nên quyết định luận — deterministic — trong checksum). Roster chính thức 8 nhân vật: hồ bốc thăm SP + server đều đủ 8, Bộ sưu tập hiện 8 thẻ (thẻ đã dựng lại dạng ngang cho vừa màn hình), avatar hồ sơ chọn được cả 8. AI/trọng tài chỉ tự tung Chiêu 1 như 4 nhân vật gốc. Kiểm chứng: SP suite có 23 test (14c) riêng cho bộ kit + smoke MP mới `mp_heroes14c_smoke` (Lôi Chấn đấu Thạch Sơn qua lockstep, checksum khớp mọi mốc) — số liệu đầy đủ ở KE-HOACH-MVP mục 14c. Ảnh: `godot/shots/empire_age_heroes8_collection_v1.png`, `empire_age_heroes8_match_v1.png`, `empire_age_heroes8_skill_v1.png`.

**Lịch sử duyệt art (trước khi cài):** Tín duyệt art vòng 1 ngày 2026-11-11: **chỉ #7 Phong Linh được duyệt** ("Chỉ số 7 đẹp") — giữ nguyên v1, không sửa. Art v1 của #5 Lôi Chấn, #6 Xích Diệm, #8 Thạch Sơn bị bác (quá tối / dữ / già so với hướng sáng, trẻ, sạch của #7) — cả ba đã có **art v2** làm lại theo đúng hướng của #7 — nhưng Tín bác tiếp cả ba bản v2 ngày 2026-11-11: **"Vẫn chưa đẹp"** (v2 vẫn còn đơn giản/thiếu độ hoàn thiện so với chuẩn Phong Linh và 4 chân dung gốc). Xử lý: làm **MỘT mẫu vàng (golden sample)** — **#6 Xích Diệm art v3** (công thức nâng mật độ trang trí + độ hoàn thiện, xem "Ghi chú art v3" cuối tài liệu) — Tín **DUYỆT công thức v3** ngày 2026-11-11 qua lệnh **"Sửa 5 với 8"**, và **#5 Lôi Chấn + #8 Thạch Sơn đã có art v3** áp đúng công thức đó. Sau khi xem v3, Tín chỉ đích danh 3 lỗi tư thế/vũ khí (2026-11-11) — đã sửa thành **art v4** (chi tiết ở "Ghi chú art v4" cuối tài liệu): Lôi Chấn chân dung song đao sau lưng chỉ thấy **chuôi đao**, toàn thân song đao cầm tay **hướng lên** (bản v3 bị lật chúc xuống + thừa mũi đao sau vai); Thạch Sơn chân dung **vác chùy trên vai**. Ba ảnh v4 đang **CHỜ DUYỆT** (toàn thân Thạch Sơn giữ v3, không bị chê). Riêng chân dung Thạch Sơn: Tín bắt thêm lỗi "Búa của thạch sơn lệch rồi" ở bản v4 (đầu chùy và cán rời nhau) → đã sửa thành **v5** — chùy một khối một trục thẳng trên cùng một vai (xem "Ghi chú art v5" cuối tài liệu), CHỜ DUYỆT. Kit của cả bốn giữ nguyên như thiết kế gốc (phán quyết chỉ về hình, không về cơ chế). Đợt này chỉ gồm thiết kế + art trình duyệt (chân dung + toàn thân mặt trước cho từng nhân vật, trong `art_candidates/`). Khi được duyệt mới làm tiếp: sheet 8 hướng + rig, cắt vũ khí chính thức, cài kit vào sim.

## Khung cốt truyện chung: TỨ ĐIỆN CHỦ

Bốn Mảnh Vương Miện đã có chủ (Ngân Kỵ · Kim Hoa · Lam Bào · Bạch Sa) — bốn nhân vật mới **không giữ mảnh nào**. Vị trí của họ trong thế giới:

Trước khi có đế chế, Đại Vương Miện được rèn và ban phước tại **bốn ngôi đền nguyên tố** quanh Valdoria: **Sấm Điện** trên đỉnh Vân Lôi Sơn, **Hỏa Điện** giữa sa mạc phương nam, **Phong Điện** trên Thiên Lộ giữa trời, **Thổ Điện** tại Cổng Sơn Môn — con đèo duy nhất đủ rộng cho một đạo quân tiến về kinh đô. Các **Điện Chủ** là chức cha truyền con nối, lâu đời hơn cả ngai vàng. Theo lễ cổ, đoàn rước đăng cơ phải đi qua đủ bốn đền và nhận ấn của bốn Điện Chủ mới tới được Đại Giáo Đường.

Ngày vương miện vỡ, cả bốn Điện Chủ đều có mặt ở Valdoria — và cả bốn đều từ chối làm chứng cho bất kỳ người thừa kế nào. Từ đó Tứ Điện đóng cửa, giữ bốn ngả đường về kinh đô, và tuyên bố: *"Vương miện vỡ vì người giữ nó không xứng. Bốn mảnh kia phải tự chứng minh trước bốn đền."* Trong Chiến Tranh Vương Miện, họ là **thế lực thứ ba**: không tranh mảnh, nhưng ai muốn đăng cơ cũng phải thắng họ, thuyết phục họ, hoặc bị họ chặn đường. Về gameplay họ là 4 nhân vật chính đầy đủ như bốn người thừa kế (bốc thăm vào trận, hero tại Castle đời IV) — khác biệt chỉ nằm ở cốt truyện: họ chiến đấu để **thử thách và phán xét** những kẻ tranh ngôi.

Câu giới thiệu (đúng một câu, theo chuẩn mục 5.4 của COT-TRUYEN.md):

- **Lôi Chấn:** "Điện chủ Sấm Điện — kẻ duy nhất dám gọi sấm xuống giữa đường về Valdoria."
- **Xích Diệm:** "Điện chủ Hỏa Điện phương nam — thà đốt vương miện thành tro còn hơn trao cho kẻ yếu."
- **Phong Linh:** "Điện chủ Phong Điện, tín sứ cuối cùng của Thiên Lộ — mọi tin chiến trường đều qua tay cô trước triều đình."
- **Thạch Sơn:** "Điện chủ Thổ Điện, người giữ Cổng Sơn Môn — mọi đạo quân về Valdoria đều phải qua được cây chùy trấn cổng."

---

## 5. LÔI CHẤN — Điện Chủ Sấm Điện (Nam · SÉT)

- **Danh hiệu:** Lôi Chấn, Song Đao Gọi Sấm
- **Hệ / vai trò:** Sét — đấu sĩ bùng nổ, áp sát tốc độ cao (khác Ngân Kỵ ở chỗ đánh nhanh và dồn dập thay vì xung phong kỷ luật).
- **Vũ khí:** Song đoản đao cong **Lôi Nha** — hai lưỡi đao cong thép bạc luôn có tia sét xanh điện chạy quanh lưỡi.
- **Màu biểu tượng:** Tím violet sáng · trắng · bạc, điểm nhấn xanh điện (art v2 — bản v1 tím sẫm/đen bị bác vì quá tối u ám; v2 cũng bị bác "Vẫn chưa đẹp"). **Art v3 (áp công thức mẫu vàng #6):** họa tiết **SÉT** lặp thành hệ thống từ đầu tới chân — trang sức tóc hình tia sét bạc, khuyên tai tia sét, thêu hồ quang xanh-bạc ở cổ áo/tay áo/gấu áo, khóa áo hình tia sét, trang sức ngực bạc ôm ngọc bão tím-xanh phát sáng; tóc tím sáng buộc đuôi ngựa cao bằng vòng bạc + một đoạn tết điểm trang sức + lọn ôm mặt sắc nét; lễ phục brocade tím nhiều lớp trên giáp phiến trắng-bạc, song đao cong bạc cầm hai tay với hồ quang xanh điện chạy dọc lưỡi; mắt tím điện phát sáng; nền chân dung là Sấm Điện sáng trên biển mây (không phải giông tối của v1).
- **Lãnh địa / móc truyện:** Sấm Điện trên đỉnh Vân Lôi Sơn — nơi lưỡi của Mảnh Kiếm từng được tôi trong sét trời trước lễ rèn vương miện. Lôi Chấn tuyên bố Ngân Kỵ chỉ mới *giữ* Mảnh Kiếm chứ chưa từng được Sấm Điện *công nhận*; muốn qua núi, kỵ sĩ tóc bạc phải đấu tay đôi dưới cơn giông. Anh là đối thủ tốc độ trực diện của Ngân Kỵ: kiếm dài kỷ luật đấu với song đao bão táp.
- **Câu thoại:** Thắng — "Sấm đã phán. Ngươi chưa xứng." / Thua — "Tia sét không bao giờ biến mất. Nó chỉ chờ cơn giông sau."

### Bộ kỹ năng

- **Hào quang — Lôi Vực (bán kính 3 ô):** đồng minh trong vùng **+12% tốc đánh**. (Lớp hiệu ứng mới: tốc đánh — bốn hào quang cũ là +công / hồi máu / chậm địch / giảm sát thương nhận.)
- **Chiêu 1 — Lôi Độn (CD 50s, chọn vị trí, tầm tối đa 5 ô):** Lôi Chấn hóa thành tia sét lao tới điểm chọn; kẻ địch trong 1 ô quanh điểm đáp nhận **40 sát thương**; bản thân **+20% tốc độ di chuyển trong 4s**.
- **Chiêu 2 — Song Lôi Liên Kích (CD 35s, chọn mục tiêu, tầm 5 ô):** tia sét đánh mục tiêu **55 sát thương** rồi nảy sang tối đa **3 kẻ địch gần nhất** trong 2 ô, mỗi kẻ **30 sát thương**.
- **Chiêu 3 (Ulti) — Thiên Lôi Phạt Trận (CD 130s, chọn vị trí, tầm 6 ô):** gọi bão sét xuống vùng **bán kính 3 ô trong 6s**; mỗi 1s một đợt sét đánh **45 sát thương** lên mọi kẻ địch trong vùng (công trình nhận 50%); kẻ địch đang ở trong vùng bị **chậm 20%**.

---

## 6. XÍCH DIỆM — Điện Chủ Hỏa Điện (Nữ · LỬA)

- **Danh hiệu:** Xích Diệm, Hỏa Phiến Thiêu Thiên
- **Hệ / vai trò:** Lửa — chỉ huy sát thương diện rộng, đốt cháy theo thời gian (khác Kim Hoa ở chỗ Kim Hoa giữ quân sống, Xích Diệm thiêu quân địch).
- **Vũ khí:** Thiết phiến **Diệm Vân** — quạt chiến sắt đen khổ lớn, mặt quạt khảm họa tiết lửa đỏ-vàng, nan quạt là lưỡi thép mỏng.
- **Màu biểu tượng:** Đỏ thắm (crimson) · trắng · vàng kim. (Art v1 bị bác: dữ/tối; art v2 bị bác 2026-11-11: "Vẫn chưa đẹp" — còn đơn giản so với chuẩn Phong Linh. **Art v3 — mẫu vàng, Tín ĐÃ DUYỆT công thức 2026-11-11 (lệnh "Sửa 5 với 8"):** tóc crimson rất dài, bồng bềnh, có vương miện tết + nhiều trang sức tóc hình lửa bằng vàng và tua rủ; hào quang họa tiết "lửa vàng" lặp ở mọi chi tiết — trâm tóc, khuyên tai, thêu cổ áo, miếng trang sức ngực ngọc lửa đỏ, khóa áo, đai, gấu áo, giày; lễ phục nhiều lớp: cổ brocade cao thêu lửa vàng, choàng vai viền lông trắng, áo trong lụa trắng, đai vàng chạm lửa; thiết phiến sắt đen họa tiết lửa đỏ-vàng cầm mở; mắt hổ phách-vàng phát sáng, cười tự tin; nền Hỏa Điện hoàng hôn ấm.)
- **Lãnh địa / móc truyện:** Hỏa Điện giữa sa mạc Valdoria Ngoại Biên — nơi giữ Ngọn Lửa Vĩnh Cửu đã nung chảy vàng của Đại Vương Miện. Phương nam bị triều đình bỏ đói qua nhiều mùa chiến tranh; Xích Diệm là Điện Chủ đầu tiên công khai nói vương miện nên bị **nung chảy rèn lại** thay vì trao cho một trong bốn người thừa kế. Cô là đối trọng tư tưởng của Kim Hoa: lòng dân bằng lễ hội và sắc phong, hay bằng lửa và sự thật trần trụi.
- **Câu thoại:** Thắng — "Tro tàn cũng là một loại câu trả lời." / Thua — "Lửa tắt hôm nay, than hồng còn đó."

### Bộ kỹ năng

- **Hào quang — Hỏa Tâm (bán kính 3 ô):** đòn đánh của đồng minh trong vùng **thiêu đốt** mục tiêu: **3 HP/0.5s trong 2s** (không cộng dồn, đánh trúng làm mới thời gian). (Lớp hiệu ứng mới: DoT gắn đòn đánh.)
- **Chiêu 1 — Hỏa Ấn (CD 60s, chọn mục tiêu, tầm 6 ô):** khắc ấn lửa lên một kẻ địch; sau **2s** ấn phát nổ **70 sát thương** trong **bán kính 1.5 ô** quanh mục tiêu (mục tiêu chết trước khi nổ thì ấn nổ tại chỗ nó ngã).
- **Chiêu 2 — Diệm Phiến Toàn (CD 35s, tung theo hướng mặt):** quạt ra quạt lửa hình nón **120°, dài 3 ô**: **50 sát thương** ngay + thiêu đốt **4 HP/0.5s trong 3s**.
- **Chiêu 3 (Ulti) — Phượng Hỏa Giáng (CD 140s, chọn vị trí, tầm 6 ô):** phượng lửa giáng xuống vùng **bán kính 3 ô**: **130 sát thương** ngay (công trình 150), mặt đất cháy tiếp **5s** gây **12 HP/0.5s** cho kẻ địch đứng trong vùng. Không choáng — khác Vương Kiếm Giáng Thế ở vùng cháy kéo dài.

---

## 7. PHONG LINH — Điện Chủ Phong Điện (Nữ · GIÓ)

**Art v1: TÍN DUYỆT ngày 2026-11-11 ("Chỉ số 7 đẹp") — giữ nguyên, không sửa.** Đây cũng là chuẩn phong cách cho art v2 của ba nhân vật còn lại.

- **Danh hiệu:** Phong Linh, Tín Sứ Thiên Lộ
- **Hệ / vai trò:** Gió — **hero đánh xa đầu tiên của game**, quấy rối tầm xa và khống chế bằng dịch chuyển vị trí địch. (Bốn nhân vật cũ đều cận chiến/cận-trung.)
- **Vũ khí:** Trường cung **Thiên Vũ** — cung dài gỗ sáng gắn lông vũ trắng và bạc; ống tên sau lưng đựng tên lông trắng.
- **Màu biểu tượng:** Xanh ngọc (teal) · trắng · bạc. Tóc xanh bạc hà tết bím dài điểm lông vũ trắng, mắt xanh lục.
- **Lãnh địa / móc truyện:** Phong Điện nằm trên Thiên Lộ — mạng lưới tháp tín hiệu và đường núi treo giữa trời nối bốn miền đất; đời đời Điện Chủ Phong Điện là người đưa tin chiến trường nhanh nhất đại lục. Phong Linh biết mọi đạo quân di chuyển trước cả khi tướng của chúng biết. Cô giữ thái độ trung lập lâu nhất trong bốn Điện Chủ và chỉ ra trận khi một người thừa kế định phá tháp tín hiệu để bịt mắt cả đại lục. Trên đỉnh đèo bắc, gió của cô và băng của Lam Bào là hai thứ thời tiết tranh nhau từng tấc đường.
- **Câu thoại:** Thắng — "Gió đã mang tin này đi khắp bốn miền rồi." / Thua — "Tin xấu cũng phải có người mang. Hôm nay là ta."

### Bộ kỹ năng

- **Hào quang — Phong Hành (bán kính 3 ô):** đồng minh trong vùng **+12% tốc độ di chuyển**. (Phía đồng minh — khác hào quang chậm của Lam Bào vốn tác động phía địch.)
- **Chiêu 1 — Truy Phong Tiễn (CD 45s, chọn mục tiêu, tầm 8 ô):** một phát bắn tỉa xuyên gió: **75 sát thương** lên một kẻ địch, bỏ qua mọi đơn vị đứng giữa đường bay.
- **Chiêu 2 — Tiễn Vũ (CD 30s, chọn vị trí, tầm 6 ô):** mưa tên xuống vùng **bán kính 2.5 ô trong 3s**: 3 đợt, mỗi đợt **20 sát thương** lên kẻ địch trong vùng.
- **Chiêu 3 (Ulti) — Cuồng Phong Nộ (CD 120s, chọn vị trí, tầm 6 ô):** lốc xoáy khổng lồ **bán kính 3.5 ô trong 6s**: kẻ địch trong vùng bị **kéo dần về tâm lốc** (0.5 ô/0.5s), nhận **15 HP/0.5s** và **−30% công** khi còn trong vùng. (Cơ chế mới hoàn toàn: dịch chuyển vị trí địch — không nhân vật cũ nào có.)

---

## 8. THẠCH SƠN — Điện Chủ Thổ Điện (Nam · ĐẤT)

- **Danh hiệu:** Thạch Sơn, Sơn Môn Bất Động
- **Hệ / vai trò:** Đất — tanker chống công thành, dựng địa hình (khác Bạch Sa ở chỗ Bạch Sa bảo vệ bằng khiên/màn, Thạch Sơn bảo vệ bằng giáp cứng và tường đá thật).
- **Vũ khí:** Đại chùy **Sơn Hà** — chùy đá nguyên khối nẹp đồng, đầu chùy khắc phù văn núi, to gần bằng thân người.
- **Màu biểu tượng:** Đồng ấm · vàng đất (ochre) · trắng · xám đá sáng (art v2 — THIẾT KẾ LẠI NGƯỜI: bản v1 tướng già râu quai nón vạm vỡ bị bác; v2 là hộ vệ trẻ tuổi; v2 cũng bị bác "Vẫn chưa đẹp"). **Art v3 (áp công thức mẫu vàng #6, giữ nguyên thiết kế hộ vệ trẻ của v2):** họa tiết **NÚI** lặp thành hệ thống — băng trán đồng khắc dãy núi (dấu ấn riêng), thêu dãy núi vàng trên khăn trắng và cổ áo/gấu áo, khóa đồng hình học, phù hiệu ngực đồng hình đỉnh núi lớn, khóa đai hình đỉnh núi, giày nẹp đồng chạm núi; tóc nâu ấm tạo cấu trúc bằng băng trán + một bím nhỏ buộc vòng đồng bên tai; giáp phiến đá xám sáng phối phiến đồng nhiều lớp, mọi viền chạm hình học núi; đại chùy đá nẹp đồng dựng cạnh người; mắt hổ phách phát sáng; nền chân dung là Cổng Sơn Môn nắng sáng giữa các đỉnh núi.
- **Lãnh địa / móc truyện:** Thổ Điện tại Cổng Sơn Môn — con đèo duy nhất xe công thành qua được để về Valdoria. Thạch Sơn là Điện Chủ trẻ nhất trong Tứ Điện: hậu duệ đời thứ chín của tướng giữ cổng cho Hoàng đế cuối cùng, vừa kế nhiệm theo lệ cha truyền con nối. Anh giữ lời thề tổ tiên rằng cổng chỉ mở cho một hoàng đế thật; với anh, bốn người thừa kế đều chưa ai chứng minh được mình xứng đáng. Anh là bức tường cuối cùng trên đường về kinh đô của mọi phe — kể cả Lam Bào từ phương bắc xuống.
- **Câu thoại:** Thắng — "Cổng vẫn đóng. Núi vẫn đứng." / Thua — "Núi sạt một lần không có nghĩa là đường đã thông."

### Bộ kỹ năng

- **Hào quang — Thổ Giáp (bán kính 3 ô):** đồng minh trong vùng được **+3 giáp phẳng** (mỗi đòn nhận vào giảm thẳng 3 sát thương, tối thiểu 1). (Lớp hiệu ứng mới: giảm phẳng — khác giảm % của Bạch Sa.)
- **Chiêu 1 — Sơn Băng Đạp (CD 55s, chọn vị trí, tầm tối đa 4 ô):** Thạch Sơn nhảy bổ tới điểm chọn; khi tiếp đất gây **40 sát thương** trong **bán kính 2 ô**, **đẩy lùi kẻ địch 1 ô** ra xa tâm và **chậm 30% trong 2s**.
- **Chiêu 2 — Nham Tường (CD 40s, chọn vị trí, tầm 5 ô):** dựng tường đá dài **3 ô** theo hướng mặt tại điểm chọn: mỗi ô là chướng ngại **300 HP**, chặn đường đi như công trình, tồn tại **12s** rồi sụp (bị phá sớm nếu địch đánh). (Cơ chế mới: tạo địa hình tạm.)
- **Chiêu 3 (Ulti) — Địa Long Lật Đất (CD 150s, chọn vị trí, tầm 6 ô):** động đất vùng **bán kính 3.5 ô**: **90 sát thương** lên quân và **300 sát thương lên công trình**, kẻ địch sống sót bị **chậm 40% trong 3s** vì đất nứt. (Chuyên công thành: tỉ lệ sát thương công trình cao nhất trong 8 nhân vật; đánh đổi bằng không có khống chế cứng.)

---

## Bảng đối chiếu nhanh 8 nhân vật

| # | Nhân vật | Giới | Hệ | Vũ khí | Hào quang | Vai trò |
|---|---|---|---|---|---|---|
| 1 | Ngân Kỵ | Nam | Kiếm/Lý | Trường kiếm | +15% công | Xung phong |
| 2 | Kim Hoa | Nữ | Sinh/Hoa | Trượng hoa | Hồi máu | Hồi phục |
| 3 | Lam Bào | Nam | Băng | Thương băng | Chậm địch | Khống chế băng |
| 4 | Bạch Sa | Nữ | Thánh | Thánh trượng | −10% sát thương nhận | Khiên/bảo hộ |
| 5 | **Lôi Chấn** | Nam | **Sét** | **Song đoản đao** | **+12% tốc đánh** | Bùng nổ áp sát |
| 6 | **Xích Diệm** | Nữ | **Lửa** | **Thiết phiến** | **Đòn đánh thiêu đốt** | Sát thương diện + DoT |
| 7 | **Phong Linh** | Nữ | **Gió** | **Trường cung** | **+12% tốc độ chạy** | Đánh xa / kéo vị trí |
| 8 | **Thạch Sơn** | Nam | **Đất** | **Đại chùy đá** | **+3 giáp phẳng** | Tank / chống công thành |

## Art trình duyệt (trong `art_candidates/`)

| Nhân vật | Chân dung | Toàn thân | Trạng thái |
|---|---|---|---|
| Lôi Chấn | `char5_loi_chan_portrait_v4.png` | `char5_loi_chan_full_v4.png` | **v4 CHỜ DUYỆT** — sửa đúng 2 lỗi Tín chỉ ở v3 (2026-11-11): chân dung song đao đeo lưng CHỈ THẤY CHUÔI (cán quấn + chặn tay bạc, không lưỡi trần sau lưng); toàn thân song đao cầm hai tay MŨI HƯỚNG LÊN, hết mũi đao thứ ba sau vai (v3 nền là công thức mẫu vàng #6 đã duyệt; v2 bị bác "Vẫn chưa đẹp"; v1 bị bác: quá tối u ám) |
| Xích Diệm | `char6_xich_diem_portrait_v3.png` | `char6_xich_diem_full_v3.png` | **v3 MẪU VÀNG — công thức ĐÃ DUYỆT 2026-11-11** qua lệnh "Sửa 5 với 8" (v2 bị bác "Vẫn chưa đẹp"; v1 bị bác: dữ/tối) |
| Phong Linh | `char7_phong_linh_portrait_v1.png` | `char7_phong_linh_full_v1.png` | **ĐÃ DUYỆT 2026-11-11 — giữ nguyên** |
| Thạch Sơn | `char8_thach_son_portrait_v5.png` | `char8_thach_son_full_v3.png` | **Chân dung v5 CHỜ DUYỆT** — v4 bị Tín bắt lỗi "Búa của thạch sơn lệch rồi" (đầu chùy nổi sau vai trái, cán nằm ở vai phải, hai mảnh rời nhau); v5 sửa: chùy MỘT KHỐI TRÊN MỘT TRỤC THẲNG — tay nắm cán tại vai phải, cán chạy một đường thẳng qua vai đó và cắm thẳng vào tâm đầu chùy đá nẹp đồng nằm ngay sau/trên cùng vai (đã kiểm chứng bằng kẻ thẳng: nắm cán → qua vai → vào tâm đầu chùy, không gãy, không lệch, không cán thứ hai, khớp nối lộ rõ không bị tóc che); toàn thân giữ v3 (không bị chê). Nền thiết kế: công thức mẫu vàng #6 đã duyệt, giữ thiết kế hộ vệ trẻ của v2 (v2 bị bác "Vẫn chưa đẹp"; v1 bị bác: già/vạm vỡ) |

Bản phụ: `char6_xich_diem_portrait_framedalt_v1.png` và `char7_phong_linh_portrait_framedalt_v1.png` — cùng hai nhân vật nhưng chân dung bị đóng khung trang trí kiểu `king_avatar_*` (sinh ở lượt đầu do dùng ảnh khung làm mẫu); giữ lại làm phương án nếu muốn chân dung dạng có khung, bản chính là bản tràn viền như `avatar_sq_*`.

**Chốt duyệt (2026-11-11):** Tín duyệt toàn bộ bộ art cuối (Lôi Chấn v4 · Xích Diệm v3 · Phong Linh v1 · Thạch Sơn chân dung v5 + toàn thân v3) — các nhãn "CHỜ DUYỆT" trong bảng trên là trạng thái tại thời điểm viết từng dòng, nay đã hết hiệu lực. Cả bốn đã vào game ở đợt 14c (xem trạng thái ở đầu tài liệu).

**Ghi chú khớp phong cách:** chân dung khớp tốt với bộ cũ (anime vẽ mềm bán tả thực, nền cảnh theo miền đất của nhân vật). Ảnh toàn thân theo format design-sheet nền gradient trơn (game chưa có tiền lệ toàn thân dạng này — bộ cũ đi thẳng từ chân dung sang sheet 8 hướng), đường nét toàn thân hơi "sạch" hơn chân dung chút ít; nếu duyệt, bước rig/sheet sẽ thống nhất lại theo chân dung.

**Ghi chú art v2 (2026-11-11):** cả ba bản v2 bám đúng công thức đã thắng của #7 — nền sáng, mặt trẻ đẹp, một màu chủ đạo mạnh + trắng/bạc, trang phục gọn và thanh thoát, nét anime vẽ mềm. #5 bỏ hẳn gam tím-đen u ám (sang violet sáng + trắng/bạc + sét xanh điện, nền trời trong thay vì giông tối); #6 bỏ vẻ dữ/tối (sang crimson + trắng/vàng, lửa chỉ là họa tiết thêu và dải lửa trang trí trong nắng ấm); #8 đổi hẳn người — từ tướng già râu ria thành hộ vệ trẻ tuấn tú (giáp đá sáng + đồng ấm + khăn trắng). File v1 vẫn giữ nguyên trên đĩa để đối chiếu, không ghi đè. **Kết cục: cả ba bản v2 đều bị Tín bác ngày 2026-11-11 — "Vẫn chưa đẹp".**

**Ghi chú art v3 — MẪU VÀNG #6 Xích Diệm (2026-11-11 — công thức ĐÃ DUYỆT qua lệnh "Sửa 5 với 8"):** bài học rút ra là "sáng/trẻ/sạch" chưa đủ — v2 vẫn thua chuẩn duyệt ở **mật độ chi tiết và độ hoàn thiện**. Công thức v3, trích trực tiếp từ Phong Linh + 4 chân dung gốc: (1) **một họa tiết chủ đạo lặp thành hệ thống** khắp tóc/trang sức/trang phục/vũ khí (Phong Linh: lông vũ/lá bạc — Xích Diệm: lửa vàng); (2) **tóc là cấu trúc thiết kế** (tết + búi + lọn ôm mặt + trang sức cài xen), không phải tóc gợn sóng generic; (3) **trang phục nhiều lớp nhiều chất liệu**, mỗi lớp có viền/hoa văn riêng (brocade + lông + lụa + trang sức vàng); (4) **mắt lớn phát sáng có gradient + mặt có thần thái**, chiếm khung lớn; (5) **nền cảnh sơn dầu theo lãnh địa**, shading mềm chi tiết, không vùng phẳng. Tín duyệt công thức khi lệnh **"Sửa 5 với 8"** (2026-11-11). **Áp dụng cho #5/#8 (art v3, CHỜ DUYỆT):** Lôi Chấn — họa tiết SÉT thành hệ thống (trang sức tóc + khuyên tai tia sét bạc, thêu hồ quang, khóa hình tia sét, ngọc bão phát sáng), tóc đuôi ngựa cao vòng bạc + đoạn tết, nền Sấm Điện sáng trên biển mây; Thạch Sơn — họa tiết NÚI thành hệ thống (băng trán đồng khắc dãy núi, thêu núi vàng trên khăn/cổ/gấu, phù hiệu ngực đỉnh núi), tóc nâu có cấu trúc bằng băng trán + bím nhỏ, giữ người hộ vệ trẻ của v2, nền Cổng Sơn Môn nắng sáng. Chi tiết nhỏ cần lưu ý khi duyệt: bản toàn thân Lôi Chấn v3 có một mũi đao cong thứ ba lộ sau vai (đọc như đao đeo lưng dự phòng) — nếu Tín không ưng thì sửa ở vòng sau.

**Ghi chú art v4 — SỬA 3 LỖI TÍN CHỈ Ở V3 (2026-11-11, CHỜ DUYỆT):** Tín xem v3 và bắt đúng ba lỗi đọc-hình: (1) **Lôi Chấn chân dung** — "song đao sau lưng là cái chuôi": v3 để nguyên một lưỡi đao cong trần nhô lên sau lưng trái; v4 song đao **tra vỏ đeo lưng, chỉ hai CHUÔI ĐAO (cán quấn tối + chặn tay/núm bạc chạm trổ) chéo nhau nhô qua hai vai** sau đầu, không một phân lưỡi trần nào sau lưng, hồ quang xanh điện nhỏ quanh chuôi. File: `char5_loi_chan_portrait_v4.png`. (2) **Lôi Chấn toàn thân** — "song đao thì bị qua úp xuống": v3 cầm hai đao chúc mũi xuống đất + thừa mũi đao thứ ba sau vai; v4 cầm **đúng hai đao, mỗi tay một chiếc, giơ thế sẵn sàng với lưỡi cong mở hướng LÊN-TRÊN, mũi đao chĩa lên**, không còn đao nào sau lưng (vì cả hai đang ở trên tay). File: `char5_loi_chan_full_v4.png`. (3) **Thạch Sơn chân dung** — "phải vẽ là vác búa trên vai": v3 chùy chỉ dựng/tựa cạnh người; v4 **đầu chùy đá nẹp đồng tựa hẳn TRÊN VAI trái, tay phải nắm cán gỗ ngay tại vai** — đọc rõ tư thế vác chùy anh hùng ngay từ thumbnail. File: `char8_thach_son_portrait_v4.png`. Toàn thân Thạch Sơn v3 không bị chê nên giữ nguyên. Cả ba bản v4 giữ nguyên mặt, tóc, trang phục, hệ họa tiết và nền của v3 (chỉ sửa tư thế/vũ khí như trên), đã soi trực tiếp từng ảnh trước khi giao.

**Ghi chú art v5 — SỬA LỖI CHÙY LỆCH CỦA THẠCH SƠN (2026-11-11, CHỜ DUYỆT):** Tín xem chân dung v4 và bắt lỗi "Búa của thạch sơn lệch rồi": trong v4, đầu chùy đá nổi sau vai trái trong khi cán gỗ nằm ở vai phải — hai mảnh rời nhau, trục cán không bao giờ gặp ổ cắm của đầu chùy (đoạn cán của đầu chùy biến mất sau tóc). **V5** (`char8_thach_son_portrait_v5.png`) vẽ lại chùy thành **một vật cứng duy nhất trên một trục thẳng**: tay phải nắm cán ngay tại vai phải, cán tựa qua đúng vai đó và chạy tiếp **một đường thẳng không gãy** ra sau vai, đầu chùy đá nẹp đồng **cắm trên đúng trục đó**, nằm ngay sau/trên cùng vai phải; khớp nối cán–đầu lộ rõ giữa không trung, không bị tóc hay áo che, không còn mảnh chùy nào ở phía vai trái. Kiểm chứng kẻ thẳng khi soi ảnh: kẻ một đường từ đoạn cán trong tay → qua điểm tựa vai → tiếp thẳng vào tâm đầu chùy — thẳng hàng, không lệch, không cán thứ hai. Giữ nguyên người hộ vệ trẻ, mặt, băng trán đồng khắc núi, bím bên, trang phục + hệ họa tiết núi, nền Sơn Môn của v4.
