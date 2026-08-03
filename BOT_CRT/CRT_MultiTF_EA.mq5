//+------------------------------------------------------------------+
//|                                             CRT_MultiTF_EA.mq5   |
//|                                                          AnhTuan |
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.35"

// ==============================================================================
// CRT_Project — Bot AE đa khung thời gian.
//
// BƯỚC 1 (xong): Vẽ High/Low + đường giữa 50% của HTF (mặc định H4).
//   Giá trị gọi mọi lúc: HTF_High(), HTF_Low(), HTF_Mid(), HTF_Ready()
//   [1.06] Thêm 2 đường "Last Major High/Low" (đỉnh/đáy Major Swing gần nhất
//   của HTF, đọc từ CSMC_Engine — cố định theo điểm swing, khác biên nến liền kề).
//
// BƯỚC 2 (xong): Quét râu HTF trên khung LTF (mặc định M15) — CẢ HAI CHIỀU.
//   Lưu: CRT_SweptLow()/CRT_SweptHigh() + HasSwept...(); thông báo Journal/Dashboard/mũi tên.
//
// BƯỚC 3: Vào lệnh theo BOS/CHOCH (CSMC_Engine) trên khung Entry (mặc định M1).
//   - Sau khi quét râu M15 XÁC NHẬN -> "arm" theo hướng (dưới=BUY, trên=SELL).
//   - Nếu Entry TF có BOS/CHOCH thuận hướng -> vào lệnh market.
//   - Chưa có thì chờ; NGỪNG arming + huỷ pending khi giá chạm biên đối diện
//     (BUY: chạm H4 High; SELL: chạm H4 Low) hoặc khi H4 sang range mới.
//   - Vol theo risk %/tài khoản (SL = râu quét); chốt an toàn tài khoản -%;
//     tối đa N lệnh; TP tại Middle hoặc biên đối diện.
//   [1.06] Hai NGUỒN biên độc lập cho toàn bộ chuỗi trên (Inp_EntrySource):
//     ADJACENT (nến H4 liền kề, như cũ) / LASTMAJOR (cụm nến H4 - Major Swing) /
//     BOTH (chạy song song, độc lập, không loại trừ lẫn nhau, mỗi nguồn có
//     magic + hạn mức lệnh riêng — xem SCRTSource).
//   [1.07] Hiển thị (chart + dashboard) đi theo Inp_EntrySource — không còn toggle
//     hiển thị riêng cho Last Major, tránh rối màn hình khi chỉ dùng 1 nguồn.
//   [1.08] Gom màu/độ dày/kiểu nét/vị trí dashboard thành const cố định (không hiện
//     trên màn hình Input nữa) — Input chỉ còn tham số vận hành + các công tắc bật/tắt
//     hiển thị (Show...). Muốn đổi màu/style phải sửa code + compile lại.
//   [1.09] Inp_ExtendBars (số nến kéo dài line) cũng chuyển thành const = 50, ẩn khỏi Input.
//   [1.10] Gộp nhóm "LAST MAJOR" vào chung nhóm "HTF" (đều là tham số H4).
//   [1.11] Inp_ShowLastMajorLabel và Inp_MarkSweep chuyển thành const, ẩn khỏi Input.
//   [1.12] Inp_ShowLabel/Inp_ShowMidLine/Inp_ShowDashboard: giữ 3 input riêng (không gộp
//     làm 1 biến) nhưng gom chung 1 group "HIỂN THỊ" cho gọn màn hình Input.
//   [1.13] Inp_ShowLabel (toggle label High/Low của HTF) cũng chuyển thành const, ẩn khỏi
//     Input — theo quy tắc chung: mọi toggle liên quan tới Label đều hardcode.
//   [1.14] Sắp xếp lại thứ tự nhóm Input theo ưu tiên: (1) VẬN HÀNH (Bot/Risk/TP) trên
//     cùng, (2) tham số theo khung thời gian H4 -> M15 -> M1, (3) HIỂN THỊ (ít đụng đến)
//     ở dưới cùng. Không đổi tên biến nào, chỉ đổi group + thứ tự khai báo.
//   [1.15] Thêm mô tả tiếng Việt cho Inp_EnableTrading và Inp_Slippage (trước đó thiếu
//     comment nên màn hình Input hiện tên biến thô thay vì mô tả).
//   [1.16] Thêm Inp_MaxSpreadPoints (mặc định 0 = tắt): chặn vào lệnh nếu spread hiện tại
//     vượt ngưỡng — khác với Inp_Slippage (chỉ là dung sai giá khớp lệnh, không liên quan
//     spread). Không đánh dấu break đã act khi bị chặn, để bar sau tự thử lại.
//   [1.17] Đổi tên enum ENUM_CRT_SOURCE cho dễ hiểu: CRT_SRC_ADJACENT -> H4_LienKe,
//     CRT_SRC_LASTMAJOR -> H4_Swing, CRT_SRC_BOTH -> Ca2_LienKe_Va_Swing (vẫn giữ nguyên
//     3 lựa chọn + toàn bộ logic chạy song song 2 nguồn độc lập, chỉ đổi tên hiển thị).
//     Tag nội bộ của 2 nguồn (dùng trong log + dashboard) cũng đổi "ADJ"/"LM" -> "LiềnKề"/"Swing".
//   [1.18] Viết lại mô tả Inp_EntrySource bằng tiếng Việt có dấu, bỏ từ "arm" khó hiểu,
//     giải thích rõ nghĩa từng lựa chọn. Lưu ý: bản thân TÊN 3 lựa chọn trong dropdown
//     (H4_LienKe/H4_Swing/Ca2_LienKe_Va_Swing) không thể có dấu/khoảng trắng — giới hạn
//     của MQL5 với tên enum, không phải lựa chọn thiết kế.
//   [1.19] Rút gọn mô tả Inp_EntrySource, chỉ còn câu dẫn ngắn "Bot canh vào lệnh theo
//     biên giá nào của H4:" — bỏ phần liệt kê chi tiết từng lựa chọn phía sau.
//   [1.20] Áp dụng tương tự cho Inp_TP_Target: đổi enum CRT_TP_MIDDLE/CRT_TP_BOUNDARY
//     -> TP_Middle/TP_BienDoiDien, mô tả rút gọn còn "Chọn TP đặt ở đâu:".
//   [1.21] Xác nhận: TP Middle/Biên đối diện vốn đã tính theo ĐÚNG nguồn kích hoạt lệnh
//     (Adjacent hay Swing), không cần sửa. Thêm Inp_TP_Mode (3 chế độ): TPMode_MidBienH4
//     (như cũ) / TPMode_RR (TP = entry + Inp_TP_RR × khoảng SL) / TPMode_Pips (TP cách
//     entry Inp_TP_FixedPips pip cố định). Logic TP tách ra hàm ComputeTP().
//   [1.22] Sửa quy đổi pip cho TPMode_Pips: broker này quote 3 chữ số thập phân nhưng
//     THỰC TẾ pip vẫn là $0.1 (như broker 2 chữ số) -> entry 4000.xxx + 50 pip = 4005.xxx.
//   [1.23] Port các cơ chế quản trị từ BOT_TLS sang (dùng chung quy ước input & quy đổi
//     pip qua GetPipSize() — vàng = 0.1 bất kể broker quote 2 hay 3 chữ số):
//       · Giới hạn số lệnh/số vòng (xem [1.25] bên dưới cho ngữ nghĩa cuối cùng). Cả 2
//         counter nằm TRONG SCRTSource nên mỗi nguồn (H4 liền kề / H4 Swing) đếm riêng.
//       · Inp_MaxSL_Pips: bỏ qua lệnh nếu SL quá xa (chặn ở ExecuteEntry).
//       · Inp_MaxDistFromLine_Pips: giá chạy quá xa đường tín hiệu -> ngừng arming
//         (chặn ở CheckDisarmSource, đo từ chính đường H4 liền kề/Last Major).
//       · Inp_Pool_SL_Percent: SL theo % — tổng lỗ nhóm lệnh CÙNG HƯỚNG (gộp cả 2 nguồn)
//         chạm ngưỡng thì đóng cả nhóm, nhóm ngược hướng vẫn chạy.
//       · SHIELD: Inp_UseMarginLimit/Inp_MaxMarginPercent (cắt lot theo margin),
//         Inp_DailyDrawdownLimit / Inp_DailyProfitLimit (mốc balance ĐẦU NGÀY, tự reset
//         mỗi ngày — khác Inp_AccountSL_Percent vốn tính từ balance lúc khởi động EA),
//         Inp_AutoPassTarget (equity mục tiêu -> dừng hẳn), Inp_NewsTimes/BufferMinutes.
//       · Inp_UseRiskPercent + Inp_FixedLotSize: chọn vol theo % tài khoản hay lot cố định.
//         Lưu ý đổi hành vi: khi risk/margin không đủ cho lot tối thiểu thì BỎ lệnh
//         (return 0) thay vì ép vào lot min như trước — giống BOT_TLS.
//       · Telegram (Telegram_Radar.mqh dùng chung với BOT_TLS): chế độ CHỈ THEO DÕI
//         (Inp_EnableTrading=false) chỉ báo tín hiệu Buy/Sell; chế độ VÀO LỆNH báo thêm
//         lệnh đã khớp + lệnh đóng (OnTradeTransaction) + cảnh báo Pool SL/Shield.
//   [1.24] Rút gọn mô tả input cho vừa cột hiển thị của MT5.
//   [1.25] SỬA cấu trúc hạn mức cho đúng cấp bậc (bản 1.23 sai: cả 2 counter đều gắn
//     vào "tín hiệu" nên chồng lấn — đốt hết quota lệnh trong vòng 1 là không bao giờ
//     sang được vòng 2). Cấp bậc đúng, giống BOT_TLS:
//         1 tín hiệu (1 lần quét râu xác nhận)
//           ├─ vòng 1: vào tối đa N lệnh -> đóng hết -> reset
//           ├─ vòng 2: ... (chỉ vòng đóng CÓ LÃI mới tính vào hạn mức vòng)
//           └─ đủ Inp_MaxRoundsPerSignal vòng lãi -> dừng, chờ tín hiệu mới
//   [1.26] Đồng bộ GIÁ TRỊ MẶC ĐỊNH của input theo file cấu hình thật CRT_MultiTF_EA.set
//     (lưu 2026-08-02 17:49) để không phải set tay sau mỗi lần cập nhật code. 10 tham số
//     đổi: MaxOrdersPerRound 0->1, MaxRoundsPerSignal 0->2, MaxSL_Pips 0->100,
//     MaxDistFromLine_Pips 0->100, UseMarginLimit true->false, DailyDrawdownLimit 3->0,
//     HTF_SwingMajor 5->1, HTF_SwingMinor 3->1, EntrySwingMajor 5->9, EntrySwingMinor 3->9.
//     Khi đổi default sau này, nhớ cập nhật cả file .set cho khớp (hoặc ngược lại).
//   [1.27] BỎ Inp_MaxTrades / Inp_MaxTrades_LastMajor (số lệnh mở cùng lúc) vì chồng lấn
//     với hạn mức số lệnh mỗi vòng: 1 vòng chỉ kết thúc khi ĐÓNG HẾT lệnh, nên số lệnh
//     mở cùng lúc của 1 nguồn vốn đã không thể vượt quá hạn mức mỗi vòng — 2 input cũ
//     chỉ có tác dụng khi đặt nhỏ hơn hạn mức vòng, dễ gây hiểu nhầm. Thay bằng 2 input
//     tách theo nguồn cho đối xứng: Inp_MaxOrders_LienKe / Inp_MaxOrders_Swing (thay cho
//     Inp_MaxOrdersPerRound dùng chung). CẢNH BÁO: đặt 0 = không giới hạn giờ có nghĩa là
//     KHÔNG còn trần nào cho số lệnh mở cùng lúc của nguồn đó — nên đặt số cụ thể.
//     Hạn mức còn lại 2 trục: số lệnh MỖI VÒNG (theo nguồn) và số vòng CÓ LÃI mỗi TÍN HIỆU.
//   [1.28] Điền sẵn Inp_BotToken + Inp_ChatID (channel -1003976929485) và bật
//     Inp_EnableTelegram = true để chạy là báo được ngay, không phải set tay.
//     Lưu ý: file .set cũ vẫn ghi Inp_EnableTelegram=false và token/chatID mặc định —
//     nếu bấm Load .set đó thì Telegram sẽ tắt trở lại; nhớ Save lại .set sau khi compile.
//   [1.29] Thêm 2 CHẾ ĐỘ ĐẶT SL (Inp_SL_Mode):
//       · SLMode_RauQuet   — SL = đáy/đỉnh râu quét ± Inp_SL_BufferPips (như cũ).
//       · SLMode_KhongDatSL — KHÔNG gửi SL lên sàn (SL=0), giao việc cắt lỗ cho
//         Inp_Pool_SL_Percent / Inp_AccountSL_Percent / Inp_DailyDrawdownLimit
//         (tương đương Inp_No_SL của BOT_TLS).
//     SL "ảo" vẫn LUÔN được tính ở cả 2 chế độ vì còn dùng để: tính lot theo risk %,
//     tính TP theo R:R, và lọc Inp_MaxSL_Pips — chỉ khác ở chỗ có gửi lên sàn hay không.
//     (Theo yêu cầu: KHÔNG hiện cảnh báo gì trên dashboard khi bật chế độ không đặt SL.)
//     ĐỔI ĐƠN VỊ: Inp_SL_BufferPoints (point) -> Inp_SL_BufferPips (pip, qua GetPipSize)
//     cho đồng bộ với BOT_TLS (SL_Buffer_Pips) và với Inp_MaxSL_Pips. Với vàng
//     1 pip = $0.1 = 100 point, nên số cũ 20 point ($0.02) tương đương 0.2 pip.
//     Đồng bộ default theo .set người dùng lưu 2026-08-03 23:08: EntrySource ->
//     Ca2_LienKe_Va_Swing, MaxSpreadPoints 0->15, UseRiskPercent true->false,
//     FixedLotSize 0.01->0.1, AccountSL_Percent 3->0, SL_BufferPips ->0,
//     TP_Mode -> TPMode_Pips, MaxSL_Pips 100->200, MaxMarginPercent 38->30.
//   [1.30] Thêm 2 CHẾ ĐỘ VÀO LỆNH (Inp_Entry_Mode):
//       · EntryMode_Market     — khớp ngay giá thị trường khi có BOS/CHOCH (như cũ).
//       · EntryMode_LimitTaiH4 — đặt lệnh CHỜ ngay tại đường biên H4 của chính nguồn
//         kích hoạt (BUY chờ hồi về H4 Low, SELL chờ hồi lên H4 High). Giá vào đẹp hơn
//         nhưng có thể không khớp nếu giá đi luôn. Lệnh chờ được huỷ tự động khi ngừng
//         arming (CheckDisarmSource / ResetSourceSweepAndArm gọi CancelEAPendings).
//         Có kiểm tra hợp lệ: giá chờ phải đúng phía so với giá hiện tại và cách tối
//         thiểu SYMBOL_TRADE_STOPS_LEVEL, không thì bỏ qua + ghi log (tránh lỗi 130).
//         Lưu ý: ordersThisRound tăng ngay khi ĐẶT được lệnh chờ, không đợi khớp.
//   [1.31] Ẩn Inp_Slippage khỏi màn hình Input -> chuyển thành const = 30 (khối KỸ THUẬT
//     / GIAO DIỆN). Lý do: khó hiểu, dễ nhầm với bộ lọc spread, và trên tài khoản Market
//     Execution thì server bỏ qua nên chỉnh cũng không đổi gì. Việc chặn vào lệnh khi
//     spread giãn đã có Inp_MaxSpreadPoints đảm nhiệm.
//   [1.32] Nới dung sai trượt giá: Inp_Slippage=30 (input) -> SLIPPAGE_POINTS=300 (const,
//     $0.30 vàng). Mục tiêu: loại bỏ nguyên nhân ngầm khiến "có setup mà không có lệnh"
//     — 300 point không bao giờ cản giao dịch bình thường (độ trễ mạng chỉ lệch 5–20
//     point) nhưng vẫn chặn cú khớp thảm họa kiểu gap/tin sốc nếu sau này đổi sang sàn
//     Instant Execution. CẢNH BÁO cho người sửa sau: KHÔNG được xoá dòng
//     SetDeviationInPoints() — CTrade mặc định 10 point, chặt hơn nhiều, xoá đi sẽ phản
//     tác dụng (bị từ chối khớp NHIỀU hơn chứ không phải ít hơn).
//     LỆCH VỚI BOT_TLS: TLS vẫn để Inp_Slippage_Points = 30 dạng input. Cố ý để vậy —
//     30 point khá chặt với vàng; nếu muốn đồng bộ thì sửa TLS lên 300, không phải
//     kéo CRT xuống 30.
//   [1.33] Inp_ShowStructure giờ CHỈ vẽ đường BOS/CHOCH. Trước đây cờ showGraphics của
//     CSMC_Engine kéo theo cả ray "LTF Protected/Active High-Low" (TRACK_*) và ray
//     "LTF Major Key Level" (KEY_LEVEL) — gây rối chart. Vì engine là file dùng chung
//     (BOT_TLS/BOT_OB_Radar) nên KHÔNG sửa engine để tách cờ; thay vào đó hàm
//     StripNonBosObjects() xoá 6 object đó ngay sau mỗi g_entryEngine.Update().
//     An toàn vì CRT không gọi HandleChartEvent() — engine chỉ tạo chúng trong Update().
//   [1.34] Thêm chế độ vào lệnh thứ 3: EntryMode_LimitTaiZoneM1 — đặt lệnh chờ tại mép
//     Zone M1 do chính BOS/CHOCH đó sinh ra (mép TRÊN zone Buy / mép DƯỚI zone Sell,
//     tức current_buy_zone_entry / current_sell_zone_entry của engine entry).
//     LÝ DO: EntryMode_LimitTaiH4 lấy giá = biên H4 vốn CỐ ĐỊNH, nên khi có nhiều
//     BOS/CHOCH liên tiếp (thường gặp trong xu hướng mạnh trên M1) bot đặt nhiều lệnh
//     CHỒNG NHAU cùng một giá — vô nghĩa, không khác gì 1 lệnh volume lớn. Mép Zone M1
//     đổi theo từng BOS/CHOCH nên các lệnh được rải ở những giá khác nhau.
//     KÈM THEO: MaxZones của engine entry đổi 5 -> 1. Bắt buộc, vì hàng đợi zone đẩy
//     phần tử cũ nhất lên đầu mảng và current_*_zone_entry đọc queue[0]; giữ 5 zone thì
//     biến đó trỏ vào zone CŨ NHẤT chứ không phải zone vừa tạo (BOT_TLS cũng dùng 1).
//   [1.35] Vá 2 lỗ hổng khi giá QUAY ĐẦU sau lúc quét râu (setup CRT đã chết mà bot
//     vẫn nhồi lệnh vì M1 vẫn có BOS/CHOCH thuận hướng):
//       (a) HUỶ SETUP khi nến LTF đóng vượt ngược qua mốc râu quét (BUY: đóng dưới
//           sweptLow / SELL: đóng trên sweptHigh) — thêm ở đầu ProcessSourceSweep, đặt
//           trước phần dò quét để cùng cây nến đó vẫn mở được cụm quét MỚI. Trước đây
//           chỉ có 2 chốt: chạm biên đối diện, và Inp_MaxDistFromLine_Pips (=100 pip
//           = $10 vàng — quá rộng, giá thủng biên gần $10 mà bot vẫn mua tiếp).
//       (b) CHẶN lệnh có SL nằm SAI PHÍA entry. slDist dùng MathAbs() nên khi giá đã
//           rơi dưới sweptLow, lệnh BUY có sl > entry vẫn lọt qua filter MaxSL_Pips và
//           tính lot từ khoảng cách vô nghĩa. Với SLMode_RauQuet sàn trả lỗi 130, nhưng
//           với SLMode_KhongDatSL (slOrder=0) thì lệnh VÀO THẬT với rủi ro đảo ngược.
// ==============================================================================

#include <Trade/Trade.mqh>
#include <CSMC_Engine.mqh>     // cần có trong MQL5/Include (dùng chung với BOT_TLS, BOT_OB_Radar)
#include <Telegram_Radar.mqh>  // dùng chung với BOT_TLS

// Lưu ý: MQL5 không cho phép tên enum chứa dấu tiếng Việt hay khoảng trắng (giới hạn của
// ngôn ngữ), nên dropdown trong Input sẽ luôn hiện đúng các tên sau — không thể hiện chữ
// có dấu/khoảng trắng được. Ý nghĩa từng tên xem ở comment của input tương ứng bên dưới.
enum ENUM_CRT_ENTRY_MODE { EntryMode_Market, EntryMode_LimitTaiH4, EntryMode_LimitTaiZoneM1 };
enum ENUM_CRT_SL_MODE { SLMode_RauQuet, SLMode_KhongDatSL };
enum ENUM_CRT_TP_MODE { TPMode_MidBienH4, TPMode_RR, TPMode_Pips };
enum ENUM_CRT_TP { TP_Middle, TP_BienDoiDien };
enum ENUM_CRT_SOURCE { H4_LienKe, H4_Swing, Ca2_LienKe_Va_Swing };

// ===================== 1. TỔNG QUAN VẬN HÀNH BOT =====================
input group "=== VẬN HÀNH (Bot / Risk / TP) ==="
input bool             Inp_EnableTrading    = true;       // Tự động vào lệnh (tắt = chỉ theo dõi + báo tín hiệu)
input ENUM_CRT_SOURCE  Inp_EntrySource      = Ca2_LienKe_Va_Swing; // Vào lệnh theo biên giá nào của H4:
input long             Inp_MagicNumber      = 20260713;   // Magic (nguồn H4 Swing tự dùng Magic+1)
input int              Inp_MaxSpreadPoints  = 15;        // Spread tối đa cho phép vào lệnh, point (0 = tắt)
input bool             Inp_UseRiskPercent   = false;     // Lot theo % tài khoản (tắt = dùng lot cố định)
input double           Inp_RiskPercent      = 1.0;       // Risk mỗi lệnh, % tài khoản
input double           Inp_FixedLotSize     = 0.1;       // Lot cố định mỗi lệnh
input double           Inp_AccountSL_Percent= 0.0;       // Đóng hết khi tài khoản âm quá % (từ lúc mở bot, 0=tắt)
input ENUM_CRT_ENTRY_MODE Inp_Entry_Mode    = EntryMode_Market; // Cách vào lệnh:
input ENUM_CRT_SL_MODE Inp_SL_Mode          = SLMode_RauQuet; // Cách đặt SL:
input double           Inp_SL_BufferPips    = 0;         //   • nếu SLMode_RauQuet — SL lùi ra ngoài râu quét (pip)
input ENUM_CRT_TP_MODE Inp_TP_Mode          = TPMode_Pips; // Cách tính TP:
input ENUM_CRT_TP      Inp_TP_Target        = TP_Middle; //   • nếu chọn TPMode_MidBienH4 — TP đặt ở:
input double           Inp_TP_RR            = 2.0;       //   • nếu chọn TPMode_RR — tỷ lệ Reward:Risk
input double           Inp_TP_FixedPips     = 50.0;      //   • nếu chọn TPMode_Pips — số pip (1 pip = $0.1)

// ===================== 2. GIỚI HẠN & LỌC TÍN HIỆU =====================
// Cấp bậc:  1 tín hiệu (1 lần quét râu xác nhận)
//             ├─ vòng 1: vào tối đa Inp_MaxOrders_* lệnh -> đóng HẾT -> sang vòng mới
//             ├─ vòng 2: ... (chỉ vòng đóng CÓ LÃI mới tính vào hạn mức vòng)
//             └─ đủ Inp_MaxRoundsPerSignal vòng lãi -> dừng, chờ tín hiệu mới.
// Mỗi nguồn (H4 liền kề / H4 Swing) đếm riêng bộ đếm của mình.
// Vì vòng chỉ kết thúc khi đóng hết lệnh, Inp_MaxOrders_* cũng chính là trần cho số
// lệnh mở CÙNG LÚC của nguồn đó -> không cần input "max trades" riêng nữa.
input group "=== GIỚI HẠN & LỌC TÍN HIỆU ==="
input int              Inp_MaxOrders_LienKe   = 1;       // Số lệnh tối đa mỗi vòng — nguồn H4 liền kề (0=không giới hạn)
input int              Inp_MaxOrders_Swing    = 1;       // Số lệnh tối đa mỗi vòng — nguồn H4 Swing (0=không giới hạn)
input int              Inp_MaxRoundsPerSignal = 2;       // Số vòng CÓ LÃI tối đa mỗi tín hiệu (0=không giới hạn)
input double           Inp_MaxSL_Pips         = 200;     // SL xa hơn số pip này thì bỏ lệnh (0=không giới hạn)
input double           Inp_MaxDistFromLine_Pips = 100;   // Giá cách đường tín hiệu quá số pip này thì bỏ chờ (0=tắt)
input double           Inp_Pool_SL_Percent    = 0;       // Nhóm lệnh cùng chiều lỗ quá % này thì đóng cả nhóm (0=tắt)

// ===================== 3. SHIELD — BẢO VỆ TÀI KHOẢN =====================
input group "=== SHIELD (Bảo vệ tài khoản) ==="
input bool             Inp_UseMarginLimit     = false;   // Bật giới hạn margin (tự giảm lot cho vừa mức dưới)
input double           Inp_MaxMarginPercent   = 30.0;    // Margin tối đa được dùng, % tài khoản
input double           Inp_DailyDrawdownLimit = 0;       // Lỗ tối đa trong NGÀY, % (0 = tắt)
input double           Inp_DailyProfitLimit   = 0;       // Lãi mục tiêu trong NGÀY, % (0 = tắt)
input double           Inp_AutoPassTarget     = 0;       // Equity mục tiêu (USD), đạt thì dừng hẳn (0 = tắt)
input string           Inp_NewsTimes          = "";      // Giờ tin cần tránh, giờ server "15:30, 21:00" (trống = tắt)
input int              Inp_NewsBufferMinutes  = 2;       // Chặn vào lệnh trước/sau giờ tin bao nhiêu phút

// ===================== 4. TELEGRAM =====================
input group "=== TELEGRAM ==="
input bool             Inp_EnableTelegram   = true;       // Bật gửi thông báo Telegram
input string           Inp_BotToken         = "8670907940:AAGkHoUQWn3hux6rUhdRF7291LVi_DUxvR0"; // Token của Bot Telegram
input string           Inp_ChatID           = "-1003976929485";      // ID chat/group/channel nhận thông báo
input bool             Inp_SendScreenshot   = true;      // Gửi kèm ảnh chart khi báo tín hiệu/vào lệnh

// ===================== 5. THAM SỐ THEO KHUNG THỜI GIAN: H4 -> M15 -> M1 =====================
// Việc HIỂN THỊ đường H4 liền kề / Last Major đi theo Inp_EntrySource ở nhóm VẬN HÀNH —
// không có toggle riêng, để tránh hiện cùng lúc 4 đường khi chỉ dùng 1 nguồn để vào lệnh.
input group "=== H4 (HTF) + Last Major Swing ==="
input ENUM_TIMEFRAMES Inp_HTF              = PERIOD_H4;  // Khung cao làm cơ sở High/Low
input int               Inp_HTF_SwingMajor  = 1;          // Số nến H4 mỗi bên xác định đỉnh/đáy Major Swing
input int               Inp_HTF_SwingMinor  = 1;          // Số nến H4 mỗi bên cho Minor Swing (engine cần)

input group "=== M15 (LTF) — QUÉT RÂU ==="
input ENUM_TIMEFRAMES  Inp_LTF             = PERIOD_M15; // Khung dùng để phát hiện quét râu
input bool             Inp_DetectLowSweep  = true;       // Bắt tín hiệu quét râu DƯỚI (chờ BUY)
input bool             Inp_DetectHighSweep = true;       // Bắt tín hiệu quét râu TRÊN (chờ SELL)

input group "=== M1 (Entry) ==="
input ENUM_TIMEFRAMES  Inp_EntryTF         = PERIOD_M1;  // Khung tìm BOS/CHOCH để vào lệnh
input int              Inp_EntrySwingMajor = 9;          // Số nến M1 mỗi bên để xác định Major Swing
input int              Inp_EntrySwingMinor = 9;          // Số nến M1 mỗi bên để xác định Minor Swing

// ===================== 6. Ít quan trọng / ít đụng đến =====================
input group "=== HIỂN THỊ ==="
input bool             Inp_ShowMidLine     = true;       // Vẽ đường Middle 50% của H4
input bool             Inp_ShowDashboard   = true;       // Hiện bảng dashboard trên chart
input bool             Inp_ShowStructure   = true;       // Vẽ BOS/CHOCH của khung entry lên chart
input bool             Inp_ShowZones       = false;      // Vẽ khung zone (sẽ đè lên nến M1)

// === KỸ THUẬT / GIAO DIỆN (cố định, không hiện trên màn hình Input) ===
// Đổi giá trị ở đây rồi compile lại (F7) nếu cần.
//
// Dung sai trượt giá khi khớp lệnh market (point). Đặt rộng để KHÔNG cản giao dịch
// bình thường (độ trễ mạng chỉ làm giá lệch chừng 5–20 point), nhưng vẫn chặn được cú
// khớp thảm họa kiểu gap cuối tuần / tin sốc / sàn treo rồi khớp lại.
// Lưu ý: trên tài khoản Market Execution (đa số sàn vàng ECN/STP) server BỎ QUA tham số
// này — nó chỉ là lưới an toàn phòng khi đổi sang sàn Instant Execution.
// KHÔNG được xoá dòng SetDeviationInPoints() đi: CTrade mặc định 10 point — CHẶT hơn
// nhiều, xoá đi sẽ bị từ chối khớp NHIỀU hơn chứ không phải ít hơn.
// Việc chặn vào lệnh khi thị trường xấu là nhiệm vụ của Inp_MaxSpreadPoints (kiểm tra
// trước khi gửi lệnh, có ghi log rõ lý do), không phải của tham số này.
const int              SLIPPAGE_POINTS        = 300;        // 300 point = $0.30 vàng
const int              Inp_ExtendBars         = 50;         // Số nến (chart hiện tại) kéo dài line sang phải
const bool             Inp_ShowLabel          = true;       // Label giá High/Low của HTF
const bool             Inp_ShowLastMajorLabel = true;
const bool             Inp_MarkSweep          = true;       // Vẽ mũi tên đánh dấu swept low/high
const color            Inp_ColorHigh          = clrRed;
const color            Inp_ColorLow           = clrLimeGreen;
const int              Inp_LineWidth          = 2;
const ENUM_LINE_STYLE  Inp_LineStyle          = STYLE_SOLID;
const int              Inp_LabelFontSize      = 9;
const int              Inp_LabelOffsetBars    = 2;          // Số nến dịch chữ label sang phải so với đầu mút line
const color            Inp_ColorMid           = clrSilver;  // xám nhạt
const int              Inp_MidLineWidth       = 1;
const ENUM_LINE_STYLE  Inp_MidLineStyle       = STYLE_DOT;
const color            Inp_ColorLastMajorHigh = clrDeepPink;
const color            Inp_ColorLastMajorLow  = clrGreen;
const int              Inp_LastMajorLineWidth = 2;
const ENUM_LINE_STYLE  Inp_LastMajorLineStyle = STYLE_DASH;
const color            Inp_ColorSweepLow      = clrDodgerBlue;
const color            Inp_ColorSweepHigh     = clrOrangeRed;
const int              Inp_DashX              = 10;         // Khoảng cách mép trái (px)
const int              Inp_DashY              = 18;         // Khoảng cách mép trên (px)
const int              Inp_DashFontSize       = 9;

string   g_prefix     = "CRT_HTF_";
string   g_entryPrefix= "CRT_ENT_";
string   g_htfEnginePrefix = "CRT_LMENG_";
string   g_nameHighLine, g_nameLowLine, g_nameMidLine, g_nameHighLabel, g_nameLowLabel;
string   g_nameLastMajorHighLine, g_nameLastMajorLowLine, g_nameLastMajorHighLabel, g_nameLastMajorLowLabel;

datetime g_lastHTFBarTime = 0;  // phát hiện nến HTF mới đóng
datetime g_lastCurBarTime = 0;  // phát hiện nến mới trên chart hiện tại (điểm kết thúc line)
datetime g_lastLTFBarTime = 0;  // phát hiện nến LTF mới đóng

bool     g_hasData = false;
double   g_htfHigh = 0;
double   g_htfLow  = 0;

datetime g_highStartTime = 0;
datetime g_lowStartTime  = 0;
datetime g_midStartTime  = 0;

//+------------------------------------------------------------------+
// Một "nguồn" biên CRT độc lập: có biên riêng, trạng thái quét râu riêng,
// arm/disarm riêng, magic + hạn mức lệnh riêng. ADJACENT và LASTMAJOR
// đều dùng chung struct này để tránh trùng lặp logic sweep/arm/entry.
//+------------------------------------------------------------------+
struct SCRTSource
{
   string   tag;                          // "LiềnKề" / "Swing" — dùng cho log & tên object
   long     magic;
   int      maxOrdersPerRound;            // hạn mức số lệnh mỗi vòng của riêng nguồn này

   double   boundHigh, boundLow;          // biên trên/dưới hiện dùng cho nguồn này
   datetime boundHighTime, boundLowTime;  // mốc thời gian gắn với biên (phát hiện đổi biên)
   bool     boundReady;

   bool     sweepLowActive;
   double   sweepLowExtreme;
   datetime sweepLowStartTime;
   bool     hasSweptLow;
   double   sweptLow;
   datetime sweptLowTime;

   bool     sweepHighActive;
   double   sweepHighExtreme;
   datetime sweepHighStartTime;
   bool     hasSweptHigh;
   double   sweptHigh;
   datetime sweptHighTime;

   bool     armed;
   int      armDir;         // +1 BUY / -1 SELL
   double   armOppBoundary;
   datetime lastActedBreakTime;

   // Giới hạn theo TÍN HIỆU (1 tín hiệu = 1 lần quét râu xác nhận -> arm).
   // Cả 2 reset về 0 mỗi khi có tín hiệu mới hoặc biên của nguồn đổi.
   int      ordersThisRound;    // số lệnh đã đặt trong vòng hiện tại — reset mỗi khi đóng hết lệnh
   int      profitRounds;       // số vòng đã đóng CÓ LÃI của tín hiệu này (Inp_MaxRoundsPerSignal)
   int      prevOpenCount;      // số lệnh đang mở ở tick trước — dùng phát hiện tập lệnh vừa đóng hết
   double   lastPoolPnl;        // P&L nhóm lệnh lúc còn mở gần nhất — quyết định round vừa rồi lãi hay lỗ

   string   lastEventMsg;
};

SCRTSource  g_srcAdj;   // nguồn H4 liền kề — biên = High/Low nến H4 vừa đóng
SCRTSource  g_srcLM;    // nguồn H4 Swing  — biên = Last Major High/Low (cụm nến H4, Major Swing)
CSMC_Engine g_htfEngine; // chạy trên Inp_HTF, chỉ dùng để lấy current_maj_last_high/low

// --- Vào lệnh (BOS/CHOCH) ---
CTrade         g_trade;
CTelegramRadar g_radar;
CSMC_Engine    g_entryEngine;
double      g_startBalance      = 0;
bool        g_halted            = false;
datetime    g_lastEntryBarTime  = 0;

// --- Shield (bảo vệ tài khoản) ---
bool     g_shieldStopped   = false;  // dừng giao dịch đến hết ngày (DD/Profit limit)
bool     g_accountPassed   = false;  // đạt Auto Pass target -> dừng hẳn
datetime g_lastDayChecked  = 0;
double   g_sodBalance      = 0;      // balance đầu ngày, mốc tính DD/Profit %
string   g_shieldReason    = "";

//============================ ACCESSOR (gọi mọi lúc) =================
double HTF_High()         { return g_htfHigh; }
double HTF_Low()          { return g_htfLow;  }
double HTF_Mid()          { return g_hasData ? (g_htfHigh + g_htfLow) / 2.0 : 0.0; }
bool   HTF_Ready()        { return g_hasData; }
double CRT_SweptLow()     { return g_srcAdj.sweptLow;  }
bool   CRT_HasSweptLow()  { return g_srcAdj.hasSweptLow; }
double CRT_SweptHigh()    { return g_srcAdj.sweptHigh; }
bool   CRT_HasSweptHigh() { return g_srcAdj.hasSweptHigh; }

// Nguồn nào được CHỌN VÀO LỆNH thì nguồn đó được hiển thị (chart + dashboard) — không
// có toggle hiển thị riêng, để tránh cùng lúc hiện 4 đường khi chỉ dùng 1 nguồn.
bool AdjacentEnabled()  { return Inp_EntrySource != H4_Swing; }
bool LastMajorEnabled() { return Inp_EntrySource != H4_LienKe; }

//+------------------------------------------------------------------+
// Kích thước 1 pip theo symbol — đồng bộ với BOT_TLS (GetPipSize).
// Vàng = 0.1 bất kể broker quote 2 hay 3 chữ số thập phân.
//+------------------------------------------------------------------+
double GetPipSize()
{
   string s = _Symbol; StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
   if(StringFind(s, "JPY") >= 0) return 0.01;
   long digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 4) return 0.0001;
   if(digits == 3 || digits == 2) return 0.01;
   return _Point * 10.0;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_nameHighLine       = g_prefix + "HighLine";
   g_nameLowLine        = g_prefix + "LowLine";
   g_nameMidLine        = g_prefix + "MidLine";
   g_nameHighLabel      = g_prefix + "HighLabel";
   g_nameLowLabel       = g_prefix + "LowLabel";
   g_nameLastMajorHighLine  = g_prefix + "LastMajorHighLine";
   g_nameLastMajorLowLine   = g_prefix + "LastMajorLowLine";
   g_nameLastMajorHighLabel = g_prefix + "LastMajorHighLabel";
   g_nameLastMajorLowLabel  = g_prefix + "LastMajorLowLabel";

   g_lastHTFBarTime  = 0;
   g_lastCurBarTime  = 0;
   g_lastLTFBarTime  = 0;
   g_hasData         = false;

   g_srcAdj.tag = "LiềnKề"; g_srcAdj.magic = Inp_MagicNumber;     g_srcAdj.maxOrdersPerRound = Inp_MaxOrders_LienKe;
   g_srcLM.tag  = "Swing";  g_srcLM.magic  = Inp_MagicNumber + 1; g_srcLM.maxOrdersPerRound  = Inp_MaxOrders_Swing;
   ResetSourceFull(g_srcAdj);
   ResetSourceFull(g_srcLM);

   // --- Vào lệnh ---
   g_trade.SetDeviationInPoints(SLIPPAGE_POINTS);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_startBalance      = AccountInfoDouble(ACCOUNT_BALANCE);
   g_halted            = false;
   g_lastEntryBarTime  = 0;

   // --- Shield ---
   g_shieldStopped  = false;
   g_accountPassed  = false;
   g_lastDayChecked = 0;
   g_sodBalance     = g_startBalance;
   g_shieldReason   = "";

   // --- Telegram ---
   if(Inp_EnableTelegram)
   {
      g_radar.Init(Inp_BotToken, Inp_ChatID, Inp_SendScreenshot);
      g_radar.SendMessage(StringFormat(
         "🟢 <b>CRT BOT KHỞI ĐỘNG</b>\n━━━━━━━━━━━━━━━\n"
         "⚙️ <b>Chế độ:</b> %s\n"
         "📊 <b>Nguồn biên:</b> %s\n"
         "🕐 <b>Khung:</b> %s · %s · %s\n"
         "💰 <b>Balance:</b> %s$",
         Inp_EnableTrading ? "VÀO LỆNH" : "CHỈ THEO DÕI (không trade)",
         EntrySourceText(),
         TFToString(Inp_HTF), TFToString(Inp_LTF), TFToString(Inp_EntryTF),
         DoubleToString(g_startBalance, 2)));
   }

   // showZone=Inp_ShowZones: mặc định tắt rectangle zone (isHTF=false vẽ foreground đè nến).
   // Zone vẫn được tính & lưu giá trị (current_buy/sell_zone_entry/sl) để dùng cho lọc entry.
   // MaxZones = 1 (giống BOT_TLS): hàng đợi zone của engine đẩy phần tử CŨ NHẤT ra đầu
   // mảng, nên current_*_zone_entry luôn = queue[0] = zone cũ nhất còn hiệu lực. Chỉ khi
   // giữ đúng 1 zone thì biến đó mới trỏ vào zone HIỆN HÀNH — điều kiện bắt buộc để
   // EntryMode_LimitTaiZoneM1 đặt lệnh đúng mép zone vừa hình thành.
   g_entryEngine.Init(_Symbol, Inp_EntryTF, g_entryPrefix, false, false, Inp_ShowStructure,
        clrDodgerBlue, clrOrangeRed, clrGray, clrDeepSkyBlue, clrRed, clrNONE, clrNONE,
        Inp_EntrySwingMajor, Inp_EntrySwingMinor, 1, 8, 8, Inp_ShowZones);

   if(LastMajorEnabled())
      g_htfEngine.Init(_Symbol, Inp_HTF, g_htfEnginePrefix, true, false, false,
           clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
           Inp_HTF_SwingMajor, Inp_HTF_SwingMinor, 5, 8, 8, false);

   RefreshAll(true);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// Inp_ShowStructure bật cờ showGraphics của CSMC_Engine, mà cờ đó vẽ CẢ 3 nhóm object:
// (1) đường BOS/CHOCH — thứ ta muốn giữ,
// (2) ray "Protected/Active High-Low" (TRACK_*) bám mép phải chart,
// (3) ray "Major Key Level" (KEY_LEVEL) xuất hiện khi có CHOCH.
// Engine là file DÙNG CHUNG với BOT_TLS/BOT_OB_Radar nên không sửa engine để tách cờ;
// thay vào đó xoá (2) và (3) ngay sau mỗi Update() — engine chỉ tạo chúng bên trong
// Update() (CRT không gọi HandleChartEvent) nên xoá ở đây là sạch, không bị vẽ lại.
//+------------------------------------------------------------------+
void StripNonBosObjects()
{
   if(!Inp_ShowStructure)
      return;

   string names[] = { "TRACK_HIGH_ray", "TRACK_HIGH_lbl",
                      "TRACK_LOW_ray",  "TRACK_LOW_lbl",
                      "KEY_LEVEL",      "KEY_LEVEL_lbl" };
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, g_entryPrefix + names[i]);
}

//+------------------------------------------------------------------+
void ResetSourceFull(SCRTSource &s)
{
   s.boundHigh = 0; s.boundLow = 0; s.boundHighTime = 0; s.boundLowTime = 0; s.boundReady = false;
   s.sweepLowActive = false; s.sweepLowExtreme = 0; s.sweepLowStartTime = 0;
   s.hasSweptLow = false; s.sweptLow = 0; s.sweptLowTime = 0;
   s.sweepHighActive = false; s.sweepHighExtreme = 0; s.sweepHighStartTime = 0;
   s.hasSweptHigh = false; s.sweptHigh = 0; s.sweptHighTime = 0;
   s.armed = false; s.armDir = 0; s.armOppBoundary = 0; s.lastActedBreakTime = 0;
   s.ordersThisRound = 0; s.profitRounds = 0; s.prevOpenCount = 0; s.lastPoolPnl = 0;
   s.lastEventMsg = "";
}

//+------------------------------------------------------------------+
// Reset trạng thái quét + huỷ arm/pending của 1 nguồn khi biên của nó đổi
// (nến H4 mới với ADJACENT; Last Major High/Low mới xác nhận với LASTMAJOR).
//+------------------------------------------------------------------+
void ResetSourceSweepAndArm(SCRTSource &s)
{
   s.sweepLowActive  = false;
   s.sweepHighActive = false;
   s.hasSweptLow     = false;
   s.hasSweptHigh    = false;
   s.lastEventMsg    = "";
   s.ordersThisRound = 0;   // biên đổi -> tín hiệu cũ hết hiệu lực, mở lại cả 2 hạn mức
   s.profitRounds    = 0;
   ObjectDelete(0, g_prefix + "SweepLowArrow_"  + s.tag);
   ObjectDelete(0, g_prefix + "SweepHighArrow_" + s.tag);

   if(s.armed)
   {
      s.armed = false;
      CancelEAPendings(s.magic);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);      // line, label, arrow, dashboard
   ObjectsDeleteAll(0, g_entryPrefix); // BOS/CHOCH của engine entry
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   RefreshAll(false);
   ProcessLTFSweep();

   if(Inp_EnableTrading)
   {
      ManageShield();
      CheckAccountStop();
      CheckPoolSL();
      TrackProfitRounds(g_srcAdj);
      TrackProfitRounds(g_srcLM);

      if(!g_halted && !g_shieldStopped && !g_accountPassed)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         CheckDisarmSource(g_srcAdj, bid, ask);  // theo giá, mỗi tick
         CheckDisarmSource(g_srcLM,  bid, ask);

         datetime eb = iTime(_Symbol, Inp_EntryTF, 0);
         if(eb != g_lastEntryBarTime)
         {
            g_lastEntryBarTime = eb;
            g_entryEngine.Update();
            StripNonBosObjects();   // chỉ giữ lại đường BOS/CHOCH trên chart
            ProcessEntrySource(g_srcAdj);
            ProcessEntrySource(g_srcLM);
         }
      }
   }

   UpdateDashboard();
}

//+------------------------------------------------------------------+
void RefreshAll(bool forceUpdate)
{
   bool priceChanged = UpdateHTFPrice(forceUpdate);
   bool timeChanged  = UpdateCurrentBarTime(forceUpdate);

   bool lmChanged = false;
   if(LastMajorEnabled())
   {
      g_htfEngine.Update();
      lmChanged = UpdateLastMajorBoundary(forceUpdate);
   }

   if(!g_hasData)
      return;

   if(priceChanged || timeChanged || lmChanged || forceUpdate)
      DrawAll();
}

//+------------------------------------------------------------------+
bool UpdateHTFPrice(bool force)
{
   datetime htfBarTime = iTime(_Symbol, Inp_HTF, 1);
   if(htfBarTime == 0)
      return false;

   if(!force && htfBarTime == g_lastHTFBarTime)
      return false;

   double htfHigh = iHigh(_Symbol, Inp_HTF, 1);
   double htfLow  = iLow(_Symbol, Inp_HTF, 1);
   if(htfHigh <= 0 || htfLow <= 0)
      return false;

   g_lastHTFBarTime = htfBarTime;
   g_htfHigh = htfHigh;
   g_htfLow  = htfLow;
   g_hasData = true;

   ComputeStartTimes(htfBarTime);

   // H4 vừa cập nhật range mới -> nguồn ADJACENT dùng biên mới, reset toàn bộ trạng thái quét/arm.
   g_srcAdj.boundHigh     = htfHigh;
   g_srcAdj.boundLow      = htfLow;
   g_srcAdj.boundHighTime = htfBarTime;
   g_srcAdj.boundLowTime  = htfBarTime;
   g_srcAdj.boundReady    = true;
   ResetSourceSweepAndArm(g_srcAdj);

   return true;
}

//+------------------------------------------------------------------+
// Đọc Last Major High/Low từ g_htfEngine; nếu 1 trong 2 phía vừa đổi
// (điểm Major Swing mới xác nhận) -> reset toàn bộ trạng thái quét/arm
// của nguồn LASTMAJOR (range cũ hết hiệu lực). Trả về true nếu có đổi.
//+------------------------------------------------------------------+
bool UpdateLastMajorBoundary(bool force)
{
   double   newHigh  = g_htfEngine.current_maj_last_high;
   datetime newHighT = g_htfEngine.current_maj_last_high_time;
   double   newLow   = g_htfEngine.current_maj_last_low;
   datetime newLowT  = g_htfEngine.current_maj_last_low_time;

   bool changed = false;

   if(newHigh != EMPTY_VALUE && newHighT != 0)
   {
      datetime oldT = g_srcLM.boundHighTime;
      if(force || newHighT != oldT)
      {
         g_srcLM.boundHigh     = newHigh;
         g_srcLM.boundHighTime = newHighT;
         if(oldT != 0 && newHighT != oldT)
            changed = true;
      }
   }

   if(newLow != EMPTY_VALUE && newLowT != 0)
   {
      datetime oldT = g_srcLM.boundLowTime;
      if(force || newLowT != oldT)
      {
         g_srcLM.boundLow     = newLow;
         g_srcLM.boundLowTime = newLowT;
         if(oldT != 0 && newLowT != oldT)
            changed = true;
      }
   }

   g_srcLM.boundReady = (g_srcLM.boundHighTime != 0 && g_srcLM.boundLowTime != 0);

   if(changed)
      ResetSourceSweepAndArm(g_srcLM);

   return changed;
}

//+------------------------------------------------------------------+
bool UpdateCurrentBarTime(bool force)
{
   datetime curBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBarTime == 0)
      return false;

   if(!force && curBarTime == g_lastCurBarTime)
      return false;

   g_lastCurBarTime = curBarTime;
   return true;
}

//+------------------------------------------------------------------+
void ComputeStartTimes(datetime htfOpen)
{
   datetime htfEnd = htfOpen + PeriodSeconds(Inp_HTF) - 1;

   int sOld = iBarShift(_Symbol, PERIOD_CURRENT, htfOpen, false);
   int sNew = iBarShift(_Symbol, PERIOD_CURRENT, htfEnd,  false);

   if(sOld < 0 || sNew < 0)
   {
      g_highStartTime = htfOpen;
      g_lowStartTime  = htfOpen;
      g_midStartTime  = htfOpen;
      return;
   }

   int loShift = MathMin(sNew, sOld);
   int hiShift = MathMax(sNew, sOld);

   double maxH = -DBL_MAX;
   double minL =  DBL_MAX;
   int    hiIdx = hiShift;
   int    loIdx = hiShift;

   for(int s = loShift; s <= hiShift; s++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, s);
      double l = iLow(_Symbol,  PERIOD_CURRENT, s);
      if(h > maxH) { maxH = h; hiIdx = s; }
      if(l < minL) { minL = l; loIdx = s; }
   }

   g_highStartTime = iTime(_Symbol, PERIOD_CURRENT, hiIdx);
   g_lowStartTime  = iTime(_Symbol, PERIOD_CURRENT, loIdx);
   g_midStartTime  = iTime(_Symbol, PERIOD_CURRENT, hiShift);
}

//+------------------------------------------------------------------+
void DrawAll()
{
   datetime endTime   = g_lastCurBarTime + Inp_ExtendBars * PeriodSeconds(PERIOD_CURRENT);
   datetime labelTime = endTime + Inp_LabelOffsetBars * PeriodSeconds(PERIOD_CURRENT);

   if(AdjacentEnabled())
   {
      DrawLevelLine(g_nameHighLine, g_highStartTime, endTime, g_htfHigh, Inp_ColorHigh, Inp_LineWidth, Inp_LineStyle);
      DrawLevelLine(g_nameLowLine,  g_lowStartTime,  endTime, g_htfLow,  Inp_ColorLow,  Inp_LineWidth, Inp_LineStyle);

      if(Inp_ShowMidLine)
         DrawLevelLine(g_nameMidLine, g_midStartTime, endTime, HTF_Mid(), Inp_ColorMid, Inp_MidLineWidth, Inp_MidLineStyle);
      else
         ObjectDelete(0, g_nameMidLine);

      if(Inp_ShowLabel)
      {
         string tfName = TFToString(Inp_HTF);
         DrawLevelLabel(g_nameHighLabel, labelTime, g_htfHigh,
                         StringFormat("%s High: %s", tfName, DoubleToString(g_htfHigh, _Digits)), Inp_ColorHigh);
         DrawLevelLabel(g_nameLowLabel, labelTime, g_htfLow,
                         StringFormat("%s Low: %s", tfName, DoubleToString(g_htfLow, _Digits)), Inp_ColorLow);
      }
      else
      {
         ObjectDelete(0, g_nameHighLabel); ObjectDelete(0, g_nameLowLabel);
      }
   }
   else
   {
      ObjectDelete(0, g_nameHighLine);  ObjectDelete(0, g_nameLowLine);  ObjectDelete(0, g_nameMidLine);
      ObjectDelete(0, g_nameHighLabel); ObjectDelete(0, g_nameLowLabel);
   }

   if(LastMajorEnabled() && g_srcLM.boundReady)
   {
      DrawLevelLine(g_nameLastMajorHighLine, g_srcLM.boundHighTime, endTime, g_srcLM.boundHigh,
                     Inp_ColorLastMajorHigh, Inp_LastMajorLineWidth, Inp_LastMajorLineStyle);
      DrawLevelLine(g_nameLastMajorLowLine,  g_srcLM.boundLowTime,  endTime, g_srcLM.boundLow,
                     Inp_ColorLastMajorLow,  Inp_LastMajorLineWidth, Inp_LastMajorLineStyle);

      if(Inp_ShowLastMajorLabel)
      {
         DrawLevelLabel(g_nameLastMajorHighLabel, labelTime, g_srcLM.boundHigh,
                         StringFormat("Last Major High: %s", DoubleToString(g_srcLM.boundHigh, _Digits)), Inp_ColorLastMajorHigh);
         DrawLevelLabel(g_nameLastMajorLowLabel, labelTime, g_srcLM.boundLow,
                         StringFormat("Last Major Low: %s", DoubleToString(g_srcLM.boundLow, _Digits)), Inp_ColorLastMajorLow);
      }
   }
   else
   {
      ObjectDelete(0, g_nameLastMajorHighLine);  ObjectDelete(0, g_nameLastMajorLowLine);
      ObjectDelete(0, g_nameLastMajorHighLabel); ObjectDelete(0, g_nameLastMajorLowLabel);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Xử lý quét râu trên khung LTF — chạy trên nến LTF ĐÃ ĐÓNG (không repaint).
// Chạy cho cả 2 nguồn (nếu biên đã sẵn sàng), mỗi nguồn có state riêng.
//+------------------------------------------------------------------+
void ProcessLTFSweep()
{
   if(!g_hasData)
      return;

   datetime ltfBar0 = iTime(_Symbol, Inp_LTF, 0);
   if(ltfBar0 == 0)
      return;
   if(ltfBar0 == g_lastLTFBarTime)
      return; // chưa có nến LTF mới đóng

   bool firstInit = (g_lastLTFBarTime == 0);
   g_lastLTFBarTime = ltfBar0;
   if(firstInit)
      return; // lần đầu chỉ lấy mốc

   // Nến LTF vừa đóng = shift 1
   double highC  = iHigh(_Symbol,  Inp_LTF, 1);
   double lowC   = iLow(_Symbol,   Inp_LTF, 1);
   double closeC = iClose(_Symbol, Inp_LTF, 1);
   datetime tC   = iTime(_Symbol,  Inp_LTF, 1);

   if(Inp_EntrySource != H4_Swing)
      ProcessSourceSweep(g_srcAdj, highC, lowC, closeC, tC);

   if(Inp_EntrySource != H4_LienKe && g_srcLM.boundReady)
      ProcessSourceSweep(g_srcLM, highC, lowC, closeC, tC);
}

//+------------------------------------------------------------------+
void ProcessSourceSweep(SCRTSource &s, double highC, double lowC, double closeC, datetime tC)
{
   double lo = s.boundLow;
   double hi = s.boundHigh;

   //============ HUỶ SETUP KHI THỦNG MỐC RÂU QUÉT ============
   // Bản chất CRT: quét thanh khoản rồi GIÀNH LẠI biên. Nếu nến LTF đóng vượt ngược qua
   // chính mốc râu đã quét (BUY: đóng dưới sweptLow) thì cú giành lại đã thất bại —
   // setup chết, không được nhồi thêm lệnh nữa dù M1 vẫn có BOS/CHOCH thuận hướng.
   // Đặt TRƯỚC phần dò quét bên dưới để cùng cây nến đó vẫn mở được cụm quét MỚI.
   if(s.armed)
   {
      bool killed = (s.armDir > 0 && s.hasSweptLow  && closeC < s.sweptLow)
                 || (s.armDir < 0 && s.hasSweptHigh && closeC > s.sweptHigh);
      if(killed)
      {
         PrintFormat("[CRT][%s] Nến %s đóng %s mốc râu quét %s -> setup hỏng, huỷ arm + pending.",
                     s.tag, TFToString(Inp_LTF),
                     s.armDir > 0 ? "THỦNG DƯỚI" : "VƯỢT TRÊN",
                     DoubleToString(s.armDir > 0 ? s.sweptLow : s.sweptHigh, _Digits));
         s.armed = false;
         CancelEAPendings(s.magic);
      }
   }

   //================= QUÉT RÂU DƯỚI =================
   if(Inp_DetectLowSweep)
   {
      if(!s.sweepLowActive)
      {
         if(lowC < lo)
         {
            s.sweepLowActive    = true;
            s.sweepLowExtreme   = lowC;
            s.sweepLowStartTime = tC;
            if(closeC > lo)
               ConfirmLowSweep(s, tC);
         }
      }
      else
      {
         if(lowC < s.sweepLowExtreme)
            s.sweepLowExtreme = lowC;
         if(closeC > lo)
            ConfirmLowSweep(s, tC);
      }
   }

   //================= QUÉT RÂU TRÊN =================
   if(Inp_DetectHighSweep)
   {
      if(!s.sweepHighActive)
      {
         if(highC > hi)
         {
            s.sweepHighActive    = true;
            s.sweepHighExtreme   = highC;
            s.sweepHighStartTime = tC;
            if(closeC < hi)
               ConfirmHighSweep(s, tC);
         }
      }
      else
      {
         if(highC > s.sweepHighExtreme)
            s.sweepHighExtreme = highC;
         if(closeC < hi)
            ConfirmHighSweep(s, tC);
      }
   }
}

//+------------------------------------------------------------------+
void ConfirmLowSweep(SCRTSource &s, datetime tConfirm)
{
   s.sweptLow     = s.sweepLowExtreme;
   s.sweptLowTime = tConfirm;
   s.hasSweptLow  = true;
   s.sweepLowActive = false;

   s.lastEventMsg = StringFormat("[%s] QUÉT RÂU DƯỚI ✔  Low=%s | Swept Low=%s | @%s",
                       s.tag,
                       DoubleToString(s.boundLow, _Digits),
                       DoubleToString(s.sweptLow, _Digits),
                       TimeToString(tConfirm, TIME_DATE|TIME_MINUTES));

   PrintFormat("[CRT][%s][%s][LTF %s] %s (cụm quét từ %s)",
               _Symbol, s.tag, TFToString(Inp_LTF), s.lastEventMsg,
               TimeToString(s.sweepLowStartTime, TIME_DATE|TIME_MINUTES));

   if(Inp_MarkSweep)
      MarkConfirmCandle(g_prefix + "SweepLowArrow_" + s.tag, OBJ_ARROW_UP, tConfirm, false, Inp_ColorSweepLow);

   NotifySignal(s, +1);
   ArmSetupSource(s, +1); // quét dưới -> chờ BUY
}

//+------------------------------------------------------------------+
void ConfirmHighSweep(SCRTSource &s, datetime tConfirm)
{
   s.sweptHigh     = s.sweepHighExtreme;
   s.sweptHighTime = tConfirm;
   s.hasSweptHigh  = true;
   s.sweepHighActive = false;

   s.lastEventMsg = StringFormat("[%s] QUÉT RÂU TRÊN ✔  High=%s | Swept High=%s | @%s",
                       s.tag,
                       DoubleToString(s.boundHigh, _Digits),
                       DoubleToString(s.sweptHigh, _Digits),
                       TimeToString(tConfirm, TIME_DATE|TIME_MINUTES));

   PrintFormat("[CRT][%s][%s][LTF %s] %s (cụm quét từ %s)",
               _Symbol, s.tag, TFToString(Inp_LTF), s.lastEventMsg,
               TimeToString(s.sweepHighStartTime, TIME_DATE|TIME_MINUTES));

   if(Inp_MarkSweep)
      MarkConfirmCandle(g_prefix + "SweepHighArrow_" + s.tag, OBJ_ARROW_DOWN, tConfirm, true, Inp_ColorSweepHigh);

   NotifySignal(s, -1);
   ArmSetupSource(s, -1); // quét trên -> chờ SELL
}

//+------------------------------------------------------------------+
// Báo Telegram khi có tín hiệu quét râu xác nhận.
//   - Chế độ CHỈ THEO DÕI (Inp_EnableTrading = false): đây là thông báo DUY NHẤT,
//     nên ghi đủ thông tin để vào tay (biên, râu quét, SL dự kiến).
//   - Chế độ VÀO LỆNH: báo sớm "đã có tín hiệu, đang chờ BOS/CHOCH xác nhận",
//     thông tin lệnh thật sẽ báo tiếp ở NotifyOrderPlaced().
//+------------------------------------------------------------------+
void NotifySignal(SCRTSource &s, int dir)
{
   if(!Inp_EnableTelegram)
      return;

   bool   isBuy = (dir > 0);
   double swept = isBuy ? s.sweptLow : s.sweptHigh;
   double buf   = Inp_SL_BufferPips * GetPipSize();
   double sl    = isBuy ? swept - buf : swept + buf;

   string msg = StringFormat(
      "%s <b>TÍN HIỆU %s — %s</b>\n━━━━━━━━━━━━━━━\n"
      "🔎 <b>Nguồn:</b> %s\n"
      "📏 <b>Biên H4:</b> %s — %s\n"
      "🪝 <b>Râu quét:</b> %s\n"
      "🛡️ <b>SL dự kiến:</b> %s%s\n"
      "%s",
      isBuy ? "🟩" : "🟥",
      isBuy ? "MUA" : "BÁN",
      _Symbol,
      s.tag,
      DoubleToString(s.boundLow, _Digits), DoubleToString(s.boundHigh, _Digits),
      DoubleToString(swept, _Digits),
      DoubleToString(sl, _Digits),
      Inp_SL_Mode == SLMode_KhongDatSL ? " (mốc ảo — không đặt SL trên sàn)" : "",
      Inp_EnableTrading
         ? ("⏳ Đang chờ BOS/CHOCH " + TFToString(Inp_EntryTF) + " xác nhận để vào lệnh...")
         : "👁 <b>Chế độ CHỈ THEO DÕI</b> — bot không tự vào lệnh.");

   g_radar.SendMessageWithPhoto(msg);
}

//+------------------------------------------------------------------+
// Trỏ mũi tên vào ĐÚNG cây nến xác nhận trên TF ĐANG CHẠY:
//   - Tìm cây nến (TF hiện tại) CUỐI CÙNG nằm trong cây LTF xác nhận
//     (vd chạy M1, LTF M15 -> cây M1 đóng cửa của cây M15 xác nhận).
//   - Đặt tại đỉnh (quét trên) / đáy (quét dưới) của chính cây nến đó.
//+------------------------------------------------------------------+
void MarkConfirmCandle(string name, ENUM_OBJECT type, datetime ltfBarOpen, bool isHigh, color clr)
{
   datetime ltfClose = ltfBarOpen + PeriodSeconds(Inp_LTF);

   int shift = iBarShift(_Symbol, PERIOD_CURRENT, ltfClose - 1, false);
   if(shift < 0)
      shift = iBarShift(_Symbol, PERIOD_CURRENT, ltfBarOpen, false);
   if(shift < 0)
      return;

   datetime t     = iTime(_Symbol, PERIOD_CURRENT, shift);
   double   price = isHigh ? iHigh(_Symbol, PERIOD_CURRENT, shift)
                           : iLow(_Symbol,  PERIOD_CURRENT, shift);
   ENUM_ARROW_ANCHOR anchor = isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP;

   DrawSweepArrow(name, type, t, price, clr, anchor);
}

//+------------------------------------------------------------------+
void DrawSweepArrow(string name, ENUM_OBJECT type, datetime t, double price, color clr, ENUM_ARROW_ANCHOR anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, type, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ChartRedraw(0);
}

//============================ VÀO LỆNH (BOS/CHOCH) ==================
// Bật arming sau khi quét râu xác nhận. dir: +1 BUY (quét dưới), -1 SELL (quét trên).
//+------------------------------------------------------------------+
void ArmSetupSource(SCRTSource &s, int dir)
{
   s.armed  = true;
   s.armDir = dir;
   s.armOppBoundary = (dir > 0) ? s.boundHigh : s.boundLow; // biên đối diện
   s.lastActedBreakTime = 0; // cho phép nhận break mới cho setup này
   s.ordersThisRound = 0;   // tín hiệu MỚI -> vòng đếm lại từ đầu
   s.profitRounds    = 0;   //               -> số vòng có lãi cũng đếm lại từ đầu
   PrintFormat("[CRT][%s] ARM %s · chờ BOS/CHOCH %s trên %s (biên đối diện %s)",
               s.tag, dir > 0 ? "BUY" : "SELL",
               dir > 0 ? "LÊN" : "XUỐNG",
               TFToString(Inp_EntryTF),
               DoubleToString(s.armOppBoundary, _Digits));
}

//+------------------------------------------------------------------+
// Ngừng arming + huỷ pending khi giá chạm biên đối diện (theo giá, mỗi tick).
//+------------------------------------------------------------------+
void CheckDisarmSource(SCRTSource &s, double bid, double ask)
{
   if(!s.armed)
      return;

   bool hit = (s.armDir > 0 && ask >= s.armOppBoundary)   // BUY: chạm biên trên
           || (s.armDir < 0 && bid <= s.armOppBoundary);  // SELL: chạm biên dưới
   if(hit)
   {
      PrintFormat("[CRT][%s] Giá chạm biên đối diện %s -> ngừng arming, huỷ pending.",
                  s.tag, DoubleToString(s.armOppBoundary, _Digits));
      s.armed = false;
      CancelEAPendings(s.magic);
      return;
   }

   // Giá đã chạy quá xa đường tín hiệu (biên bị quét râu) -> setup hết "tươi", ngừng chờ.
   // Đo từ chính đường H4 liền kề / Last Major mà râu vừa quét, không phải từ giá râu.
   if(Inp_MaxDistFromLine_Pips > 0)
   {
      double line = (s.armDir > 0) ? s.boundLow : s.boundHigh;
      double cur  = (s.armDir > 0) ? bid : ask;
      double dist = MathAbs(cur - line) / GetPipSize();
      if(dist > Inp_MaxDistFromLine_Pips)
      {
         PrintFormat("[CRT][%s] Giá cách đường tín hiệu %.1f pip (> %.1f) -> ngừng arming, chờ tín hiệu mới.",
                     s.tag, dist, Inp_MaxDistFromLine_Pips);
         s.armed = false;
         CancelEAPendings(s.magic);
      }
   }
}

//+------------------------------------------------------------------+
// Chạy mỗi nến Entry TF mới (sau engine.Update): nếu đang arm & có BOS/CHOCH
// thuận hướng (mới, trong range H4 hiện tại) -> vào lệnh.
//+------------------------------------------------------------------+
void ProcessEntrySource(SCRTSource &s)
{
   if(!s.armed)
      return;
   if(IsInNewsWindow())
      return;
   // Đủ số lệnh cho vòng này -> chờ đóng hết lệnh mới sang vòng mới (reset ở TrackProfitRounds).
   // Đây cũng là trần cho số lệnh mở CÙNG LÚC: vòng chỉ kết thúc khi đóng hết, nên số lệnh
   // đang mở của 1 nguồn không bao giờ vượt quá hạn mức này (trừ khi đặt 0 = không giới hạn).
   if(s.maxOrdersPerRound > 0 && s.ordersThisRound >= s.maxOrdersPerRound)
      return;
   // Đủ số vòng có lãi cho tín hiệu này -> chờ tín hiệu quét râu mới (reset ở ArmSetupSource).
   if(Inp_MaxRoundsPerSignal > 0 && s.profitRounds >= Inp_MaxRoundsPerSignal)
      return;

   int      brkDir  = 0;
   datetime brkTime = 0;
   if(!GetLatestBreak(brkDir, brkTime))
      return;

   datetime rangeStart = iTime(_Symbol, Inp_HTF, 0); // mở cửa cây H4 đang hình thành
   if(brkDir == s.armDir && brkTime != s.lastActedBreakTime && brkTime >= rangeStart)
   {
      // Spread giãn quá ngưỡng -> KHÔNG đánh dấu đã act, để bar sau thử lại (vẫn cùng 1 break
      // đang chờ) chứ không bỏ hẳn setup này chỉ vì spread rộng tạm thời (vd lúc tin ra).
      if(Inp_MaxSpreadPoints > 0 && CurrentSpreadPoints() > Inp_MaxSpreadPoints)
      {
         PrintFormat("[CRT][%s] Bỏ qua vào lệnh: spread %.1f point > ngưỡng %d.",
                     s.tag, CurrentSpreadPoints(), Inp_MaxSpreadPoints);
         return;
      }
      s.lastActedBreakTime = brkTime;
      ExecuteEntry(s, s.armDir);
   }
}

//+------------------------------------------------------------------+
double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid) / _Point;
}

//+------------------------------------------------------------------+
// Lấy sự kiện BOS/CHOCH gần nhất trên nến ĐÃ ĐÓNG của engine entry.
// dir: +1 (lên) / -1 (xuống); trả false nếu không có.
//+------------------------------------------------------------------+
bool GetLatestBreak(int &dir, datetime &t)
{
   int n = ArraySize(g_entryEngine.MajorEvent);
   if(n < 3)
      return false;

   int limit = MathMin(n - 1, 600);
   for(int i = 1; i <= limit; i++)
   {
      int ev = g_entryEngine.MajorEvent[i];
      if(ev != 0)
      {
         dir = (ev > 0) ? 1 : -1; // ±1 BOS, ±2 CHOCH đều tính là break
         t   = g_entryEngine.time[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void ExecuteEntry(SCRTSource &s, int dir)
{
   g_trade.SetExpertMagicNumber(s.magic);

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf   = Inp_SL_BufferPips * GetPipSize();

   bool   isBuy    = (dir > 0);
   bool   useLimit = (Inp_Entry_Mode != EntryMode_Market);

   // EntryMode_Market          -> khớp ngay giá thị trường tại lúc có BOS/CHOCH.
   // EntryMode_LimitTaiH4      -> chờ TẠI đường biên H4 của nguồn này (BUY chờ hồi về
   //   H4 Low, SELL chờ hồi lên H4 High). Giá cố định -> nhiều BOS/CHOCH liên tiếp sẽ
   //   đặt nhiều lệnh CHỒNG NHAU cùng một giá.
   // EntryMode_LimitTaiZoneM1  -> chờ tại mép Zone M1 do chính BOS/CHOCH đó sinh ra
   //   (mép TRÊN zone Buy = current_buy_zone_entry, mép DƯỚI zone Sell =
   //   current_sell_zone_entry). Mỗi BOS/CHOCH tạo zone mới nên mỗi lệnh nằm ở một giá
   //   khác nhau — đây là cách rải lệnh có ý nghĩa khi nhồi nhiều lệnh trong 1 vòng.
   double entry;
   if(Inp_Entry_Mode == EntryMode_LimitTaiZoneM1)
      entry = isBuy ? g_entryEngine.current_buy_zone_entry
                    : g_entryEngine.current_sell_zone_entry;
   else if(Inp_Entry_Mode == EntryMode_LimitTaiH4)
      entry = isBuy ? s.boundLow : s.boundHigh;
   else
      entry = isBuy ? ask : bid;

   if(useLimit)
   {
      if(entry <= 0 || entry == EMPTY_VALUE)
      { PrintFormat("[CRT][%s] Bỏ qua %s: chưa có mốc giá để đặt limit (%s).", s.tag, isBuy ? "BUY" : "SELL",
                    Inp_Entry_Mode == EntryMode_LimitTaiZoneM1 ? "Zone M1 chưa hình thành" : "chưa có biên H4"); return; }

      // Lệnh chờ phải nằm đúng phía so với giá hiện tại và cách tối thiểu stops level của sàn.
      string mocTxt  = (Inp_Entry_Mode == EntryMode_LimitTaiZoneM1) ? "mép Zone M1" : "biên H4";
      double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(isBuy && entry >= ask - stopLvl)
      { PrintFormat("[CRT][%s] Bỏ qua BUY LIMIT: giá đã ở/dưới %s (%s), không đặt chờ được.", s.tag, mocTxt, DoubleToString(entry,_Digits)); return; }
      if(!isBuy && entry <= bid + stopLvl)
      { PrintFormat("[CRT][%s] Bỏ qua SELL LIMIT: giá đã ở/trên %s (%s), không đặt chờ được.", s.tag, mocTxt, DoubleToString(entry,_Digits)); return; }
   }

   // SL "ảo" LUÔN được tính (kể cả chế độ không đặt SL) vì còn dùng để tính lot theo risk,
   // tính TP theo R:R và lọc Inp_MaxSL_Pips. Chỉ khác ở chỗ có gửi lên sàn hay không.
   double sl    = isBuy ? s.sweptLow - buf : s.sweptHigh + buf;
   double tp    = ComputeTP(s, dir, entry, sl);

   if(isBuy  && tp <= entry) { PrintFormat("[CRT][%s] Bỏ qua BUY: TP không hợp lệ (giá đã vượt biên trên).", s.tag); return; }
   if(!isBuy && tp >= entry) { PrintFormat("[CRT][%s] Bỏ qua SELL: TP không hợp lệ (giá đã vượt biên dưới).", s.tag); return; }

   // SL phải nằm ĐÚNG PHÍA so với entry. Nếu giá đã xuyên qua mốc râu quét (BUY: giá rơi
   // xuống dưới sweptLow) thì setup đã hỏng — không được vào lệnh. Không có chốt này thì
   // MathAbs() bên dưới sẽ che mất lỗi: filter MaxSL_Pips vẫn qua, lot tính từ khoảng cách
   // vô nghĩa, và ở chế độ SLMode_KhongDatSL lệnh sẽ vào thật với rủi ro đảo ngược.
   if(isBuy  && sl >= entry)
   { PrintFormat("[CRT][%s] Bỏ qua BUY: giá đã rơi xuống dưới mốc SL %s -> setup hỏng.", s.tag, DoubleToString(sl,_Digits)); return; }
   if(!isBuy && sl <= entry)
   { PrintFormat("[CRT][%s] Bỏ qua SELL: giá đã vượt lên trên mốc SL %s -> setup hỏng.", s.tag, DoubleToString(sl,_Digits)); return; }

   double slDist = MathAbs(entry - sl);
   if(Inp_MaxSL_Pips > 0)
   {
      double slPips = slDist / GetPipSize();
      if(slPips > Inp_MaxSL_Pips)
      {
         PrintFormat("[CRT][%s] Bỏ qua %s: SL cách %.1f pip (> %.1f).",
                     s.tag, isBuy ? "BUY" : "SELL", slPips, Inp_MaxSL_Pips);
         return;
      }
   }

   double lots = CalcLots(slDist);
   if(lots <= 0) { PrintFormat("[CRT][%s] Bỏ qua %s: lots=0 (hết margin hoặc dưới lot tối thiểu).", s.tag, isBuy ? "BUY" : "SELL"); return; }

   // Chế độ KHÔNG ĐẶT SL: gửi SL=0 lên sàn, giao việc cắt lỗ cho Pool SL / Account SL / Daily DD.
   double slOrder = (Inp_SL_Mode == SLMode_KhongDatSL) ? 0 : sl;

   string cmt = "CRT " + (isBuy ? "buy " : "sell ") + s.tag;
   bool   ok;
   if(useLimit)
      ok = isBuy ? g_trade.BuyLimit(lots, entry, _Symbol, slOrder, tp, ORDER_TIME_GTC, 0, cmt)
                 : g_trade.SellLimit(lots, entry, _Symbol, slOrder, tp, ORDER_TIME_GTC, 0, cmt);
   else
      ok = isBuy ? g_trade.Buy(lots, _Symbol, entry, slOrder, tp, cmt)
                 : g_trade.Sell(lots, _Symbol, entry, slOrder, tp, cmt);
   if(ok)
   {
      s.ordersThisRound++;
      PrintFormat("[CRT][%s] ✅ %s%s %.2f lot @%s SL %s TP %s", s.tag,
                  isBuy ? "BUY" : "SELL", useLimit ? " LIMIT" : "",
                  lots, DoubleToString(entry,_Digits),
                  (slOrder > 0 ? DoubleToString(sl,_Digits) : "KHÔNG ĐẶT (ảo " + DoubleToString(sl,_Digits) + ")"),
                  DoubleToString(tp,_Digits));
      NotifyOrderPlaced(s, dir, lots, entry, sl, tp);
   }
   else
      PrintFormat("[CRT][%s] ❌ %s lỗi: %d %s", s.tag, isBuy ? "BUY" : "SELL",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
// Báo Telegram khi lệnh đã khớp (chỉ ở chế độ vào lệnh — đồng bộ với BOT_TLS).
//+------------------------------------------------------------------+
void NotifyOrderPlaced(SCRTSource &s, int dir, double lots, double entry, double sl, double tp)
{
   if(!Inp_EnableTelegram)
      return;

   double slPips = MathAbs(entry - sl) / GetPipSize();
   double tpPips = MathAbs(tp - entry) / GetPipSize();

   string slLine = (Inp_SL_Mode == SLMode_KhongDatSL)
      ? StringFormat("🛡️ <b>SL:</b> KHÔNG ĐẶT trên sàn (mốc ảo %s · %s pip)",
                     DoubleToString(sl, _Digits), DoubleToString(slPips, 1))
      : StringFormat("🛡️ <b>SL:</b> %s (%s pip)",
                     DoubleToString(sl, _Digits), DoubleToString(slPips, 1));

   bool useLimit = (Inp_Entry_Mode != EntryMode_Market);

   g_radar.SendMessageWithPhoto(StringFormat(
      "🛒 <b>%s %s — %s</b>\n━━━━━━━━━━━━━━━\n"
      "🔎 <b>Nguồn:</b> %s\n"
      "📦 <b>Khối lượng:</b> %s lot\n"
      "📍 <b>%s:</b> %s\n"
      "%s\n"
      "🎯 <b>TP:</b> %s (%s pip)\n"
      "💳 <b>Balance:</b> %s$",
      useLimit ? "ĐẶT LỆNH CHỜ" : "ĐÃ VÀO LỆNH",
      dir > 0 ? "MUA" : "BÁN", _Symbol, s.tag,
      DoubleToString(lots, 2),
      Inp_Entry_Mode == EntryMode_LimitTaiZoneM1 ? "Giá chờ (Zone M1)"
        : (Inp_Entry_Mode == EntryMode_LimitTaiH4 ? "Giá chờ (biên H4)" : "Entry"),
      DoubleToString(entry, _Digits),
      slLine,
      DoubleToString(tp, _Digits), DoubleToString(tpPips, 1),
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
}

//+------------------------------------------------------------------+
// Tính giá TP theo Inp_TP_Mode. dir: +1 BUY / -1 SELL. entry/sl là giá đã xác định
// sẵn (SL luôn = râu quét ± đệm, không đổi theo mode) — mode chỉ quyết định TP ở đâu.
//+------------------------------------------------------------------+
double ComputeTP(SCRTSource &s, int dir, double entry, double sl)
{
   if(Inp_TP_Mode == TPMode_RR)
   {
      double riskDist = MathAbs(entry - sl);
      return (dir > 0) ? entry + Inp_TP_RR * riskDist : entry - Inp_TP_RR * riskDist;
   }

   if(Inp_TP_Mode == TPMode_Pips)
   {
      double dist = Inp_TP_FixedPips * GetPipSize(); // quy đổi pip dùng chung công thức với BOT_TLS
      return (dir > 0) ? entry + dist : entry - dist;
   }

   // TPMode_MidBienH4: TP theo Middle/biên của ĐÚNG nguồn đã kích hoạt lệnh này
   // (s.boundHigh/boundLow là biên nến H4 liền kề hoặc Last Major, tuỳ theo s đến từ đâu).
   double mid = (s.boundHigh + s.boundLow) / 2.0;
   if(dir > 0)
   {
      double tp = (Inp_TP_Target == TP_Middle) ? mid : s.boundHigh;
      if(tp <= entry) tp = s.boundHigh;   // đảm bảo TP trên entry — fallback từ Middle sang biên xa hơn
      return tp;
   }
   else
   {
      double tp = (Inp_TP_Target == TP_Middle) ? mid : s.boundLow;
      if(tp >= entry) tp = s.boundLow;
      return tp;
   }
}

//+------------------------------------------------------------------+
// Khối lượng lệnh: theo % tài khoản (SL cho trước) hoặc lot cố định.
// Có giới hạn margin như BOT_TLS: tự cắt lot để tổng margin không vượt ngưỡng.
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots;

   if(!Inp_UseRiskPercent)
      lots = Inp_FixedLotSize;
   else
   {
      if(slDistancePrice <= 0)
         return 0;

      double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney= bal * Inp_RiskPercent / 100.0;
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0 || tickSize <= 0)
         return 0;

      double lossPerLot = slDistancePrice / tickSize * tickVal;
      if(lossPerLot <= 0)
         return 0;

      lots = riskMoney / lossPerLot;
   }

   if(Inp_UseMarginLimit)
   {
      double usedMargin  = AccountInfoDouble(ACCOUNT_MARGIN);
      double maxMargin   = AccountInfoDouble(ACCOUNT_BALANCE) * Inp_MaxMarginPercent / 100.0;
      double marginRoom  = maxMargin - usedMargin;
      if(marginRoom <= 0)
         return 0;

      double marginPerLot = 0;
      double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, askPrice, marginPerLot))
         marginPerLot = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * askPrice)
                      / AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(marginPerLot > 0)
         lots = MathMin(lots, marginRoom / marginPerLot);
   }

   if(stepL > 0) lots = MathFloor(lots / stepL) * stepL;
   if(lots < minL)
      return 0;   // không đủ margin/risk cho 1 lot tối thiểu -> bỏ lệnh, KHÔNG ép lên minLot
   return MathMin(lots, maxL);
}

//+------------------------------------------------------------------+
int CountEAPositions(long magic)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
void CancelEAPendings(long magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
         g_trade.OrderDelete(tk);
   }
}

//+------------------------------------------------------------------+
void CloseAllEAPositions(long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         g_trade.PositionClose(tk);
   }
}

//+------------------------------------------------------------------+
// Chốt an toàn cấp tài khoản: equity <= balance_khởi_tạo * (1 - %).
// Áp dụng cho CẢ 2 nguồn (đóng hết vị thế/pending của cả ADJ và LM).
//+------------------------------------------------------------------+
void CheckAccountStop()
{
   if(g_halted || Inp_AccountSL_Percent <= 0)
      return;

   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double limit = g_startBalance * (1.0 - Inp_AccountSL_Percent / 100.0);
   if(eq <= limit)
   {
      CloseAllBotOrders();
      g_halted = true;
      PrintFormat("[CRT] 🛑 ACCOUNT SL: equity %.2f <= %.2f (-%.1f%%). Đóng tất cả & dừng vào lệnh.",
                  eq, limit, Inp_AccountSL_Percent);
      if(Inp_EnableTelegram)
         g_radar.SendMessage(StringFormat(
            "🛑 <b>ACCOUNT SL — DỪNG GIAO DỊCH</b>\n━━━━━━━━━━━━━━━\n"
            "💸 Equity %s$ <= ngưỡng %s$ (-%s%%)\n"
            "✅ Đã đóng toàn bộ lệnh của bot.",
            DoubleToString(eq, 2), DoubleToString(limit, 2),
            DoubleToString(Inp_AccountSL_Percent, 1)));
   }
}

//+------------------------------------------------------------------+
// Đóng hết vị thế + huỷ hết pending của CẢ 2 nguồn, ngừng arming.
//+------------------------------------------------------------------+
void CloseAllBotOrders()
{
   CloseAllEAPositions(g_srcAdj.magic);
   CancelEAPendings(g_srcAdj.magic);
   CloseAllEAPositions(g_srcLM.magic);
   CancelEAPendings(g_srcLM.magic);
   g_srcAdj.armed = false;
   g_srcLM.armed  = false;
}

//============================ SHIELD (bảo vệ tài khoản) =============
// Reset mốc đầu ngày + kiểm tra Auto Pass / Daily DD / Daily Profit.
// Khác CheckAccountStop (mốc balance lúc khởi động EA): Shield tính theo balance
// ĐẦU NGÀY nên tự làm mới mỗi ngày, giống cách các quỹ prop firm chấm.
//+------------------------------------------------------------------+
void ManageShield()
{
   if(g_accountPassed)
      return;

   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_lastDayChecked)
   {
      g_sodBalance     = AccountInfoDouble(ACCOUNT_BALANCE);
      g_shieldStopped  = false;
      g_shieldReason   = "";
      g_lastDayChecked = today;
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(Inp_AutoPassTarget > 0 && eq >= Inp_AutoPassTarget)
   {
      CloseAllBotOrders();
      g_accountPassed = true;
      g_shieldStopped = true;
      g_shieldReason  = "Đã đạt mục tiêu " + DoubleToString(eq, 2) + "$";
      PrintFormat("[CRT] 🏆 AUTO PASS: equity %.2f >= %.2f. Đóng tất cả & dừng hẳn.", eq, Inp_AutoPassTarget);
      if(Inp_EnableTelegram)
         g_radar.SendMessage(StringFormat(
            "🏆 <b>ĐẠT MỤC TIÊU — DỪNG GIAO DỊCH</b>\n━━━━━━━━━━━━━━━\n"
            "💰 Equity: %s$ (mục tiêu %s$)\n✅ Đã chốt toàn bộ lệnh.",
            DoubleToString(eq, 2), DoubleToString(Inp_AutoPassTarget, 0)));
      return;
   }

   if(g_shieldStopped || g_sodBalance <= 0)
      return;

   if(Inp_DailyDrawdownLimit > 0)
   {
      double lossLimit = g_sodBalance * (1.0 - Inp_DailyDrawdownLimit / 100.0);
      if(eq <= lossLimit)
      {
         CloseAllBotOrders();
         g_shieldStopped = true;
         g_shieldReason  = "Chạm Daily DD " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
         PrintFormat("[CRT] 🛑 DAILY DD: equity %.2f <= %.2f. Nghỉ đến hết ngày.", eq, lossLimit);
         if(Inp_EnableTelegram)
            g_radar.SendMessage(StringFormat(
               "🛑 <b>CHẠM GIỚI HẠN LỖ NGÀY</b>\n━━━━━━━━━━━━━━━\n"
               "💸 Equity: %s$ (đầu ngày %s$, giới hạn -%s%%)\n"
               "😴 Nghỉ giao dịch đến hết ngày.",
               DoubleToString(eq, 2), DoubleToString(g_sodBalance, 2),
               DoubleToString(Inp_DailyDrawdownLimit, 1)));
         return;
      }
   }

   if(Inp_DailyProfitLimit > 0)
   {
      double profitPct = (eq - g_sodBalance) / g_sodBalance * 100.0;
      if(profitPct >= Inp_DailyProfitLimit)
      {
         CloseAllBotOrders();
         g_shieldStopped = true;
         g_shieldReason  = "Đạt Daily Profit +" + DoubleToString(profitPct, 2) + "%";
         PrintFormat("[CRT] 🎯 DAILY PROFIT: +%.2f%% >= %.1f%%. Nghỉ đến hết ngày.", profitPct, Inp_DailyProfitLimit);
         if(Inp_EnableTelegram)
            g_radar.SendMessage(StringFormat(
               "🎯 <b>ĐẠT MỤC TIÊU LÃI NGÀY</b>\n━━━━━━━━━━━━━━━\n"
               "💰 +%s%% (equity %s$)\n✅ Đã chốt toàn bộ lệnh, nghỉ đến hết ngày.",
               DoubleToString(profitPct, 2), DoubleToString(eq, 2)));
      }
   }
}

//+------------------------------------------------------------------+
// Đang trong khung giờ tin tức cần tránh? (Inp_NewsTimes, giờ server)
//+------------------------------------------------------------------+
bool IsInNewsWindow()
{
   if(Inp_NewsTimes == "")
      return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;

   string times[];
   int cnt = StringSplit(Inp_NewsTimes, ',', times);
   for(int i = 0; i < cnt; i++)
   {
      string t = times[i];
      StringTrimLeft(t); StringTrimRight(t);
      if(t == "") continue;

      string parts[];
      if(StringSplit(t, ':', parts) != 2) continue;
      int newsMin = (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
      if(nowMin >= newsMin - Inp_NewsBufferMinutes && nowMin <= newsMin + Inp_NewsBufferMinutes)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// SL theo %: tổng lỗ của nhóm lệnh CÙNG HƯỚNG (gộp cả 2 nguồn) chạm ngưỡng
// % balance thì đóng cả nhóm đó; nhóm ngược hướng vẫn chạy bình thường.
//+------------------------------------------------------------------+
void CheckPoolSL()
{
   if(Inp_Pool_SL_Percent <= 0)
      return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0)
      return;

   double limitUsd = balance * Inp_Pool_SL_Percent / 100.0;
   double buyPnl = 0, sellPnl = 0;
   int    buyCnt = 0, sellCnt = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !IsBotMagic(PositionGetInteger(POSITION_MAGIC))) continue;

      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)
                 + PositionGetDouble(POSITION_COMMISSION);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { buyPnl += pnl; buyCnt++; }
      else                                                        { sellPnl += pnl; sellCnt++; }
   }

   bool closeBuy  = (buyCnt  > 0 && buyPnl  <= -limitUsd);
   bool closeSell = (sellCnt > 0 && sellPnl <= -limitUsd);
   if(!closeBuy && !closeSell)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !IsBotMagic(PositionGetInteger(POSITION_MAGIC))) continue;

      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if((closeBuy && isBuy) || (closeSell && !isBuy))
         g_trade.PositionClose(tk);
   }

   if(closeBuy)  NotifyPoolSL(true,  buyPnl,  balance);
   if(closeSell) NotifyPoolSL(false, sellPnl, balance);
}

//+------------------------------------------------------------------+
void NotifyPoolSL(bool isBuy, double pnl, double balance)
{
   double pct = MathAbs(pnl) / balance * 100.0;
   PrintFormat("[CRT] 🛑 POOL SL %s: lỗ %.2f$ (-%.2f%%) >= ngưỡng %.1f%%. Đã đóng nhóm lệnh này.",
               isBuy ? "BUY" : "SELL", pnl, pct, Inp_Pool_SL_Percent);
   if(Inp_EnableTelegram)
      g_radar.SendMessage(StringFormat(
         "🛑 <b>SL THEO %%: ĐÓNG NHÓM LỆNH %s</b>\n━━━━━━━━━━━━━━━\n"
         "💸 <b>Lỗ:</b> %s$ (-%s%%)\n"
         "🎚️ <b>Ngưỡng:</b> %s%%\n"
         "✅ Nhóm %s vẫn tiếp tục chạy\n"
         "💳 <b>Balance:</b> %s$",
         isBuy ? "MUA" : "BÁN",
         DoubleToString(pnl, 2), DoubleToString(pct, 2),
         DoubleToString(Inp_Pool_SL_Percent, 1),
         isBuy ? "BÁN" : "MUA",
         DoubleToString(balance, 2)));
}

//+------------------------------------------------------------------+
// Đếm "tập lệnh" (round) đã chốt lãi của 1 nguồn: 1 tập = toàn bộ vị thế của
// nguồn đó mở ra rồi đóng hết. Chỉ tính là 1 round khi P&L lúc đóng > 0.
//+------------------------------------------------------------------+
void TrackProfitRounds(SCRTSource &s)
{
   int    cnt = 0;
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != s.magic) continue;
      cnt++;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)
           + PositionGetDouble(POSITION_COMMISSION);
   }

   // Vừa từ "có lệnh" -> "hết lệnh": kết thúc 1 vòng.
   if(s.prevOpenCount > 0 && cnt == 0)
   {
      if(s.lastPoolPnl > 0)
         s.profitRounds++;      // chỉ vòng CÓ LÃI mới tính vào hạn mức số vòng
      s.ordersThisRound = 0;    // vòng mới -> mở lại hạn mức số lệnh (lãi hay lỗ đều reset)
      s.lastPoolPnl     = 0;
   }

   s.prevOpenCount = cnt;
   if(cnt > 0)
      s.lastPoolPnl = pnl;
}

//+------------------------------------------------------------------+
bool IsBotMagic(long magic)
{
   return (magic == g_srcAdj.magic || magic == g_srcLM.magic);
}

//+------------------------------------------------------------------+
string EntrySourceText()
{
   if(Inp_EntrySource == H4_LienKe) return "H4 liền kề";
   if(Inp_EntrySource == H4_Swing)  return "H4 Swing";
   return "Cả 2: H4 liền kề + H4 Swing";
}

//+------------------------------------------------------------------+
// Báo Telegram khi lệnh đóng (SL/TP/bot tự đóng) — đồng bộ với BOT_TLS.
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!Inp_EnableTelegram || trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsBotMagic(magic))
      return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   long   reason    = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string reasonTxt = "👤 Đóng tay / force close";
   if(reason == DEAL_REASON_SL)     reasonTxt = "🔴 Dính Stop Loss";
   if(reason == DEAL_REASON_TP)     reasonTxt = "✅ Chạm Take Profit";
   if(reason == DEAL_REASON_EXPERT) reasonTxt = "🤖 Bot tự đóng (Pool SL / Shield)";

   g_radar.SendMessage(StringFormat(
      "🏁 <b>ĐÓNG LỆNH — %s</b>\n━━━━━━━━━━━━━━━\n"
      "🔎 <b>Nguồn:</b> %s\n"
      "📝 <b>Lý do:</b> %s\n"
      "%s <b>P&L:</b> %s$\n"
      "💳 <b>Balance:</b> %s$",
      _Symbol,
      (magic == g_srcAdj.magic) ? g_srcAdj.tag : g_srcLM.tag,
      reasonTxt,
      pnl >= 0 ? "💰" : "💸",
      DoubleToString(pnl, 2),
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
}

// Dashboard bằng OBJ_LABEL (mỗi dòng 1 màu). Đỏ = quét TRÊN, Xanh = quét DƯỚI.
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!Inp_ShowDashboard)
      return;

   color cNeutral = NeutralTextColor();

   const int MAX_DASH_LINES = 10;
   string lines[]; color clrs[];
   ArrayResize(lines, MAX_DASH_LINES); ArrayResize(clrs, MAX_DASH_LINES);
   int n = 0;

   if(!g_hasData)
   {
      lines[n] = "CRT · chờ dữ liệu HTF..."; clrs[n] = cNeutral; n++;
   }
   else
   {
      lines[n] = StringFormat("CRT · HTF %s · LTF %s", TFToString(Inp_HTF), TFToString(Inp_LTF)); clrs[n] = cNeutral; n++;

      if(AdjacentEnabled())
      {
         lines[n] = StringFormat("H4 High: %s   ·   H4 Middle: %s   ·   H4 Low: %s",
                        DoubleToString(g_htfHigh, _Digits), DoubleToString(HTF_Mid(), _Digits),
                        DoubleToString(g_htfLow,  _Digits)); clrs[n] = cNeutral; n++;

         lines[n] = "▲ Quét trên [" + g_srcAdj.tag + "]: " + SweepStatusText(g_srcAdj, true);  clrs[n] = Inp_ColorSweepHigh; n++;
         lines[n] = "▼ Quét dưới [" + g_srcAdj.tag + "]: " + SweepStatusText(g_srcAdj, false); clrs[n] = Inp_ColorSweepLow;  n++;
      }

      if(LastMajorEnabled() && g_srcLM.boundReady)
      {
         lines[n] = StringFormat("Last Major High: %s   ·   Last Major Low: %s",
                        DoubleToString(g_srcLM.boundHigh, _Digits), DoubleToString(g_srcLM.boundLow, _Digits));
         clrs[n] = cNeutral; n++;

         lines[n] = "▲ Quét trên [" + g_srcLM.tag + "]: " + SweepStatusText(g_srcLM, true);  clrs[n] = Inp_ColorSweepHigh; n++;
         lines[n] = "▼ Quét dưới [" + g_srcLM.tag + "]: " + SweepStatusText(g_srcLM, false); clrs[n] = Inp_ColorSweepLow;  n++;
      }

      string entryTxt; color entryClr = cNeutral;
      if(!Inp_EnableTrading)
         entryTxt = "Vào lệnh: TẮT (chỉ theo dõi)";
      else if(g_halted)
      { entryTxt = "Vào lệnh: 🛑 HALT (account SL)"; entryClr = Inp_ColorSweepHigh; }
      else if(g_accountPassed || g_shieldStopped)
      { entryTxt = "Vào lệnh: 🛡 SHIELD — " + g_shieldReason; entryClr = Inp_ColorSweepHigh; }
      else if(IsInNewsWindow())
      { entryTxt = "Vào lệnh: ⏸ tạm dừng (khung giờ tin tức)"; entryClr = Inp_ColorSweepHigh; }
      else
      {
         if(Inp_EntrySource == H4_LienKe)
            entryTxt = "Vào lệnh (" + TFToString(Inp_EntryTF) + ") · " + EntryStatusText(g_srcAdj);
         else if(Inp_EntrySource == H4_Swing)
            entryTxt = "Vào lệnh (" + TFToString(Inp_EntryTF) + ") · " + EntryStatusText(g_srcLM);
         else
            entryTxt = "Vào lệnh (" + TFToString(Inp_EntryTF) + ") · " + EntryStatusText(g_srcAdj) +
                       "  |  " + EntryStatusText(g_srcLM);
      }
      lines[n] = entryTxt; clrs[n] = entryClr; n++;

      if(Inp_EnableTrading)
      {
         double eq = AccountInfoDouble(ACCOUNT_EQUITY);
         double dayPct = (g_sodBalance > 0) ? (eq - g_sodBalance) / g_sodBalance * 100.0 : 0;
         lines[n] = StringFormat("Equity %s$ · Ngày %+.2f%%%s",
                        DoubleToString(eq, 2), dayPct,
                        Inp_DailyDrawdownLimit > 0
                           ? StringFormat(" (DD tối đa -%.1f%%)", Inp_DailyDrawdownLimit) : "");
         clrs[n] = (dayPct < 0) ? Inp_ColorSweepHigh : cNeutral; n++;
      }
   }

   ArrayResize(lines, n); ArrayResize(clrs, n);
   for(int i = 0; i < n; i++)
      SetDashLabel(i, lines[i], clrs[i]);
   for(int i = n; i < MAX_DASH_LINES; i++)
      ObjectDelete(0, g_prefix + "Dash" + (string)i);
}

//+------------------------------------------------------------------+
string EntryStatusText(SCRTSource &s)
{
   string armTxt = "—";
   if(s.armed)
      armTxt = (s.armDir > 0) ? "chờ BUY" : "chờ SELL";

   string limitTxt = "";
   if(s.maxOrdersPerRound > 0)
      limitTxt += StringFormat(" · lệnh/vòng %d/%d", s.ordersThisRound, s.maxOrdersPerRound);
   else
      limitTxt += StringFormat(" · lệnh/vòng %d", s.ordersThisRound);
   if(Inp_MaxRoundsPerSignal > 0)
      limitTxt += StringFormat(" · vòng %d/%d", s.profitRounds, Inp_MaxRoundsPerSignal);

   return StringFormat("[%s] %s · đang mở %d%s", s.tag, armTxt,
                       CountEAPositions(s.magic), limitTxt);
}

//+------------------------------------------------------------------+
string SweepStatusText(SCRTSource &s, bool isHigh)
{
   if(isHigh)
   {
      if(s.sweepHighActive)
         return StringFormat("theo dõi · Cao nhất %s", DoubleToString(s.sweepHighExtreme, _Digits));
      if(s.hasSweptHigh)
         return StringFormat("✔ Cao nhất %s @%s",
                             DoubleToString(s.sweptHigh, _Digits),
                             TimeToString(s.sweptHighTime, TIME_MINUTES));
      return "—";
   }
   else
   {
      if(s.sweepLowActive)
         return StringFormat("theo dõi · Thấp nhất %s", DoubleToString(s.sweepLowExtreme, _Digits));
      if(s.hasSweptLow)
         return StringFormat("✔ Thấp nhất %s @%s",
                             DoubleToString(s.sweptLow, _Digits),
                             TimeToString(s.sweptLowTime, TIME_MINUTES));
      return "—";
   }
}

//+------------------------------------------------------------------+
void SetDashLabel(int idx, string text, color clr)
{
   string name = g_prefix + "Dash" + (string)idx;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Inp_DashX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Inp_DashY + idx * (Inp_DashFontSize + 8));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Inp_DashFontSize);
   ObjectSetString(0,  name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
// Chọn màu chữ trung tính tương phản với nền chart (đen trên nền sáng, trắng trên nền tối).
//+------------------------------------------------------------------+
color NeutralTextColor()
{
   long bg = ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int r = (int)(bg & 0xFF);
   int g = (int)((bg >> 8) & 0xFF);
   int b = (int)((bg >> 16) & 0xFF);
   double lum = 0.299 * r + 0.587 * g + 0.114 * b;
   return lum > 128 ? clrBlack : clrWhite;
}

//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime t1, datetime t2, double price, color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void DrawLevelLabel(string name, datetime t, double price, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Inp_LabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
}
//+------------------------------------------------------------------+
