//+------------------------------------------------------------------+
//|                                                   TLS_SMC_EA.mq5|
//|                   SMC Multi-Timeframe EA                         |
//|                   Based on Combo_MajorSwing_HA_BOS_Zone_V96     |
//|                   Strategy: BOS/CHOCH + Zone + Confluence        |
//|                   Version: 1.00                                  |
//+------------------------------------------------------------------+
#property copyright "anhtuan02t1"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
COrderInfo orderInfo;
CPositionInfo posInfo;

//==========================================================================
// INPUT PARAMETERS
//==========================================================================
input group "--- Indicator Settings ---" input int InpMajorSwingPeriods = 9;
input int InpMinorSwingPeriods = 5;
input int InpMovingAvgPeriods = 21;

input group "--- Risk Management ---" input double InpRiskUSD = 10.0; // Risk per trade (USD)
input double InpRR = 2.0;                                             // Risk:Reward ratio
input double InpMaxSpreadPoints = 30;                                 // Max spread to enter (points)

input group "--- Break-Even Settings ---" input bool InpUseBE = true; // Use Break-Even
input double InpBE_RR = 1.0;                                          // Move BE when price at 1:1

input group "--- Session DD Gate ---" input bool InpUseSessionDD = true; // Use Session DD Gate
input double InpMaxSessionDD_USD = 50.0;                                 // Max session drawdown (USD)

input group "--- Trade Settings ---" input int InpMagic = 202501; // Magic Number
input string InpComment = "TLS_SMC";

input group "--- Indicator Settings (Chart) ---"
input string InpIndicatorName = "test_smc"; // Indicator name on chart (must match exactly)

//==========================================================================
// BUFFER INDEX CONSTANTS (Indicator — sau patch v46.01)
//==========================================================================
#define BUF_MAJOR_TREND 10
#define BUF_MAJOR_EVENT 12
#define BUF_MAJOR_PROT_HIGH 14
#define BUF_MAJOR_PROT_LOW 15
#define BUF_BUY_ZONE_ENTRY 18  // Buy zone top (entry)
#define BUF_BUY_ZONE_SL 19     // Buy zone bottom (SL)
#define BUF_SELL_ZONE_SL 20    // Sell zone top (SL)
#define BUF_SELL_ZONE_ENTRY 21 // Sell zone bottom (entry)
#define BUF_BOS_UP_LEVEL 22    // carry-forward BOS UP
#define BUF_BOS_DN_LEVEL 23    // carry-forward BOS DN
#define BUF_CHOCH_UP_LEVEL 24  // carry-forward CHOCH UP
#define BUF_CHOCH_DN_LEVEL 25  // carry-forward CHOCH DN

//==========================================================================
// INDICATOR HANDLES
//==========================================================================
int h_H1 = INVALID_HANDLE;
int h_M15 = INVALID_HANDLE;
int h_M1 = INVALID_HANDLE;

//==========================================================================
// TRADE STATE
//==========================================================================
bool g_confirmed = false;
bool g_limit_active = false;
bool g_zone_used = false;
bool g_is_buy_side = false;

double g_limit_price = 0;
double g_limit_sl = 0;
double g_limit_tp = 0;
double g_limit_lots = 0;
ulong g_limit_ticket = 0;

double g_M1_ref = EMPTY_VALUE;
double g_H1_ref = EMPTY_VALUE;
double g_M15_ref = EMPTY_VALUE;

// Break-even tracking
bool g_be_done = false;

// Session DD
double g_session_start_balance = 0;
bool g_session_dd_hit = false;

// New bar tracking
datetime g_last_bar_M1 = 0;
datetime g_last_bar_M15 = 0;
datetime g_last_bar_H1 = 0;

//==========================================================================
// STRUCT: snapshot buffer data per timeframe
//==========================================================================
struct TFData
{
    double major_trend;
    double major_event;
    double prot_high;
    double prot_low;
    double buy_zone_entry;
    double buy_zone_sl;
    double sell_zone_sl;
    double sell_zone_entry;
    double bos_up;
    double bos_dn;
    double choch_up;
    double choch_dn;
};

TFData g_M1, g_M15, g_H1;

//+------------------------------------------------------------------+
//| UTILITY: Pip Size                                                |
//+------------------------------------------------------------------+
double PipSize()
{
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    if (digits == 5 || digits == 3)
        return _Point * 10;
    return _Point;
}

//+------------------------------------------------------------------+
//| UTILITY: Normalize price to symbol digits                        |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
    return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| UTILITY: Normalize lot size                                      |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lots = MathFloor(lots / step) * step;
    lots = MathMax(lots, min);
    lots = MathMin(lots, max);
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| UTILITY: Calculate lot size from risk USD                        |
//+------------------------------------------------------------------+
double CalcLotsByRiskUSD(double sl_points, double risk_usd)
{
    if (sl_points <= 0)
        return 0;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tick_value <= 0 || tick_size <= 0)
        return 0;
    double value_per_lot_per_point = tick_value / tick_size * _Point;
    if (value_per_lot_per_point <= 0)
        return 0;
    double lots = risk_usd / (sl_points * value_per_lot_per_point);
    return NormalizeVolume(lots);
}

//+------------------------------------------------------------------+
//| UTILITY: Is new bar on given timeframe                           |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &last_time)
{
    datetime t[];
    if (CopyTime(_Symbol, tf, 0, 1, t) < 1)
        return false;
    if (t[0] != last_time)
    {
        last_time = t[0];
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| UTILITY: Get current spread in points                            |
//+------------------------------------------------------------------+
double GetSpreadPoints()
{
    return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

//+------------------------------------------------------------------+
//| INDICATOR: Get handles from open charts via ChartIndicatorGet    |
//| Requires: M1/M15/H1 charts open with indicator attached manually |
//+------------------------------------------------------------------+
bool InitIndicatorHandles()
{
    h_H1  = INVALID_HANDLE;
    h_M15 = INVALID_HANDLE;
    h_M1  = INVALID_HANDLE;

    long chart_id = ChartFirst();
    while (chart_id >= 0)
    {
        if (ChartSymbol(chart_id) == _Symbol)
        {
            ENUM_TIMEFRAMES tf = ChartPeriod(chart_id);
            int h = ChartIndicatorGet(chart_id, 0, InpIndicatorName);
            if (h != INVALID_HANDLE)
            {
                if (tf == PERIOD_H1  && h_H1  == INVALID_HANDLE) { h_H1  = h; Print("[INIT] H1  handle=", h, " from chart_id=", chart_id); }
                if (tf == PERIOD_M15 && h_M15 == INVALID_HANDLE) { h_M15 = h; Print("[INIT] M15 handle=", h, " from chart_id=", chart_id); }
                if (tf == PERIOD_M1  && h_M1  == INVALID_HANDLE) { h_M1  = h; Print("[INIT] M1  handle=", h, " from chart_id=", chart_id); }
            }
        }
        chart_id = ChartNext(chart_id);
    }

    Print("[INIT] Handles — H1=", h_H1, " M15=", h_M15, " M1=", h_M1,
          " (INVALID=", INVALID_HANDLE, ")");

    if (h_H1 == INVALID_HANDLE)
        Print("[INIT] WARN: H1 handle not found. Open XAUUSDm H1 chart with '", InpIndicatorName, "' attached.");
    if (h_M15 == INVALID_HANDLE)
        Print("[INIT] WARN: M15 handle not found. Open XAUUSDm M15 chart with '", InpIndicatorName, "' attached.");
    if (h_M1 == INVALID_HANDLE)
        Print("[INIT] WARN: M1 handle not found. Open XAUUSDm M1 chart with '", InpIndicatorName, "' attached.");

    if (h_H1 == INVALID_HANDLE || h_M15 == INVALID_HANDLE || h_M1 == INVALID_HANDLE)
    {
        Print("[INIT] ERROR: Missing handles. EA cannot start.");
        return false;
    }

    int bc_h1  = BarsCalculated(h_H1);
    int bc_m15 = BarsCalculated(h_M15);
    int bc_m1  = BarsCalculated(h_M1);
    Print("[INIT] BarsCalculated — H1=", bc_h1, " M15=", bc_m15, " M1=", bc_m1);

    return true;
}

//+------------------------------------------------------------------+
//| INDICATOR: Read all needed buffers from one handle, shift=1      |
//+------------------------------------------------------------------+
bool ReadBuffers(int handle, int shift, TFData &out)
{
    // Silent wait until indicator is ready
    int bc = BarsCalculated(handle);
    if (bc <= 0)
        return false;

    // Log once when indicator becomes ready
    static int last_bc_h1 = 0, last_bc_m15 = 0, last_bc_m1 = 0;
    if (handle == h_H1  && last_bc_h1  == 0) { Print("[READY] H1  BarsCalculated=", bc);  last_bc_h1  = bc; }
    if (handle == h_M15 && last_bc_m15 == 0) { Print("[READY] M15 BarsCalculated=", bc);  last_bc_m15 = bc; }
    if (handle == h_M1  && last_bc_m1  == 0) { Print("[READY] M1  BarsCalculated=", bc);  last_bc_m1  = bc; }

    double tmp[1];

#define READ_BUF(buf_idx, dest)                                          \
    if (CopyBuffer(handle, buf_idx, shift, 1, tmp) < 1) {               \
        Print("[ReadBuffers] ERROR: CopyBuffer failed buf=", buf_idx,    \
              " handle=", handle, " shift=", shift,                      \
              " BarsCalculated=", bc);                                   \
        return false;                                                    \
    }                                                                    \
    dest = tmp[0];

    READ_BUF(BUF_MAJOR_TREND,     out.major_trend)
    READ_BUF(BUF_MAJOR_EVENT,     out.major_event)
    READ_BUF(BUF_MAJOR_PROT_HIGH, out.prot_high)
    READ_BUF(BUF_MAJOR_PROT_LOW,  out.prot_low)
    READ_BUF(BUF_BUY_ZONE_ENTRY,  out.buy_zone_entry)
    READ_BUF(BUF_BUY_ZONE_SL,     out.buy_zone_sl)
    READ_BUF(BUF_SELL_ZONE_SL,    out.sell_zone_sl)
    READ_BUF(BUF_SELL_ZONE_ENTRY, out.sell_zone_entry)
    READ_BUF(BUF_BOS_UP_LEVEL,    out.bos_up)
    READ_BUF(BUF_BOS_DN_LEVEL,    out.bos_dn)
    READ_BUF(BUF_CHOCH_UP_LEVEL,  out.choch_up)
    READ_BUF(BUF_CHOCH_DN_LEVEL,  out.choch_dn)

#undef READ_BUF
    return true;
}

//+------------------------------------------------------------------+
//| DEBUG: Print all buffer values for one timeframe (new bar only)  |
//+------------------------------------------------------------------+
void LogTFData(string tf_label, const TFData &d)
{
    string bz  = StringFormat("BuyZone[entry=%.5f sl=%.5f]",
                    d.buy_zone_entry == EMPTY_VALUE ? 0 : d.buy_zone_entry,
                    d.buy_zone_sl    == EMPTY_VALUE ? 0 : d.buy_zone_sl);
    string sz  = StringFormat("SellZone[sl=%.5f entry=%.5f]",
                    d.sell_zone_sl    == EMPTY_VALUE ? 0 : d.sell_zone_sl,
                    d.sell_zone_entry == EMPTY_VALUE ? 0 : d.sell_zone_entry);
    string bos = StringFormat("BOS[up=%.5f dn=%.5f]",
                    d.bos_up == EMPTY_VALUE ? 0 : d.bos_up,
                    d.bos_dn == EMPTY_VALUE ? 0 : d.bos_dn);
    string choch = StringFormat("CHOCH[up=%.5f dn=%.5f]",
                    d.choch_up == EMPTY_VALUE ? 0 : d.choch_up,
                    d.choch_dn == EMPTY_VALUE ? 0 : d.choch_dn);
    Print("[BUF] ", tf_label,
          " Trend=", (int)d.major_trend,
          " Event=", (int)d.major_event,
          " | ", bz,
          " | ", sz,
          " | ", bos,
          " | ", choch);
}

//+------------------------------------------------------------------+
//| LOGIC: Check H1 trend direction                                  |
//+------------------------------------------------------------------+
int CheckH1Trend()
{
    int trend = (int)g_H1.major_trend;
    string trend_str = (trend == 1) ? "BULL (+1)" :
                       (trend == -1) ? "BEAR (-1)" : "NEUTRAL (0)";
    Print("[H1 TREND] ", trend_str,
          " | ProtHigh=", g_H1.prot_high == EMPTY_VALUE ? 0 : g_H1.prot_high,
          " ProtLow=",   g_H1.prot_low  == EMPTY_VALUE ? 0 : g_H1.prot_low,
          " | BOS_Up=",  g_H1.bos_up    == EMPTY_VALUE ? 0 : g_H1.bos_up,
          " BOS_Dn=",    g_H1.bos_dn    == EMPTY_VALUE ? 0 : g_H1.bos_dn,
          " CHOCH_Up=",  g_H1.choch_up  == EMPTY_VALUE ? 0 : g_H1.choch_up,
          " CHOCH_Dn=",  g_H1.choch_dn  == EMPTY_VALUE ? 0 : g_H1.choch_dn,
          " | Event=",   (int)g_H1.major_event);
    if (trend == 0)
        Print("[H1 TREND] => NEUTRAL — EA will skip this bar.");
    return trend;
}

//+------------------------------------------------------------------+
//| LOGIC: Calculate ref level for given TFData (buy or sell side)   |
//+------------------------------------------------------------------+
double CalcRef(const TFData &tf, bool is_buy_side)
{
    if (is_buy_side)
        return (tf.bos_up != EMPTY_VALUE) ? tf.bos_up : tf.choch_up;
    else
        return (tf.bos_dn != EMPTY_VALUE) ? tf.bos_dn : tf.choch_dn;
}

//+------------------------------------------------------------------+
//| LOGIC: Detect M1 signal — M1 có CHOCH/BOS cùng chiều + Zone     |
//| BUY:  event=1(BOS_Up) hoặc 2(CHOCH_Up) + BuyZone tồn tại        |
//| SELL: event=-1(BOS_Dn) hoặc -2(CHOCH_Dn) + SellZone tồn tại    |
//+------------------------------------------------------------------+
bool DetectM1Signal(bool is_buy_side)
{
    double ev   = g_M1.major_event;
    string side = is_buy_side ? "BUY" : "SELL";

    string ev_str;
    if      (ev ==  1.0) ev_str = "BOS_Up(+1)";
    else if (ev ==  2.0) ev_str = "CHOCH_Up(+2)";
    else if (ev == -1.0) ev_str = "BOS_Dn(-1)";
    else if (ev == -2.0) ev_str = "CHOCH_Dn(-2)";
    else                 ev_str = StringFormat("NONE(%.0f)", ev);

    // Log snapshot M1
    Print("[M1 SIGNAL] ", side,
          " | Event=", ev_str,
          " | BuyZone[entry=", g_M1.buy_zone_entry == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.buy_zone_entry,5),
          " sl=",              g_M1.buy_zone_sl    == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.buy_zone_sl,5), "]",
          " SellZone[sl=",    g_M1.sell_zone_sl    == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.sell_zone_sl,5),
          " entry=",           g_M1.sell_zone_entry == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.sell_zone_entry,5), "]",
          " | BOS_Up=",  g_M1.bos_up   == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.bos_up,5),
          " BOS_Dn=",   g_M1.bos_dn   == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.bos_dn,5),
          " CHOCH_Up=", g_M1.choch_up == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.choch_up,5),
          " CHOCH_Dn=", g_M1.choch_dn == EMPTY_VALUE ? "EMPTY" : DoubleToString(g_M1.choch_dn,5));

    if (is_buy_side)
    {
        // Cần: BOS_Up(1) hoặc CHOCH_Up(2)
        if (ev != 1.0 && ev != 2.0)
        {
            Print("[M1 SIGNAL] FAIL — Event ", ev_str, " không phải BOS_Up/CHOCH_Up");
            return false;
        }
        // Cần: BuyZone tồn tại
        if (g_M1.buy_zone_sl == EMPTY_VALUE || g_M1.buy_zone_entry == EMPTY_VALUE)
        {
            Print("[M1 SIGNAL] FAIL — BuyZone không tồn tại (sl=",
                  g_M1.buy_zone_sl    == EMPTY_VALUE ? "EMPTY" : "OK",
                  " entry=", g_M1.buy_zone_entry == EMPTY_VALUE ? "EMPTY" : "OK", ")");
            return false;
        }
        Print("[M1 SIGNAL] PASS BUY — Event=", ev_str,
              " BuyZone[entry=", g_M1.buy_zone_entry, " sl=", g_M1.buy_zone_sl, "]");
    }
    else
    {
        // Cần: BOS_Dn(-1) hoặc CHOCH_Dn(-2)
        if (ev != -1.0 && ev != -2.0)
        {
            Print("[M1 SIGNAL] FAIL — Event ", ev_str, " không phải BOS_Dn/CHOCH_Dn");
            return false;
        }
        // Cần: SellZone tồn tại
        if (g_M1.sell_zone_sl == EMPTY_VALUE || g_M1.sell_zone_entry == EMPTY_VALUE)
        {
            Print("[M1 SIGNAL] FAIL — SellZone không tồn tại (sl=",
                  g_M1.sell_zone_sl    == EMPTY_VALUE ? "EMPTY" : "OK",
                  " entry=", g_M1.sell_zone_entry == EMPTY_VALUE ? "EMPTY" : "OK", ")");
            return false;
        }
        Print("[M1 SIGNAL] PASS SELL — Event=", ev_str,
              " SellZone[sl=", g_M1.sell_zone_sl, " entry=", g_M1.sell_zone_entry, "]");
    }
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: Confluence filter                                         |
//+------------------------------------------------------------------+
bool CheckConfluence(bool is_buy_side)
{
    double M1_ref = CalcRef(g_M1, is_buy_side);
    double H1_ref = CalcRef(g_H1, is_buy_side);
    double M15_ref = CalcRef(g_M15, is_buy_side);

    string side = is_buy_side ? "BUY" : "SELL";
    Print("[CONFLUENCE] ", side, " — Ref values:",
          " M1_ref=",  M1_ref  == EMPTY_VALUE ? "EMPTY" : DoubleToString(M1_ref,  5),
          " H1_ref=",  H1_ref  == EMPTY_VALUE ? "EMPTY" : DoubleToString(H1_ref,  5),
          " M15_ref=", M15_ref == EMPTY_VALUE ? "EMPTY" : DoubleToString(M15_ref, 5));

    // Both HTF refs empty → FAIL
    if (H1_ref == EMPTY_VALUE && M15_ref == EMPTY_VALUE)
    { Print("[CONFLUENCE] FAIL — Both H1_ref and M15_ref are EMPTY"); return false; }

    // Cache ref for order placement
    g_M1_ref = M1_ref;
    g_H1_ref = H1_ref;
    g_M15_ref = M15_ref;

    if (is_buy_side)
    {
        double M1_zone_bot  = g_M1.buy_zone_sl;
        double H1_zone_bot  = g_H1.buy_zone_sl;
        double M15_zone_bot = g_M15.buy_zone_sl;
        Print("[CONFLUENCE] BUY zones: M1_bot=", M1_zone_bot == EMPTY_VALUE ? "EMPTY" : DoubleToString(M1_zone_bot,5),
              " H1_bot=",  H1_zone_bot  == EMPTY_VALUE ? "EMPTY" : DoubleToString(H1_zone_bot,5),
              " M15_bot=", M15_zone_bot == EMPTY_VALUE ? "EMPTY" : DoubleToString(M15_zone_bot,5));

        if (H1_ref == EMPTY_VALUE || H1_zone_bot == EMPTY_VALUE)
            Print("[CONFLUENCE] CHECK H1 — SKIP (H1_ref=", H1_ref==EMPTY_VALUE?"EMPTY":"OK", " H1_zone_bot=", H1_zone_bot==EMPTY_VALUE?"EMPTY":"OK", ")");
        else
        {
            bool cz = (M1_zone_bot >= H1_zone_bot), cr = (M1_ref <= H1_ref);
            Print("[CONFLUENCE] CHECK H1: M1_bot(", M1_zone_bot, ")>=H1_bot(", H1_zone_bot, ")=", cz?"OK":"FAIL",
                  " M1_ref(", M1_ref, ")<=H1_ref(", H1_ref, ")=", cr?"OK":"FAIL");
            if (cz && cr) { Print("[CONFLUENCE] PASS via H1"); return true; }
        }
        if (M15_ref == EMPTY_VALUE || M15_zone_bot == EMPTY_VALUE)
            Print("[CONFLUENCE] CHECK M15 — SKIP (M15_ref=", M15_ref==EMPTY_VALUE?"EMPTY":"OK", " M15_zone_bot=", M15_zone_bot==EMPTY_VALUE?"EMPTY":"OK", ")");
        else
        {
            bool cz = (M1_zone_bot >= M15_zone_bot), cr = (M1_ref <= M15_ref);
            Print("[CONFLUENCE] CHECK M15: M1_bot(", M1_zone_bot, ")>=M15_bot(", M15_zone_bot, ")=", cz?"OK":"FAIL",
                  " M1_ref(", M1_ref, ")<=M15_ref(", M15_ref, ")=", cr?"OK":"FAIL");
            if (cz && cr) { Print("[CONFLUENCE] PASS via M15"); return true; }
        }
    }
    else
    {
        double M1_zone_top  = g_M1.sell_zone_sl;
        double H1_zone_top  = g_H1.sell_zone_sl;
        double M15_zone_top = g_M15.sell_zone_sl;
        Print("[CONFLUENCE] SELL zones: M1_top=", M1_zone_top == EMPTY_VALUE ? "EMPTY" : DoubleToString(M1_zone_top,5),
              " H1_top=",  H1_zone_top  == EMPTY_VALUE ? "EMPTY" : DoubleToString(H1_zone_top,5),
              " M15_top=", M15_zone_top == EMPTY_VALUE ? "EMPTY" : DoubleToString(M15_zone_top,5));

        if (H1_ref == EMPTY_VALUE || H1_zone_top == EMPTY_VALUE)
            Print("[CONFLUENCE] CHECK H1 — SKIP (H1_ref=", H1_ref==EMPTY_VALUE?"EMPTY":"OK", " H1_zone_top=", H1_zone_top==EMPTY_VALUE?"EMPTY":"OK", ")");
        else
        {
            bool cz = (M1_zone_top <= H1_zone_top), cr = (M1_ref >= H1_ref);
            Print("[CONFLUENCE] CHECK H1: M1_top(", M1_zone_top, ")<=H1_top(", H1_zone_top, ")=", cz?"OK":"FAIL",
                  " M1_ref(", M1_ref, ")>=H1_ref(", H1_ref, ")=", cr?"OK":"FAIL");
            if (cz && cr) { Print("[CONFLUENCE] PASS via H1"); return true; }
        }
        if (M15_ref == EMPTY_VALUE || M15_zone_top == EMPTY_VALUE)
            Print("[CONFLUENCE] CHECK M15 — SKIP (M15_ref=", M15_ref==EMPTY_VALUE?"EMPTY":"OK", " M15_zone_top=", M15_zone_top==EMPTY_VALUE?"EMPTY":"OK", ")");
        else
        {
            bool cz = (M1_zone_top <= M15_zone_top), cr = (M1_ref >= M15_ref);
            Print("[CONFLUENCE] CHECK M15: M1_top(", M1_zone_top, ")<=M15_top(", M15_zone_top, ")=", cz?"OK":"FAIL",
                  " M1_ref(", M1_ref, ")>=M15_ref(", M15_ref, ")=", cr?"OK":"FAIL");
            if (cz && cr) { Print("[CONFLUENCE] PASS via M15"); return true; }
        }
    }

    Print("[CONFLUENCE] FAIL — No check passed for ", side);
    return false;
}

//+------------------------------------------------------------------+
//| LOGIC: Place real pending limit order                            |
//+------------------------------------------------------------------+
bool PlaceLimitOrder(bool is_buy_side)
{
    double spread_pts = GetSpreadPoints();
    if (spread_pts > InpMaxSpreadPoints)
    {
        Print("PlaceLimitOrder: Spread too wide (", spread_pts, " pts), skip.");
        return false;
    }

    double entry_price, sl_price, tp_price, sl_dist, lots;
    if (is_buy_side)
    {
        // Entry at BOS/CHOCH level (M1_ref)
        entry_price = NormalizePrice(g_M1_ref);
        // SL below Buy Zone bottom
        sl_price = NormalizePrice(g_M1.buy_zone_sl - spread_pts * _Point);
        sl_dist = entry_price - sl_price;
        if (sl_dist <= 0)
        {
            Print("PlaceLimitOrder BUY: Invalid SL distance.");
            return false;
        }
        tp_price = NormalizePrice(entry_price + InpRR * sl_dist);

        lots = CalcLotsByRiskUSD(sl_dist / _Point, InpRiskUSD);
        if (lots <= 0)
        {
            Print("PlaceLimitOrder BUY: lot calc failed.");
            return false;
        }

        trade.SetExpertMagicNumber(InpMagic);
        trade.SetDeviationInPoints(10);
        if (!trade.BuyLimit(lots, entry_price, _Symbol, sl_price, tp_price, ORDER_TIME_GTC, 0, InpComment))
        {
            Print("PlaceLimitOrder BuyLimit FAILED: ", trade.ResultRetcodeDescription());
            return false;
        }
        g_limit_ticket = trade.ResultOrder();
        g_limit_price = entry_price;
        g_limit_sl = sl_price;
        g_limit_tp = tp_price;
        g_limit_lots = lots;
    }
    else
    {
        // Entry at BOS/CHOCH level (M1_ref)
        entry_price = NormalizePrice(g_M1_ref);
        // SL above Sell Zone top
        sl_price = NormalizePrice(g_M1.sell_zone_sl + spread_pts * _Point);
        sl_dist = sl_price - entry_price;
        if (sl_dist <= 0)
        {
            Print("PlaceLimitOrder SELL: Invalid SL distance.");
            return false;
        }
        tp_price = NormalizePrice(entry_price - InpRR * sl_dist);

        lots = CalcLotsByRiskUSD(sl_dist / _Point, InpRiskUSD);
        if (lots <= 0)
        {
            Print("PlaceLimitOrder SELL: lot calc failed.");
            return false;
        }

        trade.SetExpertMagicNumber(InpMagic);
        trade.SetDeviationInPoints(10);
        if (!trade.SellLimit(lots, entry_price, _Symbol, sl_price, tp_price, ORDER_TIME_GTC, 0, InpComment))
        {
            Print("PlaceLimitOrder SellLimit FAILED: ", trade.ResultRetcodeDescription());
            return false;
        }
        g_limit_ticket = trade.ResultOrder();
        g_limit_price = entry_price;
        g_limit_sl = sl_price;
        g_limit_tp = tp_price;
        g_limit_lots = lots;
    }

    g_confirmed = true;
    g_limit_active = true;
    g_zone_used = true;
    g_is_buy_side = is_buy_side;
    g_be_done = false;

    Print("PlaceLimitOrder ", is_buy_side ? "BUY" : "SELL",
          " ticket=", g_limit_ticket,
          " entry=", entry_price,
          " SL=", sl_price,
          " TP=", tp_price,
          " lots=", lots);
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: Cancel pending limit order by ticket                      |
//+------------------------------------------------------------------+
bool CancelLimitOrder()
{
    if (g_limit_ticket == 0)
        return true;
    if (OrderSelect(g_limit_ticket))
    {
        if (trade.OrderDelete(g_limit_ticket))
        {
            Print("CancelLimitOrder: deleted ticket=", g_limit_ticket);
            g_limit_ticket = 0;
            return true;
        }
        else
        {
            Print("CancelLimitOrder FAILED: ", trade.ResultRetcodeDescription());
            return false;
        }
    }
    // Order no longer exists
    g_limit_ticket = 0;
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: Check if limit order is still pending                     |
//+------------------------------------------------------------------+
bool IsLimitPending()
{
    if (g_limit_ticket == 0)
        return false;
    return OrderSelect(g_limit_ticket);
}

//+------------------------------------------------------------------+
//| LOGIC: Check if position opened from our limit is active        |
//+------------------------------------------------------------------+
bool IsPositionOpen()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (posInfo.SelectByIndex(i))
        {
            if (posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| LOGIC: Get open position ticket (our EA)                         |
//+------------------------------------------------------------------+
ulong GetOpenPositionTicket()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (posInfo.SelectByIndex(i))
        {
            if (posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
                return posInfo.Ticket();
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| LOGIC: 5-conditions Buy Now (execute market order now)           |
//+------------------------------------------------------------------+
bool CheckBuyNow5Conditions()
{
    string ev_str;
    double ev = g_M1.major_event;
    if      (ev ==  1.0) ev_str = "BOS_Up(+1)";
    else if (ev ==  2.0) ev_str = "CHOCH_Up(+2)";
    else if (ev == -1.0) ev_str = "BOS_Dn(-1)";
    else if (ev == -2.0) ev_str = "CHOCH_Dn(-2)";
    else                 ev_str = StringFormat("NONE(%.0f)", ev);
    int h1t = (int)g_H1.major_trend;
    Print("[5COND BUY] C1_confirmed=",   g_confirmed    ? "OK" : "FAIL",
          " C2_limit_active=",            g_limit_active ? "OK" : "FAIL",
          " C3_M1_event=", ev_str, "(need BOS_Up+1)",
          " C4_BuyZone_sl=", g_M1.buy_zone_sl == EMPTY_VALUE ? "EMPTY=FAIL" : DoubleToString(g_M1.buy_zone_sl,5)+"=OK",
          " C5_H1_trend=", h1t, "(need +1)=", h1t==1?"OK":"FAIL",
          " ticket=", g_limit_ticket);
    if (!g_confirmed)             { Print("[5COND BUY] FAIL C1: confirmed=false");    return false; }
    if (!g_limit_active)          { Print("[5COND BUY] FAIL C2: limit_active=false"); return false; }
    if (ev != 1.0)                { Print("[5COND BUY] FAIL C3: Event=", ev_str);     return false; }
    if (g_M1.buy_zone_sl == EMPTY_VALUE) { Print("[5COND BUY] FAIL C4: BuyZone SL=EMPTY"); return false; }
    if (h1t != 1)                 { Print("[5COND BUY] FAIL C5: H1_trend=", h1t);     return false; }
    Print("[5COND BUY] ALL 5 PASSED => Execute BUY NOW");
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: 5-conditions Sell Now (execute market order now)          |
//+------------------------------------------------------------------+
bool CheckSellNow5Conditions()
{
    string ev_str;
    double ev = g_M1.major_event;
    if      (ev ==  1.0) ev_str = "BOS_Up(+1)";
    else if (ev ==  2.0) ev_str = "CHOCH_Up(+2)";
    else if (ev == -1.0) ev_str = "BOS_Dn(-1)";
    else if (ev == -2.0) ev_str = "CHOCH_Dn(-2)";
    else                 ev_str = StringFormat("NONE(%.0f)", ev);
    int h1t = (int)g_H1.major_trend;
    Print("[5COND SELL] C1_confirmed=",  g_confirmed    ? "OK" : "FAIL",
          " C2_limit_active=",           g_limit_active ? "OK" : "FAIL",
          " C3_M1_event=", ev_str, "(need BOS_Dn-1)",
          " C4_SellZone_sl=", g_M1.sell_zone_sl == EMPTY_VALUE ? "EMPTY=FAIL" : DoubleToString(g_M1.sell_zone_sl,5)+"=OK",
          " C5_H1_trend=", h1t, "(need -1)=", h1t==-1?"OK":"FAIL",
          " ticket=", g_limit_ticket);
    if (!g_confirmed)              { Print("[5COND SELL] FAIL C1: confirmed=false");    return false; }
    if (!g_limit_active)           { Print("[5COND SELL] FAIL C2: limit_active=false"); return false; }
    if (ev != -1.0)                { Print("[5COND SELL] FAIL C3: Event=", ev_str);     return false; }
    if (g_M1.sell_zone_sl == EMPTY_VALUE) { Print("[5COND SELL] FAIL C4: SellZone SL=EMPTY"); return false; }
    if (h1t != -1)                 { Print("[5COND SELL] FAIL C5: H1_trend=", h1t);     return false; }
    Print("[5COND SELL] ALL 5 PASSED => Execute SELL NOW");
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: Execute market order NOW and cancel pending limit         |
//+------------------------------------------------------------------+
bool ExecuteNowAndCancelLimit(bool is_buy_side)
{
    double spread_pts = GetSpreadPoints();
    if (spread_pts > InpMaxSpreadPoints)
    {
        Print("ExecuteNow: Spread too wide, skip.");
        return false;
    }

    // Cancel existing limit first
    CancelLimitOrder();

    double entry_price, sl_price, sl_dist, tp_price;

    if (is_buy_side)
    {
        entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sl_price = NormalizePrice(g_M1.buy_zone_sl - spread_pts * _Point);
        sl_dist = entry_price - sl_price;
        if (sl_dist <= 0)
            return false;
        tp_price = NormalizePrice(entry_price + InpRR * sl_dist);
        double lots = CalcLotsByRiskUSD(sl_dist / _Point, InpRiskUSD);
        if (lots <= 0)
            return false;

        trade.SetExpertMagicNumber(InpMagic);
        if (!trade.Buy(lots, _Symbol, entry_price, sl_price, tp_price, InpComment))
        {
            Print("ExecuteNow BUY FAILED: ", trade.ResultRetcodeDescription());
            return false;
        }
    }
    else
    {
        entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sl_price = NormalizePrice(g_M1.sell_zone_sl + spread_pts * _Point);
        sl_dist = sl_price - entry_price;
        if (sl_dist <= 0)
            return false;
        tp_price = NormalizePrice(entry_price - InpRR * sl_dist);
        double lots = CalcLotsByRiskUSD(sl_dist / _Point, InpRiskUSD);
        if (lots <= 0)
            return false;

        trade.SetExpertMagicNumber(InpMagic);
        if (!trade.Sell(lots, _Symbol, entry_price, sl_price, tp_price, InpComment))
        {
            Print("ExecuteNow SELL FAILED: ", trade.ResultRetcodeDescription());
            return false;
        }
    }

    Print("ExecuteNow ", is_buy_side ? "BUY" : "SELL", " OK @ ", entry_price);
    g_limit_active = false; // limit cancelled, position now managed
    return true;
}

//+------------------------------------------------------------------+
//| LOGIC: Reset all trade state                                     |
//+------------------------------------------------------------------+
void ResetTradeState()
{
    Print("[RESET] ResetTradeState — was BuySide=", g_is_buy_side?"Y":"N",
          " confirmed=", g_confirmed?"Y":"N",
          " limit_active=", g_limit_active?"Y":"N",
          " ticket=", g_limit_ticket);
    g_confirmed    = false;
    g_limit_active = false;
    g_zone_used    = false;
    g_is_buy_side  = false;
    g_limit_ticket = 0;
    g_limit_price  = 0;
    g_limit_sl     = 0;
    g_limit_tp     = 0;
    g_limit_lots   = 0;
    g_M1_ref       = EMPTY_VALUE;
    g_H1_ref       = EMPTY_VALUE;
    g_M15_ref      = EMPTY_VALUE;
    g_be_done      = false;
}

//+------------------------------------------------------------------+
//| LOGIC: Session DD gate check                                     |
//+------------------------------------------------------------------+
bool IsSessionDDHit()
{
    if (!InpUseSessionDD)
        return false;
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dd = g_session_start_balance - current_balance;
    if (dd >= InpMaxSessionDD_USD)
    {
        if (!g_session_dd_hit)
        {
            Print("Session DD hit! DD=", dd, " USD, stopping for session.");
            g_session_dd_hit = true;
        }
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| LOGIC: Manage pending limit every tick                           |
//+------------------------------------------------------------------+
void ManagePendingLimit()
{
    if (!g_limit_active)
        return;

    // Check if position is now open (limit got filled)
    if (IsPositionOpen())
    {
        // limit_active stays true so we know a trade is running
        return;
    }

    // Limit still pending
    if (!IsLimitPending())
    {
        // Order no longer exists but no position → was cancelled externally
        Print("Limit order no longer exists. Resetting state.");
        ResetTradeState();
        return;
    }

    // Check: price reached TP level before fill → cancel limit
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (g_is_buy_side)
    {
        // If current price already at or above TP → limit won't fill normally, cancel
        if (bid >= g_limit_tp)
        {
            Print("Price at TP level before fill (BUY). Cancelling limit.");
            CancelLimitOrder();
            ResetTradeState();
            return;
        }
    }
    else
    {
        if (ask <= g_limit_tp)
        {
            Print("Price at TP level before fill (SELL). Cancelling limit.");
            CancelLimitOrder();
            ResetTradeState();
            return;
        }
    }

    // Check 5-conditions for Now execution (on new M1 bar only — called from OnTick flow)
}

//+------------------------------------------------------------------+
//| CHART COMMENT                                                    |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
    string sep = " | ";
    string h1t = StringFormat("H1 Trend=%d", (int)g_H1.major_trend);
    string m15t = StringFormat("M15 Trend=%d", (int)g_M15.major_trend);
    string m1t = StringFormat("M1 Trend=%d", (int)g_M1.major_trend);
    string m1ev = StringFormat("M1 Event=%.0f", g_M1.major_event);
    string st = StringFormat("Confirmed=%s LimitActive=%s ZoneUsed=%s BuySide=%s",
                             g_confirmed ? "Y" : "N",
                             g_limit_active ? "Y" : "N",
                             g_zone_used ? "Y" : "N",
                             g_is_buy_side ? "Y" : "N");
    string dd_s = StringFormat("SessionDD=%s", g_session_dd_hit ? "HIT" : "OK");
    string ref_s = StringFormat("M1_ref=%.5f H1_ref=%.5f M15_ref=%.5f",
                                g_M1_ref == EMPTY_VALUE ? 0 : g_M1_ref,
                                g_H1_ref == EMPTY_VALUE ? 0 : g_H1_ref,
                                g_M15_ref == EMPTY_VALUE ? 0 : g_M15_ref);

    Comment("TLS_SMC_EA v1.00\n", h1t, sep, m15t, sep, m1t, "\n",
            m1ev, "\n", st, "\n", ref_s, "\n", dd_s);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    if (!InitIndicatorHandles())
        return INIT_FAILED;

    g_session_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_session_dd_hit = false;

    ResetTradeState();

    Print("TLS_SMC_EA initialized. Magic=", InpMagic, " Symbol=", _Symbol);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Note: handles from ChartIndicatorGet are owned by the chart, not released here
    // IndicatorRelease would detach the indicator from the chart — do not call it
    Comment("");
    Print("TLS_SMC_EA deinitialized. Reason=", reason);
}

//+------------------------------------------------------------------+
//| OnTick — main logic                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // ---- Session DD gate ----
    static bool first_tick = true;
    if (first_tick)
    {
        first_tick = false;
        Print("[TICK1] balance=", AccountInfoDouble(ACCOUNT_BALANCE),
              " session_start_bal=", g_session_start_balance,
              " dd_limit=", InpMaxSessionDD_USD,
              " dd_hit=", g_session_dd_hit?"Y":"N",
              " UseDD=", InpUseSessionDD?"Y":"N");
    }
    if (IsSessionDDHit())
    {
        UpdateChartComment();
        return;
    }

    // ---- Read buffers on every tick (shift=1 = last confirmed bar) ----
    if (!ReadBuffers(h_H1, 1, g_H1))
        return;
    if (!ReadBuffers(h_M15, 1, g_M15))
        return;
    if (!ReadBuffers(h_M1, 1, g_M1))
        return;

    // ---- Position running: just manage BE ----
    if (IsPositionOpen())
    {
        UpdateChartComment();
        return;
    }

    // ---- Position closed or never opened — check if limit was filled but closed ----
    if (g_limit_active && !IsLimitPending() && !IsPositionOpen())
    {
        // Trade finished (SL or TP hit) — reset
        ResetTradeState();
    }

    // ---- Manage pending limit (cancel checks) ----
    if (g_limit_active && IsLimitPending())
    {
        ManagePendingLimit();

        // Check 5-conditions NOW on new M1 bar only
        if (IsNewBar(PERIOD_M1, g_last_bar_M1))
        {
            // Re-read M1 after new bar
            if (!ReadBuffers(h_M1, 1, g_M1))
            {
                UpdateChartComment();
                return;
            }

            if (g_is_buy_side && CheckBuyNow5Conditions())
            {
                Print("5-condition BUY NOW triggered.");
                ExecuteNowAndCancelLimit(true);
            }
            else if (!g_is_buy_side && CheckSellNow5Conditions())
            {
                Print("5-condition SELL NOW triggered.");
                ExecuteNowAndCancelLimit(false);
            }
        }
        UpdateChartComment();
        return;
    }

    // ---- No active trade or pending — look for new signals ----
    // Process only on new M1 bar
    if (!IsNewBar(PERIOD_M1, g_last_bar_M1))
    {
        UpdateChartComment();
        return;
    }

    // Re-read all buffers fresh on new bar
    if (!ReadBuffers(h_H1, 1, g_H1))
    {
        UpdateChartComment();
        return;
    }
    if (!ReadBuffers(h_M15, 1, g_M15))
    {
        UpdateChartComment();
        return;
    }
    if (!ReadBuffers(h_M1, 1, g_M1))
    {
        UpdateChartComment();
        return;
    }

    // --- DEBUG: log buffer snapshot on every new M1 bar ---
    LogTFData("H1 ", g_H1);
    LogTFData("M15", g_M15);
    LogTFData("M1 ", g_M1);

    int h1_trend = CheckH1Trend();
    if (h1_trend == 0)
    {
        UpdateChartComment();
        return;
    }

    bool looking_buy = (h1_trend == 1);
    bool looking_sell = (h1_trend == -1);

    // ---- BUY SIDE ----
    if (looking_buy)
    {
        // Detect signal: M1 has BOS Up or CHOCH Up + Buy Zone
        if (DetectM1Signal(true))
        {
            if (CheckConfluence(true))
            {
                Print("BUY signal confirmed. Placing Buy Limit...");
                PlaceLimitOrder(true);
            }
            else
            {
                Print("BUY signal FAILED confluence. Skip.");
            }
        }
    }

    // ---- SELL SIDE ----
    else if (looking_sell)
    {
        // Detect signal: M1 has BOS Dn or CHOCH Dn + Sell Zone
        if (DetectM1Signal(false))
        {
            if (CheckConfluence(false))
            {
                Print("SELL signal confirmed. Placing Sell Limit...");
                PlaceLimitOrder(false);
            }
            else
            {
                Print("SELL signal FAILED confluence. Skip.");
            }
        }
    }

    UpdateChartComment();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction — detect TP/SL close                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    // Detect position closed
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if (trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
        {
            ulong deal_ticket = trans.deal;
            if (HistoryDealSelect(deal_ticket))
            {
                long reason = HistoryDealGetInteger(deal_ticket, DEAL_REASON);
                long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);

                if (magic == InpMagic && entry == DEAL_ENTRY_OUT)
                {
                    double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                    string reason_str = (reason == DEAL_REASON_SL) ? "SL" : (reason == DEAL_REASON_TP) ? "TP"
                                                                                                       : "Manual";

                    Print("Trade closed by ", reason_str, ". Profit=", profit);
                    ResetTradeState();
                }
            }
        }
    }
}
//+------------------------------------------------------------------+