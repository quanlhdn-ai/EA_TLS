//+------------------------------------------------------------------+
//|                                             CRT_MultiTF_EA.mq5   |
//|                                                          AnhTuan |
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.85"

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
//   [1.63] TIN TELEGRAM DẠNG CHIA SẺ CỘNG ĐỒNG + NHÃN ĐƯỜNG GỌN LẠI.
//     (a) Inp_ShowLineName (input mới, mặc định TẮT): nhãn cạnh đường biên nay chỉ in GIÁ.
//         Bật lên mới hiện tên đầy đủ ("H4 High: 4680.98", "Last Major Low: 4594.43").
//         Ở chế độ gọn KHÔNG in thêm chữ "· đã dùng" — trạng thái đó đã đọc được bằng màu
//         xám của chính đường kẻ (v1.59), in thêm chữ là phá mất mục đích "chỉ giá".
//         Khoảng chừa mép phải khung nhìn cũng co lại theo, nếu không nhãn ngắn mà line
//         vẫn cụt sớm như cũ.
//     (b) Inp_TG_TinPublic (input mới, mặc định BẬT): đổi toàn bộ tin Telegram sang dạng
//         PUBLIC gọn — chỉ Entry / SL / TP / giờ / miễn trừ trách nhiệm. Bỏ hẳn Nguồn,
//         Biên H4, Râu quét, khối lượng, TP tính bằng pip, Balance và P&L: đây là kênh
//         chia sẻ cho cộng đồng, không phải nhật ký tài khoản. Tắt input này thì mọi tin
//         trở lại y nguyên bản 1.62 — không phải compile lại để đổi ý.
//     (c) GỘP 2 TIN THÀNH 1, VÀ CHỈ PHÁT KHI LỆNH ĐÃ VÀO THẬT. Trước đây NotifySignal()
//         bắn tin (kèm chart) NGAY khi xác nhận quét râu — tức TRƯỚC ExecutePairEntry().
//         Mà ExecutePairEntry có thể không đặt được lệnh nào (spread, khung tin, Shield,
//         quá xa biên, giá đã vượt Middle, SL quá rộng, lot = 0, sai stops level) -> kênh
//         public lãnh một tín hiệu "ma" mà bot không hề vào. Nay tin public phát Ở CUỐI
//         ExecutePairEntry, dựng từ ĐÚNG những lệnh đặt thành công; không lệnh nào vào
//         thì im lặng, chỉ ghi log. Riêng chế độ CHỈ THEO DÕI vẫn phát (giá dự kiến).
//     (d) "Entry vùng" = [giá lệnh market, giá lệnh limit 50%] làm tròn số nguyên, và
//         "khoảng X – Y pips" = khoảng cách từ SL tới hai giá đó (limit gần SL hơn -> số
//         nhỏ). Nếu chỉ vào được 1 lệnh thì in 1 giá + 1 con số pip.
//     (e) TP in nguyên văn theo Inp_TG_TP_Text ("5 - 10 - 30 giá") — cố ý KHÔNG tính từ
//         TP thật của lệnh: TP của bot bám Middle/biên nên mỗi kèo một số, không dùng làm
//         hướng dẫn chung cho người đọc được.
//     (f) TIN KẾT THÚC TÍN HIỆU (đề nghị của người dùng): mỗi lần lệnh CHỜ bị huỷ, hoặc
//         một vị thế đóng, kênh nhận một tin "vùng entry hết hiệu lực" kèm lý do — tránh
//         việc người theo tín hiệu vào muộn ở vùng giá đã chạy xong. CancelEAPendings()
//         nay TRẢ VỀ số lệnh xoá được để chỉ báo khi thực sự có cái để huỷ; gọi từ
//         CloseAllBotOrders() thì cố ý KHÔNG báo vì Shield/Account SL đã có tin riêng.
//     (g) GIỜ IN TRONG TIN LÀ GIỜ VIỆT NAM (GMT+7), không phải giờ server sàn. Lý do đầy
//         đủ ở GioVietNam(). Chỉ đụng tin Telegram — log terminal và mọi mốc thời gian
//         dùng cho LOGIC vẫn là giờ server, không được đổi.
//
//   [1.64] DỌN ẢNH CHỤP TRƯỚC KHI LÊN KÊNH PUBLIC — 2 input mới, cả hai mặc định BẬT.
//     (a) Inp_TG_AnMucLenh: tắt CHART_SHOW_TRADE_LEVELS lúc chụp. Ảnh cũ in nguyên
//         "BUY 0.1 at 4614.00 / BUY LIMIT 0.1 at 4609.79" ở mép trái — tức vẫn LỘ KHỐI
//         LƯỢNG dù dòng "Khối lượng" đã bị bỏ khỏi tin ở 1.63. Sót chỗ này thì công bỏ
//         dòng kia thành vô nghĩa.
//     (b) Inp_TG_CheTenEA: đè OBJ_RECTANGLE_LABEL màu nền lên nhãn "tên EA + icon" mà
//         terminal vẽ ở góc phải trên. KHÔNG có chart property nào tắt được nhãn đó —
//         đã tra tài liệu và diễn đàn MQL5, đè object là cách duy nhất.
//         ĐÃ KIỂM CHỨNG THẬT ngày 27/08 bằng script Test_CheNhanEA (nằm trong
//         MQL5\Scripts của terminal, không thuộc repo): chụp thử với tấm che ĐỎ CHÓI,
//         nhãn "TLS_SMC_CSV_BOT_QUY" biến mất hoàn toàn -> object vẽ ĐÈ LÊN được nhãn
//         của terminal. Lần chụp thứ 2 với màu nền thì không nhìn ra vết gì.
//         Thanh giá bên phải KHÔNG bị che: XDISTANCE đo từ mép phải VÙNG VẼ, không tính
//         thanh giá.
//     (c) Cả hai làm trong SendPhotoSach() của chính bot, CỐ Ý không sửa Telegram_Radar.mqh
//         — file đó byte-identical với BOT_TLS và BOT_OB_Radar, sửa là phải mirror cả 3.
//         Dựng tạm -> chụp -> trả lại nguyên trạng, chart người dùng không đổi lâu dài.
//     (d) CẠM BẪY đã trả giá một lần test: OBJ_RECTANGLE_LABEL neo bằng góc trên-TRÁI
//         CỦA CHÍNH NÓ, nên với CORNER_RIGHT_UPPER phải đặt XDISTANCE = ĐÚNG BỀ RỘNG
//         tấm che. Đặt 0 là nó nằm gọn ngoài màn hình, chụp ra không thấy gì.
//     (e) Kích thước 190x24 vừa đủ ôm "CRT_MultiTF_EA" + icon (đo được ~120px). ĐỪNG nới
//         rộng thêm cho "chắc ăn": tấm che xoá thật vùng chart nằm dưới nó, nới quá là
//         ăn mất nhãn giá của đường biên khi đường đó nằm gần đỉnh chart.
//
//   [1.65] TIN CHI TIẾT QUAY LẠI, NHƯNG TÁCH RIÊNG THÀNH TIN THỨ HAI.
//     BỐI CẢNH VẬN HÀNH (không có chỗ này thì thiết kế dưới đây trông vô lý): bot bắn tin
//     vào GROUP RIÊNG của chủ bot, rồi chủ bot FORWARD TAY tin public sang group member.
//     Nên hai loại tin sống chung một kênh là bình thường — chỉ tin public mới đi ra ngoài.
//     Vì vậy tin chi tiết CỐ Ý giữ nguyên lot và Balance: nó không bao giờ tự lộ.
//     · Inp_TG_TinChiTiet (input mới, mặc định BẬT): gửi thêm tin chi tiết ở 2 thời điểm
//       — lúc vào lệnh và lúc đóng lệnh.
//     · LUẬT SỐNG CÒN CỦA TIN CHI TIẾT: chỉ chứa thứ tin public KHÔNG có. Không lặp lại
//       chiều lệnh, symbol, giá entry, SL, TP. Yêu cầu người dùng 27/08 sau khi thử bản
//       đầu: hai tin liên tiếp mà cùng in giá thì nhìn tưởng bot vào 2 kèo khác nhau.
//       Còn lại đúng 3 thứ: nhánh setup, khối lượng, tiền. Mở đầu bằng "⚙️ chi tiết nội
//       bộ" để nhìn phát biết không phải tín hiệu, tránh forward nhầm sang group member.
//     · GỘP CẢ CẶP VÀO 1 TIN. NotifyOrderPlaced chạy mỗi lệnh một lần nên KHÔNG dùng nó
//       để bắn tin chi tiết ở Mode nến quét (giữ nguyên im lặng như 1.63) — tin chi tiết
//       phát ở cuối ExecutePairEntry, một tin cho cả cặp, ghi lot của TỪNG lệnh.
//       Lot 2 lệnh có thể KHÁC NHAU thật: CalcLots() tính theo khoảng cách tới SL, mà
//       market và limit 50% cách SL khác nhau — nên phải ghi riêng, không gộp một số.
//     · Lot lấy qua biến dùng chung g_lotVuaDat thay vì đổi chữ ký PlaceOneOrder (hàm đó
//       có 4 chỗ gọi ở 2 mode). An toàn vì mọi thứ chạy tuần tự trong cùng luồng OnTick.
//     · Tin ĐÓNG LỆNH chi tiết: "vào X → đóng Y" + lot + P&L + Balance. Cặp giá vào->đóng
//       là thứ DUY NHẤT phân biệt được vừa chốt lệnh market hay lệnh limit 50%, vì comment
//       lệnh ("CRT buy Swing") không ghi nhánh setup lẫn loại lệnh. Giá vào lấy bằng
//       GiaVaoCuaViThe() truy ngược từ DEAL_POSITION_ID.
//       Lý do đóng CHỈ in khi tin public nói không rõ: TP/SL đã thành tiêu đề tin public
//       rồi, còn "bot tự đóng" / "đóng tay" bị public gộp thành "ĐÃ ĐÓNG LỆNH" nên phải
//       nói thêm ở tin chi tiết mới biết chuyện gì xảy ra.
//     · CẠM BẪY: GiaVaoCuaViThe() gọi HistorySelectByPosition() -> ĐỔI bộ nhớ đệm history
//       mà HistoryDealGetX(trans.deal, ...) đang dựa vào. Mọi giá trị của trans.deal phải
//       đọc XONG trước khi gọi nó. Đã gom sẵn lotDong/giaDong/posId lên đầu hàm.
//
//   [1.66] GẮN THƯ VIỆN NẾN DÙNG CHUNG Signal_Candle.mqh — 2 input mới, CẢ HAI MẶC ĐỊNH
//     TẮT nên hành vi bot KHÔNG đổi cho tới khi tự tay bật.
//     · Thư viện (bản gốc ở EA_TLS/Lib_Signal_Candle/) giữ định nghĩa pinbar + engulfing
//       dùng chung cho mọi bot, chỉ xét HÌNH DẠNG nến. Mọi điều kiện vị trí (đã quét qua
//       biên, đóng lại trong biên, cửa sổ 2 cây) vẫn nằm nguyên ở bot này.
//       Bản trong MQL5/Include phải luôn giống hệt bản gốc — xem EA_TLS/CLAUDE.md.
//     · Inp_Lib_Pinbar đổi PassesWickFilter sang luật thư viện. KHÁC BIỆT: luật cũ cho nến
//       THUẬN chiều qua thẳng không đo râu gì cả, chỉ nến ngược chiều mới bị đo râu/thân.
//       Luật thư viện KHÔNG xét màu thân, mà đòi râu mũi >= 60% biên độ VÀ râu đối diện
//       <= 25% biên độ VÀ râu mũi >= 1.5 x thân. Bật lên là 2.1/2.1b vào ít lệnh hơn —
//       phải backtest lại, đừng bật thẳng trên tài khoản thật.
//       [2026-09-12] Thư viện lên v1.1: BỎ điều kiện "nến đóng thuận chiều lệnh" của v1.0,
//       sau khi soi tay 6 cây nến bot này loại trong backtest 01-11/09/2026 — 4 cây trượt
//       DUY NHẤT vì màu thân dù hình dạng đạt thoáng (ca nặng nhất: râu mũi 92% biên độ,
//       thân 4.3 pip). Lý do đầy đủ ghi ở đầu Signal_Candle.mqh.
//     · Inp_Lib_Engulfing đổi điều kiện ĐỦ của 2.2.1: thêm yêu cầu cây 2 TRÙM cả High lẫn
//       Low nến gốc, ngoài yêu cầu đóng vượt mốc như cũ. Nến gốc nay lưu thêm Open/Close
//       (m2OriginOpen/Close) để dựng đủ cây nến truyền cho thư viện.
//     · Các dòng log 2.1 / 2.1b / 2.2 tự đổi câu chữ theo luật đang bật, để đọc log biết
//       ngay lượt chạy đó dùng luật nào.
//
//   [1.67] HOÀ VỐN THEO KHOẢNG LÃI — Inp_BE_TriggerPips (input mới, mặc định 50 pip).
//     Lãi của một vị thế đạt ngưỡng này thì SL dời về đúng giá vào lệnh. Để 0 là tắt.
//     Đây là luật hoà vốn THỨ BA, chạy song song chứ không thay thế 2 luật cũ:
//       · chạm biên đối diện   (v1.44) — bám MỐC GIÁ
//       · 1 lệnh trong cặp TP  (v1.37) — bám SỰ KIỆN
//       · lãi đạt N pip        (1.67)  — bám KHOẢNG LÃI
//     Cả ba cùng gọi MovePositionToBreakeven(), mà hàm đó chỉ dời khi việc dời CÓ LỢI —
//     nên luật nào kích trước thì thắng, luật sau không phá được kết quả của luật trước.
//     Không cần thứ tự ưu tiên, không cần cờ chống trùng.
//     VÌ SAO CẦN THÊM: hai luật cũ đều có thể KHÔNG BAO GIỜ kích. Biên đối diện của nguồn
//     Swing có khi cách cả trăm pip, còn luật cặp lệnh chỉ chạy nếu vế kia ăn TP. Giá chạy
//     thuận rất xa rồi quay đầu về SL gốc là ca hoàn toàn có thật, trước 1.67 không có gì
//     chặn.
//     Đo lãi bằng giá ĐÓNG ĐƯỢC: BUY theo Bid, SELL theo Ask — đúng thứ sàn dùng tính lãi
//     lỗ. Lấy nhầm chiều giá là lệch nguyên một spread; vàng spread 24 pip nên sai chỗ này
//     đủ để lệnh kích hoà vốn sớm hơn thực tế.
//     Đặt NGOÀI khối bảo vệ của OnTick như 2 luật kia: siết SL luôn an toàn, phải chạy
//     được cả khi Shield/halt đang chặn vào lệnh mới.
//
//   [1.68] THÊM OnTester() — phục vụ đợt tối ưu TP / SL / BE / cặp khung.
//     · MQL5 KHÔNG gọi OnTester khi EA chạy thật, nên phần này không đụng gì tới bot
//       đang chạy. Không thêm input, không đổi logic vào lệnh.
//     · In bảng [TESTER]: thống kê tổng, tách theo nguồn biên (LiềnKề / Swing) và theo
//       chiều lệnh. Tiền tố [TESTER] để Tools/Summarize-Backtest.ps1 bóc được.
//     · In KỲ VỌNG MỖI LỆNH KÈM SAI SỐ và chỉ số t. Không có sai số thì không phân biệt
//       được "cấu hình này tốt hơn" với "lượt này gặp may" — đúng cái bẫy đã làm hỏng
//       19 lượt chạy của BOT_TLS_GetChart.
//     · Inp_BE_TaiBienDoiDien (mặc định BẬT = giữ nguyên hành vi cũ): công tắc cho luật
//       hoà vốn v1.44. Trước đây luật này chạy cứng, không tắt được — mà nó kéo SL về
//       entry nên CẮT NGANG hành trình lệnh, lượt đo không thấy được lệnh thật sự chạy
//       tới đâu. Nay tắt được để đo, và cũng thành một tham số so sánh được khi tối ưu.
//     · Trả điểm cho chế độ Optimization (Tools/Run-Backtest.ps1 đặt sẵn
//       OptimizationCriterion=6 = Custom max). TRƯỚC 1.68 BOT NÀY KHÔNG CÓ OnTester nên
//       mọi lượt tối ưu đều bị chấm 0 điểm — bảng xếp hạng vô nghĩa.
//       Điểm = lãi% / sụt vốn%, phạt tuyến tính nếu dưới 100 lệnh, loại thẳng nếu dưới
//       30 lệnh. Cố ý KHÔNG dùng lãi thuần làm tiêu chí: nó luôn chọn cấu hình liều nhất.
//
//   [1.69] BỐN THIẾT LẬP THEO YÊU CẦU NGƯỜI DÙNG 20/09. Không đụng logic nhận diện tín
//     hiệu; chỉ thêm công tắc và một cách tính lot.
//     (a) Inp_BE_KhiLenhKiaTP (mặc định BẬT) — công tắc cho luật hoà vốn THỨ BA. Nay cả
//         ba luật hoà vốn đều tắt được độc lập:
//           Inp_BE_TriggerPips   = 0     -> tắt luật theo khoảng lãi   (1.67)
//           Inp_BE_TaiBienDoiDien = false -> tắt luật theo biên đối diện (1.68)
//           Inp_BE_KhiLenhKiaTP   = false -> tắt luật theo cặp lệnh      (1.69)
//         Tắt cả ba thì lệnh giữ nguyên SL gốc tới cùng — cần khi muốn đo hành trình
//         trọn vẹn của một setup lúc backtest.
//         [1.70 thay thế mục này bằng Inp_KieuVaoLenh 3 chế độ — xem dưới.]
//     (c) Inp_LotMode THAY CHO input bool Inp_UseRiskPercent — 3 chế độ: lot cố định /
//         % tài khoản / SỐ TIỀN $ (mới). Chế độ mới gõ thẳng số $ chịu mất nếu dính SL,
//         bot chia ngược ra lot. Khác % tài khoản ở chỗ nó KHÔNG co giãn theo balance:
//         mỗi lệnh thua đúng một khoản đã biết trước.
//         THỨ TỰ GIÁ TRỊ ENUM CỐ Ý GIỮ: 0 = lot cố định (ứng với bool false cũ),
//         1 = % tài khoản (ứng với true cũ). Nhờ vậy giá trị trong .set cũ vẫn ánh xạ
//         đúng chế độ; chỉ TÊN input đổi nên phải sửa lại dòng đó trong cả 2 file .set.
//         Cả 2 chế độ tính-ngược đều cần SL > 0 — dùng kèm SLMode_KhongDatSL thì hàm trả
//         lot = 0 và lệnh bị bỏ. Muốn chạy không SL thì phải để lot cố định.
//     (d) DD ngày và Lãi ngày: ĐÃ CÓ SẴN từ trước, không thêm gì —
//         Inp_DailyDrawdownLimit và Inp_DailyProfitLimit ở nhóm 4 (SHIELD).
//
//   [1.70] KIỂU VÀO LỆNH 3 CHẾ ĐỘ + ĐỔI MẶC ĐỊNH THEO YÊU CẦU 20/09.
//     (a) Inp_KieuVaoLenh thay Inp_VaoCapLenh (bool chỉ có 2 nước) — nay 3 chế độ:
//           KieuVao_TrucTiep : chỉ lệnh market tại giá hiện tại
//           KieuVao_Limit    : chỉ lệnh chờ tại mốc 50% râu quét
//           KieuVao_CaHai    : cả hai (MẶC ĐỊNH, hành vi cũ)
//         CHỖ DỄ SÓT: chế độ CHỈ LIMIT phải bỏ qua TRỌN khối market, kể cả nhánh
//         "quá xa biên -> đổi market thành limit tại biên". Nhánh đó sinh ra để CỨU vế
//         market; không có vế market thì để nó chạy là tự nhiên mọc thêm một lệnh limit
//         thứ hai tại đường biên, thành ra vẫn 2 lệnh dù người dùng chọn 1.
//     (b) Đổi mặc định trong code cho khớp cấu hình người dùng chốt 20/09:
//           Inp_LotMode            = LotMode_SoTienUSD (trước: lot cố định)
//           Inp_RiskMoneyUSD       = 100  (trước: 50)
//           Inp_DailyDrawdownLimit = 3    (trước: 0 = tắt)
//           Inp_DailyProfitLimit   = 5    (trước: 0 = tắt)
//         Ba luật hoà vốn GIỮ NGUYÊN mặc định bật (50 pip / biên đối diện / cặp lệnh).
//     (c) File .set: gom 2 bản (CRT_MultiTF_EA.set + crt.set) thành MỘT bản duy nhất
//         CRT_MultiTF_EA.set, dựng trên nền cấu hình ĐANG CHẠY THẬT chứ không phải bản
//         preset repo — vì bản chạy thật mới là thứ đã qua thực chiến. Xem nhật ký.
//
//   [1.71] CHUYỂN KÊNH TELEGRAM SANG CHANNEL CÔNG KHAI — ĐỔI MÔ HÌNH VẬN HÀNH.
//     Từ 20/09 bot bắn thẳng vào channel CRT_Signal_TradingZone (id -1004487964833) và
//     MEMBER ĐỌC TRỰC TIẾP. Trước đó bot bắn vào group riêng của chủ bot rồi chủ bot
//     forward tay tin public sang group member.
//     HỆ QUẢ SỐNG CÒN: cơ chế lọc-bằng-tay biến mất. Bản 1.65 cố ý cho tin chi tiết giữ
//     nguyên lot và Balance vì "nó không bao giờ tự lộ" — tiền đề đó nay KHÔNG CÒN ĐÚNG.
//     Nên Inp_TG_TinChiTiet đổi mặc định sang TẮT, và .set cũng tắt.
//     ĐÃ RÀ TOÀN BỘ đường ra Telegram trước khi chốt: cả 3 chỗ in lot/Balance (vào lệnh
//     Mode nến quét, vào lệnh Mode BOS, đóng lệnh) đều đi qua SendChiTiet() — hàm này có
//     cổng chặn ngay đầu, nên tắt 1 công tắc là bịt đủ cả 3. Các đoạn in Balance còn lại
//     nằm trong nhánh Inp_TG_TinPublic = false (định dạng cũ 1.62), không chạy.
//     Tin public tự nó sạch: chỉ Entry / SL tham khảo / TP / giờ VN / miễn trừ trách
//     nhiệm. Ảnh chụp cũng đã sạch sẵn nhờ Inp_TG_AnMucLenh (ẩn đường lệnh -> giấu khối
//     lượng) và Inp_TG_CheTenEA, cả hai vẫn BẬT.
//     NẾU SAU NÀY QUAY LẠI MÔ HÌNH FORWARD TAY: bật lại Inp_TG_TinChiTiet và trỏ ChatID
//     về group riêng — đừng bật tin chi tiết khi ChatID còn là channel công khai.
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
#include <Signal_Candle.mqh>   // thư viện nến tín hiệu dùng chung (bản gốc: Lib_Signal_Candle/)

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
// Cách quyết định khối lượng lệnh. THỨ TỰ CÁC GIÁ TRỊ KHÔNG ĐƯỢC ĐỔI: enum này thay cho
// input bool Inp_UseRiskPercent cũ, nên 0 phải ứng với false (lot cố định) và 1 với true
// (% tài khoản) — nhờ vậy file .set cũ nạp vào vẫn ra đúng chế độ người dùng đang chạy.
enum ENUM_CRT_LOT_MODE { LotMode_CoDinh, LotMode_PhanTramTK, LotMode_SoTienUSD };
// Mỗi setup được vào những lệnh nào. "Trực tiếp" = lệnh market tại giá hiện tại;
// "Limit" = lệnh chờ tại mốc 50% râu quét.
enum ENUM_CRT_KIEU_VAO { KieuVao_TrucTiep, KieuVao_Limit, KieuVao_CaHai };
// [v1.81] Nơi đặt SL khi vào lệnh bằng khung nhỏ.
//   SLtheo_RauM15 : râu nến CRT khung quét vừa quét biên — SL rộng, giống hành vi cũ.
//   SLtheo_RauXacNhan : râu nến khung nhỏ vừa tạo tín hiệu — SL hẹp hơn nhiều, R:R đẹp
//   hơn nhưng dễ bị quét hơn. Cả hai đều cộng thêm Inp_SL_BufferPips.
enum ENUM_CRT_SL_LTF { SLtheo_RauM15, SLtheo_RauXacNhan };
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
const ENUM_CRT_TRADE_MODE Inp_TradeMode     = TradeMode_NenQuet_LTF;    // Cách xác nhận vào lệnh:
const ENUM_CRT_SOURCE  Inp_EntrySource      = Ca2_LienKe_Va_Swing; // Vào lệnh theo biên giá nào của khung gốc:
input long             Inp_MagicNumber      = 20260713;   // Magic (nguồn Swing tự dùng Magic+1)
const int              Inp_MaxSpreadPoints  = 0;         // Spread tối đa cho phép vào lệnh, point (0 = tắt)
input ENUM_CRT_LOT_MODE Inp_LotMode         = LotMode_SoTienUSD; // Cách tính khối lượng lệnh:
input double           Inp_FixedLotSize     = 0.1;       //   • nếu Lot cố định — số lot mỗi lệnh
input double           Inp_RiskPercent      = 1.0;       //   • nếu % tài khoản — rủi ro mỗi lệnh (%)
input double           Inp_RiskMoneyUSD     = 100;       //   • nếu Số tiền — dính SL thì mất bao nhiêu $
input double           Inp_BalanceCoSo      = 10000;     // Balance gốc để quy đổi MỌI thiết lập % (0 = dùng số dư thật)
input double           Inp_AccountSL_Percent= 0.0;       // Đóng hết khi tài khoản âm quá % (từ lúc mở bot, 0=tắt)
input ENUM_CRT_SL_MODE Inp_SL_Mode          = SLMode_RauQuet; // Cách đặt SL:
input double           Inp_SL_BufferPips    = 30;        //   • nếu SLMode_RauQuet — SL lùi ra ngoài râu quét (pip)
input double           Inp_MaxSL_Pips       = 200;       // SL xa hơn số pip này thì bỏ lệnh (0=không giới hạn)
input double           Inp_MaxDistFromLine_Pips = 100;   // Giá cách biên quá số pip này -> Mode BOS: bỏ chờ; Mode Nến quét: xử lý theo mục 3 (0=tắt)
input double           Inp_BE_TriggerPips   = 50;        // Lãi đạt bao nhiêu pip thì dời SL về hoà vốn (0=tắt)
// [1.68] Công tắc cho luật hoà vốn v1.44 (chạm biên đối diện -> kéo SL về entry). MẶC ĐỊNH
// BẬT nên hành vi bot không đổi. Thêm vào vì hai lý do:
//   · Đo: luật này cắt ngang hành trình lệnh, tắt đi mới quan sát được trọn vẹn lệnh chạy
//     tới đâu — cần cho lượt chạy ghi hành trình.
//   · Tối ưu: nay nó thành một tham số so sánh được, thay vì luật cứng không kiểm chứng.
input bool             Inp_BE_TaiBienDoiDien = true;     // Chạm biên đối diện thì kéo SL về hoà vốn
input bool             Inp_BE_KhiLenhKiaTP  = true;      // Lệnh kia trong cặp chạm TP thì kéo SL về hoà vốn
input ENUM_CRT_KIEU_VAO Inp_KieuVaoLenh     = KieuVao_CaHai; // Mỗi setup vào những lệnh nào:
input bool             Inp_EntryLTF_Enable  = true;      // Vào lệnh bằng KHUNG NHỎ (khung quét chỉ xác nhận setup)
input ENUM_TIMEFRAMES  Inp_EntryLTF_TF      = PERIOD_M5; //   • Khung nhỏ dùng để tìm nến vào lệnh
input int              Inp_EntryLTF_MaxBars = 12;        //   • Chờ tối đa bao nhiêu nến khung nhỏ rồi bỏ setup
input ENUM_CRT_SL_LTF  Inp_EntryLTF_SLMode  = SLtheo_RauXacNhan; //   • Đặt SL theo râu nến nào:
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
input group "=== 2. RIÊNG Mode Nến quét ==="
input ENUM_CRT_FAR_ACTION Inp_FarFromLine_Action = Far_BoLenhMarket; // Khi giá đã cách biên > Inp_MaxDistFromLine_Pips:
// [1.66] Luật nến của thư viện dùng chung Signal_Candle.mqh — định nghĩa đầy đủ ghi ở đầu
// file đó. CẢ HAI MẶC ĐỊNH TẮT: bật lên là ĐỔI HÀNH VI VÀO LỆNH, phải backtest lại trước
// khi chạy tài khoản thật. Để dạng input để chạy đối chứng mà không phải compile lại.
//   · Pinbar thư viện (v1.1) KHÔNG xét màu thân nến: đòi râu mũi >= 60% biên độ VÀ râu đối
//     diện <= 25% biên độ VÀ râu mũi >= 1.5 x thân. Luật cũ thì cho nến THUẬN chiều qua
//     thẳng khỏi đo râu, chỉ đo nến ngược chiều. Nhiều setup 2.1/2.1b đang vào lệnh sẽ bị
//     loại (nến do dự hai đầu râu), đổi lại búa/sao băng đẹp không còn bị loại vì màu thân.
//   · Engulfing thư viện đòi thêm cây 2 phải TRÙM cả High lẫn Low nến gốc, trong khi luật
//     cũ chỉ đòi đóng vượt mốc nến gốc. Nhánh 2.2.1 sẽ vào ít lệnh hơn.
const bool             Inp_Lib_Pinbar       = true;       // 2.1/2.1b: dùng pinbar thư viện thay lọc râu cũ
const bool             Inp_Lib_Engulfing    = true;       // 2.2.1: dùng engulfing thư viện thay điều kiện đủ cũ
input bool             Inp_On_21_LK         = true;       // BẬT setup [LIỀN KỀ · 2.1 pinbar]
input bool             Inp_On_21b_LK        = true;       // BẬT setup [LIỀN KỀ · 2.1b pinbar cây 2]
input bool             Inp_On_21c_LK        = true;       // BẬT setup [LIỀN KỀ · 2.1c engulfing cây 2 (gốc đóng TRONG biên)]
input bool             Inp_On_21d_LK        = true;       // BẬT setup [LIỀN KỀ · 2.1d engulfing cây 3 (trùm cây 2 + quét sâu hơn)]
input bool             Inp_On_22_LK         = true;       // BẬT setup [LIỀN KỀ · 2.2 engulfing]
input bool             Inp_On_21_SW         = true;       // BẬT setup [SWING · 2.1 pinbar]
input bool             Inp_On_21b_SW        = true;       // BẬT setup [SWING · 2.1b pinbar cây 2]
input bool             Inp_On_21c_SW        = true;       // BẬT setup [SWING · 2.1c engulfing cây 2 (gốc đóng TRONG biên)]
input bool             Inp_On_21d_SW        = true;       // BẬT setup [SWING · 2.1d engulfing cây 3 (trùm cây 2 + quét sâu hơn)]
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
input group "=== 3. CHUNG · SHIELD (Bảo vệ tài khoản) ==="
input double           Inp_DailyDrawdownLimit = 3;       // Lỗ tối đa trong NGÀY, % (0 = tắt)
input double           Inp_DailyProfitLimit   = 5;       // Lãi mục tiêu trong NGÀY, % (0 = tắt)
input double           Inp_AutoPassTarget     = 0;       // Equity mục tiêu (USD), đạt thì dừng hẳn (0 = tắt)
input string           Inp_NewsTimes          = "";      // Giờ tin cần tránh, giờ server "15:30, 21:00" (trống = tắt)
input int              Inp_NewsBufferMinutes  = 2;       // Chặn vào lệnh trước/sau giờ tin bao nhiêu phút

// ===================== 4. TELEGRAM =====================
input group "=== 4. CHUNG · TELEGRAM ==="
input bool             Inp_EnableTelegram   = true;       // Bật gửi thông báo Telegram
input string           Inp_BotToken         = "8670907940:AAGkHoUQWn3hux6rUhdRF7291LVi_DUxvR0"; // Token của Bot Telegram
input string           Inp_ChatID           = "-1004487964833";      // ID chat/group/channel nhận thông báo
input bool             Inp_SendScreenshot   = true;      // Gửi kèm ảnh chart khi báo tín hiệu/vào lệnh
input bool             Inp_TG_TinPublic     = true;      // Tin dạng CHIA SẺ CỘNG ĐỒNG (gọn, giấu số dư)
input string           Inp_TG_TP_Text       = "5 - 10 - 30 giá"; // Dòng TP in nguyên văn trong tin public
input bool             Inp_TG_CheTenEA      = true;      // Ảnh chụp: che tên EA ở góc phải trên
input bool             Inp_TG_AnMucLenh     = true;      // Ảnh chụp: ẩn đường lệnh (tránh lộ khối lượng)
input bool             Inp_TG_TinChiTiet    = false;     // Gửi thêm tin CHI TIẾT (setup/lot/PnL) — TẮT nếu member đọc trực tiếp

// ===================== 5. THAM SỐ THEO KHUNG THỜI GIAN: H4 -> M15 -> M1 =====================
// Việc HIỂN THỊ đường H4 liền kề / Last Major đi theo Inp_EntrySource ở nhóm VẬN HÀNH —
// không có toggle riêng, để tránh hiện cùng lúc 4 đường khi chỉ dùng 1 nguồn để vào lệnh.
input group "=== 5. CHUNG · KHUNG GỐC (HTF) + Last Major Swing ==="
input ENUM_TIMEFRAMES Inp_HTF              = PERIOD_H4;  // Khung cao làm cơ sở High/Low
input int               Inp_HTF_SwingMajor  = 1;          // Số nến H4 mỗi bên xác định đỉnh/đáy Major Swing
input int               Inp_HTF_SwingMinor  = 1;          // Số nến H4 mỗi bên cho Minor Swing (engine cần)

input group "=== 6. CHUNG · KHUNG QUÉT RÂU (LTF) ==="
input ENUM_TIMEFRAMES  Inp_LTF             = PERIOD_M15; // Khung dùng để phát hiện quét râu
input bool             Inp_DetectLowSweep  = true;       // Bắt tín hiệu quét râu DƯỚI (chờ BUY)
input bool             Inp_DetectHighSweep = true;       // Bắt tín hiệu quét râu TRÊN (chờ SELL)


// ===================== 6. Ít quan trọng / ít đụng đến =====================
input group "=== 7. CHUNG · HIỂN THỊ ==="
input bool             Inp_ShowLineName    = false;      // Nhãn đường: hiện tên chi tiết (tắt = chỉ giá)
input bool             Inp_ShowMidLine     = true;       // Vẽ đường Middle 50% của H4
input bool             Inp_ShowDashboard   = true;       // Hiện bảng dashboard trên chart
// [1.68] Ghi hành trình từng lệnh ra CSV — CHỈ chạy trong Strategy Tester, bật tay khi cần
// đo. Mục đích: từ MỘT lượt chạy tính ngược ra kết quả của mọi mức TP và mọi mốc BE, khỏi
// phải quét hàng chục lượt. Muốn thấy hành trình đầy đủ thì lượt đó phải để TP thật xa và
// BE tắt, nếu không lệnh bị cắt ngang và số liệu vô nghĩa.
input bool             Inp_Ghi_HanhTrinh   = false;      // (Tester) Ghi hành trình từng lệnh ra CSV

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
   int      m2WaitKind;         // 1 = chờ engulfing (2.2) · 2 = chờ cây 2 (họ 2.1) · 4 = chờ cây 3 (2.1d)
   int      m2Dir;              // +1 = quét biên dưới (chờ BUY) / -1 = quét biên trên
   double   m2OriginHigh;       // High nến gốc — mốc so sánh cho điều kiện đủ ở 2.2.1
   double   m2OriginLow;        // Low nến gốc
   double   m2OriginBodyEdge;   // Mép THÂN nến gốc phía quét — cùng với High/Low tạo thành
                                // râu quét THẬT, dùng làm mốc 50% cho nhánh 2.1b
   double   m2OriginOpen;       // [1.66] Open/Close nến gốc — để dựng đủ cây nến truyền cho
   double   m2OriginClose;      // SC_IsEngulfing khi bật Inp_Lib_Engulfing
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

   // [v1.81] Trạng thái CHỜ VÀO LỆNH TRÊN KHUNG NHỎ. Setup đã được khung quét xác nhận
   // nhưng chưa vào lệnh — bot đợi giá hồi về vùng rồi mới tìm nến xác nhận ở khung nhỏ.
   bool      ltfWaiting;
   int       ltfDir;           // +1 BUY / -1 SELL
   double    ltfZoneFar;       // mép XA của vùng = mút râu quét (cũng là mốc huỷ setup)
   double    ltfZoneNear;      // mép GẦN  = giá tham chiếu lúc khung quét xác nhận
   double    ltfSlM15;         // SL tính theo râu khung quét, để sẵn cho chế độ SL thứ 1
   int       ltfBarsLeft;      // còn bao nhiêu nến khung nhỏ nữa thì bỏ setup
   datetime  ltfLastBar;       // mốc nến khung nhỏ đã xử lý gần nhất
   string    ltfSetupName;     // tên nhánh sinh ra setup, để ghi log/tin cho đúng
   STPConfig ltfCfg;           // bộ TP của chính nhánh đó

   string   lastEventMsg;
};


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
bool SetupEnabled_21c(SCRTSource &s) { return s.isSwing ? Inp_On_21c_SW : Inp_On_21c_LK; }
bool SetupEnabled_21d(SCRTSource &s) { return s.isSwing ? Inp_On_21d_SW : Inp_On_21d_LK; }
bool SetupEnabled_22(SCRTSource &s)  { return s.isSwing ? Inp_On_22_SW  : Inp_On_22_LK;  }


SCRTSource  g_srcAdj;   // nguồn H4 liền kề — biên = High/Low nến H4 vừa đóng
SCRTSource  g_srcLM;    // nguồn H4 Swing  — biên = Last Major High/Low (cụm nến H4, Major Swing)
CSMC_Engine g_htfEngine; // chạy trên Inp_HTF, chỉ dùng để lấy current_maj_last_high/low

// --- Vào lệnh (BOS/CHOCH) ---
CTrade         g_trade;
CTelegramRadar g_radar;
double      g_startBalance      = 0;
bool        g_halted            = false;

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

   g_srcAdj.tag = "LiềnKề"; g_srcAdj.isSwing = false; g_srcAdj.magic = Inp_MagicNumber;
   g_srcLM.tag  = "Swing";  g_srcLM.isSwing  = true;  g_srcLM.magic  = Inp_MagicNumber + 1;
   ResetSourceFull(g_srcAdj);
   ResetSourceFull(g_srcLM);

   // --- Vào lệnh ---
   g_trade.SetDeviationInPoints(SLIPPAGE_POINTS);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_startBalance      = AccountInfoDouble(ACCOUNT_BALANCE);
   g_halted            = false;

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

      // [v1.73] Tin khởi động có HAI bản. Bản đầy đủ mang Balance + toàn bộ cấu hình nên
      // chỉ gửi khi kênh là nội bộ; nhưng KHÔNG gửi gì cả thì chủ bot mất luôn cách xác
      // nhận bot đã nối đúng channel — đúng vấn đề gặp phải ngay sau 1.72. Nên kênh công
      // khai vẫn nhận một tin tối giản: đủ để biết bot sống và đang nối đúng chỗ, không
      // có số dư, không có cấu hình chiến lược.
      // Init() PHẢI nằm ngoài mọi cổng này, nếu không tắt tin khởi động là tắt luôn mọi
      // tin sau đó.
      if(!TinVanHanhDuocPhep())
      {
         g_radar.SendMessage(StringFormat(
            "🟢 <b>KÊNH TÍN HIỆU ĐÃ SẴN SÀNG</b>\n━━━━━━━━━━━━━━━\n"
            "📊 <b>Cặp:</b> %s\n"
            "🕐 <b>Khung:</b> %s\n"
            "🕒 %s (giờ VN)",
            _Symbol,
            TFToString(Inp_HTF) + " · " + TFToString(Inp_LTF),
            GioVietNam()));
      }
      else
      g_radar.SendMessage(StringFormat(
         "🟢 <b>CRT BOT KHỞI ĐỘNG</b>\n━━━━━━━━━━━━━━━\n"
         "⚙️ <b>Chế độ:</b> %s\n"
         "🎯 <b>Xác nhận vào lệnh:</b> %s\n"
         "📊 <b>Nguồn biên:</b> %s\n"
         "🕐 <b>Khung:</b> %s\n"
         "💰 <b>Balance:</b> %s$",
         Inp_EnableTrading ? "VÀO LỆNH" : "CHỈ THEO DÕI (không trade)",
         "Nến quét " + TFToString(Inp_LTF) + " (pinbar / engulfing)",
         EntrySourceText(),
         TFToString(Inp_HTF) + " · " + TFToString(Inp_LTF),
         DoubleToString(g_startBalance, 2)));
   }

   // [v1.75] Engine BOS/CHOCH khung entry đã gỡ hẳn cùng Mode 1 — bot chỉ còn dùng
   // g_htfEngine cho Last Major Swing.
   if(LastMajorEnabled())
      g_htfEngine.Init(_Symbol, Inp_HTF, g_htfEnginePrefix, true, false, false,
           clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
           Inp_HTF_SwingMajor, Inp_HTF_SwingMinor, 5, 8, 8, false);

   RefreshAll(true);
   return(INIT_SUCCEEDED);
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
   s.ltfWaiting = false; s.ltfDir = 0; s.ltfBarsLeft = 0; s.ltfLastBar = 0; s.ltfSetupName = "";

   s.m2Waiting = false; s.m2WaitKind = 0; s.m2Dir = 0;
   s.m2OriginHigh = 0; s.m2OriginLow = 0; s.m2OriginBodyEdge = 0; s.m2OriginTime = 0;
   s.m2OriginOpen = 0; s.m2OriginClose = 0;
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
   s.ltfWaiting       = false;   // [v1.81] biên đổi -> setup đang chờ khung nhỏ mất căn cứ

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
   // [v1.63] Huỷ cả 2 phía nên KHÔNG nêu chiều lệnh trong tin (dir = 0).
   if(CancelEAPendings(s.magic) > 0)
      NotifySignalClosed(0, "khung " + TFToString(Inp_HTF) + " sang biên mới, tín hiệu cũ hết hạn");
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   HT_Ketthuc();                       // [1.68] ghi nốt lệnh còn mở rồi đóng file CSV
   ObjectsDeleteAll(0, g_prefix);      // line, label, arrow, dashboard
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

   // [1.68] Ghi hành trình lệnh (chỉ khi bật + chạy trong tester). Để ngoài khối bảo vệ
   // bên dưới để vẫn ghi được cả khi Shield/halt đang chặn vào lệnh mới.
   HT_CapNhat();

   // Huỷ lệnh chờ khi giá chạm mốc đã chọn (Middle hoặc biên đối diện) — CẢ 2 MODE.
   // Để ngoài khối bảo vệ bên dưới vì huỷ lệnh chờ luôn là hành động an toàn, cần
   // chạy được cả khi Shield/halt đang chặn vào lệnh mới.
   CancelPendingsAtTarget(g_srcAdj);
   CancelPendingsAtTarget(g_srcLM);

   // Giá chạm biên đối diện -> kéo SL về entry, lệnh chỉ còn được gồng lãi.
   // Cũng để ngoài khối bảo vệ: siết SL luôn an toàn, phải chạy cả khi Shield/halt bật.
   MoveSLToEntryAtOppositeBound(g_srcAdj);
   MoveSLToEntryAtOppositeBound(g_srcLM);

   // Hoà vốn theo KHOẢNG LÃI — cùng lý do đặt ngoài khối bảo vệ: siết SL luôn an toàn,
   // phải chạy được cả khi Shield/halt đang chặn vào lệnh mới.
   MoveSLToEntryAtProfitPips(g_srcAdj);
   MoveSLToEntryAtProfitPips(g_srcLM);

   // [v1.81] Chờ nến vào lệnh trên khung nhỏ. Đặt cùng chỗ với các luật quản lý lệnh —
   // tức NGOÀI khối Inp_EnableTrading bên dưới — vì bản thân hàm đã tự kiểm đủ chốt an
   // toàn (giống ExecutePairEntry), và chế độ CHỈ THEO DÕI vẫn cần nó chạy để phát tín
   // hiệu đúng thời điểm khung nhỏ xác nhận.
   if(Inp_EntryLTF_Enable)
   {
      ProcessLTFEntry(g_srcAdj);
      ProcessLTFEntry(g_srcLM);
   }

   if(Inp_EnableTrading)
   {
      ManageShield();
      CheckAccountStop();
      CheckPoolSL();
      TrackProfitRounds(g_srcAdj);
      TrackProfitRounds(g_srcLM);

      // [v1.75] Khối chạy engine BOS/CHOCH khung entry đã gỡ hẳn cùng Mode 1.
      // Mode nến quét vào lệnh ngay trong ProcessLTFSweep(), không dùng arm/disarm,
      // không cần engine thứ hai.
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
// [v1.63] Nội dung nhãn cạnh đường biên, theo Inp_ShowLineName.
//   · TẮT (mặc định): CHỈ GIÁ — "4680.98". Không kèm tên đường, cũng không kèm chữ
//     "· đã dùng": trạng thái đã xét xong vẫn đọc được qua màu xám của chính đường kẻ
//     (v1.59). Thêm chữ vào đây là phá đúng thứ người dùng muốn gọn.
//   · BẬT: tên đầy đủ + giá + hậu tố "· đã dùng" như bản 1.62 — "H4 High: 4680.98  · đã dùng".
// Tên đường truyền vào là chuỗi đã dựng sẵn (tfName + "High"/"Low", hoặc "Last Major High")
// nên hàm này không cần biết nguồn nào.
//+------------------------------------------------------------------+
string PriceTag(string tenDuong, double gia, bool used)
{
   string giaTxt = DoubleToString(gia, _Digits);
   if(!Inp_ShowLineName)
      return giaTxt;
   return LineLabel(tenDuong + ": " + giaTxt, used);
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
   // [v1.63] Ở chế độ nhãn gọn (Inp_ShowLineName = false) nhãn chỉ còn con giá, nên khoảng
   // chừa phải co lại theo — giữ nguyên số cũ thì line vẫn bị cắt cụt sớm y như khi có tên.
   if(Inp_ShowLabel || Inp_ShowLastMajorLabel)
   {
      int maxLen = Inp_ShowLineName ? (18 + _Digits + 5 + 11) : (_Digits + 6);
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
                         PriceTag(tfName + " High", g_htfHigh, usedHi),
                         LineColor(Inp_ColorHigh, usedHi));
         DrawLevelLabel(g_nameLowLabel, labelTime, g_htfLow,
                         PriceTag(tfName + " Low", g_htfLow, usedLo),
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
                         PriceTag("Last Major High", g_srcLM.boundHigh, lmUsedHi),
                         LineColor(Inp_ColorLastMajorHigh, lmUsedHi));
         DrawLevelLabel(g_nameLastMajorLowLabel, labelTime, g_srcLM.boundLow,
                         PriceTag("Last Major Low", g_srcLM.boundLow, lmUsedLo),
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

   // [1.66] Luật thư viện — thay TOÀN BỘ phép đo bên dưới, kể cả đường miễn lọc của nến
   // thuận chiều. Vị trí nến (đã quét qua biên, đóng lại trong biên) vẫn do bot kiểm ở
   // ClassifyOriginCandle; thư viện chỉ xét hình dạng.
   if(Inp_Lib_Pinbar)
   {
      SCandle k; k.o = o; k.h = h; k.l = l; k.c = c;
      return SC_IsPinbar(dir, k);
   }

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
   if(Inp_Lib_Pinbar)
   {
      double rangeL = h - l;
      double topL   = MathMax(o, c);
      double botL   = MathMin(o, c);
      double noseL  = isBuy ? (botL - l) : (h - topL);
      double oppL   = isBuy ? (h - topL) : (botL - l);
      return StringFormat("pinbar thư viện (râu mũi %s = %.0f%% biên độ, râu đối diện %.0f%%)",
                          DoubleToString(noseL, _Digits),
                          rangeL > 0 ? noseL / rangeL * 100.0 : 0.0,
                          rangeL > 0 ? oppL  / rangeL * 100.0 : 0.0);
   }
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
      // [v1.80] Cùng lý do với nhánh 2.1b/2.1c: 2.2 là nhánh chờ DUY NHẤT của đường này,
      // tắt nó thì bỏ setup ngay, đừng vào trạng thái chờ rồi đốt biên ở cây 2.
      if(!SetupEnabled_22(s))
      {
         PrintFormat("[CRT][%s] Nến gốc %s @%s đóng NGOÀI biên nhưng 2.2 đang TẮT -> bỏ setup ngay, biên vẫn còn hiệu lực.",
                     s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
         return;
      }

      // 2.2 — đóng NGOÀI biên: ghi nhận nến gốc, chờ đúng 1 cây engulfing kế tiếp.
      s.m2Waiting    = true;
      s.m2WaitKind   = 1;
      s.m2Dir        = dir;
      s.m2OriginHigh  = highC;
      s.m2OriginLow   = lowC;
      s.m2OriginOpen  = openC;
      s.m2OriginClose = closeC;
      s.m2OriginTime  = tC;
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
      //
      // [v1.80] VÁ BẤT ĐỐI XỨNG: nếu CẢ HAI nhánh chờ (2.1b, 2.1c) đều đang tắt thì bỏ
      // setup NGAY TẠI ĐÂY, không vào trạng thái chờ và KHÔNG đụng vào biên.
      // Trước đây bot vẫn chờ, và lúc chốt sổ ở cây 2 thì đốt biên TRƯỚC khi xét — chỉ
      // hoàn lại biên ở đúng nhánh "setup đang tắt nhưng cây 2 ĐỦ điều kiện". Hệ quả:
      // cây 2 TRƯỢT thì một nhánh đang tắt vẫn tiêu thụ được đường biên, cướp cơ hội của
      // các nhánh còn bật — đúng thứ mà luật "tắt nhánh thì không đốt biên" sinh ra để
      // ngăn, và làm hỏng việc so sánh hai lần backtest bật/tắt.
      if(!SetupEnabled_21b(s) && !SetupEnabled_21c(s))
      {
         PrintFormat("[CRT][%s] 2.1 nến gốc %s @%s không đạt, mà CẢ 2.1b lẫn 2.1c đều đang TẮT -> bỏ setup ngay, biên vẫn còn hiệu lực.",
                     s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
         return;
      }

      s.m2Waiting        = true;
      s.m2WaitKind       = 2;
      s.m2Dir            = dir;
      s.m2OriginHigh     = highC;
      s.m2OriginLow      = lowC;
      s.m2OriginOpen     = openC;
      s.m2OriginClose    = closeC;
      s.m2OriginBodyEdge = bodyEdge;   // giữ lại để tính mốc 50% theo râu quét THẬT
      s.m2OriginTime     = tC;
      string lyDo = Inp_Lib_Pinbar
         ? "không đạt hình pinbar thư viện"
         : StringFormat("nến ngược chiều, râu %s < %.1f x thân %s = %s",
                        DoubleToString(isBuy ? (bodyEdge - lowC) : (highC - bodyEdge), _Digits),
                        Inp_WickBodyRatio,
                        DoubleToString(MathAbs(closeC - openC), _Digits),
                        DoubleToString(MathAbs(closeC - openC) * Inp_WickBodyRatio, _Digits));
      PrintFormat("[CRT][%s] 2.1 nến gốc %s @%s bị loại (%s) -> chờ 1 cây %s kế tiếp.",
                  s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                  lyDo, TFToString(Inp_LTF));
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
   VaoLenhHoacChoKhungNho(s, dir, limitPrice, "2.1 pinbar", cfg21);
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

      // [v1.83] Giữ mút râu SÂU NHẤT của các cây TRƯỚC cây này — cây thứ 3 phải quét
      // vượt qua mốc đó mới được công nhận, nên phải đọc trước khi cập nhật bên dưới.
      double extTruoc = isBuy ? s.sweepLowExtreme : s.sweepHighExtreme;

      // Cây này có thể thọc sâu hơn cây trước -> cập nhật mút râu để SL đặt đúng chỗ.
      if(isBuy  && lowC  < s.sweepLowExtreme)  s.sweepLowExtreme  = lowC;
      if(!isBuy && highC > s.sweepHighExtreme) s.sweepHighExtreme = highC;

      bool closedIn = isBuy ? (closeC > lo) : (closeC < hi);   // điều kiện CẦN cho cả 2 nhánh

      // [v1.83] CỬA SỔ TỐI ĐA 3 CÂY, chỉ cho họ 2.1 (a/b/c).
      // Cây 1 hỏng -> xét cây 2 (như cũ). Cây 2 hỏng mà giá VẪN đóng trong biên -> cho
      // thêm ĐÚNG cây thứ 3; cây 3 đạt thì setup được công nhận, không đạt thì đốt biên.
      // Hết cây 3 là chốt sổ, KHÔNG có lượt thứ tư.
      // Nhánh 2.2 giữ nguyên 2 cây: nến gốc của nó đã đóng NGOÀI biên, tức biên bị phá
      // ngay từ đầu nên không có cửa gia hạn.
      // Biên bị đốt ở đây khi: đang là 2.2 (kind 1), hoặc cây vừa rồi đóng NGOÀI biên,
      // hoặc đây đã là cây thứ 3 (kind 4). Các trường hợp còn lại để dành cho cây 3.
      bool laCay3 = (s.m2WaitKind == 4);
      if(s.m2WaitKind == 1 || !closedIn || laCay3)
         SetLineUsed(s, s.m2Dir, true);

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
            SetLineUsed(s, s.m2Dir, true);   // [v1.82] vao lenh that -> bien het hieu luc
            ConfirmSweepForMode2(s, s.m2Dir, tC);
            STPConfig cfg21b = TPCfg_Pinbar(s);
            VaoLenhHoacChoKhungNho(s, s.m2Dir, limitPrice, "2.1b pinbar cây 2", cfg21b);
         }
         // [v1.80] NHÁNH 2.1c — cây 2 không phải pinbar nhưng TRÙM cây gốc.
         // Trước 1.80 mẫu này rơi vào khoảng trống: cây gốc đóng TRONG biên nên bot khoá
         // vào đường 2.1b và chỉ đo cây 2 bằng thước pinbar; mà engulfing mạnh thì thân
         // to, râu mũi không thể đạt >= 60% biên độ -> luôn trượt. Nhánh 2.2 lại chỉ kích
         // khi cây gốc đóng NGOÀI biên. Kết quả: "quét line, đóng lại trong biên, cây sau
         // trùm ngược" không nhánh nào phủ.
         // Dùng CHUNG hàm engulfing với 2.2.1 và CHUNG mốc vào lệnh (50% biên độ cây 2):
         // ở cả hai nhánh, cây 2 mới là cây quyết định chứ không phải cây gốc.
         if(closedIn)
         {
            SCandle gocC;  gocC.o = s.m2OriginOpen; gocC.h = s.m2OriginHigh;
                           gocC.l = s.m2OriginLow;  gocC.c = s.m2OriginClose;
            SCandle cay2C; cay2C.o = openC; cay2C.h = highC; cay2C.l = lowC; cay2C.c = closeC;
            bool trumGoc = Inp_Lib_Engulfing
                              ? SC_IsEngulfing(s.m2Dir, gocC, cay2C)
                              : (isBuy ? (closeC >= s.m2OriginHigh) : (closeC <= s.m2OriginLow));
            if(trumGoc)
            {
               if(!SetupEnabled_21c(s))
               {
                  SetLineUsed(s, s.m2Dir, false);   // setup tắt -> coi như chưa dùng biên
                  PrintFormat("[CRT][%s] 2.1c ENGULFING (cây 2) %s @%s -> setup ĐANG TẮT, bỏ qua (biên vẫn còn hiệu lực).",
                              s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES));
                  return;
               }
               double limitPrice = (highC + lowC) / 2.0;
               PrintFormat("[CRT][%s] 2.1c ENGULFING (cây 2) %s @%s · gốc đóng TRONG biên nhưng không đạt pinbar, cây 2 trùm gốc -> vào cặp lệnh (limit @50%% biên độ cây 2 = %s)",
                           s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                           DoubleToString(limitPrice, _Digits));
               SetLineUsed(s, s.m2Dir, true);   // [v1.82] vao lenh that -> bien het hieu luc
               ConfirmSweepForMode2(s, s.m2Dir, tC);
               STPConfig cfg21c = TPCfg_Engulfing(s);
               VaoLenhHoacChoKhungNho(s, s.m2Dir, limitPrice, "2.1c engulfing cây 2", cfg21c);
               return;
            }
         }

         // [v1.83] Cây 2 hỏng. Nếu giá VẪN đóng trong biên thì biên chưa bị phá -> gia hạn
         // ĐÚNG MỘT cây nữa (cây thứ 3). Đóng ngoài biên thì thôi, biên đã bị phá.
         // [v1.85] 2.1d TẮT thì KHÔNG gia hạn — đốt biên ngay tại cây 2 như hành vi cũ.
         // Cùng nguyên tắc với v1.80: một nhánh đang tắt không được phép giữ đường biên
         // ở trạng thái lửng lơ rồi tiêu thụ nó, vì như vậy hai lần backtest bật/tắt
         // không còn so sánh được với nhau.
         if(closedIn && !SetupEnabled_21d(s))
         {
            SetLineUsed(s, s.m2Dir, true);
            PrintFormat("[CRT][%s] Cây 2 không đạt và 2.1d đang TẮT -> không gia hạn cây 3, biên %s coi như đã dùng.",
                        s.tag, TFToString(Inp_HTF));
            return;
         }

         if(closedIn)
         {
            s.m2Waiting  = true;
            s.m2WaitKind = 4;
            // Cây 3 sẽ so với CÂY 2, nên cây 2 lên làm mốc. Ghi đè m2Origin* là an toàn:
            // nến gốc chỉ còn cần cho 2.1b/2.1c, mà hai nhánh đó vừa ngã ngũ xong.
            s.m2OriginHigh  = highC;
            s.m2OriginLow   = lowC;
            s.m2OriginOpen  = openC;
            s.m2OriginClose = closeC;
            s.m2OriginTime  = tC;
            PrintFormat("[CRT][%s] Cây 2 không đạt (%s) nhưng vẫn đóng TRONG biên -> gia hạn cây thứ 3 (phải TRÙM cây 2 và quét sâu hơn %s).",
                        s.tag,
                        Inp_Lib_Pinbar
                           ? "không đạt pinbar thư viện, cũng không trùm nến gốc"
                           : StringFormat("ngược chiều và râu < %.1f x thân, cũng không trùm nến gốc", Inp_WickBodyRatio),
                        DoubleToString(isBuy ? s.sweepLowExtreme : s.sweepHighExtreme, _Digits));
         }
         else
            PrintFormat("[CRT][%s] 2.1b/2.1c KHÔNG ĐỦ ĐK (cây 2 đóng NGOÀI biên -> biên coi như bị phá) -> bỏ setup, biên %s hết hiệu lực.",
                        s.tag, TFToString(Inp_HTF));
         return;
      }

      //=== Kind 4: CÂY THỨ BA — cửa cuối của họ 2.1 ===
      // Điều kiện ĐỦ, phải có cả hai: TRÙM cây 2, và RÂU QUÉT SÂU HƠN mọi cây trước đó.
      // Vế "sâu hơn" là điểm mấu chốt: trùm mà không lấy thêm thanh khoản mới thì chỉ là
      // dao động trong cùng vùng, không phải một cú quét thật.
      if(s.m2WaitKind == 4)
      {
         bool sauHon = isBuy ? (lowC < extTruoc) : (highC > extTruoc);

         SCandle cay2; cay2.o = s.m2OriginOpen; cay2.h = s.m2OriginHigh;
                       cay2.l = s.m2OriginLow;  cay2.c = s.m2OriginClose;
         SCandle cay3; cay3.o = openC; cay3.h = highC; cay3.l = lowC; cay3.c = closeC;
         bool trumCay2 = Inp_Lib_Engulfing
                            ? SC_IsEngulfing(s.m2Dir, cay2, cay3)
                            : (isBuy ? (closeC >= s.m2OriginHigh) : (closeC <= s.m2OriginLow));

         if(closedIn && sauHon && trumCay2)
         {
            SetLineUsed(s, s.m2Dir, true);
            double limitPrice = (highC + lowC) / 2.0;
            PrintFormat("[CRT][%s] 2.1d ENGULFING (cây 3) %s @%s · trùm cây 2 VÀ quét sâu hơn (%s < %s) -> vào lệnh (mốc 50%% biên độ cây 3 = %s)",
                        s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                        DoubleToString(isBuy ? lowC : highC, _Digits),
                        DoubleToString(extTruoc, _Digits),
                        DoubleToString(limitPrice, _Digits));
            ConfirmSweepForMode2(s, s.m2Dir, tC);
            STPConfig cfg21d = TPCfg_Engulfing(s);
            VaoLenhHoacChoKhungNho(s, s.m2Dir, limitPrice, "2.1d engulfing cây 3", cfg21d);
            return;
         }

         PrintFormat("[CRT][%s] Cây 3 KHÔNG ĐỦ ĐK (%s) -> hết cửa sổ 3 cây, biên %s coi như đã dùng.",
                     s.tag,
                     !closedIn ? "đóng ngoài biên"
                               : (!sauHon ? StringFormat("không quét sâu hơn %s", DoubleToString(extTruoc, _Digits))
                                          : "không trùm cây 2"),
                     TFToString(Inp_HTF));
         return;
      }

      // --- Nhánh 2.2: nến gốc đóng ngoài biên, chờ cây engulfing đảo chiều.
      // [1.66] Bật Inp_Lib_Engulfing thì điều kiện ĐỦ lấy theo thư viện: cây 2 phải trùm
      // cả High lẫn Low nến gốc VÀ đóng vượt ra ngoài biên nến gốc. Luật cũ chỉ đòi vế sau.
      bool engulfed;
      if(Inp_Lib_Engulfing)
      {
         SCandle goc; goc.o = s.m2OriginOpen; goc.h = s.m2OriginHigh;
                      goc.l = s.m2OriginLow;  goc.c = s.m2OriginClose;
         SCandle cay2; cay2.o = openC; cay2.h = highC; cay2.l = lowC; cay2.c = closeC;
         engulfed = SC_IsEngulfing(s.m2Dir, goc, cay2);
      }
      else
         engulfed = isBuy ? (closeC >= s.m2OriginHigh)
                          : (closeC <= s.m2OriginLow);           // điều kiện ĐỦ
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
         PrintFormat("[CRT][%s] 2.2.1 ENGULFING %s @%s · %s · close %s %s High/Low gốc %s -> vào cặp lệnh (limit @50%% thân = %s)",
                     s.tag, isBuy ? "BUY" : "SELL", TimeToString(tC, TIME_DATE|TIME_MINUTES),
                     Inp_Lib_Engulfing ? "luật thư viện (trùm H/L + đóng vượt)" : "luật cũ (chỉ đòi đóng vượt)",
                     DoubleToString(closeC, _Digits), isBuy ? ">=" : "<=",
                     DoubleToString(isBuy ? s.m2OriginHigh : s.m2OriginLow, _Digits),
                     DoubleToString(limitPrice, _Digits));
         ConfirmSweepForMode2(s, s.m2Dir, tC);
         STPConfig cfg22 = TPCfg_Engulfing(s);
         VaoLenhHoacChoKhungNho(s, s.m2Dir, limitPrice, "2.2.1 engulfing", cfg22);
      }
      else
      {
         PrintFormat("[CRT][%s] 2.2.2 KHÔNG ĐỦ ĐK (%s) -> bỏ setup, biên %s coi như đã dùng.",
                     s.tag,
                     !closedIn ? "cây thứ 2 vẫn đóng ngoài biên"
                               : (Inp_Lib_Engulfing ? "chưa trùm H/L nến gốc hoặc đóng chưa vượt"
                                                    : "đóng chưa vượt mốc nến gốc"),
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

   // [v1.83] Cơ chế "nhiều lượt thử, mỗi lượt phải sâu hơn" của v1.82 đã GỠ BỎ. Thay bằng
   // cửa sổ CỐ ĐỊNH 3 CÂY (xem nhánh chờ ở trên): hết cây 3 là đốt biên, không có lượt
   // thứ tư. Luật "phải quét sâu hơn" nay nằm ở điều kiện của chính cây 3.

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
   // [v1.75] Chi con MOT duong: mode nen quet. Nhanh BOS/CHOCH da go han o 1.75.
   ProcessSweepCandleMode(s, highC, lowC, closeC, tC, s.boundLow, s.boundHigh);
}

//+------------------------------------------------------------------+
// [v1.63] Giờ VIỆT NAM cho mọi tin Telegram.
// KHÔNG dùng TimeCurrent(): đó là giờ SERVER của sàn — Exness chạy GMT+2 và tự nhảy sang
// GMT+3 mùa hè, người đọc kênh phải tự nhẩm bù, còn nhẩm sai vào 2 lần chuyển mùa.
// KHÔNG dùng TimeLocal(): giờ đó theo múi giờ cài trên VPS, đổi VPS là lệch mà không ai
// biết. TimeGMT() + 7 là mốc duy nhất luôn đúng — Việt Nam không có giờ mùa hè nên số 7
// cố định quanh năm.
// Khai báo hằng số ngay tại đây (cùng lối với Inp_WickBodyRatio) thay vì thêm vào màn
// hình Input: đây không phải tham số vận hành, chẳng ai đổi múi giờ của một kênh.
//+------------------------------------------------------------------+
const int VN_GMT_OFFSET_HOURS = 7;

string GioVietNam()
{
   return TimeToString(TimeGMT() + VN_GMT_OFFSET_HOURS * 3600, TIME_DATE|TIME_MINUTES);
}

//+------------------------------------------------------------------+
// [v1.64] DỌN ẢNH CHỤP TRƯỚC KHI GỬI LÊN KÊNH PUBLIC.
// Hai thứ trong ảnh không nên để người lạ thấy:
//   1. Tên EA + icon terminal vẽ ở GÓC PHẢI TRÊN -> lộ luôn tên/chiến lược của bot.
//   2. Đường lệnh (trade levels) ở mép trái -> in rõ "BUY 0.1 at 4614.00", tức lộ KHỐI
//      LƯỢNG và giá vào thật. Đã cất công bỏ dòng "Khối lượng" khỏi tin, mà ảnh vẫn in
//      thì bằng thừa.
//
// Mục 2 tắt bằng CHART_SHOW_TRADE_LEVELS, có sẵn trong API.
// Mục 1 KHÔNG có chart property nào tắt được — nhãn đó do terminal vẽ, không phải object
// của bot. Cách duy nhất là ĐÈ một OBJ_RECTANGLE_LABEL màu nền lên. Đã kiểm chứng bằng
// script Test_CheNhanEA ngày 27/08: object vẽ ĐÈ LÊN được nhãn EA (chụp thử với tấm che
// đỏ, nhãn "TLS_SMC_CSV_BOT_QUY" biến mất hoàn toàn).
//
// CẠM BẪY TOẠ ĐỘ — mất một lần test mới ra: OBJ_RECTANGLE_LABEL neo bằng góc trên-TRÁI
// CỦA CHÍNH NÓ. Với CORNER_RIGHT_UPPER thì XDISTANCE là khoảng cách từ mép phải đo NGƯỢC
// VÀO TRONG tới cái góc trái đó. Đặt XDISTANCE = 0 là tấm che nằm gọn NGOÀI màn hình,
// chụp ra chẳng thấy gì. Phải đặt XDISTANCE = ĐÚNG BỀ RỘNG của nó.
//
// Kích thước để vừa đủ ôm chữ, đừng nới thêm: tấm che xoá thật vùng chart nằm dưới nó,
// nới rộng quá là ăn mất nhãn giá của đường biên nếu đường đó nằm gần đỉnh chart.
// "CRT_MultiTF_EA" + icon đo được ~120px, lấy 190x24 là thoải mái.
//+------------------------------------------------------------------+
const int CHE_X = 0;     // chừa thêm so với mép phải vùng vẽ (0 = sát mép)
const int CHE_Y = 0;
const int CHE_W = 190;
const int CHE_H = 24;

string CheTenEA_Name() { return g_prefix + "CheTenEA"; }

void VeTamCheTenEA()
{
   string n = CheTenEA_Name();
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   color mauNen = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   ObjectSetInteger(0, n, OBJPROP_CORNER,      CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   CHE_X + CHE_W);   // xem cạm bẫy toạ độ ở trên
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   CHE_Y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       CHE_W);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       CHE_H);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     mauNen);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       mauNen);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_BACK,        false);  // phải vẽ ĐÈ LÊN, không chui xuống nền
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      1000);
}

//+------------------------------------------------------------------+
// [v1.64] Gửi tin KÈM ẢNH qua bộ lọc dọn dẹp trên. Dựng tạm — chụp — trả lại nguyên
// trạng, nên chart của người dùng không bị đổi gì lâu dài.
// CỐ Ý làm ở đây chứ KHÔNG sửa Telegram_Radar.mqh: file đó là bản dùng chung byte-identical
// với BOT_TLS và BOT_OB_Radar, đụng vào là phải mirror sang cả 3 bot.
//+------------------------------------------------------------------+
void SendPhotoSach(string msg)
{
   // Tắt gửi ảnh -> SendMessageWithPhoto tự lùi về gửi text, dọn dẹp làm gì cho phí.
   bool canDon = Inp_SendScreenshot && (Inp_TG_CheTenEA || Inp_TG_AnMucLenh);
   if(!canDon)
   {
      g_radar.SendMessageWithPhoto(msg);
      return;
   }

   bool tradeLevelsCu = (bool)ChartGetInteger(0, CHART_SHOW_TRADE_LEVELS);
   bool gridCu        = (bool)ChartGetInteger(0, CHART_SHOW_GRID);

   if(Inp_TG_AnMucLenh)
      ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, false);

   if(Inp_TG_CheTenEA)
   {
      // [v1.64] Tấm che XOÁ THẬT vùng chart nằm dưới nó. Nếu lưới đang bật, đường lưới đi
      // qua góc phải trên sẽ bị ĐỨT một đoạn — trên nền trắng nhìn ra ngay, mà đứt lưới
      // còn đáng ngờ hơn cả cái tên EA định giấu. Tắt lưới trong lúc chụp thì ảnh ra là
      // một chart không lưới, hoàn toàn bình thường, không ai thấy có gì bị che.
      // KHÔNG làm thành input riêng: bật che mà để lưới đứt thì việc che thành công cốc,
      // đây không phải lựa chọn để cân nhắc.
      ChartSetInteger(0, CHART_SHOW_GRID, false);
      VeTamCheTenEA();
   }

   ChartRedraw(0);
   Sleep(300);          // chờ terminal vẽ xong hẳn rồi mới để bên trong chụp

   g_radar.SendMessageWithPhoto(msg);

   // Trả lại nguyên trạng dù ảnh có gửi được hay không.
   ObjectDelete(0, CheTenEA_Name());
   if(Inp_TG_CheTenEA)
      ChartSetInteger(0, CHART_SHOW_GRID, gridCu);
   if(Inp_TG_AnMucLenh)
      ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, tradeLevelsCu);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
// [v1.65] TIN CHI TIẾT — phụ lục nội bộ, đi kèm ngay sau tin public.
// NGUYÊN TẮC: CHỈ chứa thứ tin public KHÔNG có. Tuyệt đối không lặp lại chiều lệnh, giá
// entry, SL, TP — lặp là chủ bot nhìn 2 tin có giá lại tưởng bot vào 2 kèo khác nhau.
// Còn lại đúng 3 thứ: nhánh setup, khối lượng, Balance.
// Mở đầu bằng "⚙️ chi tiết nội bộ" để nhìn phát biết ngay đây không phải tín hiệu, tránh
// forward nhầm sang group member.
//+------------------------------------------------------------------+
// [v1.72] Tin VẬN HÀNH = mọi tin mang số liệu TÀI KHOẢN (balance, equity, P&L nhóm) hoặc
// cấu hình nội bộ: tin khởi động, Account SL, Auto Pass, DD ngày, Lãi ngày, Pool SL.
// Chúng KHÔNG phải tín hiệu, member không cần, và để lọt lên channel công khai là lộ
// thẳng số dư tài khoản. Dùng chung công tắc với tin chi tiết: Inp_TG_TinChiTiet vốn
// mang nghĩa "kênh này là của tôi, gửi thông tin nội bộ được".
// LƯU Ý ĐÁNH ĐỔI: tắt công tắc này thì chủ bot KHÔNG còn nhận cảnh báo Shield qua
// Telegram nữa — vẫn còn trong log terminal. Muốn có cả hai thì phải tách chat ID riêng
// cho tin nội bộ, chưa làm.
//+------------------------------------------------------------------+
bool TinVanHanhDuocPhep()
{
   return (Inp_EnableTelegram && Inp_TG_TinChiTiet);
}

//+------------------------------------------------------------------+
void SendChiTiet(string body)
{
   if(!Inp_EnableTelegram || !Inp_TG_TinChiTiet)
      return;
   g_radar.SendMessage("⚙️ <i>chi tiết nội bộ</i>\n" + body);
}

//+------------------------------------------------------------------+
// [v1.63] TIN PUBLIC — bản tin chia sẻ cho cộng đồng.
// Cố ý CHỈ có 4 dòng: chiều lệnh, vùng entry, SL, TP. Không Nguồn / Biên H4 / Râu quét /
// khối lượng / Balance — người đọc kênh không cần biết bot chạy nguồn nào, còn số dư tài
// khoản thì tuyệt đối không được lên kênh công khai.
//
// eA, eB = giá 2 lệnh của cặp (market + limit 50%). hasB = false khi chỉ vào được 1 lệnh.
// Bên gọi phải truyền giá của những lệnh ĐÃ ĐẶT THÀNH CÔNG — xem ExecutePairEntry().
//
// Vùng entry làm tròn về số nguyên (4679 – 4681) cho dễ đọc; SL giữ 2 số lẻ vì đó là mốc
// người đọc phải đặt chính xác. Khoảng pip tính từ SL tới TỪNG giá entry: lệnh limit nằm
// gần SL hơn nên ra số nhỏ, lệnh market ra số lớn -> "khoảng 47 – 65 pips".
//+------------------------------------------------------------------+
void SendPublicSignal(int dir, double eA, double eB, bool hasB, double sl, bool kemChart)
{
   if(!Inp_EnableTelegram || !Inp_TG_TinPublic)
      return;

   bool   isBuy = (dir > 0);
   double pip   = GetPipSize();

   int rA = (int)MathRound(eA);
   int rB = hasB ? (int)MathRound(eB) : rA;
   int rLo = (rA < rB) ? rA : rB;
   int rHi = (rA < rB) ? rB : rA;

   int pA = (int)MathRound(MathAbs(eA - sl) / pip);
   int pB = hasB ? (int)MathRound(MathAbs(eB - sl) / pip) : pA;
   int pLo = (pA < pB) ? pA : pB;
   int pHi = (pA < pB) ? pB : pA;

   // Cặp lệnh có thể làm tròn ra CÙNG một số nguyên (market 4679.17 / limit 4679.42) —
   // lúc đó in "vùng 4679 – 4679" là vô nghĩa, rút về một giá.
   string dongEntry = (rLo == rHi)
      ? StringFormat("📍 <b>Entry:</b> %d", rLo)
      : StringFormat("📍 <b>Entry vùng:</b> %d – %d", rLo, rHi);

   string dongSL = (pLo == pHi)
      ? StringFormat("🛡️ <b>SL tham khảo:</b> %s (khoảng %d pips)", DoubleToString(sl, 2), pLo)
      : StringFormat("🛡️ <b>SL tham khảo:</b> %s (khoảng %d – %d pips)", DoubleToString(sl, 2), pLo, pHi);

   string msg = StringFormat(
      "%s <b>TÍN HIỆU %s — %s</b>\n━━━━━━━━━━━━━━━\n"
      "%s\n"
      "%s\n"
      "🎯 <b>TP:</b> %s\n"
      "🕒 %s (giờ VN)\n"
      "━━━━━━━━━━━━━━━\n"
      "⚠️ <i>Tín hiệu chia sẻ mang tính tham khảo, không phải lời khuyên đầu tư. "
      "Anh em tự quản lý vốn và rủi ro của mình.</i>",
      isBuy ? "🟩" : "🟥",
      isBuy ? "MUA" : "BÁN",
      _Symbol,
      dongEntry,
      dongSL,
      Inp_TG_TP_Text,
      GioVietNam());

   if(kemChart)
      SendPhotoSach(msg);
   else
      g_radar.SendMessage(msg);
}

//+------------------------------------------------------------------+
// [v1.63] TIN KẾT THÚC TÍN HIỆU — phát khi vùng entry vừa công bố không còn vào được nữa.
// Mục đích DUY NHẤT: chặn người đọc kênh vào muộn ở một vùng giá đã chạy xong hoặc đã bị
// bot huỷ. Vì vậy chỉ gọi khi THỰC SỰ có lệnh chờ bị xoá (CancelEAPendings trả về > 0)
// hoặc có vị thế vừa đóng — gọi vô điều kiện sẽ thành spam mỗi lần biên H4 sang nến mới.
// dir = 0 khi không xác định được chiều (vd huỷ cả 2 phía lúc biên đổi) -> bỏ chữ MUA/BÁN.
//+------------------------------------------------------------------+
void NotifySignalClosed(int dir, string lyDo)
{
   if(!Inp_EnableTelegram)
      return;

   string chieu = (dir > 0) ? " MUA" : ((dir < 0) ? " BÁN" : "");

   g_radar.SendMessage(StringFormat(
      "⛔ <b>KẾT THÚC TÍN HIỆU%s — %s</b>\n━━━━━━━━━━━━━━━\n"
      "📝 <b>Lý do:</b> %s\n"
      "🚫 Vùng entry đã công bố KHÔNG còn hiệu lực — anh em đừng vào thêm.\n"
      "🕒 %s (giờ VN)",
      chieu, _Symbol, lyDo,
      GioVietNam()));
}

//+------------------------------------------------------------------+
// Báo Telegram khi có tín hiệu quét râu xác nhận.
//   - Chế độ CHỈ THEO DÕI (Inp_EnableTrading = false): đây là thông báo DUY NHẤT,
//     nên ghi đủ thông tin để vào tay (biên, râu quét, SL dự kiến).
//   - Chế độ VÀO LỆNH: báo sớm "đã có tín hiệu, đang chờ BOS/CHOCH xác nhận",
//     thông tin lệnh thật sẽ báo tiếp ở NotifyOrderPlaced().
//
// [v1.63] Ở chế độ tin PUBLIC hàm này IM LẶNG hoàn toàn. Tin public phải mang được vùng
// entry, mà lúc này chưa đặt lệnh nên chưa biết giá — và quan trọng hơn, chưa biết lệnh
// có vào được hay không. Việc phát tin chuyển hẳn xuống ExecutePairEntry() (Mode nến quét,
// kể cả chế độ chỉ theo dõi) và NotifyOrderPlaced() (Mode BOS/CHOCH).
//+------------------------------------------------------------------+
void NotifySignal(SCRTSource &s, int dir)
{
   if(!Inp_EnableTelegram || Inp_TG_TinPublic)
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
         : "⚡ Đang vào cặp lệnh ngay theo nến quét (market + limit 50%)...");

   SendPhotoSach(msg);
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

//+------------------------------------------------------------------+
double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid) / _Point;
}

//+------------------------------------------------------------------+
// [v1.81] Vào lệnh sau khi khung nhỏ đã cho tín hiệu: ĐÚNG 1 lệnh market, không còn cặp
// market + limit. Lý do: mốc 50% râu quét sinh ra để "bắt giá tốt hơn" khi vào ngay lúc
// khung quét xác nhận — nay việc đó đã do khung nhỏ lo, đặt thêm limit sâu hơn nữa là
// nhân đôi rủi ro cho cùng một setup.
// Chuỗi chốt an toàn giữ y như ExecutePairEntry để hai đường vào không lệch nhau.
//+------------------------------------------------------------------+
void ExecuteLTFEntry(SCRTSource &s, int dir, double entry, double slPrice, string setupName, STPConfig &cfg)
{
   if(!Inp_EnableTrading)
   {
      SendPublicSignal(dir, entry, 0, false, slPrice, true);
      return;
   }
   if(g_halted || g_shieldStopped || g_accountPassed)
   {
      PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (Shield/halt đang chặn) — vẫn phát tín hiệu.",
                  s.tag, setupName);
      SendPublicSignal(dir, entry, 0, false, slPrice, true);
      return;
   }
   if(IsInNewsWindow())
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (khung giờ tin tức).", s.tag, setupName); return; }
   if(Inp_MaxSpreadPoints > 0 && CurrentSpreadPoints() > Inp_MaxSpreadPoints)
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (spread quá rộng).", s.tag, setupName); return; }

   if(!PlaceOneOrder(s, dir, entry, false, "", setupName + " · khung nhỏ", cfg, slPrice))
   {
      PrintFormat("[CRT][%s] %s: không đặt được lệnh -> không phát tin Telegram.", s.tag, setupName);
      return;
   }

   SendPublicSignal(dir, entry, 0, false, slPrice, true);
   SendChiTiet(StringFormat(
      "🔎 %s · %s (vào bằng %s)\n"
      "📦 Market %s lot\n"
      "💳 Balance: %s$",
      s.tag, setupName, TFToString(Inp_EntryLTF_TF),
      DoubleToString(g_lotVuaDat, 2),
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
}

//+------------------------------------------------------------------+
// [v1.81] Chạy trên mỗi nến ĐÃ ĐÓNG của khung nhỏ khi đang chờ vào lệnh.
// Ba việc theo đúng thứ tự: kiểm setup còn sống không -> nến có nằm trong vùng không ->
// nến có phải tín hiệu đảo chiều không.
// Dùng CHÍNH thư viện Signal_Candle như khung quét, nên "thế nào là nến đẹp" nhất quán
// giữa hai khung, không sinh ra luật thứ hai.
//+------------------------------------------------------------------+
void ProcessLTFEntry(SCRTSource &s)
{
   if(!s.ltfWaiting)
      return;

   datetime bar0 = iTime(_Symbol, Inp_EntryLTF_TF, 0);
   if(bar0 == 0 || bar0 == s.ltfLastBar)
      return;                       // chưa có nến khung nhỏ nào đóng thêm
   s.ltfLastBar = bar0;

   bool   isBuy = (s.ltfDir > 0);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // --- 1. Setup còn sống không? ---
   // Giá xuyên qua mút râu quét = cú quét thất bại, không còn gì để chờ.
   bool thungRau = isBuy ? (bid < s.ltfZoneFar) : (ask > s.ltfZoneFar);
   if(thungRau)
   {
      PrintFormat("[CRT][%s] %s: giá xuyên mút râu quét %s -> cú quét hỏng, bỏ chờ khung nhỏ.",
                  s.tag, s.ltfSetupName, DoubleToString(s.ltfZoneFar, _Digits));
      s.ltfWaiting = false;
      return;
   }

   if(--s.ltfBarsLeft < 0)
   {
      PrintFormat("[CRT][%s] %s: hết %d nến %s mà không có nến xác nhận -> bỏ setup.",
                  s.tag, s.ltfSetupName, Inp_EntryLTF_MaxBars, TFToString(Inp_EntryLTF_TF));
      s.ltfWaiting = false;
      return;
   }

   // --- 2. Nến vừa đóng có nằm trong vùng giá không? ---
   SCandle k;
   if(!SC_LoadCandle(_Symbol, Inp_EntryLTF_TF, 1, k))
      return;

   double zLo = MathMin(s.ltfZoneFar, s.ltfZoneNear);
   double zHi = MathMax(s.ltfZoneFar, s.ltfZoneNear);
   if(k.c < zLo || k.c > zHi)
      return;                       // giá chưa hồi về vùng — cứ chờ tiếp, chưa bỏ setup

   // --- 3. Có phải nến tín hiệu không? ---
   SCandle kTruoc;
   bool coTruoc = SC_LoadCandle(_Symbol, Inp_EntryLTF_TF, 2, kTruoc);
   bool laPin   = SC_IsPinbar(s.ltfDir, k);
   bool laEng   = coTruoc && SC_IsEngulfing(s.ltfDir, kTruoc, k);
   if(!laPin && !laEng)
      return;

   // --- Đủ điều kiện: vào lệnh ---
   // SL theo lựa chọn: râu khung quét (rộng, như cũ) hoặc râu chính nến xác nhận (hẹp).
   double slPrice;
   string slMoTa;
   if(Inp_EntryLTF_SLMode == SLtheo_RauXacNhan)
   {
      double mut = isBuy ? k.l : k.h;
      slPrice = isBuy ? mut - Inp_SL_BufferPips * GetPipSize()
                      : mut + Inp_SL_BufferPips * GetPipSize();
      slMoTa  = StringFormat("râu nến %s", TFToString(Inp_EntryLTF_TF));
   }
   else
   {
      slPrice = s.ltfSlM15;
      slMoTa  = StringFormat("râu quét %s", TFToString(Inp_LTF));
   }

   double entry = isBuy ? ask : bid;
   PrintFormat("[CRT][%s] %s: nến %s @%s %s trong vùng -> VÀO LỆNH %s @%s · SL %s (%s + %.0f pip)",
               s.tag, s.ltfSetupName, TFToString(Inp_EntryLTF_TF),
               TimeToString(iTime(_Symbol, Inp_EntryLTF_TF, 1), TIME_DATE|TIME_MINUTES),
               laPin ? "PINBAR" : "ENGULFING",
               isBuy ? "BUY" : "SELL", DoubleToString(entry, _Digits),
               DoubleToString(slPrice, _Digits), slMoTa, Inp_SL_BufferPips);

   s.ltfWaiting = false;
   ExecuteLTFEntry(s, s.ltfDir, entry, slPrice, s.ltfSetupName, s.ltfCfg);
}

//+------------------------------------------------------------------+
// [v1.81] CỬA VÀO DUY NHẤT sau khi một nhánh CRT xác nhận setup. Tuỳ thiết lập mà đi
// một trong hai đường:
//   · Inp_EntryLTF_Enable TẮT  -> vào ngay như cũ (cặp market + limit 50%).
//   · BẬT -> khung quét CHỈ xác nhận setup; ghi nhận vùng giá rồi chờ khung nhỏ.
// Bốn nhánh 2.1 / 2.1b / 2.1c / 2.2 đều gọi qua đây nên chỉ cần rẽ ở một chỗ.
//+------------------------------------------------------------------+
void VaoLenhHoacChoKhungNho(SCRTSource &s, int dir, double limitPrice, string setupName, STPConfig &cfg)
{
   if(!Inp_EntryLTF_Enable)
   {
      ExecutePairEntry(s, dir, limitPrice, setupName, cfg);
      return;
   }

   bool isBuy = (dir > 0);

   // VÙNG GIÁ HỢP LỆ = [mút râu quét ... giá tham chiếu lúc khung quét xác nhận].
   // Vào ở bất kỳ đâu trong vùng này đều tốt hơn vào ngay tại giá xác nhận, vì càng gần
   // mút râu thì SL càng gần mà đích vẫn thế.
   // Mép XA (mút râu) kiêm luôn MỐC HUỶ: giá xuyên qua nó nghĩa là cú quét đã thất bại,
   // setup chết, không chờ nữa.
   double mutRau = isBuy ? s.sweptLow : s.sweptHigh;
   double giaXN  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   s.ltfWaiting   = true;
   s.ltfDir       = dir;
   s.ltfZoneFar   = mutRau;
   s.ltfZoneNear  = giaXN;
   s.ltfSlM15     = isBuy ? mutRau - Inp_SL_BufferPips * GetPipSize()
                          : mutRau + Inp_SL_BufferPips * GetPipSize();
   s.ltfBarsLeft  = Inp_EntryLTF_MaxBars;
   s.ltfLastBar   = iTime(_Symbol, Inp_EntryLTF_TF, 0);
   s.ltfSetupName = setupName;
   s.ltfCfg       = cfg;

   PrintFormat("[CRT][%s] %s: setup XÁC NHẬN trên %s -> chuyển sang chờ nến %s trong vùng %s..%s (tối đa %d nến).",
               s.tag, setupName, TFToString(Inp_LTF), TFToString(Inp_EntryLTF_TF),
               DoubleToString(MathMin(mutRau, giaXN), _Digits),
               DoubleToString(MathMax(mutRau, giaXN), _Digits),
               Inp_EntryLTF_MaxBars);
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
   // [v1.63] Giá + SL tính TRƯỚC mọi chốt chặn: chế độ chỉ theo dõi cần chúng để phát tin
   // với giá dự kiến. Đây chỉ là mấy phép đọc giá, không đụng gì tới lệnh.
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   isBuy = (dir > 0);
   double line  = isBuy ? s.boundLow : s.boundHigh;
   double mkt   = isBuy ? ask : bid;

   // Cùng công thức SL với PlaceOneOrder() (râu quét ± đệm). Tính lại ở đây thay vì đợi
   // PlaceOneOrder trả ra, vì tin public cần một mốc SL DUY NHẤT cho cả cặp lệnh.
   double slPub = isBuy ? s.sweptLow - Inp_SL_BufferPips * GetPipSize()
                        : s.sweptHigh + Inp_SL_BufferPips * GetPipSize();

   if(!Inp_EnableTrading)
   {
      // Chế độ chỉ theo dõi: không vào lệnh, nhưng vẫn phát tín hiệu cho cộng đồng vào tay.
      // Giá là DỰ KIẾN (market = giá hiện tại, limit = mốc 50%) vì không có lệnh thật nào.
      SendPublicSignal(dir, mkt, limitPrice, true, slPub, true);
      return;
   }
   // [v1.74] Shield chặn VÀO LỆNH, nhưng KÊNH TÍN HIỆU VẪN CHẠY.
   // Trước đây thoát thẳng ở đây nên chạm DD/lãi ngày là kênh im lặng đến hết ngày —
   // member tưởng bot chết. Nay xử lý y như chế độ chỉ-theo-dõi: phát tín hiệu với giá
   // DỰ KIẾN, chỉ không đặt lệnh. Nhờ vậy tin "bot dừng vào lệnh, tín hiệu vẫn gửi"
   // mới đúng sự thật.
   // Chỉ áp cho 3 cờ TRẠNG THÁI TÀI KHOẢN. Các chốt chặn bên dưới (khung giờ tin, spread)
   // vẫn im lặng như cũ: chúng là điều kiện kỹ thuật của CHÍNH sàn này, sàn của member
   // khác hẳn nên phát tín hiệu dựa vào đó là sai.
   if(g_halted || g_shieldStopped || g_accountPassed)
   {
      PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (Shield/halt đang chặn) — vẫn phát tín hiệu.",
                  s.tag, setupName);
      SendPublicSignal(dir, mkt, limitPrice, true, slPub, true);
      return;
   }
   if(IsInNewsWindow())
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (khung giờ tin tức).", s.tag, setupName); return; }
   if(Inp_MaxSpreadPoints > 0 && CurrentSpreadPoints() > Inp_MaxSpreadPoints)
   { PrintFormat("[CRT][%s] %s: bỏ qua vào lệnh (spread %.1f > %d).", s.tag, setupName,
                 CurrentSpreadPoints(), Inp_MaxSpreadPoints); return; }

   // [v1.63] Giá của những lệnh ĐẶT THÀNH CÔNG — tin public dựng từ đây, không dựng từ ý
   // định ban đầu. PlaceOneOrder còn từ chối vì nhiều lý do riêng (vượt Middle, SL quá
   // rộng, lot = 0, sai stops level) nên "đã gọi" khác hẳn "đã vào".
   double eMkt = 0, eLim = 0;
   bool   okMkt = false, okLim = false;
   double lotMkt = 0, lotLim = 0;      // [v1.65] lot từng lệnh, cho tin chi tiết
   string nhanMkt = "Market";          // đổi thành "Limit tại biên" nếu rơi vào nhánh đó

   // Giá đã chạy quá xa đường biên -> vào market lúc này là R:R xấu (SL vẫn nằm ở
   // râu quét, còn entry thì đã cách rất xa). Xử lý theo Inp_FarFromLine_Action.
   bool marketTooFar = (Inp_MaxDistFromLine_Pips > 0 &&
                        MathAbs(mkt - line) / GetPipSize() > Inp_MaxDistFromLine_Pips);

   // [v1.70] Chế độ CHỈ LIMIT thì bỏ qua trọn khối market bên dưới, kể cả nhánh
   // "quá xa biên -> đổi thành limit tại biên" — nhánh đó sinh ra để CỨU vế market,
   // không có vế market thì nó không có việc gì để làm.
   if(Inp_KieuVaoLenh == KieuVao_Limit)
   {
      // không làm gì — vế market bị tắt bằng thiết lập
   }
   else if(!marketTooFar || Inp_FarFromLine_Action == Far_VanVaoMarket)
   {
      if(PlaceOneOrder(s, dir, mkt, false, "", setupName + " · market", cfg))
      { eMkt = mkt; okMkt = true; lotMkt = g_lotVuaDat; }
   }
   else if(Inp_FarFromLine_Action == Far_ChuyenThanhLimitTaiLine)
   {
      PrintFormat("[CRT][%s] %s: giá cách biên %.1f pip (> %.1f) -> đổi lệnh market thành LIMIT tại biên %s.",
                  s.tag, setupName, MathAbs(mkt - line) / GetPipSize(), Inp_MaxDistFromLine_Pips,
                  DoubleToString(line, _Digits));
      if(PlaceOneOrder(s, dir, line, true, "biên " + TFToString(Inp_HTF), setupName + " · limit tại biên", cfg))
      { eMkt = line; okMkt = true; lotMkt = g_lotVuaDat; nhanMkt = "Limit tại biên " + TFToString(Inp_HTF); }
   }
   else // Far_BoLenhMarket
   {
      PrintFormat("[CRT][%s] %s: giá cách biên %.1f pip (> %.1f) -> BỎ lệnh market, chỉ giữ limit 50%%.",
                  s.tag, setupName, MathAbs(mkt - line) / GetPipSize(), Inp_MaxDistFromLine_Pips);
   }

   // [v1.70] Vế limit 50% chỉ chạy ở chế độ CHỈ LIMIT và CẢ HAI.
   // Khi setup chỉ còn 1 lệnh, các luật dựa trên "cặp lệnh" tự nhiên không còn việc để
   // làm — không phải tắt gì thêm: luật "1 lệnh chạm TP -> xử lý lệnh kia" quét theo
   // magic nên không tìm thấy lệnh cùng chiều, luật huỷ lệnh chờ cũng không có gì để huỷ.
   if(Inp_KieuVaoLenh != KieuVao_TrucTiep)
   {
      if(PlaceOneOrder(s, dir, limitPrice, true, "mốc 50%", setupName + " · limit 50%", cfg))
      { eLim = limitPrice; okLim = true; lotLim = g_lotVuaDat; }
   }

   // Không lệnh nào vào -> IM LẶNG. Log đã ghi rõ lý do ở PlaceOneOrder; kênh public không
   // được nhận tín hiệu mà bot không hề tham gia.
   if(!okMkt && !okLim)
   {
      PrintFormat("[CRT][%s] %s: không đặt được lệnh nào -> không phát tin Telegram.", s.tag, setupName);
      return;
   }

   double eA = okMkt ? eMkt : eLim;
   double eB = okLim ? eLim : eMkt;
   SendPublicSignal(dir, eA, eB, (okMkt && okLim), slPub, true);

   // [v1.65] Tin chi tiết: gộp CẢ CẶP vào MỘT tin. Cố ý không để NotifyOrderPlaced tự bắn
   // theo từng lệnh — hai tin liên tiếp cho cùng một setup dễ bị đọc nhầm thành hai kèo.
   string dongLenh = "";
   if(okMkt) dongLenh += StringFormat("%s %s lot", nhanMkt, DoubleToString(lotMkt, 2));
   if(okMkt && okLim) dongLenh += "  ·  ";
   if(okLim) dongLenh += StringFormat("Limit 50%% %s lot", DoubleToString(lotLim, 2));

   SendChiTiet(StringFormat(
      "🔎 %s · %s\n"
      "📦 %s\n"
      "💳 Balance: %s$",
      s.tag, setupName, dongLenh,
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
}

//+------------------------------------------------------------------+
// [v1.65] Khối lượng của lệnh VỪA đặt thành công. ExecutePairEntry đọc ngay sau mỗi lần
// gọi PlaceOneOrder để gộp cả cặp vào MỘT tin chi tiết.
// Dùng biến dùng chung thay vì thêm tham số tham chiếu vào PlaceOneOrder: hàm đó có 4 chỗ
// gọi ở 2 mode, đổi chữ ký là đụng hết. Không có rủi ro chồng lệnh — mọi thứ chạy tuần tự
// trong cùng một luồng OnTick, đọc xong dùng liền.
// Lot của 2 lệnh trong cặp CÓ THỂ KHÁC NHAU: CalcLots() tính theo khoảng cách tới SL, mà
// lệnh market và lệnh limit 50% cách SL khác nhau. Nên phải ghi riêng từng lệnh.
//+------------------------------------------------------------------+
double g_lotVuaDat = 0;

//+------------------------------------------------------------------+
// Lõi đặt 1 lệnh, dùng chung cho cả 2 mode: validate -> tính SL/TP/lot -> gửi lệnh.
// mocTxt chỉ để ghi log cho dễ hiểu khi lệnh chờ bị từ chối.
//+------------------------------------------------------------------+
bool PlaceOneOrder(SCRTSource &s, int dir, double entry, bool useLimit, string mocTxt, string setupName, STPConfig &cfg, double slOverride = 0)
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
   // [v1.81] slOverride > 0: vào lệnh bằng khung nhỏ và người dùng chọn SL theo râu nến
   // xác nhận. Mọi thứ phía sau (lot theo risk, TP theo R:R, lọc Inp_MaxSL_Pips) dùng
   // chung một biến sl nên chỉ cần thay ở đây là cả chuỗi tự khớp.
   double sl    = (slOverride > 0) ? slOverride
                                   : (isBuy ? s.sweptLow - buf : s.sweptHigh + buf);
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

   // [v1.77] CHẶN TRƯỚC THEO DƯ ĐỊA LỖ NGÀY.
   // Không có chốt này thì bot vẫn vào lệnh khi dư địa gần cạn — ví dụ đang lỗ 190$ với
   // mốc DD 200$: lệnh rủi ro 100$ vẫn được mở, rồi giá nhúc nhích ngược là Shield đóng
   // sạch ở −200$. Mốc DD không bị vượt (Shield đo equity NỔI mỗi tick nên nó chặn đúng
   // chỗ), nhưng lệnh đó chết oan: trả spread + phí cho một lệnh không có chỗ thở, và
   // một lệnh lẽ ra có thể thắng bị biến thành lỗ nhỏ.
   // Nay so rủi ro THẬT của chính lệnh này với dư địa còn lại; không đủ chỗ thì nghỉ sớm.
   // Dư địa tính từ equity NỔI nên đã bao gồm lãi lỗ của các lệnh đang mở.
   // Không áp cho bên LÃI: ở đó vào thêm lệnh không gây hại — hoặc nó đẩy nhanh tới mục
   // tiêu, hoặc nó đi ngược và ngày cứ chạy tiếp.
   if(Inp_DailyDrawdownLimit > 0 && g_sodBalance > 0 && slDist > 0)
   {
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal > 0 && tickSize > 0)
      {
         double ruiRo   = lots * slDist / tickSize * tickVal;
         double sanLo   = g_sodBalance - BalanceCoSo() * Inp_DailyDrawdownLimit / 100.0;
         double duDia   = AccountInfoDouble(ACCOUNT_EQUITY) - sanLo;
         if(ruiRo > duDia)
         {
            PrintFormat("[CRT][%s] Bỏ qua %s: rủi ro lệnh %.2f$ > dư địa lỗ ngày còn lại %.2f$ -> nghỉ sớm thay vì vào rồi bị Shield cắt.",
                        s.tag, isBuy ? "BUY" : "SELL", ruiRo, duDia);
            return false;
         }
      }
   }

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
      g_lotVuaDat = lots;      // [v1.65] cho ExecutePairEntry gộp tin chi tiết
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

   // [v1.63] TIN PUBLIC:
   //   · Mode nến quét — cả CẶP lệnh gộp thành 1 tin do ExecutePairEntry phát sau khi đặt
   //     xong. Ở đây im lặng, nếu không mỗi setup sẽ ra 3 tin gần như trùng nhau.
   //   · Mode BOS/CHOCH — mỗi lần vào là 1 lệnh đơn, đây mới là chỗ biết chắc lệnh đã vào
   //     nên tin public phát tại đây, chỉ có 1 giá entry (hasB = false).
   // [v1.65] Ở Mode nến quét, CẢ tin public LẪN tin chi tiết đều do ExecutePairEntry gộp
   // phát cho cả cặp. Hàm này im lặng hoàn toàn — nó chạy mỗi lệnh một lần, để nó bắn tin
   // là mỗi setup ra 2 tin liên tiếp, đúng thứ dễ bị đọc nhầm thành 2 kèo.
   if(Inp_TG_TinPublic)
   {
      if(Inp_TradeMode == TradeMode_NenQuet_LTF)
         return;

      // Mode BOS/CHOCH: mỗi lần vào là 1 lệnh đơn, đây mới là chỗ biết chắc lệnh đã vào.
      SendPublicSignal(dir, entry, 0, false, sl, true);
      SendChiTiet(StringFormat(
         "🔎 %s%s\n"
         "📦 %s lot\n"
         "💳 Balance: %s$",
         s.tag, setupName == "" ? "" : (" · " + setupName),
         DoubleToString(lots, 2),
         DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
      return;
   }

   double slPips = MathAbs(entry - sl) / GetPipSize();
   double tpPips = MathAbs(tp - entry) / GetPipSize();

   string slLine = (Inp_SL_Mode == SLMode_KhongDatSL)
      ? StringFormat("🛡️ <b>SL:</b> KHÔNG ĐẶT trên sàn (mốc ảo %s · %s pip)",
                     DoubleToString(sl, _Digits), DoubleToString(slPips, 1))
      : StringFormat("🛡️ <b>SL:</b> %s (%s pip)",
                     DoubleToString(sl, _Digits), DoubleToString(slPips, 1));

   // Nhãn dòng giá — setupName đã tự mô tả nhánh, ở đây chỉ phân biệt lệnh chờ / market.
   string priceLabel = useLimit ? "Giá chờ (50%)" : "Entry";

   // [v1.63] Không kèm chart nữa: tin tín hiệu ngay trước đó đã có ảnh chart của cùng
   // cây nến, chụp lại lần hai chỉ tốn thời gian và làm dài kênh.
   g_radar.SendMessage(StringFormat(
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
// [v1.74] Mốc quy đổi cho MỌI thiết lập tính bằng % tài khoản. Mặc định là một con số
// CỐ ĐỊNH do người dùng đặt (10.000$), không phải số dư thật.
// Lý do: số dư thật thay đổi từng ngày nên cùng một con số % lại ra ngưỡng tiền khác
// nhau mỗi ngày — muốn biết hôm nay lỗ bao nhiêu $ là chạm DD thì phải tính lại. Chốt
// một mốc cố định thì 3% luôn đúng bằng 300$, khỏi nhẩm.
// Để 0 thì quay về hành vi cũ: bám số dư thật, tự co giãn theo tài khoản.
// DÙNG CHUNG cho: Risk %/lệnh, giới hạn margin, Account SL, DD ngày, Lãi ngày.
// KHÔNG đụng phép ĐO mức lỗ/lãi thực tế — cái đó vẫn so với số dư đầu ngày thật, chỉ
// riêng NGƯỠNG là quy từ mốc cố định.
//+------------------------------------------------------------------+
double BalanceCoSo()
{
   if(Inp_BalanceCoSo > 0)
      return Inp_BalanceCoSo;
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots;

   if(Inp_LotMode == LotMode_CoDinh)
      lots = Inp_FixedLotSize;
   else
   {
      // [v1.69] Hai chế độ tính-ngược đi chung một công thức, chỉ khác chỗ lấy SỐ TIỀN
      // RỦI RO: % tài khoản thì nhân từ balance, còn LotMode_SoTienUSD thì người dùng gõ
      // thẳng số $ chịu mất. Số $ cố định KHÔNG co giãn theo balance — đó là điểm khác
      // biệt duy nhất và cũng là lý do dùng nó: mỗi lệnh thua đúng một khoản đã biết,
      // không phụ thuộc tài khoản đang lãi hay lỗ.
      // [v1.78] Mỗi đường trả 0 đều nói rõ VÌ SAO. Trước đây tất cả đổ về một dòng
      // "lots=0 (hết margin hoặc dưới lot tối thiểu)" ở PlaceOneOrder — soi log thật
      // không đoán nổi là do thiếu tiền, sai thiết lập, hay sàn trả số liệu rỗng.
      if(slDistancePrice <= 0)
      { Print("[CRT] lot=0: SL distance <= 0 — chế độ tính theo rủi ro bắt buộc phải có SL."); return 0; }

      double riskMoney = (Inp_LotMode == LotMode_SoTienUSD)
                            ? Inp_RiskMoneyUSD
                            : BalanceCoSo() * Inp_RiskPercent / 100.0;
      if(riskMoney <= 0)
      { PrintFormat("[CRT] lot=0: số tiền rủi ro = %.2f$ — kiểm Inp_RiskMoneyUSD (đang %.2f) hoặc Inp_RiskPercent (đang %.2f%%) / Inp_BalanceCoSo (đang %.2f).",
                    riskMoney, Inp_RiskMoneyUSD, Inp_RiskPercent, Inp_BalanceCoSo); return 0; }

      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0 || tickSize <= 0)
      { PrintFormat("[CRT] lot=0: sàn trả tick rỗng (tickValue=%.5f tickSize=%.5f) — thử lại tick sau.",
                    tickVal, tickSize); return 0; }

      double lossPerLot = slDistancePrice / tickSize * tickVal;
      if(lossPerLot <= 0)
      { PrintFormat("[CRT] lot=0: lỗ mỗi lot = %.2f$ (SL %.1f pip).", lossPerLot, slDistancePrice / GetPipSize()); return 0; }

      lots = riskMoney / lossPerLot;
      PrintFormat("[CRT] Tính lot: rủi ro %.2f$ / (SL %.1f pip = %.2f$ mỗi lot) = %.4f lot.",
                  riskMoney, slDistancePrice / GetPipSize(), lossPerLot, lots);
   }

   // [v1.75] Khối giới hạn margin đã gỡ hẳn theo yêu cầu (chỉ cần khi chạy bot quỹ).
   // Hệ quả cần nhớ: lot KHÔNG còn trần nào ngoài SYMBOL_VOLUME_MAX. Với chế độ rủi ro
   // theo số tiền, setup có SL rất chặt sẽ ra lot lớn — đó là hành vi đúng của công thức,
   // muốn chặn thì hạ Inp_RiskMoneyUSD chứ không còn cơ chế tự giảm lot.

   if(stepL > 0) lots = MathFloor(lots / stepL) * stepL;
   if(lots < minL)
   {
      // KHÔNG ép lên minLot: ép lên là phá vỡ mức rủi ro người dùng đặt.
      PrintFormat("[CRT] lot=0: sau khi làm tròn còn %.4f < lot tối thiểu %.4f của sàn -> bỏ lệnh thay vì ép lên lot tối thiểu (ép là vỡ mức rủi ro).",
                  lots, minL);
      return 0;
   }
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

   // [v1.63] Gom lại rồi báo MỘT tin sau vòng lặp. Một nguồn có thể còn 2 lệnh chờ cùng
   // chiều (limit tại biên + limit 50%) và chúng chạm mốc cùng lúc -> báo trong vòng lặp
   // sẽ ra 2 tin y hệt nhau trên kênh.
   int    nHuy = 0;
   int    dirHuy = 0;
   string lyDoHuy = "";

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
      {
         PrintFormat("[CRT][%s] Giá chạm %s %s -> huỷ lệnh chờ %s #%I64u (coi như đã chạm TP trước khi khớp).",
                     s.tag, tenMoc, DoubleToString(target, _Digits), isBuy ? "BUY" : "SELL", tk);
         nHuy++;
         dirHuy  = isBuy ? +1 : -1;
         lyDoHuy = "giá đã chạy tới " + tenMoc + " " + DoubleToString(target, 2)
                 + " — vùng entry coi như đã xong";
      }
   }

   // [v1.63] Đây là ca dễ hại người theo tín hiệu nhất: giá đã đi tới đích mà lệnh chờ
   // chưa kịp khớp — ai vào muộn là mua/bán ngay chỗ đáng lẽ phải chốt lời.
   if(nHuy > 0)
      NotifySignalClosed(dirHuy, lyDoHuy);
}

//+------------------------------------------------------------------+
// [v1.63] Trả về SỐ LỆNH CHỜ XOÁ ĐƯỢC. Bên gọi dùng con số này để quyết định có phát tin
// "kết thúc tín hiệu" hay không — hàm được gọi vô điều kiện ở nhiều chỗ (mỗi lần biên H4
// sang nến mới chẳng hạn), phần lớn các lần đó chẳng có lệnh chờ nào để huỷ.
int CancelEAPendings(long magic)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
      {
         if(g_trade.OrderDelete(tk))
            n++;
      }
   }
   return n;
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
   double limit = g_startBalance - BalanceCoSo() * Inp_AccountSL_Percent / 100.0;
   if(eq <= limit)
   {
      CloseAllBotOrders();
      g_halted = true;
      PrintFormat("[CRT] 🛑 ACCOUNT SL: equity %.2f <= %.2f (-%.1f%%). Đóng tất cả & dừng vào lệnh.",
                  eq, limit, Inp_AccountSL_Percent);
      if(TinVanHanhDuocPhep())
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
      if(TinVanHanhDuocPhep())
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
      double lossLimit = g_sodBalance - BalanceCoSo() * Inp_DailyDrawdownLimit / 100.0;
      if(eq <= lossLimit)
      {
         CloseAllBotOrders();
         g_shieldStopped = true;
         g_shieldReason  = "Chạm Daily DD " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
         PrintFormat("[CRT] 🛑 DAILY DD: equity %.2f <= %.2f. Nghỉ đến hết ngày.", eq, lossLimit);
         // [v1.74] Tin này GỬI CẢ KÊNH CÔNG KHAI, nên tuyệt đối không có con số tài khoản
         // — không equity, không số dư, không cả % ngưỡng (biết % là suy ra được số tiền).
         // Bản nội bộ vẫn in đủ số liệu để chủ bot đối chiếu.
         if(Inp_EnableTelegram)
            g_radar.SendMessage(TinVanHanhDuocPhep()
               ? StringFormat(
                    "🛑 <b>CHẠM GIỚI HẠN LỖ NGÀY</b>\n━━━━━━━━━━━━━━━\n"
                    "💸 Equity: %s$ (đầu ngày %s$, giới hạn -%s%%)\n"
                    "😴 Nghỉ giao dịch đến hết ngày.",
                    DoubleToString(eq, 2), DoubleToString(g_sodBalance, 2),
                    DoubleToString(Inp_DailyDrawdownLimit, 1))
               : "🛑 <b>ĐÃ CHẠM MỐC GIỚI HẠN THUA LỖ NGÀY</b>\n━━━━━━━━━━━━━━━\n"
                 "😴 Bot dừng vào lệnh đến hết ngày.\n"
                 "📡 Tín hiệu vẫn tiếp tục được gửi như thường.");
         return;
      }
   }

   if(Inp_DailyProfitLimit > 0)
   {
      double profitMoney  = eq - g_sodBalance;
      double profitTarget = BalanceCoSo() * Inp_DailyProfitLimit / 100.0;
      double profitPct    = (g_sodBalance > 0) ? profitMoney / g_sodBalance * 100.0 : 0;
      if(profitMoney >= profitTarget)
      {
         CloseAllBotOrders();
         g_shieldStopped = true;
         g_shieldReason  = "Đạt Daily Profit +" + DoubleToString(profitPct, 2) + "%";
         PrintFormat("[CRT] 🎯 DAILY PROFIT: +%.2f%% >= %.1f%%. Nghỉ đến hết ngày.", profitPct, Inp_DailyProfitLimit);
         if(Inp_EnableTelegram)
            g_radar.SendMessage(TinVanHanhDuocPhep()
               ? StringFormat(
                    "🎯 <b>ĐẠT MỤC TIÊU LÃI NGÀY</b>\n━━━━━━━━━━━━━━━\n"
                    "💰 +%s%% (equity %s$)\n✅ Đã chốt toàn bộ lệnh, nghỉ đến hết ngày.",
                    DoubleToString(profitPct, 2), DoubleToString(eq, 2))
               : "🎯 <b>ĐÃ ĐẠT MỐC LỢI NHUẬN NGÀY</b>\n━━━━━━━━━━━━━━━\n"
                 "✅ Bot dừng vào lệnh đến hết ngày.\n"
                 "📡 Tín hiệu vẫn tiếp tục được gửi như thường.");
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
   if(TinVanHanhDuocPhep())
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
   int  nHuy  = 0;   // [v1.63] gom lại, báo 1 tin sau vòng lặp

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
      {
         PrintFormat("[CRT] Cặp lệnh: 1 lệnh đã chạm TP -> huỷ lệnh chờ #%I64u cùng chiều.", tk);
         nHuy++;
      }
   }

   // [v1.63] Kèo đã ăn TP mà lệnh chờ chưa khớp -> báo ngay để không ai vào muộn.
   if(nHuy > 0)
      NotifySignalClosed(dir, "lệnh trong cặp đã chạm Take Profit");

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
      if(Inp_BE_KhiLenhKiaTP)
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
// [v1.67] Luật hoà vốn THỨ BA, chạy song song với 2 luật cũ (chạm biên đối diện, 1 lệnh
// trong cặp chạm TP). Ba luật cùng gọi MovePositionToBreakeven() nên luật nào kích trước
// thì thắng, và luật sau không phá được kết quả của luật trước — hàm đó chỉ dời SL khi
// việc dời có LỢI, không bao giờ nới lỏng một SL đang tốt.
// KHÁC VỚI 2 LUẬT KIA: chúng bám MỐC GIÁ (biên đối diện) hoặc SỰ KIỆN (lệnh kia TP), còn
// luật này bám KHOẢNG LÃI. Nên nó kích được cả khi biên đối diện ở quá xa — đúng ca hay
// gặp với nguồn Swing, nơi range rộng tới mức giá chạy thuận cả trăm pip mà vẫn chưa tới
// biên, lệnh vẫn có thể quay đầu về SL gốc.
// Đo bằng giá ĐÓNG ĐƯỢC (BUY đo theo Bid, SELL đo theo Ask) — đúng thứ sàn dùng để tính
// lãi lỗ; lấy nhầm chiều giá là lệch nguyên một spread, với vàng thì spread 24 pip không
// phải nhỏ.
//+------------------------------------------------------------------+
void MoveSLToEntryAtProfitPips(SCRTSource &s)
{
   if(Inp_BE_TriggerPips <= 0)
      return;   // 0 = tắt hẳn luật này

   double trigger = Inp_BE_TriggerPips * GetPipSize();
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk))         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;
      if(PositionGetInteger(POSITION_MAGIC)  != s.magic) continue;

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = isBuy ? (bid - open) : (open - ask);
      if(profit < trigger) continue;

      MovePositionToBreakeven(tk, StringFormat("[%s] Lãi đạt %.1f pip (>= %.1f)",
                              s.tag, profit / GetPipSize(), Inp_BE_TriggerPips));
   }
}

//+------------------------------------------------------------------+
void MoveSLToEntryAtOppositeBound(SCRTSource &s)
{
   if(!Inp_BE_TaiBienDoiDien)   // [1.68] tắt được để đo hành trình lệnh trọn vẹn
      return;
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
// [v1.65] Giá VÀO LỆNH của một vị thế đã đóng, truy ngược từ position id.
// Dùng để biết lệnh nào trong CẶP vừa chốt: lệnh market hay lệnh limit 50%. Comment lệnh
// ("CRT buy Swing") không ghi nhánh setup lẫn loại lệnh, nên giá vào là manh mối duy nhất.
// LƯU Ý cho người sửa sau: hàm này gọi HistorySelectByPosition() -> ĐỔI luôn bộ nhớ đệm
// history mà HistoryDealGetX(trans.deal, ...) đang dựa vào. Phải đọc xong mọi giá trị của
// trans.deal RỒI mới được gọi hàm này, đừng xen kẽ.
double GiaVaoCuaViThe(long posId)
{
   if(posId <= 0)                      return 0;
   if(!HistorySelectByPosition(posId)) return 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return HistoryDealGetDouble(d, DEAL_PRICE);
   }
   return 0;
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

   // [v1.65] Đọc HẾT các giá trị của trans.deal ở đây, TRƯỚC khi gọi GiaVaoCuaViThe() —
   // hàm đó đổi bộ nhớ đệm history nên sau nó mọi HistoryDealGetX(trans.deal,...) đều hỏng.
   double lotDong  = HistoryDealGetDouble(trans.deal,  DEAL_VOLUME);
   double giaDong  = HistoryDealGetDouble(trans.deal,  DEAL_PRICE);
   long   posId    = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

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

   // [v1.63] Tin public: TUYỆT ĐỐI không đưa P&L và Balance lên kênh cộng đồng. Người đọc
   // chỉ cần biết kèo đã đóng theo hướng nào để ngừng vào thêm ở vùng entry cũ.
   // Cặp lệnh khớp cả 2 rồi cùng ăn TP sẽ ra 2 tin — cố ý giữ vậy, mỗi tin là một lệnh
   // thật đã đóng, gộp lại phải nuôi thêm trạng thái mà chẳng rõ ràng hơn.
   if(Inp_TG_TinPublic)
   {
      string tieuDe = "🏁 <b>ĐÃ ĐÓNG LỆNH — " + _Symbol + "</b>";
      if(reason == DEAL_REASON_TP) tieuDe = "✅ <b>CHỐT LỜI — " + _Symbol + "</b>";
      if(reason == DEAL_REASON_SL) tieuDe = "🔴 <b>DÍNH STOP LOSS — " + _Symbol + "</b>";

      g_radar.SendMessage(StringFormat(
         "%s\n━━━━━━━━━━━━━━━\n"
         "🚫 Tín hiệu đã kết thúc — anh em đừng vào thêm ở vùng entry cũ.\n"
         "🕒 %s (giờ VN)",
         tieuDe, GioVietNam()));

      // [v1.65] Phụ lục nội bộ, KHÔNG lặp lại thứ tin public vừa nói (chiều lệnh, symbol,
      // TP hay SL). Chỉ 3 thứ tin public không có: lệnh nào trong cặp vừa chốt (đọc qua
      // cặp giá vào->đóng), khối lượng, và tiền.
      // Lý do đóng chỉ in khi tin public nói KHÔNG rõ: TP/SL đã thành tiêu đề ở trên rồi,
      // còn "bot tự đóng" / "đóng tay" thì public gộp chung thành "ĐÃ ĐÓNG LỆNH" nên phải
      // nói thêm ở đây mới biết chuyện gì xảy ra.
      double giaVaoP = GiaVaoCuaViThe(posId);
      string moTaP   = (giaVaoP > 0)
         ? StringFormat("vào %s → đóng %s", DoubleToString(giaVaoP, _Digits), DoubleToString(giaDong, _Digits))
         : StringFormat("đóng %s", DoubleToString(giaDong, _Digits));

      bool reasonRo = (reason == DEAL_REASON_TP || reason == DEAL_REASON_SL);

      SendChiTiet(StringFormat(
         "🔎 %s · %s · %s lot%s\n"
         "%s P&L: %s$  ·  💳 Balance: %s$",
         (magic == g_srcAdj.magic) ? g_srcAdj.tag : g_srcLM.tag,
         moTaP,
         DoubleToString(lotDong, 2),
         reasonRo ? "" : ("\n📝 " + reasonTxt),
         pnl >= 0 ? "💰" : "💸",
         DoubleToString(pnl, 2),
         DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)));
      return;
   }

   // --- Chế độ CŨ (Inp_TG_TinPublic tắt): giữ nguyên tin đầy đủ của bản 1.62 ---
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
      lines[n] = StringFormat("CRT · Mode NẾN QUÉT · Gốc %s · Quét %s",
                     TFToString(Inp_HTF), TFToString(Inp_LTF));
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
         string vaoTF = TFToString(Inp_LTF);
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
   // [v1.75] Bỏ phần "lệnh/vòng" và "vòng" trên dashboard: hai hạn mức đó thuộc Mode 1,
   // đã gỡ. Mode nến quét bị chặn bởi luật mạnh hơn — 1 phía biên = đúng 1 cặp lệnh.
   return StringFormat("[%s] %s · đang mở %d", s.tag, armTxt, CountEAPositions(s.magic));
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
//| [1.68] GHI HÀNH TRÌNH TỪNG LỆNH (chỉ trong Strategy Tester)      |
//|                                                                   |
//| Vì sao cần: TP và BE chỉ đổi cách THOÁT lệnh. Nếu biết hành trình |
//| giá của từng lệnh thì tính ngược ra được kết quả của MỌI mức TP   |
//| và MỌI mốc BE từ đúng một lượt chạy, thay vì quét hàng chục lượt. |
//|                                                                   |
//| Mỗi lệnh đóng ghi 1 dòng CSV: MFE/MAE, chạm các mốc 10/20/30/50/  |
//| 100 pip lúc nào, và sau khi chạm mốc đó giá có QUAY VỀ ENTRY hay  |
//| không — đúng câu hỏi "chạy 30 pip rồi quay đầu cắn entry".        |
//|                                                                   |
//| Không đụng gì tới logic vào lệnh. Tắt mặc định.                   |
//+------------------------------------------------------------------+
// Mốc lãi (pip) được theo dõi. Càng nhiều mốc thì từ MỘT lượt chạy càng mô phỏng offline
// được nhiều mức TP và nhiều mốc BE. Mốc lớn nhất phải <= TP đặt trong lượt ghi hành
// trình, vì quá TP thì lệnh đã đóng, không quan sát được nữa.
#define HT_SO_MOC 9
const double HT_MOC_PIP[HT_SO_MOC] = {10, 20, 30, 50, 80, 100, 150, 200, 300};

struct SHanhTrinh
{
   ulong    ticket, posId;
   long     magic;
   int      dir;
   datetime tVao;
   double   giaVao, slGoc, R_pip;
   double   mfe_pip, mae_pip;
   bool     chamMoc[HT_SO_MOC];
   int      phutToiMoc[HT_SO_MOC];
   bool     veEntrySauMoc[HT_SO_MOC];
   // Ghi cả THỜI ĐIỂM quay về entry, không chỉ có/không. Lý do: để mô phỏng BE offline
   // phải biết giá quay về entry TRƯỚC hay SAU khi chạm mức TP đang xét — chỉ có cờ
   // có/không thì không xếp được thứ tự hai sự kiện, mô phỏng sẽ đoán mò.
   int      phutVeEntry[HT_SO_MOC];
};

SHanhTrinh g_ht[];
int        g_htFile = INVALID_HANDLE;

bool HT_Bat() { return (Inp_Ghi_HanhTrinh && MQLInfoInteger(MQL_TESTER)); }

void HT_MoFile()
{
   if(g_htFile != INVALID_HANDLE) return;
   string ten = StringFormat("CRT_HT_%s_%s_%s.csv", _Symbol,
                             TFToString(Inp_HTF), TFToString(Inp_LTF));
   // FILE_COMMON là BẮT BUỘC: trong Strategy Tester, FileOpen không kèm cờ này sẽ ghi vào
   // hộp cát riêng của agent (%APPDATA%\MetaQuotes\Tester\<GUID>\Agent-...\MQL5\Files),
   // không phải MQL5\Files của terminal — chạy xong không thấy file đâu.
   // Có FILE_COMMON thì file nằm ở %APPDATA%\MetaQuotes\Terminal\Common\Files.
   g_htFile = FileOpen(ten, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(g_htFile == INVALID_HANDLE)
   {
      PrintFormat("[CRT][HT] KHÔNG mở được file %s (lỗi %d) — tắt ghi hành trình.", ten, GetLastError());
      return;
   }
   // Header dựng động theo HT_MOC_PIP, viết thẳng bằng FileWriteString để số cột đổi
   // theo số mốc mà không phải sửa tay.
   string h = "time_vao,time_dong,chieu,nguon,gia_vao,sl_goc,R_pip,mfe_pip,mae_pip,mfe_R,mae_R";
   for(int m = 0; m < HT_SO_MOC; m++)
   {
      string p = DoubleToString(HT_MOC_PIP[m], 0);
      h += ",cham" + p + ",phut" + p + ",phut_ve_entry_" + p;
   }
   h += ",ket_cuc,lai_usd,phut_giu\r\n";
   FileWriteString(g_htFile, h);
   PrintFormat("[CRT][HT] Ghi hành trình vào <Terminal>/Common/Files/%s", ten);
}

int HT_Tim(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_ht); i++)
      if(g_ht[i].ticket == ticket) return i;
   return -1;
}

void HT_Xoa(int idx)
{
   int n = ArraySize(g_ht);
   for(int i = idx; i < n - 1; i++) g_ht[i] = g_ht[i + 1];
   ArrayResize(g_ht, n - 1);
}

void HT_GhiDong(const SHanhTrinh &h, datetime tDong, string ketCuc, double lai)
{
   if(g_htFile == INVALID_HANDLE) return;
   string d = TimeToString(h.tVao, TIME_DATE | TIME_MINUTES) + ","
            + TimeToString(tDong, TIME_DATE | TIME_MINUTES) + ","
            + (h.dir > 0 ? "BUY" : "SELL") + ","
            + (h.magic == Inp_MagicNumber ? "LienKe" : "Swing") + ","
            + DoubleToString(h.giaVao, _Digits) + "," + DoubleToString(h.slGoc, _Digits) + ","
            + DoubleToString(h.R_pip, 1) + "," + DoubleToString(h.mfe_pip, 1) + ","
            + DoubleToString(h.mae_pip, 1) + ","
            + DoubleToString(h.R_pip > 0 ? h.mfe_pip / h.R_pip : 0, 2) + ","
            + DoubleToString(h.R_pip > 0 ? h.mae_pip / h.R_pip : 0, 2);
   for(int i = 0; i < HT_SO_MOC; i++)
   {
      // Rỗng = chưa chạm mốc · "-" = chạm mốc nhưng KHÔNG quay về entry · số = phút quay về.
      d += "," + (h.chamMoc[i] ? "1" : "0")
         + "," + (h.chamMoc[i] ? IntegerToString(h.phutToiMoc[i]) : "")
         + "," + (h.chamMoc[i] ? (h.veEntrySauMoc[i] ? IntegerToString(h.phutVeEntry[i]) : "-") : "");
   }
   d += "," + ketCuc + "," + DoubleToString(lai, 2)
      + "," + IntegerToString((int)((tDong - h.tVao) / 60)) + "\r\n";
   FileWriteString(g_htFile, d);
}

// Đọc kết cục của vị thế đã đóng. DEAL_REASON nói rõ SL / TP / lệnh của EA / đóng tay.
void HT_DocKetCuc(ulong posId, datetime &tDong, string &ketCuc, double &lai)
{
   tDong = TimeCurrent(); ketCuc = "?"; lai = 0;
   if(!HistorySelectByPosition(posId)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      lai  += HistoryDealGetDouble(tk, DEAL_PROFIT)
            + HistoryDealGetDouble(tk, DEAL_SWAP)
            + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      tDong = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      long r = HistoryDealGetInteger(tk, DEAL_REASON);
      ketCuc = (r == DEAL_REASON_SL) ? "SL" : (r == DEAL_REASON_TP) ? "TP"
             : (r == DEAL_REASON_EXPERT) ? "BOT_DONG" : "KHAC";
   }
}

// Gọi mỗi tick. Theo dõi vị thế đang mở, và ghi dòng khi vị thế biến mất.
void HT_CapNhat()
{
   if(!HT_Bat()) return;
   HT_MoFile();
   if(g_htFile == INVALID_HANDLE) return;

   double pip = GetPipSize();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 1. Vị thế đang mở: thêm mới hoặc cập nhật hành trình.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(!IsBotMagic(mg)) continue;

      int idx = HT_Tim(tk);
      if(idx < 0)
      {
         SHanhTrinh h;
         ZeroMemory(h);
         h.ticket = tk;
         h.posId  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         h.magic  = mg;
         h.dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         h.tVao   = (datetime)PositionGetInteger(POSITION_TIME);
         h.giaVao = PositionGetDouble(POSITION_PRICE_OPEN);
         h.slGoc  = PositionGetDouble(POSITION_SL);
         h.R_pip  = (h.slGoc > 0) ? MathAbs(h.giaVao - h.slGoc) / pip : 0;
         idx = ArraySize(g_ht);
         ArrayResize(g_ht, idx + 1);
         g_ht[idx] = h;
      }

      // Lãi/lỗ hiện tại tính bằng giá ĐÓNG ĐƯỢC: BUY theo Bid, SELL theo Ask —
      // cùng quy ước với luật hoà vốn 1.67, nếu không sẽ lệch nguyên một spread.
      double fav = (g_ht[idx].dir > 0) ? (bid - g_ht[idx].giaVao) : (g_ht[idx].giaVao - ask);
      double favPip = fav / pip;
      if(favPip > g_ht[idx].mfe_pip) g_ht[idx].mfe_pip = favPip;
      if(-favPip > g_ht[idx].mae_pip) g_ht[idx].mae_pip = -favPip;

      for(int m = 0; m < HT_SO_MOC; m++)
      {
         if(!g_ht[idx].chamMoc[m])
         {
            if(favPip >= HT_MOC_PIP[m])
            {
               g_ht[idx].chamMoc[m]    = true;
               g_ht[idx].phutToiMoc[m] = (int)((TimeCurrent() - g_ht[idx].tVao) / 60);
            }
         }
         else if(!g_ht[idx].veEntrySauMoc[m] && favPip <= 0)
         {
            // Đã chạy được mốc đó rồi quay về cắn entry — ghi luôn phút xảy ra.
            g_ht[idx].veEntrySauMoc[m] = true;
            g_ht[idx].phutVeEntry[m]   = (int)((TimeCurrent() - g_ht[idx].tVao) / 60);
         }
      }
   }

   // 2. Vị thế đã biến mất khỏi danh sách -> đã đóng, ghi dòng rồi bỏ khỏi mảng.
   for(int i = ArraySize(g_ht) - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(g_ht[i].ticket)) continue;
      datetime tDong; string ketCuc; double lai;
      HT_DocKetCuc(g_ht[i].posId, tDong, ketCuc, lai);
      HT_GhiDong(g_ht[i], tDong, ketCuc, lai);
      HT_Xoa(i);
   }
}

// Cuối lượt chạy: ghi nốt các lệnh còn mở rồi đóng file.
void HT_Ketthuc()
{
   if(g_htFile == INVALID_HANDLE) return;
   for(int i = ArraySize(g_ht) - 1; i >= 0; i--)
      HT_GhiDong(g_ht[i], TimeCurrent(), "CON_MO", 0);
   ArrayResize(g_ht, 0);
   FileClose(g_htFile);
   g_htFile = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| [1.68] OnTester — CHỈ tồn tại trong Strategy Tester. MQL5 không   |
//| gọi hàm này khi EA chạy thật, nên phần dưới KHÔNG ảnh hưởng bot   |
//| đang chạy trên tài khoản/VPS.                                     |
//|                                                                   |
//| Hai việc:                                                         |
//|  1. In bảng thống kê (tiền tố [TESTER] để Summarize-Backtest.ps1  |
//|     bóc được), tách theo nguồn biên và theo chiều lệnh, KÈM SAI   |
//|     SỐ của kỳ vọng mỗi lệnh — không có sai số thì không biết một  |
//|     cấu hình "tốt hơn" là thật hay chỉ là may rủi.                |
//|  2. Trả điểm cho chế độ Optimization (OptimizationCriterion=6).   |
//+------------------------------------------------------------------+
struct SNhomTester
{
   string ten;
   int    n, thang;
   double tong, lai, lo;
};

void CongVaoNhom(SNhomTester &g, double profit)
{
   g.n++;
   g.tong += profit;
   if(profit >= 0) { g.thang++; g.lai += profit; }
   else            { g.lo += -profit; }
}

void InNhomTester(const SNhomTester &g)
{
   if(g.n == 0) { PrintFormat("[TESTER] %-16s | 0 lệnh", g.ten); return; }
   double pf = (g.lo > 0) ? g.lai / g.lo : 0;
   PrintFormat("[TESTER] %-16s | %4d lệnh | thắng %5.1f%% | tổng %+10.2f | TB/lệnh %+7.2f | PF %.2f",
               g.ten, g.n, g.thang * 100.0 / g.n, g.tong, g.tong / g.n, pf);
}

double OnTester()
{
   double dep    = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double net    = TesterStatistics(STAT_PROFIT);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double trades = TesterStatistics(STAT_TRADES);
   double ddeq   = TesterStatistics(STAT_EQUITYDD_PERCENT);
   double ddrel  = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double maxdd  = MathMax(ddeq, ddrel);

   SNhomTester gAll, gLK, gSW, gBuy, gSell;
   ZeroMemory(gAll); ZeroMemory(gLK); ZeroMemory(gSW); ZeroMemory(gBuy); ZeroMemory(gSell);
   gAll.ten = "TẤT CẢ"; gLK.ten = "Nguồn LiềnKề"; gSW.ten = "Nguồn Swing";
   gBuy.ten = "Lệnh BUY"; gSell.ten = "Lệnh SELL";

   // Gom từng lệnh đã đóng. Tổng bình phương để tính SAI SỐ của kỳ vọng mỗi lệnh.
   double tongBp = 0;
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT)      continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)             continue;
      long mg = HistoryDealGetInteger(tk, DEAL_MAGIC);
      if(!IsBotMagic(mg))                                              continue;

      double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
               + HistoryDealGetDouble(tk, DEAL_SWAP)
               + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      CongVaoNhom(gAll, p);
      tongBp += p * p;
      if(mg == Inp_MagicNumber) CongVaoNhom(gLK, p); else CongVaoNhom(gSW, p);
      // Deal ĐÓNG mang chiều NGƯỢC với vị thế: đóng lệnh BUY sinh ra deal SELL.
      if(HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_SELL) CongVaoNhom(gBuy, p);
      else                                                       CongVaoNhom(gSell, p);
   }

   Print("[TESTER] ================= THỐNG KÊ TỔNG =================");
   PrintFormat("[TESTER] Vốn đầu %.2f | Lãi ròng %+.2f (%+.2f%%) | Sụt vốn tối đa %.2f%% | PF %.2f | Kỳ vọng/lệnh %+.2f | %d lệnh",
               dep, net, (dep > 0 ? net / dep * 100.0 : 0), maxdd, pf, payoff, (int)trades);

   // Kỳ vọng mỗi lệnh KÈM SAI SỐ: |t| < 2 nghĩa là kết quả chưa phân biệt được với ngẫu nhiên.
   double tb = 0, se = 0, t = 0;
   if(gAll.n > 1)
   {
      tb = gAll.tong / gAll.n;
      double phuongSai = MathMax(tongBp / gAll.n - tb * tb, 0.0);
      se = MathSqrt(phuongSai / gAll.n);
      t  = (se > 0) ? tb / se : 0;
   }
   PrintFormat("[TESTER] TB/lệnh %+.2f ± %.2f (sai số) -> t = %+.2f %s",
               tb, se, t, (MathAbs(t) < 2.0 ? "· CHƯA phân biệt được với ngẫu nhiên" : "· có ý nghĩa thống kê"));

   Print("[TESTER] ---------------- TÁCH NHÓM ----------------");
   InNhomTester(gAll); InNhomTester(gLK); InNhomTester(gSW); InNhomTester(gBuy); InNhomTester(gSell);

   // --- Điểm cho chế độ Optimization ---
   // Lãi thuần KHÔNG dùng làm tiêu chí: nó luôn chọn cấu hình liều nhất. Dùng lãi/sụt vốn,
   // rồi phạt cấu hình quá ít lệnh — ít lệnh thì con số đẹp mấy cũng là may rủi.
   if(trades < 30)
   {
      Print("[TESTER] Điểm tối ưu = -1000000 (dưới 30 lệnh, không đủ để kết luận).");
      return -1000000.0;
   }
   double laiPct = (dep > 0) ? net / dep * 100.0 : 0;
   double diem   = laiPct / MathMax(maxdd, 1.0);
   if(trades < 100) diem *= trades / 100.0;
   PrintFormat("[TESTER] Điểm tối ưu = %.3f (lãi %.2f%% / sụt vốn %.2f%%%s)",
               diem, laiPct, MathMax(maxdd, 1.0),
               (trades < 100 ? StringFormat(", phạt vì chỉ %d lệnh", (int)trades) : ""));
   return diem;
}
//+------------------------------------------------------------------+
