# EA_TLS/Tools — bộ công cụ backtest headless

Chạy Strategy Tester của MT5 **không cần mở giao diện**, cho mọi bot trong repo này: chạy đơn lẻ,
tối ưu hoá song song trên mọi nhân CPU, chạy hàng loạt theo file job, rồi **tái dựng từng lệnh**
từ log để phân tích sâu (theo độ rộng SL, theo ngày/tháng, chuỗi thua, số lệnh mở cùng lúc…).

Bộ công cụ được đúc kết từ đợt kiểm chứng BOT_TLS tháng 09/2026 (hơn 250 lượt chạy). Mọi chốt
chặn trong script đều sinh ra từ một lần kết luận sai hoặc một batch bị hỏng thật.

## Cài một lần

```powershell
cd EA_TLS\Tools
Copy-Item account.local.ini.example account.local.ini
notepad account.local.ini      # điền đường dẫn terminal + tài khoản demo
```

`account.local.ini` **chứa mật khẩu và đã được `.gitignore`** — không bao giờ đưa vào git.
Mọi thứ khác trong thư mục này an toàn để commit.

Dò đường dẫn trên máy mới (mỗi máy một khác, **không dùng lại giá trị của máy cũ**):

```powershell
Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Filter terminal64.exe -Recurse -ErrorAction SilentlyContinue
Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory |
  ForEach-Object { "$($_.Name) -> $(Get-Content "$($_.FullName)\origin.txt")" }
```

Script tự dò `DataFolder` qua `origin.txt`, chỉ cần điền tay khi nó dò không ra.

`Analyze-Trades.ps1` cần **gawk** — có sẵn trong Git for Windows (`usr\bin\gawk.exe`), script tự tìm.

## Các thành phần

| File | Việc làm |
|---|---|
| `Run-Backtest.ps1` | Chạy **một** lượt: đơn lẻ, hoặc tối ưu hoá song song với `-Range` |
| `Run-Batch.ps1` | Chạy **một loạt** lượt từ file `.psd1`, có chốt chặn và tự chạy bù tổ hợp bị sót |
| `Analyze-Trades.ps1` | Tách từng lệnh từ log → `trades_<Tag>.csv` + báo cáo phân tích sâu |
| `Analyze-Features.ps1` | Đặc điểm lúc vào lệnh (xu hướng D1/H4/H1, zone, cản đối diện, tốc độ chạm 1R) + 18 kịch bản TP/lọc lệnh, chấm theo tháng dương và **từng năm** |
| `lib\analyze_features.awk` | Lõi của `Analyze-Features.ps1`; thêm kịch bản ở hàm `decideTP` |
| `Summarize-Backtest.ps1` | Bảng tóm tắt nhanh mọi lượt (lãi, sụt vốn, PF, lỗi vận hành, input thật) |
| `Funnel-Swing.ps1` | Dò tuần tự nhiều input, tự chọn giá trị theo "vùng phẳng" giữa các giai đoạn |
| `BacktestLib.ps1` | Hàm dùng chung (`Get-RunMetrics`) |
| `lib\extract_trades.awk` | Tái dựng từng lệnh bằng giá khớp thật — dùng được cho mọi symbol |
| `lib\analyze_trades.awk` | Phân tích file CSV từng lệnh |
| `jobs\*.psd1` | File job cho `Run-Batch.ps1` — xem `jobs\example_bot_tls.psd1` |
| `logs\` | Mọi đầu ra (đã `.gitignore`) |

## Quy trình khuyến nghị — phễu

Thứ tự này không phải thói quen mà là kết quả của những lần kết luận sai:

1. **Sàng lọc nhanh** trên cửa sổ ngắn (1–3 tháng) để loại cấu hình tệ. Không dùng để chọn.
2. **Tối ưu song song** (`-Range`) trên một khoảng **liên tục** 12 tháng trở lên, có chứa giai đoạn
   thị trường xấu.
3. **Chốt bằng một lượt chạy liên tục dài** (vd 43 tháng). Không cộng lãi của nhiều cửa sổ rời có
   reset vốn — xem nguyên tắc 1.
4. **Kiểm ngoài mẫu** trên một năm **chưa từng dùng để chọn bất cứ gì**.
5. **Tách kết quả theo từng năm** (`Analyze-Trades.ps1`) — chỉ tin quy luật đúng dấu ở mọi năm.
6. **Chạy demo** trước khi dùng tiền thật.

```powershell
# 1–4: một file job
.\Run-Batch.ps1 -JobFile .\jobs\toi_uu_bot_x.psd1 -FillMissing
# 5: phân tích sâu từng lượt
.\Analyze-Trades.ps1 -Tag "chot_43m"
.\Summarize-Backtest.ps1 -Tag "chot_*" -Detail
```

## Run-Backtest.ps1 — một lượt

```powershell
# Lượt đơn giản nhất: dùng nguyên preset có sẵn
.\Run-Backtest.ps1 -Bot BOT_TLS -Preset exness_359.set -From 2026.06.18 -To 2026.09.09 -Tag june_now

# Đổi vài input so với preset, đổi khung, đổi file ma trận
.\Run-Backtest.ps1 -Bot BOT_TLS -Preset ftmo.set -Period M5 `
    -Matrix M_I_NOGATE_R3.csv `
    -Set @("Inp_No_SL=false","Inp_FlexTP_Enabled=false","FixedLotSize=0.02") `
    -Tag ftmo_thantrong
```

| Tham số | Mặc định | Ghi chú |
|---|---|---|
| `-Bot` | bắt buộc | tên thư mục bot, ví dụ `BOT_TLS` |
| `-Preset` | bắt buộc | tên file `.set` trong thư mục bot, hoặc đường dẫn đầy đủ |
| `-Tag` | bắt buộc | tên lượt chạy, dùng đặt tên file log |
| `-From` `-To` | 2026.01.01 → 2026.02.01 | định dạng `yyyy.MM.dd` |
| `-Period` | theo account.local.ini | `M1` `M5` `M15` `H1`... |
| `-Symbol` `-Deposit` | theo account.local.ini | |
| `-Matrix` | giữ theo preset | ghi đè `Inp_Matrix_File` |
| `-Model` | `EveryTick` | hoặc `OHLC_M1`, `OpenPrices` |
| `-Set` | rỗng | mảng `"Ten=GiaTri"` ghi đè input của preset |
| `-Range` | rỗng | mảng `"Ten=batdau:buoc:ketthuc"` — có ít nhất một mục thì MT5 chạy **chế độ tối ưu**, chia các tổ hợp ra mọi nhân CPU |
| `-Account` | `account.local.ini` | dùng file tài khoản khác |

Log từng lượt nằm ở `logs\out_<Tag>.log` (UTF-8, đã cắt đúng phần của lượt đó). Lượt tối ưu hoá
thêm `logs\opt_<Tag>.csv` (mỗi dòng một tổ hợp).

### Tối ưu tham số (`-Range`)

```powershell
# Quét 1 tham số
.\Run-Backtest.ps1 -Bot BOT_CRT -Account account.crt.ini -Preset CRT_MultiTF_EA.set `
    -From 2025.01.01 -To 2026.03.31 -Period M15 -Tag sl_buffer `
    -Range @("Inp_SL_BufferPips=20:10:50")

# Quét 2 tham số cùng lúc (tích Descartes — 4 x 5 = 20 lượt)
.\Run-Backtest.ps1 -Bot BOT_CRT -Account account.crt.ini -Preset CRT_MultiTF_EA.set `
    -Tag sl_be -Range @("Inp_SL_BufferPips=20:10:50", "Inp_BE_TriggerPips=20:20:100")
```

Kết quả xếp hạng theo **giá trị `OnTester()` trả về** (`OptimizationCriterion=6`), đọc từ file XML
mà MT5 xuất ra. **EA phải có hàm `OnTester()`**, không có thì mọi lượt bị chấm 0 điểm và bảng xếp
hạng vô nghĩa — `BOT_CRT` có từ v1.68, `BOT_TLS` có sẵn từ trước.

Quét 2 tham số là đủ cho một lượt; 3 tham số trở lên vừa lâu vừa dễ chọn trúng nhiễu. Song song
nhanh hơn chạy tuần tự khoảng **2,7 lần** trên CPU i5-1235U (8/10 nhân là nhân hiệu năng thấp) —
không phải gấp 12 lần số luồng.

Tham số kiểu chuỗi (vd `Inp_Matrix_File`) **không tối ưu song song được** — dùng `Run-Batch.ps1`.

## Run-Batch.ps1 — một loạt

```powershell
.\Run-Batch.ps1 -JobFile .\jobs\example_bot_tls.psd1 -FillMissing
.\Run-Batch.ps1 -JobFile .\jobs\example_bot_tls.psd1 -FillMissing -DryRun   # chỉ in kế hoạch
```

File job (`.psd1`) chỉ chứa giá trị:

```powershell
@{
    Name     = "ten_loat"
    Defaults = @{ Bot = "BOT_TLS"; Preset = "demo.set"; Period = "M5"; Set = @("Inp_No_SL=false") }
    Jobs     = @(
        @{ Tag = "goc_43m";   From = "2023.02.01"; To = "2026.09.12" }
        @{ Tag = "minsl_43m"; From = "2023.02.01"; To = "2026.09.12"; Range = @("Inp_Min_SL_Pips=0:30:150") }
    )
}
```

`Set` của `Defaults` được **ghép** với `Set` của từng lượt theo tên input (lượt ghi đè).

Chốt chặn tự động:

| Chốt chặn | Vì sao |
|---|---|
| **Từ chối chạy nếu bản MT5 đích đang mở** (bỏ qua bằng `-AllowStopLive`) | `Run-Backtest` tắt bản MT5 đó → **giết bot demo đang giao dịch** |
| Tắt chế độ ngủ khi cắm sạc, **khôi phục đúng giá trị cũ** khi xong — kể cả khi loạt bị lỗi giữa chừng | Máy ngủ sau 5 phút từng giết một lượt 4,4 tiếng |
| So số tổ hợp trong báo cáo tối ưu với lưới mong đợi; `-FillMissing` **tự chạy bù** từng tổ hợp thiếu | MT5 bỏ sót tổ hợp trong báo cáo — gặp **8 lần** trong một đợt, có lượt chỉ còn 1/5 |
| Lượt đơn lẻ không có `final balance` bị ghi `CAT NGANG` | `tester forced to close` trông như chạy xong |
| Một lượt lỗi không dừng cả loạt; tóm tắt ghi ở `logs\batch_<Name>_summary.txt` | |

Muốn nối nhiều loạt: chạy lần lượt trong cùng một cửa sổ PowerShell. **Đừng** để nhiều loạt tự chờ
nhau bằng vòng lặp dò file — một loạt hỏng sẽ khiến loạt sau hoặc chờ vô hạn hoặc chạy sai lúc.

## Analyze-Trades.ps1 — phân tích từng lệnh

```powershell
.\Analyze-Trades.ps1 -Tag b3_S_TP4_BE15
.\Analyze-Trades.ps1 -Tag "oos2022_*"
.\Analyze-Trades.ps1 -Tag eurusd_test -ContractSize 100000 -Pip 0.0001
```

Ghi `logs\trades_<Tag>.csv` (mỗi dòng một vị thế: giờ vào, giá vào, lot lúc vào, SL/TP ban đầu,
giờ đóng hẳn, giá đóng **bình quân theo khối lượng** của mọi lần đóng, lý do `SL`/`TP`/`EA`, số lần
chốt một phần) và `logs\report_<Tag>.txt`:

| Mục | Trả lời câu hỏi |
|---|---|
| 1. Tổng kết | Lệnh thắng/thua trung bình bao nhiêu USD, bao nhiêu pip |
| 2. Theo độ rộng SL | Nhóm SL hẹp/rộng nào thật sự kiếm tiền |
| 3. Theo ngày | Phân phối lãi lỗ ngày: % ngày dương, p10…p90, ngày tốt/tệ nhất |
| 4. Chuỗi | Thua liên tiếp dài nhất, ngày âm liên tiếp, sụt vốn, **thời gian nằm dưới đỉnh** |
| 5. Phơi nhiễm | Tối đa bao nhiêu lệnh mở cùng lúc, tổng rủi ro SL cùng lúc |
| 6. Chiều × năm | Buy/Sell từng năm — chiều nào chảy máu |
| 7. Theo tháng | % tháng dương, **tháng âm liên tiếp**, tháng tốt/tệ nhất |
| 8. Tập trung | 5% lệnh lãi lớn nhất chiếm bao nhiêu % lợi nhuận |

Lưu ý khi đọc:

- USD tính từ giá × lot × `ContractSize`, **trước swap và hoa hồng** — log không ghi hai khoản
  này. Dòng `#` trong CSV cho biết lãi ròng của tester để đối chiếu (BOT_TLS: lệch 0,6–1,5 USD/lệnh).
- Ghi lệnh đóng bằng SL/TP **và** lệnh EA tự đóng qua `CTrade` (chốt một phần, FlexTP, Pool SL).
  Vị thế còn mở lúc hết kỳ test không có trong CSV — dòng `#` ghi `chua_dong=`.
- Giá đóng là **giá khớp thật**, không phải giá SL yêu cầu: lấy giá SL yêu cầu thì tổng lãi lệch ~12%
  vì trượt giá qua đêm / cuối tuần.
- **Tự kiểm mỗi lần đọc báo cáo:** chênh lệch giữa `net` tách được và `lai_rong_tester` phải xấp xỉ
  swap + hoa hồng và **ổn định giữa các cấu hình cùng số lệnh** (BOT_TLS 43 tháng: 4,6–5,2 nghìn USD).
  Hai cấu hình khác nhau mà `net` trùng từng đô la → bộ tách đang bỏ sót một loại lệnh đóng.
  Bản cũ từng như vậy: bỏ qua dòng `market sell 0.02 XAUUSD, close #6`, nên lượt chốt 50% @2R ra
  y hệt lượt không chốt (54.401 USD) dù tester báo 41.588 so với 49.175.

## Analyze-Features.ps1 — lệnh thắng lớn có gì chung, kịch bản nào lãi đều

```powershell
.\Analyze-Features.ps1 -Tag feat_TP10_43m -CostPerTrade 1.4
```

Cần hai file trong `logs\`: `out_<Tag>.log` và `<Tag>.csv`. File CSV là file đặc điểm mà bot xuất
trong Strategy Tester (`Common\Files\study_*.csv`), copy về rồi đổi tên theo Tag. Hiện chỉ
BOT_TLS xuất file này (`StudyReport`, chỉ chạy khi backtest). Bot khác muốn dùng phải tự ghi
đúng tên cột.

**Chạy lượt đo với TP rất dài và không hoà vốn** (BOT_TLS: `M_S_TP10.csv`). Khi đó lãi nổi cao nhất
trước lúc đóng = lãi nổi trước khi chạm SL, nên mô phỏng mọi TP ≤ 10R là **chính xác từng lệnh**.
Không mô phỏng được TP + hoà vốn hay chốt một phần. Kịch bản chọn ra phải chạy thật lại.

Báo cáo gồm:
- Tỷ lệ chạm 1R/2R/4R và kỳ vọng USD/lệnh theo từng mức TP, cho mỗi nhóm đặc điểm.
- Bảng kịch bản: số lệnh, winrate, net, PF, tháng dương, tháng âm liên tiếp, chuỗi thua, sụt vốn, số năm âm.
- Bảng **kịch bản × năm**.

`-CostPerTrade` trừ swap + hoa hồng mỗi lệnh. Ước lượng = (net của Analyze-Trades − lãi ròng
tester) / số lệnh. Không trừ thì kịch bản TP ngắn trông có lãi giả: BOT_TLS TP 1R +5.319 → +124 USD.

**Đọc bảng kịch bản × năm trước bảng tổng.** Ví dụ BOT_TLS: lọc thuận D1 cho +45,8k / 43 tháng,
hơn hẳn không lọc. Nhưng số tổng này chủ yếu do năm 2025 (+34,8k), trong khi 2023 và 2026 thì
không lọc lại tốt hơn.

## Chạy song song hai topic — không giẫm chân nhau

Script **chỉ tắt đúng bản MT5 mà nó sắp dùng** (lọc theo đường dẫn tiến trình). Trước 09/2026 nó
gọi `Get-Process terminal64 | Stop-Process` nên giết mọi bản MT5 đang mở, kể cả lượt backtest của
topic khác đang chạy dở.

Quy ước hiện tại: `account.local.ini` → bản **IC Markets** (Topic_BOT_TLS_By_GETCHART),
`account.crt.ini` → bản **MetaTrader 5 / Exness** (BOT_CRT). Hai bản cài khác nhau, khác thư mục
dữ liệu, khác ký hiệu vàng (`XAUUSD` với `XAUUSDm`).

Vẫn còn một thứ dùng chung: **nhân CPU**. Hai lượt tối ưu chạy cùng lúc sẽ chia nhau agent nên cả
hai đều chậm đi — nếu cần chạy lâu thì vẫn nên hẹn giờ với topic kia.

## Nguyên tắc phương pháp — đọc trước khi kết luận

1. **Kết luận cuối phải đến từ MỘT lượt chạy liên tục.** Bốn cửa sổ mùa hè, mỗi cửa sổ reset vốn
   10.000, từng cho "+139%, dương 4/4 năm". Chạy liên tục thì cả ba bộ tham số cháy tài khoản trong
   20 ngày của tháng 01/2025 — tháng chưa từng nằm trong cửa sổ nào.
2. **Để dành dữ liệu ngoài mẫu, và nhớ nó hết "ngoài mẫu" khi đã dùng để chọn.** BOT_TLS_GetChart:
   19 cấu hình "có lãi" trong mẫu, ngoài mẫu tỷ lệ thắng rơi từ 53–68% xuống 36–39%.
3. **Tách theo từng năm. Chỉ tin quy luật đúng dấu ở mọi năm.** Ngưỡng SL tối thiểu 150 pip đẹp
   nhất trong 43 tháng, nhưng tách năm thì chỉ nhóm SL < 60 pip là âm ở cả 5/5 năm — cắt ở 90–150
   là dò trúng và làm hỏng năm 2022.
4. **Lot cố định thì R ≠ USD.** Mỗi R của lệnh SL rộng đáng giá nhiều USD hơn lệnh SL hẹp. Dời SL
   về hoà vốn @1,5R làm **giảm** 86R nhưng **tăng** 4.400 USD. Mô phỏng theo R chính xác 98% về R
   nhưng quyết định phải đo bằng USD — chạy thật.
5. **Giá trị tốt nhất nằm ở biên dải quét = chưa quét đủ.** Gặp 4 lần; có lần mở rộng ra thì lộ
   ngay một vực lỗ 88% sát cạnh.
6. **Chọn giữa vùng phẳng, không chọn đỉnh nhọn.** Một giá trị tốt mà hàng xóm tệ thì không tin được.
7. **Winrate không phải thước đo.** Winrate cao nhất (49%) cho lãi bằng nửa cấu hình 17% winrate.
   Nhìn **% tháng dương, chuỗi thua dài nhất, tháng âm liên tiếp, thời gian nằm dưới đỉnh**.
8. **Đếm số lệnh trước khi tin con số %.** Dưới ~100 lệnh là nhiễu. Một preset từng "+10,1%" với
   38 lệnh trong 43 tháng.
9. **Hai lượt trùng kết quả tới từng xu = cấu hình không được áp dụng** — trừ khi truy ra lý do
   logic (vd tham số đó không tham gia quyết định nào). Luôn truy.
10. **Cột `Equity DD %` trong báo cáo tối ưu là sụt vốn TUYỆT ĐỐI**, không phải tương đối. Cùng một
    cấu hình: 18,2% và 42,25%. Muốn số tương đối phải chạy lượt đơn lẻ.

## Bẫy kỹ thuật

Script tự lo:

- **Đóng MT5 trước khi chạy.** Terminal đang mở thì `/config:` không kích hoạt tester mà chỉ bật
  lại cửa sổ cũ — có lần nó còn tự gắn EA lên chart tài khoản demo thật.
- **Ghi `.ini` dạng ASCII không BOM.** PowerShell 5.1 `Set-Content -Encoding utf8` ghi UTF-8 *có*
  BOM, MT5 bỏ qua luôn mục `[Tester]`.
- **Liệt kê tường minh mọi input.** `[TesterInputs]` chỉ ghi đè input được liệt kê; input thiếu
  **kế thừa giá trị của lượt trước**.
- **Lọc theo `input` có thật trong `.mq5`.** Thiết lập đã đổi sang `const` vẫn còn trong `.set` cũ.
- **Cắt đúng phần log của lượt vừa chạy** (log agent gom nhiều lượt nối đuôi nhau).

Người chạy phải tự nhớ:

1. **Compile trước khi chạy.** Script dùng `.ex5` đã có, không tự build. Xem mục Build trong
   `EA_TLS/CLAUDE.md`. **Không biên dịch lại giữa một loạt đang chạy** — các lượt sau sẽ dùng bản
   khác các lượt trước. Muốn kiểm cú pháp giữa chừng thì biên dịch một bản sao ở thư mục tạm.
2. **Đọc lại input thật từ log**, đừng tin file `.ini` mình vừa viết (`Summarize-Backtest.ps1 -Detail`).
3. **PowerShell không phân biệt hoa thường tên biến.** `foreach ($w in $W)` dùng chung một biến:
   vòng đầu chạy đúng rồi ghi đè `$W`, các vòng sau lặp qua từng ký tự. Từng làm hỏng 3 phép thử.
   Đặt tên biến vòng lặp khác hẳn tên mảng.
4. **Tester có giao diện treo ở "Waiting For Update"** khi terminal mở tay chưa đăng nhập (không có
   mật khẩu đã lưu). Bộ Tools luôn truyền mật khẩu nên không gặp; mở tay thì phải đăng nhập và tick
   "Save password" trước.
5. **Không backtest bằng bản MT5 đang chạy bot demo/thật.** `Run-Batch.ps1` từ chối; gọi thẳng
   `Run-Backtest.ps1` thì không có chốt chặn này.
6. **Sửa preset `.set` khi đang có loạt chạy dùng preset đó** có thể làm lượt sau đọc file đang ghi
   dở. Để đến khi loạt xong.
7. **CSV có xuống dòng CRLF** (MT5 `FileWrite`, .NET `WriteAllLines`). Script awk đọc tên cột từ dòng
   đầu phải bỏ `\r` trước, nếu không cột cuối thành `room_d1\r`, tra ra rỗng = 0 và **không báo lỗi**.
   Hai file `lib\analyze_*.awk` đã xử lý; viết script mới thì nhớ dòng `{ sub(/\r$/, "") }`.
8. **Viết bộ phân tích mới thì kiểm trên dữ liệu giả lập tính tay được** (vài lệnh, biết trước đáp
   án) và trên một lượt thật đã biết số, trước khi tin nó trên dữ liệu mới.

## Kết quả đã lưu

Toàn bộ đợt kiểm chứng BOT_TLS (09/2026) nằm ở `BOT_TLS/Matrix_Test/BACKTEST_PROGRESS.md`: bảng
kịch bản, các lỗi code tìm được khi đối chứng log, và phân tích từng lệnh.
