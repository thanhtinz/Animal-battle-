# Đặc tả: ĐẠI CHIẾN LIÊN MINH — Giải liên minh hằng tháng 8 vs 8 (Empire Age)

_Soạn 2026-11-12 theo lệnh Tín: "đấu theo liên minh mỗi tuần, sẽ đấu
theo liên minh với nhau một map" + đính chính cùng ngày: **8 người mỗi
liên minh, tổng 16 người/trận** ("có 8 nhân vật thôi nên tổng 16
người là được") + **hai phe phân biệt bằng đúng hai màu Đỏ vs Xanh**.
Đây là tài liệu NGHIÊN CỨU + THIẾT KẾ — chưa xây. Mọi con số ghi
"mặc định" đều là đề xuất của Bé, chờ Tín chốt ở §11. Các khẳng định
kỹ thuật đều bám code thật (§0); chỗ nào là ước lượng thì ghi rõ là
ước lượng._

_Bản sửa đổi 2 — 2026-11-12, theo lệnh Tín: "làm cái kiểu như đấu
giải ấy, team nào đấu team nào, xong team nào thua rồi đi tiếp,
làm luôn cái bảng đó để mọi người xem ở sảnh chính." Hai thay đổi
lớn so với bản đầu: (1) giải tuần không còn là một trận ghép cặp
duy nhất mà là **giải loại trực tiếp có bảng đấu** — thua bị loại,
thắng đi tiếp tới chung kết (§1, §6, §7); (2) thêm mục mới **§10:
Bảng đấu công khai ở sảnh chính** để mọi người theo dõi toàn giải.
Mục Điểm chờ Tín chốt theo đó chuyển thành §11._

_Bản sửa đổi 3 — 2026-11-12, theo lệnh Tín: "Tôi nghĩ 1 tháng 1
lần hợp hơn" + hai bổ sung cùng ngày. Ba thay đổi: (1) **nhịp
giải đổi từ hằng tuần sang HẰNG THÁNG** — một giải mỗi tháng,
mỗi tuần một vòng, chung kết Thứ Bảy cuối tháng (§1, §6, §10,
§11.4); các câu "đại chiến mỗi tuần" ở bản trước hết hiệu lực
(riêng hệ điểm tuần của 17a/17b KHÔNG đổi — trận đại chiến vẫn
cộng điểm tuần trong đúng tuần diễn ra trận, §7). (2) Thêm
**danh hiệu <Liên minh vô địch>** hiện cạnh tên trong chat cho
thành viên liên minh vô địch tháng (§7.1). (3) Thêm hệ **mỹ
phẩm: khung avatar + bong bóng chat** (§7.2)._

## 0. Căn cứ nghiên cứu (trạng thái thật của game hôm nay)

| Hạng mục | Hiện trạng thật (file) |
|---|---|
| Cỡ trận | Custom 2–4 người (`server/hub.go`: `MaxPlayersPerRoom = 4`); hàng đợi Thường/Hạng gom **8 người đấu tự do** (`server/matchmaking.go`: `QueueMatchSize = 8`). Chưa từng có trận > 8 người. |
| Bản đồ | **64×64 ô**, ô 32px (`godot/scripts/world.gd`: `MAP_W/MAP_H = 64`, `TILE = 32`); nền bake 3072×3072px (48px/ô). Điểm spawn: 2–4 căn cứ ở góc; bản đồ 8 người (chỉ layout plains) thêm 4 điểm giữa cạnh thành vòng 8 (`world.gd` đoạn 13z). 6 layout: plains/river/islands/valley/arena/coast. |
| Mô hình đội | Sim đã có khái niệm **slot → faction team** (`main.gd`: `slot_teams`, `team_of_slot()`); trận 2v2 là 2 slot chung 1 team. Sương mù tính **theo team** (`fog.gd`: `local_team`, `_reveals()` theo team) — đồng đội cùng team **đã nhìn chung tầm nhìn**. |
| Tài nguyên MP | **Ví riêng từng slot**: `main.gd` mảng `mp_wallets[slot]`, khởi điểm mỗi người 200 Thực phẩm / 200 Gỗ / 100 Vàng / 0 Đá / 0 Sắt. Mọi lệnh trừ tiền (huấn luyện, xây, lên đời, nghiên cứu) đều trừ từ ví của slot ra lệnh. SP dùng một ví `resources` duy nhất. |
| Dân số | Trần dân số **theo chủ sở hữu** trong MP (`owner_pop_cap(owner)` = tổng `pop` của công trình của owner đó: Town Center +5, Nhà +5/nhà — `main.gd` BUILDING_DEFS). Không có trần cứng toàn trận ngoài nhà ở. |
| Điều kiện loại/thắng | Một slot bị loại khi **TC sập + bị quét sạch** (không còn Dân hoặc không còn công trình huấn luyện) — `_mp_evaluate_elimination()` / `_slot_annihilated()`. Trận kết thúc khi **chỉ còn một team sống** (`_mp_check_winner()` đếm `alive_teams`) — luật thắng theo team **đã có sẵn** từ 2v2. |
| Nhân vật chính | Đúng **8 tướng**; mỗi người chơi tối đa **1 tướng sống cùng lúc**, huấn luyện ở Castle đời IV, giá 500 Thực phẩm + 300 Vàng (ví người đó), bộ kỹ năng = hào quang thụ động + 1 chiêu chủ động (hồi chiêu chung 75s). Server gán tướng khi mở trận: rút từ **nhóm tướng người chơi sở hữu** (`hub.go`: `Player.Char` do server rút ở `startMatchLocked`). Tướng **không nhuộm màu đội** bao giờ; tên trên đầu tướng = tên người chơi. |
| Lockstep | Server tick **10/giây** (`hub.go`: `TickInterval = 100ms`, `InputDelayTicks = 2`); client gửi lệnh, server đóng dấu tick thi hành; **checksum mỗi 30 tick**; lệch checksum → resync bằng snapshot toàn trạng thái từ client thuộc phe đa số (`net.gd` đầu file; `hub.go`: `ChecksumKeepTicks = 3000`). Snapshot là bản ghi JSON từng unit/công trình (`main.gd`: `_mp_unit_record()` — khoảng 20 trường/unit) nên **kích thước snapshot tỉ lệ thẳng với số unit**. |
| Trọng tài | Trận Hạng có **một tiến trình Godot headless riêng/trận** làm trọng tài, server chỉ tin kết quả trọng tài báo (`server/referee.go`, timeout cứng 45 phút/trận). Custom/Thường tin báo cáo của host. |
| Mất kết nối | Slot mất kết nối được **30 giây ân hạn** (300 tick) do trọng tài theo dõi (`main.gd`: `_referee_grace_deadline`), quá hạn thì bị loại; vào lại giữa trận bằng snapshot (đường observer vào giữa trận 15a đã chứng minh cơ chế nạp snapshot hoạt động). |
| Xem lại | Server ghi mọi trận (luồng lệnh + cấu hình), giữ **200 trận gần nhất** kiểu LRU (`server/replays.go`: `ReplayCap = 200`); phòng đợi có mã xem lại. |
| Người xem | Phòng Custom tối đa **8 observer/phòng**, có tuỳ chọn trễ 0/60/120 giây (15a/15e). |
| Liên minh (17a/17b) | Tối đa **30 thành viên**; vai trò Hội trưởng (1) / Phó (tối đa 3) / Thành viên; đóng góp tuần qua hook ghi trận của server (`accounts.go`: `MatchHook`/`MatchFeed`, XP trận = 10 đấu / +20 thắng → đóng góp +10/+30); điểm tuần = tổng đóng góp + điểm thưởng nhiệm vụ tuần (17b: 3 nhiệm vụ 40 trận/15 thắng/5 thắng hạng, thưởng +30/+40/+50 điểm tuần); **vương miện Vô địch tuần** chốt lúc reset thứ Hai 00:00 theo thứ tự điểm tuần → XP tổng → tên (`alliance.go`: `weekPoints()`, `AllianceChamp`); liên minh có cấp + XP (ngưỡng 250·L·(L−1)), [TAG] duy nhất, chat liên minh lưu 50 tin. |
| Ngoại giao | Chỉ tồn tại trong phòng Custom bật cờ; hàng đợi **từ chối cấu trúc**. |
| Điểm trận | Công thức điểm cá nhân duy nhất `Main.match_score_of(slot)` = thu thập÷10 + 20×quân + 15×công trình + 40×cấp công nghệ + 100 nếu tướng còn sống — dùng cho panel Thống kê, màn kết quả AOV, tie-break. |

## 1. Tổng quan + vòng đời tháng

**Đại Chiến Liên Minh** là **giải đấu loại trực tiếp giữa các
liên minh**, chạy **mỗi tháng một giải**: mỗi bên cử **8 thành
viên** vào **một bản đồ chung**, 8 người cùng phe **dùng chung
một quỹ tài nguyên** và đánh chung một phe Đỏ hoặc Xanh. Hai
liên minh gặp nhau trong một cặp đấu của bảng: **thắng thì đi
tiếp vòng sau, thua bị loại ngay** — cứ thế tới chung kết và nhà
vô địch tháng. Toàn bộ bảng đấu hiện công khai ở sảnh chính cho
mọi người xem (§10). Đây là sự kiện lớn nhất của tháng — không
phải chế độ bấm là đấu ngay như Đấu Thường/Hạng. Nhịp tháng là
chủ đích: mỗi vòng cách nhau một tuần để hai phe có thời gian
chuẩn bị, do thám đối thủ (xem lại các trận vòng trước của họ)
và sắp xếp người — đại chiến là chuyện của cả liên minh trong
suốt một tháng, không phải một tối.

Vòng đời một tháng (mọi mốc giờ là **mặc định — chờ chốt
§11.4**; giờ tính theo giờ server). Nguyên tắc lịch: **đăng ký
đầu tháng, mỗi tuần một vòng, chung kết luôn là Thứ Bảy cuối
tháng 20:00** — các vòng trước lùi dần về các Thứ Bảy trước đó,
nên giải ít đội thì bắt đầu muộn hơn và vòng cuối luôn giữ đúng
khung giờ vàng:

| Giai đoạn | Thời gian (mặc định) | Việc xảy ra |
|---|---|---|
| Mở đăng ký | Ngày 1 của tháng, 00:00 | Hội trưởng/Phó bật "Tham chiến tháng này" ở tab Đại chiến + chốt **danh sách tham chiến tháng** (tối đa 14 người, xem §2); liên minh vào danh sách dự giải. |
| Đóng đăng ký + chốt danh sách | Ngày 4, 12:00 | Danh sách tham chiến **khoá cứng cho cả tháng** (§2); server xếp hạt giống theo Điểm Đại Chiến (§6) và **lập bảng đấu**; số suất tối đa 16, tối thiểu 4 mới mở giải (§11.12). |
| Công bố bảng đấu | Ngày 4, 13:00 | Bảng đấu lên **sảnh chính** (§10) + tab Đại chiến của từng liên minh + thư vào Hòm thư của các thành viên trong danh sách tham chiến: ai đấu ai, ngày nào, phe Đỏ/Xanh từng cặp. |
| Các vòng đấu | 20:00 các Thứ Bảy theo cỡ bảng (bảng dưới) | Mỗi vòng: các cặp đấu đồng loạt một trận 8v8 theo luật §3–§5; đội hình được **chọn lại trước mỗi vòng** từ danh sách tham chiến tháng, hạn chốt 18:00 ngày đấu (§2). Giữa hai vòng là **một tuần chuẩn bị** (hệ quả ở đoạn dưới bảng). Thắng đi tiếp, thua bị loại; kết quả cập nhật lên bảng đấu ngay khi trọng tài báo. |
| Chung kết | **Thứ Bảy cuối cùng của tháng, 20:00** (mặc định) | Cặp cuối cùng tranh vô địch tháng; kết thúc là trao thưởng hạng (§7) và **trao danh hiệu <Liên minh vô địch>** (§7.1) — điểm thưởng cộng vào điểm tuần của đúng tuần diễn ra chung kết (§7, ghi chú ranh giới hai hệ). |
| Vinh danh + khép tháng | Ngay khi chung kết kết thúc → ngày 1 tháng sau | Nhà vô địch lên ô vô địch của bảng đấu (§10) và giữ ngôi tới chung kết tháng sau; bảng tháng đã khép vẫn xem được ở sảnh trong suốt quãng nghỉ (§10.2); ngày 1 tháng sau mở đăng ký giải mới. |

Lịch vòng theo cỡ bảng (**mặc định — §11.4**; mọi vòng đều bắt
đầu **Thứ Bảy 20:00**, trận tối đa 45 phút theo §4; "T−n" = Thứ
Bảy thứ n tính ngược từ chung kết):

| Số liên minh dự giải | Các vòng | Ngày đấu |
|---|---|---|
| 4 | Bán kết → Chung kết | T−1 → Thứ Bảy cuối tháng |
| 5–8 | Tứ kết → Bán kết → Chung kết | T−2 → T−1 → Thứ Bảy cuối tháng |
| 9–16 | Vòng 16 → Tứ kết → Bán kết → Chung kết | T−3 → T−2 → T−1 → Thứ Bảy cuối tháng |

Trường hợp tháng ngắn khiến ngày Thứ Bảy tính được của vòng đầu
rơi vào hoặc trước ngày công bố bảng (ngày 4): vòng đầu dời sang
**Thứ Tư 20:00** ngay sau ngày công bố đó (mặc định — trường hợp
hiếm, chỉ xảy ra với bảng 16 ở tháng mà Thứ Bảy đầu tiên rơi
vào ngày 1–4).

Số dự giải không phải lũy thừa của 2: các hạt giống cao nhất
nhận **bye** (đi thẳng vòng sau, không đấu vòng đầu) để bảng về
đúng lũy thừa của 2 — theo đúng tiền lệ bye cho hạt giống cao của
hệ giải đấu 15h (chi tiết §6).

**Hệ quả của nhịp tháng (ghi thẳng để khỏi bất ngờ)**: giữa
hai vòng có một tuần — đủ để xem lại replay các trận của đối
thủ sắp gặp (replay đã có sẵn), tập giao hữu nội bộ, và để **dự
bị thật sự có giá trị**: người bận một Thứ Bảy không làm hỏng
cả giải của liên minh, chỉ mất vòng đó. Đổi lại, phong độ và
nhân sự có thể trồi sụt giữa các vòng (người nghỉ game giữa
tháng, người mới lên tay) — đó là tính chất của giải tháng,
chấp nhận theo thiết kế. Danh sách tham chiến khoá cả tháng
(§2) là cái neo giữ giải công bằng trong nhịp dài này: không
ai "nhảy vào" giữa giải được.

Một liên minh đấu số trận ghi điểm bằng số vòng mình đi được
(thua vòng đầu = 1 trận; vô địch bảng 8 = 3 trận; bảng 16 = 4
trận) — mọi trận đều tính ĐĐC và thưởng theo §7. Ngoài khung
giải, hai liên minh vẫn có thể đấu **giao hữu** kiểu phòng hẹn
(Phase 1) — không tính điểm, không lên bảng.

## 2. Đội hình ra trận

- **Danh sách tham chiến tháng (tối đa 14 người)**, chọn từ danh
  sách 30 thành viên, chốt cùng lúc đăng ký (hạn cuối ngày 4,
  12:00 khi đóng đăng ký, §1) và **khoá cứng cho cả tháng**: hết
  hạn chốt là không thêm/bớt được ai cho tới giải tháng sau —
  thành viên mới gia nhập liên minh giữa tháng (kể cả đủ điều
  kiện 48 giờ ở mục dưới) cũng phải chờ tới tháng sau mới vào
  được danh sách. Người chọn: **Hội trưởng hoặc Phó** (đúng ma
  trận quyền 17a: việc "tổ chức" thuộc Hội trưởng/Phó). Thành
  viên tự đánh dấu "Tháng này tôi tham chiến được" (cờ sẵn sàng)
  để Hội trưởng/Phó xếp danh sách có căn cứ — cờ này chỉ là
  thông tin, không tự vào danh sách.
- **Đội hình từng vòng (8 chính thức + tối đa 4 dự bị)** được chọn
  lại từ danh sách tham chiến trước **mỗi vòng đấu** — liên minh
  bị loại thì dừng, liên minh đi tiếp được đổi người/tướng giữa
  các vòng cho hợp lịch của thành viên. Hạn chốt đội hình một
  vòng: **18:00 ngày đấu vòng đó** (mặc định); quá hạn mà chưa
  chốt, server dùng nguyên đội hình vòng trước (vòng đầu: 8 người
  đầu danh sách tham chiến theo thứ tự Hội trưởng/Phó đã xếp).
- **Điều kiện đăng ký liên minh**: có ít nhất **10 thành viên**
  (đủ lập danh sách tham chiến tối thiểu: 8 chính thức + 2 dự bị)
  — **mặc định, §11.5**. Liên minh
  dưới 10 người chưa đăng ký được; tab Đại chiến hiện rõ còn thiếu
  bao nhiêu người.
- **Điều kiện thành viên ra trận**: là thành viên liên minh **ít
  nhất 48 giờ** tính đến giờ chốt danh sách tham chiến tháng (**mặc định, §11.9** —
  chống "thuê lính đánh thuê" nhảy vào liên minh chỉ để đấu đại
  chiến rồi rời đi). Phải có tài khoản (khách không vào được, như
  mọi tính năng liên minh).
- **Phân tướng cho đội hình** (điểm riêng của thể thức 8 người — xem
  §5.2): mỗi vị trí chính thức gắn **một tướng chỉ định** từ nhóm
  tướng người đó sở hữu; **8 tướng trong một phe không trùng nhau**.
  Hội trưởng/Phó sắp xếp ở màn đội hình **cho từng vòng** (cùng
  lúc chọn lại đội hình vòng đó); xung đột (hai người cùng chọn
  một tướng) giải theo thứ tự: ưu tiên người chọn trước, Hội
  trưởng/Phó kéo đổi; khi chốt đội hình một vòng mà vẫn thiếu
  tướng riêng cho ai đó, server tự gán tướng còn trống trong nhóm
  người đó sở hữu (theo đúng cơ chế rút tướng hiện có ở
  `startMatchLocked`).
- **Vắng mặt lúc điểm danh** — luật này áp cho **mọi vòng đấu**
  (cửa sổ điểm danh 10 phút trước giờ đấu từng vòng — mặc định):
  1. Người chính thức không vào phòng chờ → **dự bị vào thay tự
     động** theo thứ tự dự bị đã chốt, nếu dự bị đang trực tuyến và
     bấm "Vào thay". Tướng của người thay: lấy tướng chỉ định của
     chính họ nếu không trùng phe, trùng thì server gán tướng còn
     trống họ sở hữu.
  2. Hết dự bị mà vẫn thiếu: phe đấu **thiếu người** (7v8, 6v8 vẫn
     đấu — căn cứ/dân/tướng của slot vắng **không được tạo**, quỹ
     chung không đổi; xem cân bằng ở §3.5).
  3. Một phe có **dưới 6 người** lúc hết giờ điểm danh của một
     vòng → **xử thua vòng đó** (forfeit): bị loại khỏi giải, phe
     kia **đi tiếp vòng sau mà không cần đấu** (thắng vòng kiểu
     walkover); ĐĐC và thưởng tính như thắng một trận (§6/§7)
     nhưng **không** tính chỉ số cá nhân/MVP. Ngưỡng 6 là **mặc
     định, §11.5**.
  4. Cả hai phe cùng dưới 6 → **cả hai bị loại khỏi giải**, cặp
     đấu ghi "Huỷ — hai bên vắng" trên bảng đấu, không điểm cho
     cả hai.
  5. Hệ quả bảng đấu của mục 4: phe thắng cặp đấu **kề bên** (cặp
     sẽ gặp phe thắng của cặp bị huỷ ở vòng sau) nhận **bye** ở
     vòng sau đó — đi tiếp thêm một vòng không cần đấu; nếu vòng
     sau đó chính là chung kết thì phe ấy lên ngôi vô địch theo
     diện walkover (vẫn nhận thưởng vô địch §7, không tính chỉ số
     trận). Riêng trường hợp cả hai phe của **chung kết** cùng bị
     loại theo mục 4: tháng đó **không có nhà vô địch** — không
     trao thưởng vô địch/á quân của tháng; các liên minh dừng ở
     bán kết giữ nguyên thưởng hạng của mình.
- **Rời trận giữa chừng**: xử như luật mất kết nối hiện hành — 30
  giây ân hạn để vào lại bằng snapshot; quá hạn slot đó bị loại
  theo luật thường (căn cứ của họ thành "inert" — còn đứng đó
  nhưng không ai điều khiển được; **không** chuyển quyền điều khiển
  căn cứ cho đồng đội — đó là thay đổi sim lớn, để ngỏ ngoài phạm
  vi bản này). Người bỏ trận giữa chừng bị trừ uy tín theo luật
  Đấu Hạng hiện có nếu trận là trận ghi điểm (đề xuất áp cùng mức
  −5, mặc định).

## 3. Kinh tế chung — trái tim của thể thức

### 3.1 Mô hình: một quỹ cho cả phe

Mỗi phe có **MỘT ví chung duy nhất** cho 5 loại tài nguyên (Thực
phẩm/Gỗ/Vàng/Đá/Sắt). Thay đổi sim cốt lõi: `mp_wallets` hiện là
mảng theo slot (`main.gd`) — chế độ đại chiến đổi khóa truy cập ví
từ **slot → phe**: một hàm `wallet_of(slot)` trả về ví của phe khi
đang ở chế độ đại chiến, trả ví slot ở mọi chế độ khác. Mọi điểm
trừ/cộng tiền trong sim (huấn luyện, xây dựng, sửa chữa, lên đời,
nghiên cứu, chở hàng giao thương...) đã đi qua các hàm ví tập trung
nên đây là thay đổi có kiểm soát — nhưng là thay đổi **chạm vào mọi
lệnh kinh tế**, phải có bộ test hồi quy riêng cho cả hai đường ví.

- Dân của bất kỳ ai **nộp tài nguyên vào bất kỳ công trình nộp nào
  của phe** (TC của mình, TC đồng đội, kho của đồng đội...) → cộng
  vào **quỹ chung**. (Đường nộp hiện tính theo team ở
  `get_dropoff_for(u.team, ...)` — đã sẵn khái niệm nộp theo team.)
- **Ai được tiêu**: mọi thành viên trong phe đều tiêu được từ quỹ
  chung cho **căn cứ và quân của chính mình** (xây nhà, huấn luyện
  quân ở trại của mình, sửa công trình của mình). Không ai tiêu
  được "hộ" căn cứ người khác: lệnh xây/huấn luyện vẫn xuất phát từ
  công trình của chính người ra lệnh — quỹ chung chỉ là nguồn tiền
  chung, quyền điều khiển không đổi.
- **Mua sắm cấp phe** (lên đời, nghiên cứu công nghệ, sửa Thành
  trì Liên minh §4): bất kỳ thành viên nào cũng khởi xướng được
  bằng quỹ chung (lý do: khoá theo Hội trưởng sẽ chết trận khi
  người đó vắng/rớt mạng — xem §3.4); **ai khởi xướng được ghi vào
  nhật ký chi tiêu** (§3.3).

### 3.2 Số khởi điểm + dòng tiền

- Quỹ khởi điểm của phe = **tổng khởi điểm của 8 người như hôm nay:
  1600 Thực phẩm / 1600 Gỗ / 800 Vàng / 0 Đá / 0 Sắt** (**mặc định,
  §11.2**) — giữ đúng tổng lượng tiền một phe 8 người hôm nay cầm,
  chỉ khác là gộp một túi. Tốc độ thu về của 8 người chơi thật sẽ
  cao hơn một người khoảng 4–6 lần thực tế (không phải 8 lần: còn
  chia người đi quân, đi thủ), nên:
- **Lên đời và nghiên cứu công nghệ tính theo PHE** (một lần cho cả
  8 người — xem §5.1) với **chi phí ×3** so với giá một người hôm
  nay (**mặc định, §11.3**). Giá huấn luyện quân/xây nhà giữ nguyên
  từng đơn vị — vì sản lượng quân cũng nhân theo số người và bị
  chặn bởi trần dân số (§5.3), không cần nhân giá.

### 3.3 Minh bạch chống phá quỹ (anti-grief)

Quỹ chung có rủi ro thật: một người nóng nảy/ác ý có thể xả quỹ
(huấn luyện ồ ạt, xây vô tội vạ) làm cả phe trắng túi. Bản này
**không** dùng trần chi cứng (dễ chặn nhầm chiến thuật dồn lực
hợp lệ — ví dụ dồn tiền cho một người lên tướng sớm là chiến thuật
thật). Thay vào đó là **minh bạch toàn phần**:

- **Sổ chi tiêu trực tiếp**: mọi khoản chi từ quỹ ≥ một ngưỡng nhỏ
  (mặc định: mọi khoản chi) hiện dòng ngắn ở kênh chat phe ("An:
  huấn luyện Kỵ binh −80 TP −40 V") — dùng lại hạ tầng chat phe,
  không vào checksum (sự kiện trình diễn suy ra từ lệnh đã áp, như
  thông báo xe hàng 15g).
- **Số liệu góp/chi từng người** chạy trong sim (bộ đếm theo slot:
  `gathered` đã có sẵn cho công thức điểm; bổ sung `spent` theo 4
  nhóm: Quân / Kinh tế / Công nghệ+Lên đời / Công trình): hiện ở
  panel Đội trong trận (cột Góp · Chi) và ở màn kết quả (§9). Số
  này cũng là đầu vào tính **MVP phe** (§7).
- **Sau trận**: Hội trưởng/Phó xem lại bảng góp/chi đầy đủ ở lịch
  sử đại chiến; xử lý nội bộ (nhắc nhở, giáng quyền ra trận các
  giải sau) thuộc về liên minh — game chỉ cung cấp số thật.
- Người chơi **mới vào phe giữa trận là không thể** (đội hình đã
  khoá) nên không có kịch bản người lạ phá quỹ.

### 3.4 Vì sao không khoá quyền tiêu theo vai trò trong trận

Vai trò Hội trưởng/Phó là vai trò **ngoài trận**; trong trận, người
giữ vai trò đó có thể rớt mạng/vắng (dự bị thay) — nếu quyền lên
đời/nghiên cứu gắn với họ, cả phe bị khoá tiến độ. Mọi thành viên
đều là người liên minh đã chọn vào đội hình; sổ chi tiêu (§3.3) là
lớp bảo vệ đủ cho Phase 1–2. Nếu playtest cho thấy cần, Phase 3 có
thể thêm tuỳ chọn phòng "Chỉ người được uỷ quyền mới lên
đời/nghiên cứu" — ghi nhận là điểm mở, không xây trước.

### 3.5 Cân bằng khi thiếu người

Phe thiếu người (7v8, 6v8) **không** được bù tiền mặt (bù tiền sẽ
tạo động cơ "cố tình vắng người yếu"). Bù duy nhất là cấu trúc:
slot vắng không tồn tại nên phe thiếu **ít miệng ăn dân số hơn**
nhưng cũng ít căn cứ phải thủ hơn trên cùng một vùng đất. Đây là
bất lợi thật — chấp nhận được vì xử thua chỉ xảy ra dưới 6 người,
và vắng là lỗi của phe đó. Ghi nhận là **điểm chờ chốt §11.5** nếu
Tín muốn cơ chế bù khác.

### 3.6 Phương án thay thế: lai (quỹ chung + túi riêng nhỏ)

| | **Chung toàn phần** (đề xuất) | **Lai**: 70% nộp vào quỹ chung, 30% vào túi riêng; túi riêng chỉ tiêu cho quân/căn cứ của mình, quỹ chung cho lên đời/công nghệ/công trình chung + hỗ trợ |
|---|---|---|
| Đúng tinh thần "chia tài sản, đánh chung" | Trọn vẹn | Một nửa — vẫn còn "tiền của tôi" |
| Chiến thuật dồn lực (dồn cho 1 người lên đời/tướng) | Tự nhiên | Bị chặn một phần bởi túi riêng |
| Rủi ro phá quỹ | Có — chặn bằng minh bạch §3.3 | Thấp hơn (chỉ phá được quỹ chung 70%) |
| Độ phức tạp sim/UI | Thấp: 1 ví/phe, HUD một hàng số | Cao: 2 ví, mọi lệnh phải biết trừ túi nào, HUD hai hàng số, người chơi phải học luật trừ tiền |
| Cảm giác đồng đội | Mạnh nhất — đúng chất đại chiến | Trung bình |

**Đề xuất: chung toàn phần** (§3.1–3.5). Phương án lai giữ làm dự
phòng nếu playtest Phase 1 cho thấy phá quỹ là vấn đề thật chứ
không phải lo xa.

### 3.7 HUD kinh tế trong trận (tóm tắt — chi tiết §9)

Thanh tài nguyên trên cùng hiện **quỹ của phe** (5 số) thay cho ví
cá nhân; ngay dưới là dòng nhỏ "Bạn đã góp: X · Đã chi: Y" của
chính người chơi; bấm vào cụm tài nguyên mở panel Đội 8 hàng có
Góp/Chi từng người. Không còn chỗ nào hiện "tiền của tôi" vì không
còn khái niệm đó trong trận đại chiến.

## 4. Bản đồ + điều kiện thắng

### 4.1 Cỡ bản đồ: đề xuất 128×128

Bản đồ 64×64 hôm nay chứa 8 căn cứ dạng vòng đã chật: khoảng cách
giữa hai căn cứ kề nhau chỉ ~25–30 ô, một căn cứ phát triển đầy đủ
(TC + nhà dân + trại + ruộng + kho) cần vùng ~16×20 ô. Đặt 16 căn
cứ vào 64×64 → mỗi căn cứ ~256 ô² đất (16×16) — **không đủ chỗ xây
một căn cứ hoàn chỉnh**, hai phe không có đất trung lập ở giữa.

**128×128 = 4 lần diện tích** (16.384 ô): mỗi căn cứ ~1.024 ô² —
đủ một căn cứ đầy đủ + đất dự trữ phía sau; giữa hai phe còn dải
trung lập rộng ~30–40 ô cho giao tranh và mỏ tranh chấp. Hệ quả kỹ
thuật phải tính trước (chi tiết §8): ảnh nền bake tăng từ 3072² lên
6144² (bộ nhớ ảnh ×4), hai lưới A* (đất + nước) tăng từ 4.096 lên
16.384 ô mỗi lưới — cả hai đều trong tầm Godot xử lý, nhưng bake
6144² là điểm phải benchmark trên máy yếu (phương án dự phòng: bake
32px/ô cho bản đồ đại chiến → ảnh 4096², mờ hơn một chút khi zoom).

Layout đại chiến là **layout mới riêng** (đề xuất id `war`, họ
plains — theo tiền lệ hàng đợi chỉ dùng plains): đối xứng gương
qua tâm bản đồ để công bằng tuyệt đối theo cặp điểm:

- **Hai vùng nhà**: Tây (Đỏ) và Đông (Xanh) — hoặc chéo Tây-Bắc /
  Đông-Nam; chốt một kiểu khi làm bản đồ thật. Mỗi vùng: **8 căn cứ
  xếp 2 vòng cung**: 3 căn cứ tuyến đầu (gần trung tuyến), 3 căn cứ
  tuyến giữa, 2 căn cứ tuyến sau bảo vệ **Thành trì Liên minh**
  (§4.2) đặt ở góc sâu nhất của vùng.
- **Mỗi căn cứ** có sẵn quanh mình: rừng gỗ, bãi quả/thú, mỏ vàng
  nhỏ — đúng mật độ khởi điểm của một căn cứ hôm nay.
- **Dải trung lập ở giữa**: 2 mỏ vàng lớn + 2 mỏ đá lớn (tài nguyên
  tranh chấp — lí do phải đánh ra giữa), thú trung lập như thường,
  đất trống rộng cho trận địa. Không có nước cắt ngang ở Phase 1
  (đường bộ thông suốt — tàu thuyền để sau, như bản đồ hàng đợi
  hôm nay là đất liền).

### 4.2 Điều kiện thắng: phân tích 3 phương án

(a) **Quét sạch cả 8 căn cứ địch** — dùng nguyên luật loại từng
slot + "còn một team sống" đã có. Vấn đề: với 8 căn cứ/phe, người
bị phá căn cứ đầu tiên phải ngồi xem 40+ phút; cuối trận thường là
đuổi bắt 1–2 căn cứ trốn góc — trận dễ kéo 60–90 phút, vỡ khung
thời lượng một vòng đấu và timeout trọng tài 45 phút hiện có.

(b) **Phá Thành trì Liên minh (Alliance Citadel)** — mỗi phe có
**một công trình chung** đặt sẵn ở tuyến sau: HP lớn (mặc định
4.000 — gấp ~3,3 lần TC 1.200), có tháp bắn tự vệ tương đương tháp
canh, là **điểm nộp tài nguyên chung** và là nơi nghiên cứu/lên
đời của phe (§5.1). Phá được Thành trì địch = **thắng ngay**, bất
kể còn bao nhiêu căn cứ. Căn cứ cá nhân vẫn bị phá bình thường
(người mất TC + bị quét sạch vẫn bị loại khỏi trận như luật cũ) —
nhưng trận có một **trọng tâm duy nhất** để công và thủ, nhịp trận
gọn, mục tiêu rõ cho cả 8 người phối hợp. Thành trì sửa được bằng
Dân của bất kỳ ai trong phe (trừ quỹ chung); không xây lại được
khi đã sập.

(c) **Tính điểm khi hết giờ** — hết 45 phút, phe nào tổng điểm
(`match_score_of` cộng cả 8 slot) cao hơn thì thắng. Vấn đề nếu
dùng làm luật chính: khuyến khích thủ nhà câu giờ. Nhưng rất hợp
làm **luật chốt hạ** khi hết giờ mà chưa bên nào phá được Thành
trì.

**Đề xuất: (b) làm luật thắng chính + (c) làm chốt hạ hết giờ +
đầu hàng theo phe (§4.3).** Thời lượng mục tiêu: **35–50 phút**,
trần cứng 45 phút tính điểm (mặc định, §11.1) — khớp timeout trọng
tài 45 phút hiện có, không phải nới hạ tầng.

### 4.3 Đầu hàng theo phe

Một cá nhân đầu hàng chỉ loại chính họ (như hôm nay). **Đầu hàng
cả phe**: bất kỳ thành viên nào trong phe cũng mở được biểu quyết
đầu hàng trong panel Đội; cần **≥5/8 phiếu thuận** (theo số người
còn đang trong trận của phe) thì cả phe đầu hàng — đối thủ thắng.
Biểu quyết tối đa 2 lần/trận/phe (chống spam). Mặc định — §11.1.

## 5. Luật chơi trong trận

### 5.1 Đời + công nghệ: tính theo phe

- **Đời là của phe**: cả phe cùng một đời tại mọi thời điểm (sim
  đã có mầm `team_age` theo team trong `main.gd`). Lên đời thực
  hiện tại Thành trì Liên minh, bất kỳ ai khởi xướng, trừ quỹ
  chung theo giá §3.2. Hệ quả chiến thuật: không còn cảnh một
  người đời IV gánh bảy người đời I — phe phải bàn nhau thời điểm
  dồn tiền lên đời. Đây là thay đổi lớn nhất về cảm giác chơi so
  với 2v2 hôm nay (đời vẫn theo từng slot trong 2v2 — **chỉ chế độ
  đại chiến mới gộp đời theo phe**, các chế độ khác giữ nguyên).
- **Công nghệ cũng theo phe**: nghiên cứu tại bất kỳ công trình
  đúng loại nào của phe (nghiên cứu ở Trại lính của đồng đội vẫn
  tính cho cả phe), hiệu ứng áp toàn phe — đúng nguyên tắc GDD
  Công nghệ "hiệu ứng toàn đế chế", ở đây "đế chế" = phe. Một công
  nghệ chỉ nghiên cứu một lần cho cả phe (hàng chờ theo công trình
  như hiện nay, nhưng sổ công nghệ là sổ của phe — `mp_techs` đổi
  khóa slot → phe cùng cách với ví §3.1).
- Luật 1 Trại lính huấn luyện mọi loại quân, cây công nghệ 18
  dòng/35 công nghệ, bỏ nhóm Tôn giáo — giữ nguyên như hiện hành.

### 5.2 Nhân vật chính: 8 người — 8 tướng

Thể thức này là nơi duy nhất trong game một phe có thể ra sân
**đủ bộ 8 tướng cùng lúc** — đó cũng là lí do Tín chốt 8 người/phe.

- **Trong một phe: không trùng tướng** (luật phân tướng ở §2).
  Tám tướng khác nhau = tám hào quang khác nhau phủ lên quân đội
  chung — hào quang vốn tác động theo team nên tự nhiên cộng hưởng
  trong đội hình lớn.
- **Giữa hai phe: được trùng tướng** (Đỏ có Hiệp Sĩ thì Xanh cũng
  có thể có Hiệp Sĩ — mỗi người rút từ nhóm sở hữu của mình, không
  lí do gì cấm; cấm sẽ làm ghép đội hình phức tạp vô ích). Phân
  biệt tướng địch/ta khi trùng: tướng **không nhuộm màu đội** như
  luật cứng hiện hành — thay vào đó mọi yếu tố quanh tướng mang
  màu phe: **tên trên đầu + [TAG] màu Đỏ/Xanh** (§5.5), vòng chọn
  dưới chân, viền thanh máu, và chấm minimap khi trong tầm nhìn.
- Luật tướng còn lại giữ nguyên: huấn luyện ở Castle đời IV của
  **chính người đó**, giá 500+300 **trừ quỹ chung**, tối đa 1
  tướng sống/người, chết thì huấn luyện lại được như hôm nay, bộ
  kỹ năng 1 chiêu + hào quang giữ nguyên, trọng tài/AI tự tung
  chiêu theo luật cũ khi áp dụng.
- Vì giá tướng trừ quỹ chung: sổ chi tiêu (§3.3) luôn ghi rõ khoản
  500+300 này thuộc về ai — tránh tranh cãi "ai đốt quỹ mua
  tướng".

### 5.3 Trần dân số: toán cho 16 người

Hiện trạng: trần theo nhà ở, không trần cứng — một người chơi cuối
trận 8 người hôm nay thường duy trì ~40–70 đơn vị (ước lượng từ giá
nhà 30 Gỗ/+5 dân và nhịp kinh tế hiện tại; **chưa có số đo thật —
đây là một trong các đo đạc Phase 1 phải làm**, §8.4). Nếu 16 người
cùng đạt 60 đơn vị: **~960 unit + ~250 công trình** trong một sim —
gấp đôi trận 8 người nặng nhất hôm nay, mà lockstep bắt **mọi**
client (kể cả điện thoại yếu) mô phỏng toàn bộ mỗi tick.

Đề xuất trần cứng riêng cho đại chiến (**mặc định, §11.7**):
- **50 đơn vị/người** (nhà ở vẫn cần để đạt trần — trần cứng chỉ
  chặn phần vượt) và **400 đơn vị/phe**.
- Trần tối đa toàn trận: **800 unit** — chỉ ~1,3–1,7 lần trận 8
  người cuối trận hôm nay, là mức Phase 1 benchmark được (§8.4).
- Dân (villager) tính vào trần như mọi đơn vị khác, như luật hiện
  hành; tàu thuyền vẫn không tính dân số (giới hạn đã biết) nhưng
  bản đồ đại chiến Phase 1 không có nước lớn nên không phát sinh.

### 5.4 Các luật còn lại

- **Ngoại giao: TẮT cấu trúc** — phòng đại chiến không có cờ ngoại
  giao (như hàng đợi), không mời liên minh, không tặng tài nguyên
  xuyên phe (trong phe đã là quỹ chung nên không cần tặng).
- **Chat**: hai kênh — **Tất cả** và **Liên minh** (kênh đội: chỉ
  8 người cùng phe đọc được; theo đúng luật "chữ Đội chỉ ở trận có
  đội thật" — ở đây nhãn là **Liên minh**). Chat liên minh ngoài
  trận (17a/17b) vẫn chạy độc lập như cũ.
- **Tầm nhìn**: chung trong phe — đã là hành vi sẵn có của `fog.gd`
  theo team (và tiền lệ sương mù hợp nhất của đồng minh 15b). Tám
  căn cứ cùng phe = tầm nhìn phủ gần hết vùng nhà từ đầu — đúng
  chất đánh chung.
- **Khởi đầu mỗi người**: TC + 3 Dân + 1 Kỵ binh trinh sát (pop
  4/5) — **giữ nguyên như hôm nay** (`_mp_spawn_bases()`), cộng
  Thành trì Liên minh dựng sẵn ở tuyến sau của mỗi phe và quỹ
  chung §3.2. Xe hàng/xe chở quân (15g) giữ nguyên luật, doanh thu
  xe hàng của ai thì cộng vào quỹ chung của phe người đó.
- **Màu phe**: xem §5.5.

### 5.5 Màu phe Đỏ / Xanh — chỉ trong đại chiến

Luật màu slot 8 màu (Đỏ · Xanh dương · Xanh lá · Vàng · Tím · Cam ·
Xanh ngọc · Hồng) **giữ nguyên ở mọi chế độ khác**. Riêng trận đại
chiến, màu sắc thu về đúng **hai màu phe**:

- **Phân màu theo vòng**: trong mỗi cặp đấu, hạt giống cao hơn
  cầm **Đỏ ở các vòng lẻ** và **Xanh ở các vòng chẵn** (thứ tự
  vòng tính trong bảng của tháng đó) — luân phiên qua từng vòng
  để không liên minh nào giữ nguyên một màu suốt cả giải. Màu
  không tạo khác biệt cơ học nào trong sim; luân phiên là cho
  công bằng trực quan và để khán giả xem bảng đấu (§10) quen
  mắt. Màu của từng cặp được in sẵn trên bảng đấu ngay khi công
  bố, và lặp lại ở phòng chờ đại chiến (§9).
- **Nhuộm quân/công trình**: phần vải/khiên/cờ theo màu đội của
  mọi unit và công trình trong phe nhuộm **Đỏ** (phe Đỏ) hoặc
  **Xanh** (phe Xanh) — dùng đúng cơ chế nhuộm theo slot hiện có
  (`team_colors.gd`), chỉ khác: cả 8 slot của một phe nhận **cùng
  một màu đích**. Đối thủ nhìn vào là biết ngay quân ai, không cần
  nhớ bảng 8 màu.
- **Minimap**: chấm quân/công trình của phe mình = màu phe mình;
  địch (khi trong tầm nhìn) = màu phe địch. Luật "minimap không
  hiện đội khác ngoài tầm nhìn" giữ nguyên.
- **Tên + [TAG]**: tên người chơi trên đầu tướng và trong mọi
  danh sách hiện kèm [TAG] liên minh (đã có từ 17b) và **toàn bộ
  plate tên tô màu phe** — đồng đội xanh/đỏ nhất quán từ đầu tướng
  tới panel. Thành viên liên minh đang giữ ngôi vô địch tháng có
  thêm danh hiệu **<Liên minh vô địch>** ghép sau tên theo đúng
  thứ tự ghép tên ở §7.1 — trong trận đại chiến, tên trên đầu
  tướng cũng dùng cùng một chuỗi ghép đó.
- **Đầu điểm đầu trận (score header)**: thanh tỉ số trên cùng hiện
  **ĐỎ ‹điểm phe› — ‹điểm phe› XANH** (điểm phe = tổng
  `match_score_of` của 8 slot), kèm thanh máu Thành trì hai phe —
  nhìn một chỗ biết thế trận.
- **Màn kết quả**: hai khối Đỏ/Xanh rõ rệt (§9).
- **Phân biệt đồng đội với nhau** khi màu không còn phân biệt:
  bằng **số thứ tự đội hình 1–8** (hiện trong panel Đội + phòng
  chờ), **chân dung tướng chỉ định**, và **tên hiển thị** — ba thứ
  này vốn đã có trong UI; trong thế giới, tên trên đầu từng người
  là duy nhất nên không nhầm được. Lệnh điều quân vẫn theo quyền
  sở hữu như cũ: chỉ điều được quân **của mình** (màu giống nhau
  không có nghĩa là điều chung — ghi rõ trong hướng dẫn tab Đại
  chiến để người mới không hiểu nhầm).

## 6. Xếp hạt giống + bảng đấu + công bằng

- **Điểm Đại Chiến (ĐĐC) của liên minh**: một thang Elo **riêng
  cho liên minh**, tách hẳn MMR cá nhân (MMR ẩn của người chơi
  không liên quan đến đại chiến). Mỗi liên minh bắt đầu 1000 điểm;
  **sau từng trận trong bảng đấu**: Elo hai phía theo kết quả
  thắng/thua của trận đó (trận đại chiến là nhị phân — không có
  thứ hạng 1–8 nên Elo cổ điển áp nguyên được), K = 32 (mặc định,
  cùng ngưỡng với Elo cá nhân). Vô địch một giải tháng thắng 3–4
  trận trong vòng một tháng nên ĐĐC được kiểm chứng dồn dập quanh
  các ngày đấu rồi nằm yên giữa các vòng — đúng nhịp giải tháng,
  và bảng đấu vẫn là nơi ĐĐC được kiểm chứng nhiều lần nhất.
  ĐĐC hiện công khai ở tab Đại chiến + Bảng xếp hạng (đây là danh
  dự của tập thể, không có lí do giấu như MMR cá nhân).
- **Xếp hạt giống + lập bảng**: khi đóng đăng ký (ngày 4, 12:00),
  server xếp các liên minh dự giải theo ĐĐC giảm dần = hạt giống
  1..N, rồi lập bảng loại trực tiếp theo **ghép hạt giống chuẩn**
  (hạt giống 1 gặp hạt giống cuối, 2 gặp áp cuối... — hai hạt
  giống cao nhất chỉ có thể gặp nhau ở chung kết). Số ô bảng là
  lũy thừa của 2 kế tiếp (4/8/16); số dự giải lẻ thì **các hạt
  giống cao nhất nhận bye qua vòng đầu** cho đủ (ví dụ 10 liên
  minh → bảng 16 ô, 6 bye cho hạt giống 1–6, 4 liên minh còn lại
  đấu 2 cặp vòng 16) — đúng tiền lệ bye cho hạt giống cao của hệ
  giải đấu 15h. Suất giải: **tối đa 16, tối thiểu 4** mới mở giải
  (**mặc định, §11.12**); thừa đăng ký thì ưu tiên ĐĐC cao; dưới
  4 → tháng đó không mở giải, các liên minh đã đăng ký được thông
  báo và danh sách tham chiến được hoàn lại nguyên trạng (có
  thể đăng ký lại tháng sau). **Bảng cố định ngay khi công bố**
  (ngày 4, 13:00, lên sảnh chính §10) — không bốc lại, không đổi
  cặp giữa giải vì bất cứ lí do gì ngoài luật xử thua §2.
- **Bye trong bảng**: liên minh nhận bye (vì xếp hạt giống hoặc
  vì cặp kề bên bị huỷ §2.5) đi tiếp vòng sau **không cần đấu**:
  không đổi ĐĐC, không thưởng trận — chỉ vị trí trong bảng tiến
  lên, thưởng hạng cuối giải (§7) vẫn tính theo vòng dừng cuối
  cùng như thường.
- **Chu kỳ tháng = "mùa" của đại chiến**: không còn khái niệm
  mùa 4 tuần riêng — **mỗi tháng là một mùa trọn vẹn** với một
  nhà vô địch tháng. Những gì **mang qua tháng sau**: Điểm Đại
  Chiến giữ nguyên (không reset, không nén — ĐĐC là uy tín dài
  hạn của liên minh, chỉ đổi qua từng trận đã đấu); **lịch sử
  vô địch tháng** ghi vào hồ sơ liên minh (tháng · khiên · MVP
  chung kết) và hiện ở tab Đại chiến; số lần vô địch tháng là
  con số danh dự lớn nhất của một liên minh. Khi cần so "mạnh
  nhất lịch sử" giữa các liên minh: số lần vô địch tháng → số
  lần á quân → ĐĐC → XP tổng.
- **Chống gian lận**: (1) điều kiện thành viên 48 giờ (§2) chống
  lính đánh thuê; (2) kết quả chỉ từ **trọng tài** (Phase 2+) —
  không tin host như Custom; (3) **bảng đấu công khai và cố định
  từ ngày 4** (§10) — đường đi của mọi liên minh ai cũng thấy,
  win-trading muốn làm phải lộ diện trước toàn server, và ĐĐC
  Elo tự triệt tiêu kèo bắt tay (thắng liên minh yếu được rất
  ít điểm); (4) liên minh **giải tán rồi
  lập lại** để reset ĐĐC: liên minh mới luôn bắt đầu 1000 và mất
  toàn bộ lịch sử — tự nó đã là hình phạt; (5) người chơi bị ghi
  nhận bỏ trận đại chiến giữa chừng mất quyền ra trận ở giải
  tháng kế tiếp (mặc định) ngoài trừ uy tín §2.

## 7. Phần thưởng

Mọi con số là **mặc định — §11.8**:

- **Thưởng theo từng trận trong bảng**: thắng một trận được
  **+100 điểm tuần** (cộng vào cùng tổng `weekPoints()` hiện có
  qua một trường thưởng riêng như cơ chế `WeekBonus` của nhiệm
  vụ 17b — tự nhiên tham gia đua **Vương miện tuần**) + **+200
  XP liên minh**. Thua một trận đã đấu thật: **+50 điểm tuần**
  (điểm ra trận — ra sân đầy đủ là có, khuyến khích liên minh
  yếu vẫn đăng ký) + **+100 XP**. Thắng vòng theo diện walkover
  (§2): điểm như thắng trận, nhưng không có chỉ số cá nhân/MVP.
  Bye: không thưởng trận (§6). Xử thua vì vắng (dưới 6 người):
  **0 điểm** cho trận đó.
- **Thưởng theo hạng khi giải kết thúc** (cộng thêm trên thưởng
  trận): **Vô địch tháng: +300 điểm tuần + 500 XP liên minh**;
  **Á quân: +150 điểm tuần + 250 XP**; **dừng ở bán kết: +75
  điểm tuần + 100 XP** (bảng 4 đội không có mục này — bán kết là
  vòng đầu của họ, thua bán kết ở bảng 4 chỉ nhận thưởng trận).
  Để so sánh thang: nhiệm vụ tuần 17b cho +30/+40/+50 điểm;
  một nhà vô địch bảng 8 nhận tổng 3×100 (trận) + 300 (hạng) =
  **600 điểm tuần** — và vì chung kết rơi vào tuần cuối tháng,
  toàn bộ 600 điểm đó đổ vào đúng tuần chung kết, biến tuần cuối
  tháng thành tuần đua vương miện quyết định nhất. Điểm rải
  theo từng vòng nên liên minh dừng sớm vẫn có phần, không còn
  cảnh một trận ăn hết.
- **Ranh giới hai hệ (nói rõ để khỏi mâu thuẫn)**: nhịp **tháng**
  chỉ áp cho bản thân giải đại chiến. Hệ điểm tuần của 17a/17b
  (đóng góp tuần, nhiệm vụ tuần, vương miện Vô địch tuần chốt
  thứ Hai 00:00) **không đổi một chữ** — trận đại chiến vẫn cộng
  điểm tuần qua `weekPoints()` vào đúng **tuần diễn ra trận đó**
  như mọi nguồn điểm khác. Một liên minh vô địch tháng sẽ đồng
  thời là ứng viên nặng ký cho vương miện của tuần chung kết,
  nhưng đó là hai danh hiệu khác nhau của hai hệ khác nhau.
- **Cho từng thành viên ra trận** (8 chính thức + dự bị có vào
  thay): trận đại chiến được ghi như một trận thường vào hồ sơ —
  tham gia +10 XP tài khoản, thắng +20 nữa (đi qua đúng
  `MatchHook`/`MatchFeed` hiện có → tự cộng **đóng góp tuần** cho
  liên minh của họ và tính vào nhiệm vụ tuần 17b như mọi trận
  khác). Dự bị không vào trận: không tính (chưa đấu). **Không**
  chạm sao/MMR/uy tín Hạng (trừ trừ uy tín khi bỏ trận §2).
- **MVP trận**: người có `match_score_of` cao nhất toàn trận nhận
  dòng vinh danh ở màn kết quả + tab Đại chiến tháng đó; **MVP phe
  thua** vẫn ghi nhận riêng (chơi hay trong thế thua vẫn được
  thấy). Điểm MVP tính thêm từ số Góp/Chi §3.3 làm tie-break khi
  điểm trận bằng nhau. MVP của **trận chung kết** được ghi tên
  ngay tại ô Nhà vô địch trên bảng đấu sảnh chính (§10) — vinh
  danh trước toàn server.
- **Danh hiệu + vinh danh tháng**: liên minh vô địch tháng nhận
  **khiên vô địch tháng** trên thẻ hồ sơ liên minh (giữ tới khi
  có nhà vô địch tháng mới) và một dòng trong **lịch sử vô địch
  tháng** của server (liên minh · tháng · MVP chung kết — hiện
  ở tab Đại chiến và trên bảng đấu đã khép, §10). Từng thành
  viên giữ ngôi nhận **danh hiệu <Liên minh vô địch>** hiện
  cạnh tên trong chat — chi tiết ở mục 7.1 ngay dưới. Vương
  miện Vô địch tuần của 17b vẫn là của hệ tuần như cũ — đại
  chiến là một nguồn điểm của cuộc đua đó, không tạo vương
  miện thứ hai.

### 7.1 Danh hiệu <Liên minh vô địch> — hiện cạnh tên trong chat

Khi một liên minh thắng trận chung kết tháng, **mọi thành viên
của liên minh đó tại thời điểm chung kết kết thúc** mang danh
hiệu **<Liên minh vô địch>** — chuỗi ký tự nguyên văn; hai dấu
ngoặc nhọn `<` `>` là một phần của danh hiệu, không phải ký
hiệu đánh dấu của tài liệu.

- **Nơi hiện**: ghép vào tên người gửi ở **mọi dòng chat** —
  chat sảnh, chat trong trận (mọi kênh), chat liên minh — bất
  cứ đâu tên người gửi được vẽ. **Thứ tự ghép tên cố định**:
  `[TAG] Tên <Liên minh vô địch>` — [TAG] liên minh (17b) ở
  trước, tên hiển thị ở giữa, danh hiệu sau cùng, và **danh
  hiệu tô vàng** (màu vàng danh dự như chữ đội thắng trên bảng
  đấu); tên và [TAG] giữ màu vốn có của từng bề mặt. Người
  không giữ ngôi thì chuỗi ghép dừng ở tên như hôm nay — không
  chừa khoảng trống, không đổi bố cục dòng chat.
- **Ai được giữ (ảnh chụp lúc đăng quang)**: server chụp danh
  sách thành viên của liên minh vô địch **tại thời điểm trọng
  tài báo kết quả chung kết** — chỉ những người trong ảnh chụp
  đó mới mang danh hiệu. Người **gia nhập liên minh đương kim
  vô địch sau thời điểm đó KHÔNG được nhận** danh hiệu (luật
  chống "đu theo nhà vô địch" — ghi rõ luật này ở tab Đại
  chiến để khỏi thắc mắc). Người trong ảnh chụp mà **rời liên
  minh thì mất ngay**; quay lại cũng không được khôi phục (ảnh
  chụp là cố định — rời là ra khỏi diện giữ ngôi). Nếu liên
  minh đương kim vô địch bị giải tán: toàn bộ danh hiệu tắt
  ngay, vì không còn liên minh nào giữ ngôi.
- **Thời hạn**: giữ cho tới khi **nhà vô địch tháng tiếp theo
  đăng quang** — tại bất kỳ thời điểm nào cũng chỉ có **một**
  liên minh đương kim vô địch. Tháng nào giải không mở được
  (dưới 4 liên minh đăng ký, §6) hoặc chung kết bị huỷ hai bên
  (§2.5): ngôi bỏ trống — danh hiệu tháng trước tắt khi tháng
  đó khép lại mà không có nhà vô địch mới, không ai giữ danh
  hiệu của một giải đã qua hai tháng.
- **Kỹ thuật**: thuần trình diễn — server phân giải danh hiệu
  cạnh [TAG] qua cùng một đường nối (seam) kiểu `AllyTagOf`
  của 17b (một hàm tra cứu theo tài khoản, trả chuỗi danh hiệu
  hoặc rỗng), client ghép chuỗi khi vẽ tên; **không bao giờ
  vào sim, không vào checksum**. Ảnh chụp người giữ ngôi lưu
  trên bản ghi giải tháng ở server (Store), cùng chỗ với bảng
  đấu (§8.2).
- **Ở Hồ sơ (phần cộng thêm, trong phạm vi)**: người giữ ngôi
  đồng thời có mục **"Liên minh vô địch"** trong danh sách
  Danh hiệu của Hồ sơ — dùng đúng cơ chế `Titles` sẵn có như
  danh hiệu giải đấu 15h, chọn hiển thị ở Hồ sơ được như mọi
  danh hiệu; hết ngôi thì mục đó tự mờ đi và không chọn được
  nữa. Phạm vi chốt: **chat là bề mặt chính** theo lệnh Tín;
  mục Hồ sơ là phần cộng thêm nhất quán vì dùng chung một cơ
  chế — không phải bề mặt mới tách riêng.

### 7.2 Mỹ phẩm: khung avatar + bong bóng chat

Hai hệ mỹ phẩm thuần trình diễn, mở khoá từ chính các hệ đã
có trong game — không bán, không quay số (đúng luật không
pay-to-win của dự án). Cả hai đều: lưu ở server trên tài khoản
(danh sách sở hữu + món đang đeo, cùng mẫu lưu với `Titles`),
chọn ở **Hồ sơ**, và **không bao giờ vào sim/checksum**, không
emoji (mọi hoạ tiết là hình vẽ).

**A. Khung avatar** — chỉ khung **vuông** (luật cứng đã chốt
của game: avatar là ảnh vuông; không làm khung tròn):

- **Bộ khung THẬT của Tín (thay toàn bộ danh mục tự chế ở bản
  trước)**: Tín đã cung cấp sẵn một bộ khung động; danh mục
  đang dùng gồm **11 khung** — file gốc lưu ở
  `art_candidates/avatar_frames/raw/frame_01.gif`,
  `frame_03.gif` … `frame_12.gif` (**giữ nguyên số file gốc,
  không đánh số lại**). Số đo thật: cả 11 đều là **GIF động
  1064×1064**, mỗi khung 7–119 frame con và **đều có tâm
  trong suốt**. Mỗi khung có **cửa sổ trong (aperture) ở vị
  trí/kích thước khác nhau** — hệ quả kỹ thuật ở mục Tích hợp
  bên dưới. Danh mục khung của game từ nay = **11 khung này +
  khung mặc định trơn**, không còn khung tự chế nào khác.
- frame_02 Quán Cà Phê — Tín loại bỏ 2026-11-12 (file giữ ở art_candidates/avatar_frames/dropped/)
- **Nơi hiện**: bọc quanh avatar ở **mọi nơi avatar xuất
  hiện** — chip danh tính ở sảnh, thẻ hồ sơ, hàng bạn bè,
  panel Người chơi trong trận, hàng Bảng xếp hạng, hàng người
  gửi trong chat. Một hàm vẽ khung dùng chung (đặt cạnh
  `rank_badge.gd`) để mọi bề mặt giống nhau từng pixel.
- **Không che chấm trạng thái**: các chấm online/ping vốn ngồi
  ở góc avatar — khung vẽ ở lớp **dưới** cùng, viền khung nằm
  ngoài hộp avatar và chừa góc; chấm trạng thái luôn vẽ **trên
  cùng** như hôm nay. Khung không bao giờ đè lên chấm.
- **Danh mục + nguồn mở khoá (bảng đề xuất — §11.16)**:

  | # | Khung (tên hiển thị) | Cách mở khoá | Thời hạn |
  |---|---|---|---|
  | — | Mặc định (viền vàng mảnh) | Có sẵn cho mọi tài khoản | Vĩnh viễn |
  | 01 | Dây Dâu Tây | Cấp tài khoản 5 | Vĩnh viễn |
  | 03 | Mặt Mèo | Cấp tài khoản 15 | Vĩnh viễn |
  | 04 | Hoa Hồng Bướm Xanh | Là thành viên khi liên minh đạt cấp 3 | Khi còn ở liên minh đạt mốc đó |
  | 05 | Sân Khấu Trái Tim | Thành tích: thắng 50 trận (mọi chế độ ghi sổ) | Vĩnh viễn |
  | 06 | Sao Vàng | Đạt bậc Hầu Tước trong thang mùa Hạng | Vĩnh viễn |
  | 07 | Cột Hy Lạp | Vô địch một giải đấu người chơi (hệ 15h) | Vĩnh viễn |
  | 08 | Mây Anh Đào | Cấp tài khoản 25 | Vĩnh viễn |
  | 09 | Rèm Sân Khấu | Hoàn thành 10 nhiệm vụ tuần của liên minh (cộng dồn) | Vĩnh viễn |
  | 10 | Cửa Sổ Anh Đào | Là thành viên khi liên minh đạt cấp 5 | Khi còn ở liên minh đạt mốc đó |
  | 11 | Đá Rêu Nấm | Thành tích: thắng 150 trận (mọi chế độ ghi sổ) | Vĩnh viễn |
  | 12 | Ruy Băng Sao | Thuộc liên minh đương kim vô địch tháng Đại chiến — cùng luật giữ ngôi như danh hiệu §7.1 (ảnh chụp lúc đăng quang, vào sau không được, rời là mất) | **Chỉ khi đang giữ ngôi** — hết ngôi tự gỡ; nếu đang đeo thì rơi về khung mặc định |

  Phân tầng chủ đích: khung theo cấp tài khoản (01/03/08) và
  thành tích cá nhân (05/11) ai chơi đều với tới được;
  khung theo liên minh (04/09/10) buộc gắn bó với liên minh;
  06 theo Hạng và 07 theo giải đấu người chơi là tầng giỏi;
  **12 Ruy Băng Sao là khung danh giá nhất** — chỉ nhà vô
  địch Đại chiến đang giữ ngôi mới đeo được, đứng cạnh danh
  hiệu <Liên minh vô địch> ở §7.1.
- **Chọn khung**: ở Hồ sơ, danh sách khung đã sở hữu (khung
  chưa mở hiện mờ kèm dòng cách mở), một khung đang đeo; đổi
  là áp dụng ngay ở mọi nơi.
- **Tích hợp kỹ thuật (việc thật ở bước code, ghi trước để
  khỏi bất ngờ)**:
  - **Godot không chạy GIF gốc**: cả 11 file phải qua một
    pipeline chiết xuất ở build-time (tool tái lập được, cùng
    mẫu với các tool xử lý pack của Tín trước đây): tách từng
    GIF thành **sprite sheet** (hoặc WebP động) kèm nhịp
    frame gốc; runtime chỉ nạp bản đã chiết xuất, không nạp
    GIF 1064×1064 thô vào game.
  - **Hạ cỡ**: avatar trong game chỉ vẽ ở các cỡ nhỏ (chip
    sảnh, hàng danh sách, thẻ hồ sơ là mặt lớn nhất) — bản
    chiết xuất xuất ở **hai cỡ đích khớp cỡ vẽ thật** (mặc
    định 256px cho mặt lớn + 128px cho mặt nhỏ, số chốt ghi
    trong tool khi code); riêng cỡ thẻ hồ sơ giữ chuyển động
    mượt, các hàng danh sách nhỏ có thể chạy cùng bản động đã
    hạ cỡ — không phóng từ bản 1064.
  - **Hiệu chuẩn cửa sổ (aperture) — đã có bảng đo thật**:
    `art_candidates/avatar_frames/aperture_calibration.json`
    là **bảng bắt đầu cho build**, không còn là việc ước
    lượng ở bước code. Bảng này được đo bằng phép **quét
    alpha theo hai đường ngang/dọc qua tâm (centre-cross)
    trên frame đầu của từng GIF**, cho ra hình chữ nhật cửa
    sổ `[x0, y0, x1, y1]` theo toạ độ chuẩn hoá 0–1 cho 11
    khoá `frame_01`, `frame_03` … `frame_12`. Hàm vẽ đặt
    avatar thành **một hình vuông nằm giữa cửa sổ và nội
    tiếp trong hình chữ nhật đó**. Khi build vẫn phải kiểm
    tra lại bằng mắt/tay từng khung trước khi chốt số, nhất
    là các cửa sổ không thật sự chữ nhật như **frame_03 Mặt
    Mèo**; nếu số chốt cuối khác bảng đo, cập nhật JSON cùng
    thay đổi asset để tài liệu và dữ liệu không lệch nhau.

**B. Bong bóng chat** — lời chat hiện ngay trên đầu nhân vật
trong trận:

- **Hành vi**: khi một người chơi gửi chat **trong trận**,
  ngoài dòng ở panel chat, một bong bóng chứa nguyên văn tin
  nhắn hiện **trên đầu tướng của người đó** trong thế giới:
  bong bóng tự co giãn theo độ dài tin (tối đa 2 dòng, dài hơn
  thì cắt bằng "…"), tự mờ sau **4 giây** (mặc định — §11.17).
  Tướng chưa ra sân hoặc đã chết: bong bóng neo trên **Town
  Center của người đó**; TC cũng đã mất (người đó đã bị loại):
  không có bong bóng thế giới, chỉ còn dòng panel như hôm nay.
- **Luật tầm nhìn (fog)**: bong bóng tuân theo sương mù như
  mọi thứ trong thế giới — chỉ hiện cho người xem **đang nhìn
  thấy** đơn vị neo đó tại thời điểm ấy. Vì sương mù tính theo
  phe (§0), đồng đội cùng phe luôn thấy bong bóng của nhau ở
  vị trí tướng — kênh đội trong đại chiến 8 người vì thế đọc
  như nói chuyện trực tiếp. Địch chỉ thấy bong bóng của tin
  kênh Tất cả khi tướng người gửi nằm trong tầm nhìn của họ;
  tin kênh đội không bao giờ tới địch nên không phát sinh
  bong bóng phía địch. Không có ngoại lệ kiểu "vị trí biết lần
  cuối": không thấy đơn vị là không thấy bong bóng.
- **Kiểu bong bóng (mỹ phẩm)**: bong bóng cũng có **kiểu**,
  chọn được như khung — kiểu mặc định (nền navy, viền vàng,
  đúng ngôn ngữ UI), các kiểu theo bậc Hạng, và **kiểu Vô
  địch Đại chiến** (viền vàng đậm + một dải khiên nhỏ vẽ ở góc
  bong bóng) dành cho người đang giữ ngôi §7.1. Kiểu đang
  dùng đồng thời áp cho **dòng chat trong panel khi đang ở
  trong trận + panel chat liên minh** (dòng tin của người gửi
  mang nền/viền theo kiểu của họ); **chat sảnh giữ dòng trơn
  như hôm nay** — nhiều người gửi cùng lúc, áp kiểu sẽ rối
  mắt. Phạm vi chốt đúng như vậy, ghi rõ để khỏi hiểu nhầm là
  mọi panel đều đổi.
- **Ngoài trận không có bong bóng thế giới**: chat ở sảnh và
  các hàng đợi (Thường/Hạng/FFA) không có thế giới để neo —
  chỉ có dòng panel, và kiểu bong bóng cũng không áp ở đó
  (theo phạm vi ở mục trên).

## 8. Kỹ thuật — tính khả thi thật

### 8.1 Những gì tái dùng được nguyên trạng

- Khung phòng server-tạo sẵn cho trận > 4 người **đã tồn tại**
  qua đường hàng đợi (phòng Custom bị `MaxPlayersPerRoom = 4`
  nhưng phòng do server lập cho hàng đợi chứa 8 người — hub đã
  có tiền lệ n ≥ 5); phòng đại chiến đi theo đường đó: server
  lập phòng 16 slot, không mật khẩu, không niêm yết.
- Luật thắng theo team, sương mù theo team, kênh chat đội, cơ chế
  snapshot vào lại giữa trận, trọng tài headless, ghi replay —
  tất cả đã chạy cho 2v2/8 người và **mở rộng theo slot** chứ
  không phải viết mới.
- Điểm vào liên minh: tab mới trong `alliance_screen.gd` (vỏ
  Direction B đã chốt) + các trường dữ liệu mới trên bản ghi liên
  minh qua interface Store như 17a/17b.

### 8.2 Những gì phải thay đổi thật

1. **Sim theo khóa phe**: ví (§3.1), đời (§5.1), công nghệ (§5.1)
   — ba mảng `mp_wallets/mp_ages/mp_techs` đang khóa theo slot.
   Cách làm an toàn: thêm lớp truy cập `wallet_of/age_of/tech_of`
   chỉ rẽ nhánh khi cờ `war_mode` bật; các chế độ khác chạy đúng
   đường cũ từng byte. Checksum: trạng thái phe vẫn là trạng thái
   sim — mọi client đều suy ra giống nhau từ cùng luồng lệnh nên
   lockstep không đổi nguyên tắc.
2. **Bản đồ 128×128 + layout `war`**: `world.gd` đang hằng số
   64×64 ở nhiều nơi (bake, A*, scatter, spawn). Cần tham số hoá
   cỡ bản đồ theo cấu hình trận (chỉ đại chiến dùng 128) — đây là
   phần việc âm thầm nhưng dài nhất ở client; bù lại `base_centres`
   và scatter vốn đã tổng quát theo danh sách căn cứ.
3. **Phòng chờ 16 người + điểm danh/dự bị**: luồng phòng mới
   (danh sách khoá từ server, thay người theo §2) — server là
   chính, client là một biến thể màn phòng chờ hai cột Đỏ/Xanh.
4. **Đăng ký/bảng đấu/ĐĐC ở server**: thêm vào `alliance.go` +
   một lịch tháng (đúng mẫu tính lười theo mốc đã có — không
   cần cron mới: chốt danh sách/lập bảng/chốt ngôi tính lười
   khi có truy cập đầu tiên sau mốc, như cách vương miện tuần
   17b đang chốt theo mốc tuần).
   Trạng thái bảng đấu (cặp đấu, vòng, tỉ số, trạng thái từng
   trận) là một bản ghi server riêng qua interface Store — nguồn
   dữ liệu **duy nhất** cho cả bảng ở sảnh chính (§10) lẫn bản
   trong tab Đại chiến, hai bề mặt không bao giờ lệch nhau.
5. **Trọng tài cho trận 16 người**: vẫn 1 tiến trình/trận nhưng
   sim nặng gấp đôi — xem rủi ro §8.4.

### 8.3 Tải hệ thống — phân tích

- **Relay server**: mỗi lệnh của 1 người được phát tới 15 người
  còn lại (+ trọng tài). Lệnh RTS nhỏ (vài chục byte JSON); băng
  thông ước tính vẫn dưới vài trăm KB/s/phòng ở nhịp lệnh cao —
  không phải nút thắt. Tick clock 10/s giữ nguyên.
- **Độ trễ đầu vào**: `InputDelayTicks = 2` (200ms) đang vừa cho
  8 người; với 16 người, xác suất có ít nhất một client chậm
  trong phòng cao hơn — nhưng lockstep ở đây **không chờ** client
  chậm (server phát tick đều, client chậm tự tụt và bắt kịp bằng
  cơ chế hiện có), nên ảnh hưởng chính là người chậm thấy trận
  trễ hơn, không kéo cả phòng. Giữ nguyên 2; benchmark Phase 1 sẽ
  cho biết có cần 3 hay không.
- **Checksum/DESYNC**: checksum mỗi 30 tick giữ nguyên. Xác suất
  "ít nhất một client lệch" trong trận tăng theo số client × số
  unit — khi lệch, resync vẫn xử lý được (đa số 15/16 áp đảo),
  nhưng **tần suất** resync có thể tăng; mỗi lần resync là một
  snapshot ~gấp đôi kích thước hôm nay (ước tính từ ~20
  trường/unit × 800 unit + ~250 công trình → **khoảng 300–500KB
  JSON**, so với ~150–250KB của trận 8 người cuối trận — ước
  lượng theo cấu trúc `_mp_unit_record()`, chưa đo thật). Client
  được chọn làm nguồn snapshot phải **tải lên** chừng đó qua mạng
  di động — điểm nghẽn resync thực tế. Giảm nhẹ: ưu tiên chọn
  nguồn là client có ping tốt nhất trong phe đa số (server đã có
  số ping).
- **Replay**: luồng lệnh của 16 người × 45 phút → tệp ghi lớn
  hơn trận 8 người khoảng 2 lần; vẫn là JSON lệnh nhỏ, chấp
  nhận được trong trần LRU 200 — nhưng một trận đại chiến chiếm
  "dung lượng" gấp đôi trong cùng trần: đề xuất trần riêng cho
  replay đại chiến (giữ ít nhất 4 tuần gần nhất của mỗi liên
  minh, ngoài LRU chung) — chi tiết để Phase 2.
- **Hiệu năng máy người chơi**: nút thắt thật. Sim chạy trên
  **mọi** máy ở tốc độ 30 bước/giây (3 frame 1/30 cho mỗi tick
  10/s). 800 unit với tìm đường A* + sương mù theo team trên bản
  đồ 128×128: sương mù hiện quét theo team (rẻ — 2 team), tìm
  đường là chi phí chính. Điện thoại Android tầm thấp là ẩn số
  lớn nhất của toàn thể thức — xem §8.4.

### 8.4 Rủi ro lớn nhất + phép thử chốt hạ từng rủi ro

| # | Rủi ro | Phép thử chốt (làm ở Phase 1, trước mọi UI đẹp) |
|---|---|---|
| R1 | Sim 16 người × ~800 unit không giữ nổi 30 bước/giây trên điện thoại yếu → trận chậm dần, DESYNC dây chuyền | **Benchmark sim**: trận giả lập 16 slot do bot/AI điều khiển (AI địch hiện có + auto-driver của các smoke test), đẩy tới trần 800 unit, đo thời gian mỗi bước sim trên máy tính sandbox **và** một thiết bị Android tầm thấp thật; qua chuẩn: bước sim < 33ms ở phút 40. Nếu trượt: hạ trần dân số (§5.3) theo số đo, không đoán. |
| R2 | Bake bản đồ 128×128 (6144²) tốn bộ nhớ/thời gian nạp trên máy yếu | Đo thời gian + RAM lúc nạp bản đồ `war` trên cùng thiết bị R1; dự phòng bake 32px/ô (4096²). |
| R3 | Resync snapshot 300–500KB qua mạng di động làm client lệch đứng chờ lâu, lệch tiếp | Đo dung lượng snapshot thật ở trạng thái 800 unit (dụng cụ: bắt snapshot của một trận benchmark R1) + thử resync qua kết nối 4G mô phỏng; nếu quá chậm: nén snapshot (gzip ở tầng WS) là phương án đã thấy trước. |
| R4 | Quỹ chung bị phá/xả bởi một thành viên → trải nghiệm phe sụp đổ | Không đo bằng máy: **playtest Phase 1** với sổ chi tiêu §3.3, xem lại nhật ký sau 3–5 trận giao hữu; nếu phá quỹ là có thật và lặp lại → bật phương án lai §3.6 hoặc trần chi mềm. |
| R5 | 16 người thật khó tụ đủ cùng một giờ → tỉ lệ trận huỷ vì vắng cao, thể thức chết yểu | Nhịp tháng đã giảm sẵn áp lực: mỗi liên minh đấu tối đa 4 tối Thứ Bảy trong tháng và biết lịch trước cả tháng. Số liệu Phase 2 mềm (mở cho liên minh đăng ký tự nguyện): tỉ lệ điểm danh đủ ≥6 người; nếu vẫn thấp: cho mỗi vòng 2 khung giờ để hai phe thống nhất chọn, hoặc cho ghép "liên minh liên quân" (hai liên minh nhỏ hợp đội) — cả hai đều là quyết định sản phẩm để sau khi có số. |
| R6 | Trọng tài headless sim 16 người tốn CPU server (mỗi trận 1 tiến trình Godot) | Đo CPU/RAM của tiến trình trọng tài trong benchmark R1 chạy trên chính hạ tầng server hiện tại; các vòng đấu dồn vào một khung giờ Thứ Bảy nên số trận đồng thời bị chặn bởi số cặp của vòng đó (tối đa 8 trận ở vòng đầu bảng 16) — rủi ro thấp nhưng phải có số. |

### 8.5 Chia phase — mỗi phase tự chạy được, tự kiểm chứng được

- **Phase 1 — Đại chiến giao hữu (nền kỹ thuật)**: bản đồ 128 +
  layout `war`; phòng đại chiến 16 người do Hội trưởng hai liên
  minh hẹn nhau (hoặc phòng thử nghiệm nội bộ); quỹ chung + đời/
  công nghệ theo phe + Thành trì + màu Đỏ/Xanh + HUD quỹ chung +
  benchmark R1–R3 + smoke test 16 client giả lập (mở rộng bộ
  smoke hiện có: 16 tiến trình headless như cách ranked_smoke
  đang chạy nhiều client). **Không** điểm, **không** trọng tài
  bắt buộc (tin host như Custom), **không** đăng ký giải tháng. Mục
  đích duy nhất: chứng minh sim + kinh tế chung + bản đồ chạy
  được và vui. **Không** bảng đấu ở Phase 1: giao hữu là từng
  trận rời, chưa có giải thì không có bảng thật để vẽ — bảng đấu
  chỉ sinh cùng dữ liệu giải ở Phase 2.
- **Phase 2 — Giải đấu tháng chính thức (loại trực tiếp)**: đăng
  ký + danh sách tham chiến + xếp hạt giống/lập bảng §6 + đội
  hình theo từng vòng + phân tướng + điểm danh/dự bị/xử thua
  theo vòng + trọng tài bắt buộc + ĐĐC theo từng trận + điểm
  vào `weekPoints()`/vương miện + **bảng đấu công khai ở sảnh
  chính (§10) ra mắt cùng lúc** + tab Đại chiến đầy đủ + lịch
  sử/MVP/danh hiệu §7. Bảng đấu bắt buộc thuộc Phase 2 chứ không
  tách đợt riêng: nó là mặt tiền của giải, và chỉ có nghĩa khi
  chạy trên dữ liệu bảng thật. Đây là bản Tín công bố cho người
  chơi.
- **Phase 3 — Khán giả + vinh danh + tinh chỉnh**: lịch sử vô
  địch tháng + cột danh dự ở Bảng xếp hạng (§6); **bấm vào cặp
  đang đấu trên bảng đấu để vào xem** với tư
  cách observer (Phase 2 cặp đang đấu chỉ hiện trạng thái trên
  bảng, chưa vào xem được — nói rõ ở §10); observer xem đại
  chiến (tái dùng delay 0/60/120s của 15e —
  chú ý observer KHÔNG được xem kênh chat phe); replay đại chiến
  nổi bật ở tab; cân bằng lại (trần dân số, hệ số giá ×3, HP
  Thành trì) theo số liệu Phase 2; cân nhắc các điểm mở §3.4/R5
  nếu dữ kiện đòi hỏi.

## 9. Màn hình cần có

Tất cả dùng đúng ngôn ngữ UI hiện hành: nền navy đặc (PageShell),
thẻ viền vàng, nút chính vàng chữ tối, icon Font Awesome, không
emoji. Hai bề mặt, hai việc khác nhau — không trùng lặp: **quản
lý tham chiến** (đăng ký, xếp đội hình) chỉ ở **tab "Đại chiến"
trong màn Liên minh** (mục 1–5 dưới đây); **xem giải** (bảng đấu
cho mọi người) ở **sảnh chính** — đó là một màn hình riêng được
đặc tả đầy đủ ở §10, mục này không lặp lại.

1. **Tab Đại chiến** (trong `alliance_screen.gd`, cạnh tab Nhiệm
   vụ 17b): thẻ trạng thái tháng (chưa đăng ký / đã đăng ký / đối
   thủ vòng này + phe Đỏ-Xanh của vòng + ngày đấu / bị loại ở
   vòng X / vô địch tháng); Điểm Đại Chiến + thứ hạng ĐĐC toàn
   server; nút Tham chiến (Hội trưởng/Phó); khối **Bảng đấu**
   (bản đầy đủ của §10 thu vào tab, **đường đi của liên minh
   mình tô vàng** qua các vòng); khối **Đội hình vòng này** (8 ô
   chính thức: avatar + tên + tướng chỉ định + trạng thái sẵn
   sàng; 4 ô dự bị); lịch sử đại chiến của liên minh (đối thủ,
   tỉ số điểm, MVP, mã xem lại).
2. **Màn xếp đội hình** (Hội trưởng/Phó): các thành viên trong
   **danh sách tham chiến tháng** (ai chưa đủ 48 giờ đã bị loại
   khỏi danh sách từ lúc chốt đăng ký), kéo/bấm để đặt vào 8 ô
   chính + 4 ô dự bị **của vòng sắp đấu**, mỗi ô chính chọn
   tướng từ nhóm người đó sở hữu (chặn trùng trong phe ngay tại
   UI), nút Chốt đội hình (khoá theo hạn chốt của từng vòng,
   §2).
3. **Phòng chờ đại chiến**: hai cột **Đỏ / Xanh**, mỗi cột 8 hàng
   (số thứ tự + tên + [TAG] + chân dung tướng + chấm điểm danh),
   đồng hồ đếm tới giờ đấu, trạng thái thay dự bị theo §2, kênh
   chat phòng (chỉ phe mình khi chưa vào trận — hai phe không
   chat chung ở phòng chờ; vào trận mới có kênh Tất cả).
4. **HUD trong trận (phần khác biệt)**: thanh quỹ chung §3.7 +
   dòng góp/chi cá nhân; thanh tỉ số Đỏ–Xanh + máu Thành trì hai
   phe (§5.5); panel Đội 8 hàng (số, tên, tướng, trạng thái sống/
   bị loại, Góp · Chi, nút mở biểu quyết đầu hàng phe); minimap
   hai màu. Phần còn lại của HUD giữ nguyên.
5. **Màn kết quả đại chiến**: vỏ màn kết quả AOV hiện có, tổ
   chức lại theo phe: banner THẮNG/THUA + cách kết thúc (phá
   Thành trì / điểm hết giờ / đầu hàng / xử thua vắng); khối MVP
   nổi bật như cũ; **hai bảng Đỏ/Xanh** mỗi bảng 8 hàng (chân
   dung tướng · tên · Điểm · Hạ địch · Mất quân · Thu thập · Phá
   công trình · APM · Góp · Chi — kiểm chứng tràn cột với đủ 16
   hàng ở kích thước thật như luật panel của dự án); dòng điểm
   thưởng liên minh nhận được (thưởng trận §7; nếu đây là trận
   cuối của liên minh trong giải — bị loại hoặc chung kết — thì
   kèm thưởng hạng) và biến động ĐĐC; nút Xem lại (mã replay
   đại chiến) · Về màn Liên minh.

## 10. Bảng đấu công khai ở sảnh chính

Đây là **mặt tiền của giải** — theo đúng ý Tín: ai mở game cũng
thấy tháng này liên minh nào đấu liên minh nào, ai thua bị loại,
ai đang đi tiếp, và ai vô địch. Bảng đấu sống ở sảnh **suốt cả
tháng** — kể cả những tuần không có vòng đấu và cả quãng nghỉ
giữa hai giải (§10.2) — là tính năng hạng nhất của Phase 2,
không phải trang phụ.

### 10.1 Cửa vào ở sảnh chính: một cửa duy nhất, tách khỏi chip Giải đấu

Sảnh chính hiện có: rail phải chứa các chip (Bạn bè, BXH, **chip
Giải đấu của hệ giải đấu người chơi 15h**), băng chuyền banner
mùa ở giữa-trên, panel 4 chế độ. Đánh giá các cửa có thể:

- **Thêm chip "Đại chiến" vào rail phải**: bị loại — rail đã có
  chip Giải đấu (15h, giải của **người chơi**, đăng ký cá nhân/
  đội 2 người); thêm một chip nghe gần giống nhau ("Giải đấu" /
  "Đại chiến") kề nhau là công thức gây bấm nhầm và hỏi "hai cái
  khác gì nhau". Hai hệ giải khác nhau phải khác hẳn cách vào.
- **Ô thứ năm trong panel chế độ**: bị loại — panel chế độ là nơi
  vào **đấu** (Thường/Hạng/Custom/Minigame); bảng đấu là nơi
  **xem**, để lẫn vào sẽ có người tưởng bấm là vào trận.
- **Một slide riêng trong băng chuyền banner mùa** (đề xuất):
  banner vốn là bảng tin của sảnh (mùa giải, sự kiện). Slide
  "ĐẠI CHIẾN LIÊN MINH" hiện: tháng giải hiện tại, vòng đang ở
  đâu ("Bán kết — Thứ Bảy 20:00" / "Đang đấu: 2 cặp" / "Chung
  kết — Thứ Bảy cuối tháng"), ảnh nền là hai khiên Đỏ/Xanh đối
  đầu. **Bấm vào slide = mở bảng đấu toàn màn.** Giữa hai giải,
  slide hiện nhà vô địch tháng vừa rồi + ngày mở đăng ký giải
  tháng tới kèm đồng hồ đếm ngược. Một cửa, đúng việc xem,
  không đụng chip Giải đấu 15h.

Quyết định vị trí này ghi ở §11.12 chờ Tín chốt như mọi quyết
định mặt tiền khác.

### 10.2 Nội dung bảng: đọc một lượt hiểu cả giải

Màn bảng đấu (toàn màn, vỏ PageShell như các màn thông tin
khác):

- **Đầu màn**: "ĐẠI CHIẾN LIÊN MINH — Tháng N" + trạng thái giải
  (Đang nhận đăng ký / Vòng X sắp đấu / Đang đấu / Đã có nhà vô
  địch) + **đồng hồ đếm ngược tới vòng đấu kế tiếp** — giữa hai
  vòng cách nhau một tuần, đồng hồ này (còn mấy ngày · mấy giờ)
  là thứ người xem quay lại kiểm tra nhiều nhất.
- **Bảng sống cả tháng, kể cả ngoài giải**: từ lúc chung kết
  kết thúc tới khi bảng tháng mới được công bố (ngày 4 tháng
  sau), bảng giữ nguyên trạng thái đã khép: mọi cặp đã xong,
  ô **NHÀ VÔ ĐỊCH** có chủ, đầu màn ghi thêm "Giải tháng sau
  mở đăng ký ngày 1". Trong cửa sổ đăng ký (ngày 1–4, chưa có
  bảng mới), thân bảng chuyển sang danh sách các liên minh **đã
  đăng ký** + hạn chót chốt danh sách; bảng tháng trước vẫn xem
  lại được bằng nút chuyển "Giải tháng trước" ở đầu màn.
- **Thân bảng**: mỗi vòng một **cột** (Vòng 16 · Tứ kết · Bán
  kết · Chung kết), trong cột là các **thẻ cặp đấu** xếp dọc;
  giữa hai cột có **đường nối** từ thẻ thắng của vòng trước tới
  ô của vòng sau — mắt đi theo đường nối là thấy ngay "thắng cặp
  này thì gặp ai". Điện thoại ngang: bảng 16 có 4 cột + ô vô địch
  không vừa một màn → **cuộn ngang theo cột, bám cột** (snap),
  cột vòng hiện tại luôn là cột mở đầu khi vào màn.
- **Mỗi thẻ cặp đấu** gồm: hai dòng liên minh (khiên huy hiệu +
  tên + [TAG] + hạt giống), mỗi dòng gắn **chấm màu phe của vòng
  đó** (Đỏ/Xanh theo §5.5); giờ đấu dự kiến; **trạng thái** —
  *Sắp đấu* (mờ, hiện giờ) / *Đang đấu* (viền vàng nhấp nháy
  nhẹ, hiện phút thứ + thanh máu Thành trì hai phe) / *Đã xong*
  (phía thắng **chữ vàng đậm** + tỉ số điểm phe, phía thua mờ
  đi; kết thúc kiểu walkover/huỷ ghi rõ "Xử thua" / "Huỷ — hai
  bên vắng" thay cho tỉ số).
- **Cuối bảng**: ô **NHÀ VÔ ĐỊCH** nối từ chung kết — trống (khung
  khiên mờ) cho tới khi chung kết kết thúc, sau đó hiện khiên +
  tên liên minh vô địch + tên MVP trận chung kết (§7).
- **Tự làm mới**: khi màn đang mở, bảng tự cập nhật theo cùng
  nhịp làm mới của màn Giải đấu 15h (vài giây một lần) + cập nhật
  ngay khi có trận kết thúc trong lúc đang xem; đóng màn là
  ngừng, không có tiến trình nền nào chạy thêm.

### 10.3 Ai xem được: mọi người, kể cả khách

Bảng đấu là dữ liệu công khai của giải (tên liên minh, lịch,
kết quả — không có dữ liệu cá nhân nào nhạy cảm): **mọi người
mở sảnh đều xem được, kể cả tài khoản khách chưa thuộc liên
minh nào**. Chỉ xem — bảng không có nút thao tác nào ngoài điều
hướng: không đăng ký, không vào trận, không chat từ bảng (đăng
ký/tham chiến vẫn chỉ ở tab Đại chiến của liên minh, §9). Đây
cũng là kênh tuyển quân tự nhiên: người chưa có liên minh nhìn
bảng đấu là thấy ngay liên minh nào đang mạnh.

### 10.4 Bản trong tab Đại chiến: cùng một bảng, tô đường của mình

Tab Đại chiến (§9 mục 1) chứa **cùng bảng đấu đó** — cùng dữ
liệu, cùng bố cục cột — cộng hai khác biệt trình diễn: **đường
đi của liên minh mình được tô vàng** từ vòng đầu tới vòng hiện
tại (và ô đích ở vòng sau), và thẻ cặp của mình có thêm dòng giờ
điểm danh + nút qua phòng chờ khi tới vòng của mình. Một nguồn
dữ liệu server duy nhất (§8.2 mục 4) nuôi cả hai bề mặt — cấm
duyệt hai bảng riêng lệch nhau.

### 10.5 Dữ liệu + trạng thái trực tiếp lấy từ đâu

- Trạng thái bảng sống ở **server**, cạnh dữ liệu giải (Store,
  §8.2 mục 4): lập bảng khi công bố, cập nhật khi trọng tài báo
  kết quả từng trận, khi xử thua/walkover chốt, khi vô địch xác
  định. Client lấy/gửi theo đúng mẫu màn Giải đấu 15h
  (`tournament_screen.gd`: xin dữ liệu khi mở + làm mới định kỳ
  khi đang mở) — thêm một message xin bảng đại chiến, không cơ
  chế mới.
- Trạng thái **"Đang đấu"** lấy từ chính phòng đại chiến đang
  chạy (server biết phòng nào thuộc cặp nào vì phòng do server
  lập): server gắn cờ live + phút thứ + máu Thành trì hai phe
  (hai con số phòng/trọng tài đã có) lên bản ghi cặp đấu; không
  cần client nào "báo cáo" thêm.
- **Bấm vào một cặp đang đấu**: ở **Phase 2 chỉ xem bảng** —
  chưa vào xem trận được (nói thẳng ở đây để khỏi hứa quá): thẻ
  cặp hiện trạng thái trực tiếp là hết. **Phase 3** mới nối vào
  hệ observer (vào xem có trễ như 15e, §8.5) — lúc đó thẻ đang
  đấu có thêm nút "Xem".

### 10.6 Sơ đồ bố cục bảng (bảng 8 liên minh)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ←  ĐẠI CHIẾN LIÊN MINH — THÁNG 11    Bán kết · Thứ Bảy 20:00 · còn 6 ngày│
├───────────────┬───────────────┬───────────────┬──────────────────────┤
│ TỨ KẾT        │ BÁN KẾT       │ CHUNG KẾT     │ NHÀ VÔ ĐỊCH          │
│ ┌───────────┐ │ ┌───────────┐ │ ┌───────────┐ │ ┌──────────────────┐ │
│ │[1] Sông Lam│ │ │ Sông Lam  │ │ │           │ │ │                  │ │
│ │[8] Hắc Long│─┼─│ Hổ Vương  │─┼─│  ? — ?    │─┼─│   (chờ chung kết)│ │
│ │ ✓ SL thắng │ │ │ T7 20:00  │ │ │ T7 cuối   │ │ │                  │ │
│ └───────────┘ │ └───────────┘ │ └───────────┘ │ └──────────────────┘ │
│ ┌───────────┐ │ ┌───────────┐ │               │                      │
│ │[3] Hổ Vương│ │ │ Bạch Hổ   │ │               │                      │
│ │[6] Kim Ưng │─┼─│ Kim Long  │ │               │                      │
│ │ ✓ HV thắng │ │ │ T7 20:00  │ │               │                      │
│ └───────────┘ │ └───────────┘ │               │                      │
│ ... (2 cặp   │               │               │                      │
│  tứ kết nữa) │               │               │                      │
└───────────────┴───────────────┴───────────────┴──────────────────────┘
  ✓ = đã xong · phe thắng chữ vàng · đường nối ─┼─ = đường đi tiếp
```

## 11. Điểm chờ Tín chốt

Mỗi mục ghi kèm **đề xuất mặc định của Bé**:

1. **Điều kiện thắng**: (b) phá Thành trì Liên minh làm luật
   chính + hết 45 phút tính điểm + biểu quyết đầu hàng ≥5/8.
   *(Đề xuất: đúng như vậy.)*
2. **Kinh tế**: chung toàn phần (§3) với quỹ đầu 1600/1600/800,
   hay phương án lai 70/30 (§3.6)? *(Đề xuất: chung toàn phần.)*
3. **Đời + công nghệ theo phe**, chi phí lên đời/nghiên cứu ×3
   giá một người. *(Đề xuất: theo phe, ×3.)*
4. **Lịch giải tháng**: đăng ký ngày 1, 00:00 – ngày 4, 12:00,
   công bố bảng ngày 4, 13:00, mọi vòng đấu **Thứ Bảy 20:00**
   tính ngược từ chung kết (bảng 16: 4 Thứ Bảy; bảng 8: 3; bảng
   4: 2), chung kết luôn **Thứ Bảy cuối tháng 20:00**; đội hình
   từng vòng chốt lúc 18:00 ngày đấu. *(Đề xuất: đúng lịch này;
   nếu người chơi lệch múi giờ nhiều sẽ bàn khung giờ thứ hai ở
   Phase 3.)*
5. **Roster tối thiểu + luật vắng**: đăng ký cần ≥10 thành viên;
   điểm danh dưới 6 người ở **bất kỳ vòng nào** = xử thua vòng
   đó; cả hai phe cùng vắng một cặp = cả hai bị loại (§2). Có
   bù gì cho phe thiếu người không (§3.5)? *(Đề xuất: 10 / 6 /
   không bù.)*
6. **Tướng trong phe**: cấm trùng trong một phe + phân tướng lúc
   xếp đội hình; hai phe được trùng nhau. *(Đề xuất: đúng vậy.)*
7. **Trần dân số đại chiến**: 50/người, 400/phe (chốt lại sau
   benchmark R1). *(Đề xuất: 50/400 làm mốc benchmark.)*
8. **Thưởng đại chiến**: theo trận (thắng +100 điểm tuần/+200
   XP liên minh; thua +50/+100; vắng = 0) cộng thưởng hạng
   (vô địch tháng +300 điểm tuần/+500 XP; á quân +150/+250;
   dừng ở bán kết +75/+100). *(Đề xuất: đúng thang §7 này.)*
9. **Điều kiện thành viên ra trận**: ở liên minh ≥48 giờ.
   *(Đề xuất: 48 giờ.)*
10. **Phe Đỏ/Xanh phân cho ai**: luân phiên theo vòng — hạt
    giống cao hơn cầm Đỏ ở vòng lẻ, Xanh ở vòng chẵn (§5.5),
    in sẵn trên bảng đấu. *(Đề xuất: đúng luật luân phiên này —
    màu không có lợi thế cơ học, luân phiên cho công bằng trực
    quan.)*
11. **Số phase**: làm Phase 1 (giao hữu + benchmark) trước rồi
    mới quyết Phase 2, hay duyệt cả lộ trình 3 phase một lượt?
    **Bảng đấu công khai (§10) thuộc Phase 2** — không làm ở
    Phase 1 vì chưa có dữ liệu giải thật. *(Đề xuất: duyệt cả
    lộ trình, nhưng Phase 1 phải qua cổng benchmark R1–R3 mới
    làm Phase 2.)*
12. **Số suất giải tháng**: tối đa 16 liên minh (thừa đăng ký
    thì ưu tiên ĐĐC cao), tối thiểu 4 mới mở giải. *(Đề xuất:
    16 / 4 — khớp cỡ bảng lũy thừa của 2 và lịch vòng trong
    tháng.)*
13. **Cửa vào bảng đấu ở sảnh chính**: một slide riêng trong
    băng chuyền banner mùa (§10.1) — không thêm chip rail (tránh
    nhầm với chip Giải đấu 15h), không đặt vào panel chế độ.
    *(Đề xuất: đúng cửa banner này.)*
    **[SỬA ĐỔI — Tín lệnh 2026-11-12 22:03, ĐÃ LÀM]:** cửa vào
    là một **nút ngang vàng nổi bật ngay dưới banner mùa**
    ("XEM BẢNG ĐẤU · Đại chiến liên minh", rộng bằng banner),
    bấm mở màn Bảng đấu — thay cho ý tưởng slide trong băng
    chuyền. Màn Bảng đấu đã dựng ở mức khung + lịch tháng +
    trạng thái chưa có giải; bảng thật đổ dữ liệu vào đây ở
    Phase 2.
14. **Nhịp giải trong tháng**: một vòng mỗi tuần (đề xuất ở §1)
    hay dồn cả giải vào **một tuần duy nhất trong tháng** (các
    vòng cách nhau 1–2 ngày như bản sửa đổi 2 đã từng ghi)?
    *(Đề xuất: một vòng/tuần. Biến thể dồn-tuần KHÔNG chọn: cả
    giải nén vào vài tối liên tiếp làm rủi ro vắng (R5) tăng
    mạnh — 16 người phải rảnh nhiều tối trong cùng một tuần —
    và mất hẳn thời gian chuẩn bị/do thám giữa các vòng, thứ
    làm giải tháng khác một giải giao hữu. Giữ biến thể này
    làm dự phòng nếu nhịp tháng bị chê quá chậm sau Phase 2.)*
15. **Danh hiệu <Liên minh vô địch> (§7.1)**: người giữ = ảnh
    chụp thành viên lúc đăng quang (vào sau không được nhận,
    rời liên minh là mất), giữ tới khi có nhà vô địch tháng
    tiếp theo. *(Đề xuất: đúng luật chống đu theo này.)*
16. **Khung avatar (§7.2A)**: bộ khung là **11 khung GIF thật
    của Tín** (đã thay danh mục tự chế ở bản trước; frame_02
    Quán Cà Phê đã bị loại khỏi danh mục) — **bảng gán nguồn
    mở khoá ở §7.2A là mặc định đề xuất** chờ chốt (phân
    tầng: cấp tài khoản/thành tích → liên minh → Hạng/giải
    đấu → vô địch Đại chiến; nguồn “hoàn thành 30 nhiệm vụ
    ngày” của frame_02 được bỏ hẳn, không gán chồng lên khung
    khác). Riêng khung 12 (Ruy Băng Sao): chỉ đeo được **khi
    đang giữ ngôi** (hết ngôi tự gỡ) hay giữ vĩnh viễn như
    khung 07 của giải đấu người chơi?
    *(Đề xuất: chỉ khi giữ ngôi — khớp luật danh hiệu §7.1,
    và làm ngôi vô địch tháng luôn hiện diện trên avatar
    khắp server.)*
17. **Bong bóng chat (§7.2)**: thời lượng hiện 4 giây; kiểu
    bong bóng áp cho panel chat trong trận + panel chat liên
    minh, **không** áp cho chat sảnh. *(Đề xuất: 4 giây + đúng
    phạm vi đó.)*

---
_Kết luận của Bé: thể thức **khả thi trên nền hiện có** — ba thay
đổi sim khóa-theo-phe (ví/đời/công nghệ), bản đồ 128×128 và luồng
phòng 16 người là việc thật nhưng không phải viết lại game; rủi ro
quyết định nằm ở hiệu năng sim 800 unit trên điện thoại yếu (R1)
và hành vi quỹ chung (R4) — cả hai đều có phép thử rẻ ở Phase 1
trước khi cam kết làm giải đấu tháng._
