# EMPIRE AGE — PROJECT MASTER DOCUMENT

Online 2D Pixel Real-Time Strategy Game

- Phiên bản: 1.0
- Thể loại: Real-Time Strategy (RTS)
- Nền tảng: Android, iOS
- Định hướng: Multiplayer Online
- Đồ họa: HD 2D Pixel Art
- Camera: Top-down 2D
- Engine: Godot 4
- Tài liệu: Project Master Document
- Nguồn: Tín gửi 2026-11-07 (bản gốc nguyên văn bên dưới)

---

## 1. TỔNG QUAN DỰ ÁN

### 1.1. Giới thiệu

Empire Age là trò chơi chiến thuật thời gian thực trực tuyến (Online RTS), lấy cảm hứng từ các trò chơi chiến thuật kinh điển như Age of Empires.

Người chơi bắt đầu với một khu định cư nhỏ, phát triển nền kinh tế, khai thác tài nguyên, xây dựng công trình, nghiên cứu công nghệ, huấn luyện quân đội và mở rộng lãnh thổ.

Mục tiêu cuối cùng là xây dựng một đế chế hùng mạnh và đánh bại đối thủ thông qua chiến thuật kinh tế, quân sự và kiểm soát bản đồ.

Game được thiết kế ưu tiên trải nghiệm mobile nhưng vẫn giữ chiều sâu chiến thuật của RTS truyền thống.

### 1.2. Tầm nhìn sản phẩm

* Tạo ra một game RTS thực thụ trên điện thoại.
* Cho phép điều khiển hàng chục đến hàng trăm đơn vị.
* Có hệ thống kinh tế và quân sự chuyên sâu.
* Có multiplayer cạnh tranh thời gian thực.
* Có hệ thống xếp hạng và giải đấu.
* Có cộng đồng, clan và chiến tranh đội nhóm.
* Có khả năng mở rộng sang PC trong tương lai.

### 1.3. Định vị sản phẩm

Empire Age không phải game xây thành chờ đợi hoặc chiến thuật theo lượt.

Gameplay chính diễn ra liên tục trong trận đấu. Người chơi phải đưa ra quyết định ngay lập tức về khai thác, xây dựng, phát triển công nghệ và điều quân.

## 2. THÔNG SỐ SẢN PHẨM

| Hạng mục | Định hướng |
|---|---|
| Thể loại | RTS |
| Camera | Top-down |
| Đồ họa | HD Pixel Art |
| Gameplay | Real-time |
| Chế độ | Online Multiplayer |
| Nền tảng đầu tiên | Android, iOS |
| Engine | Godot 4 |
| Ngôn ngữ | GDScript / C# |
| Trận đấu tiêu chuẩn | 20–30 phút |
| Thời đại | 4 |
| Người chơi | 2–4 người/phòng: 1v1, 2v2, FFA 3–4 người |
| Điều khiển | Touch Control |
| Máy chủ | Dedicated Server |

## 3. CORE GAMEPLAY

### 3.1. Vòng lặp gameplay

1. Bắt đầu trận đấu.
2. Nhận trung tâm thành phố và dân cư.
3. Phân công dân khai thác tài nguyên.
4. Xây dựng công trình.
5. Phát triển kinh tế.
6. Nghiên cứu công nghệ.
7. Nâng cấp thời đại.
8. Huấn luyện quân đội.
9. Khám phá và kiểm soát bản đồ.
10. Tấn công hoặc phòng thủ.
11. Tiêu diệt đối thủ hoặc hoàn thành điều kiện chiến thắng.

### 3.2. Hệ thống thời gian

Trận đấu sử dụng thời gian thực. Mọi hoạt động diễn ra đồng thời: dân khai thác tài nguyên, công trình được xây dựng, quân đội di chuyển, đơn vị giao chiến, công nghệ được nghiên cứu, tài nguyên liên tục được tiêu thụ và sản xuất. Không có cơ chế chờ lượt.

## 4. HỆ THỐNG KINH TẾ

### 4.1. Các loại tài nguyên

| Tài nguyên | Công dụng |
|---|---|
| Food | Tạo dân và quân |
| Wood | Xây dựng và sản xuất |
| Gold | Huấn luyện quân cao cấp |
| Stone | Phòng thủ và công trình |
| Iron | Nâng cấp quân sự |

### 4.2. Hệ thống dân cư

Dân cư là lực lượng sản xuất quan trọng nhất. Các công việc: chặt cây, đào vàng, khai thác đá, khai thác sắt, làm ruộng, xây dựng, sửa chữa, vận chuyển tài nguyên.

### 4.3. Hệ thống phân công lao động

Người chơi có thể: chọn một dân, chọn nhiều dân, kéo thả vùng chọn, giao nhiệm vụ, chuyển đổi nhiệm vụ, tập trung khai thác, chia nhóm dân theo công việc. Dân phải có AI tìm đường, tránh vật cản và xử lý công việc tự động.

## 5. HỆ THỐNG CÔNG TRÌNH

### 5.1. Công trình kinh tế

| Công trình | Chức năng |
|---|---|
| Town Center | Trung tâm thành phố |
| House | Tăng giới hạn dân số |
| Farm | Sản xuất lương thực |
| Lumber Camp | Điểm khai thác gỗ |
| Mining Camp | Điểm khai thác khoáng sản |
| Market | Trao đổi tài nguyên |
| Storage | Lưu trữ tài nguyên |

### 5.2. Công trình quân sự

Barracks — TRƯỜNG LÍNH DUY NHẤT: huấn luyện MỌI loại lính (bộ binh, cung thủ, thương binh, kỵ binh, máy công thành), mở khóa dần theo thời đại (gom chung 1 loại trường lính theo lệnh Tín 2026-11-08 — KHÔNG còn Archery Range / Stable / Siege Workshop riêng), Blacksmith (nâng cấp quân), Castle (quân đội đặc biệt), Watch Tower (phòng thủ), Wall (tường thành), Gate (cổng thành), Dock (hải quân).

### 5.3. Cơ chế xây dựng

Chọn công trình từ thanh xây dựng → hiển thị bản xem trước → kiểm tra vị trí hợp lệ → xác nhận xây dựng → dân tự động đến vị trí → công trình có thanh tiến độ → có thể sửa chữa → có thể bị phá hủy → có thể nâng cấp theo thời đại.

## 6. HỆ THỐNG QUÂN ĐỘI

- Bộ binh: Militia, Swordsman, Long Swordsman, Champion, Spearman, Pikeman.
- Cung thủ: Archer, Crossbowman, Longbowman, Elite Archer.
- Kỵ binh: Scout Cavalry, Light Cavalry, Knight, Heavy Cavalry, Cavalry Archer.
- Công thành: Battering Ram, Catapult, Mangonel, Trebuchet, Siege Tower.
- Hải quân: Fishing Boat, Transport Ship, War Galley, Fire Ship, Heavy Warship.

Mỗi đơn vị có: HP, Attack, Defense, Attack Range, Attack Speed, Movement Speed, Armor Type, Damage Type, Population Cost, Resource Cost, Training Time, Vision Range.

Khắc chế: Spearman > Kỵ binh; Archer > Bộ binh; Cavalry > Cung thủ; Swordsman > Công trình nhẹ; Siege > Công trình; Warship > Hải quân đối phương. Hệ thống khắc chế phải đủ sâu để chiến thuật và phối hợp quân đội quan trọng hơn sản xuất số lượng lớn.

## 7. HỆ THỐNG THỜI ĐẠI

- Age I – Dark Age: khởi đầu nền văn minh, kinh tế cơ bản, bộ binh sơ cấp, công trình gỗ.
- Age II – Feudal Age: phát triển quân sự, mở khóa cung thủ, kỵ binh, công trình phòng thủ.
- Age III – Castle Age: lâu đài, quân đội cao cấp, máy công thành, công nghệ chuyên sâu.
- Age IV – Imperial Age: công nghệ tối đa, quân đội tinh nhuệ, công trình cao cấp, chiến tranh tổng lực.

Nâng cấp thời đại cần tài nguyên và thời gian nghiên cứu.

## 8. HỆ THỐNG NỀN VĂN MINH

Roman (bộ binh), Chinese (kinh tế và công nghệ), Japanese (bộ binh tinh nhuệ), Viking (hải quân), Mongol (kỵ binh), Persian (kỵ binh và kinh tế), Egyptian (công trình), Byzantine (phòng thủ). Mỗi nền văn minh có: đơn vị đặc biệt, công trình đặc biệt, công nghệ độc quyền, bonus kinh tế, bonus quân sự, phong cách chiến đấu. Các nền văn minh phải được cân bằng trong Ranked.

## 9. BẢN ĐỒ VÀ ĐỊA HÌNH

Loại bản đồ: Grassland, Forest, Desert, Snow, Island, Riverland, Highland, Swamp. Thành phần: cây, đá, mỏ vàng, mỏ sắt, sông, hồ, núi, đồng bằng, vật cản, tàn tích, khu vực chiến lược.

Fog of War: khu vực đã khám phá / đang nhìn thấy / chưa khám phá. Người chơi không nhìn thấy hoạt động quân sự trong vùng bị che khuất.

## 10. MULTIPLAYER ONLINE

Chế độ: Ranked 1v1 (2 người), Ranked 2v2 (4 người), FFA 3–4 người, Custom Match, Co-op vs AI, Survival, Clan War. MỖI PHÒNG TỐI ĐA 4 NGƯỜI CHƠI (sửa đổi 2026-11-07 theo lệnh Tín — bỏ hẳn 3v3 và 4v4).

Custom Match: tạo phòng, mời bạn bè, đặt mật khẩu, chọn bản đồ, chọn đội, chọn nền văn minh, chọn số lượng người (từ 2 đến 4), chọn giới hạn thời gian, chọn điều kiện chiến thắng, chọn mức độ AI, bắt đầu trận đấu.

Matchmaking dựa trên: MMR, Rank, khu vực máy chủ, độ trễ mạng, số lượng người chơi, chế độ chơi.

Đồng bộ multiplayer: kiến trúc **Server Authoritative** — máy chủ xác thực hành động, đồng bộ trạng thái, tính toán tài nguyên, điều khiển AI, xử lý chiến đấu, xác định kết quả, phát hiện gian lận. Không để client tự quyết định kết quả chiến đấu hoặc tài nguyên.

## 11. ĐIỀU KHIỂN MOBILE

- Camera: kéo một ngón di chuyển, pinch zoom, chạm minimap chuyển vị trí, giới hạn camera theo bản đồ.
- Chọn đơn vị: chạm chọn một, kéo vùng chọn nhiều đơn vị, chạm hai lần chọn nhóm cùng loại, chọn toàn bộ quân đội, chọn toàn bộ dân.
- Điều khiển: chạm vị trí để di chuyển, chạm mục tiêu để tấn công, chọn công trình để xây dựng, chọn dân để khai thác, gán nhóm quân, đặt điểm tập kết, chọn đội hình.
- Group Control: tối đa 5 nhóm điều khiển nhanh (VD: 1 bộ binh, 2 cung thủ, 3 kỵ binh, 4 công thành, 5 dự bị).

## 12. ĐIỀU KIỆN CHIẾN THẮNG

1. Destroy Town Center. 2. Elimination. 3. Wonder Victory. 4. Conquest. 5. Time Limit (điểm số khi hết giờ). Cho phép tùy chỉnh trong Custom Match.

## 13. HỆ THỐNG NGOÀI TRẬN ĐẤU

Tài khoản người chơi, hồ sơ cá nhân, Rank, MMR, lịch sử trận đấu, thống kê thắng thua, thành tựu, nhiệm vụ, Clan, danh sách bạn bè, Chat, bảng xếp hạng, Tournament, Battle Pass, Skin, Cosmetic. Vật phẩm trả phí không được tạo lợi thế sức mạnh trong Ranked.

## 14. ĐỊNH HƯỚNG ĐỒ HỌA

HD Pixel Art: pixel sắc nét, không nhòe, không pha trộn tùy tiện với 3D, tỷ lệ sprite thống nhất, màu sắc dễ phân biệt, đơn vị dễ nhận biết khi zoom xa, hiệu ứng chiến đấu rõ ràng.

Asset cần sản xuất — Terrain: Grass, Dirt, Sand, Snow, Water, Forest, Mountain, Road. Buildings: Town Center, House, Barracks (trường lính duy nhất cho mọi loại lính), Farm, Market, Blacksmith, Castle, Tower, Wall, Gate. Units: Villager, Infantry, Archer, Spearman, Cavalry, Siege, Naval. Animation: Idle, Walk, Run, Attack, Gather, Build, Death, Hit, Repair. Mỗi đơn vị cần sprite sheet riêng, quy chuẩn hướng nhìn và kích thước frame.

## 15. GIAO DIỆN NGƯỜI DÙNG

20 màn hình: Splash, Login, Main Menu, Player Profile, Game Mode, Matchmaking, Custom Lobby, Civilization Selection, Loading, In-game HUD, Building Menu, Unit Command Menu, Technology Tree, Pause Menu, Victory, Defeat, Ranking, Clan, Friends, Settings.

## 16. KIẾN TRÚC KỸ THUẬT

- Game Client: Godot 4 (Rendering, Input Controller, Camera, TileMap, Entity System, Unit AI, Building System, Resource System, Combat System, UI, Audio, Networking).
- Backend: Go (Authentication, User Profile, Matchmaking, Lobby, Friends, Clan, Ranking, Match History, Inventory, Payment, Admin API).
- Infrastructure: PostgreSQL, Redis, Dedicated Game Servers, Docker, Kubernetes khi mở rộng, Object Storage, CDN, Monitoring, Logging.
- Network: Server Authoritative; client gửi lệnh, server kiểm tra và xử lý, đồng bộ trạng thái tới các client. Có thể nghiên cứu deterministic lockstep hoặc simulation authoritative tùy kết quả thử nghiệm.

## 17. DATABASE MODULE

users, user_profiles, user_settings, civilizations, civilization_units, civilization_technologies, units, buildings, technologies, maps, game_rooms, game_matches, match_players, match_results, player_ratings, match_history, friends, clans, clan_members, chat_messages, achievements, missions, inventories, cosmetics, purchases, transactions, sanctions, audit_logs. Dữ liệu mô phỏng trận đấu tách biệt với dữ liệu tài khoản và giao dịch.

## 18. ANTI-CHEAT VÀ BẢO MẬT

Server authoritative, xác thực lệnh, giới hạn tốc độ gửi lệnh, chống sửa tài nguyên, chống giả mạo kết quả, kiểm tra tốc độ di chuyển, kiểm tra thời gian huấn luyện, kiểm tra hành vi bất thường, match replay, audit log, rate limiting, account security.

## 19. ADMIN PANEL

Quản lý tài khoản, khóa tài khoản, quản lý nền văn minh, đơn vị, chỉ số quân đội, công trình, công nghệ, bản đồ, theo dõi trận đấu, xem replay, quản lý matchmaking, rank, clan, vật phẩm, sự kiện, báo cáo, theo dõi máy chủ, xem audit log.

## 20. LỘ TRÌNH PHÁT TRIỂN

- Phase 1 – Pre-production: hoàn thiện GDD, thiết kế gameplay, kinh tế, quân đội, bản đồ, art direction, prototype điều khiển mobile.
- Phase 2 – Core Prototype: Camera, TileMap, di chuyển đơn vị, chọn nhiều đơn vị, tìm đường, khai thác tài nguyên, xây dựng công trình, huấn luyện quân.
- Phase 3 – Core Gameplay: kinh tế, chiến đấu, công nghệ, thời đại, Fog of War, AI, điều kiện chiến thắng.
- Phase 4 – Multiplayer: Authentication, Lobby, Matchmaking, Dedicated Server, đồng bộ trận đấu, Reconnect, Match Results, Replay.
- Phase 5 – Content Production: nền văn minh, quân đội, công trình, bản đồ, animation, hiệu ứng, âm thanh.
- Phase 6 – Beta: Closed Beta, kiểm thử thiết bị, kiểm thử multiplayer, cân bằng, hiệu suất, chống gian lận.
- Phase 7 – Launch: phát hành Android + iOS, vận hành máy chủ, Live Ops, cập nhật nội dung, giải đấu cộng đồng.

## 21. MVP – PHIÊN BẢN ĐẦU TIÊN

1 nền văn minh, 1 bản đồ, 2 đội chơi, 1 Town Center, 5–8 loại công trình, 6–8 loại đơn vị, 3 loại tài nguyên cơ bản, 2 thời đại, dân khai thác, xây dựng, huấn luyện quân, chiến đấu, Fog of War cơ bản, AI cơ bản, multiplayer phòng 2–4 người, điều kiện chiến thắng cơ bản. Mục tiêu MVP: chứng minh game chơi RTS thực sự được trên mobile và vận hành ổn định qua mạng.

## 22. NGUYÊN TẮC PHÁT TRIỂN

1. Ưu tiên gameplay trước mỹ thuật. 2. Không hy sinh chiều sâu RTS để đơn giản hóa quá mức. 3. Điều khiển tối ưu cho cảm ứng. 4. Server kiểm soát trạng thái trận đấu. 5. Tối ưu hiệu suất cho điện thoại tầm trung. 6. Thiết kế asset theo hướng tái sử dụng. 7. Không pay-to-win. 8. Có khả năng mở rộng nội dung và nền văn minh. 9. Tách biệt hệ thống game client và backend. 10. Thiết kế multiplayer ngay từ giai đoạn prototype.

## KẾT LUẬN

Empire Age hướng đến một trò chơi chiến thuật thời gian thực 2D Pixel có chiều sâu, kết hợp xây dựng kinh tế, phát triển nền văn minh, quản lý quân đội và chiến tranh multiplayer. Sản phẩm phải giữ tinh thần RTS cổ điển nhưng có trải nghiệm điều khiển hiện đại, phù hợp với thiết bị di động. Đây là tài liệu Master định hướng dự án; các thông số cân bằng, API, database schema chi tiết, giao thức mạng và đặc tả từng module sẽ được phát triển thành các tài liệu kỹ thuật độc lập trong giai đoạn tiếp theo.
