//+------------------------------------------------------------------+
//|                                  TLS_SMC_CSV_BOT_HEDGING.mq5    |
//|                    Base: TLS_SMC_CSV_BOT_TREND v5.0              |
//|                    Add-on: Hedging Protection Module             |
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
input long   BaseMagicNumber           = 2026000;   // Magic number gốc của EA (Normal: [Base,Base+1000); Hedge Sell: [Base+10000,Base+10100); Counter-hedge Buy: [Base+20000,Base+20100))

input group "--- Telegram Radar Settings ---"
input string  Inp_BotToken             = "YOUR_BOT_TOKEN_HERE"; // Token Bot Telegram để gửi thông báo
input string  Inp_ChatID               = "YOUR_CHAT_ID_HERE";   // ID Chat/Group Telegram nhận thông báo
input bool    Inp_SendScreenshot       = true;                  // Gửi kèm ảnh chụp chart khi báo tin

input group "--- Prop Firm Protection ---"
input bool   Inp_UseMarginLimit        = true;    // Bật giới hạn margin tối đa khi tính khối lượng lệnh
input double Inp_MaxMarginPercent      = 38.0;    // % margin tối đa / balance được phép dùng (cắt lot nếu vượt)
input double Inp_DailyDrawdownLimit    = 3.0;     // % lỗ tối đa trong ngày so với balance đầu phiên -> chạm là đóng hết lệnh & dừng trade
input double Inp_DailyProfitLimit      = 0.0;     // % lãi mục tiêu trong ngày -> đạt là dừng trade (0 = không giới hạn)
input double Inp_AutoPassTarget        = 11010.0; // Mức equity (USD) mục tiêu -> đạt là tự đóng hết lệnh (Auto Pass)
input string Inp_NewsTimes             = "15:30, 21:00"; // Danh sách giờ tin (giờ server, "HH:MM", phân tách bằng dấu phẩy)
input int    Inp_NewsBufferMinutes     = 2;       // Số phút trước/sau giờ tin bị chặn vào lệnh & xóa lệnh chờ

input group "--- Risk Management & Scaling ---"
input int    Inp_Max_Risk_Trades       = 3;       // Số lệnh đang chịu risk (chưa hòa vốn) tối đa cùng lúc - vượt là không vào lệnh mới
input bool   UseRiskPerTrade           = true;    // true = tính lot theo % risk balance; false = dùng lot cố định FixedLotSize
input double RiskPercent               = 0.5;     // % balance chấp nhận rủi ro mỗi lệnh (khi UseRiskPerTrade = true)
input double FixedLotSize              = 0.05;    // Khối lượng lệnh cố định (khi UseRiskPerTrade = false)
input double SL_Buffer_Pips            = 30.0;    // Số pip đệm thêm ra ngoài mức SL gốc (zone SL) để tránh bị quét SL
input bool   Inp_No_SL                 = false;   // true = không đặt SL trên sàn (quản lý SL ảo nội bộ) - rủi ro cao

input group "--- Flexible Take Profit ---"
input bool   Inp_FlexTP_Enabled        = false;   // Bật cơ chế chốt lãi linh hoạt (FlexTP) theo tổng P&L cả pool lệnh
input double Inp_FlexTP_Percent        = 1.0;     // % lợi nhuận / balance để FlexTP đóng hết pool
input double Inp_FlexTP_Pips           = 0.0;     // Số pip lợi nhuận trung bình để FlexTP đóng hết pool (0 = không dùng tiêu chí pip)

enum ENUM_ENTRY_MODE {
    ENTRY_SMART       = 0,
    ENTRY_LIMIT_BOS   = 1,
    ENTRY_MARKET_ONLY = 2
};

input group "--- Smart Order Execution ---"
input ENUM_ENTRY_MODE Inp_Entry_Mode   = ENTRY_SMART; // Chế độ vào lệnh: SMART (Market nếu SL gần/Limit nếu xa), LIMIT_BOS (Limit tại mốc BOS/ChoCh), MARKET_ONLY (luôn Market)
input double Market_vs_Limit_Pips      = 50.0;    // Ngưỡng Entry->SL (pips): nếu <= ngưỡng thì vào Market, ngược lại đặt Limit (chế độ SMART)
input double Max_Zone_SL_Pips          = 300.0;   // Khoảng cách SL tối đa (pips); zone rộng hơn sẽ bị cắt bớt (kéo entry lại gần SL)
input double Entry_Buffer_Percent      = 10.0;    // % độ rộng zone dùng dịch điểm vào lệnh (dương = ra ngoài mép zone, âm = vào sâu trong zone)
input double Min_Reward_to_Risk_R      = 1.5;     // Tỷ lệ R:R tối thiểu yêu cầu (so với chướng ngại HTF đối diện); không đạt thì bỏ qua lệnh
input double Inp_Min_Entry_Dist_Pips   = 30.0;    // Khoảng cách tối thiểu (pips) giữa SL lệnh mới với SL lệnh cùng chiều gần nhất, tránh vào trùng vùng

input group "--- The Smart Gatekeeper ---"
input bool   Inp_Buddha_Palm           = true;    // Bật bộ lọc "Bàn tay Phật": chặn Buy trong HTF Sell Zone và chặn Sell trong HTF Buy Zone
input double HTF_Zone_Buffer_Pct       = 0.0;     // % độ rộng HTF Zone làm đệm mở cổng: dương = mở rộng ra ngoài zone (có sàn Min_HTF_Buffer_Pips), âm = yêu cầu giá vào sâu trong zone theo % (vd -50 = phải tới giữa zone mới mở cổng)
input double Min_HTF_Buffer_Pips       = 15.0;    // Sàn tối thiểu (pips) cho vùng đệm mở cổng - chỉ áp dụng khi HTF_Zone_Buffer_Pct >= 0
input double Zone_Break_Tolerance_Pct  = 50.0;    // % chiều cao HTF Zone cho phép giá xuyên qua trước khi coi là "vỡ zone" và đóng cổng (kill line)
input int    Inp_Max_Entries_Per_Zone  = 2;     // Giới hạn số lượt vào lệnh mỗi lần chạm Zone (0 = không giới hạn)

input group "--- HTF Settings (M15) ---"
input ENUM_TIMEFRAMES HTF_Timeframe         = PERIOD_M15; // Khung thời gian xác định Vùng giá (Location/HTF Zone)
input int    HTF_PeriodsInMajorSwing        = 9;  // Số nến mỗi bên để xác định đỉnh/đáy Major Swing trên khung HTF
input int    HTF_PeriodsInMinorSwing        = 5;  // Số nến mỗi bên để xác định đỉnh/đáy Minor Swing trên khung HTF
input color  HTF_BuyZoneColor               = C'235,250,240'; // Màu vẽ vùng Buy Zone trên khung HTF
input color  HTF_SellZoneColor              = C'255,235,235'; // Màu vẽ vùng Sell Zone trên khung HTF
input color  HTF_KeyLevelColor              = clrOrange;  // Màu vẽ các mức giá quan trọng (Key Level) trên khung HTF
input color  HTF_BOS_Up_Color               = clrDodgerBlue; // Màu vẽ đường BOS tăng trên khung HTF
input color  HTF_BOS_Dn_Color               = clrRed;    // Màu vẽ đường BOS giảm trên khung HTF

input group "--- Trend TF Settings (H1) ---"
input ENUM_TIMEFRAMES Trend_Timeframe       = PERIOD_H1; // Khung thời gian xác định Xu hướng lớn (Trend)
input int    Trend_PeriodsInMajorSwing      = 9;  // Số nến mỗi bên để xác định đỉnh/đáy Major Swing trên khung Trend
input int    Trend_PeriodsInMinorSwing      = 5;  // Số nến mỗi bên để xác định đỉnh/đáy Minor Swing trên khung Trend

input group "--- LTF Core Logic Settings (M1) ---"
input int    PeriodsInMajorSwing            = 9;  // Số nến mỗi bên để xác định đỉnh/đáy Major Swing trên M1 (khung tín hiệu vào lệnh)
input int    PeriodsInMinorSwing            = 5;  // Số nến mỗi bên để xác định đỉnh/đáy Minor Swing trên M1
input int    MaxZones                       = 1;  // Số lượng Zone (Buy/Sell) tối đa lưu trữ mỗi loại trên M1
input int    MaxBOSLines                    = 5;  // Số đường BOS Major tối đa lưu trữ/hiển thị trên chart M1
input int    MaxMinorBOSLines               = 3;  // Số đường BOS Minor tối đa lưu trữ/hiển thị trên chart M1

input group "--- Hedging Protection ---"
// Magic: HedgeSell=[Base+10000,Base+10100), CounterBuy=[Base+20000,Base+20100)
input bool   Inp_Hedge_Enabled             = true; // Bật/tắt toàn bộ module Hedging Protection
input double Inp_Hedge_Trigger_Pct         = 30.0;   // Trigger khi pool lỗ >= X% balance
input double Inp_Hedge_Vol_Ratio           = 0.5;    // Vol hedge = stuck_vol * ratio
input double Inp_Hedge_TP_Profit_Pct       = 10.0;   // Đóng C2 khi hedge lãi >= X% trigger_balance
input double Inp_Hedge_Reentry_Pct         = 5.0;    // Re-entry khi pool lỗ thêm X% balance
input int    Inp_Hedge_Max_Per_Day         = 3;      // Max lần hedge/ngày mỗi chiều

input group "--- Dashboard Settings ---"
input color  DashboardColor                = clrBlack; // Màu chữ chính của bảng Dashboard trên chart
input bool   Inp_Debug_Gate                = false;     // Bật log debug chi tiết cho Gatekeeper (Experts log)

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

// --- [HEDGE] ---
struct THedgeGroup {
    int      hedge_id;
    int      direction;             // +1 = hedge SELL (bảo vệ BUY pool)
                                    // -1 = counter-hedge BUY (bảo vệ SELL pool)
    double   hedge_vol;
    double   trigger_balance;       // Balance lúc trigger (tính 10% TP threshold)
    ulong    hedge_ticket;          // Position ticket = ResultOrder() của market order
    bool     is_active;             // Lệnh hedge còn đang mở
    bool     is_orphaned;           // Positions được bảo vệ đã đóng hết
    bool     waiting_reentry;       // Đang chờ re-entry sau C2
    double   reentry_ref_pnl_usd;   // P&L của protected pool lúc đóng C2
    datetime created_time;
};
THedgeGroup g_hedge_groups[];

struct TPoolStats {
    double total_vol;
    double total_pnl_usd;
    int    count;
};

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

// Prop Shield
bool     g_trading_stopped_today = false;
bool     g_account_passed        = false;
datetime g_last_day_checked      = 0;
double   g_sod_balance           = 0;

// --- [HEDGE] ---
int    g_hedge_sell_count = 0;   // Số lần hedge sell hôm nay
int    g_hedge_buy_count  = 0;   // Số lần counter-hedge buy hôm nay
int    g_next_hedge_id    = 0;   // ID tiếp theo trong ngày (0–99, reset hàng ngày)

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
    int handle = FileOpen("TLS_Matrix_Trend.csv", FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON, 0, CP_UTF8);
    if(handle == INVALID_HANDLE) { Print("LỖI: Không tìm thấy TLS_Matrix_Trend.csv!"); return false; }
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
// HELPER: MAGIC NUMBER CLASSIFICATION [HEDGE]
// ==================================================================
bool IsNormalMagic(long magic) {
    return (magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000);
}
bool IsHedgeSellMagic(long magic) {
    return (magic >= BaseMagicNumber + 10000 && magic < BaseMagicNumber + 10100);
}
bool IsHedgeBuyMagic(long magic) {
    return (magic >= BaseMagicNumber + 20000 && magic < BaseMagicNumber + 20100);
}
bool IsHedgeMagic(long magic) {
    return IsHedgeSellMagic(magic) || IsHedgeBuyMagic(magic);
}
bool IsEAMagic(long magic) {
    return IsNormalMagic(magic) || IsHedgeMagic(magic);
}

// ==================================================================
// SMC ENGINE INSTANCES
// ==================================================================
CSMC_Engine SMC_LTF;
CSMC_Engine SMC_HTF;
CSMC_Engine SMC_TREND;

// ==================================================================
// PROP SHIELD [MODIFIED: đóng cả hedge positions]
// ==================================================================
void CloseAll_PropFirm(string reason) {
    bool action_taken = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(IsEAMagic(OrderGetInteger(ORDER_MAGIC))) {
            trade.OrderDelete(ticket);
            action_taken = true;
        }
    }
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(IsEAMagic(PositionGetInteger(POSITION_MAGIC))) {
            trade.PositionClose(ticket);
            action_taken = true;
        }
    }
    // Reset toàn bộ hedge groups khi Prop Shield kích hoạt
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        g_hedge_groups[i].is_active      = false;
        g_hedge_groups[i].waiting_reentry = false;
    }
    if(action_taken)
        Radar.SendMessage("🚨 <b>PROP SHIELD TRIGGERED!</b>\n" + reason
            + "\nĐã tự động xóa sạch lệnh chờ và chốt toàn bộ vị thế (kể cả Hedge)!");
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

// [MODIFIED: reset hedge counters hàng ngày]
void ManagePropFirmRules() {
    if(g_account_passed) return;
    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
    if(current_day != g_last_day_checked) {
        g_sod_balance           = AccountInfoDouble(ACCOUNT_BALANCE);
        g_trading_stopped_today = false;
        g_last_day_checked      = current_day;
        // Reset hedge daily counters — hedge groups đang mở KHÔNG reset
        g_hedge_sell_count = 0;
        g_hedge_buy_count  = 0;
        g_next_hedge_id    = 0;
    }
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(Inp_AutoPassTarget > 0 && current_equity >= Inp_AutoPassTarget) {
        CloseAll_PropFirm("🎉 CHÚC MỪNG PASS QUỸ! Đạt mục tiêu: " + DoubleToString(current_equity, 2) + "$");
        g_account_passed = true; g_trading_stopped_today = true; return;
    }
    if(Inp_DailyDrawdownLimit > 0 && g_sod_balance > 0) {
        double loss_limit = g_sod_balance - g_sod_balance * (Inp_DailyDrawdownLimit / 100.0);
        if(current_equity <= loss_limit && !g_trading_stopped_today) {
            CloseAll_PropFirm("🛑 DAILY DD HIT! Vượt quá " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%");
            g_trading_stopped_today = true;
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
    if(SMC_TREND.current_major_trend != last_trend_tf_trend) {
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

    if(!g_gate_buy_open) {
        double buy_e = SMC_HTF.current_buy_zone_entry, buy_s = SMC_HTF.current_buy_zone_sl;
        if(buy_e == 0 || buy_s == 0) { buy_e = SMC_HTF.current_minor_buy_zone_entry; buy_s = SMC_HTF.current_minor_buy_zone_sl; }
        if(buy_e > 0 && buy_s > 0) {
            double w = MathAbs(buy_e - buy_s) / pip_size;
            double pct_buf = w * HTF_Zone_Buffer_Pct / 100.0;
            // Pct >= 0: mở rộng vùng kích hoạt ra ngoài Zone, có sàn Min_HTF_Buffer_Pips.
            // Pct <  0: yêu cầu giá xuyên sâu vào trong Zone theo %, không áp sàn.
            double buf = (HTF_Zone_Buffer_Pct >= 0) ? MathMax(pct_buf, Min_HTF_Buffer_Pips) : pct_buf;
            double buffered_top = buy_e + buf * pip_size;
            bool c_price = (bid <= buffered_top);
            bool c_fresh = (buy_s != g_last_broken_buy_zone_sl);
            bool c_h1    = (SMC_TREND.current_major_trend == 1);
            if(c_price && c_fresh && c_h1) { g_gate_buy_open = true; g_gate_buy_zone_entry = buy_e; g_gate_buy_zone_sl = buy_s; g_zone_buy_profit_rounds = 0; }
            if(Inp_Debug_Gate) Print("[GATE_BUY] Zone=", buy_e, "/", buy_s, " | price=", c_price, " fresh=", c_fresh, " H1=", c_h1, " → ", g_gate_buy_open ? "OPEN" : "LOCK");
        }
    }
    if(!g_gate_sell_open) {
        double sell_e = SMC_HTF.current_sell_zone_entry, sell_s = SMC_HTF.current_sell_zone_sl;
        if(sell_e == 0 || sell_s == 0) { sell_e = SMC_HTF.current_minor_sell_zone_entry; sell_s = SMC_HTF.current_minor_sell_zone_sl; }
        if(sell_e > 0 && sell_s > 0) {
            double w = MathAbs(sell_s - sell_e) / pip_size;
            double pct_buf = w * HTF_Zone_Buffer_Pct / 100.0;
            double buf = (HTF_Zone_Buffer_Pct >= 0) ? MathMax(pct_buf, Min_HTF_Buffer_Pips) : pct_buf;
            double buffered_bot = sell_e - buf * pip_size;
            bool c_price = (ask >= buffered_bot);
            bool c_fresh = (sell_s != g_last_broken_sell_zone_sl);
            bool c_h1    = (SMC_TREND.current_major_trend == -1);
            if(c_price && c_fresh && c_h1) { g_gate_sell_open = true; g_gate_sell_zone_entry = sell_e; g_gate_sell_zone_sl = sell_s; g_zone_sell_profit_rounds = 0; }
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
    if(g_zone_buy_prev_cnt > 0 && buy_cnt == 0 && g_zone_buy_last_pnl > 0) g_zone_buy_profit_rounds++;
    if(buy_cnt > 0) g_zone_buy_last_pnl = buy_pnl;
    g_zone_buy_prev_cnt = buy_cnt;
    if(g_zone_sell_prev_cnt > 0 && sell_cnt == 0 && g_zone_sell_last_pnl > 0) g_zone_sell_profit_rounds++;
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
            if(new_sl > 0 && new_sl != DBL_MAX) {
                bool modify = false;
                if(type == POSITION_TYPE_BUY)  { if(current_sl == 0 || (new_sl > current_sl && new_sl < current_price)) modify = true; }
                if(type == POSITION_TYPE_SELL) { if(current_sl == 0 || (new_sl < current_sl && new_sl > current_price)) modify = true; }
                if(modify) trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
            }
        }
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
                        if(reason == DEAL_REASON_SL) reason_str = "🔴 CẮN STOP LOSS";
                        if(reason == DEAL_REASON_TP) reason_str = "✅ CHẠM TAKE PROFIT";
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
    if(g_trading_stopped_today || g_account_passed) { g_filter_text = "[SHIELD] Prop Shield đang chặn"; return; }
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
        if(Inp_Max_Entries_Per_Zone > 0) {
            int rounds = (signal == 1) ? g_zone_buy_profit_rounds : g_zone_sell_profit_rounds;
            if(rounds >= Inp_Max_Entries_Per_Zone) {
                g_filter_text = "Blocked: Đã đủ " + IntegerToString(Inp_Max_Entries_Per_Zone) + " tập lệnh chốt lãi từ Zone này";
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
    bool success = false;
    double mkt_tp      = CalcHardTP(signal, current_price, final_sl, g_matrix_rules[rule_idx]);
    double lmt_tp      = CalcHardTP(signal, entry_zone,    final_sl, g_matrix_rules[rule_idx]);
    double eff_mkt_tp  = Inp_FlexTP_Enabled ? 0 : mkt_tp;
    double eff_lmt_tp  = Inp_FlexTP_Enabled ? 0 : lmt_tp;
    double eff_bos_tp  = Inp_FlexTP_Enabled ? 0 : bos_lmt_tp;
    if(signal == 1) {
        bool force_mkt = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (dist_to_sl_pips <= Market_vs_Limit_Pips);
        if(force_mkt) { double lot = CalculateLotSize(dist_to_sl_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.Buy(lot, _Symbol, current_price, order_sl, eff_mkt_tp, order_cmt); }
        else if(bos_lmt_price > 0 && current_price > bos_lmt_price) { double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.BuyLimit(lot, bos_lmt_price, _Symbol, order_sl, eff_bos_tp, ORDER_TIME_GTC, 0, order_cmt); }
        else if(current_price > entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) { double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.BuyLimit(lot, entry_zone, _Symbol, order_sl, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt); }
        if(success || trade.ResultRetcode() == 10009) g_last_traded_buy_sl = sl_price;
    } else if(signal == -1) {
        bool force_mkt = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (dist_to_sl_pips <= Market_vs_Limit_Pips);
        if(force_mkt) { double lot = CalculateLotSize(dist_to_sl_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.Sell(lot, _Symbol, current_price, order_sl, eff_mkt_tp, order_cmt); }
        else if(bos_lmt_price > 0 && current_price < bos_lmt_price) { double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.SellLimit(lot, bos_lmt_price, _Symbol, order_sl, eff_bos_tp, ORDER_TIME_GTC, 0, order_cmt); }
        else if(current_price < entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) { double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); if(lot <= 0) { g_filter_text = "Blocked: Hết Margin"; return; } success = trade.SellLimit(lot, entry_zone, _Symbol, order_sl, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt); }
        if(success || trade.ResultRetcode() == 10009) g_last_traded_sell_sl = sl_price;
    }
    if(success || trade.ResultRetcode() == 10009) {
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

// Kiểm tra ticket có phải orphaned hedge không (dùng bởi CheckFlexTP)
bool IsOrphanedHedgeTicket(ulong ticket) {
    for(int j = 0; j < ArraySize(g_hedge_groups); j++) {
        if(g_hedge_groups[j].hedge_ticket == ticket
        && g_hedge_groups[j].is_active
        && g_hedge_groups[j].is_orphaned) return true;
    }
    return false;
}

void CheckFlexTP() {
    if(!Inp_FlexTP_Enabled) return;
    double pip_size = GetPipSize(_Symbol); double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double buy_usd = 0, sell_usd = 0, buy_pips = 0, sell_pips = 0;
    int buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        // Gộp: normal positions + orphaned hedge positions vào cùng pool
        bool include = IsNormalMagic(magic)
                    || (IsHedgeMagic(magic) && IsOrphanedHedgeTicket(ticket));
        if(!include) continue;
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
        // Đóng: normal positions + orphaned hedge positions
        bool can_close = IsNormalMagic(magic)
                      || (IsHedgeMagic(magic) && IsOrphanedHedgeTicket(ticket));
        if(!can_close) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        bool do_close = close_all
                     || (close_buy  && type == POSITION_TYPE_BUY)
                     || (close_sell && type == POSITION_TYPE_SELL);
        if(do_close && trade.PositionClose(ticket)) any_closed = true;
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
// [HEDGE MODULE] - Toàn bộ phần mới
// ==================================================================

// Tính tổng vol và P&L của một pool theo chiều:
//   direction = +1 → BUY pool  (normal buys + orphaned counter-hedge buys)
//   direction = -1 → SELL pool (normal sells + orphaned hedge sells)
TPoolStats CalcPoolStats(int direction) {
    TPoolStats stats;
    stats.total_vol     = 0;
    stats.total_pnl_usd = 0;
    stats.count         = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        long type  = PositionGetInteger(POSITION_TYPE);
        bool is_buy  = (type == POSITION_TYPE_BUY);
        bool is_sell = (type == POSITION_TYPE_SELL);
        bool include = false;
        if(direction == 1) {
            if(is_buy && IsNormalMagic(magic)) include = true;
            // Orphaned counter-hedge buy
            if(is_buy && IsHedgeBuyMagic(magic)) {
                for(int j = 0; j < ArraySize(g_hedge_groups); j++) {
                    if(g_hedge_groups[j].hedge_ticket == ticket
                    && g_hedge_groups[j].is_active
                    && g_hedge_groups[j].is_orphaned) { include = true; break; }
                }
            }
        } else {
            if(is_sell && IsNormalMagic(magic)) include = true;
            // Orphaned hedge sell
            if(is_sell && IsHedgeSellMagic(magic)) {
                for(int j = 0; j < ArraySize(g_hedge_groups); j++) {
                    if(g_hedge_groups[j].hedge_ticket == ticket
                    && g_hedge_groups[j].is_active
                    && g_hedge_groups[j].is_orphaned) { include = true; break; }
                }
            }
        }
        if(include) {
            stats.total_vol     += PositionGetDouble(POSITION_VOLUME);
            stats.total_pnl_usd += PositionGetDouble(POSITION_PROFIT)
                                  + PositionGetDouble(POSITION_SWAP)
                                  + PositionGetDouble(POSITION_COMMISSION);
            stats.count++;
        }
    }
    return stats;
}

bool HasActiveHedge(int direction) {
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(g_hedge_groups[i].is_active && g_hedge_groups[i].direction == direction)
            return true;
    }
    return false;
}

// Tính tổng volume thực tế tất cả vị thế cùng chiều (dùng để sizing hedge)
// Khác CalcPoolStats: đếm CẢ hedge non-orphaned vì chúng vẫn chịu rủi ro thị trường
double CalcGrossVolForSizing(int direction) {
    double total = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsEAMagic(magic)) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        bool is_buy  = (type == POSITION_TYPE_BUY);
        bool is_sell = (type == POSITION_TYPE_SELL);
        if(direction == 1  && is_buy)  total += PositionGetDouble(POSITION_VOLUME);
        if(direction == -1 && is_sell) total += PositionGetDouble(POSITION_VOLUME);
    }
    return total;
}

// Đặt lệnh hedge market:
//   direction = +1 → mở SELL (bảo vệ BUY pool)
//   direction = -1 → mở BUY  (bảo vệ SELL pool)
void ExecuteHedgeEntry(int direction) {
    double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    TPoolStats pool   = CalcPoolStats(direction);  // pool bị bảo vệ (dùng để check có vị thế không)
    if(pool.count == 0) {
        Print("[HEDGE] Pool trống — bỏ qua hedge entry");
        return;
    }
    // Sizing dựa trên TỔNG volume thực tế cùng chiều (kể cả hedge chưa orphaned)
    double gross_vol = CalcGrossVolForSizing(direction);
    if(gross_vol <= 0) {
        Print("[HEDGE] Gross vol = 0 — bỏ qua hedge entry");
        return;
    }
    double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double raw_vol = gross_vol * Inp_Hedge_Vol_Ratio;
    double hedge_vol = MathFloor(raw_vol / step) * step;
    if(hedge_vol < min_lot) {
        Print("[HEDGE] Vol quá nhỏ (", hedge_vol, " < min ", min_lot, ") → bỏ qua");
        return;
    }
    hedge_vol = MathMin(hedge_vol, max_lot);
    // Kiểm tra margin
    if(Inp_UseMarginLimit) {
        double used_margin    = AccountInfoDouble(ACCOUNT_MARGIN);
        double max_margin     = balance * (Inp_MaxMarginPercent / 100.0);
        double remaining      = max_margin - used_margin;
        if(remaining <= 0) { Print("[HEDGE] Hết margin room → bỏ qua hedge"); return; }
    }
    int  hedge_id    = g_next_hedge_id;
    long hedge_magic = BaseMagicNumber + (direction == 1 ? 10000 : 20000) + hedge_id;
    trade.SetExpertMagicNumber(hedge_magic);
    string comment_str = (direction == 1)
        ? "HEDGE_SELL_#" + IntegerToString(hedge_id)
        : "HEDGE_BUY_#"  + IntegerToString(hedge_id);
    bool success = false;
    if(direction == 1) success = trade.Sell(hedge_vol, _Symbol, 0, 0, 0, comment_str);
    else               success = trade.Buy (hedge_vol, _Symbol, 0, 0, 0, comment_str);
    if(success || trade.ResultRetcode() == 10009) {
        int sz = ArraySize(g_hedge_groups);
        ArrayResize(g_hedge_groups, sz + 1);
        g_hedge_groups[sz].hedge_id           = hedge_id;
        g_hedge_groups[sz].direction          = direction;
        g_hedge_groups[sz].hedge_vol          = hedge_vol;
        g_hedge_groups[sz].trigger_balance    = balance;
        g_hedge_groups[sz].hedge_ticket       = trade.ResultOrder();
        g_hedge_groups[sz].is_active          = true;
        g_hedge_groups[sz].is_orphaned        = false;
        g_hedge_groups[sz].waiting_reentry    = false;
        g_hedge_groups[sz].reentry_ref_pnl_usd = 0;
        g_hedge_groups[sz].created_time       = TimeCurrent();
        // Cập nhật counters
        g_next_hedge_id = (g_next_hedge_id + 1) % 100;
        if(direction == 1) g_hedge_sell_count++;
        else               g_hedge_buy_count++;
        string dir_str  = (direction == 1) ? "SELL" : "BUY";
        string pool_str = (direction == 1) ? "BUY"  : "SELL";
        int cnt_today   = (direction == 1) ? g_hedge_sell_count : g_hedge_buy_count;
        string msg = "🛡️ <b>HEDGE ACTIVATED: " + dir_str + " #" + IntegerToString(hedge_id) + "</b>\n"
                   + "━━━━━━━━━━━━━━━\n"
                   + "📊 <b>Lý do:</b> " + pool_str + " pool lỗ ≥ "
                   + DoubleToString(Inp_Hedge_Trigger_Pct, 1) + "% balance\n"
                   + "📦 <b>Vol hedge:</b> " + DoubleToString(hedge_vol, 2) + " lots"
                   + " (" + DoubleToString(Inp_Hedge_Vol_Ratio, 2) + "x của " + DoubleToString(gross_vol, 2) + " lots)\n"
                   + "💰 <b>Pool P&L:</b> " + DoubleToString(pool.total_pnl_usd, 2) + "$\n"
                   + "💳 <b>Balance:</b> " + DoubleToString(balance, 2) + "$\n"
                   + "🔢 <b>Hedge hôm nay:</b> " + IntegerToString(cnt_today)
                   + "/" + IntegerToString(Inp_Hedge_Max_Per_Day);
        Radar.SendMessageWithPhoto(msg);
    } else {
        Print("[HEDGE] Đặt lệnh thất bại: retcode=", trade.ResultRetcode(),
              " comment=", trade.ResultComment());
    }
}

// Đồng bộ g_hedge_groups[] với thực tế và đánh dấu orphaned
void ValidateHedgeGroups() {
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(!g_hedge_groups[i].is_active) continue;
        // Kiểm tra ticket còn tồn tại
        if(!PositionSelectByTicket(g_hedge_groups[i].hedge_ticket)) {
            // Tìm lại theo magic (phòng trường hợp ticket thay đổi sau restart)
            bool found = false;
            long expected_magic = BaseMagicNumber
                + (g_hedge_groups[i].direction == 1 ? 10000 : 20000)
                + g_hedge_groups[i].hedge_id;
            for(int j = 0; j < PositionsTotal(); j++) {
                ulong t = PositionGetTicket(j);
                if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == expected_magic) {
                    g_hedge_groups[i].hedge_ticket = t;
                    found = true; break;
                }
            }
            if(!found) { g_hedge_groups[i].is_active = false; continue; }
        }
        // Kiểm tra orphaned: không còn position nào được bảo vệ
        if(!g_hedge_groups[i].is_orphaned) {
            bool protected_exist = false;
            for(int j = 0; j < PositionsTotal(); j++) {
                ulong t = PositionGetTicket(j);
                if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                long magic = PositionGetInteger(POSITION_MAGIC);
                long type  = PositionGetInteger(POSITION_TYPE);
                if(g_hedge_groups[i].direction == 1) {
                    // Hedge SELL đang bảo vệ BUY → tìm normal BUY
                    if(type == POSITION_TYPE_BUY && IsNormalMagic(magic)) { protected_exist = true; break; }
                } else {
                    // Counter-hedge BUY đang bảo vệ SELL → tìm normal SELL hoặc orphaned hedge sell
                    if(type == POSITION_TYPE_SELL && IsNormalMagic(magic)) { protected_exist = true; break; }
                    if(type == POSITION_TYPE_SELL && IsHedgeSellMagic(magic)) {
                        for(int k = 0; k < ArraySize(g_hedge_groups); k++) {
                            if(k == i) continue;
                            if(g_hedge_groups[k].hedge_ticket == t && g_hedge_groups[k].is_active && g_hedge_groups[k].is_orphaned)
                                { protected_exist = true; break; }
                        }
                        if(protected_exist) break;
                    }
                }
            }
            if(!protected_exist) {
                g_hedge_groups[i].is_orphaned = true;
                Print("[HEDGE] Group #", g_hedge_groups[i].hedge_id,
                      " (", (g_hedge_groups[i].direction == 1 ? "SELL" : "BUY"), ") → ORPHANED");
            }
        }
    }
}

// Kiểm tra và thực hiện đóng hedge theo điều kiện C0, C1, C2
void CheckHedgeExitConditions() {
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(!g_hedge_groups[i].is_active) continue;
        if(!PositionSelectByTicket(g_hedge_groups[i].hedge_ticket)) continue;
        double hedge_pnl = PositionGetDouble(POSITION_PROFIT)
                         + PositionGetDouble(POSITION_SWAP)
                         + PositionGetDouble(POSITION_COMMISSION);
        double hedge_pnl_pct = (g_hedge_groups[i].trigger_balance > 0)
                             ? (hedge_pnl / g_hedge_groups[i].trigger_balance * 100.0)
                             : 0;
        bool   should_close  = false;
        bool   is_c2         = false;
        string close_reason  = "";

        // C0: Orphaned + đang lãi → đóng ngay (mục đích bảo vệ đã xong)
        if(g_hedge_groups[i].is_orphaned && hedge_pnl > 0) {
            should_close = true;
            close_reason = "C0: Orphaned + Lãi";
        }
        // C1: Trend đảo chiều (ChoCh) + hedge đang lãi → đóng ngay
        // Hedge SELL (dir=+1) đóng khi H1 flip lên (+1)
        // Counter-hedge BUY (dir=-1) đóng khi H1 flip xuống (-1)
        if(!should_close && hedge_pnl > 0) {
            bool trend_reversed = (g_hedge_groups[i].direction == 1  && SMC_TREND.current_major_trend == 1)
                                || (g_hedge_groups[i].direction == -1 && SMC_TREND.current_major_trend == -1);
            if(trend_reversed) { should_close = true; close_reason = "C1: ChoCh đảo chiều + Lãi"; }
        }
        // C2: Hedge lãi đủ Inp_Hedge_TP_Profit_Pct% trigger_balance → chốt lãi
        if(!should_close && hedge_pnl_pct >= Inp_Hedge_TP_Profit_Pct) {
            should_close = true; is_c2 = true;
            close_reason = "C2: Lãi đủ " + DoubleToString(Inp_Hedge_TP_Profit_Pct, 1) + "%";
        }
        if(!should_close) continue;
        // Ghi nhận re-entry reference trước khi đóng (chỉ C2)
        if(is_c2) {
            TPoolStats protected_pool = CalcPoolStats(g_hedge_groups[i].direction);
            g_hedge_groups[i].reentry_ref_pnl_usd = protected_pool.total_pnl_usd;
            g_hedge_groups[i].waiting_reentry      = true;
        }
        if(trade.PositionClose(g_hedge_groups[i].hedge_ticket)) {
            g_hedge_groups[i].is_active = false;
            double cur_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            string dir_str = (g_hedge_groups[i].direction == 1) ? "SELL" : "BUY";
            string msg = "🔄 <b>HEDGE CLOSED [" + close_reason + "]</b>\n"
                       + "━━━━━━━━━━━━━━━\n"
                       + "📊 <b>Loại:</b> Hedge " + dir_str
                       + " #" + IntegerToString(g_hedge_groups[i].hedge_id) + "\n"
                       + "💰 <b>P&L hedge:</b> " + DoubleToString(hedge_pnl, 2) + "$"
                       + " (+" + DoubleToString(hedge_pnl_pct, 1) + "%)\n"
                       + "💳 <b>Balance:</b> " + DoubleToString(cur_balance, 2) + "$";
            if(is_c2)
                msg += "\n⏳ <b>Chờ re-entry:</b> Protected pool lỗ thêm "
                     + DoubleToString(Inp_Hedge_Reentry_Pct, 1) + "% balance";
            Radar.SendMessage(msg);
        }
    }
}

// Kiểm tra điều kiện re-entry sau C2
void CheckHedgeReentry() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(!g_hedge_groups[i].waiting_reentry) continue;
        // Nếu đã có hedge active cùng chiều → pool đã được bảo vệ, hủy re-entry
        if(HasActiveHedge(g_hedge_groups[i].direction)) {
            g_hedge_groups[i].waiting_reentry = false;
            continue;
        }
        // Kiểm tra trend vẫn hợp lệ (cùng chiều với hedge ban đầu)
        bool trend_valid = (g_hedge_groups[i].direction == 1  && SMC_TREND.current_major_trend == -1)
                        || (g_hedge_groups[i].direction == -1 && SMC_TREND.current_major_trend ==  1);
        // Hủy waiting nếu trend đảo ngược
        if(!trend_valid) { g_hedge_groups[i].waiting_reentry = false; continue; }
        // Tính ngưỡng kích hoạt: pool phải lỗ thêm Inp_Hedge_Reentry_Pct% balance
        double reentry_threshold = g_hedge_groups[i].reentry_ref_pnl_usd
                                 - (Inp_Hedge_Reentry_Pct / 100.0 * balance);
        TPoolStats pool = CalcPoolStats(g_hedge_groups[i].direction);
        int count_today = (g_hedge_groups[i].direction == 1) ? g_hedge_sell_count : g_hedge_buy_count;
        if(pool.total_pnl_usd < reentry_threshold
        && count_today < Inp_Hedge_Max_Per_Day
        && pool.count > 0) {
            g_hedge_groups[i].waiting_reentry = false;
            Print("[HEDGE] Re-entry trigger: pool P&L=", pool.total_pnl_usd,
                  " < threshold=", reentry_threshold);
            ExecuteHedgeEntry(g_hedge_groups[i].direction);
        }
    }
}

// Kiểm tra có pending re-entry nào cho hướng này không
bool HasPendingReentry(int direction) {
    for(int j = 0; j < ArraySize(g_hedge_groups); j++) {
        if(g_hedge_groups[j].direction == direction && g_hedge_groups[j].waiting_reentry)
            return true;
    }
    return false;
}

// Phát hiện flip H1 trend và kích hoạt hedge nếu đủ điều kiện
void CheckNewHedgeTrigger() {
    int current_h1 = SMC_TREND.current_major_trend;
    if(current_h1 == 0) return;
    double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
    double trigger_usd = balance * (Inp_Hedge_Trigger_Pct / 100.0);
    // STATE-BASED: kiểm tra mỗi tick dựa trên H1 direction hiện tại
    // HasActiveHedge() là debounce tự nhiên: không trigger lại khi đã có hedge active
    // HasPendingReentry() nhường quyền cho CheckHedgeReentry() khi đang chờ re-entry với threshold cao hơn
    //
    // [HEDGE SELL] H1 đang DOWN + BUY pool lỗ đủ ngưỡng + chưa có hedge sell active/pending
    if(current_h1 < 0 && !HasActiveHedge(1) && !HasPendingReentry(1) && g_hedge_sell_count < Inp_Hedge_Max_Per_Day) {
        TPoolStats buy_pool = CalcPoolStats(1);
        bool pool_in_loss = (buy_pool.total_pnl_usd < 0)
                         && (MathAbs(buy_pool.total_pnl_usd) >= trigger_usd);
        if(pool_in_loss && buy_pool.count > 0) {
            Print("[HEDGE] TRIGGER SELL: BUY pool P&L=", buy_pool.total_pnl_usd,
                  " (", -MathAbs(buy_pool.total_pnl_usd)/balance*100.0, "%) threshold=-",
                  Inp_Hedge_Trigger_Pct, "%");
            ExecuteHedgeEntry(1);
        }
    }
    // [COUNTER-HEDGE BUY] H1 đang UP + SELL pool lỗ đủ ngưỡng + chưa có counter-hedge buy active/pending
    if(current_h1 > 0 && !HasActiveHedge(-1) && !HasPendingReentry(-1) && g_hedge_buy_count < Inp_Hedge_Max_Per_Day) {
        TPoolStats sell_pool = CalcPoolStats(-1);
        bool pool_in_loss = (sell_pool.total_pnl_usd < 0)
                         && (MathAbs(sell_pool.total_pnl_usd) >= trigger_usd);
        if(pool_in_loss && sell_pool.count > 0) {
            Print("[HEDGE] TRIGGER BUY: SELL pool P&L=", sell_pool.total_pnl_usd,
                  " (", -MathAbs(sell_pool.total_pnl_usd)/balance*100.0, "%) threshold=-",
                  Inp_Hedge_Trigger_Pct, "%");
            ExecuteHedgeEntry(-1);
        }
    }
}

// Hàm tổng điều phối hedge — gọi mỗi tick sau ManageTrades_Tick()
void ManageHedgeGroups() {
    if(!Inp_Hedge_Enabled) return;
    if(g_trading_stopped_today || g_account_passed) return;
    if(IsInNewsWindow()) return;
    ValidateHedgeGroups();
    CheckHedgeExitConditions();
    CheckHedgeReentry();
    CheckNewHedgeTrigger();
}

// Tái tạo g_hedge_groups[] khi bot restart — đọc từ positions đang mở
void ReconstructHedgeGroupsOnInit() {
    ArrayResize(g_hedge_groups, 0);
    int reconstructed = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(!IsHedgeMagic(magic)) continue;
        bool is_sell_hedge = IsHedgeSellMagic(magic);
        int  hedge_id      = (int)(magic - BaseMagicNumber - (is_sell_hedge ? 10000 : 20000));
        if(hedge_id < 0 || hedge_id >= 100) continue;
        int sz = ArraySize(g_hedge_groups);
        ArrayResize(g_hedge_groups, sz + 1);
        g_hedge_groups[sz].hedge_id            = hedge_id;
        g_hedge_groups[sz].direction           = is_sell_hedge ? 1 : -1;
        g_hedge_groups[sz].hedge_vol           = PositionGetDouble(POSITION_VOLUME);
        g_hedge_groups[sz].trigger_balance     = AccountInfoDouble(ACCOUNT_BALANCE);
        g_hedge_groups[sz].hedge_ticket        = ticket;
        g_hedge_groups[sz].is_active           = true;
        g_hedge_groups[sz].is_orphaned         = false;  // ValidateHedgeGroups() sẽ cập nhật
        g_hedge_groups[sz].waiting_reentry     = false;
        g_hedge_groups[sz].reentry_ref_pnl_usd = 0;
        g_hedge_groups[sz].created_time        = (datetime)PositionGetInteger(POSITION_TIME);
        if(hedge_id >= g_next_hedge_id) g_next_hedge_id = (hedge_id + 1) % 100;
        reconstructed++;
        Print("[HEDGE INIT] Tái tạo group #", hedge_id,
              " (", (is_sell_hedge ? "SELL" : "BUY"), ") ticket=", ticket);
    }
    if(reconstructed > 0)
        Print("[HEDGE INIT] Đã tái tạo ", reconstructed, " hedge group(s)");
}

// ==================================================================
// DASHBOARD [MODIFIED: thêm hedge status]
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
    string flt_txt = (g_filter_text == "") ? " " : g_filter_text;
    color  flt_clr = c_gray;
    if(StringFind(flt_txt, "PASSED") >= 0) flt_clr = c_ok;
    else if(StringFind(flt_txt, "Blocked") >= 0) flt_clr = c_bad;
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
    // --- Hedge status rows: gộp tất cả active hedges vào 1 dòng mỗi chiều ---
    string hedge_sell_str = "NONE";  color hedge_sell_clr = c_gray;
    string hedge_buy_str  = "NONE";  color hedge_buy_clr  = c_gray;
    double sell_total_pnl = 0; int sell_active_cnt = 0;
    double buy_total_pnl  = 0; int buy_active_cnt  = 0;
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(!g_hedge_groups[i].is_active) continue;
        if(!PositionSelectByTicket(g_hedge_groups[i].hedge_ticket)) continue;
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        string orphan_tag = g_hedge_groups[i].is_orphaned ? "[O]" : "";
        if(g_hedge_groups[i].direction == 1) {
            sell_total_pnl += pnl; sell_active_cnt++;
            // Append mỗi hedge: #id vol pnl[O]
            string entry = "#" + IntegerToString(g_hedge_groups[i].hedge_id)
                         + " " + DoubleToString(g_hedge_groups[i].hedge_vol, 2) + "L"
                         + (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 0) + "$" + orphan_tag;
            hedge_sell_str = (hedge_sell_str == "NONE") ? entry : (hedge_sell_str + " | " + entry);
        } else {
            buy_total_pnl += pnl; buy_active_cnt++;
            string entry = "#" + IntegerToString(g_hedge_groups[i].hedge_id)
                         + " " + DoubleToString(g_hedge_groups[i].hedge_vol, 2) + "L"
                         + (pnl >= 0 ? "+" : "") + DoubleToString(pnl, 0) + "$" + orphan_tag;
            hedge_buy_str = (hedge_buy_str == "NONE") ? entry : (hedge_buy_str + " | " + entry);
        }
    }
    if(sell_active_cnt > 0) hedge_sell_clr = (sell_total_pnl >= 0) ? c_ok : c_bad;
    if(buy_active_cnt  > 0) hedge_buy_clr  = (buy_total_pnl  >= 0) ? c_ok : c_bad;
    // Hiển thị waiting_reentry khi không có active hedge cùng chiều
    for(int i = 0; i < ArraySize(g_hedge_groups); i++) {
        if(!g_hedge_groups[i].is_active && g_hedge_groups[i].waiting_reentry) {
            if(g_hedge_groups[i].direction == 1 && sell_active_cnt == 0) { hedge_sell_str = "#" + IntegerToString(g_hedge_groups[i].hedge_id) + " [WAIT RE-ENTRY]"; hedge_sell_clr = C'200,130,0'; }
            if(g_hedge_groups[i].direction == -1 && buy_active_cnt  == 0) { hedge_buy_str  = "#" + IntegerToString(g_hedge_groups[i].hedge_id) + " [WAIT RE-ENTRY]"; hedge_buy_clr  = C'200,130,0'; }
        }
    }
    string hedge_cnt = "HgCnt: S=" + IntegerToString(g_hedge_sell_count)
                     + "/" + IntegerToString(Inp_Hedge_Max_Per_Day)
                     + " B=" + IntegerToString(g_hedge_buy_count)
                     + "/" + IntegerToString(Inp_Hedge_Max_Per_Day);
    DashLabel("BOT_DASH_SEP_H", 8, 168, c_sep,          7, "─────────────────────");
    DashLabel("BOT_DASH_HS_K",  8, 182, c_dark,          7, "HgSell:");
    DashLabel("BOT_DASH_HS_V",  58, 182, hedge_sell_clr, 7, hedge_sell_str);
    DashLabel("BOT_DASH_HB_K",  8, 196, c_dark,          7, "HgBuy :");
    DashLabel("BOT_DASH_HB_V",  58, 196, hedge_buy_clr,  7, hedge_buy_str);
    DashLabel("BOT_DASH_HC",    8, 210, c_gray,          7, hedge_cnt);
    // Zone Round Limit: số "tập lệnh" đã chốt lãi / giới hạn cho phép, theo từng chiều
    string zone_rd_str;
    if(Inp_Max_Entries_Per_Zone > 0)
        zone_rd_str = "ZoneTP: Buy " + IntegerToString(g_zone_buy_profit_rounds)  + "/" + IntegerToString(Inp_Max_Entries_Per_Zone)
                     + "  Sell "      + IntegerToString(g_zone_sell_profit_rounds) + "/" + IntegerToString(Inp_Max_Entries_Per_Zone);
    else
        zone_rd_str = "ZoneTP: Buy " + IntegerToString(g_zone_buy_profit_rounds)
                     + "  Sell "      + IntegerToString(g_zone_sell_profit_rounds) + " (Unlimited)";
    DashLabel("BOT_DASH_ZRD", 8, 224, c_gray, 7, zone_rd_str);
}

// ==================================================================
// LIFECYCLE
// ==================================================================
int OnInit() {
    Print("DA NẠP ENGINE HEDGING v1.0!");
    if(!LoadMatrixCSV()) return INIT_FAILED;
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
    ReconstructHedgeGroupsOnInit();
    string s_trend = EnumToString(Trend_Timeframe); StringReplace(s_trend, "PERIOD_", "");
    string s_htf   = EnumToString(HTF_Timeframe);   StringReplace(s_htf,   "PERIOD_", "");
    string s_ltf   = EnumToString(_Period);          StringReplace(s_ltf,   "PERIOD_", "");
    string msg = "🟢 <b>SYSTEM STARTED: TLS HEDGING BOT v1.0</b>\n━━━━━━━━━━━━━━━\n"
               + "💰 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n"
               + "⚙️ <b>T-L-S:</b> " + _Symbol + " | T=" + s_trend + " | L=" + s_htf + " | S=" + s_ltf + "\n"
               + "🛡️ <b>Mục tiêu:</b> " + DoubleToString(Inp_AutoPassTarget, 0)
               + "$ | DD ngày: " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%\n"
               + "🔀 <b>Hedge:</b> Trigger=" + DoubleToString(Inp_Hedge_Trigger_Pct, 1)
               + "% | TP=" + DoubleToString(Inp_Hedge_TP_Profit_Pct, 1)
               + "% | Max=" + IntegerToString(Inp_Hedge_Max_Per_Day) + "/ngày";
    Radar.SendMessage(msg);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "TLS_HTF_");
    ObjectsDeleteAll(0, "TLS_LTF_");
    ObjectsDeleteAll(0, "TLS_TREND_");
    string dash[] = {
        "BOT_DASH_T","BOT_DASH_L","BOT_DASH_SMAJ","BOT_DASH_SMIN",
        "BOT_DASH_ACT","BOT_DASH_FLT","BOT_DASH_FLT2",
        "BOT_DASH_BUY_K","BOT_DASH_BUY_V","BOT_DASH_SLL_K","BOT_DASH_SLL_V",
        "BOT_DASH_SHD_K","BOT_DASH_SHD_V","BOT_DASH_RSK_K","BOT_DASH_RSK_V",
        "BOT_DASH_SEP_H","BOT_DASH_HS_K","BOT_DASH_HS_V",
        "BOT_DASH_HB_K","BOT_DASH_HB_V","BOT_DASH_HC","BOT_DASH_ZRD","BOT_DASH_SEP1","BOT_DASH_SEP2"
    };
    for(int i = 0; i < ArraySize(dash); i++) ObjectDelete(0, dash[i]);
}

void OnTick() {
    ManagePropFirmRules();
    CleanPendingOrdersForNews();
    CheckFlexTP();
    ManageTrades_Tick();
    ManageHedgeGroups();       // [HEDGE] sau ManageTrades_Tick, trước Gatekeeper
    UpdateZoneRoundTracking(); // [ZONE LIMIT] phát hiện tập lệnh normal vừa chốt lãi
    UpdateGatekeeperState();
    if(IsNewBar()) {
        SMC_TREND.Update();
        SMC_HTF.Update();
        SMC_LTF.Update();
        ExecuteTradeLogic();
    }
    UpdateDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_CHART_CHANGE) SMC_HTF.HandleChartEvent();
}
//+------------------------------------------------------------------+
