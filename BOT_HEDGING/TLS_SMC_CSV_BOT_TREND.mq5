//+------------------------------------------------------------------+
//|                                              TLS_SMC_Bot_V5.0    |
//|                    Focus: Ultimate Prop Shield (News, DD, Pass)  |
//|                    Status: Ready for The Trading Pit 10K         |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "5.0"

#include <Trade\Trade.mqh>
#include <CSMC_Engine.mqh>
#include <Telegram_Radar.mqh> 

CTrade trade;
CTelegramRadar Radar; 

// ==================================================================
// 1. GIAO DIỆN CÀI ĐẶT (INPUTS)
// ==================================================================
input group "--- EA Identification ---"
input long   BaseMagicNumber        = 2026000; 

input group "--- Telegram Radar Settings ---"
input string  Inp_BotToken       = "YOUR_BOT_TOKEN_HERE"; 
input string  Inp_ChatID         = "YOUR_CHAT_ID_HERE";   
input bool    Inp_SendScreenshot = true; 

// [ULTIMATE PROP SHIELD] Bảo vệ tài khoản Quỹ toàn diện
input group "--- Prop Firm Protection (The Trading Pit) ---"
input bool   Inp_UseMarginLimit     = true;      // 1. Bật Lá chắn Ký quỹ (Margin)
input double Inp_MaxMarginPercent   = 38.0;      //    Hạn mức Margin tối đa (Quỹ cấm 40%)
input double Inp_DailyDrawdownLimit = 3.0;       // 2. Giới hạn Lỗ Ngày (%) (Quỹ cấm 4%)
input double Inp_DailyProfitLimit   = 0.0;       // 2b. Giới hạn Lãi Ngày (%) - Đạt là ngừng vào lệnh (0 = tắt)
input double Inp_AutoPassTarget     = 11010.0;   // 3. Mục tiêu đỗ quỹ ($) - Chạm là chốt hết nghỉ ngơi
input string Inp_NewsTimes          = "15:30, 21:00"; // 4. Giờ ra Tin Đỏ (Theo GIỜ SÀN MT5, cách nhau dấu phẩy)
input int    Inp_NewsBufferMinutes  = 2;         //    Ngừng giao dịch và xóa lệnh chờ trước/sau tin (Phút)

input group "--- Risk Management & Scaling ---"
input int    Inp_Max_Risk_Trades    = 3;
input bool   UseRiskPerTrade        = true;
input double RiskPercent            = 0.5;
input double FixedLotSize           = 0.05;
input double SL_Buffer_Pips         = 30.0;
input bool   Inp_No_SL              = false;  // Không đặt SL (thả trôi - lot tính theo zone width)

input group "--- Flexible Take Profit (Chốt Lãi Linh Hoạt) ---"
input bool   Inp_FlexTP_Enabled  = false;  // Bật chốt lãi linh hoạt toàn bộ lệnh
input double Inp_FlexTP_Percent  = 1.0;    // Đóng tất cả khi tổng lãi >= X% tài khoản (0 = bỏ qua)
input double Inp_FlexTP_Pips     = 0.0;    // Đóng tất cả khi tổng pips >= X pips (0 = bỏ qua)

enum ENUM_ENTRY_MODE {
    ENTRY_SMART       = 0,  // Tự động: Market nếu gần SL, Limit tại Zone nếu xa
    ENTRY_LIMIT_BOS   = 1,  // Limit ngay tại đỉnh/đáy BOS/ChoCh (retest level)
    ENTRY_MARKET_ONLY = 2   // Luôn vào Market ngay lập tức
};

input group "--- Smart Order Execution ---"
input ENUM_ENTRY_MODE Inp_Entry_Mode = ENTRY_SMART;  // Chế độ vào lệnh
input double Market_vs_Limit_Pips   = 50.0;
input double Max_Zone_SL_Pips       = 300.0;
input double Entry_Buffer_Percent   = 10.0;
input double Min_Reward_to_Risk_R        = 1.5;
input double Inp_Min_Entry_Dist_Pips     = 30.0;  // Khoảng cách tối thiểu giữa 2 lệnh cùng chiều (pips), 0 = tắt

input group "--- The Smart Gatekeeper (Location Filter) ---"
input bool   Inp_Buddha_Palm          = true;   // Bàn tay Phật: chặn lệnh ngược HTF zone
input double HTF_Zone_Buffer_Pct    = 0.0;
input double Min_HTF_Buffer_Pips    = 15.0;
input double Zone_Break_Tolerance_Pct = 50.0;

input group "--- HTF Settings (M15) ---"
input ENUM_TIMEFRAMES HTF_Timeframe          = PERIOD_M15;   
input int    HTF_PeriodsInMajorSwing         = 9;            
input int    HTF_PeriodsInMinorSwing         = 5;            
input color  HTF_BuyZoneColor                = C'235,250,240'; 
input color  HTF_SellZoneColor               = C'255,235,235'; 
input color  HTF_KeyLevelColor               = clrOrange;      
input color  HTF_BOS_Up_Color                = clrDodgerBlue;
input color  HTF_BOS_Dn_Color                = clrRed;

input group "--- Trend TF Settings (H1) ---"
input ENUM_TIMEFRAMES Trend_Timeframe         = PERIOD_H1;
input int    Trend_PeriodsInMajorSwing        = 9;
input int    Trend_PeriodsInMinorSwing        = 5;

input group "--- LTF Core Logic Settings (M1) ---"
input int    PeriodsInMajorSwing    = 9;     
input int    PeriodsInMinorSwing    = 5;     
input int    MaxZones               = 1;
input int    MaxBOSLines            = 5;
input int    MaxMinorBOSLines       = 3;

input group "--- Dashboard Settings ---"
input color  DashboardColor         = clrBlack;
input bool   Inp_Debug_Gate         = false;     // In log cổng vào lệnh mỗi bar (debug)

// ==================================================================
// BIẾN TOÀN CỤC & CẤU TRÚC DỮ LIỆU
// ==================================================================
double g_last_traded_buy_sl  = 0.0; 
double g_last_traded_sell_sl = 0.0;
string g_action_text = "Khởi tạo hệ thống...";
string g_filter_text = "Filter: Đang quét cản..."; 
bool   g_gate_buy_open  = false;
bool   g_gate_sell_open = false;
bool   g_tg_buy_notified = false;  
bool   g_tg_sell_notified = false; 
string g_last_m1_phase  = "";
double g_last_broken_buy_zone_sl  = 0.0;
double g_last_broken_sell_zone_sl = 0.0;
// Zone thực sự đã mở cổng (có thể là major hoặc minor M15 zone)
double g_gate_buy_zone_entry  = 0.0;
double g_gate_buy_zone_sl     = 0.0;
double g_gate_sell_zone_entry = 0.0;
double g_gate_sell_zone_sl    = 0.0;

// [PROP SHIELD] Biến toàn cục cho Quỹ
bool     g_trading_stopped_today = false;
bool     g_account_passed = false;
datetime g_last_day_checked = 0;
double   g_sod_balance = 0;

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

string CleanString(string str) { string temp = str; StringReplace(temp, "\"", ""); StringReplace(temp, " ", ""); StringReplace(temp, "\r", ""); StringReplace(temp, "\n", ""); StringReplace(temp, "–", "-"); StringReplace(temp, "—", "-"); StringToUpper(temp); return temp; }
bool LoadMatrixCSV() { int handle = FileOpen("TLS_Matrix_Trend.csv", FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON, 0, CP_UTF8); if(handle == INVALID_HANDLE) { Print("LỖI: Không tìm thấy TLS_Matrix_Trend.csv!"); return false; } ArrayResize(g_matrix_rules, 0); bool is_header = true; while(!FileIsEnding(handle)) { string line = FileReadString(handle); string check_empty = line; StringTrimLeft(check_empty); StringTrimRight(check_empty); if(check_empty == "") continue; if(is_header) { is_header = false; continue; } ushort separator = StringGetCharacter(",", 0); if (StringFind(line, ";") >= 0) separator = StringGetCharacter(";", 0); else if (StringFind(line, "\t") >= 0) separator = StringGetCharacter("\t", 0); string cols[]; int col_count = StringSplit(line, separator, cols); if (col_count >= 13) { int size = ArraySize(g_matrix_rules); ArrayResize(g_matrix_rules, size + 1); g_matrix_rules[size].HTF_State = CleanString(cols[0]); g_matrix_rules[size].Maj_State = CleanString(cols[1]); g_matrix_rules[size].Min_State = CleanString(cols[2]); g_matrix_rules[size].Entry_Type = (int)StringToInteger(cols[3]); g_matrix_rules[size].Risk_Multiplier = StringToDouble(cols[4]); g_matrix_rules[size].BE_Trigger_R = StringToDouble(cols[5]); g_matrix_rules[size].Partial_R = StringToDouble(cols[6]); g_matrix_rules[size].Partial_Pct = StringToDouble(cols[7]); g_matrix_rules[size].TP_Strategy = CleanString(cols[8]); g_matrix_rules[size].TP_Param = StringToDouble(cols[9]); g_matrix_rules[size].Trail_Strategy = CleanString(cols[10]); g_matrix_rules[size].Location_Filter = CleanString(cols[11]); string dash_note = cols[12]; StringReplace(dash_note, "\"", ""); g_matrix_rules[size].Dash_Note = dash_note; } } FileClose(handle); return true; }
double GetPipSize(string sym) { string s = sym; StringToUpper(s); if (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1; if (StringFind(s, "JPY") >= 0) return 0.01; long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS); if (digits == 5 || digits == 4) return 0.0001; if (digits == 3 || digits == 2) return 0.01; return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0; }
bool IsNewBar() { static datetime last_bar_time = 0; datetime current_bar_time = iTime(_Symbol, _Period, 0); if(last_bar_time == 0) { last_bar_time = current_bar_time; return true; } if(current_bar_time != last_bar_time) { last_bar_time = current_bar_time; return true; } return false; }

CSMC_Engine SMC_LTF;
CSMC_Engine SMC_HTF;
CSMC_Engine SMC_TREND; // H1 Trend Engine (T-L-S Architecture)

// ==================================================================
// HÀM BẢO VỆ TÀI KHOẢN QUỸ (SHIELD)
// ==================================================================
void CloseAll_PropFirm(string reason) {
    bool action_taken = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        long magic = OrderGetInteger(ORDER_MAGIC);
        if(magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) { trade.OrderDelete(ticket); action_taken = true; }
    }
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        long magic = PositionGetInteger(POSITION_MAGIC);
        if(magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) { trade.PositionClose(ticket); action_taken = true; }
    }
    if (action_taken) Radar.SendMessage("🚨 <b>PROP SHIELD TRIGGERED!</b>\n" + reason + "\nĐã tự động xóa sạch lệnh chờ và chốt toàn bộ vị thế!");
}

bool IsInNewsWindow() {
    if (Inp_NewsTimes == "") return false;
    datetime now = TimeCurrent();
    MqlDateTime dt_now; TimeToStruct(now, dt_now);
    int now_minutes = dt_now.hour * 60 + dt_now.min;

    string times[]; StringSplit(Inp_NewsTimes, ',', times);
    for (int i=0; i<ArraySize(times); i++) {
        string t = times[i]; StringTrimLeft(t); StringTrimRight(t);
        if (t == "") continue;
        string parts[]; StringSplit(t, ':', parts);
        if (ArraySize(parts) == 2) {
            int news_min = (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
            if (now_minutes >= (news_min - Inp_NewsBufferMinutes) && now_minutes <= (news_min + Inp_NewsBufferMinutes)) return true;
        }
    }
    return false;
}

void CleanPendingOrdersForNews() {
    if (IsInNewsWindow()) {
        bool deleted = false;
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            long magic = OrderGetInteger(ORDER_MAGIC);
            if(magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) { if(trade.OrderDelete(ticket)) deleted = true; }
        }
        if (deleted) Radar.SendMessage("⚠️ <b>NEWS FILTER ACTIVE</b>\nĐã tự động hủy lệnh chờ (Pending) do dính khung giờ Tin Tức ("+IntegerToString(Inp_NewsBufferMinutes)+" mins)!");
    }
}

void ManagePropFirmRules() {
    if (g_account_passed) return;

    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
    if (current_day != g_last_day_checked) {
        g_sod_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_trading_stopped_today = false;
        g_last_day_checked = current_day;
    }

    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // 1. Kiểm tra Pass Quỹ
    if (Inp_AutoPassTarget > 0 && current_equity >= Inp_AutoPassTarget) {
        CloseAll_PropFirm("🎉 CHÚC MỪNG PASS QUỸ! Đạt mục tiêu: " + DoubleToString(current_equity, 2) + "$");
        g_account_passed = true; g_trading_stopped_today = true; return;
    }

    // 2. Kiểm tra Daily DD (Tính theo SOD Balance)
    if (Inp_DailyDrawdownLimit > 0 && g_sod_balance > 0) {
        double max_loss_amount = g_sod_balance * (Inp_DailyDrawdownLimit / 100.0);
        double loss_limit_level = g_sod_balance - max_loss_amount;
        if (current_equity <= loss_limit_level && !g_trading_stopped_today) {
            CloseAll_PropFirm("🛑 DAILY DD HIT! Vượt quá " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%");
            g_trading_stopped_today = true;
        }
    }

    // 2b. Kiểm tra Daily Profit Limit (đóng hết lệnh + ngừng vào mới cả ngày)
    if (Inp_DailyProfitLimit > 0 && g_sod_balance > 0 && !g_trading_stopped_today) {
        double daily_profit_pct = (current_equity - g_sod_balance) / g_sod_balance * 100.0;
        if (daily_profit_pct >= Inp_DailyProfitLimit) {
            CloseAll_PropFirm("🎯 DAILY PROFIT TARGET ĐẠT! +"
                + DoubleToString(daily_profit_pct, 2) + "% (ngưỡng "
                + DoubleToString(Inp_DailyProfitLimit, 1) + "%)\n"
                + "💰 Equity: " + DoubleToString(current_equity, 2) + "$\n"
                + "✅ Đã chốt toàn bộ lệnh. Nghỉ giao dịch đến hết ngày.");
            g_trading_stopped_today = true;
        }
    }
}

// HÀM TÍNH LOT BẢO VỆ MARGIN TỔNG
double CalculateLotSize(double sl_distance_points, double risk_multiplier) {
   if(!UseRiskPerTrade || sl_distance_points <= 0) return FixedLotSize;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size == 0 || tick_value == 0) return FixedLotSize;
   double actual_risk_pct = RiskPercent * risk_multiplier;
   if(actual_risk_pct <= 0) return FixedLotSize;
   double money_risk = AccountInfoDouble(ACCOUNT_BALANCE) * (actual_risk_pct / 100.0);
   double value_per_point = tick_value / (tick_size / _Point);
   double risk_per_lot = sl_distance_points * value_per_point;
   if(risk_per_lot == 0) return 0;
   double raw_lot = money_risk / risk_per_lot;
   
   if(Inp_UseMarginLimit) {
       double current_used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
       double max_total_margin_allowed = AccountInfoDouble(ACCOUNT_BALANCE) * (Inp_MaxMarginPercent / 100.0);
       double remaining_margin_room = max_total_margin_allowed - current_used_margin;
       if(remaining_margin_room <= 0) return 0; 
       double margin_per_lot = 0;
       double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
       if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, ask_price, margin_per_lot)) { margin_per_lot = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * ask_price) / AccountInfoInteger(ACCOUNT_LEVERAGE); }
       if(margin_per_lot > 0) {
           double max_lot_by_remaining_margin = remaining_margin_room / margin_per_lot;
           if(raw_lot > max_lot_by_remaining_margin) raw_lot = max_lot_by_remaining_margin; 
       }
   }

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   raw_lot = MathRound(raw_lot / step_lot) * step_lot;
   if(raw_lot < min_lot) return 0; 
   return MathMin(raw_lot, max_lot);
}

// ... (Các hàm CalculateCurrentRR, UpdateGatekeeperState, CalcTargetPrice, CalcHardTP, ManageTrades_Tick, OnTradeTransaction giữ nguyên y hệt V4.91) ...
double CalculateCurrentRR(TPosTracker &tracker) {
   if(tracker.initial_risk_money <= 0) return 0;
   if(!PositionSelectByTicket(tracker.ticket)) return tracker.realized_pnl / tracker.initial_risk_money;
   double current_pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
   return (tracker.realized_pnl + current_pnl) / tracker.initial_risk_money;
}

void UpdateGatekeeperState() {
    if (SMC_LTF.current_market_phase != g_last_m1_phase) {
        if (SMC_LTF.current_market_phase == "Impulse Down - ChoCh Down") g_gate_buy_open = false;
        if (SMC_LTF.current_market_phase == "Impulse Up - ChoCh Up") g_gate_sell_open = false;
        g_last_m1_phase = SMC_LTF.current_market_phase;
    }
    static int last_htf_trend = 0;
    if (SMC_HTF.current_major_trend != last_htf_trend) {
        if (SMC_HTF.current_major_trend == 1) g_gate_sell_open = false;
        if (SMC_HTF.current_major_trend == -1) g_gate_buy_open = false;
        last_htf_trend = SMC_HTF.current_major_trend;
    }
    // [T-L-S] H1 Trend flip: đóng cổng ngược chiều trend mới
    static int last_trend_tf_trend = 0;
    if (SMC_TREND.current_major_trend != last_trend_tf_trend) {
        if (SMC_TREND.current_major_trend == 1)  g_gate_sell_open = false;
        if (SMC_TREND.current_major_trend == -1) g_gate_buy_open  = false;
        last_trend_tf_trend = SMC_TREND.current_major_trend;
    }
    double pip_size = GetPipSize(_Symbol);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // [FIX-1] Auto-reset "broken zone" block khi M15 tạo ra zone MỚI có SL khác
    // Trường hợp CSMC_Engine tạo zone mới → SL thay đổi → xóa block cũ
    static double s_prev_htf_buy_sl = 0, s_prev_htf_sell_sl = 0;
    if (SMC_HTF.current_buy_zone_sl != s_prev_htf_buy_sl) {
        if (SMC_HTF.current_buy_zone_sl > 0 && SMC_HTF.current_buy_zone_sl != g_last_broken_buy_zone_sl)
            g_last_broken_buy_zone_sl = 0;   // Zone mới khác SL cũ → xóa block
        s_prev_htf_buy_sl = SMC_HTF.current_buy_zone_sl;
    }
    if (SMC_HTF.current_sell_zone_sl != s_prev_htf_sell_sl) {
        if (SMC_HTF.current_sell_zone_sl > 0 && SMC_HTF.current_sell_zone_sl != g_last_broken_sell_zone_sl)
            g_last_broken_sell_zone_sl = 0;
        s_prev_htf_sell_sl = SMC_HTF.current_sell_zone_sl;
    }

    // [FIX-2] Cổng Mua: ưu tiên Major zone, fallback Minor zone khi Major trống
    // Trường hợp M15 bearish (BuyZonesQueue trống) nhưng MinorBuyZonesQueue còn zone
    if (!g_gate_buy_open) {
        double buy_e = SMC_HTF.current_buy_zone_entry, buy_s = SMC_HTF.current_buy_zone_sl;
        if (buy_e == 0 || buy_s == 0) { buy_e = SMC_HTF.current_minor_buy_zone_entry; buy_s = SMC_HTF.current_minor_buy_zone_sl; }
        if (buy_e > 0 && buy_s > 0) {
            double w = MathAbs(buy_e - buy_s) / pip_size; double buf = MathMax(w * HTF_Zone_Buffer_Pct / 100.0, Min_HTF_Buffer_Pips); double buffered_top = buy_e + buf * pip_size;
            bool c_price = (bid <= buffered_top); bool c_fresh = (buy_s != g_last_broken_buy_zone_sl); bool c_h1 = (SMC_TREND.current_major_trend == 1);
            if (c_price && c_fresh && c_h1) { g_gate_buy_open = true; g_gate_buy_zone_entry = buy_e; g_gate_buy_zone_sl = buy_s; }
            if (Inp_Debug_Gate) Print("[GATE_BUY] Zone=", buy_e, "/", buy_s, " BufTop=", buffered_top, " Bid=", bid, " | price=", c_price, " fresh=", c_fresh, " H1=", c_h1, " lastBrk=", g_last_broken_buy_zone_sl, " → ", g_gate_buy_open ? "OPEN" : "LOCK");
        } else if (Inp_Debug_Gate) Print("[GATE_BUY] M15 BuyZone TRỐNG (major+minor) | H1=", SMC_TREND.current_major_trend, " M15=", SMC_HTF.current_market_phase);
    }

    // [FIX-2] Cổng Bán: ưu tiên Major zone, fallback Minor zone khi Major trống
    if (!g_gate_sell_open) {
        double sell_e = SMC_HTF.current_sell_zone_entry, sell_s = SMC_HTF.current_sell_zone_sl;
        if (sell_e == 0 || sell_s == 0) { sell_e = SMC_HTF.current_minor_sell_zone_entry; sell_s = SMC_HTF.current_minor_sell_zone_sl; }
        if (sell_e > 0 && sell_s > 0) {
            double w = MathAbs(sell_s - sell_e) / pip_size; double buf = MathMax(w * HTF_Zone_Buffer_Pct / 100.0, Min_HTF_Buffer_Pips); double buffered_bot = sell_e - buf * pip_size;
            bool c_price = (ask >= buffered_bot); bool c_fresh = (sell_s != g_last_broken_sell_zone_sl); bool c_h1 = (SMC_TREND.current_major_trend == -1);
            if (c_price && c_fresh && c_h1) { g_gate_sell_open = true; g_gate_sell_zone_entry = sell_e; g_gate_sell_zone_sl = sell_s; }
            if (Inp_Debug_Gate) Print("[GATE_SELL] Zone=", sell_e, "/", sell_s, " BufBot=", buffered_bot, " Ask=", ask, " | price=", c_price, " fresh=", c_fresh, " H1=", c_h1, " lastBrk=", g_last_broken_sell_zone_sl, " → ", g_gate_sell_open ? "OPEN" : "LOCK");
        } else if (Inp_Debug_Gate) Print("[GATE_SELL] M15 SellZone TRỐNG (major+minor) | H1=", SMC_TREND.current_major_trend, " M15=", SMC_HTF.current_market_phase);
    }

    // Zone-break kill: dùng zone ĐÃ MỞ CỔNG (g_gate_*_zone_*) thay vì SMC_HTF hiện tại
    // Đảm bảo kill đúng zone đang theo dõi (kể cả khi dùng minor zone)
    MqlRates r[]; ArraySetAsSeries(r, true);
    if (CopyRates(_Symbol, _Period, 0, 2, r) >= 2) {
        double ha_open_1  = ( (r[1].open + r[1].close)/2.0 + (r[1].open + r[1].high + r[1].low + r[1].close)/4.0 ) / 2.0; double ha_close_1 = (r[1].open + r[1].high + r[1].low + r[1].close) / 4.0; double ha_low_1   = MathMin(r[1].low, MathMin(ha_open_1, ha_close_1)); double ha_high_1  = MathMax(r[1].high, MathMax(ha_open_1, ha_close_1));
        if (g_gate_buy_open && g_gate_buy_zone_entry > 0 && g_gate_buy_zone_sl > 0) {
            double h = MathAbs(g_gate_buy_zone_entry - g_gate_buy_zone_sl); double kill_line = g_gate_buy_zone_sl - (h * Zone_Break_Tolerance_Pct / 100.0);
            if (ha_low_1 < kill_line && ha_close_1 < g_gate_buy_zone_sl) { g_gate_buy_open = false; g_last_broken_buy_zone_sl = g_gate_buy_zone_sl; if (Inp_Debug_Gate) Print("[GATE_BUY] KILLED: HA low=", ha_low_1, " < kill_line=", kill_line, " | broken_sl=", g_gate_buy_zone_sl); }
        }
        if (g_gate_sell_open && g_gate_sell_zone_entry > 0 && g_gate_sell_zone_sl > 0) {
            double h = MathAbs(g_gate_sell_zone_sl - g_gate_sell_zone_entry); double kill_line = g_gate_sell_zone_sl + (h * Zone_Break_Tolerance_Pct / 100.0);
            if (ha_high_1 > kill_line && ha_close_1 > g_gate_sell_zone_sl) { g_gate_sell_open = false; g_last_broken_sell_zone_sl = g_gate_sell_zone_sl; if (Inp_Debug_Gate) Print("[GATE_SELL] KILLED: HA high=", ha_high_1, " > kill_line=", kill_line, " | broken_sl=", g_gate_sell_zone_sl); }
        }
    }
    if(g_gate_buy_open && !g_tg_buy_notified) { string msg = "🔓 <b>GATE OPENED: MỞ CỔNG MUA</b>\n━━━━━━━━━━━━━━━\n🔎 <b>Vị trí:</b> Giá chạm HTF Buy Zone\n⏳ Chờ xác nhận cấu trúc LTF để vào lệnh..."; Radar.SendMessageWithPhoto(msg); g_tg_buy_notified = true; }
    if(!g_gate_buy_open) g_tg_buy_notified = false;
    if(g_gate_sell_open && !g_tg_sell_notified) { string msg = "🔓 <b>GATE OPENED: MỞ CỔNG BÁN</b>\n━━━━━━━━━━━━━━━\n🔎 <b>Vị trí:</b> Giá chạm HTF Sell Zone\n⏳ Chờ xác nhận cấu trúc LTF để vào lệnh..."; Radar.SendMessageWithPhoto(msg); g_tg_sell_notified = true; }
    if(!g_gate_sell_open) g_tg_sell_notified = false;
}

double CalcTargetPrice(int signal, double entry_price, double sl_price, TMatrixRule &rule) {
    double tp = 0.0; double risk_val = MathAbs(entry_price - sl_price); double pip_size = GetPipSize(_Symbol); if (risk_val <= 0) return 0.0;
    if (rule.TP_Strategy == "FIXED_R" && rule.TP_Param > 0) { tp = (signal == 1) ? (entry_price + risk_val * rule.TP_Param) : (entry_price - risk_val * rule.TP_Param); }
    else if (rule.TP_Strategy == "OPPOSITE_ZONE") { double target = (signal == 1) ? SMC_LTF.current_sell_zone_entry : SMC_LTF.current_buy_zone_entry; if(target > 0) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if (rule.TP_Strategy == "HTF_OPPOSITE_ZONE") { double target = (signal == 1) ? SMC_HTF.current_sell_zone_entry : SMC_HTF.current_buy_zone_entry; if(target > 0) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if (rule.TP_Strategy == "HTF_ACTIVE") { double target = (signal == 1) ? SMC_HTF.current_maj_extreme_high : SMC_HTF.current_maj_extreme_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if (rule.TP_Strategy == "HTF_PROT") { double target = (signal == 1) ? SMC_HTF.current_maj_prot_high : SMC_HTF.current_maj_prot_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if (rule.TP_Strategy == "LTF_ACTIVE") { double target = (signal == 1) ? SMC_LTF.current_maj_extreme_high : SMC_LTF.current_maj_extreme_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    else if (rule.TP_Strategy == "LTF_PROT") { double target = (signal == 1) ? SMC_LTF.current_maj_prot_high : SMC_LTF.current_maj_prot_low; if(target > 0 && target != EMPTY_VALUE) tp = (signal == 1) ? (target - rule.TP_Param * pip_size) : (target + rule.TP_Param * pip_size); }
    return (tp > 0) ? NormalizeDouble(tp, _Digits) : 0.0;
}

double CalcHardTP(int signal, double entry_price, double sl_price, TMatrixRule &rule) { if (rule.Partial_R == -1) return 0.0; return CalcTargetPrice(signal, entry_price, sl_price, rule); }

void ManageTrades_Tick() {
   for(int i = 0; i < PositionsTotal(); i++) { ulong ticket = PositionGetTicket(i); long magic = PositionGetInteger(POSITION_MAGIC); if(magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) { bool found = false; for(int j=0; j<ArraySize(g_trackers); j++) { if(g_trackers[j].ticket == ticket) { found = true; break; } } if(!found) { int size = ArraySize(g_trackers); ArrayResize(g_trackers, size + 1); g_trackers[size].ticket = ticket; g_trackers[size].initial_sl = PositionGetDouble(POSITION_SL); g_trackers[size].initial_open = PositionGetDouble(POSITION_PRICE_OPEN); g_trackers[size].initial_risk = MathAbs(g_trackers[size].initial_open - g_trackers[size].initial_sl); g_trackers[size].initial_vol = PositionGetDouble(POSITION_VOLUME); g_trackers[size].partial_done = false; g_trackers[size].trail_r_watermark = 0.0; g_trackers[size].realized_pnl = 0; g_trackers[size].be_notified = false; double sl_dist = MathAbs(g_trackers[size].initial_open - g_trackers[size].initial_sl); g_trackers[size].initial_risk_money = sl_dist * g_trackers[size].initial_vol * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)); } } }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
       ulong ticket = PositionGetTicket(i);
       if(PositionSelectByTicket(ticket)) {
           long magic = PositionGetInteger(POSITION_MAGIC); if(magic < BaseMagicNumber || magic >= BaseMagicNumber + 1000) continue; 
           int rule_idx = (int)(magic - BaseMagicNumber); if(rule_idx < 0 || rule_idx >= ArraySize(g_matrix_rules)) continue; TMatrixRule rule = g_matrix_rules[rule_idx];
           int t_idx = -1; for(int j=0; j<ArraySize(g_trackers); j++) { if(g_trackers[j].ticket == ticket) { t_idx = j; break; } } if(t_idx == -1) continue; 
           double initial_risk = g_trackers[t_idx].initial_risk; if (initial_risk <= 0) continue; 
           long type = PositionGetInteger(POSITION_TYPE); double open_price = g_trackers[t_idx].initial_open; double current_sl = PositionGetDouble(POSITION_SL); double current_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK); double current_profit = (type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price); double current_R = current_profit / initial_risk;
           if (!g_trackers[t_idx].partial_done) {
               bool trigger_partial = false;
               if (rule.Partial_R > 0 && current_R >= rule.Partial_R) { trigger_partial = true; } 
               else if (rule.Partial_R == -1) { int pos_signal = (type == POSITION_TYPE_BUY) ? 1 : -1; double target_price = CalcTargetPrice(pos_signal, open_price, g_trackers[t_idx].initial_sl, rule); if (target_price > 0) { if (type == POSITION_TYPE_BUY && current_price >= target_price) trigger_partial = true; if (type == POSITION_TYPE_SELL && current_price <= target_price) trigger_partial = true; } }
               if (trigger_partial) {
                   g_trackers[t_idx].partial_done = true; 
                   if (rule.Partial_Pct > 0) {
                       double close_vol = g_trackers[t_idx].initial_vol * (rule.Partial_Pct / 100.0); double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); close_vol = MathFloor(close_vol / step) * step; 
                       if (close_vol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                           double before_bal = AccountInfoDouble(ACCOUNT_BALANCE); bool isPartialSuccess = false;
                           if (close_vol >= PositionGetDouble(POSITION_VOLUME)) isPartialSuccess = trade.PositionClose(ticket); else isPartialSuccess = trade.PositionClosePartial(ticket, close_vol); 
                           if(isPartialSuccess) { Sleep(500); double pnl_added = AccountInfoDouble(ACCOUNT_BALANCE) - before_bal; g_trackers[t_idx].realized_pnl += pnl_added; string msg = "✂️ <b>PARTIAL CLOSE: CHỐT LỜI 1 PHẦN</b>\n━━━━━━━━━━━━━━━\n🎯 <b>Lý do:</b> Đạt mốc " + DoubleToString(rule.Partial_R, 1) + "R\n💰 <b>Lợi nhuận chốt:</b> +" + DoubleToString(pnl_added, 2) + "$\n📉 <b>Volume còn lại:</b> " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " Lots"; Radar.SendMessage(msg); }
                           continue; 
                       }
                   }
               }
           }
           if (rule.BE_Trigger_R > 0 && current_R >= rule.BE_Trigger_R) {
               bool needs_be = false; if (type == POSITION_TYPE_BUY && current_sl < open_price) needs_be = true; if (type == POSITION_TYPE_SELL && current_sl > open_price) needs_be = true;
               if (needs_be) {
                   if(trade.PositionModify(ticket, NormalizeDouble(open_price, _Digits), PositionGetDouble(POSITION_TP))) {
                       current_sl = open_price; 
                       if(!g_trackers[t_idx].be_notified) { string msg = "🛡️ <b>SL TRAILED: VỀ ĐIỂM HÒA VỐN</b>\n━━━━━━━━━━━━━━━\n🔒 <b>Trạng thái:</b> Đã dời SL về Entry (Risk Free)\n📈 <b>Lãi nổi:</b> +" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + "$"; Radar.SendMessage(msg); g_trackers[t_idx].be_notified = true; }
                   }
               }
           }
           if (rule.Trail_Strategy != "NONE" && rule.Trail_Strategy != "") {
               double new_sl = current_sl; double pip_size = GetPipSize(_Symbol); double buffer_val = SL_Buffer_Pips * pip_size;
               if (rule.Trail_Strategy == "TRAIL_MINOR") { double raw_sl = (type == POSITION_TYPE_BUY) ? SMC_LTF.current_minor_buy_zone_sl : SMC_LTF.current_minor_sell_zone_sl; if (raw_sl > 0) new_sl = (type == POSITION_TYPE_BUY) ? (raw_sl - buffer_val) : (raw_sl + buffer_val); }
               else if (rule.Trail_Strategy == "TRAIL_MAJOR") { double raw_sl = (type == POSITION_TYPE_BUY) ? SMC_LTF.current_buy_zone_sl : SMC_LTF.current_sell_zone_sl; if (raw_sl > 0) new_sl = (type == POSITION_TYPE_BUY) ? (raw_sl - buffer_val) : (raw_sl + buffer_val); }
               else if (rule.Trail_Strategy == "TRAIL_STRUCT") {
                   double best_sl = current_sl; 
                   if (type == POSITION_TYPE_BUY) { double p_low = SMC_LTF.current_maj_prot_low; double cand_p = (p_low > 0 && p_low != EMPTY_VALUE) ? (p_low - buffer_val) : 0; if (cand_p >= current_price) cand_p = 0; if (cand_p > best_sl) best_sl = cand_p; if (best_sl > current_sl) new_sl = best_sl; } 
                   else if (type == POSITION_TYPE_SELL) { double p_high = SMC_LTF.current_maj_prot_high; double cand_p = (p_high > 0 && p_high != EMPTY_VALUE) ? (p_high + buffer_val) : 0; if (cand_p <= current_price && cand_p > 0) cand_p = 0; if (best_sl <= 0) best_sl = DBL_MAX; if (cand_p > 0 && cand_p < best_sl) best_sl = cand_p; if (best_sl < current_sl || current_sl <= 0) new_sl = best_sl; }
               }
               else if (rule.Trail_Strategy == "TRAIL_R") {
                   if (current_R > g_trackers[t_idx].trail_r_watermark) { g_trackers[t_idx].trail_r_watermark = current_R; }
                   if (g_trackers[t_idx].trail_r_watermark >= 1.0) { double locked_R = g_trackers[t_idx].trail_r_watermark - 1.0; if (locked_R > 0) { new_sl = (type == POSITION_TYPE_BUY) ? (open_price + locked_R * initial_risk) : (open_price - locked_R * initial_risk); } }
               }
               if (new_sl > 0 && new_sl != DBL_MAX) {
                   bool modify = false;
                   if (type == POSITION_TYPE_BUY) { if (current_sl == 0 || (new_sl > current_sl && new_sl < current_price)) modify = true; }
                   else if (type == POSITION_TYPE_SELL) { if (current_sl == 0 || (new_sl < current_sl && new_sl > current_price)) modify = true; }
                   if (modify) trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
               }
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
            for(int j = ArraySize(g_trackers) - 1; j >= 0; j--) {
               if(g_trackers[j].ticket == pos_id) {
                  double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
                  double total_pnl = g_trackers[j].realized_pnl + profit;
                  double final_rr = (g_trackers[j].initial_risk_money > 0) ? (total_pnl / g_trackers[j].initial_risk_money) : 0;
                  long reason = HistoryDealGetInteger(deal_ticket, DEAL_REASON);
                  
                  string reason_str = "👤 ĐÓNG TAY / FORCE CLOSE";
                  if(reason == DEAL_REASON_SL) reason_str = "🔴 CẮN STOP LOSS";
                  if(reason == DEAL_REASON_TP) reason_str = "✅ CHẠM TAKE PROFIT";

                  string msg = "🏁 <b>TRADE CLOSED: KẾT THÚC LỆNH</b>\n━━━━━━━━━━━━━━━\n";
                  msg += "📝 <b>Lý do:</b> " + reason_str + "\n";
                  msg += "📊 <b>Tỉ lệ RR:</b> " + DoubleToString(final_rr, 2) + "R\n";
                  msg += "💰 <b>PnL Tổng:</b> " + DoubleToString(total_pnl, 2) + "$\n";
                  msg += "💳 <b>Số dư mới:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$";
                  Radar.SendMessage(msg);

                  for(int k=j; k<ArraySize(g_trackers)-1; k++) g_trackers[k] = g_trackers[k+1];
                  ArrayResize(g_trackers, ArraySize(g_trackers)-1);
                  break;
               }
            }
         }
      }
   }
}

void ExecuteTradeLogic() {
   // BƯỚC 1: Luôn khớp CSV để dashboard hiển thị đúng kịch bản hiện tại
   string htf = CleanString(SMC_HTF.current_market_phase); string maj = CleanString(SMC_LTF.current_market_phase); string min = CleanString(SMC_LTF.current_minor_phase);
   int action_type = 0; int rule_idx = -1; double risk_mult = 1.0; string loc_filter = "NONE"; g_action_text = "Đứng ngoài (Không khớp CSV)"; g_filter_text = "";
   bool is_found = false;
   for(int i=0; i<ArraySize(g_matrix_rules); i++) {
       if(g_matrix_rules[i].HTF_State == htf && g_matrix_rules[i].Maj_State == maj && g_matrix_rules[i].Min_State == min) {
           action_type = g_matrix_rules[i].Entry_Type; risk_mult = g_matrix_rules[i].Risk_Multiplier; loc_filter = g_matrix_rules[i].Location_Filter; g_action_text = g_matrix_rules[i].Dash_Note; rule_idx = i; is_found = true; break;
       }
   }

   // BƯỚC 2: Kiểm tra Shield sau khi đã cập nhật g_action_text cho dashboard
   if (g_trading_stopped_today || g_account_passed) {
       g_filter_text = "[SHIELD] Không thực thi - Prop Shield đang chặn";
       return;
   }
   if (IsInNewsWindow()) {
       g_filter_text = "Blocked: Thời gian cấm giao dịch (News Shield Active)";
       return;
   }

   if(rule_idx >= 0) { ulong target_magic = BaseMagicNumber + rule_idx; trade.SetExpertMagicNumber(target_magic); }

   if (action_type == 0) {
       for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong ticket = OrderGetTicket(i); long magic = OrderGetInteger(ORDER_MAGIC); if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) trade.OrderDelete(ticket); }
       return;
   }

   int signal = 0; double sl_price = 0; double entry_zone = 0;
   if(action_type == 1) { signal = 1; sl_price = SMC_LTF.current_buy_zone_sl; entry_zone = SMC_LTF.current_buy_zone_entry; } 
   else if (action_type == 2) { signal = -1; sl_price = SMC_LTF.current_sell_zone_sl; entry_zone = SMC_LTF.current_sell_zone_entry; } 
   else if (action_type == 3) { signal = 1; sl_price = SMC_LTF.current_min_prot_low; entry_zone = SMC_LTF.current_minor_buy_zone_entry; } 
   else if (action_type == 4) { signal = -1; sl_price = SMC_LTF.current_min_prot_high; entry_zone = SMC_LTF.current_minor_sell_zone_entry; } 
   else if (action_type == 5) { signal = 1; sl_price = SMC_LTF.current_buy_zone_sl; entry_zone = SMC_LTF.current_minor_buy_zone_entry; } 
   else if (action_type == 6) { signal = -1; sl_price = SMC_LTF.current_sell_zone_sl; entry_zone = SMC_LTF.current_minor_sell_zone_entry; }

   if (signal == 1 && entry_zone == 0) entry_zone = SymbolInfoDouble(_Symbol, SYMBOL_ASK); if (signal == -1 && entry_zone == 0) entry_zone = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(signal == 0 || sl_price == 0 || sl_price == EMPTY_VALUE || entry_zone == 0 || entry_zone == EMPTY_VALUE) {
       for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong ticket = OrderGetTicket(i); long magic = OrderGetInteger(ORDER_MAGIC); if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) trade.OrderDelete(ticket); } return;
   }

   if (loc_filter == "HTF_ZONE") { bool is_passed = false; if (signal == 1 && g_gate_buy_open) is_passed = true; if (signal == -1 && g_gate_sell_open) is_passed = true; if (!is_passed) return; }

   double pip_size = GetPipSize(_Symbol); double buffer_val = SL_Buffer_Pips * pip_size; double raw_zone_width = MathAbs(entry_zone - sl_price); double entry_buffer_val = raw_zone_width * (Entry_Buffer_Percent / 100.0);
   double current_price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double final_sl = NormalizeDouble((signal == 1) ? (sl_price - buffer_val) : (sl_price + buffer_val), _Digits);
   double order_sl = Inp_No_SL ? 0 : final_sl;
   if (signal == 1) entry_zone = entry_zone + entry_buffer_val; else if (signal == -1) entry_zone = entry_zone - entry_buffer_val; 
   entry_zone = NormalizeDouble(entry_zone, _Digits);
   double zone_width_val = MathAbs(entry_zone - final_sl); double zone_width_pips = zone_width_val / pip_size;
   
   if (zone_width_pips > Max_Zone_SL_Pips) { double max_sl_val = Max_Zone_SL_Pips * pip_size; entry_zone = (signal == 1) ? (final_sl + max_sl_val) : (final_sl - max_sl_val); entry_zone = NormalizeDouble(entry_zone, _Digits); zone_width_val = max_sl_val; }
   if(zone_width_val <= 0) return; 

   if (Inp_Buddha_Palm) {
       if (signal == 1) { double htf_sell_top = SMC_HTF.current_sell_zone_sl; double htf_sell_bot = SMC_HTF.current_sell_zone_entry; if (htf_sell_top > 0 && htf_sell_bot > 0) { double max_p = MathMax(htf_sell_top, htf_sell_bot); double min_p = MathMin(htf_sell_top, htf_sell_bot); if (entry_zone >= min_p) { g_filter_text = "Blocked by Buddha's Palm: Đang ngầm Mua trong lòng HTF Sell Zone!"; return; } } }
       else if (signal == -1) { double htf_buy_top = SMC_HTF.current_buy_zone_entry; double htf_buy_bot = SMC_HTF.current_buy_zone_sl; if (htf_buy_top > 0 && htf_buy_bot > 0) { double max_p = MathMax(htf_buy_top, htf_buy_bot); double min_p = MathMin(htf_buy_top, htf_buy_bot); if (entry_zone <= max_p) { g_filter_text = "Blocked by Buddha's Palm: Đang ngầm Bán trong lòng HTF Buy Zone!"; return; } } }
   }

   if (Min_Reward_to_Risk_R > 0 && zone_width_val > 0) {
       double closest_obstacle = 0;
       if (signal == 1) { double obs_htf = SMC_HTF.current_sell_zone_entry; if (obs_htf > entry_zone) closest_obstacle = obs_htf; } else if (signal == -1) { double obs_htf = SMC_HTF.current_buy_zone_entry; if (obs_htf > 0 && obs_htf < entry_zone) closest_obstacle = obs_htf; }
       double intended_target = CalcTargetPrice(signal, entry_zone, final_sl, g_matrix_rules[rule_idx]); double final_limit_price = 0;
       if (closest_obstacle > 0 && intended_target > 0) { if (signal == 1) final_limit_price = MathMin(closest_obstacle, intended_target); else if (signal == -1) final_limit_price = MathMax(closest_obstacle, intended_target); } else if (closest_obstacle > 0) { final_limit_price = closest_obstacle; } else if (intended_target > 0) { final_limit_price = intended_target; }
       if (final_limit_price > 0) {
           double potential_reward = MathAbs(final_limit_price - entry_zone); double current_rr = potential_reward / zone_width_val;
           if (current_rr < Min_Reward_to_Risk_R) { g_filter_text = "Blocked by Anti-Chop: RR = " + DoubleToString(current_rr, 1) + "R (Đích đến quá gần)"; return; } else { g_filter_text = "Filter PASSED: RR = " + DoubleToString(current_rr, 1) + "R (Không gian thoáng)"; }
       } else { g_filter_text = "Filter PASSED: Đánh tự do, không có cản"; }
   }

   // Tính BOS limit price sớm (dùng cho cả has_limit check và order execution)
   double bos_lmt_price = 0, bos_risk_val = 0, bos_lmt_tp = 0;
   if (Inp_Entry_Mode == ENTRY_LIMIT_BOS) {
       double raw_bos = (signal == 1) ? SMC_LTF.current_bos_up_level : SMC_LTF.current_bos_dn_level;
       if (raw_bos > 0) {
           bos_lmt_price = NormalizeDouble(raw_bos, _Digits);
           bos_risk_val  = MathAbs(bos_lmt_price - final_sl);
           bos_lmt_tp    = CalcHardTP(signal, bos_lmt_price, final_sl, g_matrix_rules[rule_idx]);
       }
   }
   // Entry price thực sự sẽ dùng để kiểm tra has_limit (BOS mode hay Zone mode)
   double eff_entry = (bos_lmt_price > 0) ? bos_lmt_price : entry_zone;

   int risk_trades = 0; bool has_limit_at_current_zone = false;
   for(int i = 0; i < PositionsTotal(); i++) {
       ulong ticket = PositionGetTicket(i);
       if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) >= BaseMagicNumber && PositionGetInteger(POSITION_MAGIC) < BaseMagicNumber + 1000) {
           long type = PositionGetInteger(POSITION_TYPE); double open_price = PositionGetDouble(POSITION_PRICE_OPEN); double current_sl = PositionGetDouble(POSITION_SL);
           if (type == POSITION_TYPE_BUY && (current_sl < open_price || current_sl == 0)) risk_trades++; if (type == POSITION_TYPE_SELL && (current_sl > open_price || current_sl == 0)) risk_trades++;
       }
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
       ulong ticket = OrderGetTicket(i); long magic = OrderGetInteger(ORDER_MAGIC);
       if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && magic >= BaseMagicNumber && magic < BaseMagicNumber + 1000) {
           long type = OrderGetInteger(ORDER_TYPE); double o_sl = OrderGetDouble(ORDER_SL); double o_en = OrderGetDouble(ORDER_PRICE_OPEN);
           bool is_buy_limit = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP); bool is_sell_limit = (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP); bool is_perfect_match = false;
           if (signal == 1  && is_buy_limit  && MathAbs(o_sl - order_sl) < 10 * _Point && MathAbs(o_en - eff_entry) < 10 * _Point) is_perfect_match = true;
           if (signal == -1 && is_sell_limit && MathAbs(o_sl - order_sl) < 10 * _Point && MathAbs(o_en - eff_entry) < 10 * _Point) is_perfect_match = true;
           if (is_perfect_match) { has_limit_at_current_zone = true; risk_trades++; } else { trade.OrderDelete(ticket); }
       }
   }

   if(has_limit_at_current_zone || risk_trades >= Inp_Max_Risk_Trades) return;
   if (signal == 1  && MathAbs(sl_price - g_last_traded_buy_sl)  < 10 * _Point) return;
   if (signal == -1 && MathAbs(sl_price - g_last_traded_sell_sl) < 10 * _Point) return;

   // Khoảng cách tối thiểu giữa 2 lệnh cùng chiều
   if (Inp_Min_Entry_Dist_Pips > 0) {
       double min_dist = Inp_Min_Entry_Dist_Pips * pip_size;
       bool too_close = false;
       for (int i = 0; i < PositionsTotal() && !too_close; i++) {
           ulong t = PositionGetTicket(i);
           if (!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
           long mg = PositionGetInteger(POSITION_MAGIC);
           if (mg < BaseMagicNumber || mg >= BaseMagicNumber + 1000) continue;
           long tp = PositionGetInteger(POSITION_TYPE);
           if (signal == 1 && tp != POSITION_TYPE_BUY)  continue;
           if (signal ==-1 && tp != POSITION_TYPE_SELL) continue;
           if (MathAbs(eff_entry - PositionGetDouble(POSITION_PRICE_OPEN)) < min_dist) too_close = true;
       }
       for (int i = 0; i < OrdersTotal() && !too_close; i++) {
           ulong t = OrderGetTicket(i);
           if (!t || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
           long mg = OrderGetInteger(ORDER_MAGIC);
           if (mg < BaseMagicNumber || mg >= BaseMagicNumber + 1000) continue;
           long ot = OrderGetInteger(ORDER_TYPE);
           bool is_buy  = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
           bool is_sell = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
           if (signal == 1 && !is_buy)  continue;
           if (signal ==-1 && !is_sell) continue;
           if (MathAbs(eff_entry - OrderGetDouble(ORDER_PRICE_OPEN)) < min_dist) too_close = true;
       }
       if (too_close) { g_filter_text = "Blocked: Entry quá sát lệnh cũ (< " + DoubleToString(Inp_Min_Entry_Dist_Pips, 0) + " pips)"; return; }
   }

   string order_cmt = g_matrix_rules[rule_idx].Dash_Note; int dash_pos = StringFind(order_cmt, " - "); if(dash_pos > 0) order_cmt = StringSubstr(order_cmt, 0, dash_pos);

   double current_to_sl_val = MathAbs(current_price - final_sl); double current_to_sl_pips = current_to_sl_val / pip_size; bool success = false;
   double mkt_tp  = CalcHardTP(signal, current_price, final_sl, g_matrix_rules[rule_idx]);
   double lmt_tp  = CalcHardTP(signal, entry_zone,    final_sl, g_matrix_rules[rule_idx]);

   // Khi FlexTP bật: không đặt TP cứng, để FlexTP quản lý thoát theo tập lệnh cùng chiều
   double eff_mkt_tp    = Inp_FlexTP_Enabled ? 0 : mkt_tp;
   double eff_lmt_tp    = Inp_FlexTP_Enabled ? 0 : lmt_tp;
   double eff_bos_lmt_tp = Inp_FlexTP_Enabled ? 0 : bos_lmt_tp;

   if (signal == 1) {
       bool force_market = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (current_to_sl_pips <= Market_vs_Limit_Pips);
       if (force_market) {
           double lot = CalculateLotSize(current_to_sl_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.Buy(lot, _Symbol, current_price, order_sl, eff_mkt_tp, order_cmt);
       } else if (bos_lmt_price > 0 && current_price > bos_lmt_price) {
           // ENTRY_LIMIT_BOS: đặt Limit ngay tại mức BOS/ChoCh đã break
           double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.BuyLimit(lot, bos_lmt_price, _Symbol, order_sl, eff_bos_lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       } else if (current_price > entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) {
           // ENTRY_SMART: Limit tại Zone entry
           double lot = CalculateLotSize(zone_width_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.BuyLimit(lot, entry_zone, _Symbol, order_sl, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       }
       if(success || trade.ResultRetcode() == 10009) g_last_traded_buy_sl = sl_price;
   }
   else if (signal == -1) {
       bool force_market = (Inp_Entry_Mode == ENTRY_MARKET_ONLY) || (current_to_sl_pips <= Market_vs_Limit_Pips);
       if (force_market) {
           double lot = CalculateLotSize(current_to_sl_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.Sell(lot, _Symbol, current_price, order_sl, eff_mkt_tp, order_cmt);
       } else if (bos_lmt_price > 0 && current_price < bos_lmt_price) {
           // ENTRY_LIMIT_BOS: Sell Limit tại mức BOS/ChoCh đã break
           double lot = CalculateLotSize(bos_risk_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.SellLimit(lot, bos_lmt_price, _Symbol, order_sl, eff_bos_lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       } else if (current_price < entry_zone && Inp_Entry_Mode != ENTRY_LIMIT_BOS) {
           // ENTRY_SMART: Limit tại Zone entry
           double lot = CalculateLotSize(zone_width_val / _Point, risk_mult);
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; }
           success = trade.SellLimit(lot, entry_zone, _Symbol, order_sl, eff_lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       }
       if(success || trade.ResultRetcode() == 10009) g_last_traded_sell_sl = sl_price;
   }

   if (success || trade.ResultRetcode() == 10009) {
       double display_tp    = (bos_lmt_price > 0) ? bos_lmt_tp : lmt_tp;
       double sl_pips       = MathAbs(eff_entry - final_sl) / pip_size;
       string msg = "🛒 <b>ORDER PLACED: KHỚP LỆNH SMC</b>\n━━━━━━━━━━━━━━━\n🏷️ <b>Rule:</b> " + g_matrix_rules[rule_idx].Dash_Note + "\n📍 <b>Entry:</b> " + DoubleToString(eff_entry, _Digits) + "\n🛡️ <b>SL:</b> " + DoubleToString(final_sl, _Digits) + " (" + DoubleToString(sl_pips, 1) + " pips)\n🎯 <b>TP:</b> " + DoubleToString(display_tp, _Digits);
       Radar.SendMessageWithPhoto(msg);
   }
}

// ─── Helper: tạo/cập nhật một dashboard label (x, y có thể thay đổi) ──
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
   // ── Timeframe strings ──────────────────────────────────────
   string s_t = EnumToString(Trend_Timeframe); StringReplace(s_t, "PERIOD_", "");
   string s_l = EnumToString(HTF_Timeframe);   StringReplace(s_l, "PERIOD_", "");
   string s_s = EnumToString(_Period);          StringReplace(s_s, "PERIOD_", "");
   // Pad về 5 ký tự để align colon (H1→"H1   ", M15→"M15  ", M1→"M1   ")
   string t_pad = s_t; while(StringLen(t_pad) < 4) t_pad += " ";
   string l_pad = s_l; while(StringLen(l_pad) < 4) l_pad += " ";
   string s_pad = s_s; while(StringLen(s_pad) < 4) s_pad += " ";

   // ── Đếm Risk Trade đang mở ────────────────────────────────
   int risk_cnt = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetString(POSITION_SYMBOL)  == _Symbol &&
         PositionGetInteger(POSITION_MAGIC)  >= BaseMagicNumber &&
         PositionGetInteger(POSITION_MAGIC)  <  BaseMagicNumber + 1000) {
         long   pt = PositionGetInteger(POSITION_TYPE);
         double op = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         if (pt == POSITION_TYPE_BUY  && (sl < op || sl == 0)) risk_cnt++;
         if (pt == POSITION_TYPE_SELL && (sl > op || sl == 0)) risk_cnt++;
      }
   }

   // ── Màu tối ưu cho light chart ────────────────────────────
   color c_dark = clrBlack;
   color c_gray = C'130,130,130';
   color c_sep  = C'190,190,190';
   color c_ok   = C'0,140,0';
   color c_bad  = C'210,0,0';

   color buy_clr  = g_gate_buy_open  ? c_ok : c_bad;
   color sell_clr = g_gate_sell_open ? c_ok : c_bad;
   color shd_clr  = g_trading_stopped_today ? c_bad : c_ok;
   color rsk_clr  = (risk_cnt >= Inp_Max_Risk_Trades) ? c_bad : c_ok;

   string buy_val  = g_gate_buy_open  ? "OPEN"    : "LOCK";
   string sell_val = g_gate_sell_open ? "OPEN"    : "LOCK";
   string shd_val  = g_trading_stopped_today ? "STOPPED" : "ACTIVE";
   string rsk_val  = IntegerToString(risk_cnt) + "/" + IntegerToString(Inp_Max_Risk_Trades);

   // ── Filter text (dùng space khi rỗng để tránh MT5 hiện "Label") ──
   string flt_txt = (g_filter_text == "") ? " " : g_filter_text;
   color flt_clr = c_gray;
   if (StringFind(flt_txt, "PASSED") >= 0) flt_clr = c_ok;
   else if (StringFind(flt_txt, "Blocked") >= 0) flt_clr = c_bad;

   // Dọn BOT_DASH_FLT cũ nếu còn tồn tại từ phiên bản trước
   ObjectDelete(0, "BOT_DASH_FLT");

   // ── STRUCTURE (font 7, Y=25, spacing 17px, pad 4 ký tự) ──
   DashLabel("BOT_DASH_T",    8, 25, c_dark, 7, t_pad + ": " + SMC_TREND.current_market_phase);
   DashLabel("BOT_DASH_L",    8, 42, c_dark, 7, l_pad + ": " + SMC_HTF.current_market_phase);
   DashLabel("BOT_DASH_SMAJ", 8, 59, c_dark, 7, s_pad + ": Major:  " + SMC_LTF.current_market_phase);
   DashLabel("BOT_DASH_SMIN", 8, 76, c_gray, 7, "        Minor:  " + SMC_LTF.current_minor_phase);

   // ── ACTION (font 7, gap 22px để phân cụm) ────────────────
   DashLabel("BOT_DASH_ACT", 8, 98, clrMagenta, 7, g_action_text);

   // ── STATUS ROW 1: Buy | Sell (font 8, gap 22px) ──────────
   DashLabel("BOT_DASH_BUY_K", 8,   120, c_dark,   8, "Buy:");
   DashLabel("BOT_DASH_BUY_V", 46,  120, buy_clr,  8, buy_val);
   DashLabel("BOT_DASH_SLL_K", 100, 120, c_dark,   8, "Sell:");
   DashLabel("BOT_DASH_SLL_V", 142, 120, sell_clr, 8, sell_val);

   // ── STATUS ROW 2: Shield | Risk (font 7) ─────────────────
   DashLabel("BOT_DASH_SHD_K", 8,   137, c_dark,  7, "Shield:");
   DashLabel("BOT_DASH_SHD_V", 60,  137, shd_clr, 7, shd_val);
   DashLabel("BOT_DASH_RSK_K", 135, 137, c_dark,  7, "Risk:");
   DashLabel("BOT_DASH_RSK_V", 170, 137, rsk_clr, 7, rsk_val);

   // ── FILTER ở cuối (font 7) ────────────────────────────────
   DashLabel("BOT_DASH_FLT2", 8, 154, flt_clr, 7, flt_txt);
}

int OnInit() {
   Print("DA NẠP ENGINE V5.0 - ULTIMATE PROP SHIELD!");
   if(!LoadMatrixCSV()) return INIT_FAILED; 
   Radar.Init(Inp_BotToken, Inp_ChatID, Inp_SendScreenshot);
   SMC_LTF.Init(_Symbol, _Period, "TLS_LTF_", false, true, false, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, PeriodsInMajorSwing, PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
   SMC_HTF.Init(_Symbol, HTF_Timeframe, "TLS_HTF_", true, false, true, HTF_BuyZoneColor, HTF_SellZoneColor, HTF_KeyLevelColor, HTF_BOS_Up_Color, HTF_BOS_Dn_Color, clrNONE, clrNONE, HTF_PeriodsInMajorSwing, HTF_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
   SMC_TREND.Init(_Symbol, Trend_Timeframe, "TLS_TREND_", true, false, false, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, Trend_PeriodsInMajorSwing, Trend_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);

   string s_trend = EnumToString(Trend_Timeframe); StringReplace(s_trend, "PERIOD_", "");
   string s_htf   = EnumToString(HTF_Timeframe);   StringReplace(s_htf,   "PERIOD_", "");
   string s_ltf   = EnumToString(_Period);          StringReplace(s_ltf,   "PERIOD_", "");
   string msg = "🟢 <b>SYSTEM STARTED: TLS SMC BOT (T-L-S v5.1)</b>\n━━━━━━━━━━━━━━━\n";
   msg += "💰 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n";
   msg += "⚙️ <b>T-L-S:</b> " + _Symbol + " | T=" + s_trend + " | L=" + s_htf + " | S=" + s_ltf + "\n";
   msg += "🛡️ <b>Mục tiêu:</b> " + DoubleToString(Inp_AutoPassTarget, 0) + "$ | <b>Dừng lỗ ngày:</b> " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
   Radar.SendMessage(msg);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "TLS_HTF_"); ObjectsDeleteAll(0, "TLS_LTF_"); ObjectsDeleteAll(0, "TLS_TREND_");
   // Dashboard hiện tại
   string dash[] = {
      "BOT_DASH_T","BOT_DASH_L","BOT_DASH_SMAJ","BOT_DASH_SMIN",
      "BOT_DASH_ACT","BOT_DASH_FLT",
      "BOT_DASH_BUY_K","BOT_DASH_BUY_V","BOT_DASH_SLL_K","BOT_DASH_SLL_V",
      "BOT_DASH_SHD_K","BOT_DASH_SHD_V","BOT_DASH_RSK_K","BOT_DASH_RSK_V",
      "BOT_DASH_FLT2","BOT_DASH_SEP1","BOT_DASH_SEP2"
   };
   for(int i = 0; i < ArraySize(dash); i++) ObjectDelete(0, dash[i]);
   // Dashboard phiên bản cũ — cleanup khi upgrade
   string old_dash[] = {
      "BOT_DASH_S1","BOT_DASH_TREND","BOT_DASH_HTF","BOT_DASH_LTF_MAJ","BOT_DASH_LTF_MIN",
      "BOT_DASH_S2","BOT_DASH_ACTION","BOT_DASH_FILTER","BOT_DASH_S3",
      "BOT_DASH_BUY","BOT_DASH_SELL","BOT_DASH_SHIELD",
      "BOT_DASHBOARD_TREND","BOT_DASHBOARD_HTF","BOT_DASHBOARD_LTF_MAJ",
      "BOT_DASHBOARD_LTF_MIN","BOT_DASHBOARD_ACTION","BOT_DASHBOARD_FILTER","BOT_DASHBOARD_GK"
   };
   for(int i = 0; i < ArraySize(old_dash); i++) ObjectDelete(0, old_dash[i]);
}

void CheckFlexTP() {
   if (!Inp_FlexTP_Enabled) return;

   double pip_size  = GetPipSize(_Symbol);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);

   // ── Tính riêng BUY / SELL ─────────────────────────────────
   double buy_usd = 0, sell_usd = 0;
   double buy_pips = 0, sell_pips = 0;
   int    buy_cnt  = 0, sell_cnt  = 0;

   for (int i = 0; i < PositionsTotal(); i++) {
       ulong ticket = PositionGetTicket(i);
       if (!PositionSelectByTicket(ticket)) continue;
       if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
       long magic = PositionGetInteger(POSITION_MAGIC);
       if (magic < BaseMagicNumber || magic >= BaseMagicNumber + 1000) continue;

       long   type       = PositionGetInteger(POSITION_TYPE);
       double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
       double usd        = PositionGetDouble(POSITION_PROFIT)
                         + PositionGetDouble(POSITION_SWAP)
                         + PositionGetDouble(POSITION_COMMISSION);
       double cur_price  = (type == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
       double pips       = (type == POSITION_TYPE_BUY)
                           ? (cur_price - open_price) / pip_size
                           : (open_price - cur_price) / pip_size;

       if (type == POSITION_TYPE_BUY)  { buy_usd  += usd;  buy_pips  += pips;  buy_cnt++;  }
       else                            { sell_usd += usd;  sell_pips += pips;  sell_cnt++; }
   }

   if (buy_cnt == 0 && sell_cnt == 0) return;

   double all_usd  = buy_usd  + sell_usd;
   double all_pips = buy_pips + sell_pips;

   double pct_buy  = (balance > 0) ? (buy_usd  / balance * 100.0) : 0;
   double pct_sell = (balance > 0) ? (sell_usd / balance * 100.0) : 0;
   double pct_all  = (balance > 0) ? (all_usd  / balance * 100.0) : 0;

   // ── Quyết định đóng ──────────────────────────────────────
   // close_all: tổng BUY+SELL đạt ngưỡng → đóng hết
   // close_buy:  chỉ BUY đạt ngưỡng → đóng BUY, giữ SELL
   // close_sell: chỉ SELL đạt ngưỡng → đóng SELL, giữ BUY
   bool close_all  = (Inp_FlexTP_Percent > 0 && pct_all  >= Inp_FlexTP_Percent)
                  || (Inp_FlexTP_Pips    > 0 && all_pips >= Inp_FlexTP_Pips);
   bool close_buy  = !close_all && buy_cnt  > 0
                  && ((Inp_FlexTP_Percent > 0 && pct_buy  >= Inp_FlexTP_Percent)
                   || (Inp_FlexTP_Pips    > 0 && buy_pips >= Inp_FlexTP_Pips));
   bool close_sell = !close_all && sell_cnt > 0
                  && ((Inp_FlexTP_Percent > 0 && pct_sell >= Inp_FlexTP_Percent)
                   || (Inp_FlexTP_Pips    > 0 && sell_pips >= Inp_FlexTP_Pips));

   if (!close_all && !close_buy && !close_sell) return;

   // ── Đóng positions ────────────────────────────────────────
   bool any_closed = false;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
       ulong ticket = PositionGetTicket(i);
       if (!PositionSelectByTicket(ticket)) continue;
       if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
       long magic = PositionGetInteger(POSITION_MAGIC);
       if (magic < BaseMagicNumber || magic >= BaseMagicNumber + 1000) continue;
       long type = PositionGetInteger(POSITION_TYPE);
       bool do_close = close_all
                    || (close_buy  && type == POSITION_TYPE_BUY)
                    || (close_sell && type == POSITION_TYPE_SELL);
       if (do_close && trade.PositionClose(ticket)) any_closed = true;
   }
   // ── Xóa lệnh chờ cùng chiều ──────────────────────────────
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
       ulong ticket = OrderGetTicket(i);
       if (!ticket || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
       long magic = OrderGetInteger(ORDER_MAGIC);
       if (magic < BaseMagicNumber || magic >= BaseMagicNumber + 1000) continue;
       long ot = OrderGetInteger(ORDER_TYPE);
       bool is_buy_ord  = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY_STOP);
       bool is_sell_ord = (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP);
       bool do_del = close_all
                  || (close_buy  && is_buy_ord)
                  || (close_sell && is_sell_ord);
       if (do_del) trade.OrderDelete(ticket);
   }

   if (any_closed) {
       string dir = close_all ? "BUY+SELL" : (close_buy ? "BUY" : "SELL");
       double rep_usd  = close_all ? all_usd  : (close_buy ? buy_usd  : sell_usd);
       double rep_pips = close_all ? all_pips : (close_buy ? buy_pips : sell_pips);
       double rep_pct  = close_all ? pct_all  : (close_buy ? pct_buy  : pct_sell);
       bool   by_pct   = (Inp_FlexTP_Percent > 0 && rep_pct  >= Inp_FlexTP_Percent);
       string trigger_msg = by_pct
           ? ("Tổng lãi " + dir + ": +" + DoubleToString(rep_pct,  2) + "% (ngưỡng " + DoubleToString(Inp_FlexTP_Percent, 2) + "%)")
           : ("Tổng pips " + dir + ": +" + DoubleToString(rep_pips, 1) + " pips (ngưỡng " + DoubleToString(Inp_FlexTP_Pips, 1) + " pips)");
       string msg = "🏆 <b>FLEX TP: CHỐT LÃI LINH HOẠT</b>\n━━━━━━━━━━━━━━━\n📊 <b>Lý do:</b> " + trigger_msg
                  + "\n💰 <b>Lãi thực:</b> +" + DoubleToString(rep_usd, 2) + "$"
                  + "\n💳 <b>Số dư mới:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$";
       Radar.SendMessage(msg);
   }
}

void OnTick() {
   ManagePropFirmRules();
   CleanPendingOrdersForNews();
   CheckFlexTP();
   ManageTrades_Tick();
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
   if (id == CHARTEVENT_CHART_CHANGE) SMC_HTF.HandleChartEvent();
}
//+------------------------------------------------------------------+