# Empire Age — Nghiên cứu VFX + âm thanh cho đợt cài skill

_Bản nghiên cứu chuẩn bị trước đợt skill (lệnh của Tín: VFX là hạng mục chính; phải nghiên cứu VFX Godot 4, chuẩn bị tool tạo texture hiệu ứng, và làm âm thanh từng chiêu trước khi cài). Trạng thái khi viết: `characters.gd` vẫn là bộ kit cũ 1 chiêu chủ động/nhân vật; thiết kế 3 chiêu/nhân vật (2 thường + 1 ulti) và bộ icon pixel v6 đã chốt, chưa cài._

## 1. Ràng buộc kỹ thuật đo từ chính project

- **Renderer: `gl_compatibility` cho cả desktop lẫn mobile** (`project.godot`: `renderer/rendering_method="gl_compatibility"`, `rendering_method.mobile="gl_compatibility"`). Mọi lựa chọn VFX phải chạy tốt trên Compatibility, không dùng tính năng chỉ có ở Forward+/Mobile.
- Game là pixel-art 2D top-down, đích Android/iOS → ngân sách hạt phải khiêm tốn, ưu tiên đọc rõ ở cỡ nhỏ thay vì hoành tráng.
- **Luật đồng bộ giữ nguyên:** VFX và âm thanh là lớp trình diễn thuần — phát theo sự kiện chiêu ở tầng presentation, TUYỆT ĐỐI không vào sim/checksum/lockstep. Hero được bốc thăm vốn đã là dữ liệu trình diễn; hiệu ứng skill đi cùng đường đó.

## 2. Chiến lược hạt: CPUParticles2D là mặc định

| Tiêu chí | GPUParticles2D | CPUParticles2D |
|---|---|---|
| Compatibility renderer | Chạy được từ Godot 4.2 nhưng đường này ít được kiểm chứng hơn; có độ trễ biên dịch shader ở lần bùng phát đầu tiên (giật khung đúng lúc tung chiêu) | Hành vi giống hệt trên mọi renderer, không biên dịch shader, không giật lần đầu |
| Culling | Phải tự giữ `visibility_rect`, hạt bay ra ngoài là biến mất | Tự tính bounds |
| Tính năng thừa | Turbulence, sub-emitter, trails — đợt này không cần tới | Thiếu các tính năng đó, nhưng đủ cho mọi công thức ở mục 4 |
| Chi phí | Rẻ CPU khi hàng nghìn hạt | Chi phí tăng theo số hạt — chấp nhận được ở ngân sách ≤120 hạt/hiệu ứng |

**Chốt:** toàn bộ skill dùng **CPUParticles2D** (one_shot, explosiveness cao cho chiêu bùng phát; emitting liên tục có thời hạn cho bão băng/vùng kết giới). Không dùng GPUParticles2D trong đợt này — tránh rủi ro Compatibility và giật khung lần đầu. Mọi hiệu ứng dựng từ code trong `_ready` như các scene khác của project, không hand-author `.tscn` fragile.

## 3. Shader canvas_item (chạy tốt trên Compatibility)

Project hiện chỉ có 2 shader (`flag_wave`, `rounded_clip`) — chưa có hạ tầng VFX. Cần viết mới 4 shader dùng chung, tham số hoá theo màu/thời gian, mỗi hiệu ứng một `ShaderMaterial` riêng (material dùng chung sẽ làm mọi bản sao nhấp nháy cùng lúc):

1. **Ring shockwave** — vòng tròn nở từ tâm, alpha theo `progress`, mép sáng — dùng cho Vương Kiếm Giáng Thế (vòng xung kích mặt đất), Vạn Hoa Khai Thiên, Thiên Màn Bất Diệt.
2. **Dome/field** — đĩa bán trong suốt + viền pulse theo sin(TIME) — dùng cho Kết Giới, Thiên Màn, vùng Băng Hà.
3. **Freeze overlay** — phủ xanh băng + lấp lánh noise lên sprite mục tiêu (cần texture có padding trong suốt 8–16px quanh sprite để không bị cắt) — dùng cho Băng Phong, Thương Băng, công trình bị đóng băng.
4. **Slash arc** — vệt chém cong quét theo `progress`, đầu vệt sáng nhất — dùng cho Kiếm Khí Tung Hoành (vệt bay theo đường thẳng) và Xung Phong (vệt tốc độ sau hero).

## 4. Công thức từng chiêu (12 chiêu chủ động + 4 hào quang)

Ngân sách: chiêu thường ≤80 hạt, ulti ≤150 hạt, hào quang ≤12 hạt liên tục. Mọi hiệu ứng tự huỷ (queue_free) khi xong.

| Chiêu | Công thức VFX |
|---|---|
| Hào quang (cả 4) | Vòng đĩa mờ dưới chân hero theo màu nhân vật (đỏ/vàng/xanh băng/trắng) + hạt nhỏ bay lên chậm, liên tục |
| Xung Phong (Ngân Kỵ) | 3 vệt afterimage mờ dần sau hero trong 5s + hạt gió ở chân; shader slash arc mờ |
| Kiếm Khí Tung Hoành | Sprite vệt kiếm (đúng kiếm Ngân Kỵ: lưỡi bạc, chắn vàng, ngọc đỏ) bay thẳng + trail hạt sáng đỏ-vàng, nổ tia nhỏ khi trúng mục tiêu đầu |
| Vương Kiếm Giáng Thế (ulti) | Đại kiếm rơi từ trên xuống cắm đất → ring shockwave + cột bụi/đá vụn văng 2 bên + mặt đất nứt phát sáng (sprite nứt + ring), rung màn nhẹ 0.2s |
| Vương Mệnh Hồi Phục (Kim Hoa) | Cột sáng vàng mềm từ hero + dấu `+` / hạt hoa sáng bay lên trên mọi đồng minh trong vùng |
| Hoa Vũ Hồi Sinh | Mưa cánh hoa hồng-trắng rơi xoay trong vùng 3 ô suốt thời gian hồi máu, hạt hồi máu nhỏ bay lên |
| Vạn Hoa Khai Thiên (ulti) | Nở hoa lớn: ring shockwave hồng-vàng + mưa cánh hoa dày + vòng sáng miễn nhiễm quanh đồng minh 3s |
| Băng Phong (Lam Bào) | Pha lê băng bật từ đất quanh địch (sprite pha lê) + hạt tuyết nổ + freeze overlay trên địch bị chậm |
| Thương Băng Xuyên Tâm | Thương pha lê (đúng thương Lam Bào, ruy băng hoa tuyết) bay thẳng, đóng băng cứng mục tiêu đầu: khối băng phủ sprite + vệt lạnh kéo theo |
| Băng Hà Vĩnh Cửu (ulti) | Bão tuyết diện rộng: hạt tuyết chéo theo gió (CPUParticles2D emitting ~120 hạt, hướng chéo), đĩa băng dưới đất (dome/field shader xanh băng), công trình trong vùng phủ freeze overlay và ngừng hoạt động |
| Kết Giới (Bạch Sa) | Dome/field shader trắng-vàng dựng lên tại vị trí, viền pulse; đồng minh trong vùng có hạt sáng nhỏ quanh người |
| Thánh Quang Phán Xét | Cột thánh quang giáng xuống nhóm địch + tia sáng toả, địch bị giảm công có icon/hạt tối trên đầu 5s |
| Thiên Màn Bất Diệt (ulti) | Màn sáng lớn: dome/field shader + ring shockwave vàng trắng + cột sáng ở tâm; công trình trong màn có viền sáng bảo vệ |

## 5. Texture hiệu ứng — sinh thủ tục, không cần mua/tải tool ngoài

Sandbox đã có sẵn và kiểm chứng chạy được: **Godot 4.4.1** (`~/workspace/tools/godot/`) + **Python PIL/numpy**. Sinh bằng PIL rồi import như asset thường:

- `fx_glow_dot.png` — chấm mềm radial (hạt sáng mọi hệ)
- `fx_petal.png` — cánh hoa (Kim Hoa)
- `fx_snow.png` — bông tuyết 6 cánh nhỏ + hạt tuyết tròn (Lam Bào)
- `fx_shard.png` — mảnh pha lê/đá vụn (băng + Vương Kiếm)
- `fx_crack.png` — vết nứt đất phát sáng (Vương Kiếm)
- `fx_ring.png` — vòng trơn làm nền cho ring shader khi cần
- Kiếm khí và thương băng: **cắt từ chính ảnh vũ khí thật Tín gửi** (kho `assets/hero_weapons/`), pixel-hoá về cùng hạt với icon v6 — không vẽ vũ khí generic (luật đã chốt ở đợt icon).

## 6. Âm thanh từng chiêu — tổng hợp WAV bằng numpy, không cần thư viện ngoài

Mỗi chiêu 1 file WAV ngắn, phát bằng `AudioStreamPlayer2D` ở tầng presentation theo sự kiện tung chiêu (không vào sim):

- Kiếm/Xung Phong: whoosh = noise qua bandpass quét tần xuống.
- Vương Kiếm: boom trầm (sine 55Hz decay) + nứt đất (noise burst ngắn, ngắt quãng).
- Hồi máu/Hoa Vũ: chuông arpeggio sine ấm (3 nốt lên), Vạn Hoa thêm hợp âm nở.
- Băng: crackle (noise xung ngắn dày) + ting pha lê (sine cao decay nhanh); Băng Hà thêm gió rít loop ngắn.
- Thánh quang/Kết Giới: choir pad tổng hợp (sine + harmonic, attack chậm) và ting khi màn dựng xong.

## 7. Thứ tự cài đề xuất cho đợt skill

1. Sinh 6 texture fx + cắt 2 vũ khí bay; viết 4 shader dùng chung + module `skill_fx.gd` phát hiệu ứng theo sự kiện (code-only).
2. Cài logic 12 chiêu vào sim (số liệu theo thiết kế đã chốt) — VFX/âm thanh chỉ nghe sự kiện, tách hoàn toàn.
3. Tổng hợp 12 WAV + gắn player.
4. Test: bộ SP hiện có phải PASS nguyên; thêm test smoke "tung đủ 12 chiêu không lỗi, checksum 2 máy vẫn khớp" để chứng minh VFX không lọt vào sim; xuất ảnh chụp từng chiêu ở cỡ thật cho Tín duyệt bằng mắt.

## Nguồn tham khảo đã tra

- Đối chiếu GPUParticles2D/CPUParticles2D trong Godot 4 (mô phỏng GPU bằng ParticleProcessMaterial, turbulence/sub-emitter/trails, visibility_rect, giật biên dịch lần đầu; CPU particles hành vi đồng nhất mọi renderer): https://dev.to/saltmire/gpuparticles2d-vs-cpuparticles2d-in-godot-4-which-and-when-3e1f
- Tài liệu chính thức GPUParticles2D (amount/fixed_fps/trail, chi phí theo tổng amount): https://docs.godotengine.org/en/4.2/classes/class_gpuparticles2d.html
- Ngân sách hạt mobile tham khảo (giảm amount trên mobile, giới hạn hiệu ứng đồng thời): https://deepwiki.com/haowg/GODOT-VFX-LIBRARY/6.2-platform-considerations
