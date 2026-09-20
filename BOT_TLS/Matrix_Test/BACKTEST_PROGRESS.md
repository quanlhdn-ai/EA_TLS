# BOT_TLS — tiến trình backtest phễu (Topic ma trận 216 kịch bản)

File này để **phiên Claude bất kỳ nối lại được công việc** khi phiên cũ hết token
hoặc bị ngắt. Đọc từ trên xuống, làm tiếp từ mục "VIỆC TIẾP THEO".

## Bối cảnh

- Vốn thật: **10.000 USD**. Symbol XAUUSD, dữ liệu **IC Markets** (tai khoan demo IC — thong tin dang nhap KHONG luu trong repo, hoi nguoi dung), terminal `C:\Program Files\MetaTrader 5 IC Markets Global`.
- Data folder IC: `%APPDATA%\MetaQuotes\Terminal\010E047102812FC0C18890992854220E`
- Log tester: `%APPDATA%\MetaQuotes\Tester\010E047102812FC0C18890992854220E\Agent-127.0.0.1-3000\logs\`
- Yêu cầu người dùng: chạy **cả 216 kịch bản đều vào lệnh** (thuận/nghịch xu hướng
  đều vào, không lọc), tạo **nhiều cấu hình CSV khác nhau** để có cái nhìn tổng
  quan trước khi thu hẹp. Tiêu chí chọn: lãi ~10%/tháng với sụt vốn thấp, hoặc sụt
  vốn cao thì lãi phải vượt trội.
- Cách làm: **phễu** — nhiều kịch bản trên 1 tháng trước, loại dần, rồi mới đào sâu.
- Vừa backtest vừa **đối chứng log tìm lỗi vận hành**.

## Công cụ đã dựng (nằm trong scratchpad của phiên, dựng lại được từ mô tả dưới)

- `run_tls.ps1 -Tag <ten> -Matrix <file.csv> [-From -To -Period -Override @("k=v")]`
  Tự kill terminal, ghi .ini **ASCII không BOM**, chạy `/config:`, copy log agent
  (UTF-16) sang UTF-8 thành `out_<Tag>.log`, **xoá .ini** (chứa mật khẩu).
  Base input đọc từ `inputs_359.txt` (48 input của exness_359.set) rồi áp override.
- `tbl.sh out_*.log` — in bảng tóm tắt (lãi%, sụt vốn, số lệnh, thắng%, PF, điểm,
  số rule phát sinh lệnh, số lỗi).
- `an.sh out_X.log` — bung chi tiết một lượt: input thực tế, phân loại lỗi, 3 bảng
  OnTester.
- `gen_matrix.awk` — sinh file ma trận từ `TLS_Matrix_Trend_FIXED.csv`.

## Thay đổi code đã làm (đã compile IC: 0 errors, 6 warnings)

1. Thêm `input string Inp_Matrix_File = "TLS_Matrix_Trend.csv"` → chọn được file ma
   trận lúc chạy. Mặc định giữ nguyên tên cũ nên 2 preset đang chạy không đổi.
   Có `Print("[MATRIX] Dang doc file: ", mfile)` để đối chứng trong log.
2. Thêm `OnTester()` in 3 bảng: thống kê tổng, THUẬN/NGHỊCH HTF, phân tầng 8 nhóm
   HTF×Major×Minor, và bảng từng dòng luật. Dùng bản đồ `position_id -> magic` lấy
   từ deal MỞ lệnh (deal ĐÓNG do stop-out mang magic=0, lọc theo nó sẽ bỏ sót đúng
   những lệnh thua thảm).
3. **Sửa lỗi thật**: vòng trail so sánh SL trên giá thô rồi mới NormalizeDouble khi
   gửi → TRAIL_R nhích watermark mỗi tick, sau làm tròn ra đúng giá cũ → sàn trả
   `[Invalid stops]` lặp mỗi tick, **50.812 lần/tháng**. Nay so sánh trên giá đã
   normalize (`TLS_SMC_CSV_Bot.mq5`, khối `if(new_sl > 0 && new_sl != DBL_MAX)`).

## Phát hiện cấu trúc (quan trọng — đừng test lại)

1. `Inp_No_SL=true` trong BOT_TLS = **KHÔNG CÓ SL**, không phải SL ảo. Nó chỉ xuất
   hiện một chỗ (`order_sl = Inp_No_SL ? 0 : final_sl`) và không có code nào theo
   dõi để đóng lệnh. Hệ quả: `POSITION_SL=0` → `initial_risk=0` → **toàn bộ
   ManageTrades (BE / partial / trail) bị bỏ qua**. Với exness_359
   (`Inp_DailyDrawdownLimit=0`) thì Prop Shield cũng tắt → không còn đường thoát lỗ
   nào. Đây là cơ chế của kết quả −82,6% / sụt vốn 85,2% trên vốn 10.000.
2. `Inp_FlexTP_Enabled=true` ép `tp=0` cho mọi lệnh → **xoá cột TP của CSV**.
3. Cộng lại, với 2 preset đang chạy thì **7/13 cột ma trận là code chết**:
   BE_Trigger_R, Partial_R, Partial_Pct, TP_Strategy, TP_Param, Trail_Strategy, và
   phần SL của Entry_Type. Sweep ma trận **bắt buộc** phải chạy với
   `Inp_No_SL=false` + `Inp_FlexTP_Enabled=false`.
4. `Inp_Entry_Mode=2` (MARKET_ONLY) → **không bao giờ đặt limit tại mép zone**,
   trái với mô tả trong cột Dash_Note của cả 216 dòng. Bằng chứng: ma trận
   F_HYBRID (Entry_Type 5/6) trùng A_R2 **tới từng xu**, vì lot cố định 0,05 và
   entry luôn là giá thị trường nên `entry_zone` không còn ảnh hưởng.
5. File CSV live `TLS_Matrix_Trend.csv` **sai so với Excel gốc**: mất toàn bộ 72
   dòng `Entry_Type=0`. Excel = 72/72/72 (0/1/2), CSV live = 108/108, không có số 0.
   Bản đúng đã dựng: `TLS_Matrix_Trend_FIXED.csv` (**chưa deploy**, chờ người dùng
   quyết).

## Ma trận đã sinh (thư mục `Matrix_Test/`, đã copy vào `Terminal\Common\Files\`)

Tất cả 216 dòng đều vào lệnh (trừ M_X_EXCEL), hướng lấy theo Major (Up→Buy, Down→Sell).

| File | Entry_Type | TP | BE/Partial/Trail | Location_Filter |
|---|---|---|---|---|
| M_A_R2 | 1/2 | FIXED_R 2.0 | không | HTF_ZONE |
| M_B_R1 | 1/2 | FIXED_R 1.0 | không | HTF_ZONE |
| M_C_R3 | 1/2 | FIXED_R 3.0 | không | HTF_ZONE |
| M_D_OPPZONE | 1/2 | OPPOSITE_ZONE 5 | không | HTF_ZONE |
| M_E_MINOR | 3/4 | FIXED_R 2.0 | không | HTF_ZONE |
| M_F_HYBRID | 5/6 | FIXED_R 2.0 | không | HTF_ZONE |
| M_G_BE_TRAIL | 1/2 | FIXED_R 3.0 | BE1R + 50%@1R + TRAIL_R | HTF_ZONE |
| M_H_NOGATE | 1/2 | FIXED_R 2.0 | không | NONE |
| M_I_NOGATE_R3 | 1/2 | FIXED_R 3.0 | không | NONE |
| M_J_NOGATE_R1 | 1/2 | FIXED_R 1.0 | không | NONE |
| M_K_MINOR_NOGATE | 3/4 | FIXED_R 2.0 | không | NONE |
| M_L_NOGATE_TRAIL | 1/2 | FIXED_R 3.0 | BE1R + TRAIL_R | NONE |
| M_X_EXCEL | **đúng bản Excel** (72 dòng đứng ngoài) | FIXED_R 2.0 | không | HTF_ZONE |

## Kết quả VÒNG 1 — tháng 01/2026, M1, every-tick, vốn 10.000

Input: exness_359 + `Inp_No_SL=false` + `Inp_FlexTP_Enabled=false` (Entry_Mode=2).

| Ma trận | Lãi % | Sụt vốn | Lệnh | Thắng % | PF | Rule hoạt động | Lỗi |
|---|---|---|---|---|---|---|---|
| H_NOGATE | +18,76 | 26,8% | 691 | 33,4 | 1,05 | 90/216 | 8 (market closed) |
| E_MINOR | +4,25 | 8,6% | 27 | 40,7 | 1,38 | 15/216 | 2 |
| C_R3 | −1,78 | 15,6% | 65 | 18,5 | 0,93 | 19/216 | 0 |
| B_R1 | −4,50 | 9,8% | 66 | 37,9 | 0,78 | 19/216 | 0 |
| A_R2 | −5,81 | 15,8% | 65 | 23,1 | 0,77 | 19/216 | 0 |
| F_HYBRID | −5,81 | 15,8% | 65 | 23,1 | 0,77 | 19/216 | 0 |
| G_BE_TRAIL | −3,57 | 9,8% | 141 | 71,6 | 0,82 | 19/216 | **50.812** (lỗi trail, đã sửa) |
| X_EXCEL | −12,51 | 16,7% | 46 | 17,4 | 0,39 | 15/216 | 0 |
| D_OPPZONE | −17,60 | 28,8% | 48 | 22,9 | 0,05 | 19/216 | 124 (TP sát giá) |

Đối chứng: cùng dữ liệu, preset exness_359 **nguyên bản** = −82,64%, sụt vốn 85,2%,
82 lệnh, thắng 69,5%, PF 0,15 (cháy tài khoản ngày 2026.02.11).

Kết luận vòng 1:
- Bật SL thật + tắt FlexTP: −82,6% → −5,8%, sụt vốn 85% → 16%. Đòn bẩy lớn nhất,
  và nó **không nằm trong file CSV** mà ở 2 input.
- Bỏ gate HTF_ZONE: 65 → 691 lệnh, 19 → 90 rule, −5,8% → +18,8% (sụt vốn 26,8%).
- Bản Excel gốc **tệ hơn** bản cho vào hết (−12,5% so với −5,8%), tức 72 dòng "đứng
  ngoài" đang bỏ lỡ lệnh Buy có lãi. Mẫu 1 tháng, cần kiểm lại ở vòng dài.
- 1 tháng chỉ đủ để **loại biến thể**, KHÔNG đủ để kết luận thuận/nghịch xu hướng:
  chỉ 15–19/216 dòng luật phát sinh lệnh (trừ H_NOGATE 90/216), và 25/65 lệnh dồn
  vào đúng rule 0.

## VIỆC TIẾP THEO

- [x] **VÒNG 1b XONG** (batch `bpaclqmx3`): 8 ma trận
      {A_R2, C_R3, E_MINOR, H_NOGATE, I_NOGATE_R3, J_NOGATE_R1, K_MINOR_NOGATE,
      L_NOGATE_TRAIL} × Entry_Mode {0 SMART, 2 MARKET}, tháng 01/2026.
      Tag `T1b_<ma tran>_EM<0|2>`.
- [x] **VÒNG 1c XONG** (cùng batch): FlexTP=true + SL thật, {A_R2, H_NOGATE} ×
      Entry_Mode {0,2}. Tag `T1c_..._FLEX`. Đây là tổ hợp CHƯA TỪNG thử: rổ chốt
      lãi nhưng có sàn chặn lỗ.
- [x] **VÒNG 2 XONG** (batch `ba7s30967`).
- [ ] **VÒNG 3**: 3 cấu hình tốt nhất chạy 8 tháng (2026.01.01–2026.09.01), lúc này
      mới đọc bảng phân tầng 216 kịch bản cho ra kết luận thuận/nghịch xu hướng.
- [x] VÒNG 4 ngoài mẫu XONG. Toàn bộ phễu đã chạy xong — xem mục TỔNG KẾT ở cuối file.
      Bài học từ BOT_TLS_GetChart: 19 cấu hình đều "có lãi" trong mẫu 2026 nhưng
      thắng 36–39% ngoài mẫu 2025 = curve-fitting. Không có bước này thì mọi con số
      ở trên vô nghĩa.
- [ ] Chạy thêm cấu hình FTMO (chart M5, `Inp_DailyDrawdownLimit=2.0`) sau khi chốt
      được cấu hình demo.

## Câu hỏi còn treo với người dùng

- Có deploy `TLS_Matrix_Trend_FIXED.csv` đè lên ma trận live không? (chưa trả lời)
- Giới hạn sụt vốn ngày/tổng của FTMO là bao nhiêu? (chưa trả lời)
- Có tạo `EA_TLS/Tools/` (bộ script backtest dùng lại) không? (hỏi 3 lần, chưa quyết)

## Bẫy phải nhớ khi chạy tiếp

1. **MT5 phải đóng** trước khi `/config:` — không thì nó chỉ bật lại cửa sổ cũ và
   có thể tự gắn EA lên chart tài khoản thật.
2. **.ini không được có BOM** — dùng `[System.IO.File]::WriteAllText(..., ASCII)`.
3. `[TesterInputs]` chỉ ghi đè input được liệt kê; input thiếu sẽ **kế thừa lượt
   trước**. Phải liệt kê tường minh mọi input ở mọi lượt.
4. **Đọc lại input thật từ log**, không tin file .ini mình vừa viết.
5. Log agent là **file theo ngày, gom nhiều lượt** — phải cắt từ lần xuất hiện
   CUỐI CÙNG của `Inp_Matrix_File=` trở đi. Thiếu dòng `final balance` = bị cắt
   ngang, phải chạy lại.
6. **Đếm số lệnh trước khi tin con số %.** Dưới ~100 lệnh thì % là nhiễu.
7. Hai kết quả **trùng nhau tới từng xu** = dấu hiệu cấu hình không được áp dụng —
   phải truy nguyên nhân (lần này truy ra là đúng: MARKET_ONLY làm entry_zone vô
   nghĩa).
8. Máy đã tắt ngủ (`powercfg /change standby-timeout-ac 0`, hibernate, monitor,
   disk, và gập nắp không ngủ). **Nhớ khôi phục** khi xong việc.

---

## Kết quả VÒNG 1b/1c — tháng 01/2026, thêm trục Entry_Mode và FlexTP

EM0 = SMART (có đặt limit tại zone), EM2 = MARKET_ONLY. Tất cả đều `Inp_No_SL=false`.

| Cấu hình | Lãi % | Sụt vốn | Lệnh | Thắng % | PF | Điểm | Rule | Lỗi |
|---|---|---|---|---|---|---|---|---|
| I_NOGATE_R3 EM2 | **+87,68** | 27,4% | 691 | 27,1 | 1,23 | 3,24 | 90/216 | 8 |
| H_NOGATE R2 EM2 | +18,76 | 26,8% | 691 | 33,4 | 1,05 | 0,71 | 90/216 | 8 |
| H_NOGATE R2 EM0 FLEX | +8,83 | **4,9%** | 402 | 50,0 | 1,13 | 1,84 | 78/216 | 341 |
| J_NOGATE_R1 EM0 | +10,56 | **5,0%** | 413 | 50,8 | 1,13 | 2,13 | 78/216 | 13 |
| H_NOGATE R2 EM2 FLEX | +10,87 | 11,1% | 691 | 65,6 | 1,08 | 1,00 | 90/216 | 8426 |
| H_NOGATE R2 EM0 | +8,67 | 11,6% | 413 | 33,2 | 1,08 | 0,76 | 78/216 | 13 |
| J_NOGATE_R1 EM2 | +7,33 | 28,6% | 691 | 50,2 | 1,03 | 0,26 | 90/216 | 8 |
| K_MINOR_NOGATE EM2 | +4,65 | 52,1% | 555 | 32,8 | 1,01 | 0,09 | 59/216 | 6 |
| L_NOGATE_TRAIL EM2 | +4,33 | 38,9% | 691 | 49,9 | 1,02 | 0,11 | 90/216 | 14250 |
| E_MINOR EM0 | +0,19 | 2,3% | 11 | 27,3 | 1,07 | 0,09 | 7/216 | 9 |
| A_R2 EM0 | −3,62 | 6,5% | 45 | 22,2 | 0,69 | −0,61 | 14/216 | 0 |
| I_NOGATE_R3 EM0 | −7,39 | 20,4% | 413 | 23,5 | 0,94 | −0,37 | 78/216 | 13 |
| K_MINOR_NOGATE EM0 | −3,13 | 13,7% | 297 | 30,0 | 0,96 | −0,23 | 55/216 | **620** |

### Phân tầng THUẬN/NGHỊCH — lần đầu đủ mẫu (I_NOGATE_R3 EM2, 691 lệnh, 90/216 rule)

| Nhóm | Lệnh | Thắng % | PnL | Kỳ vọng/lệnh |
|---|---|---|---|---|
| THUẬN HTF (Major cùng chiều HTF) | 413 | 31,5 | **+11.295,86** | **+27,35** |
| NGHỊCH HTF | 275 | 20,0 | **−2.598,78** | **−9,45** |

Phân tầng 3 trục: `HTF tăng / Maj tăng / Min tăng` là nhóm mạnh nhất (293 lệnh,
+6.315). Nhóm tệ nhất: `HTF tăng / Maj giảm / Min tăng` (15 lệnh, −1.097) và
`HTF giảm / Maj tăng / Min tăng` (148 lệnh, −1.525) — cả hai đều là Major ngược HTF.

### Lỗi tìm thêm (đối chứng log)

- **Lỗi 2 — retry vô hạn khi thị trường đóng**: sau khi sửa lỗi trail, spam đổi từ
  `[Invalid stops]` sang `[Market closed]`: 14.242 modify hỏng + 3.647 close hỏng
  trong một tháng. Code cũ thử lại mỗi tick. **Đã sửa**: `g_mkt_closed_until` chặn
  5 phút sau mỗi retcode 10018, gác đầu `ManageTrades_Tick()` và `CheckFlexTP()`.
- **Lỗi 3 — chưa sửa**: `M_K_MINOR_NOGATE` ở EM0 mất 612 lệnh limit vì
  `[Invalid stops]` — SL theo Minor protected quá sát giá limit, dưới stops level
  của sàn. Số liệu của K vì vậy không dùng được. Cách sửa nếu cần: kẹp SL/TP theo
  `SYMBOL_TRADE_STOPS_LEVEL` trước khi gửi, hoặc bỏ qua setup có SL quá sát.
- `M_D_OPPZONE`: 124 lệnh hỏng cùng lý do (TP quá sát giá). Biến thể này đã loại.

### Nhận định

- Bỏ gate HTF_ZONE là đòn bẩy lớn nhất trong file CSV; TP dài (R3) + vào Market là
  cấu hình lãi nhất nhưng sụt vốn 27%; TP ngắn (R1) + SMART cho lãi ~10%/tháng với
  sụt vốn 5% — **đúng khẩu vị người dùng mô tả**.
- **Cảnh báo**: +87,68%/tháng là con số bất thường, mới đo trên 1 tháng TRONG MẪU.
  Chưa được tin cho tới khi qua vòng 3 tháng và vòng kiểm ngoài mẫu 2025.

## VÒNG 2 đang chạy (batch `ba7s30967`) — 3 tháng 2026.01.01–2026.04.01

11 cấu hình, tag `T2_*`, gồm cả đối chứng `T2_A_R2_EM2_CTRL`, `T2_X_EXCEL_EM2` và
`T2_359_NGUYENBAN` (exness_359 y nguyên: No_SL=true + FlexTP=true).

---

## Kết quả VÒNG 2 — 3 tháng 2026.01.01–2026.04.01, vốn 10.000

| Cấu hình | Lãi % | Sụt vốn | Lệnh | Thắng % | PF | Rule | Lỗi |
|---|---|---|---|---|---|---|---|
| I_NOGATE_R3 EM2 | **+180,53** | 36,5% | 2124 | 26,6 | 1,13 | 119/216 | 26 |
| H_NOGATE R2 EM2 | +41,29 | **59,9%** | 2124 | 33,2 | 1,03 | 119/216 | 26 |
| **359 nguyên bản + ma trận Excel đúng** | **+29,45** | 20,5% | 122 | 92,6 | 4,74 | 32/216 | 0 |
| J_NOGATE_R1 EM2 | +15,49 | 30,9% | 2124 | 50,0 | 1,02 | 119/216 | 26 |
| H_NOGATE R2 EM0 | +9,08 | 20,8% | 1245 | 32,9 | 1,02 | 109/216 | 36 |
| J_NOGATE_R1 EM0 | +5,72 | 19,3% | 1245 | 49,9 | 1,02 | 109/216 | 36 |
| I_NOGATE_R3 EM0 | +5,05 | 39,1% | 1245 | 24,3 | 1,01 | 109/216 | 36 |
| A_R2 EM2 (giữ gate) | −2,54 | 15,8% | 165 | 32,7 | 0,96 | 36/216 | 0 |
| X_EXCEL EM2 (giữ gate) | −9,63 | 21,2% | 144 | 31,9 | 0,85 | 32/216 | 0 |
| H_NOGATE EM0 + FlexTP | −11,46 | 30,1% | 1216 | 49,0 | 0,96 | 109/216 | 50 |
| H_NOGATE EM2 + FlexTP | −15,22 | 43,1% | 2124 | 66,4 | 0,97 | 119/216 | 80 |

### PHÁT HIỆN LỚN: ma trận hỏng chính là thứ làm cháy tài khoản

Cùng input exness_359 y nguyên (`Inp_No_SL=true`, FlexTP bật, EM2), cùng 3 tháng,
cùng vốn 10.000 — **chỉ khác file ma trận**:

| Ma trận | Kết quả |
|---|---|
| `TLS_Matrix_Trend.csv` (bản live, mất 72 dòng Entry_Type=0) | **−82,64%**, sụt vốn 85,2%, cháy 2026.02.11 |
| `M_X_EXCEL.csv` (đúng bản Excel gốc) | **+29,45%**, sụt vốn 20,5%, 122 lệnh, PF 4,74 |

Tức là bot demo đang chạy sai file cấu hình, và chính 72 dòng bị hỏng đó đã đốt tài
khoản. **Nên deploy `TLS_Matrix_Trend_FIXED.csv`** (chờ người dùng xác nhận). Vẫn
phải kiểm ngoài mẫu trước khi tin: đây là chiến lược rổ lệnh không SL, thắng 92,6%
là kiểu lãi nhỏ đều rồi trả hết trong vài lệnh.

### Những thứ KHÔNG trụ được qua 3 tháng (loại)

- **FlexTP + SL thật**: 1 tháng cho +8,8%/+10,9% với sụt vốn ~5%, sang 3 tháng
  thành −11,5%/−15,2%. Loại.
- **J_NOGATE_R1 EM0** (ứng viên "10%/tháng sụt vốn 5%"): 3 tháng chỉ +5,72% và sụt
  vốn nở từ 5,0% lên 19,3%. Loại khỏi nhóm khẩu vị thấp rủi ro.
- **H_NOGATE R2 EM2**: lãi +41,29% nhưng sụt vốn **59,9%** — không dùng được với
  vốn thật.

### Phân tầng THUẬN/NGHỊCH — 2118 lệnh, hai cấu hình TP khác nhau cùng kết luận

| | I_NOGATE_R3 EM2 | H_NOGATE_R2 EM2 |
|---|---|---|
| THUẬN HTF (1104 lệnh) | thắng 30,3% · PnL +27.361 · **kỳ vọng +24,78** | thắng 36,1% · PnL +13.673 · **kỳ vọng +12,38** |
| NGHỊCH HTF (1014 lệnh) | thắng 22,4% · PnL −8.906 · **kỳ vọng −8,78** | thắng 29,9% · PnL −9.141 · **kỳ vọng −9,02** |

Phân tầng 8 nhóm, hai cấu hình xếp hạng **giống nhau**:

| Nhóm (HTF · Major · Minor) | Lệnh | Kỳ vọng R3 | Kỳ vọng R2 |
|---|---|---|---|
| giảm · giảm · giảm | 458 | **+39,85** | **+26,14** |
| tăng · tăng · giảm | 28 | +53,55 | +32,65 |
| giảm · giảm · tăng | 31 | +31,70 | +12,98 |
| giảm · tăng · giảm | 38 | +13,57 | +12,36 |
| tăng · tăng · tăng | 587 | +11,29 | +0,65 |
| tăng · giảm · giảm | 285 | −5,00 | −12,17 |
| giảm · tăng · tăng | 661 | **−8,69** | **−6,99** |
| tăng · giảm · tăng | 30 | **−75,13** | **−50,75** |

Bốn nhóm âm đều là **Major ngược chiều HTF**, trừ nhóm `tăng·giảm·giảm`. Hai nhóm
đủ mẫu và âm nặng: `giảm·tăng·tăng` (661 lệnh) và `tăng·giảm·giảm` (285 lệnh).
=> Bằng chứng nhất quán: **lọc bỏ các dòng Major ngược chiều HTF**. Nhưng phải chờ
vòng ngoài mẫu xác nhận, vì đây vẫn là dữ liệu trong mẫu.

### Lỗi vận hành sau khi vá

Số lỗi rơi từ 8.426–14.250 xuống **26–80 mỗi lượt 3 tháng** (chỉ còn `[Market
closed]` lác đác và vài lệnh trượt). Bản vá backoff hoạt động đúng.

---

## VÒNG NGOÀI MẪU (2025.02.01–2026.01.01, 11 tháng) — mọi ứng viên đều TRƯỢT

| Cấu hình | Lãi % | Sụt vốn | Lệnh | Thắng % | PF |
|---|---|---|---|---|---|
| exness_359 + ma trận **Excel đúng** | **−81,62** | 89,7% | 608 | 81,7 | 0,68 |
| exness_359 + ma trận live (hỏng) | −82,03 | 85,5% | 255 | 79,6 | 0,35 |
| I_NOGATE_R3 EM2 | +9,53 | 58,9% | 7909 | 25,6 | **1,00** |
| H_NOGATE_R2 EM2 | −25,33 | 64,4% | 7909 | 33,7 | 0,99 |
| J_NOGATE_R1 EM2 | −54,13 | 64,7% | 7909 | 49,2 | 0,96 |

**ĐÍNH CHÍNH quan trọng**: `+29,45%` của ma trận Excel đúng ở vòng 3 tháng là **may
mắn cửa sổ**. Trên 11 tháng 2025 nó cháy y hệt bản hỏng (−81,6% so với −82,0%).
Sửa file CSV vẫn nên làm vì nó đúng thiết kế của người dùng, nhưng **không** phải
lời giải cho việc cháy tài khoản — nguyên nhân gốc là chạy rổ lệnh không SL.

## PHÁT HIỆN TÁI LẬP ĐƯỢC: thuận xu hướng khung lớn

Dấu giữ nguyên qua 2 giai đoạn, 2 mức TP, tổng ~10.000 lệnh:

| | 2026 trong mẫu (2.118 lệnh) | 2025 ngoài mẫu (7.909 lệnh) |
|---|---|---|
| THUẬN HTF | kỳ vọng +24,78 / +12,38 | +1,58 / +0,47 |
| NGHỊCH HTF | −8,78 / −9,02 | −1,24 / −0,85 |

Cảnh báo: **độ lớn sụt 15 lần** giữa hai giai đoạn, và **xếp hạng chi tiết 8 nhóm
KHÔNG tái lập** (nhóm giảm·giảm·giảm tốt nhất 2026 với +39,85 lại âm nhẹ 2025 với
−0,12). Chỉ phép chia thô thuận/nghịch là bền.

## MA TRẬN THUẬN XU HƯỚNG (M_P_TREND_R3 / M_Q_TREND_R2)

108 dòng vào lệnh (Major cùng chiều HTF), 108 dòng đứng ngoài. Không gate, không BE,
không trail, TP FIXED_R.

| Cấu hình | Giai đoạn | Lãi % | Sụt vốn | Lệnh | Thắng % | PF |
|---|---|---|---|---|---|---|
| P_TREND **R3** | 2026 trong mẫu (8 th) | +367,04 | 28,3% | 3510 | **27,2** | 1,22 |
| P_TREND **R3** | 2025 **ngoài mẫu** (11 th) | **+69,33** | 37,9% | 4823 | **26,2** | 1,06 |
| Q_TREND **R2** | 2026 trong mẫu (8 th) | +178,17 | 38,9% | 3510 | **34,4** | 1,12 |
| Q_TREND **R2** | 2025 **ngoài mẫu** (11 th) | **+22,35** | 37,9% | 4823 | **34,1** | 1,02 |
| I_NOGATE_R3 (đối chứng, cả 216) | 2026 trong mẫu (8 th) | +190,50 | 36,5% | 5686 | 25,5 | 1,07 |

**Tỷ lệ thắng gần như trùng nhau giữa trong mẫu và ngoài mẫu** (27,2 vs 26,2 và
34,4 vs 34,1) — ngược hẳn dấu vân tay curve-fitting của BOT_TLS_GetChart (53–68%
trong mẫu so với 36–39% ngoài mẫu). Lọc bỏ nghịch xu hướng cải thiện **cả hai** mặt
ngoài mẫu: lãi +9,53% → +69,33% và sụt vốn 58,9% → 37,9%.

Vẫn chưa dùng được: sụt vốn 37,9% quá xa tiêu chí "sụt vốn thấp", và độ lớn lãi
chênh 5 lần giữa hai giai đoạn (45,9%/tháng trong mẫu so với 6,3%/tháng ngoài mẫu).

## VÒNG 5 đang chạy (batch `bp9652s0s`)

1. `T5_P_R3_2024` — **cửa sổ thứ ba chưa từng đụng tới** (2024.02–2025.02).
2. `T5_P_R3_LOT002_OOS` — hạ lot 0,05 → 0,02 để kéo sụt vốn xuống.
3. `T5_P_R3_RISK05_OOS` — sizing theo % rủi ro thay vì lot cố định.
4. `T5_P_R3_SHIELD2_OOS` — bật lá chắn sụt vốn ngày 2% (kiểu FTMO).
5. `T5_P_R3_M5_OOS` — chart M5 (cấu hình ftmo đang chạy M5).

---
---

# TỔNG KẾT — 90 lượt backtest, dữ liệu IC Markets XAUUSD, every-tick

## 1. BẢNG KỊCH BẢN ĐỀ XUẤT (thay cho exness_359.set và ftmo.set)

**Nền chung — khác 2 preset hiện tại ở 4 điểm:**

| Thiết lập | Hiện tại | Đề xuất | Lý do |
|---|---|---|---|
| `Inp_No_SL` | `true` | **`false`** | `true` = không có SL nào cả (không phải SL ảo) |
| `Inp_FlexTP_Enabled` | `true` | **`false`** | `true` xoá cột TP của CSV → 7/13 cột ma trận thành code chết |
| Chart | M1 (359) / M5 (ftmo) | **M5** | M1 lỗ 2023 và 2024; M5 dương 3/4 năm |
| Ma trận | `TLS_Matrix_Trend.csv` (hỏng) | **`M_I_NOGATE_R3.csv`** — 216 dòng vào hết, `Location_Filter=NONE`, `TP_Strategy=FIXED_R 3.0` | tổ hợp duy nhất sống qua 4 năm |

Giữ nguyên: `Inp_Entry_Mode=2`, `UseRiskPerTrade=false`, `Inp_DailyDrawdownLimit=0`,
`HTF_Timeframe=M15`, `Trend_Timeframe=H1`, `MaxZones=1`.

**Ba mức khẩu vị rủi ro — chỉ khác `FixedLotSize`.** Đo trên 43 tháng LIÊN TỤC
(2023.02.01–2026.09.01), vốn 10.000, một lượt chạy duy nhất:

| Kịch bản | Lot | Lãi/tháng | Sụt vốn | 43 tháng | Lệnh | Thắng | PF |
|---|---|---|---|---|---|---|---|
| Tăng trưởng | 0,05 | **10,41%** | 42,25% | 10.000 → 54.718 | 6031 | 27,2% | 1,15 |
| Cân bằng | 0,03 | 6,23% | 27,19% | 10.000 → 36.808 | 6031 | 27,2% | 1,15 |
| Thận trọng | 0,02 | 4,17% | **18,77%** | 10.000 → 27.910 | 6031 | 27,2% | 1,15 |

Cùng một chiến lược phóng to/thu nhỏ tuyến tính. Mốc 10%/tháng **đạt được**, giá
phải trả là sụt vốn 42% — không tách rời hai con số này được.

**KHÔNG bật lá chắn sụt vốn ngày 2%**: ở lot 0,02 nó kéo lãi +179% → +138% mà sụt
vốn còn nhích lên (19,29% so với 18,77%). Nó cắt lệnh đúng vào ngày đảo chiều.

## 2. HAI PRESET HIỆN TẠI TRÊN CÙNG 43 THÁNG

| Preset | Kết quả | Sụt vốn | Lệnh | Ghi chú |
|---|---|---|---|---|
| `exness_359` (M1, ma trận live) | 10.000 → **429,57** (−95,70%) | 96,11% | 167 | **cháy sau 1,6 tháng** |
| `ftmo` (M5, ma trận live) | 10.000 → 11.009 (+10,10%) | 8,39% | **38** | chỉ 38 lệnh / 43 tháng → % là nhiễu (bẫy 6) |
| `ftmo` (M5, ma trận Excel đúng) | 10.000 → 7.024 (−29,76%) | 40,50% | 233 | PF 0,76 |

## 3. TRẢ LỜI CÂU HỎI PHÂN TẦNG 216 KỊCH BẢN

Kết luận **phụ thuộc khung chart** — đây chính là lý do phải cho chạy hết không lọc:

| Khung | THUẬN HTF | NGHỊCH HTF | Kết luận |
|---|---|---|---|
| M1, 2026 (2.118 lệnh) | kỳ vọng +24,78 / +12,38 | −8,78 / −9,02 | nên lọc bỏ nghịch |
| M1, 2025 (7.909 lệnh) | +1,58 / +0,47 | −1,24 / −0,85 | nên lọc bỏ nghịch |
| **M5, 43 tháng (6.031 lệnh)** | **+7,17** | **+7,89** | **KHÔNG nên lọc** |

Ở M5, nghịch xu hướng còn nhỉnh hơn thuận. Bộ lọc thuận-xu-hướng kiểm chứng trực
tiếp: trên M5 nó **thua** bản chạy hết ở **cả 4 năm** (2024 +35,14 vs +43,25;
2025 +101,84 vs +184,93; 2026 +232,38 vs +244,43; sụt vốn cũng xấu hơn).
=> Yêu cầu "cho vào lệnh hết, không lọc gì" của người dùng là ĐÚNG. Nếu lọc trước
khi đo thì đã kết luận sai.

Xếp hạng chi tiết 8 nhóm 3 trục **không tái lập** giữa các giai đoạn (nhóm
giảm·giảm·giảm tốt nhất 2026 với +39,85 lại âm nhẹ 2025 với −0,12). Không dùng
được để chọn kịch bản.

## 4. BA LỖI CODE ĐÃ SỬA (đều compile 0 errors)

1. **Trail so sánh SL trên giá thô** → `[Invalid stops]` lặp mỗi tick, 50.812
   lần/tháng. Sửa: so sánh trên giá đã `NormalizeDouble`.
2. **Retry vô hạn khi thị trường đóng** trong `ManageTrades_Tick` và `CheckFlexTP`
   → 14.242 modify + 3.647 close hỏng/tháng. Sửa: `g_mkt_closed_until` chặn 5 phút
   sau mỗi retcode 10018.
3. **Cùng lỗi đó ở `CheckPoolSL`** → 3.087 close hỏng trên lượt ftmo. Sửa tương tự.

Chưa sửa (chờ người dùng quyết vì đổi hành vi gửi lệnh live): SL/TP quá sát giá
dưới `SYMBOL_TRADE_STOPS_LEVEL` làm mất lệnh — 612 lệnh với ma trận SL-theo-Minor,
124 lệnh với TP `OPPOSITE_ZONE`.

Đã thêm: `input string Inp_Matrix_File` (mặc định giữ tên cũ) và `OnTester()`.

## 5. BA CẢNH BÁO TRƯỚC KHI DÙNG VỐN THẬT

1. **Sụt vốn 42% (hoặc 19% bản thận trọng) rơi vào NĂM ĐẦU.** 2023 lỗ −16,2%. Vào
   tiền đầu 2023 là mất 42% vốn trước khi thấy đồng lãi nào.
2. **PF 1,15 trên 6.031 lệnh là lợi thế mỏng và phụ thuộc chế độ thị trường.** PF
   theo năm: 0,95 (2023) → 1,08 (2024) → 1,21 (2025) → 1,19 (2026). Hai năm lãi
   lớn trùng đúng giai đoạn vàng chạy xu hướng mạnh.
3. **Toàn bộ số liệu từ MỘT sàn, MỘT cặp tiền.** Chưa kiểm symbol khác hay sàn
   khác — đây là phép thử còn thiếu quan trọng nhất, và là phép thử duy nhất còn
   lại có thể bác bỏ kết luận trên.

## 6. VIỆC CÒN TREO — cần người dùng quyết

- [ ] Deploy `TLS_Matrix_Trend_FIXED.csv` đè ma trận live? (bản live mất 72 dòng
      `Entry_Type=0`; nhưng đã chứng minh sửa nó KHÔNG cứu được tài khoản, vì
      nguyên nhân gốc là chạy rổ lệnh không SL)
- [ ] Có kẹp SL/TP theo `SYMBOL_TRADE_STOPS_LEVEL` không? (đổi hành vi live)
- [ ] Có tạo `EA_TLS/Tools/` (bộ script backtest dùng lại) không? (hỏi 4 lần)
- [ ] Giới hạn sụt vốn ngày/tổng của FTMO là bao nhiêu?
- [ ] Có chạy kiểm trên symbol khác / sàn khác không? (cảnh báo số 3)

---

## BỔ SUNG 09/09/2026 — quyết định của người dùng và kết quả kèm theo

### Quyết định
1. Ma trận CSV: **KHÔNG deploy** bản FIXED. Giữ nguyên file live.
2. Lỗi SL/TP: **có sửa**.
3. Kiểm chéo symbol/sàn khác: **chưa cần** (cảnh báo số 3 vẫn còn nguyên giá trị).
4. FTMO: giới hạn **4% ngày / 8% tổng**.

### Lỗi 4 đã sửa — nhưng NGUYÊN NHÂN KHÁC hẳn chẩn đoán ban đầu

Chẩn đoán sai ban đầu: "SL/TP quá sát giá, dưới stops level". Bản vá đầu tiên theo
hướng đó **không có tác dụng nào** — kết quả trùng khít tới từng xu (dấu hiệu bẫy 4).
Truy log ra lệnh hỏng thật:

    failed buy limit 0.05 XAUUSD at 4390.17  sl: 4393.00  tp: 4395.83  [Invalid stops]

Lệnh **Buy** mà **SL nằm CAO HƠN giá vào**. Không phải khoảng cách, mà là **SL sai
phía**. Ma trận SL-theo-Minor-protected sinh ra mốc bảo vệ nằm ngược phía mép zone.
Thêm nữa: IC Markets có `SYMBOL_TRADE_STOPS_LEVEL = 0`, nên dòng
`if(lvl <= 0) return stop;` trong bản vá đầu làm hàm thoát ngay, không chạm gì.

Bản vá đúng (`ClampStopLevel`, `TLS_SMC_CSV_Bot.mq5`):
- Mốc đúng phía nhưng quá sát → đẩy ra tối thiểu `max(stops_level, 1 point)`.
- **SL sai phía → trả −1, bỏ qua setup.** Kẹp lại sẽ tạo SL rộng 1 point = lệnh
  cầm chắc thua ngay, tệ hơn không vào.
- TP sai phía → chỉ bỏ TP (trả 0), vẫn vào lệnh.
Kèm 6 chốt chặn tại 6 điểm gửi lệnh.

**Kết quả kiểm chứng — bản vá KHÔNG cải thiện hiệu quả:**

| | Lỗi | Invalid stops | Lệnh | Lãi % | Sụt vốn | PF |
|---|---|---|---|---|---|---|
| Trước vá | 620 | 612 | 297 | −3,13 | 13,66% | 0,96 |
| Sau vá | **8** | **0** | **297** | −3,13 | 13,66% | 0,96 |

612 lệnh đó trước nay bị sàn từ chối nên chưa bao giờ vào thị trường; nay bot chủ
động không gửi. Số lệnh khớp thật vẫn đúng 297 cả hai bên. **Đây là bản vá làm sạch
log và đúng logic, không phải bản vá cải thiện kết quả.** Ghi lại để sau này không
ai tưởng nhầm là đã "cứu được 612 lệnh".

Hồi quy trên cấu hình đề xuất (M5, 2025): **184,93% / sụt vốn 21,86% / 1569 lệnh** —
trùng khít lượt trước khi sửa. Bản vá không làm hỏng gì.

### FTMO 4%/8% — cấu hình đề xuất KHÔNG đạt trên tài khoản 10.000

| Lot | Lãi 43 tháng | Sụt vốn balance | Sụt vốn equity | Lá chắn ngày 4% |
|---|---|---|---|---|
| 0,02 | +184,85% | 11,82% | 18,77% | gần như không kích hoạt |
| **0,01** (nhỏ nhất sàn cho) | **+88,95%** | **9,00%** | **10,88%** | **không kích hoạt lần nào** |

Ở lot nhỏ nhất, sụt vốn balance 9,00% vẫn **vượt ngưỡng 8% tổng**. Lá chắn ngày 4%
không kích hoạt lần nào (kết quả trùng khít bản không bật) → các cú sụt vốn tích tụ
qua nhiều ngày, giới hạn ngày không chặn được.

Không phải lỗi tham số mà là **chạm sàn bước lot**. Muốn vừa khít 8% cần khoảng
**13.600 USD vốn cho mỗi 0,01 lot**. Với gói FTMO 25.000 hoặc 50.000 thì con số này
nằm trong tầm — cần người dùng cho biết gói dự định để chạy lại đúng quy mô.

---
---

# 10/09/2026 — DÒ THAM SỐ SWING BA KHUNG: KẾT QUẢ ÂM TÍNH

137 lượt chạy. Mục tiêu: tìm bộ `PeriodsInMajorSwing` tốt nhất cho ba khung của
cấu hình `exness_359` sau khi đổi Trend H1→M15 và HTF M15→M5.

## Quy trình đã làm

Tuần tự theo yêu cầu người dùng: chốt M15 → dò M5 với M15 đã chốt → dò M1 với cả
hai đã chốt. Mỗi giá trị chấm điểm trên **bốn cửa sổ 18/06–09/09 của 2023, 2024,
2025, 2026** (cùng độ dài, cùng mùa, mỗi cửa sổ vốn 10.000).

Kết quả tuần tự: **M15 = 10, M5 = 10, M1 = 10**, tổng bốn cửa sổ **+139,25%**,
dương **4/4**, sụt vốn tối đa **15,5%** — so với cấu hình đang chạy có sụt vốn 74,8%.
Đỉnh rộng 4 giá trị (M15 9–12), vùng phẳng M1 rộng từ 10 đến 20.

## Phép kiểm cuối đã phá hỏng tất cả

Chạy **liên tục 20 tháng** 2025.01.01 → 2026.09.10, cùng vốn 10.000:

| Bộ | M15 | M5 | M1 | Lãi | Sụt vốn | Balance cuối | Hết tiền lúc |
|---|---|---|---|---|---|---|---|
| A (bộ tuần tự chốt) | 10 | 10 | 10 | **−85,60%** | 86,98% | 1.440 | 22/01/2025 |
| B (vùng sụt vốn thấp) | 10 | 13 | 16 | **−86,05%** | 86,89% | 1.395 | 22/01/2025 |
| GỐC (đang chạy thật) | H1·3 | M15·5 | M1·9 | **−86,85%** | 87,70% | 1.315 | 22/01/2025 |

**Cả ba cháy trong 20 ngày** (02/01 → 22/01/2025), rồi 38–360 lệnh bị từ chối vì
`[No money]` suốt 19 tháng còn lại. Bộ "tốt nhất" chỉ hơn cấu hình đang chạy 1,25
điểm phần trăm — nằm trong nhiễu.

## VÌ SAO 104 LƯỢT TRƯỚC ĐÓ NÓI DỐI — BẪY THỨ 8

Mỗi cửa sổ test **bắt đầu lại với 10.000 mới**, và cả bốn đều nằm trong khoảng
18/06–09/09. Thua lỗ của các tháng ngoài mùa đó **không bao giờ được cộng dồn**.
Bộ tham số tìm được là "bộ sống sót qua bốn mùa hè", không phải "bộ có lợi thế".
Tháng 01/2025 chưa từng được test, và chính nó xoá sổ cả ba bộ.

=> **Quy tắc mới: kết luận cuối cùng phải đến từ MỘT lượt chạy liên tục.** Nhiều
cửa sổ rời rạc chỉ dùng để loại nhanh, không bao giờ dùng để chốt. Cộng lãi của các
cửa sổ reset vốn là phép cộng vô nghĩa.

## Những gì vẫn còn giá trị

- Tham số swing của khung M15 **hầu như không tác động**: ở các cửa sổ 2023, 2024,
  2026 các giá trị 8–13 cho kết quả gần y hệt (2026: 47,85 / 47,85 / 47,85 / 47,86
  / 47,86 / 47,83). Toàn bộ khác biệt dồn vào đúng một tình huống ở hè 2025.
- Các giá trị nhỏ (M5 1–7, M1 1–7) cho sụt vốn 80–92% ở mọi cửa sổ; các giá trị lớn
  (M5 10–16, M1 10–20) cho 12–29%. Xu hướng này nhất quán và có thể vẫn đúng — nhưng
  nó chỉ làm chậm cái chết, không ngăn được.
- Nguyên nhân gốc vẫn nguyên vẹn: `Inp_No_SL=true`. Không có tham số swing nào cứu
  được một rổ lệnh không có sàn chặn lỗ.

## Việc còn treo

- [ ] Chạy lại phễu dò tham số này TRÊN NỀN có SL thật (`Inp_No_SL=false`) — đó là
      phép thử duy nhất còn ý nghĩa cho hướng đi này.
- [ ] Gói FTMO: người dùng chốt vốn 10.000, chưa quyết thời điểm.

---
---

# 12/09/2026 — PHỄU SWING TRÊN NỀN CÓ SL THẬT: CÓ LỜI GIẢI, MỎNG

Chạy lại phễu dò `PeriodsInMajorSwing` ba khung với `Inp_No_SL=false`.

## Công cụ mới trong Tools/

- `Run-Backtest.ps1 -Range "Ten=batdau:buoc:ketthuc"` → MT5 chạy **optimization song
  song trên mọi nhân CPU**, báo cáo XML được parse thành `logs/opt_<Tag>.csv`.
  Nhanh gấp ~2,7 lần chạy tuần tự (i5-1235U, 12 luồng, U-series nên bị giảm xung).
- `Funnel-Swing.ps1` — dò tuần tự nhiều input, **tự chọn giá trị giữa các giai đoạn**
  theo điểm bền vững (điểm thấp nhất trong cửa sổ 3 ô liền kề → ưu tiên vùng phẳng).
- `BacktestLib.ps1` — `Get-RunMetrics` dùng chung.

**BẪY MỚI: báo cáo optimization của MT5 HAY BỎ SÓT TỔ HỢP.** Ba lần liên tiếp:
17/19, 18/19, 5/8, 6/8 — và lần nào cũng thiếu đúng tổ hợp quan trọng nhất. Luôn
đếm số dòng trong CSV; thiếu thì chạy bù bằng lượt đơn lẻ.

## Kết quả phễu (cửa sổ chọn: 10/2024–10/2025 liên tục, 12 tháng)

Mọi giá trị ở cả ba giai đoạn đều LỖ khi `Inp_FlexTP_Enabled=true`:
M15 quét 18 giá trị → −8% đến −18%; M5 quét 17 → −6% đến −27%; M1 quét 18 → −3%
đến −31%. Bộ tốt nhất **M15=9, M5=12, M1=16** cho −2,93% (PF 0,977).

**Nghi phạm tìm ra: `Inp_FlexTP_Enabled=true` kết hợp SL thật tạo bất đối xứng
ngược** — FlexTP đóng cả rổ khi tổng lãi chạm 1% balance (chặn trần phần thắng),
còn mỗi lệnh thua vẫn chạy đủ tới SL. Tắt nó đi:

| Bộ swing | FlexTP bật | FlexTP tắt |
|---|---|---|
| 9/12/16 | −2,93% · PF 0,977 | **+16,00% · PF 1,082** |
| 3/5/9 (gốc) | −17,75% · PF 0,923 | −6,20% · PF 0,981 |

## Kiểm ngoài mẫu (SL thật + FlexTP tắt)

| Đoạn | 9/12/16 | 3/5/9 gốc |
|---|---|---|
| 02/2023–10/2024 (20th, ngoài mẫu) | −9,32% · PF 0,960 · DD 17,6% | −48,18% · PF 0,870 · DD 49,9% |
| 10/2024–10/2025 (12th, trong mẫu) | +16,00% · PF 1,082 · DD 14,4% | −6,20% · PF 0,981 · DD 30,4% |
| 10/2025–09/2026 (11th, ngoài mẫu) | +43,13% · PF 1,158 · DD 17,9% | −36,68% · PF 0,926 · DD 77,6% |

## KẾT LUẬN — chạy LIÊN TỤC 43 tháng (2023.02.01 → 2026.09.12), vốn 10.000

| M15/M5/M1 | Lãi | Sụt vốn eq | Lệnh | PF | Vốn cuối |
|---|---|---|---|---|---|
| **9/12/16** | **+49,23%** | **23,8%** | 3731 | **1,070** | **14.923** |
| 9/5/16 | +7,34% | 37,3% | 4859 | 1,008 | 10.734 |
| 3/5/16 | +1,18% | 45,2% | 5045 | 1,001 | 10.118 |
| 3/12/16 | −17,63% | 48,2% | 3984 | 0,977 | 8.237 |
| 9/5/9 | −41,82% | 72,0% | 7526 | 0,963 | 5.818 |
| **3/5/9 (đang chạy demo)** | **−98,02%** | 98,0% | 7171 | 0,901 | **198** |
| 3/12/9 | −98,43% | 98,4% | 5663 | 0,887 | 157 |

**Bộ cấu hình đề xuất** (khác preset `exness_359` đang chạy ở 5 điểm):
`Inp_No_SL=false`, `Inp_FlexTP_Enabled=false`, `Trend_Timeframe=M15` (từ H1),
`HTF_Timeframe=M5` (từ M15), và swing `Trend=9 / HTF=12 / Chart=16` (từ 3/5/9).

- Lãi 1,14%/tháng ở lot cố định 0,05 — **không đạt mốc 10%/tháng người dùng muốn**.
  Muốn 10%/tháng phải nhân lot ~9 lần → sụt vốn vượt 100% → bất khả thi.
- `PeriodsInMajorSwing` (khung chart) là trục quyết định: mọi tổ hợp có 16 đều dương
  hoặc gần hoà; mọi tổ hợp có 9 đều mất 42–98%. Chênh lệch tới 90 điểm.
- PF 1,070 trên 3731 lệnh là lợi thế **thật nhưng mỏng**, và một đoạn 20 tháng
  (2023–2024) vẫn âm.

**So với hướng khác đã thử:** cấu hình chart M5 + bỏ gate HTF + TP 3R + cả 216 kịch
bản cho **+447% / PF 1,15 / DD 42,25%** trên cùng 43 tháng — lãi cao hơn nhiều,
nhưng sụt vốn gần gấp đôi. Hai hướng này chưa từng được ghép với nhau.

## Việc còn treo

- [ ] Ghép hai hướng: chart M5 + ma trận bỏ gate TP 3R + bộ swing vừa tìm được.
- [ ] Kiểm trên symbol/sàn khác (cảnh báo cũ, chưa làm).
- [ ] FTMO 10.000: người dùng chốt vốn, chưa quyết thời điểm.

---

## GHÉP HAI HƯỚNG (12/09/2026) — chart M5 + ma trận không gate + bộ swing mới

Nền: chart **M5**, ma trận `M_I_NOGATE_R3` (216 dòng vào hết, `Location_Filter=NONE`,
TP `FIXED_R 3.0`), `Inp_No_SL=false`, `Inp_FlexTP_Enabled=false`, `Entry_Mode=2`,
lot 0,05. Lưới 2×2×2 trên swing, chạy liên tục 43 tháng 2023.02.01 → 2026.09.12.

### Phát hiện: ở cấu hình này chỉ CHART swing có tác dụng

Sáu tổ hợp cho đúng **hai** kết quả: mọi tổ hợp chart=9 trùng khít nhau, mọi tổ hợp
chart=16 trùng khít nhau, bất kể `Trend_PeriodsInMajorSwing` và
`HTF_PeriodsInMajorSwing`. Không phải lỗi chạy mà là hệ quả logic: ma trận cho cả
216 dòng vào lệnh với hướng theo Major, và gate HTF tắt → **trạng thái HTF và Minor
không còn ảnh hưởng quyết định nào**. Hai tầng phân tích trên chỉ còn trang trí.
=> Dùng ma trận không gate thì khỏi tinh chỉnh Trend/HTF swing.

### Kết quả (43 tháng liên tục, vốn 10.000)

| Chart swing | Lãi | Lãi/tháng | Sụt vốn tương đối | Lệnh | Thắng | PF |
|---|---|---|---|---|---|---|
| 9 | +447,18% | 10,41% | **42,25%** | 6031 | 27,2% | 1,15 |
| **16** | +433,63% | **10,01%** | **33,02%** | 3722 | 27,9% | **1,17** |

Swing 16 giữ 96% lợi nhuận với 78% mức sụt vốn. Tỷ lệ lãi-tháng trên sụt vốn:
0,303 so với 0,246 — **cải thiện 23% về rủi ro-điều chỉnh**.

### BẪY ĐO LƯỜNG (quan trọng)

Cột `Equity DD %` trong báo cáo optimization của MT5 là **sụt vốn equity TUYỆT ĐỐI**
(`STAT_EQUITYDD_PERCENT`), KHÔNG phải tương đối. Với cấu hình này: tuyệt đối 18,2%
nhưng tương đối 42,25% — lệch hơn gấp đôi. Đặt bảng optimization cạnh bảng OnTester
mà không kiểm sẽ kết luận sai về rủi ro. Muốn con số tương đối phải chạy lượt đơn lẻ.

### Bẫy vận hành mới

Hai lần liên tiếp lượt chart=9 bị `tester forced to close` sau đúng ~3,4 phút, log có
`prepare for shutdown` giữa lúc bot đang giao dịch bình thường rồi `login (build 6182)`
— terminal bị yêu cầu tắt từ bên ngoài (nhiều khả năng MT5 tự cập nhật), không phải
lỗi bot. Số liệu lấy lại từ lượt đo trước đó cùng cấu hình.

## BẢNG TỔNG SO SÁNH — cùng 43 tháng liên tục, cùng vốn 10.000

| Cấu hình | Lãi/tháng | Sụt vốn tương đối | PF |
|---|---|---|---|
| **M5 · không gate · TP 3R · chart swing 16** | **10,01%** | **33,0%** | **1,17** |
| M5 · không gate · TP 3R · chart swing 9 | 10,41% | 42,3% | 1,15 |
| M1 · ma trận live · swing 9/12/16 | 1,14% | 23,8% | 1,07 |
| M1 · ma trận live · swing 3/5/9 (demo đang chạy) | −2,28% | 98,0% | 0,90 |

**Cấu hình đề xuất cuối cùng cho tới thời điểm này: dòng đầu bảng.** Đạt đúng mốc
~10%/tháng người dùng nêu từ đầu topic, với sụt vốn 33% — cao hơn mong muốn nhưng là
mức thấp nhất trong các cấu hình đạt được mốc lãi đó.

### Còn treo
- [ ] Kiểm ngoài mẫu riêng cho chart swing 16 (hiện mới có lượt liên tục trọn 43 tháng).
- [ ] Kiểm trên symbol/sàn khác.
- [ ] FTMO 10.000.

---

## 13/09/2026 — KIỂM CHỨNG CẤU HÌNH M5: ĐẠT CẢ BA PHÉP KIỂM

Cấu hình: chart **M5**, ma trận `M_I_NOGATE_R3`, `Inp_No_SL=false`,
`Inp_FlexTP_Enabled=false`, `Entry_Mode=2`, lot 0,05, `PeriodsInMajorSwing=16`.

### 1. Vùng phẳng (43 tháng liên tục) — ĐẠT

| Chart swing | Lãi | Lệnh | PF |
|---|---|---|---|
| 12 | +265,39% | 4731 | 1,096 |
| 14 | +411,19% | 4139 | 1,160 |
| **16** | +433,63% | 3722 | 1,173 |
| 20 | +422,63% | 3055 | 1,192 |

Dải 14–20 đều PF 1,16–1,19. **16 không phải đỉnh nhọn.** Ranh giới dưới của vùng
lành nằm giữa 12 và 14.

### 2. Ngoài mẫu đoạn gần (10/2025 → 09/2026, 11 tháng) — ĐẠT MẠNH

Cả 5 giá trị dương, PF 1,11–1,21. Swing 16: +276,82%, PF **1,199** — cao hơn PF của
lượt 43 tháng (1,173). Dấu hiệu ngược hẳn với curve-fitting.

### 3. Ngoài mẫu đoạn xa (02/2023 → 10/2024, 20 tháng) — ĐẠT, MỎNG

| Chart swing | Lãi | Lãi/tháng | Sụt vốn tương đối | Lệnh | PF |
|---|---|---|---|---|---|
| 14 | +7,28% | 0,36% | — | 1866 | 1,013 |
| **16** | **+40,98%** | 2,05% | 33,02% | 1670 | **1,08** |
| 20 | +51,83% | 2,60% | 34,95% | 1394 | 1,11 |

Không giá trị nào âm, nhưng đây là chế độ thị trường mà chiến lược chỉ kiếm được
~2%/tháng. **Đây mới là kỳ vọng thực tế cho giai đoạn xấu**, không phải 10%/tháng.

### Hồ sơ đầy đủ của cấu hình đề xuất

| Giai đoạn | Lãi/tháng | PF |
|---|---|---|
| 2023.02–2024.10 (ngoài mẫu, chế độ xấu) | 2,05% | 1,08 |
| 2025.10–2026.09 (ngoài mẫu, chế độ tốt) | ~25% | 1,20 |
| 43 tháng liên tục | **10,01%** | **1,17** |

Dương ở mọi cửa sổ đã đo, sụt vốn tương đối ổn định quanh 33–35% ở mọi giai đoạn.

### CẤU HÌNH ĐỀ XUẤT CUỐI — khác `exness_359` ở 4 điểm

| Thiết lập | exness_359 hiện tại | Đề xuất |
|---|---|---|
| Chart | M1 | **M5** |
| `Inp_No_SL` | true | **false** |
| `Inp_FlexTP_Enabled` | true | **false** |
| `Inp_Matrix_File` | TLS_Matrix_Trend.csv | **M_I_NOGATE_R3.csv** |
| `PeriodsInMajorSwing` | 9 | **16** |

Giữ nguyên: `Trend_Timeframe=H1`, `HTF_Timeframe=M15`, `Entry_Mode=2`,
`FixedLotSize=0.05`, `UseRiskPerTrade=false`, `Inp_DailyDrawdownLimit=0`.
(`Trend_PeriodsInMajorSwing` và `HTF_PeriodsInMajorSwing` **không có tác dụng** với
ma trận không gate — đã chứng minh: 6 tổ hợp cho đúng 2 kết quả.)

Điều chỉnh khẩu vị rủi ro bằng `FixedLotSize`, co giãn tuyến tính:
lot 0,05 → ~10%/tháng, sụt vốn 33% · lot 0,03 → ~6%/tháng, ~20% · lot 0,02 → ~4%/tháng, ~13%.

### Còn thiếu duy nhất
- [ ] Kiểm trên symbol khác / sàn khác. Toàn bộ số liệu vẫn là XAUUSD trên IC Markets.

---

## 13/09/2026 — NGHIÊN CỨU QUẢN LÝ LỆNH (bước 1: thiết bị đo trong OnTester)

Code: thêm `StudyTick()`, `StudyReport()`, `UpdateLeg()` vào `TLS_SMC_CSV_Bot.mq5`, chỉ
chạy khi `MQL_TESTER`. Không đổi logic vào/đóng lệnh (kiểm: +433,27%/3724 lệnh so với
+433,63%/3722 lệnh không đo). Mô phỏng dời SL và TP ngắn là CHÍNH XÁC theo đường giá,
không ước lượng. Cấu hình đo: `demo_M5_nogate_R3.set`, M5, 2023.02→2026.09. 1R ≈ 101 USD.

### Lệnh thua: lãi nổi cao nhất trước khi dính SL (2684 lệnh)
<0.5R 47,4% · 0.5–1R 21,8% · 1–1.5R 12,5% · 1.5–2R 7,6% · 2–2.5R 6,0% · 2.5–3R 4,7%
=> 491 lệnh (18,3%) từng lãi ≥1,5R rồi quay về −1R. Hiện tượng người dùng mô tả CÓ THẬT.

### Nhưng MỌI cách dời SL / TP ngắn đều LÀM GIẢM tổng lợi nhuận (gốc: +427,0R)
| Cách | Cứu lệnh thua | Giết/cắt lệnh thắng | Thay đổi |
|---|---|---|---|
| BE @0.5R | 1411 | 548 | −225,9R |
| BE @1.0R | 826 | 317 | −119,3R |
| BE @1.5R | 491 | 191 | −79,5R |
| BE @2.0R | 288 | 109 | −35,4R |
| BE @2.5R | 127 | 53 | −29,9R |
| Khoá +0.5R @2.0R (tốt nhất nhóm khoá) | 288 | 192 | −45,2R |
| TP 2.5R | | | −76,9R |
| TP 2.0R | | | −175,3R |
| TP 1.5R | | | −333,7R |
| Chốt 50% @1.5R (tính từ MFE) | | | ≈ −165R |
Tỷ lệ cứu/giết ≈ 2,6 : 1 ở mọi mốc — dưới ngưỡng 3 : 1 cần để BE có lãi với TP 3R.
Đường TP tăng đơn điệu 1R→3R: TP DÀI HƠN có thể còn tốt hơn → đang chạy thật TP 4R, 5R.

### Nhịp xu hướng Major lúc vào lệnh (1=CHoCH, +1 mỗi BOS cùng chiều)
| Nhịp | Khung chart M5: lệnh · R/lệnh | Khung HTF M15: lệnh · R/lệnh |
|---|---|---|
| 1 | 802 · +0,087 | 785 · +0,122 |
| 2 | 768 · +0,116 | 691 · +0,118 |
| 3 | 545 · +0,173 | 539 · +0,095 |
| 4 | 407 · +0,000 | 428 · +0,195 |
| 5+ | 1200 · **+0,145** | 1279 · +0,090 |
KHÔNG có suy giảm theo nhịp. Nhịp 5+ đóng góp nhiều R nhất (+173,8R ở M5). Nhịp 4 bằng 0
nhưng không có quy luật (3 tốt, 4 bằng 0, 5+ tốt) → nhiễu. Ở nhịp muộn, TP ngắn tệ nhất
(nhịp 5+ M5: TP2 +0,079 so với TP3 +0,145). => Giả thuyết "nhịp muộn nên ăn ngắn / ngừng
vào lệnh" BỊ SỐ LIỆU BÁC BỎ.

### Giờ vào lệnh (giờ SERVER IC, GMT+2/+3; giờ VN ≈ server +4 đến +5)
Tiêu chí loại: lỗ ở CẢ HAI giai đoạn (trước 2025 và từ 2025). **Không giờ nào đạt.**
Giờ âm tổng đều đổi dấu giữa hai giai đoạn: 04h (−0,289 / +0,056), 07h (+0,279 / −0,359),
16h (−0,189 / +0,199), 17h (+0,009 / −0,086).
Dương ổn định cả hai giai đoạn: 08h (+0,319/+0,285), 11h (+0,303/+0,335),
22h (+0,293/+0,301), 15h (+0,217/+0,154), 05h (+0,175/+0,266), 02h (+0,169/+0,121).
Thứ: T4 yếu nhất (−0,028/lệnh, −21,3R) nhưng dương trước 2025 → không đạt tiêu chí loại.

### Bước 2 đang chạy (lượt thật, 43 tháng): b2_S_BE15 (đối chiếu mô phỏng: dự báo
≈ +347,5R), b2_S_TP4, b2_S_TP5, b2_S_TRAIL_STRUCT, b2_S_TRAIL_R, b2_S_TRAIL_MINOR,
b2_S_TRAIL_MAJOR.

---

## BƯỚC 2 — LƯỢT THẬT 43 THÁNG + KIỂM ĐỊNH MÔ PHỎNG

| Biến thể | Lãi USD | PF | Thắng | Sụt vốn tg.đối | Tổng R | 1R ≈ USD |
|---|---|---|---|---|---|---|
| **TP 5R** | **+626,83%** | 1,22 | 20,2% | 36,81% | 747,7 | 84 |
| **TP 4R** | **+599,56%** | 1,23 | 23,3% | 31,15% | 582,2 | 103 |
| Hoà vốn @1,5R | +477,25% | 1,24 | 26,9% | 29,15% | 341,4 | 140 |
| Gốc TP 3R | +433,27% | 1,17 | 27,9% | 33,19% | 427,0 | 101 |
| Trail theo R | +313,39% | 1,19 | 49,3% | 25,36% | 211,6 | 148 |
| Trail cấu trúc Major (Protected) | +296,69% | 1,16 | 32,8% | 32,00% | 287,2 | 103 |
| Trail zone Major | +254,00% | 1,16 | 32,9% | 44,11% | 122,1 | 208 |
| Trail zone Minor | +97,70% | 1,08 | 34,3% | 41,36% | 86,4 | 113 |

### Kiểm định mô phỏng: CHÍNH XÁC
Dự báo BE@1,5R = 347,5R · thật = 341,4R (lệch 1,8%). Dự báo 682 lệnh đóng ở điểm vào ·
thật 683. Dự báo giết 191 lệnh thắng · thật TP 1039 → 848 = đúng 191.

### PHÁT HIỆN QUAN TRỌNG: R ≠ USD vì lot cố định
Lot cố định 0,05 → 1R của mỗi lệnh đáng giá theo độ rộng SL. BE@1,5R giảm 86R nhưng TĂNG
~4.400 USD: nó cứu chủ yếu lệnh thua SL RỘNG (lỗ nhiều tiền) và giết lệnh thắng SL HẸP.
=> Kết luận ở bước 1 "mọi cách dời SL đều giảm lợi nhuận" SAI khi tính bằng USD. Bảng mô
phỏng R vẫn đúng về R, nhưng quyết định cho tài khoản lot cố định phải chạy thật để đo USD.
Trail zone Major là ví dụ ngược: 1R ≈ 208 USD nhưng tổng R quá thấp → vẫn kém.

### Lỗi vận hành lộ ra
BE@1,5R: 5.965 lần sửa SL thất bại — đang truy nguyên nhân.

### Đang chạy: ngoài mẫu THẬT năm 2022 (2022.02.01→2023.02.01, chưa từng dùng) cho TP 3R/4R/5R.

### Nguyên nhân 5.965 lần sửa SL thất bại — ĐÃ VÁ
Toàn bộ là `[Market closed]`, dồn vào 13 lệnh (trung bình 459 lần/lệnh, nhiều nhất 1.771).
Khối dời SL về hoà vốn trong `ManageTrades_Tick()` sửa SL thất bại mà không gọi
`NoteRetcode()`, nên cơ chế chờ 5 phút không bật và bot thử lại mỗi tick suốt lúc sàn
nghỉ. Cùng loại với 3 lỗi đã vá trước; lần trước bỏ sót đường này. Đã thêm nhánh `else`
gọi `NoteRetcode()`. Ảnh hưởng kết quả gần bằng 0 (sàn nghỉ thì giá không chạy), nhưng
chạy thật sẽ spam sàn. Còn một điểm chưa sửa: nếu chốt một phần thất bại thì
`partial_done` đã bị đặt true trước đó nên phần chốt đó mất luôn, không thử lại (ma trận
đang dùng không có chốt một phần nên chưa ảnh hưởng).

## NGOÀI MẪU THẬT — NĂM 2022 (2022.02.01→2023.02.01, chưa từng dùng để chọn gì)

| Biến thể | Lãi | PF | Thắng | Sụt vốn tg.đối | Lệnh |
|---|---|---|---|---|---|
| TP 3R (demo hiện tại) | −7,52% | 0,98 | 24,4% | 34,60% | 1013 |
| **TP 4R** | **+2,53%** | **1,01** | 20,2% | 38,08% | 1013 |
| TP 5R | −6,85% | 0,98 | 17,2% | **49,54%** | 1013 |

2022 là năm cả chiến lược đi ngang. TP 4R là biến thể duy nhất không lỗ. TP 5R — thắng
đậm nhất trong 43 tháng — có sụt vốn gần 50% ở năm xấu → không dùng TP 5R đơn thuần.
Theo nhịp (M5, TP 3R): nhịp 1–4 đều âm, nhịp 5+ dương (+0,108R/lệnh) — khớp với phát hiện
43 tháng rằng nhịp muộn là nhóm tốt nhất.

## BƯỚC 3 đang chạy: TP4+BE1,5 · TP4+BE2,0 · TP5+BE2,0 trên 43 tháng, và BE1,5 · cả ba tổ
hợp trên năm 2022. Bản `.ex5` đã biên dịch lại với bản vá Market closed.

---

## BƯỚC 3 — TP DÀI + HOÀ VỐN, 43 THÁNG VÀ NGOÀI MẪU 2022 (14/09/2026)

Bản vá Market closed đã xác nhận: sửa SL thất bại 5.965 → 9–14 lần mỗi lượt.

| Biến thể | 43 th: lãi · PF · sụt vốn tg.đối | 2022: lãi · PF · sụt vốn tg.đối |
|---|---|---|
| TP 3R (demo hiện tại) | +433,27% · 1,17 · 33,19% | −7,52% · 0,98 · 34,60% |
| Hoà vốn @1,5R | +477,25% · 1,24 · 29,15% | +8,49% · 1,03 · 23,54% |
| TP 4R | +599,56% · 1,23 · 31,15% | +2,53% · 1,01 · 38,08% |
| TP 5R | +626,83% · 1,22 · 36,81% | −6,85% · 0,98 · 49,54% |
| **TP 4R + hoà vốn @1,5R** | **+491,75% · 1,24 · 30,27%** | **+13,43% · 1,05 · 27,73%** |
| TP 4R + hoà vốn @2R | +435,44% · 1,19 · 30,22% | +1,03% · 1,00 · 36,77% |
| TP 5R + hoà vốn @2R | +390,18% · 1,17 · 41,28% | −7,72% · 0,97 · 41,21% |

### Kết luận
- **Đề xuất: TP 4R + dời SL về hoà vốn khi chạm 1,5R** (`M_S_TP4_BE15.csv`). Biến thể duy
  nhất đứng top ở CẢ HAI phép kiểm: dương ở năm xấu 2022 (+13,43%, cao nhất), sụt vốn
  27–30% ổn định qua cả hai giai đoạn, PF 1,24 / 1,05.
- TP 4R đơn thuần lãi 43 tháng cao hơn (+600%) nhưng năm xấu sụt vốn 38% và chỉ +2,5% →
  phù hợp nếu ưu tiên lợi nhuận hơn độ an toàn.
- TP 5R (đơn thuần hoặc kèm hoà vốn): LOẠI. Sụt vốn 41–50% ở năm xấu.
- Hoà vốn @2R luôn kém hoà vốn @1,5R ở cả hai phép kiểm.
- Lưu ý chọn mẫu: năm 2022 đã được dùng để so 7 biến thể → không còn là ngoài mẫu hoàn
  toàn cho lựa chọn cuối. Chênh lệch TP4+BE1,5 so với phần còn lại đủ lớn (+13,4% so với
  kế tiếp +8,5%) nhưng vẫn cần demo để xác nhận.

### Các giả thuyết của người dùng — kết quả cuối
| Giả thuyết | Kết quả |
|---|---|
| Lệnh có lãi rồi quay về SL | CÓ THẬT: 18,3% lệnh thua từng lãi ≥1,5R |
| Dời SL về hoà vốn có lợi | CÓ, tính theo USD (lot cố định), tốt nhất ở 1,5R. Theo R thì lỗ — chênh lệch do lệnh SL rộng/hẹp có giá trị USD khác nhau |
| Dời SL theo cấu trúc M5 (Major/Protected/Minor) | KHÔNG: cả ba kém gốc (+97% đến +297% so với +433%) |
| Dời SL theo bậc R (trail) | KHÔNG: +313% |
| Theo cấu trúc M1 / theo pips cố định | Chưa test (chart M5 không có cấu trúc M1; pips cố định chưa có code) |
| Ngừng vào lệnh ở nhịp muộn | KHÔNG: nhịp 5+ là nhóm lãi nhất ở cả 43 tháng và 2022 |
| Nhịp muộn ăn ngắn | KHÔNG: TP ngắn ở nhịp 5+ giảm kỳ vọng rõ rệt |
| Bắt sóng mạnh nhất | Hướng đúng là TP DÀI hơn (4R), không phải lọc sóng |
| Loại khung giờ lỗ | KHÔNG giờ nào lỗ ở cả hai giai đoạn → không loại |

### File
`BOT_TLS/demo_M5_nogate_TP4_BE15.set` — giống `demo_M5_nogate_R3.set`, chỉ đổi
`Inp_Matrix_File=M_S_TP4_BE15.csv`. Cần copy `Matrix_Test/M_S_TP4_BE15.csv` vào
`Terminal\Common\Files\` và biên dịch lại EA trên máy chạy.

---

## 14/09/2026 07:26 — ĐÃ TRIỂN KHAI DEMO TRÊN MÁY NÀY

- MT5 **IC Markets Global** (`C:\Program Files\MetaTrader 5 IC Markets Global`), tài khoản
  IC demo, chế độ **Hedge**, máy chủ HK-Demo (ping ~231 ms).
- EA `TLS_SMC_CSV_Bot` trên **XAUUSD M5**, preset `demo_M5_nogate_TP4_BE15.set`
  (49 input), ma trận `M_S_TP4_BE15.csv`. Mã nguồn / ma trận / preset trên MT5 khớp repo
  theo MD5 lúc khởi động.
- Lệnh đầu tiên 07:26:11: buy 0,05 @4335,71, SL 4289,95, TP 4518,50 (= 3,99R → TP 4R đúng).
- Tắt ngủ khi cắm sạc: `standby-timeout-ac 0`, `hibernate-timeout-ac 0`.

### CẢNH BÁO CHO MỌI PHIÊN SAU
**`Tools/Run-Backtest.ps1` tắt đúng bản MT5 IC Markets trước khi backtest → sẽ GIẾT phiên
demo đang chạy.** Không chạy backtest bằng bản IC trên máy này khi demo còn chạy. Muốn
backtest thì dùng máy khác, hoặc hỏi người dùng để tạm dừng demo.

### Chưa xong
- Telegram chưa gửi được (`Error 4014` = WebRequest chưa được phép). Cấu hình `[Experts]
  WebRequest` truyền qua `/config:` không có hiệu lực. Người dùng cần thêm
  `https://api.telegram.org` trong Tools → Options → Expert Advisors. Token/ChatID trong
  preset là của nhóm `exness_359` → thông báo sẽ lẫn với bot trên VPS.
- Rủi ro mỗi lệnh có thể vượt trần zone: vào lệnh thị trường nên khoảng SL tính từ giá hiện
  tại, lệnh đầu tiên rộng 45,76 giá ≈ 229 USD (2,3% vốn) dù `Max_Zone_SL_Pips=300`. Hành vi
  này giống hệt trong backtest.

---

## 15/09/2026 — PHÂN TÍCH SÂU TỪNG LỆNH (tái dựng từ log, giá khớp thật, TRƯỚC swap/hoa hồng)

Người dùng đã tắt demo và cho phép Claude tắt/bật bot khi cần phân tích.
Công cụ: `extract_trades.awk` (log → CSV từng lệnh), `analyze_trades.awk` (scratchpad).
Chênh lệch còn lại so với lãi ròng tester ≈ 0,6–1,5 USD/lệnh = swap + hoa hồng (log không ghi).

### Cấu hình demo TP4 + hoà vốn @1,5R — 43 tháng
- 3.722 lệnh · lệnh thắng TB **+394 USD (+788 pip)** · lệnh thua TB **−65 USD (−129 pip)**.
- SL ban đầu: trung vị 12 giá (120 pip, 60 USD) · p90 39 giá (195 USD) · lớn nhất 371 giá (1.854 USD).

**Theo độ rộng SL ban đầu** (phát hiện mạnh, lặp lại ở MỌI cấu hình và năm 2022):
| SL rộng | Lệnh | Net USD | USD/lệnh | TP3 gốc USD/lệnh | TP4 USD/lệnh | 2022 USD/lệnh |
|---|---|---|---|---|---|---|
| **0–10 giá (<100 pip)** | **1.559 (42%)** | **−248** | **−0,2** | +2,5 | +2,8 | −0,1 (737 lệnh = 73%) |
| 10–20 | 1.082 | +16.680 | +15,4 | +13,8 | +20,3 | +5,4 |
| 20–30 | 479 | +5.333 | +11,1 | −0,7 | +4,9 | −17,8 (30 lệnh) |
| 30–45 | 324 | +14.518 | +44,8 | +26,0 | +44,2 | |
| 45–60 | 149 | +7.588 | +50,9 | +62,6 | +64,2 | |
| 60+ | 129 | +10.531 | +81,6 | +98,6 | +76,7 | |
=> Lệnh SL hẹp dưới ~100 pip chiếm 42–73% số lệnh nhưng lợi nhuận ≈ 0 (âm sau phí). Nhiều
khả năng bị nhiễu và spread quét. Ứng viên bộ lọc: SL tối thiểu.

**Theo ngày** (916 ngày có đóng lệnh): chỉ **31,7% ngày dương** · trung vị **−76 USD/ngày** ·
p90 +575 · p95 +1.204 · ngày tốt nhất +8.097 · ngày tệ nhất −2.431.
**5% lệnh lãi lớn nhất = 285% lợi nhuận ròng** (95% lệnh còn lại âm ~185%).
=> Lợi nhuận đến từ số ít ngày/lệnh rất lớn. Chốt lãi ngày ở mức thấp có nguy cơ cắt đúng
động cơ lợi nhuận — đang đo chính xác bằng `Inp_DailyProfitLimit`.

**Chuỗi & rủi ro**: thua liên tiếp dài nhất **45 lệnh** (cả 43 tháng lẫn 2022) · 18 ngày âm
liên tiếp · nằm dưới đỉnh lâu nhất **278 ngày** · tháng dương 50% (22/44).
**Phơi nhiễm**: tối đa **14 lệnh mở cùng lúc** (TB 5,5 lúc vào lệnh) · tổng rủi ro SL cùng lúc
tối đa 9.017 USD (05/02/2026). TP4 đơn thuần: tối đa 19 lệnh.

**Theo chiều và năm** (USD): 2024 BUY +10.397 / SELL −6.125 · 2025 BUY +35.853 / SELL −12.154 ·
2026 BUY −2.391 / SELL +25.528. Chiều ngược xu hướng năm luôn chảy máu → ứng viên bộ lọc
xu hướng khung lớn (H4/D1) — chưa test.

### Đang chạy
1. `mfe_TP4_BE15`: xuất MFE từng lệnh (pips/USD) — bot có thêm `StudyReport` ghi CSV vào
   Common\Files, chỉ khi backtest.
2. `opt_dpl_43m` / `opt_dpl_2022`: `Inp_DailyProfitLimit` 0,2,4,…,12%.
3. `opt_ddl_43m` / `opt_ddl_2022`: `Inp_DailyDrawdownLimit` 0,2,…,10%.

---

## LOẠT 1 (15/09/2026) — CHỐT LÃI NGÀY / CẮT LỖ NGÀY / MFE TỪNG LỆNH
Cấu hình nền: demo TP4 + hoà vốn @1,5R. Dùng cơ chế có sẵn của bot (`ManagePropFirmRules`):
so equity với balance đầu ngày D1, chạm ngưỡng thì ĐÓNG HẾT lệnh và nghỉ tới hết ngày.
Cột DD là sụt vốn equity TUYỆT ĐỐI của báo cáo tối ưu hoá (tương đối sẽ cao hơn một chút).

### `Inp_DailyProfitLimit` — chốt lãi ngày
| Ngưỡng | 43 tháng: lãi · PF · Recovery · DD | 2022: lãi · PF |
|---|---|---|
| tắt | **+492,1%** · 1,240 · 2,88 · 26,2% | +13,43% · 1,05 |
| 2% | +108,6% · 1,090 · 2,34 · 41,3% | −10,53% · 0,95 |
| 4% | +56,4% · 1,037 · 0,95 · 35,9% | +13,43% · 1,06 |
| 6% | +92,2% · 1,054 · 1,08 · 38,1% | +14,83% · 1,06 |
| 8% | +243,2% · 1,134 · 3,78 · 19,5% | −0,39% · 1,00 |
| 10% | +377,5% · 1,194 · 4,17 · 16,5% | **+15,45%** · DD tương đối 22,0% (chạy bù loạt 3) |
| 12% | +407,6% · 1,205 · **4,50** · **15,7%** | **−4,47%** · 0,98 |
=> Ngưỡng 2–6% phá huỷ 80–90% lợi nhuận. Ngưỡng 10–12% giảm DD tuyệt đối 26% → 16% và tăng
Recovery Factor, đổi lại mất 17–23% lợi nhuận — NHƯNG năm 2022 ngưỡng 8% và 12% biến +13,4%
thành −0,4% và −4,5%. Không bền → KHÔNG khuyến nghị chốt lãi ngày.
Cơ chế: lợi nhuận dồn vào số ít ngày rất lớn (5% lệnh lãi nhất = 285% lợi nhuận 43 tháng,
555% năm 2022); chốt lãi ngày cắt đúng những ngày đó.

### `Inp_DailyDrawdownLimit` — cắt lỗ ngày
| Ngưỡng | 43 tháng | 2022 |
|---|---|---|
| tắt | +492,1% · DD 26,2% | +13,43% |
| 2% | **+362,8% · DD 32,1%** (tệ hơn cả hai mặt) | **+0,80%** (chạy bù loạt 3) |
| 4% | +492,1% — trùng khít "tắt" (chạy bù loạt 3) | +13,53% |
| 6%, 8%, 10% | **trùng khít "tắt"** — chưa từng kích hoạt trong 43 tháng | 10%: +13,53% |
=> Cắt lỗ ngày chặt (2%) gây hại. Từ 6% trở lên chưa bao giờ chạm → là "bảo hiểm miễn phí"
cho một ngày thiên nga đen, không tốn lợi nhuận lịch sử.

### MFE từng lệnh (43 tháng, lot 0,05: 1 pip = 0,5 USD)
- 2.198 lệnh dính SL đủ −1R: lãi nổi cao nhất trước khi dính SL trung vị **43 pip**, p75 109,
  p90 237. **45,6% từng lên ≥50 pip · 27,3% ≥100 pip (50 USD) · 13,2% ≥200 pip · 6,8% ≥300
  pip · 2,7% ≥500 pip.**
- 880 lệnh đóng ở hoà vốn (đã chạm 1,5R rồi quay về): lãi nổi cao nhất trung vị **253 pip
  (126 USD)**, p90 907 pip (453 USD).
- 644 lệnh chốt TP 4R: TB +394 USD, quãng đường trung vị 559 pip.
=> Nhóm hoà vốn có lãi nổi đáng kể → thử chốt 50% ở 2R / 3R (loạt 3).

---

## LOẠT 2 (15/09/2026) — BỘ LỌC SL TỐI THIỂU `Inp_Min_SL_Pips` (input mới, mặc định 0 = tắt)

| SL tối thiểu | 43 tháng: lãi · PF · Recovery · DD tuyệt đối · lệnh | 2022: lãi · PF · DD · lệnh |
|---|---|---|
| tắt | +492,1% · 1,240 · 2,88 · 26,2% · 3724 | +13,53% · 1,051 · 27,7% · 1013 |
| 30 | (MT5 bỏ sót) | +12,35% · 1,047 · 28,3% · 981 |
| 60 | +500,0% · 1,246 · 2,91 · 25,9% · 3353 | (bỏ sót — loạt 5 bù) |
| 90 | +544,3% · 1,273 · 3,18 · 24,2% · 2953 | **+2,08%** · 1,008 · **37,3%** · 632 |
| 120 | (bỏ sót — loạt 5 bù) | +4,25% · 1,020 · 35,2% · 445 |
| 150 | **+646,5% · 1,357 · 3,82 · 21,2% · 2172** | **+17,99% · 1,104 · 23,5%** · 294 |
43 tháng cải thiện đều theo ngưỡng; 2022 lẫn lộn (90–120 tệ hơn tắt, 150 tốt nhất nhưng chỉ 294
lệnh). Giá trị tốt nhất nằm ở BIÊN dải quét → loạt 5 quét 180–270.
Nghi vấn: ngưỡng pip cố định có ý nghĩa khác nhau khi giá vàng từ ~1.800 (2022) lên ~4.300
(2026) → đang tách theo năm × pip và × % giá.

### BẪY SCRIPT MỚI (bẫy thứ 9)
PowerShell KHÔNG phân biệt hoa thường tên biến: `foreach ($w in $W)` dùng chung một biến, vòng
đầu chạy đúng nhưng ghi đè `$W` bằng phần tử cuối → các vòng sau lặp qua từng ký tự (tag
`opt_maxrisk_2`, khoảng ngày `0..2`, MT5 thoát sau 7 giây). Làm hỏng 3 phép thử của loạt 2
(giới hạn số lệnh, lọc xu hướng H4/D1, khoảng cách lệnh) → đã xếp lại thành loạt 4.
Luôn đặt tên biến vòng lặp khác hẳn tên mảng (`$win` / `$windowList`).

### Hàng đợi
Loạt 3 (đang chạy): bù chốt lãi/cắt lỗ ngày bị sót + chốt 50% @2R / @3R.
Loạt 4: giới hạn lệnh chưa hoà vốn 2–10 · lọc xu hướng HTF H4/D1 · khoảng cách lệnh 0–150 pip.
Loạt 5: bù SL tối thiểu 120 (43 th) / 60 (2022) · quét 180–270.

### SL tối thiểu — tách theo năm (USD trước phí, từ dữ liệu từng lệnh)
Nhóm SL < 60 pip, cùng khoảng 1.160 lệnh trong 5 năm:
| Cấu hình | 2022 | 2023 | 2024 | 2025 | 2026 | Tổng | Năm âm |
|---|---|---|---|---|---|---|---|
| TP4 không hoà vốn | −184 | +1.102 | −736 | +127 | +71 | +380 | 2/5 |
| TP3 + hoà vốn 1,5R | −706 | +93 | −220 | +279 | −49 | −603 | 3/5 |
| TP4 + hoà vốn 1,5R | −166 | −198 | −904 | −161 | −11 | −1.440 | 5/5 |
- Nhóm < 60 pip ≈ 0 USD/lệnh ở MỌI cấu hình → âm sau swap + hoa hồng (~0,6–1,5 USD/lệnh).
- Hoà vốn @1,5R làm nhóm này tệ hơn: winrate 18–30% → 11–20% (1,5R của lệnh SL hẹp chỉ cách
  điểm vào 60–90 pip, nằm trong biên độ nhiễu nên giá dễ chạm lại hoà vốn).
- Nhóm 60–90 và 90–150 pip đổi dấu theo năm → cắt ở 90–150 là dò trúng, đó là lý do năm 2022
  tụt khi đặt 90–120. Nhóm 150–250 pip dương cả 5/5 năm.
- Theo % giá: nhóm < 0,25% âm 4/5 năm, 0,25–0,5% và 0,5–1% dương 5/5.
=> Khuyến nghị `Inp_Min_SL_Pips = 60` (bền theo năm), KHÔNG dùng 150 (tối ưu trong mẫu 43 tháng
nhưng không bền). Bản nâng cấp sau có thể đổi sang ngưỡng theo % giá (~0,25%) để tự co giãn
theo mức giá vàng.

---

## 15/09/2026 — ĐỔI MỤC TIÊU & GOM BỘ CÔNG CỤ

### Người dùng đổi mục tiêu
Cần chiến lược **lãi đều theo tháng, kiểu lướt sóng vào nhanh thoát nhanh**; không chịu được chuỗi
thua hàng chục lệnh để chờ một lệnh thắng lớn. Cấu hình demo TP4 + hoà vốn (winrate 17%, chuỗi
thua 45, 50% tháng dương) đi NGƯỢC mục tiêu này. Câu hỏi mới:
1. Nghịch xu hướng H4/D1 thì chốt nhanh, thuận thì nuôi dài? Hay chỉ đánh thuận?
2. Lệnh thắng lớn có đặc điểm chung gì lúc vào lệnh (xu hướng D1/H4/H1/M15, hợp lưu zone khung lớn)?
3. Gom mọi thứ thành bộ công cụ backtest hoàn chỉnh cho các bot sau.

### Đã làm
- Dừng loạt 4 và 5 (khoảng cách lệnh, SL tối thiểu 180–270 pip — không còn khớp mục tiêu).
- Thêm đo đặc điểm lệnh vào `TLS_SMC_CSV_Bot.mq5` (chỉ khi backtest): engine H4 và D1 riêng
  (`SMC_H4`, `SMC_D1`), `StudyFeat()` ghi cho 5 khung (chart/HTF/Trend/H4/D1): xu hướng Major,
  giá có trong zone cùng chiều không, pip tới mép zone, pip tới zone ngược chiều; thêm giờ chạm
  1R lần đầu, giờ đạt MFE, dòng ma trận. CSV xuất thêm 26 cột. Biên dịch thử: 0 lỗi.
- Ma trận `M_S_TP10.csv`: cả 216 dòng, TP 10R, không hoà vốn — để đo lệnh thắng chạy xa bao nhiêu.
- Đang xếp hàng (sau loạt 3): `feat_TP10_43m`, `feat_TP10_2022`.

### Bộ công cụ `EA_TLS/Tools` (xem README.md)
| File mới | Việc làm |
|---|---|
| `Run-Batch.ps1` | Chạy loạt từ file `.psd1`; từ chối nếu MT5 đích đang chạy; tắt/khôi phục chế độ ngủ; tự phát hiện và `-FillMissing` chạy bù tổ hợp tối ưu bị MT5 bỏ sót; `-DryRun`. Đã chạy thử: phát hiện đúng `opt_minsl_43m` thiếu 30 và 120 |
| `Analyze-Trades.ps1` + `lib/extract_trades.awk` + `lib/analyze_trades.awk` | Tái dựng từng lệnh bằng giá khớp thật, báo cáo 8 mục. Đã kiểm khớp số liệu bản cũ |
| `Analyze-Features.ps1` + `lib/analyze_features.awk` | Đặc điểm lúc vào lệnh + 10 kịch bản TP/lọc lệnh, chấm theo % tháng dương, tháng âm liên tiếp, chuỗi thua |
| `jobs/example_bot_tls.psd1` | File job mẫu |
README viết lại: quy trình phễu, 10 nguyên tắc phương pháp, toàn bộ bẫy kỹ thuật (có bẫy 9:
PowerShell không phân biệt hoa thường tên biến).

---

## LOẠT 3 (15/09/2026) — KẾT QUẢ: CHẠY BÙ CHỐT LÃI/CẮT LỖ NGÀY + CHỐT 50% @2R / @3R

### Chạy bù (điền vào bảng loạt 1 ở trên)
- Chốt lãi ngày 10%, 2022: **+15,45%**, DD tương đối 22,0%, 7/12 tháng dương (tắt: +13,53%, 5/12).
  43 tháng ở ngưỡng 10% là +377,5% (−23% lợi nhuận). Ngưỡng 8% và 12% năm 2022 đều âm, nên 10%
  dương chỉ là dò trúng → giữ kết luận KHÔNG dùng chốt lãi ngày.
- Cắt lỗ ngày 2%, 2022: **+0,80%** → gây hại cả hai giai đoạn. 4% trên 43 tháng trùng khít "tắt".

### Chốt 50% khối lượng khi đạt 2R / 3R (TP4 + hoà vốn 1,5R giữ nguyên)
| | Gốc (không chốt) | Chốt 50% @2R | Chốt 50% @3R |
|---|---|---|---|
| 43 tháng: lãi · DD tương đối | +491,75% · 30,27% | +415,88% · **24,22%** | +489,09% · 29,69% |
| 43 tháng: winrate · chuỗi thua | 17,3% · 45 | **32,2% · 26** | 22,7% · 41 |
| 43 tháng: tháng dương · âm liên tiếp | 22/44 · 5 | 23/44 · 5 | 23/44 · 5 |
| 43 tháng: ngày dương · nằm dưới đỉnh | 31,7% · 278 ngày | 36,5% · 207 ngày | 34,0% · 273 ngày |
| 2022: lãi · DD tương đối | +13,53% · 27,7% | +11,71% · **22,9%** | +11,57% · 26,0% |
| 2022: winrate · chuỗi thua | 15,2% · 45 | **29,9% · 22** | 19,9% · 45 |
| 2022: tháng dương · âm liên tiếp | 5/12 · 4 | 6/12 · **2** | 6/12 · 2 |
=> Chốt 50% @2R đổi ~15% lợi nhuận lấy chuỗi thua giảm một nửa (45 → 22–26) và DD giảm 5–6 điểm,
bền ở cả hai giai đoạn. Nhưng tháng dương vẫn chỉ ~50% → CHƯA đạt mục tiêu lãi đều theo tháng;
chỉ là bước giảm đau. @3R gần như không đổi gì. Hướng chính vẫn là lọc lệnh theo đặc điểm (lượt đo
`feat_TP10_*`).

### BẪY CÔNG CỤ MỚI (bẫy thứ 10)
`extract_trades.awk` bỏ qua dòng EA tự đóng `market sell 0.02 XAUUSD, close #6 (...)` và lấy lot lúc
vào lệnh cho cả lần đóng cuối → lượt chốt 50% ra số liệu Y HỆT lượt không chốt (54.401 USD cả hai),
dù tester báo 41.588 vs 49.175. Đã sửa: mỗi vị thế một dòng, giá đóng BÌNH QUÂN theo khối lượng mọi
lần đóng, thêm cột `partial`, dòng thống kê ghi số lần chốt một phần và số vị thế chưa đóng.
Kiểm lại: lượt gốc vẫn ra 54.401 USD. Dấu hiệu nhận biết: chênh lệch giữa lãi tách được và
`lai_rong_tester` phải ổn định (≈ swap + hoa hồng, ở đây 4,6–5,2 nghìn USD / 43 tháng).

---

## ĐẶC ĐIỂM LỆNH THẮNG LỚN & KỊCH BẢN LÃI ĐỀU (15/09/2026)

Lượt đo: ma trận `M_S_TP10.csv` (216 dòng, TP 10R, không hoà vốn). 43 tháng: +922,9%, DD tương
đối 78% · 2022: −24,8%, DD 85% (lượt đo, không phải cấu hình giao dịch). 3.711 + 1.002 lệnh có đặc
điểm. Mô phỏng TP chính xác theo từng lệnh, **đã trừ 1,4 USD/lệnh phí** (ước từ chênh lệch
Analyze-Trades vs tester). Báo cáo: `Tools/logs/features_feat_TP10_*.txt`.

### 1. Lướt sóng TP ngắn trên tín hiệu này KHÔNG có lợi thế
50% lệnh chạm 1R trước khi dính SL, nhưng sau phí: TP 1R = +124 USD / 43 tháng (0/lệnh),
2022 −1.766. TP 1,5R: +7.907 / −1.254, âm năm 2022, 2023, 2024. Tháng dương 33–52%.
Lợi nhuận của bot nằm hoàn toàn ở phần đuôi (lệnh chạy ≥4R).

### 2. Nghịch xu hướng + TP ngắn: KHÔNG cứu được
Lệnh nghịch D1, theo năm (TP 1 / 1,5 / 4R, USD): 2022 −3.481 / −2.982 / −6.738 · 2024 −4.152 /
−3.629 / −5.768 · 2025 −666 / −3.435 / −9.709 — nhưng 2023 +417 / +1.097 / +2.153 và 2026 +387 /
+5.445 / +7.270. Rút TP ngắn không biến nhóm này thành dương ổn định; nó đổi dấu theo năm như
chính nhóm thuận D1 (ngược lại).

### 3. Đặc điểm lúc vào lệnh — cái gì phân biệt được lệnh thắng lớn
| Đặc điểm | 43 tháng | 2022 | Kết luận |
|---|---|---|---|
| Thuận D1 (bất kể H4) | TP4: +20,4 / +24,1 USD/lệnh | +13,1 / +14,4 | Tốt nhất, nhưng xem theo năm ↓ |
| Nghịch D1 | −6,6 / +1,5 | −13,2 / −17,3 | Xấu ở tổng |
| Thêm điều kiện H4 thuận | kém hơn chỉ D1 | kém hơn chỉ D1 | H4 **không** thêm giá trị |
| Cả H1+H4+D1 thuận | tỷ lệ ≥4R 27% vs 23% | 24% vs 20% | Hơn chút, mất 78% số lệnh |
| Giá nằm trong zone cùng chiều H1/H4 | −24 → −13 USD/lệnh | lẫn lộn | **Hợp lưu zone KHÔNG giúp** |
| Zone D1 đối diện cách < 2R | −38 → −44 USD/lệnh | −10 → −49 | Xấu cả hai giai đoạn, nhưng chỉ 6% lệnh |
| Chạm 1R sau ≥ 1 giờ | nhóm lãi nhất | nhóm lãi nhất | Lệnh thắng lớn là lệnh **chậm**; không biết được lúc vào |

### 4. Kịch bản × năm (net USD sau phí)
| Kịch bản | 2022 | 2023 | 2024 | 2025 | 2026 | Tháng dương 43 th · 2022 |
|---|---|---|---|---|---|---|
| Tất cả, TP 4R | −3.876 | +833 | +2.970 | +28.446 | +7.463 | 52% · 50% |
| Tất cả, TP 1,5R | −1.739 | −1.292 | −570 | +4.904 | +4.865 | 50% · 33% |
| Chỉ thuận D1, TP 4R | **+3.283** | −1.076 | **+11.189** | **+34.786** | +868 | 52% · 58% |
| Chỉ thuận D1, TP 1,5R | +1.401 | −2.105 | +3.779 | +7.404 | −649 | 43% · 75% |
| Thuận D1 TP 4R, nghịch D1 TP 1,5R | +143 | −263 | +6.840 | +32.285 | +6.381 | 55% · 50% |
| Thuận D1 + cản D1 ≥2R, TP 4R | +3.428 | −2.073 | +10.475 | +32.709 | +3.728 | 52% · 58% |
(2022 lấy từ lượt 2022; 2023–2026 từ lượt 43 tháng, 2023 bắt đầu từ 02/2023.)

=> **Lọc thuận D1** là đặc điểm mạnh nhất tìm được: lãi hơn "tất cả lệnh" ở 2022/2024/2025, dùng
ít hơn 41% số lệnh, sụt vốn mô phỏng 65% → 29% (43 th) và 50% → 13% (2022). Nhưng thua ở
2023/2026 → **không đạt nguyên tắc "đúng dấu mọi năm"**.
=> **Không kịch bản nào** trong 18 đạt mục tiêu lãi đều theo tháng: tốt nhất 55–57% tháng dương
trên 43 tháng, chuỗi thua 25–43 lệnh. Mô hình vào lệnh M5 SMC này là hệ **theo xu hướng, lãi ở
đuôi** — đổi TP hay lọc theo đặc điểm khung lớn không biến nó thành hệ lướt sóng lãi đều.

### Việc còn lại
- Nếu tiếp tục BOT_TLS: thêm input lọc xu hướng D1 cho bản chạy thật (engine D1 hiện chỉ có khi
  backtest) và chạy thật TP4 + hoà vốn 1,5R + chốt 50% @2R + chỉ thuận D1, 43 tháng và 2022 —
  kỳ vọng giảm sụt vốn và chuỗi thua, KHÔNG kỳ vọng lãi đều tháng.
- Nếu mục tiêu bắt buộc là lãi đều tháng: cần mô hình vào lệnh khác; bộ công cụ đã sẵn để đo
  (Analyze-Features + bảng kịch bản × năm).
- Công cụ: `Analyze-Features.ps1 -CostPerTrade`, 8 kịch bản D1 mới (11–18), cột "năm âm" và bảng
  kịch bản × năm; lý do: con số tổng 43 tháng của lọc D1 (+45,8k) che mất 2 năm ngược chiều.
- 6 file `.set` đã thêm `Inp_Min_SL_Pips=0.0` (mặc định = tắt, không đổi hành vi).
