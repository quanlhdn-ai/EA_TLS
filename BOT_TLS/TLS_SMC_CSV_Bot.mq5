//+------------------------------------------------------------------+
//|                                        TLS_SMC_CSV_Bot.mq5       |
//|                    Base: TLS_SMC_CSV_BOT_TREND v5.0              |
//|                    Add-on: Pool SL, Telegram Remote Control,     |
//|                    Crash Recovery, Close-Retry Queue             |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "1.0"

#include <Trade\Trade.mqh>
#include <CSMC_Engine.mqh>
#include <Telegram_Radar.mqh>

CTrade trade;
CTelegramRadar Radar;

// ==================================================================
// INPUTS
// ==================================================================
input group "--- EA Identification ---"
// Inp_BaseMagicNumber (Magic number gốc của EA, dùng để phân biệt lệnh của bot này với lệnh tay hoặc bot khác)
input long   BaseMagicNumber           = 2026000;

input group "--- Telegram Radar Settings ---"
// Inp_BotToken (Token của Bot Telegram dùng để gửi thông báo)
input string  Inp_BotToken             = "YOUR_BOT_TOKEN_HERE";
// Inp_ChatID (ID của Chat hoặc Group Telegram sẽ nhận thông báo)
input string  Inp_ChatID               = "YOUR_CHAT_ID_HERE";
// Inp_SendScreenshot (Gửi kèm ảnh chụp biểu đồ mỗi khi báo tin)
input bool    Inp_SendScreenshot       = true;

input group "--- Prop Firm Protection ---"
// Inp_UseMarginLimit (Bật giới hạn margin tối đa khi tính khối lượng lệnh)
input bool   Inp_UseMarginLimit        = true;
// Inp_MaxMarginPercent (Tỷ lệ % margin tối đa so với balance được phép dùng, vượt mức sẽ tự cắt giảm lot)
input double Inp_MaxMarginPercent      = 38.0;
// Inp_DailyDrawdownLimit (Tỷ lệ % thua lỗ tối đa trong ngày so với balance đầu phiên, chạm mức này sẽ đóng hết lệnh và dừng giao dịch)
input double Inp_DailyDrawdownLimit    = 3.0;
// Inp_DailyProfitLimit (Tỷ lệ % lợi nhuận mục tiêu trong ngày, đạt mức này sẽ dừng giao dịch; để 0 = không giới hạn)
input double Inp_DailyProfitLimit      = 0.0;
// Inp_AutoPassTarget (Mức equity mục tiêu theo USD, đạt mức này sẽ tự đóng hết lệnh để chốt mục tiêu - Auto Pass)
input double Inp_AutoPassTarget        = 11010.0;
// Inp_NewsTimes (Danh sách giờ tin tức cần tránh giao dịch, định dạng HH:MM theo giờ server, các mốc giờ ngăn cách bằng dấu phẩy)
input string Inp_NewsTimes             = "15:30, 21:00";
// Inp_NewsBufferMinutes (Số phút chặn giao dịch trước và sau mỗi giờ tin trong danh sách Inp_NewsTimes)
input int    Inp_NewsBufferMinutes     = 2;

input group "--- Risk Management & Scaling ---"
// Inp_Max_Risk_Trades (Số lệnh đang mở chưa hòa vốn tối đa cho phép cùng lúc, vượt số này sẽ không vào lệnh mới)
input int    Inp_Max_Risk_Trades       = 3;
// UseRiskPerTrade (true = tính khối lượng lệnh theo % rủi ro của balance, false = dùng khối lượng cố định FixedLotSize)
input bool   UseRiskPerTrade           = true;
// RiskPercent (Tỷ lệ % balance chấp nhận rủi ro cho mỗi lệnh, chỉ áp dụng khi UseRiskPerTrade = true)
input double RiskPercent               = 0.5;
// FixedLotSize (Khối lượng lệnh cố định tính bằng lot, chỉ áp dụng khi UseRiskPerTrade = false)
input double FixedLotSize              = 0.05;
// SL_Buffer_Pips (Số pip đệm thêm ra ngoài mức SL gốc lấy từ zone, để tránh bị quét SL)
input double SL_Buffer_Pips            = 30.0;
// Inp_No_SL (true = không đặt SL trên sàn, chỉ quản lý SL ảo trong EA - lưu ý rủi ro cao nếu mất kết nối)
input bool   Inp_No_SL                 = false;
// Inp_Pool_SL_Percent (Tỷ lệ % thua lỗ tối đa cho tập lệnh cùng hướng; khi tổng lỗ của pool Buy hoặc pool Sell chạm mức này thì đóng toàn bộ tập lệnh đó, pool còn lại vẫn chạy bình thường - để 0 = tắt)
input double Inp_Pool_SL_Percent       = 0.0;
// Inp_Slippage_Points (Độ trượt giá tối đa (points) cho phép khi vào/đóng lệnh; quá thấp dễ bị requote từ chối lúc giá biến động nhanh, đặc biệt với Gold)
input int    Inp_Slippage_Points       = 30;

input group "--- Flexible Take Profit ---"
// Inp_FlexTP_Enabled (Bật cơ chế chốt lãi linh hoạt FlexTP, tự đóng toàn bộ pool lệnh khi đạt ngưỡng lợi nhuận)
input bool   Inp_FlexTP_Enabled        = false;
// Inp_FlexTP_Percent (Tỷ lệ % lợi nhuận so với balance để FlexTP đóng toàn bộ pool lệnh)
input double Inp_FlexTP_Percent        = 1.0;
// Inp_FlexTP_Pips (Số pip lợi nhuận trung bình mỗi lệnh để FlexTP đóng toàn bộ pool; để 0 = không dùng điều kiện này)
input double Inp_FlexTP_Pips           = 0.0;

enum ENUM_ENTRY_MODE {
    ENTRY_SMART       = 0,
    ENTRY_LIMIT_BOS   = 1,
    ENTRY_MARKET_ONLY = 2
};

input group "--- Smart Order Execution ---"
// Inp_Entry_Mode (Chế độ vào lệnh: SMART = Market nếu SL gần và Limit tại zone nếu SL xa; LIMIT_BOS = luôn đặt Limit tại mốc BOS/ChoCh; MARKET_ONLY = luôn vào Market)
input ENUM_ENTRY_MODE Inp_Entry_Mode   = ENTRY_SMART;
// Market_vs_Limit_Pips (Ngưỡng khoảng cách Entry đến SL theo pips để quyết định Market hay Limit ở chế độ SMART: nhỏ hơn hoặc bằng ngưỡng này thì vào Market)
input double Market_vs_Limit_Pips      = 50.0;
// Max_Zone_SL_Pips (Khoảng cách SL tối đa cho phép theo pips, nếu zone rộng hơn mức này sẽ bị thu hẹp lại để SL không quá xa)
input double Max_Zone_SL_Pips          = 300.0;
// Inp_Min_SL_Pips (Khoảng cách SL tối thiểu theo pips; lệnh có SL hẹp hơn mức này bị bỏ qua vì dễ bị nhiễu và spread quét; để 0 = tắt)
input double Inp_Min_SL_Pips           = 0.0;
// Entry_Buffer_Percent (Tỷ lệ % độ rộng zone dùng để dịch điểm vào lệnh: số dương dịch ra ngoài mép zone, số âm dịch vào sâu trong zone)
input double Entry_Buffer_Percent      = 10.0;
// Min_Reward_to_Risk_R (Tỷ lệ Reward:Risk - R tối thiểu yêu cầu; nếu mục tiêu lợi nhuận không đạt tỷ lệ này so với rủi ro thì bỏ qua lệnh)
input double Min_Reward_to_Risk_R      = 1.5;
// Inp_Min_Entry_Dist_Pips (Khoảng cách tối thiểu theo pips giữa SL của lệnh mới với SL của lệnh cùng chiều gần nhất, để tránh vào lệnh trùng vùng giá)
input double Inp_Min_Entry_Dist_Pips   = 30.0;

input group "--- The Smart Gatekeeper ---"
// Inp_Enable_H1_Gate_Filter (Chế độ giao dịch: true - 3TF, xét thêm xu hướng H1 (Trend) khi mở/đóng cổng Buy/Sell - mở cổng Buy khi H1 tăng và chạm Buy Zone, mở cổng Sell khi H1 giảm và chạm Sell Zone (mặc định); false - 2TF, bỏ qua hoàn toàn điều kiện H1, cổng chỉ mở/đóng dựa theo Zone của khung Location (HTF) và M1)
input bool   Inp_Enable_H1_Gate_Filter = true;
// Inp_Buddha_Palm (Bật bộ lọc Bàn Tay Phật: chặn vào lệnh Buy khi đang trong HTF Sell Zone và chặn lệnh Sell khi đang trong HTF Buy Zone)
input bool   Inp_Buddha_Palm           = true;
// HTF_Zone_Buffer_Pct (Tỷ lệ % độ rộng HTF Zone dùng làm vùng đệm để mở cổng: số dương mở rộng vùng kích hoạt ra ngoài zone, số âm yêu cầu giá đi vào sâu trong zone theo % đó mới mở cổng - ví dụ -50 nghĩa là giá phải vào tới điểm giữa của zone)
input double HTF_Zone_Buffer_Pct       = 0.0;
// Min_HTF_Buffer_Pips (Khoảng đệm tối thiểu theo pip cho vùng mở cổng, chỉ có tác dụng khi HTF_Zone_Buffer_Pct >= 0)
input double Min_HTF_Buffer_Pips       = 15.0;
// Zone_Break_Tolerance_Pct (Tỷ lệ % chiều cao HTF Zone cho phép giá xuyên qua trước khi coi là zone đã vỡ và tự đóng cổng - kill line)
input double Zone_Break_Tolerance_Pct  = 50.0;
// Inp_ZoneTP_MaxRounds (Số lượt vào lệnh được tính theo tập lệnh chốt lãi cho mỗi lần chạm Zone; đủ số lượt này sẽ chặn vào lệnh thêm cho đến khi giá chạm Zone mới - để 0 = không giới hạn)
input int    Inp_ZoneTP_MaxRounds  = 2;
// Inp_Gate_MaxOrders (Số lệnh tối đa được phép đặt trong một lần mở cổng; đủ số này sẽ chặn vào lệnh thêm cho đến khi cổng đóng và mở lại - để 0 = không giới hạn)
input int    Inp_Gate_MaxOrders  = 2;
// Inp_Gate_MaxPipsFromZone (Khoảng cách tối đa theo pips từ giá hiện tại đến cạnh entry của M15 Zone; giá đi xa hơn mức này sẽ bị chặn vào lệnh mới - để 0 = không giới hạn)
input double Inp_Gate_MaxPipsFromZone = 0.0;

input group "--- HTF Settings (M15) ---"
// HTF_Timeframe (Khung thời gian dùng để xác định Vùng giá - HTF Zone)
input ENUM_TIMEFRAMES HTF_Timeframe         = PERIOD_M15;
// HTF_PeriodsInMajorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Major Swing trên khung HTF)
input int    HTF_PeriodsInMajorSwing        = 9;
// HTF_PeriodsInMinorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Minor Swing trên khung HTF)
input int    HTF_PeriodsInMinorSwing        = 5;
// HTF_BuyZoneColor (Màu vẽ vùng Buy Zone trên khung HTF)
const color  HTF_BuyZoneColor               = C'235,250,240';
// HTF_SellZoneColor (Màu vẽ vùng Sell Zone trên khung HTF)
const color  HTF_SellZoneColor              = C'255,235,235';
// HTF_KeyLevelColor (Màu vẽ các mức giá quan trọng - Key Level - trên khung HTF)
const color  HTF_KeyLevelColor              = clrOrange;
// HTF_BOS_Up_Color (Màu vẽ đường BOS tăng - Break of Structure Up - trên khung HTF)
const color  HTF_BOS_Up_Color               = clrDodgerBlue;
// HTF_BOS_Dn_Color (Màu vẽ đường BOS giảm - Break of Structure Down - trên khung HTF)
const color  HTF_BOS_Dn_Color               = clrRed;

input group "--- Trend TF Settings (H1) ---"
// Trend_Timeframe (Khung thời gian dùng để xác định Xu hướng lớn - Trend)
input ENUM_TIMEFRAMES Trend_Timeframe       = PERIOD_H1;
// Trend_PeriodsInMajorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Major Swing trên khung Trend)
input int    Trend_PeriodsInMajorSwing      = 9;
// Trend_PeriodsInMinorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Minor Swing trên khung Trend)
input int    Trend_PeriodsInMinorSwing      = 5;

input group "--- LTF Core Logic Settings (M1) ---"
// PeriodsInMajorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Major Swing trên M1 - khung xác định tín hiệu vào lệnh)
input int    PeriodsInMajorSwing            = 9;
// PeriodsInMinorSwing (Số nến mỗi bên dùng để xác định đỉnh/đáy Minor Swing trên M1)
input int    PeriodsInMinorSwing            = 5;
// MaxZones (Số lượng Zone Buy và Sell tối đa được lưu lại mỗi loại trên M1)
input int    MaxZones                       = 1;
// MaxBOSLines (Số đường BOS Major tối đa được lưu và hiển thị trên chart M1)
input int    MaxBOSLines                    = 5;
// MaxMinorBOSLines (Số đường BOS Minor tối đa được lưu và hiển thị trên chart M1)
input int    MaxMinorBOSLines               = 3;

input group "--- Dashboard Settings ---"
// DashboardColor (Màu chữ chính của bảng Dashboard hiển thị trên chart)
const color  DashboardColor                = clrBlack;
// Inp_Debug_Gate (Bật ghi log debug chi tiết cho Gatekeeper vào tab Experts)
input bool   Inp_Debug_Gate                = false;
// Inp_Matrix_File (Ten file ma tran CSV trong Common\Files, doi de thu cau hinh khac)
input string Inp_Matrix_File               = "TLS_Matrix_Trend.csv";

// ==================================================================
// STRUCTS
// ==================================================================
struct TMatrixRule {
    string HTF_State; string Maj_State; string Min_State;
    int    Entry_Type; double Risk_Multiplier; double BE_Trigger_R;
    double Partial_R; double Partial_Pct; string TP_Strategy;
    double TP_Param; string Trail_Strategy; string Location_Filter;
    string Dash_Note;
};
TMatrixRule g_matrix_rules[];

struct TPosTracker {
    ulong  ticket; double initial_sl; double initial_open;
    double initial_risk_money; double initial_vol; double initial_risk;
    bool partial_done; double trail_r_watermark; double realized_pnl; bool be_notified;
};
TPosTracker g_trackers[];

// ==================================================================
// NGHIÊN CỨU QUẢN LÝ LỆNH — CHỈ HOẠT ĐỘNG TRONG STRATEGY TESTER
// Ghi lãi nổi cao nhất (MFE) của từng lệnh, mô phỏng song song các mốc dời SL
// và các mức TP ngắn hơn, cùng nhịp xu hướng lúc vào lệnh. KHÔNG đổi cách bot
// vào/đóng lệnh. OnTester() in các bảng "[STUDY]" để chọn cách quản lý lệnh
// bằng số liệu thay vì phỏng đoán.
// ==================================================================
#define STUDY_NX 5                                   // số mốc kích hoạt dời SL
#define STUDY_NT 4                                   // số mức TP ngắn hơn
double g_study_x[STUDY_NX]  = {0.5, 1.0, 1.5, 2.0, 2.5};
double g_study_tp[STUDY_NT] = {1.0, 1.5, 2.0, 2.5};
struct TStudy {
    long   pos_id;  int dir;  double open;  double risk;  double mfe_R;
    bool   be_arm[STUDY_NX];  bool be_hit[STUDY_NX];     // SL -> điểm vào khi chạm mốc
    bool   lk_arm[STUDY_NX];  bool lk_hit[STUDY_NX];     // SL -> +0.5R khi chạm mốc
    int    leg_ltf; int leg_htf;                         // nhịp xu hướng Major lúc vào lệnh
    datetime open_time;                                  // giờ server lúc vào lệnh
    int    rule_idx;                                     // dòng ma trận (magic - BaseMagicNumber)
    // Đặc điểm lúc vào lệnh theo 5 khung: 0=chart, 1=HTF, 2=Trend, 3=H4, 4=D1
    int    tr_maj[5];                                    // xu hướng Major: 1 tăng, -1 giảm, 0 chưa rõ
    bool   in_zone[5];                                   // giá vào nằm trong zone CÙNG chiều lệnh
    double zone_dist[5];                                 // pip từ giá vào tới mép zone cùng chiều (<=0: trong/qua zone), -99999 = không có zone
    double room[5];                                      // pip tới mép zone NGƯỢC chiều (khoảng trống tới cản), -1 = không có
    datetime t_1r;                                       // lần đầu lãi nổi chạm 1R (0 = chưa từng)
    datetime t_mfe;                                      // thời điểm lãi nổi cao nhất
};
TStudy g_study[];
// Nhịp xu hướng Major: 1 tại CHoCH, +1 mỗi BOS cùng chiều. Cập nhật mỗi nến mới.
int    g_leg_ltf = 0, g_leg_ltf_dir = 0;  double g_leg_ltf_up = 0, g_leg_ltf_dn = 0;
int    g_leg_htf = 0, g_leg_htf_dir = 0;  double g_leg_htf_up = 0, g_leg_htf_dn = 0;

// ==================================================================
// BIẾN TOÀN CỤC
// ==================================================================
double g_last_traded_buy_sl  = 0.0;
double g_last_traded_sell_sl = 0.0;
string g_action_text = "Khởi tạo hệ thống...";
string g_filter_text = "Filter: Đang quét cản...";
bool   g_gate_buy_open  = false;
bool   g_gate_sell_open = false;
bool   g_tg_buy_notified  = false;
bool   g_tg_sell_notified = false;
string g_last_m1_phase  = "";
double g_last_broken_buy_zone_sl  = 0.0;
double g_last_broken_sell_zone_sl = 0.0;
double g_gate_buy_zone_entry  = 0.0;
double g_gate_buy_zone_sl     = 0.0;
double g_gate_sell_zone_entry = 0.0;
double g_gate_sell_zone_sl    = 0.0;
// Đếm số "tập lệnh" (round) đã CHỐT LÃI kể từ lần chạm Zone gần nhất.
// 1 "tập lệnh" = toàn bộ vị thế normal cùng chiều mở ra rồi đóng hết (không quan tâm số lượng lệnh bên trong).
int    g_zone_buy_profit_rounds  = 0;
int    g_zone_sell_profit_rounds = 0;
// Theo dõi vòng đời tập lệnh: số lệnh normal đang mở ở tick trước + P&L pool gần nhất lúc còn mở
int    g_zone_buy_prev_cnt   = 0;
int    g_zone_sell_prev_cnt  = 0;
double g_zone_buy_last_pnl   = 0.0;
double g_zone_sell_last_pnl  = 0.0;
// Đếm số lệnh đã đặt trong lần mở cổng hiện tại (reset về 0 mỗi khi cổng mở lại)
int    g_zone_buy_entry_count  = 0;
int    g_zone_sell_entry_count = 0;
// Fresh signal: yêu cầu BOS/ChoCh M1 mới sau khi round chốt lãi
bool   g_need_fresh_buy_signal  = false;
bool   g_need_fresh_sell_signal = false;
double g_buy_stale_sl_ref       = 0.0;
double g_sell_stale_sl_ref      = 0.0;

// Prop Shield
bool     g_trading_stopped_today = false;
bool     g_account_passed        = false;
datetime g_last_day_checked      = 0;
double   g_sod_balance           = 0;
string   g_shield_stop_reason    = "";
// Telegram remote commands
bool     g_cmd_paused        = false;
long     g_tg_last_update_id = 0;
ulong    g_tg_last_poll_ms   = 0;

// Close Retry Queue — lưu các ticket PositionClose() thất bại để retry qua OnTimer
struct SCloseRetry {
    ulong  ticket;
    int    retries;
    ulong  next_ms;
    string source;  // "FLEX_TP", "POOL_SL", "PROP_SHIELD"
};
SCloseRetry g_retry_queue[];
int         g_retry_count = 0;

// ==================================================================
// CLOSE RETRY HELPERS
// ==================================================================
// Khi thị trường đóng, mọi lệnh modify/close đều trả 10018 và code cũ thử lại
// MỖI TICK: đo được 14.242 modify hỏng + 3.647 close hỏng chỉ trong một tháng
// backtest. Chặn lại 5 phút sau mỗi lần dính 10018 rồi mới cho thử tiếp.
datetime g_mkt_closed_until = 0;
bool MarketClosedBackoff() { return (TimeCurrent() < g_mkt_closed_until); }
void NoteRetcode(uint rc) {
    if(rc == TRADE_RETCODE_MARKET_CLOSED) g_mkt_closed_until = TimeCurrent() + 300;
}

// Sàn cấm đặt SL/TP quá sát giá lệnh (SYMBOL_TRADE_STOPS_LEVEL). Trước đây lệnh
// rơi vào vùng cấm bị trả về [Invalid stops] và MẤT LUÔN: đo được 612 lệnh limit
// (ma trận SL theo Minor protected) và 124 lệnh market (TP OPPOSITE_ZONE) trong
// một lượt backtest. Nay đẩy mốc ra mức tối thiểu hợp lệ thay vì bỏ lệnh.
// price = giá của lệnh (giá thị trường hoặc giá limit); is_tp phân biệt TP với SL
// vì TP nằm cùng chiều lệnh còn SL nằm ngược chiều.
// Hai tình huống khác nhau, xử lý khác nhau:
//   a) Mốc đúng phía nhưng quá sát -> đẩy ra mức tối thiểu hợp lệ.
//   b) Mốc SAI PHÍA (lệnh Buy mà SL cao hơn giá vào) -> KHÔNG kẹp được. Kẹp lại
//      sẽ tạo SL rộng 0 pip, tức lệnh cầm chắc thua ngay. Trả về -1 để bỏ qua
//      setup. Đây mới là nguyên nhân thật của 612 lệnh mất trước đây: ma trận
//      SL-theo-Minor-protected sinh ra mốc bảo vệ nằm ngược phía mép zone.
//      Với TP sai phía thì chỉ bỏ TP (trả 0), không cần huỷ cả lệnh.
// Lưu ý: IC Markets có SYMBOL_TRADE_STOPS_LEVEL = 0, nên phải tự áp khoảng cách
// tối thiểu 1 point, không được thoát sớm khi stops level bằng 0.
double ClampStopLevel(double price, double stop, int signal, bool is_tp) {
    if(stop <= 0 || price <= 0) return stop;
    double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    long   lvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double mind = MathMax((double)lvl, 1.0) * pt;
    int    dir  = is_tp ? signal : -signal;
    double gap  = (dir > 0) ? (stop - price) : (price - stop);
    if(gap >= mind) return NormalizeDouble(stop, _Digits);
    if(gap <= 0) return is_tp ? 0.0 : -1.0;          // sai phía
    return NormalizeDouble((dir > 0) ? (price + mind) : (price - mind), _Digits);
}

bool IsRetryableRetcode(uint rc) {
    return (rc == TRADE_RETCODE_REQUOTE        ||
            rc == TRADE_RETCODE_PRICE_OFF      ||
            rc == TRADE_RETCODE_CONNECTION     ||
            rc == TRADE_RETCODE_TIMEOUT        ||
            rc == TRADE_RETCODE_PRICE_CHANGED);
}

void QueueCloseRetry(ulong ticket, string source) {
    for(int i = 0; i < g_retry_count; i++)
        if(g_retry_queue[i].ticket == ticket) return; // tránh trùng
    ArrayResize(g_retry_queue, g_retry_count + 1);
    g_retry_queue[g_retry_count].ticket  = ticket;
    g_retry_queue[g_retry_count].retries = 0;
    g_retry_queue[g_retry_count].next_ms = GetTickCount64() + 300;
    g_retry_queue[g_retry_count].source  = source;
    g_retry_count++;
    Print("[RETRY] Queue ticket=", ticket, " source=", source);
}

void ProcessCloseRetryQueue() {
    if(g_retry_count == 0) return;
    ulong now = GetTickCount64();
    for(int i = g_retry_count - 1; i >= 0; i--) {
        if(now < g_retry_queue[i].next_ms) continue;
        ulong ticket = g_retry_queue[i].ticket;
        if(!PositionSelectByTicket(ticket)) {
            Print("[RETRY] ticket=", ticket, " đã đóng, xóa queue");
            ArrayRemove(g_retry_queue, i, 1);
            g_retry_count--;
            continue;
        }
        if(g_retry_queue[i].retries >= 5) {
            Print("[RETRY] ticket=", ticket, " [", g_retry_queue[i].source, "] hết 5 lần retry, bỏ qua");
            ArrayRemove(g_retry_queue, i, 1);
            g_retry_count--;
            continue;
        }
        g_retry_queue[i].retries++;
        if(trade.PositionClose(ticket)) {
            Print("[RETRY] ticket=", ticket, " [", g_retry_queue[i].source, "] đóng thành công lần ", g_retry_queue[i].retries);
            ArrayRemove(g_retry_queue, i, 1);
            g_retry_count--;
        } else {
            uint rc = trade.ResultRetcode();
            if(IsRetryableRetcode(rc)) {
                g_retry_queue[i].next_ms = GetTickCount64() + 300;
                Print("[RETRY] ticket=", ticket, " lần ", g_retry_queue[i].retries, " retcode=", rc, " → retry 300ms");
            } else {
                Print("[RETRY] ticket=", ticket, " retcode=", rc, " (", trade.ResultRetcodeDescription(), ") không thể retry");
                ArrayRemove(g_retry_queue, i, 1);
                g_retry_count--;
            }
        }
    }
}

// Sau khi EA restart (crash hoặc remove/add lại), đọc lại toàn bộ vị thế đang mở
// và tạo entry mặc định trong g_trackers để ManageTrades() tiếp tục quản lý chúng.
// partial_done = true (an toàn: bỏ qua partial đã có thể thực hiện rồi).
// initial_sl = SL hiện tại (có thể đã dịch về BE); nếu SL == 0 hoặc == open thì
// initial_risk = 0 → ManageTrades() sẽ tự bỏ qua, không gây sự cố.
void RebuildTrackers() {
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        bool found = false;
        for(int j = 0; j < ArraySize(g_trackers); j++) { if(g_trackers[j].ticket == ticket) { found = true; break; } }
        if(found) continue;
        int sz = ArraySize(g_trackers);
        ArrayResize(g_trackers, sz + 1);
        g_trackers[sz].ticket           = ticket;
        g_trackers[sz].initial_open     = PositionGetDouble(POSITION_PRICE_OPEN);
        g_trackers[sz].initial_sl       = PositionGetDouble(POSITION_SL);
        g_trackers[sz].initial_risk     = MathAbs(g_trackers[sz].initial_open - g_trackers[sz].initial_sl);
        g_trackers[sz].initial_vol      = PositionGetDouble(POSITION_VOLUME);
        g_trackers[sz].partial_done     = true;  // giả định partial đã xong để tránh chốt nhầm
        g_trackers[sz].trail_r_watermark = 0.0;
        g_trackers[sz].realized_pnl     = 0.0;
        g_trackers[sz].be_notified      = true;
        double pip = GetPipSize(_Symbol);
        double lots = g_trackers[sz].initial_vol;
        double pip_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)
                       / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * pip;
        g_trackers[sz].initial_risk_money = g_trackers[sz].initial_risk / pip * pip_val * lots;
        Print("[RESTART] Tracker rebuilt: ticket=", ticket,
              " open=", g_trackers[sz].initial_open,
              " sl=", g_trackers[sz].initial_sl,
              " risk_pips=", DoubleToString(g_trackers[sz].initial_risk / pip, 1));
    }
}

// ==================================================================
// HELPER: CSV & UTILITIES
// ==================================================================
string CleanString(string str) {
    string temp = str;
    StringReplace(temp, "\"", ""); StringReplace(temp, " ", "");
    StringReplace(temp, "\r", ""); StringReplace(temp, "\n", "");
    StringReplace(temp, "–", "-"); StringReplace(temp, "—", "-");
    StringToUpper(temp);
    return temp;
}

bool LoadMatrixCSV() {
    string mfile = (StringLen(Inp_Matrix_File) > 0) ? Inp_Matrix_File : "TLS_Matrix_Trend.csv";
    int handle = FileOpen(mfile, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON, 0, CP_UTF8);
    if(handle == INVALID_HANDLE) { Print("LOI: Khong tim thay ", mfile, "!"); return false; }
    Print("[MATRIX] Dang doc file: ", mfile);
    ArrayResize(g_matrix_rules, 0);
    bool is_header = true;
    while(!FileIsEnding(handle)) {
        string line = FileReadString(handle);
        string check_empty = line; StringTrimLeft(check_empty); StringTrimRight(check_empty);
        if(check_empty == "") continue;
        if(is_header) { is_header = false; continue; }
        ushort separator = StringGetCharacter(",", 0);
        if(StringFind(line, ";") >= 0) separator = StringGetCharacter(";", 0);
        else if(StringFind(line, "\t") >= 0) separator = StringGetCharacter("\t", 0);
        string cols[];
        int col_count = StringSplit(line, separator, cols);
        if(col_count >= 13) {
            int size = ArraySize(g_matrix_rules);
            ArrayResize(g_matrix_rules, size + 1);
            g_matrix_rules[size].HTF_State       = CleanString(cols[0]);
            g_matrix_rules[size].Maj_State       = CleanString(cols[1]);
            g_matrix_rules[size].Min_State       = CleanString(cols[2]);
            g_matrix_rules[size].Entry_Type      = (int)StringToInteger(cols[3]);
            g_matrix_rules[size].Risk_Multiplier = StringToDouble(cols[4]);
            g_matrix_rules[size].BE_Trigger_R    = StringToDouble(cols[5]);
            g_matrix_rules[size].Partial_R       = StringToDouble(cols[6]);
            g_matrix_rules[size].Partial_Pct     = StringToDouble(cols[7]);
            g_matrix_rules[size].TP_Strategy     = CleanString(cols[8]);
            g_matrix_rules[size].TP_Param        = StringToDouble(cols[9]);
            g_matrix_rules[size].Trail_Strategy  = CleanString(cols[10]);
            g_matrix_rules[size].Location_Filter = CleanString(cols[11]);
            string dash_note = cols[12];
            StringReplace(dash_note, "\"", "");
            g_matrix_rules[size].Dash_Note = dash_note;
        }
    }
    FileClose(handle);
    return true;
}

double GetPipSize(string sym) {
    string s = sym; StringToUpper(s);
    if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
    if(StringFind(s, "JPY") >= 0) return 0.01;
    long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS);
    if(digits == 5 || digits == 4) return 0.0001;
    if(digits == 3 || digits == 2) return 0.01;
    return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0;
}

bool IsNewBar() {
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    if(last_bar_time == 0) { last_bar_time = current_bar_time; return true; }
    if(current_bar_time != last_bar_time) { last_bar_time = current_bar_time; return true; }
    return false;
}

// ==================================================================
// HELPER: MAGIC NUMBER CLASSIFICATION
// ==================================================================
bool IsNormalMagic(long magic) {
    return (magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000);
}

// ==================================================================
// STATE PERSISTENCE (GlobalVariables)
// ==================================================================
string GVKey(string k) { return "TLSH_" + _Symbol + "_" + k; }

void SaveState() {
    GlobalVariableSet(GVKey("buy_entry_cnt"),   (double)g_zone_buy_entry_count);
    GlobalVariableSet(GVKey("sell_entry_cnt"),  (double)g_zone_sell_entry_count);
    GlobalVariableSet(GVKey("buy_rounds"),      (double)g_zone_buy_profit_rounds);
    GlobalVariableSet(GVKey("sell_rounds"),     (double)g_zone_sell_profit_rounds);
    GlobalVariableSet(GVKey("gate_buy_open"),   g_gate_buy_open  ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("gate_sell_open"),  g_gate_sell_open ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("gate_buy_entry"),  g_gate_buy_zone_entry);
    GlobalVariableSet(GVKey("gate_buy_sl"),     g_gate_buy_zone_sl);
    GlobalVariableSet(GVKey("gate_sell_entry"), g_gate_sell_zone_entry);
    GlobalVariableSet(GVKey("gate_sell_sl"),    g_gate_sell_zone_sl);
    GlobalVariableSet(GVKey("broken_buy_sl"),   g_last_broken_buy_zone_sl);
    GlobalVariableSet(GVKey("broken_sell_sl"),  g_last_broken_sell_zone_sl);
    GlobalVariableSet(GVKey("fresh_buy"),       g_need_fresh_buy_signal  ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("fresh_sell"),      g_need_fresh_sell_signal ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("stale_buy_ref"),   g_buy_stale_sl_ref);
    GlobalVariableSet(GVKey("stale_sell_ref"),  g_sell_stale_sl_ref);
    GlobalVariableSet(GVKey("stopped_today"),   g_trading_stopped_today ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("sod_balance"),     g_sod_balance);
    GlobalVariableSet(GVKey("last_day"),        (double)g_last_day_checked);
    GlobalVariableSet(GVKey("cmd_paused"),      g_cmd_paused ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("tg_last_uid"),     (double)g_tg_last_update_id);
}

void LoadState() {
    if(!GlobalVariableCheck(GVKey("buy_entry_cnt"))) return;
    g_zone_buy_entry_count    = (int)GlobalVariableGet(GVKey("buy_entry_cnt"));
    g_zone_sell_entry_count   = (int)GlobalVariableGet(GVKey("sell_entry_cnt"));
    g_zone_buy_profit_rounds  = (int)GlobalVariableGet(GVKey("buy_rounds"));
    g_zone_sell_profit_rounds = (int)GlobalVariableGet(GVKey("sell_rounds"));
    g_gate_buy_open           = GlobalVariableGet(GVKey("gate_buy_open"))  > 0.5;
    g_gate_sell_open          = GlobalVariableGet(GVKey("gate_sell_open")) > 0.5;
    g_gate_buy_zone_entry     = GlobalVariableGet(GVKey("gate_buy_entry"));
    g_gate_buy_zone_sl        = GlobalVariableGet(GVKey("gate_buy_sl"));
    g_gate_sell_zone_entry    = GlobalVariableGet(GVKey("gate_sell_entry"));
    g_gate_sell_zone_sl       = GlobalVariableGet(GVKey("gate_sell_sl"));
    g_last_broken_buy_zone_sl = GlobalVariableGet(GVKey("broken_buy_sl"));
    g_last_broken_sell_zone_sl= GlobalVariableGet(GVKey("broken_sell_sl"));
    g_need_fresh_buy_signal   = GlobalVariableGet(GVKey("fresh_buy"))  > 0.5;
    g_need_fresh_sell_signal  = GlobalVariableGet(GVKey("fresh_sell")) > 0.5;
    g_buy_stale_sl_ref        = GlobalVariableGet(GVKey("stale_buy_ref"));
    g_sell_stale_sl_ref       = GlobalVariableGet(GVKey("stale_sell_ref"));
    g_trading_stopped_today   = GlobalVariableGet(GVKey("stopped_today")) > 0.5;
    g_sod_balance             = GlobalVariableGet(GVKey("sod_balance"));
    g_last_day_checked        = (datetime)GlobalVariableGet(GVKey("last_day"));
    if(GlobalVariableCheck(GVKey("cmd_paused")))  g_cmd_paused        = GlobalVariableGet(GVKey("cmd_paused"))  > 0.5;
    if(GlobalVariableCheck(GVKey("tg_last_uid"))) g_tg_last_update_id = (long)GlobalVariableGet(GVKey("tg_last_uid"));
    Print("[STATE RESTORED] buy_cnt=", g_zone_buy_entry_count,
          " sell_cnt=", g_zone_sell_entry_count,
          " buy_rounds=", g_zone_buy_profit_rounds,
          " sell_rounds=", g_zone_sell_profit_rounds,
          " gate_buy=", g_gate_buy_open, " gate_sell=", g_gate_sell_open,
          " stopped=", g_trading_stopped_today);
}

// ==================================================================
// SMC ENGINE INSTANCES
// ==================================================================
CSMC_Engine SMC_LTF;
CSMC_Engine SMC_HTF;
CSMC_Engine SMC_TREND;
// Chỉ khởi tạo trong Strategy Tester: ghi xu hướng và zone H4/D1 lúc vào lệnh để nghiên cứu
// đặc điểm các lệnh thắng lớn. Không tham gia bất kỳ quyết định giao dịch nào.
CSMC_Engine SMC_H4;
CSMC_Engine SMC_D1;

// ==================================================================
// PROP SHIELD
// ==================================================================
void CloseAll_PropFirm(string reason) {
    bool action_taken = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) {
            trade.OrderDelete(ticket);
            action_taken = true;
        }
    }
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) {
            if(!trade.PositionClose(ticket)) {
                uint rc = trade.ResultRetcode();
                Print("[PROP_SHIELD] Close FAILED ticket=", ticket, " retcode=", rc, " (", trade.ResultRetcodeDescription(), ")");
                if(IsRetryableRetcode(rc)) QueueCloseRetry(ticket, "PROP_SHIELD");
            }
            action_taken = true;
        }
    }
    if(action_taken)
        Radar.SendMessage("🚨 <b>PROP SHIELD TRIGGERED!</b>\n" + reason
            + "\nĐã tự động xóa sạch lệnh chờ và chốt toàn bộ vị thế!");
}

bool IsInNewsWindow() {
    if(Inp_NewsTimes == "") return false;
    datetime now = TimeCurrent();
    MqlDateTime dt_now; TimeToStruct(now, dt_now);
    int now_minutes = dt_now.hour * 60 + dt_now.min;
    string times[]; StringSplit(Inp_NewsTimes, ',', times);
    for(int i = 0; i < ArraySize(times); i++) {
        string t = times[i]; StringTrimLeft(t); StringTrimRight(t);
        if(t == "") continue;
        string parts[]; StringSplit(t, ':', parts);
        if(ArraySize(parts) == 2) {
            int news_min = (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
            if(now_minutes >= (news_min - Inp_NewsBufferMinutes) && now_minutes <= (news_min + Inp_NewsBufferMinutes))
                return true;
        }
    }
    return false;
}

void CleanPendingOrdersForNews() {
    if(IsInNewsWindow()) {
        bool deleted = false;
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if(IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) {
                if(trade.OrderDelete(ticket)) deleted = true;
            }
        }
        if(deleted)
            Radar.SendMessage("⚠️ <b>NEWS FILTER ACTIVE</b>\nĐã tự động hủy lệnh chờ (Pending) do dính khung giờ Tin Tức ("
                + IntegerToString(Inp_NewsBufferMinutes) + " mins)!");
    }
}

void ManagePropFirmRules() {
    if(g_account_passed) return;
    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
    if(current_day != g_last_day_checked) {
        g_sod_balance           = AccountInfoDouble(ACCOUNT_BALANCE);
        g_trading_stopped_today = false;
        g_shield_stop_reason    = "";
        g_last_day_checked      = current_day;
    }
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(Inp_AutoPassTarget > 0 && current_equity >= Inp_AutoPassTarget) {
        CloseAll_PropFirm("🎉 CHÚC MỪNG PASS QUỸ! Đạt mục tiêu: " + DoubleToString(current_equity, 2) + "$");
        g_account_passed = true; g_trading_stopped_today = true;
        g_shield_stop_reason = "Đã đạt mục tiêu Pass (" + DoubleToString(current_equity, 2) + "$)";
        return;
    }
    if(Inp_DailyDrawdownLimit > 0 && g_sod_balance > 0) {
        double loss_limit = g_sod_balance - g_sod_balance * (Inp_DailyDrawdownLimit / 100.0);
        if(current_equity <= loss_limit && !g_trading_stopped_today) {
            CloseAll_PropFirm("🛑 DAILY DD HIT! Vượt quá " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%");
            g_trading_stopped_today = true;
            g_shield_stop_reason = "Chạm Daily Drawdown " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
        }
    }
    if(Inp_DailyProfitLimit > 0 && g_sod_balance > 0 && !g_trading_stopped_today) {
        double daily_profit_pct = (current_equity - g_sod_balance) / g_sod_balance * 100.0;
        if(daily_profit_pct >= Inp_DailyProfitLimit) {
            CloseAll_PropFirm("🎯 DAILY PROFIT TARGET ĐẠT! +"
                + DoubleToString(daily_profit_pct, 2) + "% (ngưỡng "
                + DoubleToString(Inp_DailyProfitLimit, 1) + "%)\n"
                + "💰 Equity: " + DoubleToString(current_equity, 2) + "$\n"
                + "✅ Đã chốt toàn bộ lệnh. Nghỉ giao dịch đến hết ngày.");
            g_trading_stopped_today = true;
            g_shield_stop_reason = "Đạt Daily Profit Target +" + DoubleToString(daily_profit_pct, 2)
                                  + "% (>= " + DoubleToString(Inp_DailyProfitLimit, 1) + "%)";
        }
    }
}

// ==================================================================
// RISK SIZING
// ==================================================================
double CalculateLotSize(double sl_distance_points, double risk_multiplier) {
    if(!UseRiskPerTrade || sl_distance_points <= 0) return FixedLotSize;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size == 0 || tick_value == 0) return FixedLotSize;
    double actual_risk_pct = RiskPercent * risk_multiplier;
    if(actual_risk_pct <= 0) return FixedLotSize;
    double money_risk      = AccountInfoDouble(ACCOUNT_BALANCE) * (actual_risk_pct / 100.0);
    double value_per_point = tick_value / (tick_size / _Point);
    double risk_per_lot    = sl_distance_points * value_per_point;
    if(risk_per_lot == 0) return 0;
    double raw_lot = money_risk / risk_per_lot;
    if(Inp_UseMarginLimit) {
        double current_used_margin    = AccountInfoDouble(ACCOUNT_MARGIN);
        double max_total_margin       = AccountInfoDouble(ACCOUNT_BALANCE) * (Inp_MaxMarginPercent / 100.0);
        double remaining_margin_room  = max_total_margin - current_used_margin;
        if(remaining_margin_room <= 0) return 0;
        double margin_per_lot = 0;
        double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, ask_price, margin_per_lot))
            margin_per_lot = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * ask_price)
                           / AccountInfoInteger(ACCOUNT_LEVERAGE);
        if(margin_per_lot > 0) {
            double max_lot_by_margin = remaining_margin_room / margin_per_lot;
            if(raw_lot > max_lot_by_margin) raw_lot = max_lot_by_margin;
        }
    }
    double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    raw_lot = MathRound(raw_lot / step_lot) * step_lot;
    if(raw_lot < min_lot) return 0;
    return MathMin(raw_lot, max_lot);
}

// ==================================================================
// TRADE MANAGEMENT (giữ nguyên từ v5.0)
// ==================================================================
double CalculateCurrentRR(TPosTracker &tracker) {
    if(tracker.initial_risk_money <= 0) return 0;
    if(!PositionSelectByTicket(tracker.ticket))
        return tracker.realized_pnl / tracker.initial_risk_money;
    double current_pnl = PositionGetDouble(POSITION_PROFIT)
                       + PositionGetDouble(POSITION_SWAP)
                       + PositionGetDouble(POSITION_COMMISSION);
    return (tracker.realized_pnl + current_pnl) / tracker.initial_risk_money;
}

void UpdateGatekeeperState() {
    if(SMC_LTF.current_market_phase != g_last_m1_phase) {
        if(SMC_LTF.current_market_phase == "Impulse Down - ChoCh Down") g_gate_buy_open  = false;
        if(SMC_LTF.current_market_phase == "Impulse Up - ChoCh Up")   g_gate_sell_open = false;
        g_last_m1_phase = SMC_LTF.current_market_phase;
    }
    static int last_htf_trend = 0;
    if(SMC_HTF.current_major_trend != last_htf_trend) {
        if(SMC_HTF.current_major_trend ==  1) g_gate_sell_open = false;
        if(SMC_HTF.current_major_trend == -1) g_gate_buy_open  = false;
        last_htf_trend = SMC_HTF.current_major_trend;
    }
    static int last_trend_tf_trend = 0;
    if(Inp_Enable_H1_Gate_Filter && SMC_TREND.current_major_trend != last_trend_tf_trend) {
        if(SMC_TREND.current_major_trend ==  1) g_gate_sell_open = false;
        if(SMC_TREND.current_major_trend == -1) g_gate_buy_open  = false;
        last_trend_tf_trend = SMC_TREND.current_major_trend;
    }
    double pip_size = GetPipSize(_Symbol);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    static double s_prev_htf_buy_sl = 0, s_prev_htf_sell_sl = 0;
    if(SMC_HTF.current_buy_zone_sl != s_prev_htf_buy_sl) {
        if(SMC_HTF.current_buy_zone_sl > 0 && SMC_HTF.current_buy_zone_sl != g_last_broken_buy_zone_sl)
            g_last_broken_buy_zone_sl = 0;
        s_prev_htf_buy_sl = SMC_HTF.current_buy_zone_sl;
    }
    if(SMC_HTF.current_sell_zone_sl != s_prev_htf_sell_sl) {
        if(SMC_HTF.current_sell_zone_sl > 0 && SMC_HTF.current_sell_zone_sl != g_last_broken_sell_zone_sl)
            g_last_broken_sell_zone_sl = 0;
        s_prev_htf_sell_sl = SMC_HTF.current_sell_zone_sl;
    }

    // Đóng cổng nếu Zone đã kích hoạt cổng không còn tồn tại trên Zone Queue của HTF
    // (đã bị giá phá vỡ và bị xóa khỏi chart).
    if(g_gate_buy_open && g_gate_buy_zone_sl > 0) {
        bool zone_still_exists = (g_gate_buy_zone_sl == SMC_HTF.current_buy_zone_sl);
        if(!zone_still_exists) { g_gate_buy_open = false; g_last_broken_buy_zone_sl = g_gate_buy_zone_sl; }
    }
    if(g_gate_sell_open && g_gate_sell_zone_sl > 0) {
        bool zone_still_exists = (g_gate_sell_zone_sl == SMC_HTF.current_sell_zone_sl);
        if(!zone_still_exists) { g_gate_sell_open = false; g_last_broken_sell_zone_sl = g_gate_sell_zone_sl; }
    }
    // Kill-line: đóng cổng khi giá xuyên qua SL của zone (zone bị phá về giá dù H4 bar chưa đóng)
    // Zone_Break_Tolerance_Pct = 0 → đóng ngay khi giá vượt SL; 50 → cho phép vượt thêm 50% chiều cao zone
    if(g_gate_sell_open && g_gate_sell_zone_sl > 0 && g_gate_sell_zone_entry > 0) {
        double zone_h   = g_gate_sell_zone_sl - g_gate_sell_zone_entry;
        double kill_line = g_gate_sell_zone_sl + zone_h * (Zone_Break_Tolerance_Pct / 100.0);
        if(ask > kill_line) { g_gate_sell_open = false; g_last_broken_sell_zone_sl = g_gate_sell_zone_sl; }
    }
    if(g_gate_buy_open && g_gate_buy_zone_sl > 0 && g_gate_buy_zone_entry > 0) {
        double zone_h    = g_gate_buy_zone_entry - g_gate_buy_zone_sl;
        double kill_line = g_gate_buy_zone_sl - zone_h * (Zone_Break_Tolerance_Pct / 100.0);
        if(bid < kill_line) { g_gate_buy_open = false; g_last_broken_buy_zone_sl = g_gate_buy_zone_sl; }
    }

    if(!g_gate_buy_open) {
        double buy_e = SMC_HTF.current_buy_zone_entry, buy_s = SMC_HTF.current_buy_zone_sl;
        if(buy_e > 0 && buy_s > 0) {
            double w = MathAbs(buy_e - buy_s) / pip_size;
            double pct_buf = w * HTF_Zone_Buffer_Pct / 100.0;
            // Pct >= 0: mở rộng vùng kích hoạt ra ngoài Zone, có sàn Min_HTF_Buffer_Pips.
            // Pct <  0: yêu cầu giá xuyên sâu vào trong Zone theo %, không áp sàn.
            double buf = (HTF_Zone_Buffer_Pct >= 0) ? MathMax(pct_buf, Min_HTF_Buffer_Pips) : pct_buf;
            double buffered_top = buy_e + buf * pip_size;
            bool c_price = (bid <= buffered_top);
            bool c_fresh = (buy_s != g_last_broken_buy_zone_sl);
            bool c_h1    = !Inp_Enable_H1_Gate_Filter ? true : (SMC_TREND.current_major_trend == 1);
            if(c_price && c_fresh && c_h1) {
                bool is_new_zone = (buy_s != g_gate_buy_zone_sl);
                g_gate_buy_open = true; g_gate_buy_zone_entry = buy_e; g_gate_buy_zone_sl = buy_s;
                if(is_new_zone) { g_zone_buy_profit_rounds = 0; g_zone_buy_entry_count = 0; }
                g_need_fresh_buy_signal = true;
                g_buy_stale_sl_ref = SMC_LTF.current_buy_zone_sl;
            }
            if(Inp_Debug_Gate) Print("[GATE_BUY] Zone=", buy_e, "/", buy_s, " | price=", c_price, " fresh=", c_fresh, " H1=", c_h1, " → ", g_gate_buy_open ? "OPEN" : "LOCK");
        }
    }
    if(!g_gate_sell_open) {
        double sell_e = SMC_HTF.current_sell_zone_entry, sell_s = SMC_HTF.current_sell_zone_sl;
        if(sell_e > 0 && sell_s > 0) {
            double w = MathAbs(sell_s - sell_e) / pip_size;
            double pct_buf = w * HTF_Zone_Buffer_Pct / 100.0;
            double buf = (HTF_Zone_Buffer_Pct >= 0) ? MathMax(pct_buf, Min_HTF_Buffer_Pips) : pct_buf;
            double buffered_bot = sell_e - buf * pip_size;
            bool c_price = (ask >= buffered_bot);
            bool c_fresh = (sell_s != g_last_broken_sell_zone_sl);
            bool c_h1    = !Inp_Enable_H1_Gate_Filter ? true : (SMC_TREND.current_major_trend == -1);
            if(c_price && c_fresh && c_h1) {
                bool is_new_zone = (sell_s != g_gate_sell_zone_sl);
                g_gate_sell_open = true; g_gate_sell_zone_entry = sell_e; g_gate_sell_zone_sl = sell_s;
                if(is_new_zone) { g_zone_sell_profit_rounds = 0; g_zone_sell_entry_count = 0; }
                g_need_fresh_sell_signal = true;
                g_sell_stale_sl_ref = SMC_LTF.current_sell_zone_sl;
            }
            if(Inp_Debug_Gate) Print("[GATE_SELL] Zone=", sell_e, "/", sell_s, " | price=", c_price, " fresh=", c_fresh, " H1=", c_h1, " → ", g_gate_sell_open ? "OPEN" : "LOCK");
        }
    }

    MqlRates r[]; ArraySetAsSeries(r, true);
    if(CopyRates(_Symbol, _Period, 0, 2, r) >= 2) {
        double ha_open_1  = ((r[1].open + r[1].close) / 2.0 + (r[1].open + r[1].high + r[1].low + r[1].close) / 4.0) / 2.0;
        double ha_close_1 = (r[1].open + r[1].high + r[1].low + r[1].close) / 4.0;
        double ha_low_1   = MathMin(r[1].low,  MathMin(ha_open_1, ha_close_1));
        double ha_high_1  = MathMax(r[1].high, MathMax(ha_open_1, ha_close_1));
        if(g_gate_buy_open && g_gate_buy_zone_entry > 0 && g_gate_buy_zone_sl > 0) {
            double h = MathAbs(g_gate_buy_zone_entry - g_gate_buy_zone_sl);
            double kill_line = g_gate_buy_zone_sl - (h * Zone_Break_Tolerance_Pct / 100.0);
            if(ha_low_1 < kill_line && ha_close_1 < g_gate_buy_zone_sl) {
                g_gate_buy_open = false; g_last_broken_buy_zone_sl = g_gate_buy_zone_sl;
            }
        }
        if(g_gate_sell_open && g_gate_sell_zone_entry > 0 && g_gate_sell_zone_sl > 0) {
            double h = MathAbs(g_gate_sell_zone_sl - g_gate_sell_zone_entry);
            double kill_line = g_gate_sell_zone_sl + (h * Zone_Break_Tolerance_Pct / 100.0);
            if(ha_high_1 > kill_line && ha_close_1 > g_gate_sell_zone_sl) {
                g_gate_sell_open = false; g_last_broken_sell_zone_sl = g_gate_sell_zone_sl;
            }
        }
    }
    if(g_gate_buy_open  && !g_tg_buy_notified)  { Radar.SendMessageWithPhoto("🔓 <b>GATE OPENED: MỞ CỔNG MUA</b>\n━━━━━━━━━━━━━━━\n🔎 <b>Vị trí:</b> Giá chạm HTF Buy Zone\n⏳ Chờ xác nhận cấu trúc LTF để vào lệnh..."); g_tg_buy_notified  = true; }
    if(!g_gate_buy_open)  g_tg_buy_notified  = false;
    if(g_gate_sell_open && !g_tg_sell_notified) { Radar.SendMessageWithPhoto("🔓 <b>GATE OPENED: MỞ CỔNG BÁN</b>\n━━━━━━━━━━━━━━━\n🔎 <b>Vị trí:</b> Giá chạm HTF Sell Zone\n⏳ Chờ xác nhận cấu trúc LTF để vào lệnh..."); g_tg_sell_notified = true; }
    if(!g_gate_sell_open) g_tg_sell_notified = false;
}

// Theo dõi vòng đời "tập lệnh" (round) của các vị thế normal theo từng chiều.
// Khi toàn bộ vị thế cùng chiều đóng hết (count > 0 → 0), nếu P&L pool ngay trước đó > 0
// thì tính là 1 "tập lệnh chốt lãi" → tăng g_zone_*_profit_rounds (dùng để giới hạn vào lệnh theo Zone).
void UpdateZoneRoundTracking() {
    double buy_pnl = 0, sell_pnl = 0;
    int buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
        if(type == POSITION_TYPE_BUY) { buy_pnl += pnl; buy_cnt++; }
        else                          { sell_pnl += pnl; sell_cnt++; }
    }
    if(g_zone_buy_prev_cnt > 0 && buy_cnt == 0) {
        // Reset entry_count + yêu cầu fresh signal khi tập lệnh buy đóng vì bất kỳ lý do gì (SL/TP/tay)
        g_zone_buy_entry_count  = 0;
        g_need_fresh_buy_signal = true;
        g_buy_stale_sl_ref      = SMC_LTF.current_buy_zone_sl;
        // Chỉ tính profit_round khi đóng có lãi (dùng cho giới hạn Inp_ZoneTP_MaxRounds)
        if(g_zone_buy_last_pnl > 0) g_zone_buy_profit_rounds++;
    }
    if(buy_cnt > 0) g_zone_buy_last_pnl = buy_pnl;
    g_zone_buy_prev_cnt = buy_cnt;
    if(g_zone_sell_prev_cnt > 0 && sell_cnt == 0) {
        g_zone_sell_entry_count  = 0;
        g_need_fresh_sell_signal = true;
        g_sell_stale_sl_ref      = SMC_LTF.current_sell_zone_sl;
        if(g_zone_sell_last_pnl > 0) g_zone_sell_profit_rounds++;
    }
    if(sell_cnt > 0) g_zone_sell_last_pnl = sell_pnl;
    g_zone_sell_prev_cnt = sell_cnt;
}

double CalcTargetPrice(int signal, double entry_price, double sl_price, TMatrixRule &rule) {
    double tp = 0.0; double risk_val = MathAbs(entry_price - sl_price); double pip_size = GetPipSize(_Symbol);
    if(risk_val <= 0) return 0.0;
    if(rule.TP_Strategy == "FIXED_R" && rule.TP_Param > 0)
        tp = (signal == 1) ? (entry_price + risk_val * rule.TP_Param) : (entry_price - risk_val * rule.TP_Param);
    else if(rule.TP_Strategy == "OPPOSITE_ZONE") { double target = (signal == 1) ? SMC_LTF.current_sell_zone_entry : SMC_LTF.current_buy_zone_entry; if(target > 0) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if(rule.TP_Strategy == "HTF_OPPOSITE_ZONE") { double target = (signal == 1) ? SMC_HTF.current_sell_zone_entry : SMC_HTF.current_buy_zone_entry; if(target > 0) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if(rule.TP_Strategy == "HTF_ACTIVE") { double target = (signal == 1) ? SMC_HTF.current_maj_extreme_high : SMC_HTF.current_maj_extreme_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if(rule.TP_Strategy == "HTF_PROT") { double target = (signal == 1) ? SMC_HTF.current_maj_prot_high : SMC_HTF.current_maj_prot_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if(rule.TP_Strategy == "LTF_ACTIVE") { double target = (signal == 1) ? SMC_LTF.current_maj_extreme_high : SMC_LTF.current_maj_extreme_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if(rule.TP_Strategy == "LTF_PROT") { double target = (signal == 1) ? SMC_LTF.current_maj_prot_high : SMC_LTF.current_maj_prot_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    return (tp > 0) ? NormalizeDouble(tp, _Digits) : 0.0;
}

double CalcHardTP(int signal, double entry_price, double sl_price, TMatrixRule &rule) {
    if(rule.Partial_R == -1) return 0.0;
    return CalcTargetPrice(signal, entry_price, sl_price, rule);
}

void ManageTrades_Tick() {
    if(MarketClosedBackoff()) return;
    // Đăng ký tracker cho position mới (chỉ normal magic)
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsNormalMagic(magic)) continue;
        bool found = false;
        for(int j = 0; j < ArraySize(g_trackers); j++) { if(g_trackers[j].ticket == ticket) { found = true; break; } }
        if(!found) {
            int size = ArraySize(g_trackers); ArrayResize(g_trackers, size + 1);
            g_trackers[size].ticket          = ticket;
            g_trackers[size].initial_sl      = PositionGetDouble(POSITION_SL);
            g_trackers[size].initial_open    = PositionGetDouble(POSITION_PRICE_OPEN);
            g_trackers[size].initial_risk    = MathAbs(g_trackers[size].initial_open - g_trackers[size].initial_sl);
            g_trackers[size].initial_vol     = PositionGetDouble(POSITION_VOLUME);
            g_trackers[size].partial_done    = false;
            g_trackers[size].trail_r_watermark = 0.0;
            g_trackers[size].realized_pnl    = 0;
            g_trackers[size].be_notified     = false;
            double sl_dist = g_trackers[size].initial_risk;
            g_trackers[size].initial_risk_money = sl_dist * g_trackers[size].initial_vol
                * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
        }
    }
    // Quản lý BE / Partial / Trail cho normal positions
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsNormalMagic(magic)) continue;
        int rule_idx = (int)(magic - BaseMagicNumber);
        if(rule_idx < 0 || rule_idx >= ArraySize(g_matrix_rules)) continue;
        TMatrixRule rule = g_matrix_rules[rule_idx];
        int t_idx = -1;
        for(int j = 0; j < ArraySize(g_trackers); j++) { if(g_trackers[j].ticket == ticket) { t_idx = j; break; } }
        if(t_idx == -1) continue;
        double initial_risk = g_trackers[t_idx].initial_risk;
        if(initial_risk <= 0) continue;
        long   type          = PositionGetInteger(POSITION_TYPE);
        double open_price    = g_trackers[t_idx].initial_open;
        double current_sl    = PositionGetDouble(POSITION_SL);
        double current_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double current_profit = (type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price);
        double current_R = current_profit / initial_risk;

        if(!g_trackers[t_idx].partial_done) {
            bool trigger_partial = false;
            if(rule.Partial_R > 0 && current_R >= rule.Partial_R) trigger_partial = true;
            else if(rule.Partial_R == -1) {
                int pos_signal = (type == POSITION_TYPE_BUY) ? 1 : -1;
                double target_price = CalcTargetPrice(pos_signal, open_price, g_trackers[t_idx].initial_sl, rule);
                if(target_price > 0) {
                    if(type == POSITION_TYPE_BUY  && current_price >= target_price) trigger_partial = true;
                    if(type == POSITION_TYPE_SELL && current_price <= target_price) trigger_partial = true;
                }
            }
            if(trigger_partial) {
                g_trackers[t_idx].partial_done = true;
                if(rule.Partial_Pct > 0) {
                    double close_vol = g_trackers[t_idx].initial_vol * (rule.Partial_Pct / 100.0);
                    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                    close_vol = MathFloor(close_vol / step) * step;
                    if(close_vol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                        double before_bal = AccountInfoDouble(ACCOUNT_BALANCE);
                        bool ok = (close_vol >= PositionGetDouble(POSITION_VOLUME))
                                ? trade.PositionClose(ticket)
                                : trade.PositionClosePartial(ticket, close_vol);
                        if(ok) {
                            Sleep(500);
                            double pnl_added = AccountInfoDouble(ACCOUNT_BALANCE) - before_bal;
                            g_trackers[t_idx].realized_pnl += pnl_added;
                            Radar.SendMessage("✂️ <b>PARTIAL CLOSE</b>\n🎯 Mốc " + DoubleToString(rule.Partial_R, 1) + "R\n💰 +" + DoubleToString(pnl_added, 2) + "$");
                        }
                        continue;
                    }
                }
            }
        }
        if(rule.BE_Trigger_R > 0 && current_R >= rule.BE_Trigger_R) {
            bool needs_be = (type == POSITION_TYPE_BUY  && current_sl < open_price)
                         || (type == POSITION_TYPE_SELL && current_sl > open_price);
            if(needs_be) {
                if(trade.PositionModify(ticket, NormalizeDouble(open_price, _Digits), PositionGetDouble(POSITION_TP))) {
                    current_sl = open_price;
                    if(!g_trackers[t_idx].be_notified) {
                        Radar.SendMessage("🛡️ <b>SL TRAILED: VỀ HÒA VỐN</b>\n📈 Lãi nổi: +" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + "$");
                        g_trackers[t_idx].be_notified = true;
                    }
                } else {
                    // Thiếu dòng này thì khi sàn nghỉ, khối dời SL về hoà vốn thử lại MỖI
                    // TICK: đo được 5.965 lần hỏng [Market closed] trên 13 lệnh (có lệnh
                    // 1.771 lần) trong backtest 43 tháng. Báo retcode để bật chờ 5 phút.
                    NoteRetcode(trade.ResultRetcode());
                }
            }
        }
        if(rule.Trail_Strategy != "NONE" && rule.Trail_Strategy != "") {
            double new_sl = current_sl; double pip_size = GetPipSize(_Symbol); double buffer_val = SL_Buffer_Pips * pip_size;
            if(rule.Trail_Strategy == "TRAIL_MINOR") { double raw_sl = (type == POSITION_TYPE_BUY) ? SMC_LTF.current_minor_buy_zone_sl : SMC_LTF.current_minor_sell_zone_sl; if(raw_sl > 0) new_sl = (type == POSITION_TYPE_BUY) ? (raw_sl - buffer_val) : (raw_sl + buffer_val); }
            else if(rule.Trail_Strategy == "TRAIL_MAJOR") { double raw_sl = (type == POSITION_TYPE_BUY) ? SMC_LTF.current_buy_zone_sl : SMC_LTF.current_sell_zone_sl; if(raw_sl > 0) new_sl = (type == POSITION_TYPE_BUY) ? (raw_sl - buffer_val) : (raw_sl + buffer_val); }
            else if(rule.Trail_Strategy == "TRAIL_STRUCT") {
                double best_sl = current_sl;
                if(type == POSITION_TYPE_BUY) { double p_low = SMC_LTF.current_maj_prot_low; double cand_p = (p_low > 0 && p_low != EMPTY_VALUE) ? (p_low - buffer_val) : 0; if(cand_p >= current_price) cand_p = 0; if(cand_p > best_sl) best_sl = cand_p; if(best_sl > current_sl) new_sl = best_sl; }
                else if(type == POSITION_TYPE_SELL) { double p_high = SMC_LTF.current_maj_prot_high; double cand_p = (p_high > 0 && p_high != EMPTY_VALUE) ? (p_high + buffer_val) : 0; if(cand_p <= current_price && cand_p > 0) cand_p = 0; if(best_sl <= 0) best_sl = DBL_MAX; if(cand_p > 0 && cand_p < best_sl) best_sl = cand_p; if(best_sl < current_sl || current_sl <= 0) new_sl = best_sl; }
            }
            else if(rule.Trail_Strategy == "TRAIL_R") {
                if(current_R > g_trackers[t_idx].trail_r_watermark) g_trackers[t_idx].trail_r_watermark = current_R;
                if(g_trackers[t_idx].trail_r_watermark >= 1.0) { double locked_R = g_trackers[t_idx].trail_r_watermark - 1.0; if(locked_R > 0) new_sl = (type == POSITION_TYPE_BUY) ? (open_price + locked_R * initial_risk) : (open_price - locked_R * initial_risk); }
            }
            // So sánh phải làm trên giá ĐÃ NORMALIZE. Trước đây so trên giá thô:
            // TRAIL_R nhích watermark từng chút mỗi tick nên new_sl luôn "lớn hơn"
            // current_sl vài phần nghìn, nhưng sau NormalizeDouble lại ra ĐÚNG giá
            // cũ -> sàn trả [Invalid stops] -> lặp lại mỗi tick. Đo được 50.812 lần
            // modify hỏng trong một tháng backtest.
            if(new_sl > 0 && new_sl != DBL_MAX) {
                double nsl = NormalizeDouble(new_sl, _Digits);
                double csl = NormalizeDouble(current_sl, _Digits);
                bool modify = false;
                if(type == POSITION_TYPE_BUY)  { if(nsl < current_price && (csl == 0 || nsl > csl)) modify = true; }
                if(type == POSITION_TYPE_SELL) { if(nsl > current_price && (csl == 0 || nsl < csl)) modify = true; }
                if(modify && !trade.PositionModify(ticket, nsl, PositionGetDouble(POSITION_TP)))
                    NoteRetcode(trade.ResultRetcode());
            }
        }
    }
}

// Đếm nhịp xu hướng Major của một engine. BOS ngược chiều (vd "Impulse Up - BoS
// Down") là phá cấu trúc của nhịp hồi, không phải nhịp mới, nên không tính.
void UpdateLeg(CSMC_Engine &eng, int &leg, int &last_dir, double &last_up, double &last_dn) {
    int dir = eng.current_major_trend;
    if(dir != last_dir) {
        leg = (dir != 0) ? 1 : 0;
        last_dir = dir;
    } else {
        if(dir ==  1 && eng.current_bos_up_level != last_up) leg++;
        if(dir == -1 && eng.current_bos_dn_level != last_dn) leg++;
    }
    last_up = eng.current_bos_up_level;
    last_dn = eng.current_bos_dn_level;
}

// Ghi đặc điểm của một khung tại lúc vào lệnh: xu hướng Major, giá có nằm trong zone cùng
// chiều lệnh không, cách mép zone đó bao nhiêu pip, và còn bao nhiêu pip tới zone ngược chiều.
// Buy: zone cùng chiều là demand (entry = mép trên, sl = mép dưới); cản là mép dưới supply.
// Sell: zone cùng chiều là supply (entry = mép dưới, sl = mép trên); cản là mép trên demand.
void StudyFeat(CSMC_Engine &e, int k, int s) {
    double pip = GetPipSize(_Symbol);
    double px  = g_study[s].open;
    int    dir = g_study[s].dir;
    g_study[s].tr_maj[k]    = e.current_major_trend;
    g_study[s].in_zone[k]   = false;
    g_study[s].zone_dist[k] = -99999;
    g_study[s].room[k]      = -1;
    double z_edge = (dir == 1) ? e.current_buy_zone_entry  : e.current_sell_zone_entry;
    double z_far  = (dir == 1) ? e.current_buy_zone_sl     : e.current_sell_zone_sl;
    double o_edge = (dir == 1) ? e.current_sell_zone_entry : e.current_buy_zone_entry;
    if(z_edge > 0 && z_edge != EMPTY_VALUE && z_far > 0 && z_far != EMPTY_VALUE) {
        g_study[s].zone_dist[k] = (px - z_edge) * dir / pip;
        g_study[s].in_zone[k]   = (px >= MathMin(z_edge, z_far) && px <= MathMax(z_edge, z_far));
    }
    if(o_edge > 0 && o_edge != EMPTY_VALUE) {
        double r = (o_edge - px) * dir / pip;
        if(r > 0) g_study[s].room[k] = r;
    }
}

// Chạy mỗi tick khi backtest: ghi MFE và kích hoạt/chạm các mốc dời SL ảo.
// Giá dùng đúng phía mà sàn dùng để khớp SL/TP (Bid cho Buy, Ask cho Sell), nên
// kết quả mô phỏng khớp với việc thật sự đặt SL tại các mốc đó.
void StudyTick() {
    if(!MQLInfoInteger(MQL_TESTER)) return;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long pid = PositionGetInteger(POSITION_IDENTIFIER);
        int s = -1;
        for(int j = ArraySize(g_study) - 1; j >= 0; j--) if(g_study[j].pos_id == pid) { s = j; break; }
        if(s < 0) {
            double sl = PositionGetDouble(POSITION_SL);
            double op = PositionGetDouble(POSITION_PRICE_OPEN);
            if(sl <= 0 || MathAbs(op - sl) <= 0) continue;   // không có SL thì không quy ra R được
            s = ArraySize(g_study);
            ArrayResize(g_study, s + 1, 1024);
            g_study[s].pos_id = pid;
            g_study[s].dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
            g_study[s].open   = op;
            g_study[s].risk   = MathAbs(op - sl);
            g_study[s].mfe_R  = 0;
            for(int k = 0; k < STUDY_NX; k++) {
                g_study[s].be_arm[k] = false; g_study[s].be_hit[k] = false;
                g_study[s].lk_arm[k] = false; g_study[s].lk_hit[k] = false;
            }
            g_study[s].leg_ltf = g_leg_ltf;
            g_study[s].leg_htf = g_leg_htf;
            g_study[s].open_time = (datetime)PositionGetInteger(POSITION_TIME);
            g_study[s].rule_idx  = (int)(PositionGetInteger(POSITION_MAGIC) - BaseMagicNumber);
            g_study[s].t_1r = 0;
            g_study[s].t_mfe = 0;
            StudyFeat(SMC_LTF,   0, s);
            StudyFeat(SMC_HTF,   1, s);
            StudyFeat(SMC_TREND, 2, s);
            StudyFeat(SMC_H4,    3, s);
            StudyFeat(SMC_D1,    4, s);
        }
        double px = (g_study[s].dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double r  = (px - g_study[s].open) * g_study[s].dir / g_study[s].risk;
        if(r > g_study[s].mfe_R) { g_study[s].mfe_R = r; g_study[s].t_mfe = TimeCurrent(); }
        if(g_study[s].t_1r == 0 && r >= 1.0) g_study[s].t_1r = TimeCurrent();
        for(int k = 0; k < STUDY_NX; k++) {
            if(!g_study[s].be_hit[k]) {
                if(g_study[s].be_arm[k] && r <= 0.0) g_study[s].be_hit[k] = true;
                else if(r >= g_study_x[k])           g_study[s].be_arm[k] = true;
            }
            // Khoá +0.5R chỉ có nghĩa khi mốc kích hoạt lớn hơn 0.5R.
            if(!g_study[s].lk_hit[k] && g_study_x[k] > 0.5) {
                if(g_study[s].lk_arm[k] && r <= 0.5) g_study[s].lk_hit[k] = true;
                else if(r >= g_study_x[k])           g_study[s].lk_arm[k] = true;
            }
        }
    }
}

// In các bảng [STUDY]. Kết quả thật của từng lệnh lấy từ giá deal đóng lệnh.
// Mô phỏng chính xác theo đường giá, không ước lượng:
//   - Dời SL về X: nếu lệnh đã chạm mốc rồi quay về X trước khi đóng -> nhận X.
//   - TP ngắn T: lãi nổi cao nhất ghi đến lúc đóng lệnh là lãi nổi TRƯỚC khi chạm
//     SL, nên MFE >= T nghĩa là TP T đã khớp trước -> nhận T.
void StudyReport() {
    int n = ArraySize(g_study);
    if(n == 0) { Print("[STUDY] Khong co lenh nao de nghien cuu."); return; }

    HistorySelect(0, TimeCurrent());
    int total = HistoryDealsTotal();
    double act[];
    ArrayResize(act, n);
    ArrayInitialize(act, EMPTY_VALUE);
    for(int i = 0; i < total; i++) {
        ulong d = HistoryDealGetTicket(i);
        if(d == 0 || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
        for(int s = 0; s < n; s++) {
            if(g_study[s].pos_id != pid) continue;
            act[s] = (HistoryDealGetDouble(d, DEAL_PRICE) - g_study[s].open) * g_study[s].dir / g_study[s].risk;
            break;
        }
    }

    int    valid = 0, win_act = 0, losers = 0;
    double sum_act = 0, gw_act = 0, gl_act = 0;
    int    mfe_bin[7];
    double be_sum[STUDY_NX], be_gw[STUDY_NX], be_gl[STUDY_NX];
    int    be_win[STUDY_NX], be_save[STUDY_NX], be_kill[STUDY_NX];
    double lk_sum[STUDY_NX], lk_gw[STUDY_NX], lk_gl[STUDY_NX];
    int    lk_win[STUDY_NX], lk_save[STUDY_NX], lk_kill[STUDY_NX];
    double tp_sum[STUDY_NT], tp_gw[STUDY_NT], tp_gl[STUDY_NT];
    int    tp_win[STUDY_NT];
    int    lg_n[2][6], lg_win[2][6];
    double lg_act[2][6], lg_tp15[2][6], lg_tp20[2][6], lg_be15[2][6], lg_lk20[2][6];
    // Theo giờ / thứ vào lệnh, tách 2 giai đoạn để phân biệt quy luật thật với
    // trùng hợp: một khung giờ chỉ đáng loại khi lỗ ở CẢ HAI giai đoạn.
    datetime split_t = D'2025.01.01';
    int    hr_n[24], hr_win[24], hr_na[24], hr_nb[24];
    double hr_r[24], hr_ra[24], hr_rb[24];
    int    wd_n[7], wd_win[7], wd_na[7], wd_nb[7];
    double wd_r[7], wd_ra[7], wd_rb[7];
    ArrayInitialize(hr_n, 0); ArrayInitialize(hr_win, 0); ArrayInitialize(hr_na, 0); ArrayInitialize(hr_nb, 0);
    ArrayInitialize(hr_r, 0); ArrayInitialize(hr_ra, 0); ArrayInitialize(hr_rb, 0);
    ArrayInitialize(wd_n, 0); ArrayInitialize(wd_win, 0); ArrayInitialize(wd_na, 0); ArrayInitialize(wd_nb, 0);
    ArrayInitialize(wd_r, 0); ArrayInitialize(wd_ra, 0); ArrayInitialize(wd_rb, 0);
    ArrayInitialize(mfe_bin, 0);
    ArrayInitialize(be_sum, 0); ArrayInitialize(be_gw, 0); ArrayInitialize(be_gl, 0);
    ArrayInitialize(be_win, 0); ArrayInitialize(be_save, 0); ArrayInitialize(be_kill, 0);
    ArrayInitialize(lk_sum, 0); ArrayInitialize(lk_gw, 0); ArrayInitialize(lk_gl, 0);
    ArrayInitialize(lk_win, 0); ArrayInitialize(lk_save, 0); ArrayInitialize(lk_kill, 0);
    ArrayInitialize(tp_sum, 0); ArrayInitialize(tp_gw, 0); ArrayInitialize(tp_gl, 0);
    ArrayInitialize(tp_win, 0);
    for(int f = 0; f < 2; f++) for(int L = 0; L < 6; L++) {
        lg_n[f][L] = 0; lg_win[f][L] = 0;
        lg_act[f][L] = 0; lg_tp15[f][L] = 0; lg_tp20[f][L] = 0; lg_be15[f][L] = 0; lg_lk20[f][L] = 0;
    }

    for(int s = 0; s < n; s++) {
        if(act[s] == EMPTY_VALUE) continue;
        double a = act[s];
        double m = g_study[s].mfe_R;
        valid++;
        sum_act += a; if(a > 0) { win_act++; gw_act += a; } else if(a < 0) gl_act -= a;
        if(a < 0) {
            losers++;
            int b = (m < 0.5) ? 0 : (m < 1.0) ? 1 : (m < 1.5) ? 2 : (m < 2.0) ? 3 : (m < 2.5) ? 4 : (m < 3.0) ? 5 : 6;
            mfe_bin[b]++;
        }
        for(int k = 0; k < STUDY_NX; k++) {
            double vb = g_study[s].be_hit[k] ? 0.0 : a;
            be_sum[k] += vb; if(vb > 0) { be_win[k]++; be_gw[k] += vb; } else if(vb < 0) be_gl[k] -= vb;
            if(g_study[s].be_hit[k]) { if(a < 0) be_save[k]++; else if(a > 0) be_kill[k]++; }
            double vl = g_study[s].lk_hit[k] ? 0.5 : a;
            lk_sum[k] += vl; if(vl > 0) { lk_win[k]++; lk_gw[k] += vl; } else if(vl < 0) lk_gl[k] -= vl;
            if(g_study[s].lk_hit[k]) { if(a < 0.5) lk_save[k]++; else lk_kill[k]++; }
        }
        for(int t = 0; t < STUDY_NT; t++) {
            double vt = (m >= g_study_tp[t]) ? g_study_tp[t] : a;
            tp_sum[t] += vt; if(vt > 0) { tp_win[t]++; tp_gw[t] += vt; } else if(vt < 0) tp_gl[t] -= vt;
        }
        for(int f = 0; f < 2; f++) {
            int L = (f == 0) ? g_study[s].leg_ltf : g_study[s].leg_htf;
            if(L < 0) L = 0;
            if(L > 5) L = 5;
            lg_n[f][L]++; if(a > 0) lg_win[f][L]++;
            lg_act[f][L]  += a;
            lg_tp15[f][L] += (m >= 1.5) ? 1.5 : a;
            lg_tp20[f][L] += (m >= 2.0) ? 2.0 : a;
            lg_be15[f][L] += g_study[s].be_hit[2] ? 0.0 : a;
            lg_lk20[f][L] += g_study[s].lk_hit[3] ? 0.5 : a;
        }
        MqlDateTime dt;
        TimeToStruct(g_study[s].open_time, dt);
        bool early = (g_study[s].open_time < split_t);
        int  h = dt.hour, w = dt.day_of_week;
        hr_n[h]++; hr_r[h] += a; if(a > 0) hr_win[h]++;
        wd_n[w]++; wd_r[w] += a; if(a > 0) wd_win[w]++;
        if(early) { hr_na[h]++; hr_ra[h] += a; wd_na[w]++; wd_ra[w] += a; }
        else      { hr_nb[h]++; hr_rb[h] += a; wd_nb[w]++; wd_rb[w] += a; }
    }

    // Xuất từng lệnh ra Common\Files để phân tích ngoài: lãi nổi cao nhất theo
    // pips/USD, và ghép với log để dựng lãi lỗ theo ngày. Tên file theo ma trận và
    // ngày kết thúc test để các lượt khác nhau không ghi đè lên nhau.
    string mbase = Inp_Matrix_File;
    StringReplace(mbase, ".csv", "");
    string dend = TimeToString(TimeCurrent(), TIME_DATE);
    StringReplace(dend, ".", "");
    string fname = "study_" + mbase + "_" + dend + ".csv";
    int fh = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
    if(fh != INVALID_HANDLE) {
        FileWrite(fh, "pos_id", "dir", "open_time", "open", "risk_price", "mfe_R", "act_R", "leg_ltf", "leg_htf",
                  "rule", "t1r_min", "tmfe_min", "be10", "be15", "be20",
                  "tr_chart", "tr_htf", "tr_trend", "tr_h4", "tr_d1",
                  "inz_chart", "inz_htf", "inz_trend", "inz_h4", "inz_d1",
                  "zd_chart", "zd_htf", "zd_trend", "zd_h4", "zd_d1",
                  "room_chart", "room_htf", "room_trend", "room_h4", "room_d1");
        for(int s = 0; s < n; s++) {
            if(act[s] == EMPTY_VALUE) continue;
            long t1 = (g_study[s].t_1r  > 0) ? (long)(g_study[s].t_1r  - g_study[s].open_time) / 60 : -1;
            long tm = (g_study[s].t_mfe > 0) ? (long)(g_study[s].t_mfe - g_study[s].open_time) / 60 : -1;
            FileWrite(fh, g_study[s].pos_id, g_study[s].dir,
                      TimeToString(g_study[s].open_time, TIME_DATE|TIME_SECONDS),
                      DoubleToString(g_study[s].open, _Digits), DoubleToString(g_study[s].risk, _Digits),
                      DoubleToString(g_study[s].mfe_R, 3), DoubleToString(act[s], 3),
                      g_study[s].leg_ltf, g_study[s].leg_htf,
                      g_study[s].rule_idx, t1, tm,
                      (int)g_study[s].be_hit[1], (int)g_study[s].be_hit[2], (int)g_study[s].be_hit[3],
                      g_study[s].tr_maj[0], g_study[s].tr_maj[1], g_study[s].tr_maj[2], g_study[s].tr_maj[3], g_study[s].tr_maj[4],
                      (int)g_study[s].in_zone[0], (int)g_study[s].in_zone[1], (int)g_study[s].in_zone[2], (int)g_study[s].in_zone[3], (int)g_study[s].in_zone[4],
                      DoubleToString(g_study[s].zone_dist[0], 0), DoubleToString(g_study[s].zone_dist[1], 0), DoubleToString(g_study[s].zone_dist[2], 0),
                      DoubleToString(g_study[s].zone_dist[3], 0), DoubleToString(g_study[s].zone_dist[4], 0),
                      DoubleToString(g_study[s].room[0], 0), DoubleToString(g_study[s].room[1], 0), DoubleToString(g_study[s].room[2], 0),
                      DoubleToString(g_study[s].room[3], 0), DoubleToString(g_study[s].room[4], 0));
        }
        FileClose(fh);
        PrintFormat("[STUDY] Da xuat tung lenh ra Common\\Files\\%s", fname);
    }

    double net = TesterStatistics(STAT_PROFIT);
    Print("========== [STUDY] SO LIEU NEN ==========");
    PrintFormat("[STUDY] Lenh co du lieu=%d/%d | Tong R that=%.1f | Thang=%.1f%% | PF(R)=%.3f | 1R ~ %.2f USD",
                valid, n, sum_act, (valid > 0 ? 100.0 * win_act / valid : 0),
                (gl_act > 0 ? gw_act / gl_act : 0), (sum_act != 0 ? net / sum_act : 0));

    Print("========== [STUDY] LENH THUA: LAI NOI CAO NHAT TRUOC KHI DINH SL ==========");
    string mb[7] = {"<0.5R", "0.5-1R", "1-1.5R", "1.5-2R", "2-2.5R", "2.5-3R", ">=3R"};
    for(int b = 0; b < 7; b++)
        PrintFormat("[STUDY] MFE %-7s | lenh thua=%5d | %5.1f%%", mb[b], mfe_bin[b],
                    (losers > 0 ? 100.0 * mfe_bin[b] / losers : 0));

    Print("========== [STUDY] DOI SL VE HOA VON KHI CHAM MOC ==========");
    for(int k = 0; k < STUDY_NX; k++)
        PrintFormat("[STUDY] BE @%.1fR | cuu lenh thua=%5d | giet lenh thang=%5d | Tong R=%8.1f (doi %+8.1f) | Thang=%5.1f%% | PF(R)=%.3f",
                    g_study_x[k], be_save[k], be_kill[k], be_sum[k], be_sum[k] - sum_act,
                    (valid > 0 ? 100.0 * be_win[k] / valid : 0), (be_gl[k] > 0 ? be_gw[k] / be_gl[k] : 0));

    Print("========== [STUDY] KHOA LAI +0.5R KHI CHAM MOC ==========");
    for(int k = 1; k < STUDY_NX; k++)
        PrintFormat("[STUDY] KHOA @%.1fR | cuu lenh thua=%5d | cat lenh thang=%5d | Tong R=%8.1f (doi %+8.1f) | Thang=%5.1f%% | PF(R)=%.3f",
                    g_study_x[k], lk_save[k], lk_kill[k], lk_sum[k], lk_sum[k] - sum_act,
                    (valid > 0 ? 100.0 * lk_win[k] / valid : 0), (lk_gl[k] > 0 ? lk_gw[k] / lk_gl[k] : 0));

    Print("========== [STUDY] TP NGAN HON (SL giu nguyen -1R) ==========");
    for(int t = 0; t < STUDY_NT; t++)
        PrintFormat("[STUDY] TP %.1fR | Tong R=%8.1f (doi %+8.1f) | Thang=%5.1f%% | PF(R)=%.3f",
                    g_study_tp[t], tp_sum[t], tp_sum[t] - sum_act,
                    (valid > 0 ? 100.0 * tp_win[t] / valid : 0), (tp_gl[t] > 0 ? tp_gw[t] / tp_gl[t] : 0));
    PrintFormat("[STUDY] TP 3.0R (that) | Tong R=%8.1f | Thang=%5.1f%% | PF(R)=%.3f",
                sum_act, (valid > 0 ? 100.0 * win_act / valid : 0), (gl_act > 0 ? gw_act / gl_act : 0));

    string fn[2] = {"KHUNG CHART", "KHUNG HTF"};
    for(int f = 0; f < 2; f++) {
        PrintFormat("========== [STUDY] THEO NHIP XU HUONG MAJOR %s (1=CHoCH, +1 moi BOS cung chieu) ==========", fn[f]);
        for(int L = 0; L < 6; L++) {
            if(lg_n[f][L] == 0) continue;
            string ls = IntegerToString(L);
            if(L == 0) ls = "chua ro";
            if(L == 5) ls = "5+";
            PrintFormat("[STUDY] nhip %-7s | lenh=%5d | thang=%5.1f%% | R/lenh: that=%+.3f TP2=%+.3f TP1.5=%+.3f BE@1.5=%+.3f Khoa@2=%+.3f | Tong R that=%+8.1f",
                        ls, lg_n[f][L], 100.0 * lg_win[f][L] / lg_n[f][L],
                        lg_act[f][L] / lg_n[f][L], lg_tp20[f][L] / lg_n[f][L], lg_tp15[f][L] / lg_n[f][L],
                        lg_be15[f][L] / lg_n[f][L], lg_lk20[f][L] / lg_n[f][L], lg_act[f][L]);
        }
    }

    Print("========== [STUDY] THEO GIO VAO LENH (gio SERVER) — R/lenh tach truoc 2025 / tu 2025 ==========");
    for(int h = 0; h < 24; h++) {
        if(hr_n[h] == 0) continue;
        PrintFormat("[STUDY] gio %02d | lenh=%5d | thang=%5.1f%% | R/lenh=%+.3f | truoc2025=%+.3f (%4d) | tu2025=%+.3f (%4d) | Tong R=%+8.1f",
                    h, hr_n[h], 100.0 * hr_win[h] / hr_n[h], hr_r[h] / hr_n[h],
                    (hr_na[h] > 0 ? hr_ra[h] / hr_na[h] : 0), hr_na[h],
                    (hr_nb[h] > 0 ? hr_rb[h] / hr_nb[h] : 0), hr_nb[h], hr_r[h]);
    }
    Print("========== [STUDY] THEO THU TRONG TUAN (gio SERVER) ==========");
    string wdn[7] = {"CN", "T2", "T3", "T4", "T5", "T6", "T7"};
    for(int w = 0; w < 7; w++) {
        if(wd_n[w] == 0) continue;
        PrintFormat("[STUDY] %s | lenh=%5d | thang=%5.1f%% | R/lenh=%+.3f | truoc2025=%+.3f (%4d) | tu2025=%+.3f (%4d) | Tong R=%+8.1f",
                    wdn[w], wd_n[w], 100.0 * wd_win[w] / wd_n[w], wd_r[w] / wd_n[w],
                    (wd_na[w] > 0 ? wd_ra[w] / wd_na[w] : 0), wd_na[w],
                    (wd_nb[w] > 0 ? wd_rb[w] / wd_nb[w] : 0), wd_nb[w], wd_r[w]);
    }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result) {
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        ulong deal_ticket = trans.deal;
        if(HistoryDealSelect(deal_ticket)) {
            long entry_type = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            if(entry_type == DEAL_ENTRY_OUT) {
                ulong pos_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                // Xử lý tracker cho normal positions
                for(int j = ArraySize(g_trackers) - 1; j >= 0; j--) {
                    if(g_trackers[j].ticket == pos_id) {
                        double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                                      + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                                      + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
                        double total_pnl  = g_trackers[j].realized_pnl + profit;
                        double final_rr   = (g_trackers[j].initial_risk_money > 0)
                                          ? (total_pnl / g_trackers[j].initial_risk_money) : 0;
                        long reason = HistoryDealGetInteger(deal_ticket, DEAL_REASON);
                        string reason_str = "👤 ĐÓNG TAY / FORCE CLOSE";
                        if(reason == DEAL_REASON_SL)     reason_str = "🔴 CẮN STOP LOSS";
                        if(reason == DEAL_REASON_TP)     reason_str = "✅ CHẠM TAKE PROFIT";
                        if(reason == DEAL_REASON_EXPERT) reason_str = "🤖 BOT TỰ ĐÓNG (FlexTP/PoolSL/Shield)";
                        string msg = "🏁 <b>TRADE CLOSED</b>\n━━━━━━━━━━━━━━━\n"
                                   + "📝 <b>Lý do:</b> " + reason_str + "\n"
                                   + "📊 <b>RR:</b> " + DoubleToString(final_rr, 2) + "R\n"
                                   + "💰 <b>PnL:</b> " + DoubleToString(total_pnl, 2) + "$\n"
                                   + "💳 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$";
                        Radar.SendMessage(msg);
                        for(int k = j; k < ArraySize(g_trackers) - 1; k++) g_trackers[k] = g_trackers[k+1];
                        ArrayResize(g_trackers, ArraySize(g_trackers) - 1);
                        break;
                    }
                }
            }
        }
    }
}

// ==================================================================
// ENTRY LOGIC (giữ nguyên từ v5.0)
// ==================================================================
void ExecuteTradeLogic() {
    if(g_cmd_paused) { g_filter_text = "⏸ BOT PAUSED — Gửi /start để tiếp tục"; return; }
    string htf = CleanString(SMC_HTF.current_market_phase);
    string maj = CleanString(SMC_LTF.current_market_phase);
    string min = CleanString(SMC_LTF.current_minor_phase);
    int action_type = 0; int rule_idx = -1; double risk_mult = 1.0;
    string loc_filter = "NONE";
    g_action_text = "Đứng ngoài (Không khớp CSV)"; g_filter_text = "";
    for(int i = 0; i < ArraySize(g_matrix_rules); i++) {
        if(g_matrix_rules[i].HTF_State == htf && g_matrix_rules[i].Maj_State == maj && g_matrix_rules[i].Min_State == min) {
            action_type = g_matrix_rules[i].Entry_Type; risk_mult = g_matrix_rules[i].Risk_Multiplier;
            loc_filter = g_matrix_rules[i].Location_Filter; g_action_text = g_matrix_rules[i].Dash_Note;
            rule_idx = i; break;
        }
    }
    if(g_trading_stopped_today || g_account_passed) { g_filter_text = "[SHIELD] " + g_shield_stop_reason; return; }
    if(IsInNewsWindow()) { g_filter_text = "Blocked: News Shield Active"; return; }
    if(rule_idx >= 0) trade.SetExpertMagicNumber(BaseMagicNumber + rule_idx);
    if(action_type == 0) {
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if(IsNormalMagic(OrderGetInteger(ORDER_MAGIC)) && OrderGetString(ORDER_SYMBOL) == _Symbol)
                trade.OrderDelete(ticket);
        }
        return;
    }
    int signal = 0; double sl_price = 0; double entry_zone = 0;
    if(action_type == 1)      { signal = 1;  sl_price = SMC_LTF.current_buy_zone_sl;          entry_zone = SMC_LTF.current_buy_zone_entry; }
    else if(action_type == 2) { signal = -1; sl_price = SMC_LTF.current_sell_zone_sl;         entry_zone = SMC_LTF.current_sell_zone_entry; }
    else if(action_type == 3) { signal = 1;  sl_price = SMC_LTF.current_min_prot_low;         entry_zone = SMC_LTF.current_minor_buy_zone_entry; }
    else if(action_type == 4) { signal = -1; sl_price = SMC_LTF.current_min_prot_high;        entry_zone = SMC_LTF.current_minor_sell_zone_entry; }
    else if(action_type == 5) { signal = 1;  sl_price = SMC_LTF.current_buy_zone_sl;          entry_zone = SMC_LTF.current_minor_buy_zone_entry; }
    else if(action_type == 6) { signal = -1; sl_price = SMC_LTF.current_sell_zone_sl;         entry_zone = SMC_LTF.current_minor_sell_zone_entry; }
    if(signal == 1  && entry_zone == 0) entry_zone = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(signal == -1 && entry_zone == 0) entry_zone = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(signal == 0 || sl_price == 0 || sl_price == EMPTY_VALUE || entry_zone == 0 || entry_zone == EMPTY_VALUE) {
        for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(IsNormalMagic(OrderGetInteger(ORDER_MAGIC)) && OrderGetString(ORDER_SYMBOL) == _Symbol) trade.OrderDelete(t); }
        return;
    }
    if(loc_filter == "HTF_ZONE") {
        bool passed = (signal == 1 && g_gate_buy_open) || (signal == -1 && g_gate_sell_open);
        if(!passed) return;

        // Re-validate zone với data MỚI NHẤT từ SMC_HTF.Update() vừa chạy
        // (UpdateGatekeeperState chạy trước Update nên có thể stale trên bar HBOS)
        if(signal == 1) {
            bool zone_ok = (g_gate_buy_zone_sl > 0 && g_gate_buy_zone_sl == SMC_HTF.current_buy_zone_sl);
            if(!zone_ok) {
                g_gate_buy_open = false;
                g_last_broken_buy_zone_sl = g_gate_buy_zone_sl;
                g_filter_text = "Blocked: HTF Buy Zone vừa bị phá (HBOS/ChoCh trên bar này)";
                return;
            }
        }
        if(signal == -1) {
            bool zone_ok = (g_gate_sell_zone_sl > 0 && g_gate_sell_zone_sl == SMC_HTF.current_sell_zone_sl);
            if(!zone_ok) {
                g_gate_sell_open = false;
                g_last_broken_sell_zone_sl = g_gate_sell_zone_sl;
                g_filter_text = "Blocked: HTF Sell Zone vừa bị phá (HBOS/ChoCh trên bar này)";
                return;
            }
        }
        // Kiểm tra entry price nằm trong zone (strict — không dùng tolerance, không đóng gate)
        // Gate vẫn giữ nguyên → nếu giá quay lại zone thì setup tiếp theo vẫn vào được
        if(signal == -1 && g_gate_sell_zone_sl > 0) {
            double cur_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(cur_ask > g_gate_sell_zone_sl) {
                g_filter_text = "Blocked: Entry sell nằm ngoài biên trên HTF Sell Zone — chờ giá quay lại";
                return;
            }
        }
        if(signal == 1 && g_gate_buy_zone_sl > 0) {
            double cur_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(cur_bid < g_gate_buy_zone_sl) {
                g_filter_text = "Blocked: Entry buy nằm ngoài biên dưới HTF Buy Zone — chờ giá quay lại";
                return;
            }
        }

        if(Inp_ZoneTP_MaxRounds > 0) {
            int rounds = (signal == 1) ? g_zone_buy_profit_rounds : g_zone_sell_profit_rounds;
            if(rounds >= Inp_ZoneTP_MaxRounds) {
                g_filter_text = "Blocked: Đã đủ " + IntegerToString(Inp_ZoneTP_MaxRounds) + " tập lệnh chốt lãi từ Zone này";
                return;
            }
        }
        if(Inp_Gate_MaxOrders > 0) {
            int cnt = (signal == 1) ? g_zone_buy_entry_count : g_zone_sell_entry_count;
            if(cnt >= Inp_Gate_MaxOrders) {
                g_filter_text = "Blocked: Đã đủ " + IntegerToString(Inp_Gate_MaxOrders) + " lệnh/lần mở cổng";
                return;
            }
        }
        // Fresh signal: chặn nếu zone M1 chưa đổi kể từ khi round trước chốt lãi
        if(signal == 1 && g_need_fresh_buy_signal) {
            if(g_buy_stale_sl_ref > 0 && MathAbs(sl_price - g_buy_stale_sl_ref) < _Point) {
                g_filter_text = "Blocked: Chờ BOS/ChoCh M1 mới sau khi chốt round";
                return;
            }
            g_need_fresh_buy_signal = false;
        }
        if(signal == -1 && g_need_fresh_sell_signal) {
            if(g_sell_stale_sl_ref > 0 && MathAbs(sl_price - g_sell_stale_sl_ref) < _Point) {
                g_filter_text = "Blocked: Chờ BOS/ChoCh M1 mới sau khi chốt round";
                return;
            }
            g_need_fresh_sell_signal = false;
        }
        // Khoảng cách từ giá hiện tại đến cạnh entry của M15 Zone
        if(Inp_Gate_MaxPipsFromZone > 0) {
            double ps = GetPipSize(_Symbol);
            double dist = 0;
            if(signal == 1  && g_gate_buy_zone_entry  > 0) dist = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - g_gate_buy_zone_entry)  / ps;
            if(signal == -1 && g_gate_sell_zone_entry > 0) dist = (g_gate_sell_zone_entry - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / ps;
            if(dist > Inp_Gate_MaxPipsFromZone) {
                // Đánh dấu signal này là stale — khi giá quay lại gần zone, signal cũ không được dùng
                // Chỉ setup BOS/ChoCh M1 MỚI hình thành sau khi giá vào zone mới được vào
                if(signal == 1)  { g_need_fresh_buy_signal  = true; g_buy_stale_sl_ref  = sl_price; }
                else             { g_need_fresh_sell_signal = true; g_sell_stale_sl_ref = sl_price; }
                g_filter_text = "Blocked: Giá xa Zone " + DoubleToString(dist, 0) + " pips (>" + DoubleToString(Inp_Gate_MaxPipsFromZone, 0) + ") — signal đánh dấu stale";
                return;
            }
        }
    }
    double pip_size = GetPipSize(_Symbol);
    double buffer_val = SL_Buffer_Pips * pip_size;
    double raw_zone_width = MathAbs(entry_zone - sl_price);
    double entry_buffer_val = raw_zone_width * (Entry_Buffer_Percent / 100.0);
    double current_price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double final_sl = NormalizeDouble((signal == 1) ? (sl_price - buffer_val) : (sl_price + buffer_val), _Digits);
    double order_sl = Inp_No_SL ? 0 : final_sl;
    if(signal == 1)       entry_zone = entry_zone + entry_buffer_val;
    else if(signal == -1) entry_zone = entry_zone - entry_buffer_val;
    entry_zone = NormalizeDouble(entry_zone, _Digits);
    double zone_width_val  = MathAbs(entry_zone - final_sl);
    double zone_width_pips = zone_width_val / pip_size;
    if(zone_width_pips > Max_Zone_SL_Pips) { double max_sl_val = Max_Zone_SL_Pips * pip_size; entry_zone = (signal == 1) ? (final_sl + max_sl_val) : (final_sl - max_sl_val); entry_zone = NormalizeDouble(entry_zone, _Digits); zone_width_val = max_sl_val; }
    if(zone_width_val <= 0) return;
    if(Inp_Buddha_Palm) {
        if(signal == 1) { double htf_sell_top = SMC_HTF.current_sell_zone_sl; double htf_sell_bot = SMC_HTF.current_sell_zone_entry; if(htf_sell_top > 0 && htf_sell_bot > 0) { double max_p = MathMax(htf_sell_top, htf_sell_bot); double min_p = MathMin(htf_sell_top, htf_sell_bot); if(entry_zone >= min_p) { g_filter_text = "Blocked: Đang ngầm Mua trong HTF Sell Zone!"; return; } } }
        else if(signal == -1) { double htf_buy_top = SMC_HTF.current_buy_zone_entry; double htf_buy_bot = SMC_HTF.current_buy_zone_sl; if(htf_buy_top > 0 && htf_buy_bot > 0) { double max_p = MathMax(htf_buy_top, htf_buy_bot); double min_p = MathMin(htf_buy_top, htf_buy_bot); if(entry_zone <= max_p) { g_filter_text = "Blocked: Đang ngầm Bán trong HTF Buy Zone!"; return; } } }
    }
    if(Min_Reward_to_Risk_R > 0 && zone_width_val > 0) {
        double closest_obstacle = 0;
        if(signal == 1) { double obs = SMC_HTF.current_sell_zone_entry; if(obs > entry_zone) closest_obstacle = obs; }
        else if(signal == -1) { double obs = SMC_HTF.current_buy_zone_entry; if(obs > 0 && obs < entry_zone) closest_obstacle = obs; }
        double intended_target = CalcTargetPrice(signal, entry_zone, final_sl, g_matrix_rules[rule_idx]);
        double final_limit_price = 0;
        if(closest_obstacle > 0 && intended_target > 0) { if(signal == 1) final_limit_price = MathMin(closest_obstacle, intended_target); else final_limit_price = MathMax(closest_obstacle, intended_target); }
        else if(closest_obstacle > 0) final_limit_price = closest_obstacle;
        else if(intended_target > 0)  final_limit_price = intended_target;
        if(final_limit_price > 0) {
            double current_rr = MathAbs(final_limit_price - entry_zone) / zone_width_val;
            if(current_rr < Min_Reward_to_Risk_R) { g_filter_text = "Blocked: RR = " + DoubleToString(current_rr, 1) + "R (Đích quá gần)"; return; }
            else g_filter_text = "PASSED: RR = " + DoubleToString(current_rr, 1) + "R";
        } else g_filter_text = "PASSED: Không có cản";
    }
    double bos_lmt_price = 0, bos_risk_val = 0, bos_lmt_tp = 0;
    if(Inp_Entry_Mode == ENTRY_LIMIT_BOS) {
        double raw_bos = (signal == 1) ? SMC_LTF.current_bos_up_level : SMC_LTF.current_bos_dn_level;
        if(raw_bos > 0) { bos_lmt_price = NormalizeDouble(raw_bos, _Digits); bos_risk_val = MathAbs(bos_lmt_price - final_sl); bos_lmt_tp = CalcHardTP(signal, bos_lmt_price, final_sl, g_matrix_rules[rule_idx]); }
    }
    double eff_entry = (bos_lmt_price > 0) ? bos_lmt_price : entry_zone;
    int risk_trades = 0; bool has_limit = false;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long type = PositionGetInteger(POSITION_TYPE); double op = PositionGetDouble(POSITION_PRICE_OPEN); double sl = PositionGetDouble(POSITION_SL);
        if(type == POSITION_TYPE_BUY  && (sl < op || sl == 0)) risk_trades++;
        if(type == POSITION_TYPE_SELL && (sl > op || sl == 0)) risk_trades++;
    }
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i); long magic = OrderGetInteger(ORDER_MAGIC);
        if(!ticket || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(magic)) continue;
        long type = OrderGetInteger(ORDER_TYPE); double o_sl = OrderGetDouble(ORDER_SL); double o_en = OrderGetDouble(ORDER_PRICE_OPEN);
        bool is_buy_lmt  = (type == ORDER_TYPE_BUY_LIMIT  || type == ORDER_TYPE_BUY_STOP);
        bool is_sell_lmt = (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP);
        bool perfect = false;
        if(signal == 1  && is_buy_lmt  && MathAbs(o_sl - order_sl) < 10 * _Point && MathAbs(o_en - eff_entry) < 10 * _Point) perfect = true;
        if(signal == -1 && is_sell_lmt && MathAbs(o_sl - order_sl) < 10 * _Point && MathAbs(o_en - eff_entry) < 10 * _Point) perfect = true;
        if(perfect) { has_limit = true; risk_trades++; } else trade.OrderDelete(ticket);
    }
    if(has_limit || risk_trades >= Inp_Max_Risk_Trades) return;
    if(signal == 1  && MathAbs(sl_price - g_last_traded_buy_sl)  < 10 * _Point) return;
    if(signal == -1 && MathAbs(sl_price - g_last_traded_sell_sl) < 10 * _Point) return;
    if(Inp_Min_Entry_Dist_Pips > 0) {
        double min_dist = Inp_Min_Entry_Dist_Pips * pip_size; bool too_close = false;
        for(int i = 0; i < PositionsTotal() && !too_close; i++) {
            ulong t = PositionGetTicket(i);
            if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol || !IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            long tp2 = PositionGetInteger(POSITION_TYPE);
            if(signal == 1 && tp2 != POSITION_TYPE_BUY) continue;
            if(signal == -1 && tp2 != POSITION_TYPE_SELL) continue;
            if(MathAbs(eff_entry - PositionGetDouble(POSITION_PRICE_OPEN)) < min_dist) too_close = true;
        }
        for(int i = 0; i < OrdersTotal() && !too_close; i++) {
            ulong t = OrderGetTicket(i);
            if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) continue;
            long ot = OrderGetInteger(ORDER_TYPE);
            bool is_buy  = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
            bool is_sell = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
            if(signal == 1 && !is_buy) continue; if(signal == -1 && !is_sell) continue;
            if(MathAbs(eff_entry - OrderGetDouble(ORDER_PRICE_OPEN)) < min_dist) too_close = true;
        }
        if(too_close) { g_filter_text = "Blocked: Entry quá sát lệnh cũ"; return; }
    }
    string order_cmt = g_matrix_rules[rule_idx].Dash_Note;
    int dash_pos = StringFind(order_cmt, " - "); if(dash_pos > 0) order_cmt = StringSubstr(order_cmt, 0, dash_pos);
    double dist_to_sl_val  = MathAbs(current_price - final_sl);
    double dist_to_sl_pips = dist_to_sl_val / pip_size;
    // Lọc SL quá hẹp. Rủi ro tính theo đúng loại lệnh sắp gửi (cùng điều kiện với
    // force_mkt bên dưới): lệnh thị trường tính từ giá hiện tại, lệnh limit tính theo
    // mức limit. Backtest 43 tháng: lệnh SL dưới 100 pip chiếm 42% số lệnh (73% năm
    // 2022) nhưng lợi nhuận xấp xỉ 0 ở mọi cấu hình.
    if(Inp_Min_SL_Pips > 0) {
        bool   will_mkt  = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (dist_to_sl_pips <= Market_vs_Limit_Pips);
        double plan_risk = will_mkt ? dist_to_sl_val : ((bos_lmt_price > 0) ? bos_risk_val : zone_width_val);
        double plan_pips = plan_risk / pip_size;
        if(plan_pips < Inp_Min_SL_Pips) {
            g_filter_text = "Blocked: SL chi " + DoubleToString(plan_pips, 0) + " pip (< " + DoubleToString(Inp_Min_SL_Pips, 0) + ")";
            return;
        }
    }
    bool success = false;
    double mkt_tp      = CalcHardTP(signal, current_price, final_sl, g_matrix_rules[rule_idx]);
    double lmt_tp      = CalcHardTP(signal, entry_zone,    final_sl, g_matrix_rules[rule_idx]);
    double eff_mkt_tp  = Inp_FlexTP_Enabled ? 0 : mkt_tp;
    double eff_lmt_tp  = Inp_FlexTP_Enabled ? 0 : lmt_tp;
    double eff_bos_tp  = Inp_FlexTP_Enabled ? 0 : bos_lmt_tp;
    // Kẹp SL/TP theo stops level của sàn, tính riêng cho từng loại lệnh vì mỗi loại
    // có giá khác nhau (thị trường / limit tại BOS / limit tại mép zone).
    double bos_ref = (bos_lmt_price > 0) ? bos_lmt_price : current_price;
    double sl_mkt  = ClampStopLevel(current_price, order_sl, signal, false);
    double sl_bos  = ClampStopLevel(bos_ref,       order_sl, signal, false);
    double sl_lmt  = ClampStopLevel(entry_zone,    order_sl, signal, false);
    eff_mkt_tp     = ClampStopLevel(current_price, eff_mkt_tp, signal, true);
    eff_bos_tp     = ClampStopLevel(bos_ref,       eff_bos_tp, signal, true);
    eff_lmt_tp     = ClampStopLevel(entry_zone,    eff_lmt_tp, signal, true);
    if(signal == 1) {
        bool force_mkt = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (dist_to_sl_pips <= Market_vs_Limit_Pips);
        if(force_mkt) { if(sl_mkt < 0) { g_filter_text = "Blocked: SL nam sai phia so voi gia vao"; return; } double lot = CalculateLotSize(dist_to_sl_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.Buy(lot, _Symbol, current_price, sl_mkt, eff_mkt_tp, order_cmt); }
        else if(bos_lmt_price > 0 && current_price > bos_lmt_price) { if(sl_bos < 0) { g_filter_text = "Blocked: SL nam sai phia so voi gia limit BOS"; return; } double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.BuyLimit(lot, bos_lmt_price, _Symbol, sl_bos, eff_bos_tp, ORDER_TIME_GTC, 0, order_cmt); }
        else if(current_price > entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) { if(sl_lmt < 0) { g_filter_text = "Blocked: SL nam sai phia so voi mep zone"; return; } double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.BuyLimit(lot, entry_zone, _Symbol, sl_lmt, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt); }
        if(success || trade.ResultRetcode() == 10009) g_last_traded_buy_sl = sl_price;
    } else if(signal == -1) {
        bool force_mkt = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (dist_to_sl_pips <= Market_vs_Limit_Pips);
        if(force_mkt) { if(sl_mkt < 0) { g_filter_text = "Blocked: SL nam sai phia so voi gia vao"; return; } double lot = CalculateLotSize(dist_to_sl_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.Sell(lot, _Symbol, current_price, sl_mkt, eff_mkt_tp, order_cmt); }
        else if(bos_lmt_price > 0 && current_price < bos_lmt_price) { if(sl_bos < 0) { g_filter_text = "Blocked: SL nam sai phia so voi gia limit BOS"; return; } double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.SellLimit(lot, bos_lmt_price, _Symbol, sl_bos, eff_bos_tp, ORDER_TIME_GTC, 0, order_cmt); }
        else if(current_price < entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) { if(sl_lmt < 0) { g_filter_text = "Blocked: SL nam sai phia so voi mep zone"; return; } double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.SellLimit(lot, entry_zone, _Symbol, sl_lmt, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt); }
        if(success || trade.ResultRetcode() == 10009) g_last_traded_sell_sl = sl_price;
    }
    if(success || trade.ResultRetcode() == 10009) {
        if(loc_filter == "HTF_ZONE") {
            if(signal == 1) g_zone_buy_entry_count++;
            else            g_zone_sell_entry_count++;
        }
        double display_tp = (bos_lmt_price > 0) ? bos_lmt_tp : lmt_tp;
        double sl_pips    = MathAbs(eff_entry - final_sl) / pip_size;
        string msg = "🛒 <b>ORDER PLACED: KHỚP LỆNH SMC</b>\n━━━━━━━━━━━━━━━\n"
                   + "🏷️ <b>Rule:</b> " + g_matrix_rules[rule_idx].Dash_Note + "\n"
                   + "📍 <b>Entry:</b> " + DoubleToString(eff_entry, _Digits) + "\n"
                   + "🛡️ <b>SL:</b> " + DoubleToString(final_sl, _Digits) + " (" + DoubleToString(sl_pips, 1) + " pips)\n"
                   + "🎯 <b>TP:</b> " + DoubleToString(display_tp, _Digits);
        Radar.SendMessageWithPhoto(msg);
    }
}

void CheckFlexTP() {
    if(!Inp_FlexTP_Enabled) return;
    if(MarketClosedBackoff()) return;
    double pip_size = GetPipSize(_Symbol); double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double buy_usd = 0, sell_usd = 0, buy_pips = 0, sell_pips = 0;
    int buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsNormalMagic(magic)) continue;
        long   type       = PositionGetInteger(POSITION_TYPE);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double usd        = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
        double cur_price  = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double pips       = (type == POSITION_TYPE_BUY) ? (cur_price - open_price) / pip_size : (open_price - cur_price) / pip_size;
        if(type == POSITION_TYPE_BUY)  { buy_usd  += usd; buy_pips  += pips; buy_cnt++;  }
        else                           { sell_usd += usd; sell_pips += pips; sell_cnt++; }
    }
    if(buy_cnt == 0 && sell_cnt == 0) return;
    double all_usd  = buy_usd  + sell_usd;
    double all_pips = buy_pips + sell_pips;
    double pct_buy  = (balance > 0) ? (buy_usd  / balance * 100.0) : 0;
    double pct_sell = (balance > 0) ? (sell_usd / balance * 100.0) : 0;
    double pct_all  = (balance > 0) ? (all_usd  / balance * 100.0) : 0;
    bool close_all  = (Inp_FlexTP_Percent > 0 && pct_all  >= Inp_FlexTP_Percent)
                   || (Inp_FlexTP_Pips    > 0 && all_pips >= Inp_FlexTP_Pips);
    bool close_buy  = !close_all && buy_cnt  > 0
                   && ((Inp_FlexTP_Percent > 0 && pct_buy  >= Inp_FlexTP_Percent)
                    || (Inp_FlexTP_Pips    > 0 && buy_pips >= Inp_FlexTP_Pips));
    bool close_sell = !close_all && sell_cnt > 0
                   && ((Inp_FlexTP_Percent > 0 && pct_sell >= Inp_FlexTP_Percent)
                    || (Inp_FlexTP_Pips    > 0 && sell_pips >= Inp_FlexTP_Pips));
    if(!close_all && !close_buy && !close_sell) return;
    bool any_closed = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsNormalMagic(magic)) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        bool do_close = close_all
                     || (close_buy  && type == POSITION_TYPE_BUY)
                     || (close_sell && type == POSITION_TYPE_SELL);
        if(do_close) {
            if(trade.PositionClose(ticket)) any_closed = true;
            else {
                uint rc = trade.ResultRetcode();
                NoteRetcode(rc);
                Print("[FLEX_TP] Close FAILED ticket=", ticket, " retcode=", rc, " (", trade.ResultRetcodeDescription(), ")");
                if(IsRetryableRetcode(rc)) QueueCloseRetry(ticket, "FLEX_TP");
            }
        }
    }
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(!ticket || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) continue;
        long ot = OrderGetInteger(ORDER_TYPE);
        bool is_buy_ord  = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
        bool is_sell_ord = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
        bool do_del = close_all || (close_buy && is_buy_ord) || (close_sell && is_sell_ord);
        if(do_del) trade.OrderDelete(ticket);
    }
    if(any_closed) {
        string dir = close_all ? "BUY+SELL" : (close_buy ? "BUY" : "SELL");
        double rep_usd  = close_all ? all_usd  : (close_buy ? buy_usd  : sell_usd);
        double rep_pct  = close_all ? pct_all  : (close_buy ? pct_buy  : pct_sell);
        Radar.SendMessage("🏆 <b>FLEX TP: CHỐT LÃI LINH HOẠT</b>\n📊 " + dir + ": +"
            + DoubleToString(rep_pct, 2) + "% / +" + DoubleToString(rep_usd, 2) + "$\n"
            + "💳 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$");
    }
}

// ==================================================================
// POOL STOP-LOSS
// ==================================================================
void CheckPoolSL() {
    if(Inp_Pool_SL_Percent <= 0) return;
    if(MarketClosedBackoff()) return;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return;
    double limit_usd = balance * (Inp_Pool_SL_Percent / 100.0);
    double buy_pnl = 0, sell_pnl = 0;
    int    buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long   type = PositionGetInteger(POSITION_TYPE);
        double pnl  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
        if(type == POSITION_TYPE_BUY)  { buy_pnl  += pnl; buy_cnt++;  }
        else                           { sell_pnl += pnl; sell_cnt++; }
    }
    bool close_buy  = (buy_cnt  > 0 && buy_pnl  <= -limit_usd);
    bool close_sell = (sell_cnt > 0 && sell_pnl <= -limit_usd);
    if(!close_buy && !close_sell) return;
    bool closed_buy = false, closed_sell = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        if(close_buy && type == POSITION_TYPE_BUY) {
            if(trade.PositionClose(ticket)) closed_buy = true;
            else {
                uint rc = trade.ResultRetcode();
                NoteRetcode(rc);
                Print("[POOL_SL] Close FAILED ticket=", ticket, " retcode=", rc, " (", trade.ResultRetcodeDescription(), ")");
                if(IsRetryableRetcode(rc)) QueueCloseRetry(ticket, "POOL_SL");
            }
        }
        if(close_sell && type == POSITION_TYPE_SELL) {
            if(trade.PositionClose(ticket)) closed_sell = true;
            else {
                uint rc = trade.ResultRetcode();
                NoteRetcode(rc);
                Print("[POOL_SL] Close FAILED ticket=", ticket, " retcode=", rc, " (", trade.ResultRetcodeDescription(), ")");
                if(IsRetryableRetcode(rc)) QueueCloseRetry(ticket, "POOL_SL");
            }
        }
    }
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(!ticket || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) continue;
        long ot = OrderGetInteger(ORDER_TYPE);
        bool is_buy  = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
        bool is_sell = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
        if((close_buy && is_buy) || (close_sell && is_sell)) trade.OrderDelete(ticket);
    }
    if(closed_buy) {
        g_need_fresh_buy_signal = true;
        g_buy_stale_sl_ref = SMC_LTF.current_buy_zone_sl;
        double pct = MathAbs(buy_pnl) / balance * 100.0;
        Radar.SendMessage("🛑 <b>POOL SL: ĐÓNG TẬP LỆNH BUY</b>\n━━━━━━━━━━━━━━━\n"
            + "💸 <b>Lỗ:</b> " + DoubleToString(buy_pnl, 2) + "$ (-" + DoubleToString(pct, 2) + "%)\n"
            + "🎚️ <b>Ngưỡng Pool SL:</b> " + DoubleToString(Inp_Pool_SL_Percent, 1) + "%\n"
            + "✅ <b>Pool SELL vẫn tiếp tục chạy</b>\n"
            + "💳 <b>Balance:</b> " + DoubleToString(balance, 2) + "$");
    }
    if(closed_sell) {
        g_need_fresh_sell_signal = true;
        g_sell_stale_sl_ref = SMC_LTF.current_sell_zone_sl;
        double pct = MathAbs(sell_pnl) / balance * 100.0;
        Radar.SendMessage("🛑 <b>POOL SL: ĐÓNG TẬP LỆNH SELL</b>\n━━━━━━━━━━━━━━━\n"
            + "💸 <b>Lỗ:</b> " + DoubleToString(sell_pnl, 2) + "$ (-" + DoubleToString(pct, 2) + "%)\n"
            + "🎚️ <b>Ngưỡng Pool SL:</b> " + DoubleToString(Inp_Pool_SL_Percent, 1) + "%\n"
            + "✅ <b>Pool BUY vẫn tiếp tục chạy</b>\n"
            + "💳 <b>Balance:</b> " + DoubleToString(balance, 2) + "$");
    }
}

// ==================================================================
// TELEGRAM REMOTE COMMANDS
// ==================================================================
void SendStatusMessage() {
    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
    double open_pnl = equity - balance;
    double open_pct = (balance > 0) ? (open_pnl / balance * 100.0) : 0;
    int buy_cnt = 0, sell_cnt = 0;
    double buy_pnl = 0, sell_pnl = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong tk = PositionGetTicket(i);
        if(!PositionSelectByTicket(tk) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { buy_cnt++; buy_pnl += pnl; }
        else { sell_cnt++; sell_pnl += pnl; }
    }
    string bot_st  = g_cmd_paused ? "⏸ PAUSED" : (g_trading_stopped_today ? "🛑 STOPPED (DD)" : "✅ RUNNING");
    string g_buy   = g_gate_buy_open  ? "🔓 OPEN" : "🔒 LOCK";
    string g_sell  = g_gate_sell_open ? "🔓 OPEN" : "🔒 LOCK";
    string r_lim   = (Inp_ZoneTP_MaxRounds > 0) ? ("/" + (string)Inp_ZoneTP_MaxRounds) : "";
    string e_lim   = (Inp_Gate_MaxOrders   > 0) ? ("/" + (string)Inp_Gate_MaxOrders)   : "";
    Radar.SendMessage(
        "📊 <b>BOT STATUS — " + _Symbol + "</b>\n━━━━━━━━━━━━━━━\n"
        + "🤖 <b>Trạng thái:</b> " + bot_st + "\n"
        + "💰 <b>Balance:</b> "    + DoubleToString(balance,  2) + "$\n"
        + "📈 <b>Equity:</b> "     + DoubleToString(equity,   2) + "$\n"
        + "📊 <b>Open P&L:</b> "   + (open_pnl >= 0 ? "+" : "") + DoubleToString(open_pnl, 2)
                                   + "$ (" + (open_pct >= 0 ? "+" : "") + DoubleToString(open_pct, 2) + "%)\n"
        + "━━━━━━━━━━━━━━━\n"
        + "🎯 <b>Gate:</b> Buy " + g_buy + " | Sell " + g_sell + "\n"
        + "📦 <b>Lệnh mở:</b> Buy " + (string)buy_cnt  + " (" + (buy_pnl  >= 0 ? "+" : "") + DoubleToString(buy_pnl,  2) + "$)"
                              + " | Sell " + (string)sell_cnt + " (" + (sell_pnl >= 0 ? "+" : "") + DoubleToString(sell_pnl, 2) + "$)\n"
        + "🔄 <b>Rounds:</b> Buy " + (string)g_zone_buy_profit_rounds  + r_lim
                             + " | Sell " + (string)g_zone_sell_profit_rounds + r_lim + "\n"
        + "🚦 <b>Entries:</b> Buy " + (string)g_zone_buy_entry_count  + e_lim
                              + " | Sell " + (string)g_zone_sell_entry_count + e_lim);
}

void SendConfigMessage() {
    string tf_t = EnumToString(Trend_Timeframe); StringReplace(tf_t, "PERIOD_", "");
    string tf_h = EnumToString(HTF_Timeframe);   StringReplace(tf_h, "PERIOD_", "");
    string risk_str = UseRiskPerTrade
        ? (DoubleToString(RiskPercent, 2) + "%/lệnh")
        : ("Fixed " + DoubleToString(FixedLotSize, 2) + " lot");
    Radar.SendMessage(
        "⚙️ <b>BOT CONFIG — " + _Symbol + "</b>\n━━━━━━━━━━━━━━━\n"
        + "🔢 <b>Magic:</b> " + (string)BaseMagicNumber + "\n"
        + "⏱ <b>T-L-S:</b> T=" + tf_t + " | L=" + tf_h + " | S=M1\n"
        + "━━━━━━━━━━━━━━━\n"
        + "💵 <b>Risk:</b> " + risk_str + "\n"
        + "🛡 <b>Daily DD limit:</b> " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%\n"
        + "🎯 <b>Profit limit/ngày:</b> " + (Inp_DailyProfitLimit > 0 ? DoubleToString(Inp_DailyProfitLimit, 1) + "%" : "Không giới hạn") + "\n"
        + "🏆 <b>Auto-pass target:</b> " + DoubleToString(Inp_AutoPassTarget, 0) + "$\n"
        + "🌀 <b>Pool SL:</b> " + (Inp_Pool_SL_Percent > 0 ? DoubleToString(Inp_Pool_SL_Percent, 1) + "%" : "Tắt") + "\n"
        + "━━━━━━━━━━━━━━━\n"
        + "🚪 <b>Zone Round Limit:</b> " + (string)Inp_ZoneTP_MaxRounds + "\n"
        + "📦 <b>Gate Max Orders:</b> " + (string)Inp_Gate_MaxOrders + "\n"
        + "📏 <b>Max Pips From Zone:</b> " + (Inp_Gate_MaxPipsFromZone > 0 ? DoubleToString(Inp_Gate_MaxPipsFromZone, 0) : "Không giới hạn") + "\n"
        + "💥 <b>Zone Break Tolerance:</b> " + DoubleToString(Zone_Break_Tolerance_Pct, 0) + "%\n"
        + "🙏 <b>Buddha's Palm:</b> " + (Inp_Buddha_Palm ? "ON" : "OFF") + "\n"
        + "🚦 <b>H1 Gate Filter:</b> " + (Inp_Enable_H1_Gate_Filter ? "ON" : "OFF") + "\n"
        + "━━━━━━━━━━━━━━━\n"
        + "📐 <b>Entry Mode:</b> " + EnumToString(Inp_Entry_Mode) + "\n"
        + "💹 <b>FlexTP:</b> " + (Inp_FlexTP_Enabled ? ("ON (" + DoubleToString(Inp_FlexTP_Percent, 1) + "%)") : "OFF") + "\n"
        + "📸 <b>Auto Screenshot:</b> " + (Inp_SendScreenshot ? "ON" : "OFF"));
}

void ProcessBotCommand(string cmd) {
    // Strip @BotName suffix (group chats)
    int at = StringFind(cmd, "@");
    if(at > 0) cmd = StringSubstr(cmd, 0, at);

    if(cmd == "/start") {
        g_cmd_paused = false;
        Radar.SendMessage("✅ <b>BOT STARTED</b>\n🤖 Bot đã được bật lại, sẵn sàng vào lệnh bình thường.");
    }
    else if(cmd == "/stop") {
        g_cmd_paused = true;
        int cancelled = 0;
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong tk = OrderGetTicket(i);
            if(!tk || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) continue;
            if(trade.OrderDelete(tk)) cancelled++;
        }
        Radar.SendMessage("⏸ <b>BOT PAUSED</b>\n🚫 Không vào lệnh mới\n🗑️ Đã hủy <b>" + (string)cancelled
            + "</b> lệnh chờ\n✅ Lệnh đang chạy vẫn được quản lý bình thường\n\n➡️ Gửi /start để tiếp tục");
    }
    else if(cmd == "/closeall") {
        int closed_pos = 0, closed_ord = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong tk = PositionGetTicket(i);
            if(!PositionSelectByTicket(tk) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            if(trade.PositionClose(tk)) closed_pos++;
        }
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong tk = OrderGetTicket(i);
            if(!tk || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsNormalMagic(OrderGetInteger(ORDER_MAGIC))) continue;
            if(trade.OrderDelete(tk)) closed_ord++;
        }
        g_cmd_paused = true;
        Radar.SendMessage("🔴 <b>CLOSE ALL EXECUTED</b>\n"
            + "✅ Đã đóng <b>" + (string)closed_pos + "</b> lệnh\n"
            + "🗑️ Đã hủy <b>" + (string)closed_ord + "</b> lệnh chờ\n"
            + "⏸ Bot đang <b>PAUSED</b>\n"
            + "💳 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n\n"
            + "➡️ Gửi /start để tiếp tục giao dịch");
    }
    else if(cmd == "/status") {
        SendStatusMessage();
    }
    else if(cmd == "/chart") {
        Radar.SendPhoto("📸 <b>Chart hiện tại — " + _Symbol + "</b>\n🕐 " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
    }
    else if(cmd == "/config") {
        SendConfigMessage();
    }
    else if(cmd == "/resetshield") {
        g_trading_stopped_today = false;
        g_account_passed        = false;
        g_shield_stop_reason    = "";
        // Đặt lại mốc balance đầu ngày = balance hiện tại, để DD%/Profit% tính lại từ đây,
        // tránh kích hoạt lại ngay nếu equity hiện tại vẫn đang thấp/cao hơn mốc cũ.
        g_sod_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        GlobalVariableSet(GVKey("stopped_today"), 0.0);
        GlobalVariableSet(GVKey("sod_balance"),   g_sod_balance);
        Radar.SendMessage("🔓 <b>SHIELD RESET</b>\n✅ Đã gỡ trạng thái STOPPED.\n"
            + "🔄 Mốc Daily DD/Profit được tính lại từ balance hiện tại: " + DoubleToString(g_sod_balance, 2) + "$\n"
            + "⚠️ Nếu Inp_AutoPassTarget vẫn thấp hơn balance hiện tại, Shield sẽ tự kích hoạt lại ngay.");
    }
}

void CheckTelegramCommands() {
    if(MQLInfoInteger(MQL_TESTER)) return;  // không chạy trong Strategy Tester
    if(Inp_BotToken == "" || Inp_BotToken == "YOUR_BOT_TOKEN_HERE" || Inp_ChatID == "") return;
    // Dùng GetTickCount64() (giờ hệ thống thực) thay vì TimeCurrent() (giờ theo tick giá)
    // để polling đúng nhịp 3s kể cả khi thị trường ít tick, không lệ thuộc OnTick().
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

        // Extract update_id
        int n = uid_pos + 12;
        int n_end = n;
        while(n_end < StringLen(json) && StringGetCharacter(json, n_end) >= '0' && StringGetCharacter(json, n_end) <= '9') n_end++;
        long uid = (long)StringSubstr(json, n, n_end - n);
        if(uid > g_tg_last_update_id) g_tg_last_update_id = uid;

        // Isolate this update block
        int next_uid = StringFind(json, "\"update_id\":", n_end);
        int blk_end  = (next_uid > 0) ? next_uid : StringLen(json);
        string blk   = StringSubstr(json, uid_pos, blk_end - uid_pos);

        // Extract text
        string text = "";
        int tp = StringFind(blk, "\"text\":\"");
        if(tp >= 0) {
            int ts = tp + 8, te = StringFind(blk, "\"", ts);
            if(te > ts) text = StringSubstr(blk, ts, te - ts);
        }

        // Extract chat id (handle negative group IDs)
        string chat_id_str = "";
        int cp = StringFind(blk, "\"chat\":{\"id\":");
        if(cp >= 0) {
            int cs = cp + 13, ce = cs;
            if(StringGetCharacter(blk, ce) == '-') ce++;
            while(ce < StringLen(blk) && StringGetCharacter(blk, ce) >= '0' && StringGetCharacter(blk, ce) <= '9') ce++;
            chat_id_str = StringSubstr(blk, cs, ce - cs);
        }

        if(text != "" && chat_id_str == Inp_ChatID)
            ProcessBotCommand(text);

        pos = blk_end;
    }
}

// ==================================================================
// DASHBOARD
// ==================================================================
void DashLabel(string name, int x, int y, color clr, int fsz, string text) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetString (0, name, OBJPROP_FONT,       "Arial");
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fsz);
    ObjectSetString (0, name, OBJPROP_TEXT,      text);
}

void UpdateDashboard() {
    string s_t = EnumToString(Trend_Timeframe); StringReplace(s_t, "PERIOD_", "");
    string s_l = EnumToString(HTF_Timeframe);   StringReplace(s_l, "PERIOD_", "");
    string s_s = EnumToString(_Period);          StringReplace(s_s, "PERIOD_", "");
    string t_pad = s_t; while(StringLen(t_pad) < 4) t_pad += " ";
    string l_pad = s_l; while(StringLen(l_pad) < 4) l_pad += " ";
    string s_pad = s_s; while(StringLen(s_pad) < 4) s_pad += " ";
    int risk_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong tk = PositionGetTicket(i);
        if(!PositionSelectByTicket(tk) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsNormalMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long pt = PositionGetInteger(POSITION_TYPE); double op = PositionGetDouble(POSITION_PRICE_OPEN); double sl = PositionGetDouble(POSITION_SL);
        if(pt == POSITION_TYPE_BUY  && (sl < op || sl == 0)) risk_cnt++;
        if(pt == POSITION_TYPE_SELL && (sl > op || sl == 0)) risk_cnt++;
    }
    color c_dark = clrBlack; color c_gray = C'130,130,130'; color c_sep = C'190,190,190';
    color c_ok = C'0,140,0'; color c_bad = C'210,0,0';
    color buy_clr  = g_gate_buy_open  ? c_ok : c_bad;
    color sell_clr = g_gate_sell_open ? c_ok : c_bad;
    color shd_clr  = g_trading_stopped_today ? c_bad : c_ok;
    color rsk_clr  = (risk_cnt >= Inp_Max_Risk_Trades) ? c_bad : c_ok;
    string buy_val  = g_gate_buy_open  ? "OPEN" : "LOCK";
    string sell_val = g_gate_sell_open ? "OPEN" : "LOCK";
    string shd_val  = g_trading_stopped_today ? "STOPPED" : "ACTIVE";
    string rsk_val  = IntegerToString(risk_cnt) + "/" + IntegerToString(Inp_Max_Risk_Trades);
    // g_cmd_paused đọc trực tiếp mỗi tick → hiện ngay khi /stop, không cần chờ bar mới như g_filter_text
    string flt_txt = g_cmd_paused ? "⏸ BOT PAUSED — Gửi /start để tiếp tục" : ((g_filter_text == "") ? " " : g_filter_text);
    color  flt_clr = c_gray;
    if(g_cmd_paused) flt_clr = c_bad;
    else if(StringFind(flt_txt, "PASSED") >= 0) flt_clr = c_ok;
    else if(StringFind(flt_txt, "Blocked") >= 0 || StringFind(flt_txt, "[SHIELD]") >= 0) flt_clr = c_bad;
    ObjectDelete(0, "BOT_DASH_FLT");
    DashLabel("BOT_DASH_T",    8, 25, c_dark, 7, t_pad + ": " + SMC_TREND.current_market_phase);
    DashLabel("BOT_DASH_L",    8, 42, c_dark, 7, l_pad + ": " + SMC_HTF.current_market_phase);
    DashLabel("BOT_DASH_SMAJ", 8, 59, c_dark, 7, s_pad + ": Major:  " + SMC_LTF.current_market_phase);
    DashLabel("BOT_DASH_SMIN", 8, 76, c_gray, 7, "        Minor:  " + SMC_LTF.current_minor_phase);
    DashLabel("BOT_DASH_ACT",  8, 98, clrMagenta, 7, g_action_text);
    DashLabel("BOT_DASH_BUY_K", 8,   120, c_dark,   8, "Buy:");
    DashLabel("BOT_DASH_BUY_V", 46,  120, buy_clr,  8, buy_val);
    DashLabel("BOT_DASH_SLL_K", 100, 120, c_dark,   8, "Sell:");
    DashLabel("BOT_DASH_SLL_V", 142, 120, sell_clr, 8, sell_val);
    DashLabel("BOT_DASH_SHD_K", 8,   137, c_dark,  7, "Shield:");
    DashLabel("BOT_DASH_SHD_V", 60,  137, shd_clr, 7, shd_val);
    DashLabel("BOT_DASH_RSK_K", 135, 137, c_dark,  7, "Risk:");
    DashLabel("BOT_DASH_RSK_V", 170, 137, rsk_clr, 7, rsk_val);
    DashLabel("BOT_DASH_FLT2", 8, 154, flt_clr, 7, flt_txt);
    // Gate Entry Count: số lệnh đã đặt / giới hạn cho mỗi lần mở cổng, theo từng chiều
    string gate_str;
    if(Inp_Gate_MaxOrders > 0)
        gate_str = "Gate:   Buy " + IntegerToString(g_zone_buy_entry_count)  + "/" + IntegerToString(Inp_Gate_MaxOrders)
                  + "  Sell "      + IntegerToString(g_zone_sell_entry_count) + "/" + IntegerToString(Inp_Gate_MaxOrders);
    else
        gate_str = "Gate:   Buy " + IntegerToString(g_zone_buy_entry_count)
                  + "  Sell "      + IntegerToString(g_zone_sell_entry_count) + " (Unlimited)";
    DashLabel("BOT_DASH_GTE", 8, 168, c_gray, 7, gate_str);
    // Zone Round Limit: số "tập lệnh" đã chốt lãi / giới hạn cho phép, theo từng chiều
    string zone_rd_str;
    if(Inp_ZoneTP_MaxRounds > 0)
        zone_rd_str = "ZoneTP: Buy " + IntegerToString(g_zone_buy_profit_rounds)  + "/" + IntegerToString(Inp_ZoneTP_MaxRounds)
                     + "  Sell "      + IntegerToString(g_zone_sell_profit_rounds) + "/" + IntegerToString(Inp_ZoneTP_MaxRounds);
    else
        zone_rd_str = "ZoneTP: Buy " + IntegerToString(g_zone_buy_profit_rounds)
                     + "  Sell "      + IntegerToString(g_zone_sell_profit_rounds) + " (Unlimited)";
    DashLabel("BOT_DASH_ZRD", 8, 182, c_gray, 7, zone_rd_str);
}

// ==================================================================
// LIFECYCLE
// ==================================================================
int OnInit() {
    Print("DA NẠP ENGINE TLS BOT!");
    if(!LoadMatrixCSV()) return INIT_FAILED;
    trade.SetDeviationInPoints(Inp_Slippage_Points); // tránh requote bị từ chối khi giá biến động nhanh lúc đóng/mở lệnh
    Radar.Init(Inp_BotToken, Inp_ChatID, Inp_SendScreenshot);
    SMC_LTF.Init(_Symbol, _Period, "TLS_LTF_", false, true, false,
        clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
        PeriodsInMajorSwing, PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
    SMC_HTF.Init(_Symbol, HTF_Timeframe, "TLS_HTF_", true, false, true,
        HTF_BuyZoneColor, HTF_SellZoneColor, HTF_KeyLevelColor, HTF_BOS_Up_Color, HTF_BOS_Dn_Color, clrNONE, clrNONE,
        HTF_PeriodsInMajorSwing, HTF_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
    SMC_TREND.Init(_Symbol, Trend_Timeframe, "TLS_TREND_", true, false, false,
        clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
        Trend_PeriodsInMajorSwing, Trend_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
    if(MQLInfoInteger(MQL_TESTER)) {
        // Số nến swing lấy như khung Trend: chỉ dùng để phân loại xu hướng / zone lúc vào lệnh.
        SMC_H4.Init(_Symbol, PERIOD_H4, "TLS_H4_", true, false, false,
            clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
            Trend_PeriodsInMajorSwing, Trend_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
        SMC_D1.Init(_Symbol, PERIOD_D1, "TLS_D1_", true, false, false,
            clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE,
            Trend_PeriodsInMajorSwing, Trend_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
    }
    string s_trend = EnumToString(Trend_Timeframe); StringReplace(s_trend, "PERIOD_", "");
    string s_htf   = EnumToString(HTF_Timeframe);   StringReplace(s_htf,   "PERIOD_", "");
    string s_ltf   = EnumToString(_Period);          StringReplace(s_ltf,   "PERIOD_", "");
    string msg = "🟢 <b>SYSTEM STARTED: TLS BOT v1.0</b>\n━━━━━━━━━━━━━━━\n"
               + "💰 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n"
               + "⚙️ <b>T-L-S:</b> " + _Symbol + " | T=" + s_trend + " | L=" + s_htf + " | S=" + s_ltf + "\n"
               + "🛡️ <b>Mục tiêu:</b> " + DoubleToString(Inp_AutoPassTarget, 0)
               + "$ | DD ngày: " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
    LoadState();
    RebuildTrackers();
    Radar.SendMessage(msg);
    EventSetMillisecondTimer(100); // 100ms: retry queue nhanh + Telegram polling (rate-limited 3s riêng)
    return(INIT_SUCCEEDED);
}

void OnTimer() {
    ProcessCloseRetryQueue();
    CheckTelegramCommands();
}

void OnDeinit(const int reason) {
    EventKillTimer();
    SaveState();
    ObjectsDeleteAll(0, "TLS_HTF_");
    ObjectsDeleteAll(0, "TLS_LTF_");
    ObjectsDeleteAll(0, "TLS_TREND_");
    string dash[] = {
        "BOT_DASH_T","BOT_DASH_L","BOT_DASH_SMAJ","BOT_DASH_SMIN",
        "BOT_DASH_ACT","BOT_DASH_FLT","BOT_DASH_FLT2",
        "BOT_DASH_BUY_K","BOT_DASH_BUY_V","BOT_DASH_SLL_K","BOT_DASH_SLL_V",
        "BOT_DASH_SHD_K","BOT_DASH_SHD_V","BOT_DASH_RSK_K","BOT_DASH_RSK_V",
        "BOT_DASH_GTE","BOT_DASH_ZRD","BOT_DASH_SEP1","BOT_DASH_SEP2"
    };
    for(int i = 0; i < ArraySize(dash); i++) ObjectDelete(0, dash[i]);
}

void OnTick() {
    CheckTelegramCommands();
    ManagePropFirmRules();
    CleanPendingOrdersForNews();
    CheckFlexTP();
    CheckPoolSL();
    ManageTrades_Tick();
    StudyTick();               // chỉ chạy trong Strategy Tester
    UpdateZoneRoundTracking(); // [ZONE LIMIT] phát hiện tập lệnh normal vừa chốt lãi
    UpdateGatekeeperState();
    if(IsNewBar()) {
        SMC_TREND.Update();
        SMC_HTF.Update();
        SMC_LTF.Update();
        if(MQLInfoInteger(MQL_TESTER)) {
            SMC_H4.Update();
            SMC_D1.Update();
            UpdateLeg(SMC_LTF, g_leg_ltf, g_leg_ltf_dir, g_leg_ltf_up, g_leg_ltf_dn);
            UpdateLeg(SMC_HTF, g_leg_htf, g_leg_htf_dir, g_leg_htf_up, g_leg_htf_dn);
        }
        ExecuteTradeLogic();
    }
    UpdateDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_CHART_CHANGE) SMC_HTF.HandleChartEvent();
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| OnTester — CHỈ tồn tại trong Strategy Tester, MQL5 không gọi hàm  |
//| này khi EA chạy thật, nên phần dưới không ảnh hưởng bot trên VPS. |
//|                                                                   |
//| In 3 bảng phục vụ việc chọn kịch bản:                             |
//|   1. Thống kê tổng (lãi, sụt vốn, profit factor, kỳ vọng/lệnh)    |
//|   2. Phân tầng theo 3 trục xu hướng: khung lớn (HTF) x Major x    |
//|      Minor -> 8 nhóm, để biết nên thuận hay nghịch xu hướng chính |
//|   3. Thống kê từng dòng luật của ma trận CSV (magic tự khai rule) |
//+------------------------------------------------------------------+
// Pha lưu trong g_matrix_rules đã qua CleanString: viết hoa, bỏ dấu cách
// -> "IMPULSEUP-BOSUP", "IMPULSEDOWN-CHOCHDOWN"...
int ImpulseDir(string s) { return (StringFind(s, "IMPULSEUP") >= 0) ? 1 : -1; }
int BreakDir(string s)   { return (StringFind(s, "BOSUP") >= 0 || StringFind(s, "CHOCHUP") >= 0) ? 1 : -1; }

double OnTester()
{
    double dep    = TesterStatistics(STAT_INITIAL_DEPOSIT);
    double net    = TesterStatistics(STAT_PROFIT);
    double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
    double payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
    double trades = TesterStatistics(STAT_TRADES);
    double won    = TesterStatistics(STAT_PROFIT_TRADES);
    double lost   = TesterStatistics(STAT_LOSS_TRADES);
    double ddbal  = TesterStatistics(STAT_BALANCEDD_PERCENT);
    double ddeq   = TesterStatistics(STAT_EQUITYDD_PERCENT);
    double ddrel  = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double maxdd  = MathMax(ddeq, ddrel);

    Print("========== [TESTER] THONG KE TONG ==========");
    PrintFormat("[TESTER] Von dau=%.2f | Lai rong=%.2f (%.2f%%) | Profit factor=%.2f | Ky vong/lenh=%.2f",
                dep, net, (dep > 0 ? net / dep * 100.0 : 0), pf, payoff);
    PrintFormat("[TESTER] So lenh=%.0f | Thang=%.0f | Thua=%.0f | Ty le thang=%.1f%%",
                trades, won, lost, (trades > 0 ? won / trades * 100.0 : 0));
    PrintFormat("[TESTER] Sut von: balance=%.2f%% | equity=%.2f%% | equity tuong doi=%.2f%%",
                ddbal, ddeq, ddrel);
    // Điểm xếp hạng: lãi %/tháng chia sụt vốn tối đa. Thời lượng test suy từ
    // khoảng thời gian thật của lịch sử deal, không hardcode.
    datetime t_first = 0, t_last = 0;
    HistorySelect(0, TimeCurrent());
    int total = HistoryDealsTotal();
    for(int i = 0; i < total; i++) {
        ulong d = HistoryDealGetTicket(i);
        if(d == 0) continue;
        datetime dt = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
        if(t_first == 0 || dt < t_first) t_first = dt;
        if(dt > t_last) t_last = dt;
    }
    double months = (t_last > t_first) ? ((double)(t_last - t_first) / (30.44 * 86400.0)) : 0;
    double per_month = (months > 0 && dep > 0) ? (net / dep * 100.0 / months) : 0;
    double score = (maxdd > 0.01) ? (per_month / maxdd) : 0;
    PrintFormat("[TESTER] Thoi luong=%.1f thang | Lai/thang=%.2f%% | DIEM (lai-thang/sut-von)=%.2f",
                months, per_month, score);

    // ---- gom theo rule va theo nhom xu huong ----
    int nb = ArraySize(g_matrix_rules);
    if(nb <= 0) { Print("[TESTER] Khong co ma tran rule de phan tang."); return score; }

    int    r_cnt[], r_win[];  double r_pnl[];
    ArrayResize(r_cnt, nb); ArrayResize(r_win, nb); ArrayResize(r_pnl, nb);
    ArrayInitialize(r_cnt, 0); ArrayInitialize(r_win, 0); ArrayInitialize(r_pnl, 0.0);

    int    b_cnt[8], b_win[8];  double b_pnl[8];
    ArrayInitialize(b_cnt, 0);  ArrayInitialize(b_win, 0);  ArrayInitialize(b_pnl, 0.0);
    int    t_cnt[2], t_win[2];  double t_pnl[2];   // 0 = thuan HTF, 1 = nghich HTF
    ArrayInitialize(t_cnt, 0);  ArrayInitialize(t_win, 0);  ArrayInitialize(t_pnl, 0.0);

    // Lượt 1: lập bản đồ position_id -> magic từ các deal MỞ lệnh.
    // BẮT BUỘC phải làm vậy: deal ĐÓNG do sàn tự sinh (stop out, hết kỳ test) có
    // magic = 0, nếu lọc theo magic của chính deal đóng thì toàn bộ lệnh thua
    // thảm khốc bị loại khỏi thống kê -> bảng trông toàn lãi trong khi tài khoản cháy.
    ulong map_pos[]; long map_mag[]; int nmap = 0;
    ArrayResize(map_pos, total); ArrayResize(map_mag, total);
    for(int i = 0; i < total; i++) {
        ulong d = HistoryDealGetTicket(i);
        if(d == 0) continue;
        if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
        map_pos[nmap] = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
        map_mag[nmap] = HistoryDealGetInteger(d, DEAL_MAGIC);
        nmap++;
    }

    for(int i = 0; i < total; i++) {
        ulong d = HistoryDealGetTicket(i);
        if(d == 0) continue;
        if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
        long magic = -1;
        for(int m = 0; m < nmap; m++) if(map_pos[m] == pid) { magic = map_mag[m]; break; }
        if(magic < 0 || !IsNormalMagic(magic)) continue;
        int ri = (int)(magic - BaseMagicNumber);
        if(ri < 0 || ri >= nb) continue;

        double p = HistoryDealGetDouble(d, DEAL_PROFIT)
                 + HistoryDealGetDouble(d, DEAL_SWAP)
                 + HistoryDealGetDouble(d, DEAL_COMMISSION);

        r_cnt[ri]++; r_pnl[ri] += p; if(p > 0) r_win[ri]++;

        int hd = ImpulseDir(g_matrix_rules[ri].HTF_State);
        int md = BreakDir(g_matrix_rules[ri].Maj_State);   // = chieu vao lenh
        int nd = BreakDir(g_matrix_rules[ri].Min_State);
        int b  = (hd > 0 ? 0 : 4) + (md > 0 ? 0 : 2) + (nd > 0 ? 0 : 1);
        b_cnt[b]++; b_pnl[b] += p; if(p > 0) b_win[b]++;

        int t = (md == hd) ? 0 : 1;
        t_cnt[t]++; t_pnl[t] += p; if(p > 0) t_win[t]++;
    }

    Print("========== [TESTER] THUAN HAY NGHICH XU HUONG KHUNG LON ==========");
    string tn[2] = {"THUAN HTF", "NGHICH HTF"};
    for(int t = 0; t < 2; t++)
        PrintFormat("[TESTER] %-11s | lenh=%4d | thang=%5.1f%% | PnL=%10.2f | ky vong/lenh=%7.2f",
                    tn[t], t_cnt[t], (t_cnt[t] > 0 ? 100.0 * t_win[t] / t_cnt[t] : 0),
                    t_pnl[t], (t_cnt[t] > 0 ? t_pnl[t] / t_cnt[t] : 0));

    Print("========== [TESTER] PHAN TANG 3 TRUC: HTF x MAJOR x MINOR ==========");
    for(int b = 0; b < 8; b++) {
        if(b_cnt[b] == 0) continue;
        string hs = ((b & 4) == 0) ? "HTF tang " : "HTF giam ";
        string ms = ((b & 2) == 0) ? "Maj tang " : "Maj giam ";
        string ns = ((b & 1) == 0) ? "Min tang" : "Min giam";
        PrintFormat("[TESTER] %s| %s| %s | lenh=%4d | thang=%5.1f%% | PnL=%10.2f | ky vong=%7.2f",
                    hs, ms, ns, b_cnt[b], 100.0 * b_win[b] / b_cnt[b],
                    b_pnl[b], b_pnl[b] / b_cnt[b]);
    }

    Print("========== [TESTER] TUNG DONG LUAT CO PHAT SINH LENH ==========");
    int used = 0;
    for(int i = 0; i < nb; i++) {
        if(r_cnt[i] == 0) continue;
        used++;
        PrintFormat("[TESTER] rule=%3d | lenh=%4d | thang=%5.1f%% | PnL=%10.2f | %s | %s | %s | type=%d",
                    i, r_cnt[i], 100.0 * r_win[i] / r_cnt[i], r_pnl[i],
                    g_matrix_rules[i].HTF_State, g_matrix_rules[i].Maj_State,
                    g_matrix_rules[i].Min_State, g_matrix_rules[i].Entry_Type);
    }
    PrintFormat("[TESTER] So dong luat thuc su phat sinh lenh: %d / %d", used, nb);

    StudyReport();
    return score;
}
//+------------------------------------------------------------------+
