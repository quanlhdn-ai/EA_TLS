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
input double Inp_AutoPassTarget     = 11010.0;   // 3. Mục tiêu đỗ quỹ ($) - Chạm là chốt hết nghỉ ngơi
input string Inp_NewsTimes          = "15:30, 21:00"; // 4. Giờ ra Tin Đỏ (Theo GIỜ SÀN MT5, cách nhau dấu phẩy)
input int    Inp_NewsBufferMinutes  = 2;         //    Ngừng giao dịch và xóa lệnh chờ trước/sau tin (Phút)

input group "--- Risk Management & Scaling ---"
input int    Inp_Max_Risk_Trades    = 3;     
input bool   UseRiskPerTrade        = true;  
input double RiskPercent            = 0.5;   
input double FixedLotSize           = 0.05;  
input double SL_Buffer_Pips         = 30.0;  

input group "--- Smart Order Execution ---"
input double Market_vs_Limit_Pips   = 50.0;  
input double Max_Zone_SL_Pips       = 300.0; 
input double Entry_Buffer_Percent   = 10.0;  
input double Min_Reward_to_Risk_R   = 1.5;   

input group "--- The Smart Gatekeeper (Location Filter) ---"
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

input group "--- LTF Core Logic Settings (M1) ---"
input int    PeriodsInMajorSwing    = 9;     
input int    PeriodsInMinorSwing    = 5;     
input int    MaxZones               = 1;
input int    MaxBOSLines            = 5;
input int    MaxMinorBOSLines       = 3;

input group "--- Dashboard Settings ---"
input color  DashboardColor         = clrBlack; 

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
double g_last_broken_buy_zone_sl = 0.0;
double g_last_broken_sell_zone_sl = 0.0;

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
bool LoadMatrixCSV() { int handle = FileOpen("TLS_Matrix.csv", FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON, 0, CP_UTF8); if(handle == INVALID_HANDLE) { Print("LỖI: Không tìm thấy TLS_Matrix.csv!"); return false; } ArrayResize(g_matrix_rules, 0); bool is_header = true; while(!FileIsEnding(handle)) { string line = FileReadString(handle); string check_empty = line; StringTrimLeft(check_empty); StringTrimRight(check_empty); if(check_empty == "") continue; if(is_header) { is_header = false; continue; } ushort separator = StringGetCharacter(",", 0); if (StringFind(line, ";") >= 0) separator = StringGetCharacter(";", 0); else if (StringFind(line, "\t") >= 0) separator = StringGetCharacter("\t", 0); string cols[]; int col_count = StringSplit(line, separator, cols); if (col_count >= 13) { int size = ArraySize(g_matrix_rules); ArrayResize(g_matrix_rules, size + 1); g_matrix_rules[size].HTF_State = CleanString(cols[0]); g_matrix_rules[size].Maj_State = CleanString(cols[1]); g_matrix_rules[size].Min_State = CleanString(cols[2]); g_matrix_rules[size].Entry_Type = (int)StringToInteger(cols[3]); g_matrix_rules[size].Risk_Multiplier = StringToDouble(cols[4]); g_matrix_rules[size].BE_Trigger_R = StringToDouble(cols[5]); g_matrix_rules[size].Partial_R = StringToDouble(cols[6]); g_matrix_rules[size].Partial_Pct = StringToDouble(cols[7]); g_matrix_rules[size].TP_Strategy = CleanString(cols[8]); g_matrix_rules[size].TP_Param = StringToDouble(cols[9]); g_matrix_rules[size].Trail_Strategy = CleanString(cols[10]); g_matrix_rules[size].Location_Filter = CleanString(cols[11]); string dash_note = cols[12]; StringReplace(dash_note, "\"", ""); g_matrix_rules[size].Dash_Note = dash_note; } } FileClose(handle); return true; }
double GetPipSize(string sym) { string s = sym; StringToUpper(s); if (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1; if (StringFind(s, "JPY") >= 0) return 0.01; long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS); if (digits == 5 || digits == 4) return 0.0001; if (digits == 3 || digits == 2) return 0.01; return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0; }
bool IsNewBar() { static datetime last_bar_time = 0; datetime current_bar_time = iTime(_Symbol, _Period, 0); if(last_bar_time == 0) { last_bar_time = current_bar_time; return true; } if(current_bar_time != last_bar_time) { last_bar_time = current_bar_time; return true; } return false; }

CSMC_Engine SMC_LTF; 
CSMC_Engine SMC_HTF; 

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
    double pip_size = GetPipSize(_Symbol);
    if (SMC_HTF.current_buy_zone_entry > 0 && SMC_HTF.current_buy_zone_sl > 0) {
        double htf_top = SMC_HTF.current_buy_zone_entry; double htf_bot = SMC_HTF.current_buy_zone_sl; double w_pips = MathAbs(htf_top - htf_bot) / pip_size; double buffer_pips = MathMax((w_pips * HTF_Zone_Buffer_Pct / 100.0), Min_HTF_Buffer_Pips); double buffered_top = htf_top + (buffer_pips * pip_size);
        if (SymbolInfoDouble(_Symbol, SYMBOL_BID) <= buffered_top && SMC_HTF.current_buy_zone_sl != g_last_broken_buy_zone_sl) g_gate_buy_open = true;
    }
    if (SMC_HTF.current_sell_zone_entry > 0 && SMC_HTF.current_sell_zone_sl > 0) {
        double htf_bot = SMC_HTF.current_sell_zone_entry; double htf_top = SMC_HTF.current_sell_zone_sl; double w_pips = MathAbs(htf_top - htf_bot) / pip_size; double buffer_pips = MathMax((w_pips * HTF_Zone_Buffer_Pct / 100.0), Min_HTF_Buffer_Pips); double buffered_bot = htf_bot - (buffer_pips * pip_size);
        if (SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= buffered_bot && SMC_HTF.current_sell_zone_sl != g_last_broken_sell_zone_sl) g_gate_sell_open = true;
    }
    MqlRates r[]; ArraySetAsSeries(r, true);
    if (CopyRates(_Symbol, _Period, 0, 2, r) >= 2) {
        double ha_open_1  = ( (r[1].open + r[1].close)/2.0 + (r[1].open + r[1].high + r[1].low + r[1].close)/4.0 ) / 2.0; double ha_close_1 = (r[1].open + r[1].high + r[1].low + r[1].close) / 4.0; double ha_low_1   = MathMin(r[1].low, MathMin(ha_open_1, ha_close_1)); double ha_high_1  = MathMax(r[1].high, MathMax(ha_open_1, ha_close_1));
        if (g_gate_buy_open && SMC_HTF.current_buy_zone_entry > 0 && SMC_HTF.current_buy_zone_sl > 0) {
            double h = MathAbs(SMC_HTF.current_buy_zone_entry - SMC_HTF.current_buy_zone_sl); double kill_line = SMC_HTF.current_buy_zone_sl - (h * Zone_Break_Tolerance_Pct / 100.0);
            if (ha_low_1 < kill_line && ha_close_1 < SMC_HTF.current_buy_zone_sl) { g_gate_buy_open = false; g_last_broken_buy_zone_sl = SMC_HTF.current_buy_zone_sl; }
        }
        if (g_gate_sell_open && SMC_HTF.current_sell_zone_entry > 0 && SMC_HTF.current_sell_zone_sl > 0) {
            double h = MathAbs(SMC_HTF.current_sell_zone_sl - SMC_HTF.current_sell_zone_entry); double kill_line = SMC_HTF.current_sell_zone_sl + (h * Zone_Break_Tolerance_Pct / 100.0);
            if (ha_high_1 > kill_line && ha_close_1 > SMC_HTF.current_sell_zone_sl) { g_gate_sell_open = false; g_last_broken_sell_zone_sl = SMC_HTF.current_sell_zone_sl; }
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
   if (g_trading_stopped_today || g_account_passed) return;
   if (IsInNewsWindow()) {
       g_filter_text = "Blocked: Thời gian cấm giao dịch (News Shield Active)";
       return;
   }

   string htf = CleanString(SMC_HTF.current_market_phase); string maj = CleanString(SMC_LTF.current_market_phase); string min = CleanString(SMC_LTF.current_minor_phase);
   int action_type = 0; int rule_idx = -1; double risk_mult = 1.0; string loc_filter = "NONE"; g_action_text = "Đứng ngoài (Không khớp CSV)"; g_filter_text = ""; 
   bool is_found = false;
   for(int i=0; i<ArraySize(g_matrix_rules); i++) {
       if(g_matrix_rules[i].HTF_State == htf && g_matrix_rules[i].Maj_State == maj && g_matrix_rules[i].Min_State == min) {
           action_type = g_matrix_rules[i].Entry_Type; risk_mult = g_matrix_rules[i].Risk_Multiplier; loc_filter = g_matrix_rules[i].Location_Filter; g_action_text = g_matrix_rules[i].Dash_Note; rule_idx = i; is_found = true; break;
       }
   }

   ulong target_magic = BaseMagicNumber + rule_idx; trade.SetExpertMagicNumber(target_magic);

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
   if (signal == 1) entry_zone = entry_zone + entry_buffer_val; else if (signal == -1) entry_zone = entry_zone - entry_buffer_val; 
   entry_zone = NormalizeDouble(entry_zone, _Digits);
   double zone_width_val = MathAbs(entry_zone - final_sl); double zone_width_pips = zone_width_val / pip_size;
   
   if (zone_width_pips > Max_Zone_SL_Pips) { double max_sl_val = Max_Zone_SL_Pips * pip_size; entry_zone = (signal == 1) ? (final_sl + max_sl_val) : (final_sl - max_sl_val); entry_zone = NormalizeDouble(entry_zone, _Digits); zone_width_val = max_sl_val; }
   if(zone_width_val <= 0) return; 

   if (signal == 1) { double htf_sell_top = SMC_HTF.current_sell_zone_sl; double htf_sell_bot = SMC_HTF.current_sell_zone_entry; if (htf_sell_top > 0 && htf_sell_bot > 0) { double max_p = MathMax(htf_sell_top, htf_sell_bot); double min_p = MathMin(htf_sell_top, htf_sell_bot); if (entry_zone >= min_p) { g_filter_text = "Blocked by Buddha's Palm: Đang ngầm Mua trong lòng HTF Sell Zone!"; return; } } } 
   else if (signal == -1) { double htf_buy_top = SMC_HTF.current_buy_zone_entry; double htf_buy_bot = SMC_HTF.current_buy_zone_sl; if (htf_buy_top > 0 && htf_buy_bot > 0) { double max_p = MathMax(htf_buy_top, htf_buy_bot); double min_p = MathMin(htf_buy_top, htf_buy_bot); if (entry_zone <= max_p) { g_filter_text = "Blocked by Buddha's Palm: Đang ngầm Bán trong lòng HTF Buy Zone!"; return; } } }

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
           if (signal == 1 && is_buy_limit && MathAbs(o_sl - final_sl) < 10 * _Point && MathAbs(o_en - entry_zone) < 10 * _Point) is_perfect_match = true;
           if (signal == -1 && is_sell_limit && MathAbs(o_sl - final_sl) < 10 * _Point && MathAbs(o_en - entry_zone) < 10 * _Point) is_perfect_match = true;
           if (is_perfect_match) { has_limit_at_current_zone = true; risk_trades++; } else { trade.OrderDelete(ticket); }
       }
   }

   if(has_limit_at_current_zone || risk_trades >= Inp_Max_Risk_Trades) return; 
   if (signal == 1 && MathAbs(sl_price - g_last_traded_buy_sl) < 10 * _Point) return; if (signal == -1 && MathAbs(sl_price - g_last_traded_sell_sl) < 10 * _Point) return;

   string order_cmt = g_matrix_rules[rule_idx].Dash_Note; int dash_pos = StringFind(order_cmt, " - "); if(dash_pos > 0) order_cmt = StringSubstr(order_cmt, 0, dash_pos);

   double current_to_sl_val = MathAbs(current_price - final_sl); double current_to_sl_pips = current_to_sl_val / pip_size; bool success = false;
   double mkt_tp = CalcHardTP(signal, current_price, final_sl, g_matrix_rules[rule_idx]); double lmt_tp = CalcHardTP(signal, entry_zone, final_sl, g_matrix_rules[rule_idx]);
   
   if (signal == 1) {
       if (current_to_sl_pips <= Market_vs_Limit_Pips) { 
           double lot = CalculateLotSize(current_to_sl_val / _Point, risk_mult); 
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; } 
           success = trade.Buy(lot, _Symbol, current_price, final_sl, mkt_tp, order_cmt); 
       } else if(current_price > entry_zone) {
           double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); 
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; } 
           success = trade.BuyLimit(lot, entry_zone, _Symbol, final_sl, lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       }
       if(success || trade.ResultRetcode() == 10009) g_last_traded_buy_sl = sl_price;
   }
   else if (signal == -1) {
       if (current_to_sl_pips <= Market_vs_Limit_Pips) { 
           double lot = CalculateLotSize(current_to_sl_val / _Point, risk_mult); 
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; } 
           success = trade.Sell(lot, _Symbol, current_price, final_sl, mkt_tp, order_cmt);
       } else if(current_price < entry_zone) {
           double lot = CalculateLotSize(zone_width_val / _Point, risk_mult); 
           if(lot <= 0) { g_filter_text = "Blocked: Hết hạn mức Margin (Shield Active)"; return; } 
           success = trade.SellLimit(lot, entry_zone, _Symbol, final_sl, lmt_tp, ORDER_TIME_GTC, 0, order_cmt);
       }
       if(success || trade.ResultRetcode() == 10009) g_last_traded_sell_sl = sl_price;
   }

   if (success || trade.ResultRetcode() == 10009) {
       double sl_pips = MathAbs(entry_zone - final_sl) / pip_size;
       string msg = "🛒 <b>ORDER PLACED: KHỚP LỆNH SMC</b>\n━━━━━━━━━━━━━━━\n🏷️ <b>Rule:</b> " + g_matrix_rules[rule_idx].Dash_Note + "\n📍 <b>Entry:</b> " + DoubleToString(entry_zone, _Digits) + "\n🛡️ <b>SL:</b> " + DoubleToString(final_sl, _Digits) + " (" + DoubleToString(sl_pips, 1) + " pips)\n🎯 <b>TP:</b> " + DoubleToString(lmt_tp, _Digits);
       Radar.SendMessageWithPhoto(msg); 
   }
}

void UpdateDashboard() {
   string htf_str = EnumToString(HTF_Timeframe); StringReplace(htf_str, "PERIOD_", ""); string ltf_str = EnumToString(_Period); StringReplace(ltf_str, "PERIOD_", "");
   string htf_text = htf_str + ": " + SMC_HTF.current_market_phase; string ltf_maj_text = ltf_str + " Major: " + SMC_LTF.current_market_phase; string ltf_min_text = ltf_str + " Minor: " + SMC_LTF.current_minor_phase; string action_text = "Action: " + g_action_text;
   string gk_text = "Gate Status: "; gk_text += (g_gate_buy_open) ? "Buy[OPEN]  " : "Buy[LOCKED]  "; gk_text += (g_gate_sell_open) ? "Sell[OPEN]" : "Sell[LOCKED]";
   
   string prop_status = "Prop Shield: " + (g_trading_stopped_today ? "[STOPPED]" : "[ACTIVE]");

   if(ObjectFind(0, "BOT_DASHBOARD_HTF") < 0) { ObjectCreate(0, "BOT_DASHBOARD_HTF", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_YDISTANCE, 26); ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_COLOR, DashboardColor); ObjectSetInteger(0, "BOT_DASHBOARD_HTF", OBJPROP_FONTSIZE, 7); ObjectSetString(0, "BOT_DASHBOARD_HTF", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_HTF", OBJPROP_TEXT, htf_text);
   if(ObjectFind(0, "BOT_DASHBOARD_LTF_MAJ") < 0) { ObjectCreate(0, "BOT_DASHBOARD_LTF_MAJ", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_YDISTANCE, 42); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_COLOR, DashboardColor); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_FONTSIZE, 7); ObjectSetString(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_LTF_MAJ", OBJPROP_TEXT, ltf_maj_text);
   if(ObjectFind(0, "BOT_DASHBOARD_LTF_MIN") < 0) { ObjectCreate(0, "BOT_DASHBOARD_LTF_MIN", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_YDISTANCE, 57); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_COLOR, DashboardColor); ObjectSetInteger(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_FONTSIZE, 7); ObjectSetString(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_LTF_MIN", OBJPROP_TEXT, ltf_min_text);
   if(ObjectFind(0, "BOT_DASHBOARD_ACTION") < 0) { ObjectCreate(0, "BOT_DASHBOARD_ACTION", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_YDISTANCE, 75); ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_COLOR, clrMagenta); ObjectSetInteger(0, "BOT_DASHBOARD_ACTION", OBJPROP_FONTSIZE, 8); ObjectSetString(0, "BOT_DASHBOARD_ACTION", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_ACTION", OBJPROP_TEXT, action_text);
   if(ObjectFind(0, "BOT_DASHBOARD_FILTER") < 0) { ObjectCreate(0, "BOT_DASHBOARD_FILTER", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_YDISTANCE, 90); ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_COLOR, (StringFind(g_filter_text, "Blocked") >= 0) ? clrRed : clrGray); ObjectSetInteger(0, "BOT_DASHBOARD_FILTER", OBJPROP_FONTSIZE, 8); ObjectSetString(0, "BOT_DASHBOARD_FILTER", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_FILTER", OBJPROP_TEXT, g_filter_text);
   if(ObjectFind(0, "BOT_DASHBOARD_GK") < 0) { ObjectCreate(0, "BOT_DASHBOARD_GK", OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_XDISTANCE, 5); ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_SELECTABLE, false); }
   ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_YDISTANCE, 105); ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_COLOR, clrGreen); ObjectSetInteger(0, "BOT_DASHBOARD_GK", OBJPROP_FONTSIZE, 8); ObjectSetString(0, "BOT_DASHBOARD_GK", OBJPROP_FONT, "Arial"); ObjectSetString(0, "BOT_DASHBOARD_GK", OBJPROP_TEXT, gk_text + " | " + prop_status);
}

int OnInit() {
   Print("DA NẠP ENGINE V5.0 - ULTIMATE PROP SHIELD!");
   if(!LoadMatrixCSV()) return INIT_FAILED; 
   Radar.Init(Inp_BotToken, Inp_ChatID, Inp_SendScreenshot);
   SMC_LTF.Init(_Symbol, _Period, "TLS_LTF_", false, true, false, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, PeriodsInMajorSwing, PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
   SMC_HTF.Init(_Symbol, HTF_Timeframe, "TLS_HTF_", true, false, true, HTF_BuyZoneColor, HTF_SellZoneColor, HTF_KeyLevelColor, HTF_BOS_Up_Color, HTF_BOS_Dn_Color, clrNONE, clrNONE, HTF_PeriodsInMajorSwing, HTF_PeriodsInMinorSwing, MaxZones, MaxBOSLines, MaxMinorBOSLines);
   
   string msg = "🟢 <b>SYSTEM STARTED: TLS SMC BOT (PROP SHIELD ON)</b>\n━━━━━━━━━━━━━━━\n";
   msg += "💰 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n";
   msg += "⚙️ <b>Thiết lập:</b> " + _Symbol + " | LTF: " + EnumToString(_Period) + " | HTF: " + EnumToString(HTF_Timeframe) + "\n";
   msg += "🛡️ <b>Mục tiêu:</b> " + DoubleToString(Inp_AutoPassTarget, 0) + "$ | <b>Dừng lỗ ngày:</b> " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
   Radar.SendMessage(msg);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, "TLS_HTF_"); ObjectsDeleteAll(0, "TLS_LTF_"); 
   ObjectDelete(0, "BOT_DASHBOARD_HTF"); ObjectDelete(0, "BOT_DASHBOARD_LTF_MAJ");
   ObjectDelete(0, "BOT_DASHBOARD_LTF_MIN"); ObjectDelete(0, "BOT_DASHBOARD_ACTION");
   ObjectDelete(0, "BOT_DASHBOARD_FILTER"); ObjectDelete(0, "BOT_DASHBOARD_GK");
}

void OnTick() {
   ManagePropFirmRules();
   CleanPendingOrdersForNews();
   ManageTrades_Tick();
   UpdateGatekeeperState(); 
   if(IsNewBar()) { 
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