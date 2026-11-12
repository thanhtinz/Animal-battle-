# BỘ 8 VỊ TƯỚNG TÂY TRUNG CỔ — Thiết kế thay roster (Đợt 16)

> Nguồn thiết kế duy nhất: bảng tướng Tín gửi 2026-11-11 ("Bộ 8 Vị Tướng Tây Trung Cổ",
> `art_candidates/` — file gốc `~/workspace/user/files/DD3568F1-...jpg`).
> Mọi chi tiết ngoại hình dưới đây đọc trực tiếp từ pixel của bảng (chân dung + toàn thân
> + hàng sprite 8 hướng), không suy từ tên gọi.
>
> **Phạm vi đợt 16a (đợt này):** thiết kế + art (sprite 8 hướng, rig, avatar) làm THÊM
> vào dự án, chưa xoá/chưa nối dây. **Đợt sau:** xoá roster cũ (Ngân Kỵ · Kim Hoa ·
> Lam Bào · Bạch Sa · Lôi Chấn · Xích Diệm · Phong Linh · Thạch Sơn) và nối bộ này vào
> Characters/stats/server/Collection theo đúng dữ liệu ở tài liệu này.
>
> **Luật cân bằng Tín chốt 2026-11-11:** mỗi tướng chỉ có **1 skill chủ động duy nhất**
> — chiêu tủ thể hiện đúng vai trò. Không C1/C2/Ulti, không combo nhiều tầng.

---

## 1. Khung cân bằng chung

- **Hồi chiêu chung: 75 giây cho cả 8 tướng.** Lý do: roster cũ có C1 hồi 45–70s
  (hiệu ứng vừa), C2 30–40s (nhỏ) và Ulti 120–150s (rất mạnh). Nay mỗi tướng chỉ còn
  một chiêu nên chiêu đó phải nằm giữa C1 và Ulti: mạnh hơn C1 cũ rõ rệt nhưng dùng
  được ~2 lần trong quãng một Ulti cũ hồi xong. Một con số chung cho cả 8 cũng là
  đòn bẩy cân bằng sạch nhất — không tướng nào "lãi" vì hồi nhanh hơn.
- **Ngân sách sức mạnh của 1 skill** (đối chiếu roster cũ): sát thương 100–160
  (Ulti cũ: 120 diện rộng / 250 lên công trình), hồi máu 150–160 diện rộng
  (Ulti Kim Hoa cũ: 200 + miễn nhiễm), khống chế 2–4 giây, khiên hấp thụ ≤ 200.
  Mỗi skill chỉ có **một hiệu ứng duy nhất** — không kèm hiệu ứng phụ.
- **Đòn đánh thường:** theo đúng khung tướng hiện tại (HP ~650, sát thương ~26/đòn
  với tướng cận chiến). Tướng đánh xa dùng tầm **160** như tiền lệ Phong Linh
  (tướng đánh xa đầu tiên của game).
- **Hào quang (Tín chốt 2026-11-11):** mỗi tướng có **1 hào quang thụ động** cộng
  thêm đúng 1 kỹ năng chủ động ở trên — giữ nguyên khung "hào quang + chiêu tủ"
  của game. Số hào quang cân bằng như hiệu ứng thụ động độc lập (nhỏ, luôn bật,
  bán kính 3 ô như hào quang của roster cũ) và KHÔNG tính vào ngân sách của skill.

## 2. Cốt truyện chung (gọn, không đụng cốt truyện Vương Miện)

Tám vị tướng là **Hiệp Sĩ Đoàn Sao Phương Tây** — một đoàn viễn chinh hiệp sĩ từ
vương quốc bên kia biển Tây, cập bến Valdoria sau khi bản đồ sao cổ trong thư viện
của đoàn chỉ về nơi Đại Vương Miện được rèn. Họ không giữ Mảnh Vương Miện nào và
không tranh ngôi: họ đến để tận mắt xét xem kẻ tự xưng kế thừa Vương Miện có xứng
đáng hay không — và cho mướn gươm của mình trong lúc chờ đợi. (Canon nhẹ, không
thay thế cốt truyện chính ở `COT-TRUYEN.md`.)

---

## 3. Từng tướng

### 3.1 `knight` — Hiệp Sĩ Hoàng Gia (Knight) · Vai trò: Đỡ Đòn

- **Nhận diện (đọc từ ảnh):** nam, tóc vàng vuốt ngược sóng lớn, mắt xanh dương,
  mặt cương nghị. Giáp tấm bạc viền VÀNG, áo tabard xanh dương, **áo choàng xanh
  dương dài** sau lưng. Tay phải **trường kiếm** lưỡi bạc cán vàng; tay trái
  **khiên heater xanh navy, viền vàng, huy hiệu SƯ TỬ VÀNG** chồm. Hệ motif:
  sư tử vàng + viền vàng lặp trên giáp/khiên. Băng cờ: xanh dương, hai kiếm chéo.
- **Đánh thường:** cận chiến bằng kiếm (tầm cận chiến).
- **SKILL — Khiên Sư Tử (hồi chiêu 75s):** giương khiên sư tử, gầm lệnh: nhận
  một lớp khiên hấp thụ **250 sát thương** trong **6 giây**, đồng thời mọi địch
  trong bán kính **3 ô** bị buộc phải tấn công Hiệp Sĩ trong **4 giây**. (Một
  thế thủ duy nhất: khiên hấp thụ + khiêu khích là cùng một lần dựng khiên.)
- **Hào quang (thụ động):** đồng minh trong 3 ô giảm 8% sát thương nhận vào.

### 3.2 `berserker` — Chiến Binh Cuồng Nộ (Berserker) · Vai trò: Đấu Sĩ

- **Nhận diện:** nam lực lưỡng, **tóc đỏ dựng ngược + râu quai nón đỏ** kín cằm,
  mặt gầm dữ. Ngực trần cơ bắp, **choàng lông thú trắng-xám** qua vai, dây da nâu
  chéo ngực, thắt lưng nâu đính đinh, quần tối, ủng viền lông. Vũ khí: **rìu chiến
  lớn một lưỡi** cán gỗ, lưỡi bạc — cầm tay phải. Hệ motif: đỏ (tóc/râu) + lông
  trắng + da nâu. Băng cờ: đỏ sẫm, hai rìu chéo.
- **Đánh thường:** cận chiến bằng rìu (đòn chậm hơn kiếm, sát thương mỗi đòn cao hơn).
- **SKILL — Rìu Xoáy Cuồng Nộ (hồi chiêu 75s):** xoay rìu một vòng lớn: gây
  **110 sát thương** cho mọi địch trong bán kính **2 ô** quanh mình.
- **Hào quang (thụ động):** đồng minh trong 3 ô tăng 10% tốc độ đánh.

### 3.3 `archer` — Cung Thủ Tinh Anh (Archer) · Vai trò: Xạ Thủ

- **Nhận diện:** nữ tinh linh (elf), tóc vàng dài, **tai nhọn**, trán đeo **vòng
  trán xanh lá đính ngọc**, mắt xanh dương. Áo tunic xanh lá viền vàng, áo choàng
  xanh lá, thắt lưng + ủng nâu, **ống tên đeo sau lưng**. Tay trái cầm **cung gỗ
  cong** (recurve). Hệ motif: xanh lá + vàng + tai nhọn/vòng trán là dấu nhận
  diện. Băng cờ: xanh lá, huy hiệu cung-tên vàng.
- **Đánh thường:** đánh xa bằng cung, tầm **160** (như tiền lệ Phong Linh).
- **SKILL — Mưa Tên (hồi chiêu 75s):** gọi một cơn mưa tên xuống một khu vực
  bán kính **2,5 ô** trong tầm **8 ô**: **3 đợt tên** trong 2 giây, mỗi đợt gây
  **40 sát thương** cho mọi địch trong vùng (tổng tối đa **120**).
- **Hào quang (thụ động):** đồng minh trong 3 ô tăng 8% sát thương đòn đánh.

### 3.4 `mage` — Pháp Sư Cung Đình (Mage) · Vai trò: Pháp Sư

- **Nhận diện:** nữ, **tóc bạc trắng dài**, mắt tím. **Áo choàng tím sẫm có mũ
  trùm**, viền VÀNG, trên mũ thêu **sao vàng nhỏ**, thắt lưng vàng. Tay phải cầm
  **trượng vàng cao**, đầu trượng là **quả cầu tím phát sáng** có tia lửa. Hệ
  motif: tím + vàng + sao trên mũ lặp lại. Băng cờ: tím, huy hiệu trượng-chìa.
- **Đánh thường:** đánh xa bằng tia ma thuật từ cầu trượng, tầm **160**.
- **SKILL — Thiên Thạch Ma Thuật (hồi chiêu 75s):** gọi một thiên thạch ma
  thuật rơi xuống một điểm:
  nổ diện rộng bán kính **2,5 ô**, gây **120 sát thương** phép cho địch trong vùng.
- **Hào quang (thụ động):** đồng minh trong 3 ô hồi 1,2 HP mỗi giây.

### 3.5 `paladin` — Thánh Kỵ Sĩ (Paladin) · Vai trò: Hỗ Trợ

- **Nhận diện:** nam, tóc vàng, **râu ngắn sẫm** quanh cằm, mắt xanh dương, cổ áo
  có khoá cài ngọc xanh lá. Giáp tấm **trắng-bạc phủ viền VÀNG**, motif **thập tự
  vàng** lặp trên giáp vai + thắt lưng, áo choàng trắng. Tay phải cầm **búa chiến
  vàng** (đầu búa vuông) — *đọc từ pixel: là búa, không phải kiếm*; tay trái
  **khiên heater trắng viền vàng, thập tự VÀNG lớn** giữa khiên. Băng cờ: trắng,
  thập tự vàng.
- **Đánh thường:** cận chiến bằng búa chiến (tầm cận chiến).
- **SKILL — Thánh Quang Hồi Phục (hồi chiêu 75s):** giương khiên thập tự cầu
  nguyện: hồi **160 HP** cho mọi đồng minh trong bán kính **3 ô** quanh mình và
  **giải mọi hiệu ứng xấu** (làm chậm, thiêu đốt, giữ chân...) trên họ.
- **Hào quang (thụ động):** đồng minh trong 3 ô được +3 giáp phẳng.

### 3.6 `dragoon` — Kỵ Sĩ Long (Dragoon) · Vai trò: Cơ Động

- **Nhận diện:** nam, **tóc trắng bạc dựng**, mặt lạnh nghiêm, mắt xanh. Giáp tấm
  **xanh dương sẫm viền VÀNG dày**, giáp vai chạm **họa tiết rồng vàng**, thắt
  lưng vàng đính ngọc xanh, **áo choàng xanh dài**. Tay phải cầm **thương dài**
  cán vàng, mũi thương bạc hướng xuống-trước; bên hông trái còn một thanh kiếm
  mảnh đeo làm trang bị phụ (chi tiết trang phục, không phải vũ khí chính).
  Băng cờ: vàng, huy hiệu đầu ngựa.
- **Đánh thường:** cận chiến bằng thương — tầm đánh dài hơn kiếm (~1,3 lần tầm
  cận chiến thường).
- **SKILL — Long Thương Xuyên Tâm (hồi chiêu 75s):** lao thẳng theo một đường
  thẳng tối đa **5 ô**: gây **120 sát thương** cho mọi địch nằm trên đường lao
  (bề ngang **1 ô**) và dừng ở cuối đường hoặc khi chạm công trình.
- **Hào quang (thụ động):** đồng minh trong 3 ô tăng 10% tốc độ di chuyển.

### 3.7 `assassin` — Sát Thủ Bóng Đêm (Assassin) · Vai trò: Sát Thủ

- **Nhận diện:** nam, **mũ trùm than đen + khăn bịt nửa mặt dưới**, tóc đen ló
  dưới mũ, mắt sắc lạnh. **Khăn quàng cổ ĐỎ** là điểm nhấn màu duy nhất trên nền
  giáp **đen than**, áo choàng đen lót **đỏ burgundy**, thắt lưng khoá vàng.
  Hai tay hai **đoản kiếm** lưỡi bạc. Hệ motif: đen + đỏ (khăn/lót choàng).
  Băng cờ: xám than, hai kiếm chéo.
- **Đánh thường:** cận chiến bằng song đoản kiếm (tốc độ đánh nhanh nhất nhóm).
- **SKILL — Ám Sát (hồi chiêu 75s):** biến mất và xuất hiện ngay sau lưng một
  địch trong tầm **6 ô**, đâm một đòn chí mạng gây **160 sát thương**.
- **Hào quang (thụ động):** đồng minh trong 3 ô tăng 10% sát thương khi đánh tướng địch.

### 3.8 `ranger` — Nhà Thám Hiểm (Ranger) · Vai trò: Thám Hiểm

- **Nhận diện:** nữ, **tóc đỏ dài uốn sóng**, đội **mũ thám hiểm nâu vành rộng**
  có dải vàng + **lông vũ trắng lớn**, mặt tươi tự tin. Áo khoác **da nâu viền
  lông trắng** (vai + gấu áo), thắt lưng **khoá tròn vàng lớn**, ngực đeo dây
  chéo gắn **huy chương ngọc xanh teal**, áo choàng nâu dài, ủng nâu. Tay trái
  cầm **kiếm dài** lưỡi **bạc-xanh**, cán vàng chạm khắc — *đọc từ pixel +
  Tín kiểm chứng: là kiếm (kiếm sĩ cơ động), không phải súng*. Băng cờ: vàng
  nâu, huy hiệu đàn lyre.
- **Đánh thường:** cận chiến bằng kiếm (tầm cận chiến, tốc độ đánh nhanh).
- **SKILL — Kiếm Vũ Lữ Hành (hồi chiêu 75s):** múa kiếm thần tốc: tung **5
  nhát chém** trong 1 giây vào các địch trong bán kính **2 ô** quanh mình, mỗi
  nhát **32 sát thương** (tổng tối đa **160**, các nhát chia đều cho các địch
  trong vùng, một địch có thể trúng nhiều nhát).
- **Hào quang (thụ động):** đồng minh trong 3 ô tăng 1 ô tầm nhìn.

---

## 4. Bảng tổng kết

| id | Tên | Vai trò | Đánh thường | Hào quang (thụ động, r3) | Skill duy nhất (75s) |
|---|---|---|---|---|---|
| knight | Hiệp Sĩ Hoàng Gia | Đỡ Đòn | Kiếm, cận chiến | Đồng minh giảm 8% sát thương nhận | Khiên Sư Tử: khiên hấp thụ 250 trong 6s + khiêu khích r3 trong 4s |
| berserker | Chiến Binh Cuồng Nộ | Đấu Sĩ | Rìu, cận chiến | Đồng minh +10% tốc độ đánh | Rìu Xoáy Cuồng Nộ: xoáy rìu 110 sát thương r2 |
| archer | Cung Thủ Tinh Anh | Xạ Thủ | Cung, tầm 160 | Đồng minh +8% sát thương | Mưa Tên: 3 đợt × 40 sát thương, vùng r2,5 tầm 8 ô |
| mage | Pháp Sư Cung Đình | Pháp Sư | Tia phép, tầm 160 | Đồng minh hồi 1,2 HP/s | Thiên Thạch Ma Thuật: 120 sát thương r2,5 tại một điểm |
| paladin | Thánh Kỵ Sĩ | Hỗ Trợ | Búa, cận chiến | Đồng minh +3 giáp phẳng | Thánh Quang Hồi Phục: hồi 160 HP + giải hiệu ứng xấu, đồng minh r3 |
| dragoon | Kỵ Sĩ Long | Cơ Động | Thương, cận chiến dài | Đồng minh +10% tốc độ di chuyển | Long Thương Xuyên Tâm: lao thẳng 5 ô, 120 sát thương mọi địch trên đường |
| assassin | Sát Thủ Bóng Đêm | Sát Thủ | Song kiếm, cận chiến nhanh | Đồng minh +10% sát thương lên tướng địch | Dịch chuyển sau lưng địch (tầm 6 ô), 160 sát thương |
| ranger | Nhà Thám Hiểm | Thám Hiểm | Kiếm, cận chiến nhanh | Đồng minh +1 ô tầm nhìn | Kiếm vũ: 5 nhát × 32 sát thương quanh mình r2 |

## 5. Ghi chú art (cho đợt nối dây + kiểm chứng)

- Sprite theo đúng khuôn roster hiện tại: cao 92px, đầu to ~0,47 chiều cao,
  palette ~52 màu, alpha nhị phân (0 pixel bán trong suốt) — xem
  `tools/build_hero_assets3.py` + `tools/build_hero_rig3.py`.
- **Luật hướng lưng áp nguyên văn:** ở 3 hướng lưng (ne/n/nw) KHÔNG vẽ vũ khí
  (weapon rỗng trong rig) cho cả 8 tướng mới; khiên của Knight/Paladin là một
  phần thân (đeo trên tay) nên vẫn thấy ở mép thân như trang bị — vũ khí cầm
  tay (kiếm/búa/thương...) thì biến mất hẳn.
- Chân dung Collection + avatar vuông cắt trực tiếp từ chân dung trên bảng của
  Tín (không vẽ lại): `assets/avatars/avatar_sq_<id>.png` +
  `assets/avatars/king_avatar_<id>.png`.
- Hai điểm đọc-ảnh cần Tín biết: Paladin cầm **búa chiến vàng** (không phải
  kiếm như nhãn vai trò gợi ý) và Ranger cầm **kiếm dài** (Tín kiểm chứng:
  kiếm sĩ cơ động, không phải súng) — thiết kế đi theo pixel thật của bảng.
