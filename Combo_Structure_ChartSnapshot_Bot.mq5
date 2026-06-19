//+------------------------------------------------------------------+
//|                          Combo_Structure_ChartSnapshot_Bot.mq5   |
//| Mục đích duy nhất: gửi ảnh chụp chart (kèm chỉ báo Combo_Structure|
//| _MajorSwing_HA_BOS_Zone_Anchor) về Telegram theo lệnh /chart_XX  |
//| (M1/M5/M15/M30/H1/H4/D). Bot này KHÔNG đặt lệnh, KHÔNG quản lý   |
//| vị thế — chỉ lấy chart.                                          |
//|                                                                   |
//| Lưu ý kiến trúc: KHÔNG đổi timeframe của chart đang chạy EA này, |
//| vì MT5 sẽ coi đó là đổi timeframe thủ công và tự unload/reload   |
//| lại toàn bộ EA giữa luồng xử lý (gây lỗi 4102 liên tục). Thay    |
//| vào đó, mỗi timeframe được mở trên 1 chart riêng (ChartOpen),    |
//| mở 1 lần rồi giữ nguyên để các lần sau chụp nhanh, không đụng gì |
//| tới chart gốc đang chạy EA.                                      |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & Quân (anhtuan02t1)"
#property version   "2.00"

#include <Telegram_ChartBot.mqh>
CTelegramChartBot Radar;

input group "--- Telegram Settings ---"
input string Inp_BotToken      = "8953133302:AAHnKSoe-PRHItjGb1MTugmBroeru3Ip0ds";
input string Inp_ChatID        = "-5499770162";

input group "--- Indicator Settings ---"
// Tên file indicator tính theo thư mục MQL5\Indicators\ (KHÔNG kèm đuôi .ex5)
input string Inp_IndicatorPath = "Combo_Structure_MajorSwing_HA_BOS_Zone_Anchor";

input group "--- Screenshot Settings ---"
input int    Inp_ScreenshotWidth  = 1280;
input int    Inp_ScreenshotHeight = 720;
input int    Inp_ChartReadyWaitMs = 3000; // thời gian tối đa chờ nạp dữ liệu khi mở chart mới

// ==================================================================
// STATE
// ==================================================================
long  g_tg_last_update_id = 0;
ulong g_tg_last_poll_ms   = 0;

// Cache: 1 chart riêng cho mỗi timeframe, mở 1 lần và giữ nguyên
ENUM_TIMEFRAMES g_cache_tf[];
long            g_cache_chart_id[];

// ==================================================================
// CHART / INDICATOR HELPERS
// ==================================================================
// Chart vừa mở/vừa đổi nội dung có thể tạm thời chưa "rep" kịp,
// ChartIndicatorAdd trả lỗi 4102 (ERR_CHART_NO_REPLY) — thử lại vài lần.
bool ChartIndicatorAddRetry(long chart_id, int sub_window, int handle, int max_tries = 6, int delay_ms = 400) {
   for(int i = 0; i < max_tries; i++) {
      ResetLastError();
      if(ChartIndicatorAdd(chart_id, sub_window, handle)) return true;
      int err = GetLastError();
      if(err != 4102) { Print("[ChartSnapshotBot] ChartIndicatorAdd lỗi: ", err); return false; }
      Sleep(delay_ms);
   }
   Print("[ChartSnapshotBot] ChartIndicatorAdd vẫn lỗi 4102 sau ", max_tries, " lần thử.");
   return false;
}

void WaitChartReady(ENUM_TIMEFRAMES tf) {
   int waited = 0;
   while(waited < Inp_ChartReadyWaitMs) {
      if(SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED) && Bars(_Symbol, tf) > 300) break;
      Sleep(100);
      waited += 100;
   }
}

// Đảm bảo chart đã có sẵn chỉ báo SMC (tránh gắn trùng nếu chart đã mở từ trước,
// ví dụ do EA bị reload và mất cache trong RAM nhưng chart vẫn còn mở).
void EnsureIndicatorOnChart(long chart_id, ENUM_TIMEFRAMES tf) {
   int total = ChartIndicatorsTotal(chart_id, 0);
   for(int i = 0; i < total; i++) {
      if(StringFind(ChartIndicatorName(chart_id, 0, i), "Combo_Structure_MajorSwing_HA_BOS_Zone_Anchor") >= 0) return;
   }
   int handle = iCustom(_Symbol, tf, Inp_IndicatorPath);
   if(handle == INVALID_HANDLE) {
      Print("[ChartSnapshotBot] Không tạo được handle indicator '", Inp_IndicatorPath, "' | Error: ", GetLastError());
      return;
   }
   if(!ChartIndicatorAddRetry(chart_id, 0, handle)) IndicatorRelease(handle);
}

void RemoveSMCIndicatorFromChart(long chart_id) {
   for(int i = ChartIndicatorsTotal(chart_id, 0) - 1; i >= 0; i--) {
      string nm = ChartIndicatorName(chart_id, 0, i);
      if(StringFind(nm, "Combo_Structure_MajorSwing_HA_BOS_Zone_Anchor") >= 0) ChartIndicatorDelete(chart_id, 0, nm);
   }
}

// Lấy chart riêng cho 1 timeframe — mở mới nếu chưa có, dùng lại nếu đã mở.
long GetOrCreateChartForTF(ENUM_TIMEFRAMES tf) {
   for(int i = 0; i < ArraySize(g_cache_tf); i++) {
      if(g_cache_tf[i] == tf && ChartSymbol(g_cache_chart_id[i]) != "") {
         EnsureIndicatorOnChart(g_cache_chart_id[i], tf);
         return g_cache_chart_id[i];
      }
   }

   long id = ChartOpen(_Symbol, tf);
   if(id == 0) {
      Print("[ChartSnapshotBot] Không mở được chart cho khung ", EnumToString(tf), " | Error: ", GetLastError());
      return 0;
   }

   // Chart vừa mở cần thời gian "ổn định" trước khi gắn indicator — gắn quá sớm
   // khiến indicator không bind đúng chart, dẫn đến không vẽ được BOS/CHOCH/Zone
   // (chỉ hết khi người dùng tự bấm "Reset" tay). Đợi rồi gắn — tính toán xong —
   // gỡ ra gắn lại 1 lần (tự "Reset") để đảm bảo vẽ đủ toàn bộ lịch sử.
   WaitChartReady(tf);
   Sleep(1500);

   EnsureIndicatorOnChart(id, tf);
   ChartRedraw(id);
   Sleep(1500);

   RemoveSMCIndicatorFromChart(id);
   EnsureIndicatorOnChart(id, tf);
   ChartRedraw(id);
   Sleep(1500);

   int n = ArraySize(g_cache_tf);
   ArrayResize(g_cache_tf, n + 1);
   ArrayResize(g_cache_chart_id, n + 1);
   g_cache_tf[n]       = tf;
   g_cache_chart_id[n] = id;
   return id;
}

// ==================================================================
// COMMAND -> TIMEFRAME MAP
// ==================================================================
// cmd đã được chuyển về chữ thường ở ProcessCommand trước khi vào đây —
// để khớp được với lệnh menu BotFather (Telegram bắt buộc lệnh menu viết thường).
bool MapCommandToTF(string cmd, ENUM_TIMEFRAMES &tf, string &label) {
   if(cmd == "/chart_m1")               { tf = PERIOD_M1;  label = "M1";  return true; }
   if(cmd == "/chart_m5")               { tf = PERIOD_M5;  label = "M5";  return true; }
   if(cmd == "/chart_m15")              { tf = PERIOD_M15; label = "M15"; return true; }
   if(cmd == "/chart_m30")              { tf = PERIOD_M30; label = "M30"; return true; }
   if(cmd == "/chart_h1")               { tf = PERIOD_H1;  label = "H1";  return true; }
   if(cmd == "/chart_h4")               { tf = PERIOD_H4;  label = "H4";  return true; }
   if(cmd == "/chart_d" || cmd == "/chart_d1") { tf = PERIOD_D1; label = "D1"; return true; }
   return false;
}

void SendChartForTF(ENUM_TIMEFRAMES tf, string label) {
   long chart_id = GetOrCreateChartForTF(tf);
   if(chart_id == 0) {
      Radar.SendMessage("⚠️ Không thể mở chart cho khung " + label);
      return;
   }

   ChartRedraw(chart_id);
   Sleep(300);

   string caption = "📸 <b>" + _Symbol + " — " + label + "</b>\n🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   Radar.SendPhoto(chart_id, caption, Inp_ScreenshotWidth, Inp_ScreenshotHeight);
}

// Custom keyboard: hiện sẵn nút bấm dưới khung chat, bấm là gửi đúng lệnh — khỏi gõ tay.
const string KEYBOARD_JSON =
   "{\"keyboard\":["
   "[\"/chart_M1\",\"/chart_M5\",\"/chart_M15\",\"/chart_M30\"],"
   "[\"/chart_H1\",\"/chart_H4\",\"/chart_D\",\"/help\"]"
   "],\"resize_keyboard\":true,\"is_persistent\":true}";

void SendHelp() {
   Radar.SendMessage(
      "📋 <b>Lệnh lấy chart:</b>\n"
      "/chart_M1\n/chart_M5\n/chart_M15\n/chart_M30\n/chart_H1\n/chart_H4\n/chart_D"
      , KEYBOARD_JSON
   );
}

void ProcessCommand(string cmd) {
   int at = StringFind(cmd, "@");
   if(at > 0) cmd = StringSubstr(cmd, 0, at);
   StringToLower(cmd);

   ENUM_TIMEFRAMES tf; string label;
   if(MapCommandToTF(cmd, tf, label)) { SendChartForTF(tf, label); return; }

   if(cmd == "/start" || cmd == "/help") SendHelp();
}

// ==================================================================
// TELEGRAM POLLING (long-poll getUpdates, không phụ thuộc tick giá)
// ==================================================================
void CheckTelegramCommands() {
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!Radar.IsConfigured()) return;
   if(GetTickCount64() - g_tg_last_poll_ms < 3000) return;
   g_tg_last_poll_ms = GetTickCount64();

   string url = "https://api.telegram.org/bot" + Inp_BotToken
              + "/getUpdates?offset=" + (string)(g_tg_last_update_id + 1) + "&limit=10&timeout=0";
   char post[], result[];
   string headers;
   ResetLastError();
   if(WebRequest("GET", url, "", 5000, post, result, headers) != 200) return;

   string json = CharArrayToString(result);
   if(StringFind(json, "\"ok\":true") < 0) return;

   int pos = 0;
   while(true) {
      int uid_pos = StringFind(json, "\"update_id\":", pos);
      if(uid_pos < 0) break;

      int n = uid_pos + 12;
      int n_end = n;
      while(n_end < StringLen(json) && StringGetCharacter(json, n_end) >= '0' && StringGetCharacter(json, n_end) <= '9') n_end++;
      long uid = (long)StringSubstr(json, n, n_end - n);
      if(uid > g_tg_last_update_id) g_tg_last_update_id = uid;

      int next_uid = StringFind(json, "\"update_id\":", n_end);
      int blk_end  = (next_uid > 0) ? next_uid : StringLen(json);
      string blk   = StringSubstr(json, uid_pos, blk_end - uid_pos);

      // Nếu tin nhắn là REPLY tới 1 tin cũ, "reply_to_message" lồng vào trước
      // và cũng có field "text" riêng — phải lấy "text" CUỐI CÙNG (của tin
      // nhắn thật ngoài cùng), không lấy cái đầu tiên (sẽ là tin bị reply tới).
      string text = "";
      int search_from = 0, last_tp = -1;
      while(true) {
         int tp = StringFind(blk, "\"text\":\"", search_from);
         if(tp < 0) break;
         last_tp = tp;
         search_from = tp + 8;
      }
      if(last_tp >= 0) {
         int ts = last_tp + 8, te = StringFind(blk, "\"", ts);
         if(te > ts) text = StringSubstr(blk, ts, te - ts);
      }

      string chat_id_str = "";
      int cp = StringFind(blk, "\"chat\":{\"id\":");
      if(cp >= 0) {
         int cs = cp + 13, ce = cs;
         if(StringGetCharacter(blk, ce) == '-') ce++;
         while(ce < StringLen(blk) && StringGetCharacter(blk, ce) >= '0' && StringGetCharacter(blk, ce) <= '9') ce++;
         chat_id_str = StringSubstr(blk, cs, ce - cs);
      }

      if(text != "") {
         Print("[ChartSnapshotBot] Nhận tin: '", text, "' | chat_id nhận: '", chat_id_str, "' | chat_id cấu hình: '", Inp_ChatID, "'");
         if(chat_id_str == Inp_ChatID) ProcessCommand(text);
      }

      pos = blk_end;
   }
}

// ==================================================================
// LIFECYCLE
// ==================================================================
// Mỗi lần EA reload, bỏ qua toàn bộ update cũ còn tồn đọng — chỉ phản hồi
// lệnh gửi SAU thời điểm khởi động này, tránh phải "đuổi" qua hàng tồn cũ
// (giới hạn 10 update/lần) mới tới được lệnh mới nhất của người dùng.
void SkipPendingTelegramUpdates() {
   if(!Radar.IsConfigured()) return;
   string url = "https://api.telegram.org/bot" + Inp_BotToken + "/getUpdates?offset=-1&limit=1";
   char post[], result[];
   string headers;
   ResetLastError();
   if(WebRequest("GET", url, "", 5000, post, result, headers) != 200) return;
   string json = CharArrayToString(result);
   int uid_pos = StringFind(json, "\"update_id\":");
   if(uid_pos < 0) return;
   int n = uid_pos + 12, n_end = n;
   while(n_end < StringLen(json) && StringGetCharacter(json, n_end) >= '0' && StringGetCharacter(json, n_end) <= '9') n_end++;
   long uid = (long)StringSubstr(json, n, n_end - n);
   if(uid > g_tg_last_update_id) g_tg_last_update_id = uid;
}

int OnInit() {
   Radar.Init(Inp_BotToken, Inp_ChatID);
   SkipPendingTelegramUpdates();
   EventSetTimer(3);
   Radar.SendMessage("🟢 <b>Chart Snapshot Bot đã khởi động</b>\n" + _Symbol + " | Chỉ dùng để lấy chart, không giao dịch.\nBấm nút bên dưới để chọn khung thời gian.", KEYBOARD_JSON);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   // Không đóng các chart đã mở cho từng timeframe — giữ lại để xem tay
   // hoặc để lần sau gắn EA lại không phải tải lịch sử từ đầu.
}

void OnTick() {
   // Bot này không giao dịch, không có logic gì chạy theo tick.
}

void OnTimer() {
   CheckTelegramCommands();
}
//+------------------------------------------------------------------+
