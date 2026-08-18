//+------------------------------------------------------------------+
//|                                             CRT_MultiTF_EA.mq5   |
//|                                                          AnhTuan |
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.62"

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
//   [1.17] Đổi tên enum ENUM_CRT_SOURCE cho dễ hiểu: CRT_SRC_ADJACENT -> Bien_LienKe,
//     CRT_SRC_LASTMAJOR -> Bien_Swing, CRT_SRC_BOTH -> Ca2_LienKe_Va_Swing (vẫn giữ nguyên
//     3 lựa chọn + toàn bộ logic chạy song song 2 nguồn độc lập, chỉ đổi tên hiển thị).
//     Tag nội bộ của 2 nguồn (dùng trong log + dashboard) cũng đổi "ADJ"/"LM" -> "LiềnKề"/"Swing".
//   [1.18] Viết lại mô tả Inp_EntrySource bằng tiếng Việt có dấu, bỏ từ "arm" khó hiểu,
//     giải thích rõ nghĩa từng lựa chọn. Lưu ý: bản thân TÊN 3 lựa chọn trong dropdown
//     (Bien_LienKe/Bien_Swing/Ca2_LienKe_Va_Swing) không thể có dấu/khoảng trắng — giới hạn
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
//       · EntryMode_LimitTaiBienHTF — đặt lệnh CHỜ ngay tại đường biên H4 của chính nguồn
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
//   [1.34] Thêm chế độ vào lệnh thứ 3: EntryMode_LimitTaiZoneEntry — đặt lệnh chờ tại mép
//     Zone M1 do chính BOS/CHOCH đó sinh ra (mép TRÊN zone Buy / mép DƯỚI zone Sell,
//     tức current_buy_zone_entry / current_sell_zone_entry của engine entry).
//     LÝ DO: EntryMode_LimitTaiBienHTF lấy giá = biên H4 vốn CỐ ĐỊNH, nên khi có nhiều
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
//   [1.36] (A) BỎ NHÃN KHUNG THỜI GIAN GẮN CỨNG. Logic vốn đã chạy đúng theo Inp_HTF /
//     Inp_LTF / Inp_EntryTF (không có PERIOD_M1/M15/H4 nào trong phần tính toán — các
//     PERIOD_CURRENT còn lại chỉ để quy đổi thời gian sang vị trí nến khi VẼ). Nhưng mọi
//     NHÃN đều ghi cứng "H4"/"M1", nên đổi Inp_HTF sang D1 thì dashboard/Telegram vẫn
//     hiện "H4 High" -> gây tưởng là bot bị gắn cứng. Nay tất cả dùng TFToString(Inp_*).
//     Đổi tên enum bỏ tiền tố TF: H4_LienKe->Bien_LienKe, H4_Swing->Bien_Swing,
//     EntryMode_LimitTaiH4->EntryMode_LimitTaiBienHTF,
//     EntryMode_LimitTaiZoneM1->EntryMode_LimitTaiZoneEntry. Tên group Input cũng đổi
//     thành KHUNG GỐC (HTF) / KHUNG QUÉT RÂU (LTF) / KHUNG VÀO LỆNH (Entry).
//     Muốn bot bám theo TF của chart đang mở: chọn "Current timeframe" trong dropdown.
//
//   [1.36] (B) THÊM MODE VÀO LỆNH THỨ 2 — Inp_TradeMode:
//     · TradeMode_BOS_KhungEntry (mặc định, như cũ): quét râu LTF -> arm -> chờ
//       BOS/CHOCH trên khung Entry -> vào lệnh theo Inp_Entry_Mode.
//     · TradeMode_NenQuet_LTF (mới): vào lệnh NGAY trên khung LTF, bỏ qua khung Entry.
//         Nến LTF thọc râu ra ngoài biên = NẾN GỐC
//           ├─ 2.1  nến gốc đóng lại BÊN TRONG biên ("pinbar": râu ngoài, thân trong)
//           │        -> cặp lệnh, limit @ 50% RÂU (mút râu -> đáy/đỉnh THÂN)
//           └─ 2.2  nến gốc đóng BÊN NGOÀI biên -> xét ĐÚNG 1 cây LTF kế tiếp:
//                    ├─ 2.2.1  đóng BÊN TRONG biên (cần) VÀ close >= High(gốc) khi quét
//                    │          biên dưới / close <= Low(gốc) khi quét biên trên (đủ)
//                    │          -> cặp lệnh, limit @ 50% TOÀN THÂN nến này (High+Low)/2
//                    └─ 2.2.2  còn lại -> bỏ setup VÀ ĐỐT BIÊN (s.lineUsed): ngưng mọi
//                               setup trên biên đó tới khi biên ĐỔI GIÁ TRỊ (nến HTF mới
//                               với nguồn LiềnKề / điểm Swing mới với nguồn Swing).
//     Mỗi setup vào ĐÚNG 1 CẶP: 1 market + 1 limit @ mốc 50%, đếm 2 đơn vị vào
//     Inp_MaxOrders_*. Inp_Entry_Mode KHÔNG áp dụng cho Mode 2 (mode này tự quyết định).
//     Refactor kèm theo: tách lõi đặt lệnh thành PlaceOneOrder() dùng chung cho cả 2 mode;
//     ExecuteEntry() (Mode 1) và ExecutePairEntry() (Mode 2) chỉ lo chọn giá.
//     LƯU Ý: ProcessLTFSweep() chạy NGOÀI khối bảo vệ của OnTick nên ExecutePairEntry()
//     phải tự kiểm EnableTrading / halt / Shield / news / spread / hạn mức vòng.
//
//   [1.37] Bổ sung luật vòng đời cho Mode Nến quét + tách lại bố cục Input.
//     (a) 1 BIÊN = 1 LẦN DÙNG: s.lineUsed nay bật ở CẢ 3 kết cục (2.1 vào lệnh,
//         2.2.1 vào lệnh, 2.2.2 thất bại). Nghĩa là mỗi đường biên chỉ xét ĐÚNG lần
//         quét đầu tiên và chỉ vào ĐÚNG 1 cặp lệnh; mọi lần quét sau đều bỏ qua,
//         tới khi biên đổi giá trị (nến HTF mới / điểm Swing mới).
//     (b) Hạn mức Inp_MaxOrders_* nay chỉ áp cho Mode BOS. Trước đó nếu để = 1 thì
//         cặp lệnh của Mode 2 bị chặn mất vế limit — luật (a) đã là trần chặt hơn.
//     (c) BIÊN MỚI -> huỷ mọi lệnh chờ chưa khớp của biên cũ. ResetSourceSweepAndArm()
//         trước đây chỉ gọi CancelEAPendings() khi s.armed = true, mà Mode 2 không dùng
//         arm -> lệnh chờ sẽ sống sót qua biên mới. Nay huỷ vô điều kiện.
//     (d) 1 LỆNH CHẠM TP -> lệnh còn lại cùng chiều: chưa khớp thì huỷ, đã khớp thì dời
//         SL về entry (HandlePairAfterTP, gọi từ OnTradeTransaction). Chỉ dời SL khi có
//         lợi để không nới lỏng SL đang tốt. OnTradeTransaction bỏ điều kiện chặn
//         Inp_EnableTelegram ở đầu hàm — nếu không, tắt Telegram là mất luôn luật này.
//     (e) Inp_FarFromLine_Action: khi giá đã cách biên quá Inp_MaxDistFromLine_Pips,
//         chọn cách xử lý vế MARKET của cặp lệnh — Far_BoLenhMarket (mặc định, khuyến
//         nghị: chỉ giữ limit 50%) / Far_ChuyenThanhLimitTaiLine / Far_VanVaoMarket.
//     (f) Input chia lại thành nhóm CHUNG (mọi mode) và nhóm RIÊNG từng mode, đánh số
//         1..9 để dễ tra: 1,4,5,6,7,9 = chung; 2,8 = riêng Mode BOS; 3 = riêng Mode Nến quét.
//
//   [1.38] CẢ 2 MODE: giá chạm đường Middle -> huỷ mọi lệnh CHỜ cùng chiều chưa khớp
//     (CancelPendingsAtMiddle, chạy mỗi tick cho từng nguồn). Ý nghĩa: Middle là đích
//     của setup — giá đã đi tới đó mà lệnh chờ vẫn chưa khớp thì cơ hội đã trôi qua,
//     giữ lệnh lại chỉ rước rủi ro vào lúc sóng đã hết. Chỉ đụng LỆNH CHỜ; vị thế đã
//     khớp vẫn để TP/SL của nó tự chạy. Middle lấy theo biên của CHÍNH nguồn đó, đồng
//     bộ với cách ComputeTP() tính TP_Middle (nguồn liền kề và Swing có Middle khác nhau).
//     Đặt NGOÀI khối bảo vệ của OnTick vì huỷ lệnh chờ luôn an toàn, cần chạy được cả
//     khi Shield/halt đang chặn vào lệnh mới.
//
//   [1.39] BỘ LỌC CHẤT LƯỢNG NẾN cho nhánh 2.1 (PassesWickFilter):
//     Bối cảnh: backtest cho thấy 2.1 nhận cả những cây "thọc qua biên rồi đi tiếp" —
//     thân dài, râu ngắn, đóng ngược hướng lệnh. Đó là nến xu hướng ngược chứ không
//     phải cú quét thanh khoản bị từ chối.
//     Luật: CHỈ lọc khi nến đóng NGƯỢC chiều lệnh
//        · quét biên dưới (chờ BUY) mà nến GIẢM  -> cần râu DƯỚI >= thân
//        · quét biên trên (chờ SELL) mà nến TĂNG -> cần râu TRÊN >= thân
//     Nến đã đóng THUẬN chiều lệnh thì tự nó thể hiện lực -> miễn lọc.
//     Trượt lọc -> KHÔNG bỏ ngay mà chờ ĐÚNG 1 cây kế tiếp (nhánh 2.1b, m2WaitKind=2):
//     cây đó phải đóng TRONG biên VÀ qua bộ lọc thì mới vào, limit @ 50% râu của CHÍNH
//     cây đó; không đạt -> bỏ setup, biên coi như đã dùng (giống 2.2.2).
//     Kèm theo: khi chờ cây thứ 2 (cả nhánh 2.1b lẫn 2.2), nếu cây đó thọc sâu hơn nến
//     gốc thì cập nhật sweepLowExtreme/sweepHighExtreme -> SL bám đúng mút râu thật sự,
//     trước đây chỉ lấy theo nến gốc nên SL có thể nằm trong vùng đã bị xuyên qua.
//
//   [1.40] CHẶN VÀO LỆNH KHI GIÁ ĐÃ VƯỢT MIDDLE (bổ sung cho luật 1.38, đặt trong
//     PlaceOneOrder nên bao CẢ market lẫn limit, CẢ 2 mode):
//       1.38 mới chỉ HUỶ lệnh chờ khi giá chạm Middle, còn lệnh MARKET vẫn vào bình
//       thường dù giá đã ở bên kia Middle. Backtest 2026.08.09 22:00 cho thấy hậu quả:
//       Middle = 4340.599 nhưng market BUY khớp ở 4343.852 — đã vượt đích, dư địa còn
//       lại gần như bằng 0. Với TP_Middle thì còn vô lý hẳn: TP nằm DƯỚI entry của lệnh
//       BUY, ComputeTP() âm thầm lùi TP về biên đối diện thay vì báo lỗi.
//     Nay: entry >= Middle (BUY) hoặc entry <= Middle (SELL) -> bỏ lệnh, ghi log rõ.
//     LƯU Ý khi chỉnh chiến lược: luật này áp dụng cho MỌI TP mode, kể cả TPMode_RR /
//     TPMode_Pips vốn không lấy Middle làm đích. Lý do giữ vậy: Middle là mốc đo "setup
//     đã chạy được bao xa", độc lập với việc TP đặt ở đâu.
//
//   [1.41] TÁCH THIẾT LẬP TP theo mode VÀ theo nhánh setup. Trước đây cả 2 mode dùng
//     chung 1 bộ Inp_TP_* nên không thể để pinbar ăn Middle còn engulfing ăn 2R.
//     Nay có 3 bộ độc lập:
//       · Mode BOS/CHOCH      -> Inp_TP_Mode / Target / RR / FixedPips  (nhóm 2)
//       · Nhánh 2.1 + 2.1b    -> Inp_TP21_*  (nhóm 3) — mặc định TPMode_MidBienH4 + TP_Middle
//       · Nhánh 2.2.1         -> Inp_TP22_*  (nhóm 3) — mặc định TPMode_RR + RR 2.0
//     Cách nối dây: struct STPConfig gói 4 tham số TP, tạo qua TPCfg_ModeBOS() /
//     TPCfg_Pinbar() / TPCfg_Engulfing(), truyền xuyên ExecutePairEntry -> PlaceOneOrder
//     -> ComputeTP. Làm vậy để không phải thêm 4 tham số vào từng tầng gọi, và mỗi lần
//     thêm nhánh setup mới chỉ cần thêm 1 hàm TPCfg_*() chứ không sửa chữ ký hàm.
//     Lưu ý: cặp lệnh (market + limit 50%) của cùng 1 setup dùng CHUNG bộ TP — nhưng
//     giá TP hai lệnh vẫn khác nhau nếu chọn TPMode_RR/Pips vì entry khác nhau.
//
//   [1.43] LỌC "QUÉT KHÔNG RÕ RÀNG" — Inp_MinSweepPips (mặc định 3 pip):
//     Vấn đề: chênh lệch giá giữa các sàn cỡ vài pip đủ để một cây nến chạm biên ở sàn
//     này mà không chạm ở sàn kia -> cùng một chiến lược cho kết quả khác nhau.
//     Luật: râu phải thọc qua biên >= Inp_MinSweepPips mới được tính là quét.
//       · Cây đầu quét NÔNG hơn ngưỡng -> bỏ qua cây đó, chờ ĐÚNG 1 cây kế tiếp
//         (m2WaitKind = 3).
//       · Cây kế tiếp quét đủ sâu -> CHÍNH NÓ trở thành NẾN GỐC, rồi chạy lại toàn bộ
//         cơ chế 2.1 / 2.1b / 2.2 như thường. Nghĩa là cặp nến xét pinbar/engulfing lúc
//         này là cây thứ 2 và thứ 3.
//       · Cây kế tiếp vẫn không đủ (hoặc không chạm biên) -> bỏ tín hiệu, đốt biên.
//     Áp cho CẢ 2 nguồn (liền kề + Swing) vì nằm trong ProcessSweepCandleMode.
//     REFACTOR kèm theo: tách ClassifyOriginCandle() — phần quyết định "nến gốc này vào
//     lệnh ngay (2.1) hay chờ tiếp (2.1b/2.2)". Cần tách vì nay được gọi từ 2 chỗ: lúc
//     dò nến gốc lần đầu, và lúc cây kế tiếp lên ngôi nến gốc. Tiện thể gộp luôn 2 nhánh
//     BUY/SELL vốn đối xứng nhau thành 1 (trước đây copy-paste 2 lần ~40 dòng).
//     LƯU Ý về lineUsed: nhánh kind 3 KHÔNG đốt biên ngay khi vào (khác kind 1 & 2) —
//     nếu cây kế tiếp lên ngôi nến gốc thì biên vẫn còn nguyên quyền vào lệnh.
//
//   [1.44] GIÁ CHẠM BIÊN ĐỐI DIỆN -> DỜI SL VỀ ENTRY (hoà vốn), cho CẢ 2 MODE và cả 2
//     nguồn: MoveSLToEntryAtOppositeBound() chạy mỗi tick.
//       · BUY  (quét biên dưới) -> biên đối diện = boundHigh, chạm thì kéo SL lên entry
//       · SELL (quét biên trên) -> biên đối diện = boundLow
//     Mục đích: từ mốc đó trở đi lệnh chỉ được gồng lãi, không thể quay đầu thành lỗ.
//     Chỉ đụng VỊ THẾ đã khớp; lệnh chờ do CancelPendingsAtMiddle lo.
//     Đặt ngoài khối bảo vệ của OnTick vì siết SL luôn an toàn, cần chạy cả khi
//     Shield/halt đang chặn vào lệnh mới.
//     Refactor kèm: tách MovePositionToBreakeven(ticket, reason) dùng chung với
//     HandlePairAfterTP — cả 2 chỗ đều chỉ dời SL khi việc đó CÓ LỢI (BUY: entry cao
//     hơn SL hiện tại), để không bao giờ nới lỏng một SL đang tốt. Trước đây logic này
//     chỉ nằm trong HandlePairAfterTP, dễ lệch nhau nếu sửa một chỗ mà quên chỗ kia.
//
//   [1.45] MỞ RỘNG MỐC TP: ENUM_CRT_TP từ 2 lên 4 giá trị —
//       0 TP_Middle              Middle của CHÍNH nguồn      (Swing -> Middle Last Major)
//       1 TP_BienDoiDien         Biên đối diện của chính nguồn
//       2 TP_Middle_LienKe       Middle của nến HTF LIỀN KỀ        <- mới
//       3 TP_BienDoiDien_LienKe  Biên đối diện của nến HTF liền kề  <- mới
//     Lý do KHÔNG tạo thêm bộ input TP riêng cho nguồn Swing: với nguồn liền kề thì
//     0≡2 và 1≡3 (biên của chính nó CHÍNH LÀ biên liền kề), nên 4 lựa chọn này chỉ tạo
//     khác biệt ở nguồn Swing — đúng thứ cần. Thêm bộ input riêng theo nguồn sẽ nhân đôi
//     số ô cấu hình mà không mở thêm khả năng nào.
//     Công dụng thực tế: vào lệnh theo Last Major (biên rộng, ít nhiễu) nhưng chốt lãi
//     theo nến HTF hiện tại (mục tiêu gần, thực tế hơn).
//     An toàn: nếu chọn mốc liền kề mà g_srcAdj chưa sẵn sàng thì tự lùi về biên của
//     chính nguồn, không để ComputeTP trả về số vô nghĩa.
//     Giữ nguyên giá trị 0/1 nên file .set cũ vẫn load đúng; chỉ nới dải hợp lệ 0..3.
//
//   [1.46] TÁCH BỘ TP THEO NGUỒN (thay cho cách gộp enum ở 1.45 — cách đó không cho
//     phép 2 nguồn dùng chế độ TP khác nhau, chỉ cho chọn mốc khác nhau).
//     Nay có ĐỦ 6 bộ TP độc lập = 3 nhánh setup × 2 nguồn:
//       [BOS · LiềnKề] [BOS · Swing] [2.1 · LiềnKề] [2.1 · Swing] [2.2 · LiềnKề] [2.2 · Swing]
//     Mỗi bộ đủ 4 tham số (Mode / Target / RR / Pips) -> 24 ô cấu hình.
//     HAI ENUM MỐC KHÁC NHAU theo nguồn, đúng yêu cầu:
//       · ENUM_CRT_TP    (2 mốc) cho nguồn LIỀN KỀ — biên của nó CHÍNH LÀ biên HTF liền
//         kề, nên thêm mốc "…_LienKe" chỉ trùng lại chính nó, không đưa vào dropdown.
//       · ENUM_CRT_TP_SW (4 mốc) cho nguồn SWING — thêm TPSW_Middle_LienKe và
//         TPSW_BienDoiDien_LienKe: vào theo Last Major nhưng chốt theo nến HTF hiện tại.
//     Cách nối dây: 2 enum trên được ép về thang chung ENUM_TP_ANCHOR (4 giá trị) lưu
//     trong STPConfig.anchor, nên ComputeTP() chỉ phải xử lý MỘT kiểu. Giá trị 2 enum
//     xếp trùng thứ tự với ENUM_TP_ANCHOR nên ép kiểu trực tiếp, không cần bảng tra.
//     SCRTSource thêm cờ isSwing để TPCfg_*() biết lấy bộ nào — dùng cờ thay vì so sánh
//     magic để ý định rõ ràng và không phụ thuộc quy ước Magic+1.
//     LƯU Ý: TPCfg_*() phải khai báo SAU struct SCRTSource (MQL5 yêu cầu kiểu đã biết),
//     nên khối này nằm dưới struct chứ không nằm cạnh STPConfig.
//
//   [1.47] CÔNG TẮC BẬT/TẮT TỪNG SETUP CON của Mode Nến quét — 6 nút = 3 nhánh × 2 nguồn:
//       Inp_On_21_LK  / Inp_On_21b_LK  / Inp_On_22_LK   (nguồn liền kề)
//       Inp_On_21_SW  / Inp_On_21b_SW  / Inp_On_22_SW   (nguồn Swing)
//     Tra qua SetupEnabled_21/21b/22(s) — cùng cơ chế chọn theo cờ s.isSwing như TPCfg_*.
//     QUAN TRỌNG — tắt setup thì KHÔNG ĐỐT BIÊN: khi gặp ca bị tắt, bot bỏ vào lệnh và
//     trả s.lineUsed về false. Mục đích: bật/tắt một nhánh KHÔNG được ảnh hưởng nhánh
//     khác — nếu vẫn đốt biên thì tắt 2.1 sẽ vô tình cướp mất cơ hội của 2.2 ở những
//     lần quét sau trên cùng đường biên đó.
//     Ghi chú phân loại: 2.1b là biến thể VÀO CHẬM 1 NẾN của 2.1 (nến gốc trượt lọc
//     râu/thân nên phải chờ thêm), không phải loại setup thứ 3 — nhưng vẫn tách công tắc
//     riêng để đo được nó có đáng giữ hay chỉ làm loãng thống kê.
//     Còn nhánh "quét không rõ ràng" (m2WaitKind = 3) KHÔNG có công tắc vì nó là bộ lọc
//     đầu vào, sau đó vẫn dẫn về 2.1 hoặc 2.2 — tắt bằng cách để Inp_MinSweepPips = 0.
//
//   [1.48] Inp_PinbarChiThuan_LK / _SW — CHỈ NHẬN PINBAR THUẬN CHIỀU.
//     Bối cảnh: nhánh 2.1 vốn gộp HAI loại nến mà 6 công tắc ở 1.47 không tách được:
//       (a) nến THUẬN chiều lệnh (quét đáy + nến tăng) -> qua lọc ngay, không cần đo râu
//       (b) nến NGƯỢC chiều nhưng râu >= thân          -> cũng qua lọc
//     Bật cờ này thì loại thẳng nhóm (b), chỉ giao dịch pinbar "sạch" kiểu (a).
//     Cài trong PassesWickFilter() nên áp cho CẢ 2.1 lẫn 2.1b — nghĩa là cây thứ 2 ở
//     nhánh 2.1b cũng phải thuận chiều mới được vào.
//     Hệ quả dây chuyền cần biết: nến nhóm (b) giờ TRƯỢT lọc -> rơi vào nhánh chờ 2.1b
//     thay vì vào lệnh ngay. Muốn bỏ hẳn nhóm đó thì tắt luôn Inp_On_21b_*.
//     Để per-source cho nhất quán với mọi thiết lập khác của Mode Nến quét.
//
//   [1.49] SỬA LOG SAI ở nhánh 2.1/2.1b (chỉ là chữ, logic vào lệnh vẫn đúng từ 1.48).
//     Journal ghi cứng "râu>=thân đạt" cho mọi ca qua lọc, nhưng PassesWickFilter có
//     HAI đường qua khác hẳn nhau: nến THUẬN chiều thì qua ngay mà KHÔNG hề đo râu/thân;
//     chỉ nến NGƯỢC chiều mới phải so râu >= thân. Khi bật Inp_PinbarChiThuan_* thì
//     đường thứ hai bị chặn hẳn, nên dòng log cũ mô tả một phép so sánh chưa từng chạy.
//     Nay thêm WickPassReason() để in đúng lý do thật, và dòng "2.1b KHÔNG ĐỦ ĐK" cũng
//     phân biệt được là trượt vì râu ngắn hay vì đang bật chế độ chỉ nhận nến thuận.
//
//   [1.50] NHÁNH 2.1b — MỐC 50% ĐỔI SANG RÂU QUÉT THẬT CỦA NẾN GỐC.
//     Trước đây lấy theo râu của CÂY THỨ 2. Soi ca 2026.08.04 08:00-08:15 (nguồn Swing,
//     SELL) bằng Data Window mới lộ ra vấn đề: cây thứ 2 có đỉnh 4068.806, vẫn nằm DƯỚI
//     đường Last Major 4069.405 — tức là nó KHÔNG HỀ chạm biên. "Râu phía quét" của nó
//     (0.563) chẳng liên quan gì tới cú quét thanh khoản thật, vốn xảy ra ở nến gốc
//     08:00 (đỉnh 4072.959). Mốc chờ tính ra chỉ là một mức hồi kỹ thuật ngẫu nhiên.
//     Nay lấy theo râu quét của nến gốc: từ mút râu tới mép thân của CHÍNH nến gốc.
//     Ca trên: mốc chờ đổi từ 4068.524 -> (4072.959 + 4068.240)/2 = 4070.600, nằm đúng
//     trong vùng thanh khoản vừa bị quét.
//     Cần thêm trường m2OriginBodyEdge vào SCRTSource vì trước đó chỉ lưu High/Low của
//     nến gốc, không đủ để dựng lại râu quét.
//     KHÔNG áp dụng cho nhánh 2.2.1 — mốc ở đó là 50% TOÀN THÂN cây thứ 2, vốn là lựa
//     chọn riêng và cây thứ 2 ở nhánh đó luôn là cây quyết định thật sự.
//     Đề xuất cùng đợt "bắt cây thứ 2 qua phép đo râu/thân (bỏ đường tắt thuận chiều)"
//     đã cân nhắc và CHỦ ĐỘNG BỎ QUA: "cứ nến thuận chiều là được" là hành vi mong muốn.
//
//   [1.51] VÁ 3 LỖI PHÁT HIỆN QUÉT SAI — soi từ ca 2026.08.04 16:00 (nguồn Swing nhận
//     nhầm "quét biên trên" trong khi giá đã giao dịch hẳn TRÊN đường Last Major High
//     4069.405 từ nhiều giờ trước; nến M15 15:45 H=4088.883 nằm trọn phía trên đường):
//     (A) TƯ CÁCH QUÉT THEO TỪNG PHÍA BIÊN (sweepEligibleLow/High): một phía chỉ được
//         nhận diện quét sau khi có bằng chứng giá giao dịch BÊN TRONG biên —
//           · lúc biên hình thành: cấp theo giá thực tế (bid) — giá đang trong biên thì
//             cấp ngay, đang ngoài (khởi động nguội giữa cây HTF, hoặc biên Swing bị giá
//             bỏ lại) thì KHÔNG cấp; bid=0 (OnInit trước tick đầu) cũng không cấp;
//           · sau đó: một nến LTF ĐÓNG CỬA trong biên sẽ cấp, hiệu lực TỪ CÂY KẾ TIẾP
//             (GrantSweepEligibility gọi SAU ProcessSourceSweep) — cây quay về từ ngoài
//             không thể tự cấp rồi tự bị nhận nhầm là quét;
//           · bất đẳng thức NGHIÊM NGẶT: đóng đúng ngay tại biên chưa tính là trong biên;
//           · tư cách TIÊU HAO khi chuỗi quét bắt đầu — chuỗi thất bại mà giá ở lại bên
//             ngoài thì không còn cờ nào để lần reset biên sau tái kích quét ảo.
//         Gác ở cả 2 mode: Mode 2 chặn lúc dò nến gốc; Mode 1 chặn lúc MỞ cụm quét mới
//         (cụm đang theo dõi dở vẫn chạy tiếp vì nó mở lúc còn đủ tư cách).
//     (B) ĐỔI BIÊN PHÍA NÀO CHỈ THU HỒI TƯ CÁCH PHÍA ĐÓ: ResetSourceSweepAndArm nhận
//         thêm (highChanged, lowChanged). Trước đây Last Major Low đổi cũng gỡ khoá phía
//         High — chính là ngòi nổ của ca trên. Trạng thái THEO SETUP (chờ cây 2, lineUsed,
//         hạn mức, lệnh chờ) vẫn reset toàn bộ vì setup dang dở đã mất căn cứ.
//     (C) XỬ LÝ NẾN LTF TRƯỚC, CẬP NHẬT BIÊN SAU trong OnTick: sửa lỗi lệch-một-nến —
//         nến LTF cuối chu kỳ HTF trước đây bị so với biên mà chính nó góp phần tạo ra
//         (không bao giờ vượt được) thay vì biên cũ; cú quét thật ở nến đó bị bỏ sót.
//         Hệ quả đã cân nhắc: cặp lệnh sinh ra ở nến đó sẽ bị biên mới huỷ vế limit ngay
//         sau đó (đúng luật), vế market giữ nguyên.
//
//   [1.52] KHỞI ĐỘNG NGUỘI — MỒI TƯ CÁCH QUÉT TỪ LỊCH SỬ. Bản 1.51 quá thận trọng:
//     khởi động là cả 2 phía chưa có tư cách, cây LTF đầu tiên của phiên chạy phải hy
//     sinh làm "bằng chứng giá trong biên" — nếu chính cây đó là cây quét (backtest
//     04/08 00:00 quét Last Major High 4064.700) thì cú quét bị bỏ qua oan. Nhưng "bot
//     chưa ghi nhận" không có nghĩa là không có dữ liệu: lịch sử LTF luôn sẵn trong MT5.
//     Nay ở lần lấy mốc đầu tiên, dùng CLOSE của nến LTF đã đóng gần nhất để cấp tư cách
//     — nến đó đóng TRƯỚC lúc bot chạy nên vẫn giữ nguyên tắc "hiệu lực từ cây sau".
//     Vẫn an toàn cho ca giá đang ở ngoài biên: nến lịch sử đóng ngoài thì không cấp.
//
//   [1.53] TƯ CÁCH QUÉT ĐỔI THÀNH TRẠNG THÁI LIÊN TỤC — vá lỗ hổng còn lại của 1.51/1.52.
//     Backtest 2026.08.04 16:15 vẫn lặp lại y hệt ca quét ảo cũ: nến M15 H=4088.586
//     L=4084.268 nằm TRỌN trên Last Major High 4069.405 mà vẫn vào nhánh 2.2. Truy ra
//     HAI lỗ hổng cùng một gốc — cờ tư cách chỉ biết CẤP, không bao giờ THU HỒI:
//       · giá leo hẳn lên trên biên suốt 6 tiếng nhưng cờ vẫn giữ true từ lần cấp lúc
//         08:15, nên khi biên phía Low đổi lúc 16:00 (mở lại lineUsed) là quét ảo nổ ngay;
//       · tệ hơn, hàm cấp chạy NGAY SAU ProcessSourceSweep trên CÙNG cây nến, mà nhánh
//         2.1/2.1b theo định nghĩa đóng cửa TRONG biên -> vừa tiêu hao xong đã cấp lại.
//         Cơ chế "tiêu hao" thêm ở 1.51 vì thế chưa bao giờ có tác dụng thật -> đã gỡ bỏ.
//     Nay rút về ĐÚNG MỘT bất biến, kiểm chứng được bằng mắt trên chart:
//         phía biên X đủ tư cách  <=>  nến LTF ĐÓNG GẦN NHẤT đóng cửa BÊN TRONG phía X.
//     RefreshSweepEligibility() gán TUYỆT ĐỐI cả 2 phía (không còn chỉ-gán-một-chiều),
//     gọi ở 3 nơi duy nhất: sau mỗi nến LTF đóng, lúc biên đổi giá trị, và lúc khởi động.
//     Giá ra ngoài -> mất tư cách ngay; quay vào -> có lại, hiệu lực từ cây kế tiếp.
//
//   [1.53] NHÃN ĐƯỜNG KẺ BÁM MÉP PHẢI KHUNG NHÌN. Trước đây đầu mút line và nhãn gắn
//     cứng ở "nến hiện tại + 50 nến" nên zoom to lên là nhãn nằm ngoài màn hình, mất hút.
//     Nay VisibleEdgeTimes() chừa sẵn ở mép phải một khoảng tính bằng PIXEL vừa đủ chứa
//     chữ (bề rộng chữ cố định theo pixel, còn 1 nến chiếm bao nhiêu pixel thì đổi theo
//     zoom), line kết thúc ngay trước khoảng đó, nhãn nằm gọn bên trong. Thêm
//     OnChartEvent(CHARTEVENT_CHART_CHANGE) để zoom/kéo chart là vẽ lại — chỉ đụng đối
//     tượng đồ hoạ, không chạm logic vào lệnh.
//
//   [1.54] LOG TƯ CÁCH QUÉT: BÁO HẬU QUẢ, KHÔNG BÁO TRẠNG THÁI. Bản 1.53 in mỗi lần
//     trạng thái lật, mà giá dập dình quanh đường line thì lật liên tục (backtest
//     2026.08.04: mất 11:45 -> đủ 12:15 -> mất 12:45 -> đủ 13:15 -> mất 13:30) — ngập
//     log mà không nói được điều người dùng cần biết. Nay im lặng khi đổi trạng thái,
//     chỉ in khi tư cách THỰC SỰ CHẶN một cú vượt biên, và mỗi đợt giá ra ngoài biên chỉ
//     in ĐÚNG 1 dòng (cờ elgBlockLogged*, reset lúc vừa mất tư cách).
//
//   [1.55] GỠ BỎ HẲN LỌC ĐỘ SÂU QUÉT (Inp_MinSweepPips). Quyết định của người dùng sau
//     khi soi kịch bản: line -> cây quét 1 pip -> vài cây lởn vởn quanh line, có cây ra
//     1-2 pip -> vài cây không chạm -> rồi một cây quét 10 pip kèm setup 2.1/2.2 hoàn hảo.
//     Luật cũ xử lý ca này rất tệ: cây 1 pip vào nhánh chờ (m2WaitKind=3), cây kế không
//     đủ 3 pip là ĐỐT BIÊN ngay -> toàn bộ phần sau, kể cả cú quét 10 pip đẹp nhất, bị bỏ
//     qua sạch. Đã xảy ra thật trong backtest 2026.08.04: cú chạm 1.6 pip lúc 12:30 giết
//     đường H4 lúc 13:00, nằm chết tới 16:00.
//     Nay bỏ hẳn cho đồng nhất: râu vượt biên BAO NHIÊU CŨNG TÍNH LÀ QUÉT, mọi cú quét đi
//     thẳng vào 2.1 / 2.2 như nhau. Gỡ luôn nhánh chờ m2WaitKind=3, hàm SweepDepthPips()
//     và input Inp_MinSweepPips (76 -> 75 input, .set phải bỏ dòng tương ứng).
//     ĐÃ BÁO TRƯỚC VÀ NGƯỜI DÙNG CHẤP NHẬN: cách này KHÔNG cứu được kịch bản trên. Cây
//     quét 1 pip nếu đóng lại trong biên giờ thành pinbar 2.1 hợp lệ -> vào lệnh ngay
//     trên cú chạm 1 pip rồi đốt biên, cú quét 10 pip sau đó vẫn bị bỏ qua. Đổi lại được
//     sự đồng nhất: chỉ còn 2 cổng lọc thay vì 3, không còn nhánh chờ ngoại lệ nào.
//     Nếu backtest cho thấy nhiễu tăng, phương án chưa dùng tới là: quét nông = CHƯA CHẠM
//     BIÊN (bỏ qua hẳn, KHÔNG đốt biên) — giữ được cả lọc nhiễu lẫn cú quét sâu về sau.
//
//   [1.56] DỌN SẠCH THEO MÔ HÌNH "CỬA SỔ 2 CÂY". Sau khi bỏ lọc độ sâu, vòng đời một
//     lần quét gọn lại đúng như người dùng đúc kết: TỐI ĐA 2 CÂY NẾN kể từ lúc chạm biên
//     (cây gốc + đúng 1 cây xác nhận), hết 2 cây là ngã ngũ — vào lệnh hoặc đốt biên.
//     Hai việc dọn theo:
//     (a) BỎ Inp_PinbarChiThuan_LK / _SW. Hai công tắc này cho phép loại thẳng nến ngược
//         chiều mà không xét râu/thân — một nhánh luật thứ ba nằm ngoài mô hình 2.1/2.1b.
//         Cả hai vốn đang mặc định false nên gỡ đi KHÔNG đổi hành vi, chỉ bớt 2 input và
//         xoá 3 chỗ rẽ nhánh trong log. PassesWickFilter() nay không cần tham số nguồn.
//     (b) BỎ TRẠNG THÁI "tư cách quét" (4 biến + hàm RefreshSweepEligibility + 3 điểm
//         gọi + toàn bộ log đổi trạng thái). Thay bằng CameFromInside() đọc thẳng giá
//         đóng cửa nến LTF shift 2 đúng lúc cần. Kết quả LOGIC Y HỆT (trạng thái cũ chẳy
//         qua chẳy lại cũng chỉ để nhớ "nến liền trước đóng trong hay ngoài biên"), nhưng
//         hết sạch log ngập kiểu "ĐỦ/MẤT tư cách" mỗi khi giá dập dình quanh line, và
//         không còn phải mồi trạng thái lúc khởi động nguội hay lúc biên đổi.
//         ResetSourceSweepAndArm() vì thế bỏ luôn 2 tham số "phía nào đổi" của v1.51.
//     LƯU Ý: cổng "đi từ trong ra" KHÔNG bị bỏ — nó chỉ đổi cách tính. Bỏ hẳn là quét ảo
//     kiểu 2026.08.04 16:00 quay lại ngay.
//
//   [1.57] IN RÕ SỰ KIỆN ĐỔI BIÊN của nguồn Swing. Soi backtest 2026.08.04 thấy một
//     mắt xích luôn bị hụt khi đọc journal: 08:15 vào lệnh 2.1 -> biên bị đốt (lineUsed)
//     -> im lặng suốt 8 tiếng -> rồi 16:15 "đột nhiên" có dòng log xét quét trở lại.
//     Nguyên nhân nằm ở giữa mà không ai thấy: 16:00 nến H4 đóng -> engine xác nhận điểm
//     Major Swing mới -> biên Swing đổi giá trị -> lineUsed mở lại -> đường biên tưởng đã
//     chết bỗng sống lại. Nay in đúng 1 dòng ngay tại thời điểm đó, ghi rõ phía nào đổi
//     và giá cũ -> giá mới, nên chuỗi nhân quả đọc thẳng trên journal là hiểu.
//     Chỉ in cho nguồn Swing; nguồn liền kề đổi biên mỗi nến HTF theo định nghĩa nên in
//     ra chỉ tổ ngập journal.
//
//   [1.58] "1 BIÊN = 1 LẦN DÙNG" TÁCH THEO TỪNG PHÍA. Chính dòng log thêm ở 1.57 làm lộ
//     lỗi: 08:00 biên Swing đổi CẢ 2 phía (trên 4064.700->4069.405) -> 08:15 vào lệnh 2.1
//     trên biên trên -> 08:45 TP. Đến 16:00 chỉ biên DƯỚI đổi (4042.403->4045.486), vậy
//     mà biên TRÊN — vẫn nguyên giá trị 4069.405, đã xét xong và đã ăn TP — cũng bị mở
//     lại và lôi ra kiểm tra tiếp. Nguyên nhân: lineUsed là MỘT cờ dùng chung cho cả 2
//     phía, nên reset là mất sạch trí nhớ của cả hai.
//     Nay tách lineUsedLow / lineUsedHigh, ResetSourceSweepAndArm() nhận lại 2 tham số
//     (highChanged, lowChanged) và chỉ xoá cờ của đúng phía có giá trị biên mới. Kiểm tra
//     cờ chuyển xuống sau khi đã biết chiều quét, nên bỏ luôn lệnh chặn sớm đầu hàm.
//     Dashboard cũng tách 3 trạng thái: cả 2 biên đã dùng / chỉ biên trên / chỉ biên dưới.
//     Lưu ý phân biệt với v1.51: hồi đó tách theo phía là để thu hồi TƯ CÁCH QUÉT (nay
//     tính tại chỗ, không còn cờ); lần này tách là cho CỜ ĐÃ DÙNG — hai việc khác nhau.
//
//   [1.59] BÁO "BIÊN ĐÃ DÙNG" NGAY TRÊN ĐƯỜNG LINE, KHÔNG NHỒI VÀO DASHBOARD.
//     Bản 1.58 báo bằng chữ trên dashboard ("biên trên đã dùng — còn chờ quét biên dưới")
//     làm dashboard dài ra và che chart. Nay đường biên nào đã xét xong thì tự đổi sang
//     XÁM và nhãn thêm "· đã dùng" — nhìn lướt chart là biết đường nào còn hiệu lực,
//     đường nào chỉ còn là dấu vết. Tách theo phía nên biên trên có thể xám trong khi
//     biên dưới vẫn giữ màu. Dashboard rút gọn, chỉ còn báo việc ĐANG diễn ra (chờ nến 2).
//     Kèm theo: RefreshAll() phải coi thay đổi của cờ "đã dùng" là một lý do vẽ lại
//     (g_lastUsedMask). Thiếu điều kiện này thì đường vừa xét xong vẫn giữ màu cũ cho tới
//     lần vẽ kế tiếp vì lý do khác, tức hiển thị sai trong một quãng.
//
//   [1.60] SỬA CÂU CHỮ LOG ĐỔI BIÊN + CHỐT MỘT QUYẾT ĐỊNH.
//     (a) Bản 1.57 ghi "biên mở lại cho lần quét mới" -> gây hiểu nhầm là đường biên CŨ
//         được hồi sinh. Bản chất khác hẳn: điểm Major Swing mới làm đường Last Major
//         NHẢY SANG GIÁ KHÁC (vd 4045.486 -> 4065.367); đường cũ biến mất khỏi chart,
//         đường mới thay chỗ và chưa từng được dùng nên bộ đếm "1 biên = 1 lần dùng" của
//         nó bắt đầu từ 0 — không liên quan gì tới lịch sử đường cũ. Câu log nay nói rõ
//         "đường KHÁC thay chỗ đường cũ", và ghi thêm "phía kia giữ nguyên trạng thái"
//         để thấy ngay luật per-side của 1.58 đang có hiệu lực.
//     (b) CHỐT: khi biên MỘT phía đổi, vẫn huỷ lệnh chờ của CẢ 2 phía. Xem lý do đầy đủ
//         ở chỗ gọi CancelEAPendings() trong ResetSourceSweepAndArm(). Tóm tắt: TP neo
//         vào Middle, mà Middle phụ thuộc cả 2 biên, nên một phía đổi là lệnh chờ phía
//         kia đã mang TP lạc hậu. Đây KHÔNG phải chỗ sót của luật per-side.
//
//   [1.61] SIẾT TỶ LỆ RÂU/THÂN CỦA PINBAR: 1.0 -> 1.5. Trước đây râu chỉ cần BẰNG thân
//     là đạt; nay đòi râu dài gấp rưỡi thân thì sự từ chối giá mới được coi là rõ ràng.
//     Khai báo bằng hằng số Inp_WickBodyRatio ngay trên PassesWickFilter() (theo yêu cầu
//     người dùng: sửa thẳng trong code, không thêm vào màn hình Input) -> số input giữ
//     nguyên 73, .set không phải đụng tới.
//     PHẠM VI: áp cho CẢ 2.1 (nến gốc) lẫn 2.1b (cây thứ 2) vì hai nhánh gọi chung hàm
//     lọc. KHÔNG đụng nhánh 2.2 — nhánh đó xét engulfing, chưa bao giờ gọi bộ lọc râu.
//     KHÔNG đụng nến THUẬN chiều lệnh — loại này vẫn qua thẳng, không đo gì.
//     Log ở 3 chỗ đã sửa để in kèm ngưỡng cần đạt (vd "râu 0.689 < 1.5 x thân 2.077 =
//     3.116"), tránh phải nhẩm tay khi soi lại.
//     DỰ ĐOÁN TÁC ĐỘNG khi backtest: nhiều ca 2.1 sẽ bị đẩy sang 2.1b, và cây thứ 2 của
//     2.1b cũng khó qua hơn -> tổng số lệnh giảm ở cả hai nhánh.
//     Nến gần doji (thân ~ 0) vẫn luôn qua bất kể tỷ lệ, vì ngưỡng cần đạt cũng ~ 0 —
//     không hại, doji có râu dài đúng là nến từ chối giá.
//
//   GHI CHÚ MÔ HÌNH — chỉ còn 2 cổng, và một cửa sổ 2 cây:
//     1. ĐI TỪ TRONG RA: nến LTF liền trước phải đóng cửa TRONG biên phía đang xét.
//     2. CHẠM BIÊN: râu vượt qua line -> QUÉT CRT ĐÃ XONG, dù chỉ vượt 1 point.
//     Rồi cửa sổ 2 cây: cây gốc đóng trong biên -> 2.1 (đạt râu/thân thì vào luôn, không
//     đạt thì chờ 1 cây -> 2.1b); cây gốc đóng ngoài biên -> chờ 1 cây engulfing -> 2.2.
//     Hết cây thứ 2 là chốt sổ: vào lệnh hoặc đốt biên. Không theo dõi thêm cây nào nữa.
// ==============================================================================

#include <Trade/Trade.mqh>
#include <CSMC_Engine.mqh>     // cần có trong MQL5/Include (dùng chung với BOT_TLS, BOT_OB_Radar)
#include <Telegram_Radar.mqh>  // dùng chung với BOT_TLS

// Lưu ý: MQL5 không cho phép tên enum chứa dấu tiếng Việt hay khoảng trắng (giới hạn của
// ngôn ngữ), nên dropdown trong Input sẽ luôn hiện đúng các tên sau — không thể hiện chữ
// có dấu/khoảng trắng được. Ý nghĩa từng tên xem ở comment của input tương ứng bên dưới.
enum ENUM_CRT_TRADE_MODE { TradeMode_BOS_KhungEntry, TradeMode_NenQuet_LTF };
enum ENUM_CRT_FAR_ACTION { Far_BoLenhMarket, Far_ChuyenThanhLimitTaiLine, Far_VanVaoMarket };
enum ENUM_CRT_ENTRY_MODE { EntryMode_Market, EntryMode_LimitTaiBienHTF, EntryMode_LimitTaiZoneEntry };
// Mốc giá mà tới đó thì lệnh CHỜ chưa khớp coi như hết cơ hội -> huỷ.
// Middle: chặt hơn, coi như setup đã ăn nửa đường thì thôi.
// Biên đối diện: rộng hơn, để lệnh chờ sống tới tận đích cuối của cú CRT.
enum ENUM_CRT_CANCEL_AT { CancelAt_Middle, CancelAt_BienDoiDien };
enum ENUM_CRT_SL_MODE { SLMode_RauQuet, SLMode_KhongDatSL };
enum ENUM_CRT_TP_MODE { TPMode_MidBienH4, TPMode_RR, TPMode_Pips };
// Mốc đặt TP khi chọn TPMode_MidBienH4. Hai enum riêng vì 2 nguồn có số lựa chọn khác nhau:
//   · Nguồn LIỀN KỀ — chỉ bám biên của chính nó (biên của nó CHÍNH LÀ biên HTF liền kề,
//     nên thêm mốc "liền kề" cũng chỉ trùng lại chính nó).
//   · Nguồn SWING   — ngoài biên Last Major của mình, còn được chốt theo nến HTF liền kề.
enum ENUM_CRT_TP
{
   TP_Middle,               // Middle của biên HTF liền kề
   TP_BienDoiDien           // Biên đối diện của HTF liền kề
};

enum ENUM_CRT_TP_SW
{
   TPSW_Middle,             // Middle của Last Major (biên của chính nguồn Swing)
   TPSW_BienDoiDien,        // Biên Last Major đối diện
   TPSW_Middle_LienKe,      // Middle của nến HTF LIỀN KỀ
   TPSW_BienDoiDien_LienKe  // Biên đối diện của nến HTF LIỀN KỀ
};

// Mốc đã "giải mã" dùng nội bộ — gộp 2 enum trên về một thang chung để ComputeTP()
// chỉ phải xử lý 1 kiểu. Giá trị trùng khớp với ENUM_CRT_TP_SW nên ép kiểu trực tiếp được.
enum ENUM_TP_ANCHOR
{
   Anchor_Mid_Nguon,        // Middle của chính nguồn kích hoạt lệnh
   Anchor_Bien_Nguon,       // Biên đối diện của chính nguồn
   Anchor_Mid_LienKe,       // Middle của nến HTF liền kề
   Anchor_Bien_LienKe       // Biên đối diện của nến HTF liền kề
};
enum ENUM_CRT_SOURCE { Bien_LienKe, Bien_Swing, Ca2_LienKe_Va_Swing };

// ============ 1. VẬN HÀNH CHUNG — áp dụng cho MỌI mode ============
input group "=== 1. CHUNG · Bot / Risk / SL / TP ==="
input bool             Inp_EnableTrading    = true;       // Tự động vào lệnh (tắt = chỉ theo dõi + báo tín hiệu)
input ENUM_CRT_TRADE_MODE Inp_TradeMode     = TradeMode_NenQuet_LTF;    // Cách xác nhận vào lệnh:
input ENUM_CRT_SOURCE  Inp_EntrySource      = Ca2_LienKe_Va_Swing; // Vào lệnh theo biên giá nào của khung gốc:
input long             Inp_MagicNumber      = 20260713;   // Magic (nguồn Swing tự dùng Magic+1)
input int              Inp_MaxSpreadPoints  = 0;         // Spread tối đa cho phép vào lệnh, point (0 = tắt)
input bool             Inp_UseRiskPercent   = false;     // Lot theo % tài khoản (tắt = dùng lot cố định)
input double           Inp_RiskPercent      = 1.0;       // Risk mỗi lệnh, % tài khoản
input double           Inp_FixedLotSize     = 0.1;       // Lot cố định mỗi lệnh
input double           Inp_AccountSL_Percent= 0.0;       // Đóng hết khi tài khoản âm quá % (từ lúc mở bot, 0=tắt)
input ENUM_CRT_SL_MODE Inp_SL_Mode          = SLMode_RauQuet; // Cách đặt SL:
input double           Inp_SL_BufferPips    = 30;        //   • nếu SLMode_RauQuet — SL lùi ra ngoài râu quét (pip)
input double           Inp_MaxSL_Pips       = 200;       // SL xa hơn số pip này thì bỏ lệnh (0=không giới hạn)
input double           Inp_MaxDistFromLine_Pips = 100;   // Giá cách biên quá số pip này -> Mode BOS: bỏ chờ; Mode Nến quét: xử lý theo mục 3 (0=tắt)
input ENUM_CRT_CANCEL_AT Inp_CancelPendingAt = CancelAt_Middle; // Huỷ lệnh chờ chưa khớp khi giá chạm:
input double           Inp_Pool_SL_Percent  = 0;         // Nhóm lệnh cùng chiều lỗ quá % này thì đóng cả nhóm (0=tắt)

// ============ 2. RIÊNG MODE BOS/CHOCH (TradeMode_BOS_KhungEntry) ============
// Quét râu LTF -> arm -> chờ BOS/CHOCH khung Entry -> vào lệnh, có thể NHỒI nhiều
// lệnh theo nhiều BOS/CHOCH liên tiếp. Cấp bậc hạn mức:
//   1 tín hiệu (1 lần quét râu xác nhận)
//     ├─ vòng 1: vào tối đa Inp_MaxOrders_* lệnh -> đóng HẾT -> sang vòng mới
//     ├─ vòng 2: ... (chỉ vòng đóng CÓ LÃI mới tính vào hạn mức vòng)
//     └─ đủ Inp_MaxRoundsPerSignal vòng lãi -> dừng, chờ tín hiệu mới.
// Mỗi nguồn (liền kề / Swing) đếm riêng. Vì vòng chỉ kết thúc khi đóng hết lệnh,
// Inp_MaxOrders_* cũng chính là trần cho số lệnh mở CÙNG LÚC của nguồn đó.
// KHÔNG áp dụng cho Mode Nến quét — mode đó bị chặn bởi luật "1 biên = 1 cặp lệnh".
input group "=== 2. RIÊNG Mode BOS/CHOCH ==="
input ENUM_CRT_ENTRY_MODE Inp_Entry_Mode    = EntryMode_Market; // Cách vào lệnh:
input int              Inp_MaxOrders_LienKe   = 1;       // Số lệnh tối đa mỗi vòng — nguồn liền kề (0=không giới hạn)
input int              Inp_MaxOrders_Swing    = 1;       // Số lệnh tối đa mỗi vòng — nguồn Swing (0=không giới hạn)
input int              Inp_MaxRoundsPerSignal = 2;       // Số vòng CÓ LÃI tối đa mỗi tín hiệu (0=không giới hạn)
input ENUM_CRT_TP_MODE Inp_BOS_TPMode_LK    = TPMode_RR;   // [nguồn LIỀN KỀ] Cách tính TP:
input ENUM_CRT_TP      Inp_BOS_TPTarget_LK  = TP_Middle;  //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_BOS_TPRR_LK      = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_BOS_TPPips_LK    = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)
input ENUM_CRT_TP_MODE Inp_BOS_TPMode_SW    = TPMode_RR;  // [nguồn SWING] Cách tính TP:
input ENUM_CRT_TP_SW   Inp_BOS_TPTarget_SW  = TPSW_Middle; //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_BOS_TPRR_SW      = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_BOS_TPPips_SW    = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)

// ============ 3. RIÊNG MODE NẾN QUÉT (TradeMode_NenQuet_LTF) ============
// Vào lệnh ngay trên khung LTF. Các luật CỐ ĐỊNH của mode này (không có input):
//   · 1 biên chỉ xét ĐÚNG 1 lần quét đầu tiên, và chỉ vào ĐÚNG 1 cặp lệnh
//     (1 market + 1 limit @ 50%). Mọi lần quét sau trên cùng biên đều bỏ qua.
//   · Biên mới hình thành -> tự huỷ mọi lệnh chờ chưa khớp của biên cũ.
//   · 1 lệnh trong cặp chạm TP -> lệnh còn lại: chưa khớp thì huỷ, đã khớp thì
//     dời SL về entry (hoà vốn).
// TP của mode này TÁCH RIÊNG khỏi Mode BOS, và tách riêng cho từng nhánh setup:
//   · nhánh 2.1 / 2.1b (pinbar)     — mặc định TP tại đường Middle
//   · nhánh 2.2.1 (engulfing 2 nến) — mặc định TP theo 2R
input group "=== 3. RIÊNG Mode Nến quét ==="
input ENUM_CRT_FAR_ACTION Inp_FarFromLine_Action = Far_BoLenhMarket; // Khi giá đã cách biên > Inp_MaxDistFromLine_Pips:
input bool             Inp_On_21_LK         = true;       // BẬT setup [LIỀN KỀ · 2.1 pinbar]
input bool             Inp_On_21b_LK        = true;       // BẬT setup [LIỀN KỀ · 2.1b pinbar cây 2]
input bool             Inp_On_22_LK         = true;       // BẬT setup [LIỀN KỀ · 2.2 engulfing]
input bool             Inp_On_21_SW         = true;       // BẬT setup [SWING · 2.1 pinbar]
input bool             Inp_On_21b_SW        = true;       // BẬT setup [SWING · 2.1b pinbar cây 2]
input bool             Inp_On_22_SW         = true;       // BẬT setup [SWING · 2.2 engulfing]
input ENUM_CRT_TP_MODE Inp_TP21_Mode_LK     = TPMode_MidBienH4; // [2.1 · LIỀN KỀ] Cách tính TP:
input ENUM_CRT_TP      Inp_TP21_Target_LK   = TP_Middle;  //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_TP21_RR_LK       = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_TP21_Pips_LK     = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)
input ENUM_CRT_TP_MODE Inp_TP21_Mode_SW     = TPMode_MidBienH4; // [2.1 · SWING] Cách tính TP:
input ENUM_CRT_TP_SW   Inp_TP21_Target_SW   = TPSW_Middle; //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_TP21_RR_SW       = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_TP21_Pips_SW     = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)
input ENUM_CRT_TP_MODE Inp_TP22_Mode_LK     = TPMode_RR;  // [2.2 · LIỀN KỀ] Cách tính TP:
input ENUM_CRT_TP      Inp_TP22_Target_LK   = TP_Middle;  //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_TP22_RR_LK       = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_TP22_Pips_LK     = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)
input ENUM_CRT_TP_MODE Inp_TP22_Mode_SW     = TPMode_RR;  // [2.2 · SWING] Cách tính TP:
input ENUM_CRT_TP_SW   Inp_TP22_Target_SW   = TPSW_Middle; //   • nếu MidBienH4 — TP đặt ở:
input double           Inp_TP22_RR_SW       = 2.0;        //   • nếu RR — tỷ lệ Reward:Risk
input double           Inp_TP22_Pips_SW     = 50.0;       //   • nếu Pips — số pip (1 pip = $0.1)

// ===================== 3. SHIELD — BẢO VỆ TÀI KHOẢN =====================
input group "=== 4. CHUNG · SHIELD (Bảo vệ tài khoản) ==="
input bool             Inp_UseMarginLimit     = false;   // Bật giới hạn margin (tự giảm lot cho vừa mức dưới)
input double           Inp_MaxMarginPercent   = 30.0;    // Margin tối đa được dùng, % tài khoản
input double           Inp_DailyDrawdownLimit = 0;       // Lỗ tối đa trong NGÀY, % (0 = tắt)
input double           Inp_DailyProfitLimit   = 0;       // Lãi mục tiêu trong NGÀY, % (0 = tắt)
input double           Inp_AutoPassTarget     = 0;       // Equity mục tiêu (USD), đạt thì dừng hẳn (0 = tắt)
input string           Inp_NewsTimes          = "";      // Giờ tin cần tránh, giờ server "15:30, 21:00" (trống = tắt)
input int              Inp_NewsBufferMinutes  = 2;       // Chặn vào lệnh trước/sau giờ tin bao nhiêu phút

// ===================== 4. TELEGRAM =====================
input group "=== 5. CHUNG · TELEGRAM ==="
input bool             Inp_EnableTelegram   = true;       // Bật gửi thông báo Telegram
input string           Inp_BotToken         = "8670907940:AAGkHoUQWn3hux6rUhdRF7291LVi_DUxvR0"; // Token của Bot Telegram
input string           Inp_ChatID           = "-1003976929485";      // ID chat/group/channel nhận thông báo
input bool             Inp_SendScreenshot   = true;      // Gửi kèm ảnh chart khi báo tín hiệu/vào lệnh

// ===================== 5. THAM SỐ THEO KHUNG THỜI GIAN: H4 -> M15 -> M1 =====================
// Việc HIỂN THỊ đường H4 liền kề / Last Major đi theo Inp_EntrySource ở nhóm VẬN HÀNH —
// không có toggle riêng, để tránh hiện cùng lúc 4 đường khi chỉ dùng 1 nguồn để vào lệnh.
input group "=== 6. CHUNG · KHUNG GỐC (HTF) + Last Major Swing ==="
input ENUM_TIMEFRAMES Inp_HTF              = PERIOD_H4;  // Khung cao làm cơ sở High/Low
input int               Inp_HTF_SwingMajor  = 1;          // Số nến H4 mỗi bên xác định đỉnh/đáy Major Swing
input int               Inp_HTF_SwingMinor  = 1;          // Số nến H4 mỗi bên cho Minor Swing (engine cần)

input group "=== 7. CHUNG · KHUNG QUÉT RÂU (LTF) ==="
input ENUM_TIMEFRAMES  Inp_LTF             = PERIOD_M15; // Khung dùng để phát hiện quét râu
input bool             Inp_DetectLowSweep  = true;       // Bắt tín hiệu quét râu DƯỚI (chờ BUY)
input bool             Inp_DetectHighSweep = true;       // Bắt tín hiệu quét râu TRÊN (chờ SELL)

input group "=== 8. RIÊNG Mode BOS/CHOCH · KHUNG VÀO LỆNH ==="
input ENUM_TIMEFRAMES  Inp_EntryTF         = PERIOD_M1;  // Khung tìm BOS/CHOCH để vào lệnh
input int              Inp_EntrySwingMajor = 9;          // Số nến M1 mỗi bên để xác định Major Swing
input int              Inp_EntrySwingMinor = 9;          // Số nến M1 mỗi bên để xác định Minor Swing

// ===================== 6. Ít quan trọng / ít đụng đến =====================
input group "=== 9. CHUNG · HIỂN THỊ ==="
input bool             Inp_ShowMidLine     = true;       // Vẽ đường Middle 50% của H4
input bool             Inp_ShowDashboard   = true;       // Hiện bảng dashboard trên chart
input bool             Inp_ShowStructure   = false;      // Vẽ BOS/CHOCH của khung entry lên chart
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
// [v1.59] Màu cho đường biên ĐÃ XÉT XONG. Xám trung tính để nó lùi hẳn ra sau, nhìn
// lướt qua chart là biết ngay đường nào còn hiệu lực, đường nào chỉ còn là dấu vết.
// Chọn tông giữa (128,128,128) để đọc được trên cả nền chart sáng lẫn tối.
const color            Inp_ColorLineUsed      = clrGray;
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
int      g_lastUsedMask = -1;   // ảnh chụp cờ "biên đã dùng" của 2 nguồn ở lần vẽ trước
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
// Bộ tham số TP của MỘT nhánh setup. Mỗi mode/nhánh có bộ riêng, truyền xuống
// PlaceOneOrder -> ComputeTP để không phải nhân đôi tham số ở từng tầng gọi.
//+------------------------------------------------------------------+
struct STPConfig
{
   ENUM_CRT_TP_MODE mode;
   ENUM_TP_ANCHOR   anchor;   // mốc đã giải mã từ ENUM_CRT_TP (liền kề) hoặc ENUM_CRT_TP_SW
   double           rr;
   double           pips;
};

STPConfig MakeTPConfig(ENUM_CRT_TP_MODE m, ENUM_TP_ANCHOR a, double rr, double pips)
{
   STPConfig c;
   c.mode = m; c.anchor = a; c.rr = rr; c.pips = pips;
   return c;
}
//+------------------------------------------------------------------+
struct SCRTSource
{
   string   tag;                          // "LiềnKề" / "Swing" — dùng cho log & tên object
   bool     isSwing;                      // true = nguồn Last Major Swing; dùng để chọn bộ TP riêng
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

   // --- Trạng thái riêng cho TradeMode_NenQuet_LTF ---
   // "Nến gốc" = cây LTF đầu tiên thọc râu ra ngoài biên. Nếu nó đóng lại BÊN TRONG biên
   // -> setup 2.1 (pinbar) ngay. Nếu đóng BÊN NGOÀI -> chờ ĐÚNG 1 cây kế tiếp (2.2).
   bool     m2Waiting;          // đang chờ cây LTF thứ 2 sau nến gốc
   int      m2WaitKind;         // 1 = nhánh 2.2 (chờ engulfing) · 2 = nhánh 2.1b (chờ cây 2 qua lọc râu)
   int      m2Dir;              // +1 = quét biên dưới (chờ BUY) / -1 = quét biên trên
   double   m2OriginHigh;       // High nến gốc — mốc so sánh cho điều kiện đủ ở 2.2.1
   double   m2OriginLow;        // Low nến gốc
   double   m2OriginBodyEdge;   // Mép THÂN nến gốc phía quét — cùng với High/Low tạo thành
                                // râu quét THẬT, dùng làm mốc 50% cho nhánh 2.1b
   datetime m2OriginTime;
   // Biên đã DÙNG XONG -> ngưng mọi setup trên biên này cho tới khi biên đổi giá trị.
   // Đặt = true ở CẢ 3 kết cục: 2.1 vào lệnh, 2.2.1 vào lệnh, 2.2.2 thất bại.
   // Nghĩa là mỗi đường biên chỉ được xét ĐÚNG 1 lần quét đầu tiên, và chỉ vào ĐÚNG 1 cặp lệnh.
   // [v1.58] TÁCH THEO TỪNG PHÍA. Trước đây dùng chung 1 cờ nên khi biên phía DƯỚI đổi
   // (điểm Major Swing mới) thì phía TRÊN — vốn đã xét xong và vào lệnh — cũng bị mở lại
   // oan, dù đường biên trên không hề thay đổi giá trị. Xem ca 2026.08.04: biên trên
   // 4069.405 vào lệnh lúc 08:15 và TP lúc 08:45, nhưng 16:00 biên DƯỚI đổi là nó lại bị
   // lôi ra xét tiếp. Nay mỗi phía nhớ riêng, chỉ mở lại đúng phía có giá trị mới.
   bool     lineUsedLow;    // biên DƯỚI đã xét xong (quét dưới -> BUY)
   bool     lineUsedHigh;   // biên TRÊN đã xét xong (quét trên -> SELL)

   // [FIX A - v1.51] Phía biên chỉ ĐỦ TƯ CÁCH tính quét sau khi đã có ít nhất 1 nến LTF
   // ĐÓNG CỬA BÊN TRONG biên kể từ lúc biên nhận giá trị hiện tại. Nếu không có chốt này,
   // khi giá đã giao dịch hẳn ở NGOÀI biên (vd biên Swing cũ bị giá bỏ lại phía dưới)
   // thì MỌI nến đều "vượt biên" và bị nhận nhầm là quét thanh khoản — dù chẳng có cú
   // thọc-ra-rồi-bị-từ-chối nào cả. Bản chất CRT: quét là đi TỪ TRONG ra, không phải
   // đang ở ngoài sẵn.
   // Đã in log "vượt biên nhưng không tính là quét" cho biên hiện tại chưa — mỗi đường
   // biên chỉ in đúng 1 dòng, không spam. Reset khi biên đổi hoặc khi có cú quét hợp lệ.
   bool     sweepBlockLogged;

   string   lastEventMsg;
};


// 6 bộ TP: 3 nhánh setup (Mode BOS / 2.1-2.1b pinbar / 2.2.1 engulfing) × 2 nguồn.
// Nguồn liền kề dùng ENUM_CRT_TP (2 mốc) — biên của nó CHÍNH LÀ biên HTF liền kề nên
// 2 mốc "…_LienKe" sẽ trùng lại chính nó, không đưa vào dropdown cho đỡ rối.
// Nguồn Swing dùng ENUM_CRT_TP_SW (4 mốc): thêm lựa chọn chốt theo nến HTF liền kề.
STPConfig TPCfg_ModeBOS(SCRTSource &s)
{
   if(s.isSwing)
      return MakeTPConfig(Inp_BOS_TPMode_SW, (ENUM_TP_ANCHOR)Inp_BOS_TPTarget_SW, Inp_BOS_TPRR_SW, Inp_BOS_TPPips_SW);
   return MakeTPConfig(Inp_BOS_TPMode_LK, (ENUM_TP_ANCHOR)Inp_BOS_TPTarget_LK, Inp_BOS_TPRR_LK, Inp_BOS_TPPips_LK);
}

STPConfig TPCfg_Pinbar(SCRTSource &s)
{
   if(s.isSwing)
      return MakeTPConfig(Inp_TP21_Mode_SW, (ENUM_TP_ANCHOR)Inp_TP21_Target_SW, Inp_TP21_RR_SW, Inp_TP21_Pips_SW);
   return MakeTPConfig(Inp_TP21_Mode_LK, (ENUM_TP_ANCHOR)Inp_TP21_Target_LK, Inp_TP21_RR_LK, Inp_TP21_Pips_LK);
}

STPConfig TPCfg_Engulfing(SCRTSource &s)
{
   if(s.isSwing)
      return MakeTPConfig(Inp_TP22_Mode_SW, (ENUM_TP_ANCHOR)Inp_TP22_Target_SW, Inp_TP22_RR_SW, Inp_TP22_Pips_SW);
   return MakeTPConfig(Inp_TP22_Mode_LK, (ENUM_TP_ANCHOR)Inp_TP22_Target_LK, Inp_TP22_RR_LK, Inp_TP22_Pips_LK);
}

//+------------------------------------------------------------------+
// Công tắc bật/tắt từng setup con của Mode Nến quét (3 nhánh × 2 nguồn).
// Tắt một setup nghĩa là khi gặp đúng ca đó thì KHÔNG vào lệnh, nhưng biên vẫn bị
// đánh dấu đã dùng — giữ nguyên luật "1 biên chỉ xét 1 lần quét đầu tiên", tránh việc
// tắt một nhánh lại vô tình cho phép biên đó chờ mãi tới khi trúng nhánh còn bật.
//+------------------------------------------------------------------+
bool SetupEnabled_21(SCRTSource &s)  { return s.isSwing ? Inp_On_21_SW  : Inp_On_21_LK;  }
bool SetupEnabled_21b(SCRTSource &s) { return s.isSwing ? Inp_On_21b_SW : Inp_On_21b_LK; }
bool SetupEnabled_22(SCRTSource &s)  { return s.isSwing ? Inp_On_22_SW  : Inp_On_22_LK;  }


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
bool AdjacentEnabled()  { return Inp_EntrySource != Bien_Swing; }
bool LastMajorEnabled() { return Inp_EntrySource != Bien_LienKe; }

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

   g_srcAdj.tag = "LiềnKề"; g_srcAdj.isSwing = false; g_srcAdj.magic = Inp_MagicNumber;     g_srcAdj.maxOrdersPerRound = Inp_MaxOrders_LienKe;
   g_srcLM.tag  = "Swing";  g_srcLM.isSwing  = true;  g_srcLM.magic  = Inp_MagicNumber + 1; g_srcLM.maxOrdersPerRound  = Inp_MaxOrders_Swing;
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
         "🎯 <b>Xác nhận vào lệnh:</b> %s\n"
         "📊 <b>Nguồn biên:</b> %s\n"
         "🕐 <b>Khung:</b> %s\n"
         "💰 <b>Balance:</b> %s$",
         Inp_EnableTrading ? "VÀO LỆNH" : "CHỈ THEO DÕI (không trade)",
         Inp_TradeMode == TradeMode_NenQuet_LTF
            ? ("Nến quét " + TFToString(Inp_LTF) + " (pinbar / engulfing)")
            : ("BOS-CHOCH " + TFToString(Inp_EntryTF)),
         EntrySourceText(),
         Inp_TradeMode == TradeMode_NenQuet_LTF
            ? (TFToString(Inp_HTF) + " · " + TFToString(Inp_LTF))
            : (TFToString(Inp_HTF) + " · " + TFToString(Inp_LTF) + " · " + TFToString(Inp_EntryTF)),
         DoubleToString(g_startBalance, 2)));
   }

   // showZone=Inp_ShowZones: mặc định tắt rectangle zone (isHTF=false vẽ foreground đè nến).
   // Zone vẫn được tính & lưu giá trị (current_buy/sell_zone_entry/sl) để dùng cho lọc entry.
   // MaxZones = 1 (giống BOT_TLS): hàng đợi zone của engine đẩy phần tử CŨ NHẤT ra đầu
   // mảng, nên current_*_zone_entry luôn = queue[0] = zone cũ nhất còn hiệu lực. Chỉ khi
   // giữ đúng 1 zone thì biến đó mới trỏ vào zone HIỆN HÀNH — điều kiện bắt buộc để
   // EntryMode_LimitTaiZoneEntry đặt lệnh đúng mép zone vừa hình thành.
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
// Đánh dấu / đọc cờ "biên phía này đã xét xong". dir > 0 = quét biên DƯỚI (vào BUY),
// dir < 0 = quét biên TRÊN (vào SELL).
//+------------------------------------------------------------------+
void SetLineUsed(SCRTSource &s, int dir, bool used)
{
   if(dir > 0) s.lineUsedLow  = used;
   else        s.lineUsedHigh = used;
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
   s.lineUsedLow = false; s.lineUsedHigh = false; s.sweepBlockLogged = false;
   s.m2Waiting = false; s.m2WaitKind = 0; s.m2Dir = 0;
   s.m2OriginHigh = 0; s.m2OriginLow = 0; s.m2OriginBodyEdge = 0; s.m2OriginTime = 0;
   s.sweepBlockLogged = false;
   s.lastEventMsg = "";
}

//+------------------------------------------------------------------+
// Reset trạng thái quét + huỷ arm/pending của 1 nguồn khi biên của nó đổi
// (nến H4 mới với ADJACENT; Last Major High/Low mới xác nhận với LASTMAJOR).
//+------------------------------------------------------------------+
// Biên đổi giá trị -> trạng thái THEO SETUP mất căn cứ: setup dở dang, hạn mức, lệnh chờ
// đều tham chiếu biên cũ nên xoá sạch.
// [v1.58] Riêng cờ "biên đã dùng" thì xoá THEO TỪNG PHÍA (highChanged / lowChanged):
// biên Swing có thể đổi chỉ một phía, phía kia vẫn nguyên đường cũ nên không được phép
// hồi sinh — nếu không thì một đường biên đã vào lệnh và TP xong vẫn bị lôi ra xét lại
// mỗi lần phía đối diện có điểm Major Swing mới.
//+------------------------------------------------------------------+
void ResetSourceSweepAndArm(SCRTSource &s, bool highChanged, bool lowChanged)
{
   s.sweepLowActive  = false;
   s.sweepHighActive = false;
   s.hasSweptLow     = false;
   s.hasSweptHigh    = false;
   s.lastEventMsg    = "";
   s.ordersThisRound = 0;   // biên đổi -> tín hiệu cũ hết hiệu lực, mở lại cả 2 hạn mức
   s.profitRounds    = 0;
   s.m2Waiting       = false;
   s.m2WaitKind      = 0;
   s.m2Dir           = 0;

   // [v1.58] CHỈ mở lại quyền vào lệnh ở PHÍA có giá trị biên mới. Phía không đổi vẫn là
   // đúng đường biên cũ -> luật "1 biên = 1 lần dùng" phải tiếp tục có hiệu lực với nó.
   if(lowChanged)  s.lineUsedLow  = false;
   if(highChanged) s.lineUsedHigh = false;

   s.sweepBlockLogged = false;   // biên mới -> cho phép in lại 1 dòng nếu bị chặn

   ObjectDelete(0, g_prefix + "SweepLowArrow_"  + s.tag);
   ObjectDelete(0, g_prefix + "SweepHighArrow_" + s.tag);

   s.armed = false;
   // Biên mới hình thành -> lệnh chờ của biên CŨ hết ý nghĩa, huỷ ngay dù chưa khớp.
   // Phải huỷ vô điều kiện (không bọc trong "if(s.armed)") vì Mode 2 không dùng arm.
   //
   // CỐ Ý HUỶ CẢ 2 PHÍA, KHÔNG lọc theo phía vừa đổi — đừng "sửa cho nhất quán" với luật
   // per-side của lineUsed ở v1.58. Lý do: TP của nhiều nhánh neo vào đường Middle, mà
   // Middle = (biên trên + biên dưới)/2. Chỉ cần MỘT phía đổi là Middle đã đổi, nên lệnh
   // chờ của phía kia tuy vẫn đúng tiền đề (đường biên của nó không thay đổi) nhưng đang
   // mang sẵn TP tính theo range CŨ -> đã lạc hậu, để lại còn hại hơn huỷ đi.
   // Quyết định của người dùng 2026-08-18, đã cân nhắc cả hướng ngược lại.
   CancelEAPendings(s.magic);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);      // line, label, arrow, dashboard
   ObjectsDeleteAll(0, g_entryPrefix); // BOS/CHOCH của engine entry
   Comment("");
}

//+------------------------------------------------------------------+
// [v1.53] Zoom / kéo chart -> vẽ lại để đầu mút line và nhãn bám lại mép phải khung
// nhìn mới. Chỉ đụng đối tượng đồ hoạ, không chạm gì tới logic vào lệnh.
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && g_hasData)
      DrawAll();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // [FIX C - v1.51] Xử lý nến LTF vừa đóng TRƯỚC, cập nhật biên SAU.
   // Thứ tự cũ (RefreshAll trước) có lỗi lệch-một-nến: tại tick chuyển giao HTF, biên
   // nhảy sang cây HTF vừa đóng RỒI mới xử lý nến LTF cuối cùng của chính cây đó — nến
   // này bị so với đường biên mà nó góp phần tạo ra, về mặt toán học không bao giờ vượt
   // qua được -> cú quét thật xảy ra ở nến LTF cuối chu kỳ HTF bị bỏ sót vĩnh viễn.
   // Nay nến LTF cuối chu kỳ được so với biên CŨ (biên đúng của nó); biên mới chỉ áp
   // từ nến kế tiếp. Hệ quả đã cân nhắc: nếu nến đó tạo cặp lệnh thì ngay sau đó
   // RefreshAll đổi biên và huỷ vế limit chưa khớp — đúng luật "biên mới huỷ lệnh chờ
   // của biên cũ", vế market vẫn giữ.
   // Riêng tick ĐẦU TIÊN sau khởi động: chưa có biên (g_hasData = false) thì phải cập
   // nhật biên trước rồi mới xử lý nến — nếu không ProcessLTFSweep chỉ lấy mốc rồi thoát,
   // và OnInit đã gọi RefreshAll(true) nên thực tế nhánh này hiếm khi cần tới.
   if(!g_hasData)
      RefreshAll(false);
   ProcessLTFSweep();
   RefreshAll(false);

   // Huỷ lệnh chờ khi giá chạm mốc đã chọn (Middle hoặc biên đối diện) — CẢ 2 MODE.
   // Để ngoài khối bảo vệ bên dưới vì huỷ lệnh chờ luôn là hành động an toàn, cần
   // chạy được cả khi Shield/halt đang chặn vào lệnh mới.
   CancelPendingsAtTarget(g_srcAdj);
   CancelPendingsAtTarget(g_srcLM);

   // Giá chạm biên đối diện -> kéo SL về entry, lệnh chỉ còn được gồng lãi.
   // Cũng để ngoài khối bảo vệ: siết SL luôn an toàn, phải chạy cả khi Shield/halt bật.
   MoveSLToEntryAtOppositeBound(g_srcAdj);
   MoveSLToEntryAtOppositeBound(g_srcLM);

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
         // Mode 2 vào lệnh ngay trong ProcessLTFSweep() nên KHÔNG dùng arm/disarm và
         // cũng không cần engine BOS. Chỉ chạy engine khi thật sự cần: Mode 1, hoặc khi
         // người dùng vẫn muốn thấy đường BOS/CHOCH trên chart.
         if(Inp_TradeMode == TradeMode_BOS_KhungEntry)
         {
            CheckDisarmSource(g_srcAdj, bid, ask);  // theo giá, mỗi tick
            CheckDisarmSource(g_srcLM,  bid, ask);
         }

         datetime eb = iTime(_Symbol, Inp_EntryTF, 0);
         if(eb != g_lastEntryBarTime &&
            (Inp_TradeMode == TradeMode_BOS_KhungEntry || Inp_ShowStructure))
         {
            g_lastEntryBarTime = eb;
            g_entryEngine.Update();
            StripNonBosObjects();   // chỉ giữ lại đường BOS/CHOCH trên chart
            if(Inp_TradeMode == TradeMode_BOS_KhungEntry)
            {
               ProcessEntrySource(g_srcAdj);
               ProcessEntrySource(g_srcLM);
            }
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

   // [v1.59] Cờ "biên đã dùng" đổi cũng phải vẽ lại: nó quyết định MÀU của đường line.
   // Không có điều kiện này thì đường vừa xét xong vẫn giữ màu cũ cho tới lần vẽ kế tiếp
   // vì lý do khác (giá đổi / nến mới), tức là hiển thị sai trong một quãng.
   int usedMask = (g_srcAdj.lineUsedLow  ? 1 : 0) | (g_srcAdj.lineUsedHigh ? 2 : 0)
                | (g_srcLM.lineUsedLow   ? 4 : 0) | (g_srcLM.lineUsedHigh  ? 8 : 0);
   bool usedChanged = (usedMask != g_lastUsedMask);
   g_lastUsedMask = usedMask;

   if(priceChanged || timeChanged || lmChanged || usedChanged || forceUpdate)
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

   // HTF vừa cập nhật range mới -> nguồn LIỀN KỀ dùng biên mới, xoá sạch setup dở dang.
   g_srcAdj.boundHigh     = htfHigh;
   g_srcAdj.boundLow      = htfLow;
   g_srcAdj.boundHighTime = htfBarTime;
   g_srcAdj.boundLowTime  = htfBarTime;
   g_srcAdj.boundReady    = true;
   ResetSourceSweepAndArm(g_srcAdj, true, true);   // nến HTF mới -> cả 2 phía đều là biên mới

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

   bool highChanged = false;
   bool lowChanged  = false;
   double oldHigh   = g_srcLM.boundHigh;   // giữ lại để in log đổi biên
   double oldLow    = g_srcLM.boundLow;

   if(newHigh != EMPTY_VALUE && newHighT != 0)
   {
      datetime oldT = g_srcLM.boundHighTime;
      if(force || newHighT != oldT)
      {
         g_srcLM.boundHigh     = newHigh;
         g_srcLM.boundHighTime = newHighT;
         if(oldT != 0 && newHighT != oldT)
            highChanged = true;
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
            lowChanged = true;
      }
   }

   g_srcLM.boundReady = (g_srcLM.boundHighTime != 0 && g_srcLM.boundLowTime != 0);

   // Phía nào đổi cũng xoá sạch setup dở dang của biên cũ.
   if(highChanged || lowChanged)
   {
      // [v1.57] In rõ SỰ KIỆN ĐỔI BIÊN. Đây là mắt xích hay bị hụt khi soi lại journal:
      // biên Swing chỉ đổi khi có nến HTF mới đóng và engine xác nhận điểm Major Swing
      // mới, và chính lúc đó lineUsed được mở lại -> một đường biên tưởng đã "chết" từ
      // lâu bỗng sống lại và bot xét quét trở lại. Không có dòng này thì các log quét
      // sau đó trông như tự nhiên xuất hiện.
      // Chỉ in cho nguồn Swing: nguồn liền kề đổi biên mỗi nến HTF theo định nghĩa,
      // in ra chỉ tổ ngập journal mà chẳng nói thêm được gì.
      // Câu chữ nói rõ: đây là ĐƯỜNG KHÁC thay chỗ đường cũ, KHÔNG phải đường cũ hồi sinh.
      // Bản 1.57 ghi "biên mở lại cho lần quét mới" gây hiểu nhầm là đường cũ được dùng lại.
      if(highChanged && lowChanged)
         PrintFormat("[CRT][%s] ĐỔI BIÊN cả 2 phía (Major Swing mới): trên %s->%s · dưới %s->%s — đường KHÁC thay chỗ đường cũ, huỷ setup/lệnh chờ của đường cũ; đường mới ở trạng thái CHƯA DÙNG.",
                     g_srcLM.tag, DoubleToString(oldHigh, _Digits), DoubleToString(g_srcLM.boundHigh, _Digits),
                     DoubleToString(oldLow, _Digits), DoubleToString(g_srcLM.boundLow, _Digits));
      else if(highChanged)
         PrintFormat("[CRT][%s] ĐỔI BIÊN phía TRÊN (Major Swing mới): %s -> %s — đường KHÁC thay chỗ đường cũ, huỷ setup/lệnh chờ của đường cũ; đường mới ở trạng thái CHƯA DÙNG. Biên dưới giữ nguyên trạng thái.",
                     g_srcLM.tag, DoubleToString(oldHigh, _Digits), DoubleToString(g_srcLM.boundHigh, _Digits));
      else
         PrintFormat("[CRT][%s] ĐỔI BIÊN phía DƯỚI (Major Swing mới): %s -> %s — đường KHÁC thay chỗ đường cũ, huỷ setup/lệnh chờ của đường cũ; đường mới ở trạng thái CHƯA DÙNG. Biên trên giữ nguyên trạng thái.",
                     g_srcLM.tag, DoubleToString(oldLow, _Digits), DoubleToString(g_srcLM.boundLow, _Digits));

      ResetSourceSweepAndArm(g_srcLM, highChanged, lowChanged);
   }

   return (highChanged || lowChanged);
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
// [v1.59] Đường biên ĐÃ XÉT XONG thì đổi sang xám + nhãn thêm chữ "đã dùng", thay vì
// báo bằng chữ trên dashboard. Nhìn thẳng vào chart là biết đường nào còn hiệu lực.
// Trạng thái này theo TỪNG PHÍA, nên biên trên có thể xám trong khi biên dưới vẫn màu.
//+------------------------------------------------------------------+
color LineColor(color base, bool used)
{
   return used ? Inp_ColorLineUsed : base;
}

string LineLabel(string base, bool used)
{
   return used ? base + "  · đã dùng" : base;
}

//+------------------------------------------------------------------+
// [v1.53] Mốc đầu mút line + vị trí nhãn, BÁM THEO VÙNG ĐANG NHÌN THẤY của chart.
// Trước đây cả 2 gắn cứng ở "nến hiện tại + 50 nến": zoom to lên thì điểm đó nằm ngoài
// màn hình -> nhãn biến mất. Nay chừa sẵn ở mép phải khung nhìn một khoảng vừa đủ chứa
// chữ, line kết thúc ngay trước khoảng đó, nhãn nằm gọn bên trong — đúng bố cục hình
// minh hoạ và không bao giờ bị cắt mất dù zoom mức nào.
// Chừa theo PIXEL chứ không theo số nến: bề rộng chữ cố định theo pixel, còn một nến
// chiếm bao nhiêu pixel thì đổi theo mức zoom.
// Trả về false nếu chưa lấy được toạ độ chart -> bên gọi dùng lại mốc cũ.
//+------------------------------------------------------------------+
bool VisibleEdgeTimes(int maxTextLen, datetime &lineEnd, datetime &labelAt)
{
   long wpx = 0;
   if(!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, wpx) || wpx <= 0)
      return false;

   // ~0.62 * cỡ chữ là bề rộng trung bình 1 ký tự của font mặc định; +16px lề.
   int reserve = (int)(maxTextLen * Inp_LabelFontSize * 0.62) + 16;
   if(reserve > (int)wpx / 2)
      reserve = (int)wpx / 2;          // chart quá hẹp -> nhiều nhất lấy nửa bề ngang

   int      sub = 0;
   double   px  = 0;
   datetime tEnd = 0, tLabel = 0;
   if(!ChartXYToTimePrice(0, (int)wpx - reserve,     0, sub, tEnd,   px)) return false;
   if(!ChartXYToTimePrice(0, (int)wpx - reserve + 6, 0, sub, tLabel, px)) return false;
   if(tEnd <= 0 || tLabel <= 0 || tLabel <= tEnd)
      return false;

   lineEnd = tEnd;
   labelAt = tLabel;
   return true;
}

//+------------------------------------------------------------------+
void DrawAll()
{
   datetime endTime   = g_lastCurBarTime + Inp_ExtendBars * PeriodSeconds(PERIOD_CURRENT);
   datetime labelTime = endTime + Inp_LabelOffsetBars * PeriodSeconds(PERIOD_CURRENT);

   // Nhãn dài nhất quyết định khoảng chừa: "Last Major High: " + giá + "  · đã dùng".
   if(Inp_ShowLabel || Inp_ShowLastMajorLabel)
   {
      int maxLen = 18 + _Digits + 5 + 11;
      datetime e2 = 0, l2 = 0;
      if(VisibleEdgeTimes(maxLen, e2, l2))
      {
         endTime   = e2;
         labelTime = l2;
      }
   }

   if(AdjacentEnabled())
   {
      bool usedHi = g_srcAdj.lineUsedHigh;
      bool usedLo = g_srcAdj.lineUsedLow;

      DrawLevelLine(g_nameHighLine, g_highStartTime, endTime, g_htfHigh,
                    LineColor(Inp_ColorHigh, usedHi), Inp_LineWidth, Inp_LineStyle);
      DrawLevelLine(g_nameLowLine,  g_lowStartTime,  endTime, g_htfLow,
                    LineColor(Inp_ColorLow,  usedLo), Inp_LineWidth, Inp_LineStyle);

      if(Inp_ShowMidLine)
         DrawLevelLine(g_nameMidLine, g_midStartTime, endTime, HTF_Mid(), Inp_ColorMid, Inp_MidLineWidth, Inp_MidLineStyle);
      else
         ObjectDelete(0, g_nameMidLine);

      if(Inp_ShowLabel)
      {
         string tfName = TFToString(Inp_HTF);
         DrawLevelLabel(g_nameHighLabel, labelTime, g_htfHigh,
                         LineLabel(StringFormat("%s High: %s", tfName, DoubleToString(g_htfHigh, _Digits)), usedHi),
                         LineColor(Inp_ColorHigh, usedHi));
         DrawLevelLabel(g_nameLowLabel, labelTime, g_htfLow,
                         LineLabel(StringFormat("%s Low: %s", tfName, DoubleToString(g_htfLow, _Digits)), usedLo),
                         LineColor(Inp_ColorLow, usedLo));
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
      bool lmUsedHi = g_srcLM.lineUsedHigh;
      bool lmUsedLo = g_srcLM.lineUsedLow;

      DrawLevelLine(g_nameLastMajorHighLine, g_srcLM.boundHighTime, endTime, g_srcLM.boundHigh,
                     LineColor(Inp_ColorLastMajorHigh, lmUsedHi), Inp_LastMajorLineWidth, Inp_LastMajorLineStyle);
      DrawLevelLine(g_nameLastMajorLowLine,  g_srcLM.boundLowTime,  endTime, g_srcLM.boundLow,
                     LineColor(Inp_ColorLastMajorLow,  lmUsedLo), Inp_LastMajorLineWidth, Inp_LastMajorLineStyle);

      if(Inp_ShowLastMajorLabel)
      {
         DrawLevelLabel(g_nameLastMajorHighLabel, labelTime, g_srcLM.boundHigh,
                         LineLabel(StringFormat("Last Major High: %s", DoubleToString(g_srcLM.boundHigh, _Digits)), lmUsedHi),
                         LineColor(Inp_ColorLastMajorHigh, lmUsedHi));
         DrawLevelLabel(g_nameLastMajorLowLabel, labelTime, g_srcLM.boundLow,
                         LineLabel(StringFormat("Last Major Low: %s", DoubleToString(g_srcLM.boundLow, _Digits)), lmUsedLo),
                         LineColor(Inp_ColorLastMajorLow, lmUsedLo));
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
      return; // lần đầu chỉ lấy mốc; cổng "đi từ trong ra" đọc thẳng lịch sử nên không
              // cần mồi trạng thái gì cả, kể cả khi bot vừa khởi động nguội.

   // Nến LTF vừa đóng = shift 1
   double highC  = iHigh(_Symbol,  Inp_LTF, 1);
   double lowC   = iLow(_Symbol,   Inp_LTF, 1);
   double closeC = iClose(_Symbol, Inp_LTF, 1);
   datetime tC   = iTime(_Symbol,  Inp_LTF, 1);

   if(Inp_EntrySource != Bien_Swing)
      ProcessSourceSweep(g_srcAdj, highC, lowC, closeC, tC);

   if(Inp_EntrySource != Bien_LienKe && g_srcLM.boundReady)
      ProcessSourceSweep(g_srcLM, highC, lowC, closeC, tC);
}

//+------------------------------------------------------------------+
// [v1.56] "Quét là đi TỪ TRONG biên ra" — kiểm TẠI CHỖ, không nuôi trạng thái chạy nền.
// Nến LTF LIỀN TRƯỚC phải đóng cửa BÊN TRONG biên phía đang xét. Nếu nó đã đóng ở ngoài
// thì giá đang giao dịch ở vùng khác, phía đó không còn thanh khoản để quét — cú "vượt
// biên" của cây hiện tại chỉ là giá đi tiếp, không phải cú thọc-ra-rồi-bị-từ-chối.
// Không có chốt này thì tái diễn ca backtest 2026.08.04 16:00: nến M15 H=4088.586 nằm
// TRỌN trên đường 4069.405 vẫn bị nhận là "quét biên trên".
// Trước đây (v1.51-1.55) việc này nuôi bằng 4 biến trạng thái cập nhật sau MỖI nến, sinh
// ra hàng loạt log đổi trạng thái vô nghĩa khi giá dập dình quanh line. Nay đọc thẳng
// nến shift 2 đúng lúc cần -> bỏ được toàn bộ trạng thái và log đó, kết quả y hệt.
// Dùng CLOSE chứ không dùng High/Low: thân nến nằm trong biên mới chứng tỏ giá thực sự
// giao dịch bên trong, râu chạm vào chưa đủ. Bất đẳng thức NGHIÊM NGẶT: đóng đúng ngay
// tại biên chưa tính là "trong biên".
//+------------------------------------------------------------------+
bool CameFromInside(int dir, double lo, double hi)
{
   double prevClose = iClose(_Symbol, Inp_LTF, 2);
   if(prevClose <= 0)
      return false;
   return (dir > 0) ? (prevClose > lo) : (prevClose < hi);
}

//+------------------------------------------------------------------+
// MODE 2 — TradeMode_NenQuet_LTF: vào lệnh ngay trên khung LTF, KHÔNG dùng khung Entry.
//
//   Nến LTF thọc râu ra ngoài biên  =  NẾN GỐC
//     ├─ 2.1  nến gốc đóng lại BÊN TRONG biên  ("pinbar": râu ngoài, thân trong)
//     │        · qua PassesWickFilter -> vào cặp lệnh, limit @ 50% RÂU
//     │        · trượt bộ lọc (nến ngược chiều + râu < thân) -> 2.1b: chờ ĐÚNG 1 cây kế
//     │          tiếp; cây đó phải đóng TRONG biên VÀ qua bộ lọc thì mới vào, limit @
//     │          50% râu của CHÍNH cây đó; không đạt -> bỏ, biên coi như đã dùng.
//     └─ 2.2  nến gốc đóng BÊN NGOÀI biên -> xét ĐÚNG 1 cây LTF kế tiếp:
//              ├─ 2.2.1  đóng BÊN TRONG biên (cần) VÀ close vượt/bằng High(gốc)
//              │          — với quét biên trên là close <= Low(gốc) — (đủ)
//              │          -> vào cặp lệnh, limit @ 50% TOÀN THÂN nến này (High+Low)/2
//              └─ 2.2.2  còn lại -> bỏ qua VÀ ĐỐT BIÊN (lineUsed) tới khi biên đổi.
//
// Ghi chú: chỉ xét đúng 1 cây kế tiếp — không kiên nhẫn chờ như Mode 1.
//+------------------------------------------------------------------+
// Bộ lọc chất lượng nến quét — chỉ áp dụng khi nến đóng NGƯỢC chiều lệnh:
//   · quét biên dưới (chờ BUY) mà nến GIẢM  -> phải có râu dưới >= thân
//   · quét biên trên (chờ SELL) mà nến TĂNG -> phải có râu trên >= thân
// Nến đã đóng THUẬN chiều lệnh thì tự nó đã thể hiện lực, không cần lọc thêm.
// Mục đích: loại nến xu hướng mạnh ngược hướng (thân dài, râu ngắn) — chỉ thọc qua biên
// rồi đi tiếp chứ không phải quét thanh khoản rồi bị từ chối.
//+------------------------------------------------------------------+
// [v1.61] Tỷ lệ tối thiểu RÂU / THÂN để một nến ngược chiều được công nhận là cú từ chối
// giá. Trước là 1.0 (râu chỉ cần bằng thân); nay 1.5 — râu phải dài hơn hẳn thân thì sự
// từ chối mới rõ ràng. Đặt hằng số chứ không đưa vào Input theo yêu cầu người dùng; muốn
// đổi thì sửa đúng dòng này. Để 0 là bỏ hẳn phép đo (mọi nến ngược chiều đều qua).
// Áp CHUNG cho cả nhánh 2.1 (nến gốc) lẫn 2.1b (cây thứ 2) vì cả hai gọi hàm này.
const double Inp_WickBodyRatio = 1.5;

//+------------------------------------------------------------------+
bool PassesWickFilter(int dir, double h, double l, double o, double c)
{
   bool isBuy = (dir > 0);

   bool candleWithTrade = isBuy ? (c > o) : (c < o);
   if(candleWithTrade)
      return true;   // nến thuận chiều lệnh -> miễn lọc, tự nó đã thể hiện lực

   // Từ đây trở xuống: nến đóng NGƯỢC chiều lệnh -> đòi râu phía quét >= 1.5 x thân.
   double body = MathAbs(c - o);
   double wick = isBuy ? (MathMin(o, c) - l)     // quét biên dưới -> đo râu DƯỚI
                       : (h - MathMax(o, c));    // quét biên trên -> đo râu TRÊN
   if(wick < 0) wick = 0;
   return (wick >= body * Inp_WickBodyRatio);
}

//+------------------------------------------------------------------+
// Diễn giải VÌ SAO nến qua được PassesWickFilter — dùng cho log, để journal nói đúng
// điều kiện thực sự đã thoả thay vì đoán. Có 2 đường qua khác hẳn nhau:
//   · nến THUẬN chiều lệnh -> qua ngay, KHÔNG hề đo râu/thân
//   · nến NGƯỢC chiều      -> phải có râu >= thân (chỉ khi Inp_PinbarChiThuan_* = false)
//+------------------------------------------------------------------+
string WickPassReason(int dir, double h, double l, double o, double c)
{
   bool isBuy = (dir > 0);
   if(isBuy ? (c > o) : (c < o))
      return "nến THUẬN chiều lệnh";

   double body = MathAbs(c - o);
   double wick = isBuy ? (MathMin(o, c) - l) : (h - MathMax(o, c));
   if(wick < 0) wick = 0;
   return StringFormat("nến ngược chiều nhưng râu %s >= %.1f x thân %s (cần %s)",
                       DoubleToString(wick, _Digits), Inp_WickBodyRatio,
                       DoubleToString(body, _Digits),
                       DoubleToString(body * Inp_WickBodyRatio, _Digits));
}

//+------------------------------------------------------------------+
// Phân loại NẾN GỐC (cây đã quét đủ sâu qua biên) -> quyết định vào lệnh ngay hay chờ tiếp.
// Tách riêng vì được gọi từ 2 nơi: lúc dò nến gốc lần đầu, và lúc cây kế tiếp "lên ngôi"
// Tách riêng thành hàm vì đây là điểm rẽ 3 nhánh 2.1 / 2.1b / 2.2 của cây gốc.
//+------------------------------------------------------------------+
void ClassifyOriginCandle(SCRTSource &s, int dir, double highC, double lowC, double closeC,
                          double openC, datetime tC, double lo, double hi)
{
   bool isBuy    = (dir > 0);
   bool closedIn = isBuy ? (closeC > lo) : (closeC < hi);

   if(!closedIn)
   {
      // 2.2 — đóng NGOÀI biên: ghi nhận nến gốc, chờ đúng 1 cây engulfing kế tiếp.
      s.m2Waiting    = true;
      s.m2WaitKind   = 1;
      s.m2Dir        = dir;
      s.m2OriginHigh = highC;
      s.m2OriginLow  = lowC;
      s.m2OriginTime = tC;
      PrintFormat("[CRT][%s] 2.2 Nến gốc quét biên %s đóng NGOÀI biên @%s (H=%s L=%s) -> chờ 1 cây %s kế tiếp.",
                  s.tag, isBuy ? "dưới" : "trên", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                  DoubleToString(highC, _Digits), DoubleToString(lowC, _Digits), TFToString(Inp_LTF));
      return;
   }

   double bodyEdge = isBuy ? MathMin(openC, closeC) : MathMax(openC, closeC);

   if(!PassesWickFilter(dir, highC, lowC, openC, closeC))
   {
      // 2.1 nhưng nến ngược chiều lệnh và râu < 1.5 x thân -> nến xu hướng ngược, không phải
      // cú từ chối. Cho thêm ĐÚNG 1 cây để thị trường thể hiện lực.
      s.m2Waiting        = true;
      s.m2WaitKind       = 2;
      s.m2Dir            = dir;
      s.m2OriginHigh     = highC;
      s.m2OriginLow      = lowC;
      s.m2OriginBodyEdge = bodyEdge;   // giữ lại để tính mốc 50% theo râu quét THẬT
      s.m2OriginTime     = tC;
      PrintFormat("[CRT][%s] 2.1 nến gốc %s @%s bị loại (nến ngược chiều, râu %s < %.1f x thân %s = %s) -> chờ 1 cây %s kế tiếp.",
                  s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                  DoubleToString(isBuy ? (bodyEdge - lowC) : (highC - bodyEdge), _Digits),
                  Inp_WickBodyRatio,
                  DoubleToString(MathAbs(closeC - openC), _Digits),
                  DoubleToString(MathAbs(closeC - openC) * Inp_WickBodyRatio, _Digits),
                  TFToString(Inp_LTF));
      return;
   }

   // 2.1 — pinbar hợp lệ. Nếu setup đang TẮT thì bỏ qua mà KHÔNG đốt biên, để nhánh
   // khác (2.2) còn cơ hội ở lần quét sau — bật/tắt 1 nhánh không ảnh hưởng nhánh kia.
   if(!SetupEnabled_21(s))
   {
      PrintFormat("[CRT][%s] 2.1 PINBAR %s @%s -> setup ĐANG TẮT, bỏ qua (biên vẫn còn hiệu lực).",
                  s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
      return;
   }
   SetLineUsed(s, dir, true);   // phía biên này chỉ vào đúng 1 cặp lệnh

   // limit @ 50% RÂU phía quét (từ mút râu tới mép THÂN).
   double limitPrice = isBuy ? (lowC + bodyEdge) / 2.0 : (highC + bodyEdge) / 2.0;
   PrintFormat("[CRT][%s] 2.1 PINBAR %s @%s · qua lọc: %s · râu %s->%s -> vào cặp lệnh (limit @50%% râu = %s)",
               s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
               WickPassReason(dir, highC, lowC, openC, closeC),
               DoubleToString(isBuy ? lowC : highC, _Digits), DoubleToString(bodyEdge, _Digits),
               DoubleToString(limitPrice, _Digits));
   ConfirmSweepForMode2(s, dir, tC);
   STPConfig cfg21 = TPCfg_Pinbar(s);
   ExecutePairEntry(s, dir, limitPrice, "2.1 pinbar", cfg21);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void ProcessSweepCandleMode(SCRTSource &s, double highC, double lowC, double closeC,
                            datetime tC, double lo, double hi)
{
   // [v1.58] Không chặn sớm ở đây nữa: cờ "đã dùng" nay theo TỪNG PHÍA nên chỉ kiểm được
   // sau khi biết cú quét thuộc phía nào (xem chỗ dò nến gốc bên dưới). Nhánh đang chờ
   // cây 2 thì đương nhiên chưa dùng xong nên vẫn chạy tiếp bình thường.
   double openC = iOpen(_Symbol, Inp_LTF, 1);

   //---------- Đang chờ cây kế tiếp ----------
   if(s.m2Waiting)
   {
      bool isBuy  = (s.m2Dir > 0);
      s.m2Waiting = false;

      // Cây này có thể thọc sâu hơn cây trước -> cập nhật mút râu để SL đặt đúng chỗ.
      if(isBuy  && lowC  < s.sweepLowExtreme)  s.sweepLowExtreme  = lowC;
      if(!isBuy && highC > s.sweepHighExtreme) s.sweepHighExtreme = highC;

      //=== Kind 1 & 2: setup đã ngã ngũ -> đốt biên. Riêng trường hợp setup BỊ TẮT thì
      //=== KHÔNG đốt, để các nhánh còn bật vẫn còn cơ hội ở lần quét sau trên biên này.
      SetLineUsed(s, s.m2Dir, true);
      bool closedIn = isBuy ? (closeC > lo) : (closeC < hi);   // điều kiện CẦN cho cả 2 nhánh

      if(s.m2WaitKind == 2)
      {
         // --- Nhánh 2.1b: nến gốc là pinbar nhưng trượt lọc chất lượng.
         //     Yêu cầu cây này vừa đóng trong biên, vừa qua được lọc.
         //     MỐC 50% LẤY THEO RÂU QUÉT THẬT CỦA NẾN GỐC, không phải râu cây này —
         //     cây thứ 2 có thể không hề chạm biên (râu của nó chẳng liên quan gì tới
         //     cú quét thanh khoản), nên lấy theo nó sẽ ra một mức hồi ngẫu nhiên.
         bool strong = PassesWickFilter(s.m2Dir, highC, lowC, openC, closeC);
         if(closedIn && strong)
         {
            if(!SetupEnabled_21b(s))
            {
               SetLineUsed(s, s.m2Dir, false);   // setup tắt -> coi như chưa dùng biên
               PrintFormat("[CRT][%s] 2.1b PINBAR (cây 2) %s @%s -> setup ĐANG TẮT, bỏ qua (biên vẫn còn hiệu lực).",
                           s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
               return;
            }
            double limitPrice = isBuy ? (s.m2OriginLow  + s.m2OriginBodyEdge) / 2.0
                                      : (s.m2OriginHigh + s.m2OriginBodyEdge) / 2.0;
            PrintFormat("[CRT][%s] 2.1b PINBAR (cây 2) %s @%s · qua lọc: %s -> vào cặp lệnh (limit @50%% râu quét nến gốc %s->%s = %s)",
                        s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                        WickPassReason(s.m2Dir, highC, lowC, openC, closeC),
                        DoubleToString(isBuy ? s.m2OriginLow : s.m2OriginHigh, _Digits),
                        DoubleToString(s.m2OriginBodyEdge, _Digits),
                        DoubleToString(limitPrice, _Digits));
            ConfirmSweepForMode2(s, s.m2Dir, tC);
            STPConfig cfg21b = TPCfg_Pinbar(s);
            ExecutePairEntry(s, s.m2Dir, limitPrice, "2.1b pinbar cây 2", cfg21b);
         }
         else
            PrintFormat("[CRT][%s] 2.1b KHÔNG ĐỦ ĐK (%s) -> bỏ setup, biên %s coi như đã dùng.",
                        s.tag,
                        !closedIn ? "cây 2 đóng ngoài biên"
                                  : StringFormat("cây 2 ngược chiều và râu < %.1f x thân", Inp_WickBodyRatio),
                        TFToString(Inp_HTF));
         return;
      }

      // --- Nhánh 2.2: nến gốc đóng ngoài biên, chờ cây engulfing đảo chiều.
      bool engulfed = isBuy ? (closeC >= s.m2OriginHigh)
                            : (closeC <= s.m2OriginLow);         // điều kiện ĐỦ
      if(closedIn && engulfed)
      {
         if(!SetupEnabled_22(s))
         {
            SetLineUsed(s, s.m2Dir, false);   // setup tắt -> coi như chưa dùng biên
            PrintFormat("[CRT][%s] 2.2.1 ENGULFING %s @%s -> setup ĐANG TẮT, bỏ qua (biên vẫn còn hiệu lực).",
                        s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
            return;
         }
         // 2.2.1 — cặp nến kiểu engulfing đảo chiều. Limit @ 50% TOÀN THÂN cây thứ 2.
         double limitPrice = (highC + lowC) / 2.0;
         PrintFormat("[CRT][%s] 2.2.1 ENGULFING %s @%s · close %s %s High/Low gốc %s -> vào cặp lệnh (limit @50%% thân = %s)",
                     s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                     DoubleToString(closeC, _Digits), isBuy ? ">=" : "<=",
                     DoubleToString(isBuy ? s.m2OriginHigh : s.m2OriginLow, _Digits),
                     DoubleToString(limitPrice, _Digits));
         ConfirmSweepForMode2(s, s.m2Dir, tC);
         STPConfig cfg22 = TPCfg_Engulfing(s);
         ExecutePairEntry(s, s.m2Dir, limitPrice, "2.2.1 engulfing", cfg22);
      }
      else
      {
         PrintFormat("[CRT][%s] 2.2.2 KHÔNG ĐỦ ĐK (%s) -> bỏ setup, biên %s coi như đã dùng.",
                     s.tag,
                     !closedIn ? "cây thứ 2 vẫn đóng ngoài biên" : "đóng chưa vượt mốc nến gốc",
                     TFToString(Inp_HTF));
      }
      return;
   }

   //---------- Dò NẾN GỐC: cây chạm biên, mở cửa sổ theo dõi 2 cây ----------
   // Phía nào đã xét xong (vào lệnh hoặc thất bại) thì im lặng cho tới khi CHÍNH phía đó
   // nhận giá trị biên mới — phía kia đổi không liên quan.
   int dir = 0;
   if(Inp_DetectLowSweep       && !s.lineUsedLow  && lowC  < lo) dir = +1;
   else if(Inp_DetectHighSweep && !s.lineUsedHigh && highC > hi) dir = -1;
   if(dir == 0)
      return;

   // Cổng "đi từ trong ra" — xem CameFromInside().
   if(!CameFromInside(dir, lo, hi))
   {
      if(!s.sweepBlockLogged)
      {
         s.sweepBlockLogged = true;   // mỗi đường biên chỉ báo 1 lần, tránh ngập log
         PrintFormat("[CRT][%s] Nến %s @%s %s biên %s nhưng KHÔNG tính là quét: nến liền trước đã đóng NGOÀI biên (giá đang ở vùng khác, không còn thanh khoản để quét).",
                     s.tag, TFToString(Inp_LTF), TimeToString(tC, TIME_DATE|TIME_MINUTES),
                     dir > 0 ? "thủng" : "vượt",
                     DoubleToString(dir > 0 ? lo : hi, _Digits));
      }
      return;
   }
   s.sweepBlockLogged = false;

   if(dir > 0) { s.sweepLowExtreme  = lowC;  s.sweepLowStartTime  = tC; }
   else        { s.sweepHighExtreme = highC; s.sweepHighStartTime = tC; }

   // [1.55] Không còn lọc độ sâu: râu thọc qua biên BAO NHIÊU CŨNG TÍNH LÀ QUÉT.
   // Mọi cú vượt biên đi thẳng vào 2.1 / 2.2 như nhau.

   ClassifyOriginCandle(s, dir, highC, lowC, closeC, openC, tC, lo, hi);
}

//+------------------------------------------------------------------+
// Ghi nhận mốc râu quét + báo Telegram cho Mode 2 (tương đương ConfirmLow/HighSweep
// của Mode 1 nhưng KHÔNG gọi ArmSetupSource — Mode 2 vào lệnh ngay, không chờ arm).
//+------------------------------------------------------------------+
void ConfirmSweepForMode2(SCRTSource &s, int dir, datetime tConfirm)
{
   if(dir > 0)
   {
      s.sweptLow     = s.sweepLowExtreme;
      s.sweptLowTime = tConfirm;
      s.hasSweptLow  = true;
      if(Inp_MarkSweep)
         MarkConfirmCandle(g_prefix + "SweepLowArrow_" + s.tag, OBJ_ARROW_UP, tConfirm, false, Inp_ColorSweepLow);
   }
   else
   {
      s.sweptHigh     = s.sweepHighExtreme;
      s.sweptHighTime = tConfirm;
      s.hasSweptHigh  = true;
      if(Inp_MarkSweep)
         MarkConfirmCandle(g_prefix + "SweepHighArrow_" + s.tag, OBJ_ARROW_DOWN, tConfirm, true, Inp_ColorSweepHigh);
   }
   NotifySignal(s, dir);
}

//+------------------------------------------------------------------+
void ProcessSourceSweep(SCRTSource &s, double highC, double lowC, double closeC, datetime tC)
{
   double lo = s.boundLow;
   double hi = s.boundHigh;

   if(Inp_TradeMode == TradeMode_NenQuet_LTF)
   {
      ProcessSweepCandleMode(s, highC, lowC, closeC, tC, lo, hi);
      return;
   }

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
   // [FIX A] Chỉ MỞ cụm quét mới khi phía đó có tư cách; cụm đang theo dõi dở thì vẫn
   // tiếp tục (nó đã được mở lúc còn đủ tư cách).
   if(Inp_DetectLowSweep)
   {
      if(!s.sweepLowActive)
      {
         if(lowC < lo && CameFromInside(+1, lo, hi))
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
         if(highC > hi && CameFromInside(-1, lo, hi))
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
      "📏 <b>Biên %s:</b> %s — %s\n"
      "🪝 <b>Râu quét:</b> %s\n"
      "🛡️ <b>SL dự kiến:</b> %s%s\n"
      "%s",
      isBuy ? "🟩" : "🟥",
      isBuy ? "MUA" : "BÁN",
      _Symbol,
      s.tag,
      TFToString(Inp_HTF),
      DoubleToString(s.boundLow, _Digits), DoubleToString(s.boundHigh, _Digits),
      DoubleToString(swept, _Digits),
      DoubleToString(sl, _Digits),
      Inp_SL_Mode == SLMode_KhongDatSL ? " (mốc ảo — không đặt SL trên sàn)" : "",
      !Inp_EnableTrading
         ? "👁 <b>Chế độ CHỈ THEO DÕI</b> — bot không tự vào lệnh."
         : (Inp_TradeMode == TradeMode_NenQuet_LTF
              ? "⚡ Đang vào cặp lệnh ngay theo nến quét (market + limit 50%)..."
              : ("⏳ Đang chờ BOS/CHOCH " + TFToString(Inp_EntryTF) + " xác nhận để vào lệnh...")));

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
// Mode 1 (BOS/CHOCH khung Entry): chọn giá theo Inp_Entry_Mode rồi đặt ĐÚNG 1 lệnh.
//   EntryMode_Market            -> khớp ngay giá thị trường tại lúc có BOS/CHOCH.
//   EntryMode_LimitTaiBienHTF   -> chờ TẠI đường biên khung gốc của nguồn này. Giá cố
//     định -> nhiều BOS/CHOCH liên tiếp sẽ đặt nhiều lệnh CHỒNG NHAU cùng một giá.
//   EntryMode_LimitTaiZoneEntry -> chờ tại mép Zone khung Entry do chính BOS/CHOCH đó
//     sinh ra. Mỗi BOS/CHOCH tạo zone mới nên mỗi lệnh nằm ở một giá khác nhau.
void ExecuteEntry(SCRTSource &s, int dir)
{
   bool   isBuy    = (dir > 0);
   bool   useLimit = (Inp_Entry_Mode != EntryMode_Market);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry;
   string mocTxt = "";
   if(Inp_Entry_Mode == EntryMode_LimitTaiZoneEntry)
   {
      entry  = isBuy ? g_entryEngine.current_buy_zone_entry
                     : g_entryEngine.current_sell_zone_entry;
      mocTxt = "mép Zone " + TFToString(Inp_EntryTF);
   }
   else if(Inp_Entry_Mode == EntryMode_LimitTaiBienHTF)
   {
      entry  = isBuy ? s.boundLow : s.boundHigh;
      mocTxt = "biên " + TFToString(Inp_HTF);
   }
   else
      entry = isBuy ? ask : bid;

   STPConfig cfg = TPCfg_ModeBOS(s);
   PlaceOneOrder(s, dir, entry, useLimit, mocTxt, "", cfg);
}

//+------------------------------------------------------------------+
// Mode 2 (nến quét LTF): vào ĐÚNG 1 CẶP lệnh — 1 market + 1 limit @ mốc 50%.
// Hai lệnh đếm 2 đơn vị vào Inp_MaxOrders_* nhưng KHÔNG bị hạn mức đó chặn: luật
// mạnh hơn là "1 biên = 1 cặp" (s.lineUsed).
// Vì ProcessLTFSweep() chạy NGOÀI khối bảo vệ của OnTick nên mọi chốt an toàn
// (EnableTrading / halt / Shield / news / spread) phải tự kiểm ở đây.
//+------------------------------------------------------------------+
void ExecutePairEntry(SCRTSource &s, int dir, double limitPrice, string setupName, STPConfig &cfg)
{
   if(!Inp_EnableTrading)
      return;                                  // chế độ chỉ theo dõi: đã báo Telegram, không vào lệnh
   if(g_halted || g_shieldStopped || g_accountPassed)
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (Shield/halt đang chặn).", s.tag, setupName); return; }
   if(IsInNewsWindow())
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (khung giờ tin tức).", s.tag, setupName); return; }
   if(Inp_MaxSpreadPoints > 0 && CurrentSpreadPoints() > Inp_MaxSpreadPoints)
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (spread %.1f > %d).", s.tag, setupName,
                 CurrentSpreadPoints(), Inp_MaxSpreadPoints); return; }

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   isBuy = (dir > 0);
   double line  = isBuy ? s.boundLow : s.boundHigh;
   double mkt   = isBuy ? ask : bid;

   // Giá đã chạy quá xa đường biên -> vào market lúc này là R:R xấu (SL vẫn nằm ở
   // râu quét, còn entry thì đã cách rất xa). Xử lý theo Inp_FarFromLine_Action.
   bool marketTooFar = (Inp_MaxDistFromLine_Pips > 0 &&
                        MathAbs(mkt - line) / GetPipSize() > Inp_MaxDistFromLine_Pips);

   if(!marketTooFar || Inp_FarFromLine_Action == Far_VanVaoMarket)
   {
      PlaceOneOrder(s, dir, mkt, false, "", setupName + " · market", cfg);
   }
   else if(Inp_FarFromLine_Action == Far_ChuyenThanhLimitTaiLine)
   {
      PrintFormat("[CRT][%s] %s: giá cách biên %.1f pip (> %.1f) -> đổi lệnh market thành LIMIT tại biên %s.",
                  s.tag, setupName, MathAbs(mkt - line) / GetPipSize(), Inp_MaxDistFromLine_Pips,
                  DoubleToString(line, _Digits));
      PlaceOneOrder(s, dir, line, true, "biên " + TFToString(Inp_HTF), setupName + " · limit tại biên", cfg);
   }
   else // Far_BoLenhMarket
   {
      PrintFormat("[CRT][%s] %s: giá cách biên %.1f pip (> %.1f) -> BỎ lệnh market, chỉ giữ limit 50%%.",
                  s.tag, setupName, MathAbs(mkt - line) / GetPipSize(), Inp_MaxDistFromLine_Pips);
   }

   PlaceOneOrder(s, dir, limitPrice, true, "mốc 50%", setupName + " · limit 50%", cfg);
}

//+------------------------------------------------------------------+
// Lõi đặt 1 lệnh, dùng chung cho cả 2 mode: validate -> tính SL/TP/lot -> gửi lệnh.
// mocTxt chỉ để ghi log cho dễ hiểu khi lệnh chờ bị từ chối.
//+------------------------------------------------------------------+
bool PlaceOneOrder(SCRTSource &s, int dir, double entry, bool useLimit, string mocTxt, string setupName, STPConfig &cfg)
{
   // Hạn mức số lệnh/vòng là khái niệm của Mode 1 (nhồi lệnh theo nhiều BOS/CHOCH).
   // Mode 2 bị chặn bởi luật mạnh hơn: 1 phía biên = đúng 1 cặp lệnh (lineUsedLow/High).
   if(Inp_TradeMode == TradeMode_BOS_KhungEntry &&
      s.maxOrdersPerRound > 0 && s.ordersThisRound >= s.maxOrdersPerRound)
      return false;

   g_trade.SetExpertMagicNumber(s.magic);

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf   = Inp_SL_BufferPips * GetPipSize();
   bool   isBuy = (dir > 0);

   // Giá vào lệnh đã VƯỢT QUA đường Middle -> setup coi như đã chạy xong, vào lúc này là
   // muộn: phần lớn dư địa tới đích đã mất. Với TP_Middle thì còn vô lý hẳn (BUY mà TP
   // lại nằm dưới entry — ComputeTP sẽ âm thầm lùi TP về biên đối diện).
   // Áp cho CẢ market lẫn limit, CẢ 2 mode — cùng tinh thần với CancelPendingsAtTarget().
   if(s.boundReady && s.boundHigh > 0 && s.boundLow > 0)
   {
      double mid = (s.boundHigh + s.boundLow) / 2.0;
      if((isBuy && entry >= mid) || (!isBuy && entry <= mid))
      {
         PrintFormat("[CRT][%s] Bỏ qua %s%s: giá vào %s đã vượt Middle %s -> setup đã chạy xong.",
                     s.tag, isBuy ? "BUY" : "SELL", useLimit ? " LIMIT" : "",
                     DoubleToString(entry, _Digits), DoubleToString(mid, _Digits));
         return false;
      }
   }

   if(useLimit)
   {
      if(entry <= 0 || entry == EMPTY_VALUE)
      { PrintFormat("[CRT][%s] Bỏ qua %s: chưa có mốc giá để đặt limit (%s).",
                    s.tag, isBuy ? "BUY" : "SELL", mocTxt == "" ? "không xác định" : mocTxt); return false; }

      // Lệnh chờ phải nằm đúng phía so với giá hiện tại và cách tối thiểu stops level của sàn.
      double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(isBuy && entry >= ask - stopLvl)
      { PrintFormat("[CRT][%s] Bỏ qua BUY LIMIT: giá đã ở/dưới %s (%s), không đặt chờ được.", s.tag, mocTxt, DoubleToString(entry,_Digits)); return false; }
      if(!isBuy && entry <= bid + stopLvl)
      { PrintFormat("[CRT][%s] Bỏ qua SELL LIMIT: giá đã ở/trên %s (%s), không đặt chờ được.", s.tag, mocTxt, DoubleToString(entry,_Digits)); return false; }
   }

   // SL "ảo" LUÔN được tính (kể cả chế độ không đặt SL) vì còn dùng để tính lot theo risk,
   // tính TP theo R:R và lọc Inp_MaxSL_Pips. Chỉ khác ở chỗ có gửi lên sàn hay không.
   double sl    = isBuy ? s.sweptLow - buf : s.sweptHigh + buf;
   double tp    = ComputeTP(s, dir, entry, sl, cfg);

   if(isBuy  && tp <= entry) { PrintFormat("[CRT][%s] Bỏ qua BUY: TP không hợp lệ (giá đã vượt biên trên).", s.tag); return false; }
   if(!isBuy && tp >= entry) { PrintFormat("[CRT][%s] Bỏ qua SELL: TP không hợp lệ (giá đã vượt biên dưới).", s.tag); return false; }

   // SL phải nằm ĐÚNG PHÍA so với entry. Nếu giá đã xuyên qua mốc râu quét (BUY: giá rơi
   // xuống dưới sweptLow) thì setup đã hỏng — không được vào lệnh. Không có chốt này thì
   // MathAbs() bên dưới sẽ che mất lỗi: filter MaxSL_Pips vẫn qua, lot tính từ khoảng cách
   // vô nghĩa, và ở chế độ SLMode_KhongDatSL lệnh sẽ vào thật với rủi ro đảo ngược.
   if(isBuy  && sl >= entry)
   { PrintFormat("[CRT][%s] Bỏ qua BUY: giá đã rơi xuống dưới mốc SL %s -> setup hỏng.", s.tag, DoubleToString(sl,_Digits)); return false; }
   if(!isBuy && sl <= entry)
   { PrintFormat("[CRT][%s] Bỏ qua SELL: giá đã vượt lên trên mốc SL %s -> setup hỏng.", s.tag, DoubleToString(sl,_Digits)); return false; }

   double slDist = MathAbs(entry - sl);
   if(Inp_MaxSL_Pips > 0)
   {
      double slPips = slDist / GetPipSize();
      if(slPips > Inp_MaxSL_Pips)
      {
         PrintFormat("[CRT][%s] Bỏ qua %s: SL cách %.1f pip (> %.1f).",
                     s.tag, isBuy ? "BUY" : "SELL", slPips, Inp_MaxSL_Pips);
         return false;
      }
   }

   double lots = CalcLots(slDist);
   if(lots <= 0) { PrintFormat("[CRT][%s] Bỏ qua %s: lots=0 (hết margin hoặc dưới lot tối thiểu).", s.tag, isBuy ? "BUY" : "SELL"); return false; }

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
      PrintFormat("[CRT][%s] ✅ %s%s %.2f lot @%s SL %s TP %s%s", s.tag,
                  isBuy ? "BUY" : "SELL", useLimit ? " LIMIT" : "",
                  lots, DoubleToString(entry,_Digits),
                  (slOrder > 0 ? DoubleToString(sl,_Digits) : "KHÔNG ĐẶT (ảo " + DoubleToString(sl,_Digits) + ")"),
                  DoubleToString(tp,_Digits),
                  setupName == "" ? "" : ("  [" + setupName + "]"));
      NotifyOrderPlaced(s, dir, lots, entry, sl, tp, useLimit, setupName);
   }
   else
      PrintFormat("[CRT][%s] ❌ %s lỗi: %d %s", s.tag, isBuy ? "BUY" : "SELL",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return ok;
}

//+------------------------------------------------------------------+
// Báo Telegram khi lệnh đã khớp (chỉ ở chế độ vào lệnh — đồng bộ với BOT_TLS).
//+------------------------------------------------------------------+
void NotifyOrderPlaced(SCRTSource &s, int dir, double lots, double entry, double sl, double tp,
                       bool useLimit, string setupName)
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

   // Nhãn dòng giá: Mode 2 tự mô tả qua setupName; Mode 1 lấy theo Inp_Entry_Mode.
   string priceLabel;
   if(Inp_TradeMode == TradeMode_NenQuet_LTF)
      priceLabel = useLimit ? "Giá chờ (50%)" : "Entry";
   else if(Inp_Entry_Mode == EntryMode_LimitTaiZoneEntry)
      priceLabel = "Giá chờ (Zone " + TFToString(Inp_EntryTF) + ")";
   else if(Inp_Entry_Mode == EntryMode_LimitTaiBienHTF)
      priceLabel = "Giá chờ (biên " + TFToString(Inp_HTF) + ")";
   else
      priceLabel = "Entry";

   g_radar.SendMessageWithPhoto(StringFormat(
      "🛒 <b>%s %s — %s</b>\n━━━━━━━━━━━━━━━\n"
      "🔎 <b>Nguồn:</b> %s%s\n"
      "📦 <b>Khối lượng:</b> %s lot\n"
      "📍 <b>%s:</b> %s\n"
      "%s\n"
      "🎯 <b>TP:</b> %s (%s pip)\n"
      "💳 <b>Balance:</b> %s$",
      useLimit ? "ĐẶT LỆNH CHỜ" : "ĐÃ VÀO LỆNH",
      dir > 0 ? "MUA" : "BÁN", _Symbol, s.tag,
      setupName == "" ? "" : (" · " + setupName),
      DoubleToString(lots, 2),
      priceLabel,
      DoubleToString(entry, _Digits),
      slLine,
      DoubleToString(tp, _Digits), DoubleToString(tpPips, 1),
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
}

//+------------------------------------------------------------------+
// Tính giá TP theo bộ tham số cfg của chính nhánh setup đang vào lệnh.
// dir: +1 BUY / -1 SELL. entry/sl là giá đã xác định sẵn (SL luôn = râu quét ± đệm,
// không đổi theo mode) — cfg chỉ quyết định TP đặt ở đâu.
//+------------------------------------------------------------------+
double ComputeTP(SCRTSource &s, int dir, double entry, double sl, STPConfig &cfg)
{
   if(cfg.mode == TPMode_RR)
   {
      double riskDist = MathAbs(entry - sl);
      return (dir > 0) ? entry + cfg.rr * riskDist : entry - cfg.rr * riskDist;
   }

   if(cfg.mode == TPMode_Pips)
   {
      double dist = cfg.pips * GetPipSize(); // quy đổi pip dùng chung công thức với BOT_TLS
      return (dir > 0) ? entry + dist : entry - dist;
   }

   // TPMode_MidBienH4: TP bám theo biên. cfg.anchor quyết định lấy biên của CHÍNH nguồn
   // đã kích hoạt lệnh, hay của nến HTF LIỀN KỀ (g_srcAdj).
   bool dungLienKe = (cfg.anchor == Anchor_Mid_LienKe || cfg.anchor == Anchor_Bien_LienKe);

   // Nếu chọn biên liền kề mà nó chưa sẵn sàng thì lùi về biên của chính nguồn — thà TP
   // hơi khác ý muốn còn hơn tính ra số 0 rồi đặt lệnh sai.
   double bHigh = s.boundHigh;
   double bLow  = s.boundLow;
   if(dungLienKe && g_srcAdj.boundReady && g_srcAdj.boundHigh > 0 && g_srcAdj.boundLow > 0)
   {
      bHigh = g_srcAdj.boundHigh;
      bLow  = g_srcAdj.boundLow;
   }

   bool layMiddle = (cfg.anchor == Anchor_Mid_Nguon || cfg.anchor == Anchor_Mid_LienKe);
   double mid = (bHigh + bLow) / 2.0;

   if(dir > 0)
   {
      double tp = layMiddle ? mid : bHigh;
      if(tp <= entry) tp = bHigh;   // đảm bảo TP trên entry — fallback từ Middle sang biên xa hơn
      return tp;
   }
   else
   {
      double tp = layMiddle ? mid : bLow;
      if(tp >= entry) tp = bLow;
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
// Giá đã chạm đường Middle của biên nguồn này -> coi như "cú chạy đã xong": mọi lệnh
// CHỜ cùng chiều chưa khớp đều mất ý nghĩa (giá đã đi tới đích mà không khớp mình),
// nên huỷ. Chỉ đụng tới lệnh chờ — vị thế đã khớp vẫn để TP/SL của nó tự chạy.
// Middle lấy theo biên của CHÍNH nguồn đó, đồng bộ với cách ComputeTP() tính TP_Middle.
//+------------------------------------------------------------------+
void CancelPendingsAtTarget(SCRTSource &s)
{
   if(!s.boundReady || s.boundHigh <= 0 || s.boundLow <= 0)
      return;

   double mid = (s.boundHigh + s.boundLow) / 2.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk))                    continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)        continue;
      if(OrderGetInteger(ORDER_MAGIC)  != s.magic)       continue;

      long ot    = OrderGetInteger(ORDER_TYPE);
      bool isBuy = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
      bool isSell= (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
      if(!isBuy && !isSell) continue;

      // [v1.62] Mốc huỷ do người dùng chọn. Lệnh chờ BUY sinh ra từ cú quét biên DƯỚI nên
      // đích của nó nằm ở TRÊN -> giá lên tới mốc là hết cửa; lệnh chờ SELL ngược lại.
      // Biên đối diện của BUY là biên TRÊN, của SELL là biên DƯỚI.
      double target = (Inp_CancelPendingAt == CancelAt_Middle)
                         ? mid
                         : (isBuy ? s.boundHigh : s.boundLow);
      string tenMoc = (Inp_CancelPendingAt == CancelAt_Middle) ? "Middle" : "biên đối diện";

      bool reached = isBuy ? (bid >= target) : (ask <= target);
      if(!reached) continue;

      if(g_trade.OrderDelete(tk))
         PrintFormat("[CRT][%s] Giá chạm %s %s -> huỷ lệnh chờ %s #%I64u (coi như đã chạm TP trước khi khớp).",
                     s.tag, tenMoc, DoubleToString(target, _Digits), isBuy ? "BUY" : "SELL", tk);
   }
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
   string htf = TFToString(Inp_HTF);
   if(Inp_EntrySource == Bien_LienKe) return htf + " liền kề";
   if(Inp_EntrySource == Bien_Swing)  return htf + " Swing";
   return "Cả 2: " + htf + " liền kề + " + htf + " Swing";
}

//+------------------------------------------------------------------+
// Báo Telegram khi lệnh đóng (SL/TP/bot tự đóng) — đồng bộ với BOT_TLS.
//+------------------------------------------------------------------+
// [Mode 2] Sau khi 1 lệnh trong cặp chạm TP: lệnh còn lại CÙNG CHIỀU, cùng magic
//   · còn là lệnh chờ -> huỷ (setup đã ăn xong, không cần vào thêm)
//   · đã thành vị thế -> kéo SL về entry để khoá lỗ về 0
// Chỉ dời SL khi việc đó có LỢI (BUY: entry > SL hiện tại), tránh nới lỏng SL đang tốt.
//+------------------------------------------------------------------+
void HandlePairAfterTP(long magic, int dir)
{
   bool isBuy = (dir > 0);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)          continue;
      if(OrderGetInteger(ORDER_MAGIC)  != magic)           continue;
      long ot = OrderGetInteger(ORDER_TYPE);
      bool sameDir = isBuy ? (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP)
                           : (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
      if(!sameDir) continue;

      if(g_trade.OrderDelete(tk))
         PrintFormat("[CRT] Cặp lệnh: 1 lệnh đã chạm TP -> huỷ lệnh chờ #%I64u cùng chiều.", tk);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != magic)  continue;
      long pt = PositionGetInteger(POSITION_TYPE);
      if(isBuy != (pt == POSITION_TYPE_BUY)) continue;

      // [v1.62] LƯU Ý — việc dời SL này CHỈ THÀNH CÔNG khi lệnh còn lại đang LÃI.
      // Cặp BUY: lệnh chờ vào THẤP hơn lệnh market, nên TP của nó có thể nằm dưới cả điểm
      // vào của lệnh market (vd market 4400.86 · limit 4382.60 TP 4387.60). Lúc limit ăn
      // TP thì market đang âm, dời SL về 4400.86 tức đặt SL TRÊN giá hiện tại -> sàn trả
      // lỗi invalid stops. Cặp SELL không gặp vì lệnh chờ vào CAO hơn.
      // CỐ Ý ĐỂ NGUYÊN (quyết định người dùng 2026-08-18): lệnh âm cứ chạy tiếp tới SL/TP
      // của chính nó. Đã cân nhắc 2 hướng khác — đóng luôn lệnh âm, hoặc nuốt dòng log
      // thất bại — và bỏ cả hai. Dòng log "dời SL THẤT BẠI" ở đây là BÌNH THƯỜNG, không
      // phải lỗi cần vá.
      MovePositionToBreakeven(tk, "1 lệnh trong cặp đã chạm TP");
   }
}

//+------------------------------------------------------------------+
// Dời SL của 1 vị thế về đúng giá entry (hoà vốn). Chỉ dời khi việc đó CÓ LỢI
// (BUY: entry cao hơn SL hiện tại) để không bao giờ nới lỏng một SL đang tốt.
// Dùng chung cho 2 tình huống: 1 lệnh trong cặp chạm TP, và giá chạm biên đối diện.
//+------------------------------------------------------------------+
bool MovePositionToBreakeven(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);

   bool better = isBuy ? (sl == 0 || open > sl) : (sl == 0 || open < sl);
   if(!better)
      return false;   // SL hiện tại đã bằng/tốt hơn entry -> không đụng vào

   if(g_trade.PositionModify(ticket, NormalizeDouble(open, _Digits), tp))
   {
      PrintFormat("[CRT] %s -> dời SL vị thế #%I64u về entry %s (hoà vốn).",
                  reason, ticket, DoubleToString(open, _Digits));
      return true;
   }

   PrintFormat("[CRT] %s -> dời SL về entry cho #%I64u THẤT BẠI: %d %s",
               reason, ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
// Giá đã chạm biên ĐỐI DIỆN của nguồn -> vị thế đang lãi đậm. Kéo SL về entry để từ
// đây trở đi lệnh chỉ có thể gồng lãi, không thể quay đầu thành lỗ.
//   · BUY  (quét biên dưới) -> biên đối diện là boundHigh
//   · SELL (quét biên trên) -> biên đối diện là boundLow
// Chạy mỗi tick, cho cả 2 mode và cả 2 nguồn. Không đụng lệnh chờ.
//+------------------------------------------------------------------+
void MoveSLToEntryAtOppositeBound(SCRTSource &s)
{
   if(!s.boundReady || s.boundHigh <= 0 || s.boundLow <= 0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk))         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;
      if(PositionGetInteger(POSITION_MAGIC)  != s.magic) continue;

      bool isBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool reached = isBuy ? (bid >= s.boundHigh) : (ask <= s.boundLow);
      if(!reached) continue;

      MovePositionToBreakeven(tk, StringFormat("[%s] Giá chạm biên đối diện %s",
                              s.tag, DoubleToString(isBuy ? s.boundHigh : s.boundLow, _Digits)));
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
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

   // [Mode 2] Luật cặp lệnh: 1 lệnh chạm TP -> lệnh còn lại cùng chiều:
   //   · chưa khớp  -> huỷ lệnh chờ
   //   · đã khớp    -> dời SL về entry (hoà vốn)
   // Deal đóng lệnh có DEAL_TYPE ngược với chiều vị thế: SELL deal đóng vị thế BUY.
   if(Inp_TradeMode == TradeMode_NenQuet_LTF && reason == DEAL_REASON_TP)
   {
      int closedDir = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL) ? +1 : -1;
      HandlePairAfterTP(magic, closedDir);
   }

   if(!Inp_EnableTelegram)
      return;

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
      lines[n] = StringFormat("CRT · %s · Gốc %s · Quét %s%s",
                     Inp_TradeMode == TradeMode_NenQuet_LTF ? "Mode NẾN QUÉT" : "Mode BOS/CHOCH",
                     TFToString(Inp_HTF), TFToString(Inp_LTF),
                     Inp_TradeMode == TradeMode_NenQuet_LTF ? "" : (" · Entry " + TFToString(Inp_EntryTF)));
      clrs[n] = cNeutral; n++;

      if(AdjacentEnabled())
      {
         string htfN = TFToString(Inp_HTF);
         lines[n] = StringFormat("%s High: %s   ·   %s Middle: %s   ·   %s Low: %s",
                        htfN, DoubleToString(g_htfHigh, _Digits),
                        htfN, DoubleToString(HTF_Mid(), _Digits),
                        htfN, DoubleToString(g_htfLow,  _Digits)); clrs[n] = cNeutral; n++;

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
         string vaoTF = (Inp_TradeMode == TradeMode_NenQuet_LTF)
                        ? TFToString(Inp_LTF) : TFToString(Inp_EntryTF);
         if(Inp_EntrySource == Bien_LienKe)
            entryTxt = "Vào lệnh (" + vaoTF + ") · " + EntryStatusText(g_srcAdj);
         else if(Inp_EntrySource == Bien_Swing)
            entryTxt = "Vào lệnh (" + vaoTF + ") · " + EntryStatusText(g_srcLM);
         else
            entryTxt = "Vào lệnh (" + vaoTF + ") · " + EntryStatusText(g_srcAdj) +
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
   // Mode 1 hiện trạng thái arm; Mode 2 hiện trạng thái riêng của nó (chờ nến 2 / biên cháy).
   string armTxt = "—";
   if(Inp_TradeMode == TradeMode_NenQuet_LTF)
   {
      // [v1.59] Chỉ còn báo việc ĐANG DIỄN RA. Trạng thái "biên đã dùng" nay đọc thẳng
      // trên chart (đường xám + nhãn "đã dùng") nên không nhồi thêm chữ vào dashboard.
      if(s.m2Waiting)
         armTxt = (s.m2Dir > 0) ? "chờ nến 2 (BUY)" : "chờ nến 2 (SELL)";
   }
   else if(s.armed)
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
