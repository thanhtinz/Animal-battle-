# Empire Age

Game chiến thuật thời gian thực (RTS) 2D pixel online cho Android/iOS — kiểu Age of Empires bản PC chơi mạng LAN: xây dựng căn cứ, khai thác tài nguyên, huấn luyện quân tại một Trại lính duy nhất, lên 4 thời đại và thắng bằng cách phá Town Center của đối thủ.

- **Engine:** Godot 4 (client) · **Server:** Go (stdlib thuần) — lockstep 10 tick/s, trọng tài headless cho trận đấu hạng
- **Chế độ:** Đấu Thường + Đấu Hạng 8 người đấu tự do (hàng đợi, MMR ẩn + hệ sao theo mùa kiểu Liên Quân) · Phòng Custom 2–4 người (mật khẩu, người xem có trì hoãn chống gian lận, ngoại giao) · Chơi đơn với máy
- **Nhân vật chính:** 8 nhân vật (4 nhân vật gốc + Tứ Điện Chủ Sấm/Hỏa/Phong/Thổ), mỗi người một bộ kỹ năng riêng, bốc thăm vào trận

## Cấu trúc

- `godot/` — client Godot 4 (scripts, assets, tests)
- `server/` — server Go: relay lockstep, tài khoản, hàng đợi, trọng tài, replay
- `EMPIRE-AGE-MASTER.md` — tài liệu thiết kế gốc · `KE-HOACH-MVP.md` — kế hoạch + nhật ký từng đợt làm
- `art_candidates/`, `assets-src/` — nguồn art và asset gốc

_Repo này trước đây là dự án Animal Battle (đã đóng); nay là nơi lưu trữ của Empire Age._
