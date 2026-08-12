//+------------------------------------------------------------------+
//|                          Combo_Structure_ChartSnapshot_Bot.mq5   |
//| Mục đích: gửi ảnh chụp chart (kèm chỉ báo TLS_SMC_Indicator) về  |
//| Telegram theo lệnh /chart_XX, và tự động báo khi giá chạm Zone   |
//| Buy/Sell (Inp_EnableZoneAlert). Bot này KHÔNG đặt lệnh, KHÔNG    |
//| quản lý vị thế.                                                  |
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
input string Inp_ChatID        = "-1004485122634"; // Group Telegram đã được nâng cấp thành supergroup -> chat_id cũ "-5499770162" không còn dùng được

input group "--- Indicator Settings ---"
// Tên file indicator tính theo thư mục MQL5\Indicators\ (KHÔNG kèm đuôi .ex5)
input string Inp_IndicatorPath = "TLS_SMC_Indicator";

input group "--- Screenshot Settings ---"
input int    Inp_ScreenshotWidth  = 1280;
input int    Inp_ScreenshotHeight = 720;
input int    Inp_ChartReadyWaitMs = 3000; // thời gian tối đa chờ nạp dữ liệu khi mở chart mới

input group "--- Timeframe Filter ---"
input string Inp_EnabledTF = "M1,M5,M15,M30,H1,H4,D1"; // TF được phép lấy chart (vd "M5,H4"). Trống = tất cả

input group "--- Zone Alert Settings ---"
input bool   Inp_EnableZoneAlert = true; // Tự động báo Telegram khi giá chạm Zone Buy/Sell (áp dụng cho các TF trong Inp_EnabledTF)

// ==================================================================
// STATE
// ==================================================================
long  g_tg_last_update_id = 0;
ulong g_tg_last_poll_ms   = 0;

// Cache: 1 chart riêng cho mỗi timeframe, mở 1 lần và giữ nguyên
ENUM_TIMEFRAMES g_cache_tf[];
long            g_cache_chart_id[];

// Danh sách TF được bật (parse từ Inp_EnabledTF) + bàn phím Telegram dựng theo đó
ENUM_TIMEFRAMES g_enabled_tf[];
string          g_enabled_label[];
string          g_keyboard_json;

// Handle indicator riêng cho Zone Alert — chỉ để CopyBuffer, KHÔNG cần mở chart
// (khác với g_cache_chart_id vốn phải mở chart thật để chụp ảnh).
ENUM_TIMEFRAMES g_zone_handle_tf[];
int             g_zone_handle[];

// Trạng thái Zone theo từng phần tử của g_enabled_tf (song song index) — lưu Entry/SL
// của Zone hiện tại để phát hiện khi Zone đổi (reset cờ đã báo) và cờ "đã báo" để
// mỗi Zone chỉ báo 1 lần, tránh spam Telegram mỗi khi timer chạy trong lúc giá còn nằm trong Zone.
bool   g_zone_buy_alerted[];
double g_zone_buy_entry[];
double g_zone_buy_stop[];
bool   g_zone_sell_alerted[];
double g_zone_sell_entry[];
double g_zone_sell_stop[];

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
      if(StringFind(ChartIndicatorName(chart_id, 0, i), "TLS_SMC_Indicator") >= 0) return;
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
      if(StringFind(nm, "TLS_SMC_Indicator") >= 0) ChartIndicatorDelete(chart_id, 0, nm);
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

// ==================================================================
// TIMEFRAME FILTER (Inp_EnabledTF)
// ==================================================================
bool LabelToTF(string label, ENUM_TIMEFRAMES &tf) {
   if(label == "M1")  { tf = PERIOD_M1;  return true; }
   if(label == "M5")  { tf = PERIOD_M5;  return true; }
   if(label == "M15") { tf = PERIOD_M15; return true; }
   if(label == "M30") { tf = PERIOD_M30; return true; }
   if(label == "H1")  { tf = PERIOD_H1;  return true; }
   if(label == "H4")  { tf = PERIOD_H4;  return true; }
   if(label == "D" || label == "D1") { tf = PERIOD_D1; return true; }
   return false;
}

// Parse Inp_EnabledTF ("M5,H4") -> g_enabled_tf[]/g_enabled_label[]. Rỗng = cho phép tất cả
// (giữ hành vi cũ cho các bot chưa cấu hình input này).
void BuildEnabledTFList() {
   ArrayFree(g_enabled_tf);
   ArrayFree(g_enabled_label);

   string src = Inp_EnabledTF;
   StringTrimLeft(src);
   StringTrimRight(src);
   if(src == "") src = "M1,M5,M15,M30,H1,H4,D1";

   string parts[];
   int n = StringSplit(src, ',', parts);
   for(int i = 0; i < n; i++) {
      string tok = parts[i];
      StringTrimLeft(tok);
      StringTrimRight(tok);
      StringToUpper(tok);
      if(tok == "") continue;

      ENUM_TIMEFRAMES tf;
      if(!LabelToTF(tok, tf)) {
         Print("[ChartSnapshotBot] Bỏ qua TF không hợp lệ trong Inp_EnabledTF: '", tok, "'");
         continue;
      }
      string label = (tok == "D") ? "D1" : tok;

      bool dup = false;
      for(int j = 0; j < ArraySize(g_enabled_tf); j++) if(g_enabled_tf[j] == tf) { dup = true; break; }
      if(dup) continue;

      int m = ArraySize(g_enabled_tf);
      ArrayResize(g_enabled_tf, m + 1);
      ArrayResize(g_enabled_label, m + 1);
      g_enabled_tf[m]    = tf;
      g_enabled_label[m] = label;
   }

   if(ArraySize(g_enabled_tf) == 0)
      Print("[ChartSnapshotBot] CẢNH BÁO: Inp_EnabledTF không có TF hợp lệ nào — bot sẽ không phản hồi lệnh /chart_xx nào.");

   // Zone Alert dùng chung danh sách TF này — reset trạng thái theo dõi song song với g_enabled_tf.
   int cnt = ArraySize(g_enabled_tf);
   ArrayResize(g_zone_buy_alerted, cnt);  ArrayResize(g_zone_buy_entry, cnt);  ArrayResize(g_zone_buy_stop, cnt);
   ArrayResize(g_zone_sell_alerted, cnt); ArrayResize(g_zone_sell_entry, cnt); ArrayResize(g_zone_sell_stop, cnt);
   for(int i = 0; i < cnt; i++) {
      g_zone_buy_alerted[i]  = false; g_zone_buy_entry[i]  = EMPTY_VALUE; g_zone_buy_stop[i]  = EMPTY_VALUE;
      g_zone_sell_alerted[i] = false; g_zone_sell_entry[i] = EMPTY_VALUE; g_zone_sell_stop[i] = EMPTY_VALUE;
   }
}

// ==================================================================
// ZONE ALERT (báo Telegram khi giá chạm Zone Buy/Sell của Combo_Structure)
// ==================================================================
// Handle riêng, không mở chart — CopyBuffer đọc được giá trị buffer bất kể chart
// có tồn tại hay không, nên không cần trả giá tài nguyên của việc mở cả cửa sổ chart.
int GetOrCreateZoneHandle(ENUM_TIMEFRAMES tf) {
   for(int i = 0; i < ArraySize(g_zone_handle_tf); i++)
      if(g_zone_handle_tf[i] == tf) return g_zone_handle[i];

   int handle = iCustom(_Symbol, tf, Inp_IndicatorPath);
   if(handle == INVALID_HANDLE) {
      Print("[ChartSnapshotBot] Không tạo được handle Zone cho khung ", EnumToString(tf), " | Error: ", GetLastError());
      return INVALID_HANDLE;
   }
   int n = ArraySize(g_zone_handle_tf);
   ArrayResize(g_zone_handle_tf, n + 1);
   ArrayResize(g_zone_handle, n + 1);
   g_zone_handle_tf[n] = tf;
   g_zone_handle[n]    = handle;
   return handle;
}

void ReleaseZoneHandles() {
   for(int i = 0; i < ArraySize(g_zone_handle); i++)
      if(g_zone_handle[i] != INVALID_HANDLE) IndicatorRelease(g_zone_handle[i]);
   ArrayFree(g_zone_handle_tf);
   ArrayFree(g_zone_handle);
}

// Buffer 18/19 = Buy Zone Entry/SL, buffer 20/21 = Sell Zone SL/Entry (xem SetIndexBuffer
// trong TLS_SMC_Indicator.mq5). "Chạm Zone" = giá nằm trong khoảng [min(Entry,SL), max(Entry,SL)].
void CheckZoneTouches() {
   if(!Inp_EnableZoneAlert) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf[1];

   for(int i = 0; i < ArraySize(g_enabled_tf); i++) {
      int handle = GetOrCreateZoneHandle(g_enabled_tf[i]);
      if(handle == INVALID_HANDLE) continue;

      double buyEntry = EMPTY_VALUE, buyStop = EMPTY_VALUE, sellStop = EMPTY_VALUE, sellEntry = EMPTY_VALUE;
      if(CopyBuffer(handle, 18, 0, 1, buf) > 0) buyEntry  = buf[0];
      if(CopyBuffer(handle, 19, 0, 1, buf) > 0) buyStop   = buf[0];
      if(CopyBuffer(handle, 20, 0, 1, buf) > 0) sellStop  = buf[0];
      if(CopyBuffer(handle, 21, 0, 1, buf) > 0) sellEntry = buf[0];

      // Buy zone
      if(buyEntry != EMPTY_VALUE && buyStop != EMPTY_VALUE) {
         if(g_zone_buy_entry[i] != buyEntry || g_zone_buy_stop[i] != buyStop) {
            // Zone đổi (mới hình thành) -> reset cờ để cho phép báo lại lần chạm đầu tiên của Zone mới.
            g_zone_buy_entry[i] = buyEntry; g_zone_buy_stop[i] = buyStop; g_zone_buy_alerted[i] = false;
         }
         double lo = MathMin(buyEntry, buyStop), hi = MathMax(buyEntry, buyStop);
         if(!g_zone_buy_alerted[i] && bid >= lo && bid <= hi) {
            Radar.SendMessage("🔔 <b>Chạm Zone Buy " + g_enabled_label[i] + "</b> — " + _Symbol
                             + "\nGiá: " + DoubleToString(bid, _Digits));
            g_zone_buy_alerted[i] = true;
         }
      } else {
         g_zone_buy_entry[i] = EMPTY_VALUE; g_zone_buy_stop[i] = EMPTY_VALUE; g_zone_buy_alerted[i] = false;
      }

      // Sell zone
      if(sellEntry != EMPTY_VALUE && sellStop != EMPTY_VALUE) {
         if(g_zone_sell_entry[i] != sellEntry || g_zone_sell_stop[i] != sellStop) {
            g_zone_sell_entry[i] = sellEntry; g_zone_sell_stop[i] = sellStop; g_zone_sell_alerted[i] = false;
         }
         double lo = MathMin(sellEntry, sellStop), hi = MathMax(sellEntry, sellStop);
         if(!g_zone_sell_alerted[i] && bid >= lo && bid <= hi) {
            Radar.SendMessage("🔔 <b>Chạm Zone Sell " + g_enabled_label[i] + "</b> — " + _Symbol
                             + "\nGiá: " + DoubleToString(bid, _Digits));
            g_zone_sell_alerted[i] = true;
         }
      } else {
         g_zone_sell_entry[i] = EMPTY_VALUE; g_zone_sell_stop[i] = EMPTY_VALUE; g_zone_sell_alerted[i] = false;
      }
   }
}

bool IsTFEnabled(ENUM_TIMEFRAMES tf) {
   for(int i = 0; i < ArraySize(g_enabled_tf); i++) if(g_enabled_tf[i] == tf) return true;
   return false;
}

// Dựng bàn phím custom + tối đa 4 nút/hàng, chỉ gồm các TF đang bật.
string BuildKeyboardJson() {
   int n = ArraySize(g_enabled_label);
   string json = "{\"keyboard\":[";
   if(n == 0) {
      json += "[\"/help\"]";
   } else {
      int per_row = 4;
      int i = 0;
      bool first_row = true;
      while(i < n) {
         if(!first_row) json += ",";
         json += "[";
         int row_end = MathMin(i + per_row, n);
         for(int k = i; k < row_end; k++) {
            if(k > i) json += ",";
            json += "\"/chart_" + g_enabled_label[k] + "\"";
         }
         json += "]";
         first_row = false;
         i = row_end;
      }
      json += ",[\"/help\"]";
   }
   json += "],\"resize_keyboard\":true,\"is_persistent\":true}";
   return json;
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

// Bàn phím custom (nút bấm dưới khung chat) — dựng động theo Inp_EnabledTF
// lúc OnInit, lưu vào g_keyboard_json, chỉ hiện nút của các TF bot này hỗ trợ.

void SendHelp() {
   string txt = "📋 <b>Lệnh lấy chart:</b>\n";
   int n = ArraySize(g_enabled_label);
   if(n == 0) txt += "(Chưa có TF nào được bật — kiểm tra input Inp_EnabledTF)";
   else for(int i = 0; i < n; i++) txt += "/chart_" + g_enabled_label[i] + "\n";

   Radar.SendMessage(txt, g_keyboard_json);
}

void ProcessCommand(string cmd) {
   int at = StringFind(cmd, "@");
   if(at > 0) cmd = StringSubstr(cmd, 0, at);
   StringToLower(cmd);

   ENUM_TIMEFRAMES tf; string label;
   if(MapCommandToTF(cmd, tf, label)) {
      if(!IsTFEnabled(tf)) {
         Radar.SendMessage("⚠️ Bot này không hỗ trợ khung " + label + " (xem input Inp_EnabledTF).");
         return;
      }
      SendChartForTF(tf, label);
      return;
   }

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
   BuildEnabledTFList();
   g_keyboard_json = BuildKeyboardJson();
   SkipPendingTelegramUpdates();
   EventSetTimer(3);
   Radar.SendMessage("🟢 <b>Chart Snapshot Bot đã khởi động</b>\n" + _Symbol + " | Chỉ dùng để lấy chart, không giao dịch.\nBấm nút bên dưới để chọn khung thời gian.", g_keyboard_json);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   ReleaseZoneHandles();
   // Không đóng các chart đã mở cho từng timeframe — giữ lại để xem tay
   // hoặc để lần sau gắn EA lại không phải tải lịch sử từ đầu.
}

void OnTick() {
   // Bot này không giao dịch, không có logic gì chạy theo tick.
}

void OnTimer() {
   CheckTelegramCommands();
   CheckZoneTouches();
}
//+------------------------------------------------------------------+
