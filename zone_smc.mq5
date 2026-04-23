//+------------------------------------------------------------------+
//|                              TradingZone_SMC_Zone_OB             |
//|           Converted 1:1 from Pine Script v6 (TradingView)        |
//|           Logic: SMC BOS/CHOCH + OB + SD Zone + HA Filter        |
//|           Buffers: EA-readable, no logic added/removed           |
//+------------------------------------------------------------------+
#property copyright "Converted from PineScript by TradingZone"
#property version   "1.00"
#property indicator_chart_window

// -----------------------------------------------------------------------
// BUFFER COUNT:
//  0  = HAOpen          (HA candles)
//  1  = HAHigh
//  2  = HALow
//  3  = HAClose
//  4  = HAColor         (color index: 0=bull, 1=bear)
//  5  = MajorTrend      (+1 / 0 / -1)
//  6  = MajorEventBuf   (+1=BOS up, -1=BOS dn, +2=CHOCH up, -2=CHOCH dn)
//  7  = MajProt_High    (protected high level)
//  8  = MajProt_Low     (protected low level)
//  9  = BuyZoneEntry    (buy zone entry = top)
//  10 = BuyZoneSL       (buy zone SL   = bottom)
//  11 = SellZoneEntry   (sell zone entry = bottom)
//  12 = SellZoneSL      (sell zone SL   = top)
//  13 = OB_BullTop      (latest live bull OB top)
//  14 = OB_BullBot      (latest live bull OB bottom)
//  15 = OB_BearTop      (latest live bear OB top)
//  16 = OB_BearBot      (latest live bear OB bottom)
// -----------------------------------------------------------------------

#property indicator_buffers 17
#property indicator_plots   5

// Plot 0-3: Heiken Ashi candles
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  C'8,153,129', C'242,54,69'
#property indicator_label1  "HA Open;HA High;HA Low;HA Close"

// Plot 4: Major trend (hidden, EA reads only)
#property indicator_type2   DRAW_NONE
#property indicator_label2  "Major Trend"

// Plot 5: Major Event (hidden)
#property indicator_type3   DRAW_NONE
#property indicator_label3  "Major Event"

// Plot 6-7: Protected levels (hidden)
#property indicator_type4   DRAW_NONE
#property indicator_label4  "Maj Prot High"

#property indicator_type5   DRAW_NONE
#property indicator_label5  "Maj Prot Low"

// ============================================================
// INPUTS
// ============================================================
input group "--- Major Swing Settings ---"
input color c_SwingHigh     = C'0,180,0';      // Swing High Color
input color c_SwingLow      = clrRed;           // Swing Low Color
input int   p_MajSwing      = 9;                // Periods In Major Swing
input bool  filter_fractals = true;             // Filter H/L Pivots (Zigzag)

input group "--- Structure Tracking Graphics ---"
input bool  ShowTrackingLines = true;
input color c_TrackingLine    = clrFuchsia;

input group "--- Structure Settings (BOS/CHOCH) ---"
input color c_BOS_Up   = C'30,144,255';        // BOS Up Color
input color c_BOS_Dn   = clrRed;               // BOS Down Color
input color c_KeyLevel = clrOrange;             // Key Level Color

input group "--- SD Zone Settings ---"
input bool  ShowZone   = true;
input int   MaxZones   = 1;
input color c_BuyZone  = C'190,235,210';
input color c_SellZone = C'255,200,200';

input group "--- Valid Order Block Settings ---"
input bool  EnableOB   = true;
input color c_BuyOB    = C'255,250,205';
input color c_SellOB   = C'255,250,205';

input group "--- Heiken Ashi Settings ---"
input bool  ShowHA     = true;
input color c_ha_bull  = C'8,153,129';
input color c_ha_bear  = C'242,54,69';

input group "--- Minor Swing Settings ---"
input bool  ShowMinor  = true;
input int   p_MinSwing = 5;

// ============================================================
// INDICATOR BUFFERS
// ============================================================
double HAOpen_Buf[], HAHigh_Buf[], HALow_Buf[], HAClose_Buf[], HAColor_Buf[];
double MajTrend_Buf[];
double MajEvent_Buf[];
double MajProtH_Buf[], MajProtL_Buf[];
double BuyZoneEntry_Buf[], BuyZoneSL_Buf[];
double SellZoneEntry_Buf[], SellZoneSL_Buf[];
double OB_BullTop_Buf[], OB_BullBot_Buf[];
double OB_BearTop_Buf[], OB_BearBot_Buf[];

// ============================================================
// STRUCTS
// ============================================================
struct SActiveOB
{
    string  name;       // object prefix for this OB
    double  top;
    double  bottom;
    double  imb_top;
    double  imb_bot;
    bool    has_imb;
    bool    isBull;
    int     bar_idx;    // absolute bar index at creation (0=oldest, rates_total-1=newest)
    datetime bar_time;
};

struct SSDZone
{
    string  name;
    double  entry;  // top for buy, bottom for sell
    double  sl;     // bottom for buy, top for sell
    bool    isSell;
    datetime tStart;
};

// ============================================================
// GLOBAL STATE VARIABLES
// ============================================================

// --- HA ---
double g_ha_open_prev  = EMPTY_VALUE;
double g_ha_close_prev = EMPTY_VALUE;

// --- OB engine ---
SActiveOB liveOBs[];
int g_liveOB_count = 0;

int   major_trend       = 0;
double act_maj_h_price  = EMPTY_VALUE;  int act_maj_h_idx = -1; bool act_maj_h_active = false;
double act_maj_l_price  = EMPTY_VALUE;  int act_maj_l_idx = -1; bool act_maj_l_active = false;
double maj_prot_h       = EMPTY_VALUE;  int maj_prot_h_idx = -1;
double maj_prot_l       = EMPTY_VALUE;  int maj_prot_l_idx = -1;
double maj_ext_h        = EMPTY_VALUE;  int maj_ext_h_idx = -1;
double maj_ext_l        = EMPTY_VALUE;  int maj_ext_l_idx = -1;
double last_maj_h       = EMPTY_VALUE;  int last_maj_h_idx = -1;
double last_maj_l       = EMPTY_VALUE;  int last_maj_l_idx = -1;
bool   pending_purge    = false;

// Pivot filter state (Zigzag)
double max_high_state = EMPTY_VALUE;
double min_low_state  = EMPTY_VALUE;

// Active struct lines/labels tracking (for smart cleanup)
string struct_line_names[];
int    struct_line_x1s[];  // x1 idx for smart deletion
int    g_struct_count = 0;

string active_kl_up_name = "";
string active_kl_dn_name = "";

// --- Zone engine (array-based, mirrors Pine z_a_* arrays) ---
// We store a rolling history buffer indexed [0]=newest
double z_a_h[];    // high
double z_a_l[];    // low
datetime z_a_t[];  // bar time
double z_a_ha_o[]; // ha open
double z_a_ha_h[]; // ha high
double z_a_ha_l[]; // ha low
double z_a_ha_c[]; // ha close
double z_a_maj_h[];// swing high marker (or EMPTY_VALUE)
double z_a_maj_l[];// swing low marker  (or EMPTY_VALUE)
int    z_arr_size = 0;
int    Z_MAX_SIZE = 2000;

double z_ActiveHigh_price = EMPTY_VALUE; int z_ActiveHigh_time = 0; bool z_ActiveHigh_isActive = false;
double z_ActiveLow_price  = EMPTY_VALUE; int z_ActiveLow_time  = 0; bool z_ActiveLow_isActive  = false;
int    z_major_trend = 0;
double z_maj_prot_h  = EMPTY_VALUE; int z_maj_prot_h_time = 0;
double z_maj_prot_l  = EMPTY_VALUE; int z_maj_prot_l_time = 0;
double z_maj_ext_h   = EMPTY_VALUE; int z_maj_ext_h_time  = 0;
double z_maj_ext_l   = EMPTY_VALUE; int z_maj_ext_l_time  = 0;
double z_last_maj_h  = EMPTY_VALUE; int z_last_maj_h_time = 0;
double z_last_maj_l  = EMPTY_VALUE; int z_last_maj_l_time = 0;
int    z_last_processed_high_time = 0;
int    z_last_processed_low_time  = 0;
int    z_last_break_dir  = 0;
int    z_last_break_type = 0;
int    z_latest_break_up_time = 0; double z_latest_break_up_lvl = EMPTY_VALUE;
int    z_latest_break_dn_time = 0; double z_latest_break_dn_lvl = EMPTY_VALUE;

// --- Zone queues ---
SSDZone buy_zones[];
SSDZone sell_zones[];
int g_buy_zone_count  = 0;
int g_sell_zone_count = 0;

// --- Tracking line names ---
string track_high_name = "IND_TV_TRACK_HIGH";
string track_low_name  = "IND_TV_TRACK_LOW";

// OB export: last live bull/bear OB values (for buffer)
double g_ob_bull_top = EMPTY_VALUE, g_ob_bull_bot = EMPTY_VALUE;
double g_ob_bear_top = EMPTY_VALUE, g_ob_bear_bot = EMPTY_VALUE;

// Unique counter for object names
int g_obj_counter = 0;

// ============================================================
// HELPER: unique name generator
// ============================================================
string UniqueObjName(string prefix)
{
    g_obj_counter++;
    return "IND_TV_" + prefix + "_" + IntegerToString(g_obj_counter);
}

// ============================================================
// HELPER: pivot high/low detection (replaces ta.pivothigh/low)
// Checks if bar at [center] is highest/lowest in window [center-period .. center+period]
// Operates on raw series arrays (AsSeries=true)
// Returns price if pivot, else EMPTY_VALUE
// ============================================================
double PivotHigh(const double &h[], int center, int period, int rates_total)
{
    if(center - period < 0 || center + period >= rates_total) return EMPTY_VALUE;
    double c = h[center];
    for(int k = center - period; k <= center + period; k++)
    {
        if(k == center) continue;
        if(h[k] >= c) return EMPTY_VALUE;
    }
    return c;
}

double PivotLow(const double &l[], int center, int period, int rates_total)
{
    if(center - period < 0 || center + period >= rates_total) return EMPTY_VALUE;
    double c = l[center];
    for(int k = center - period; k <= center + period; k++)
    {
        if(k == center) continue;
        if(l[k] <= c) return EMPTY_VALUE;
    }
    return c;
}

// ============================================================
// HELPER: Pivot filter (AnhTuan Zigzag) — mirrors f_pivots_filter
// Pine uses bar-by-bar running state; we pass/update state externally
// Returns filtered ph/pl (EMPTY_VALUE if not a final pivot)
// ============================================================
void PivotFilter(double ph, double pl,
                 double &io_max_high, double &io_min_low,
                 double &out_fph, double &out_fpl)
{
    // last_high = fixnan(ph) → if ph valid use ph, else keep prev
    double last_high = (ph != EMPTY_VALUE) ? ph : io_max_high;
    double max_high  = (pl != EMPTY_VALUE) ? ph  // if pivot low detected, reset max_high to current ph
                     : (io_max_high == EMPTY_VALUE) ? ph : io_max_high;
    if(ph != EMPTY_VALUE) max_high = MathMax(max_high, last_high);
    else if(io_max_high != EMPTY_VALUE) max_high = MathMax(io_max_high, (ph != EMPTY_VALUE ? ph : io_max_high));

    double last_low = (pl != EMPTY_VALUE) ? pl : io_min_low;
    double min_low  = (ph != EMPTY_VALUE) ? pl
                    : (io_min_low == EMPTY_VALUE) ? pl : io_min_low;
    if(pl != EMPTY_VALUE) min_low = MathMin(min_low, last_low);
    else if(io_min_low != EMPTY_VALUE) min_low = MathMin(io_min_low, (pl != EMPTY_VALUE ? pl : io_min_low));

    double cur_max_high = (max_high != EMPTY_VALUE) ? max_high : io_max_high;
    double cur_min_low  = (min_low  != EMPTY_VALUE) ? min_low  : io_min_low;

    out_fph = EMPTY_VALUE;
    out_fpl = EMPTY_VALUE;
    if(ph != EMPTY_VALUE && max_high == ph) out_fph = cur_max_high;
    if(pl != EMPTY_VALUE && min_low  == pl) out_fpl = cur_min_low;

    io_max_high = max_high;
    io_min_low  = min_low;
}

// ============================================================
// ZONE ARRAY: get index by time
// ============================================================
int z_get_index_by_time(int target_t)
{
    for(int i = 0; i < z_arr_size; i++)
        if((int)z_a_t[i] == target_t) return i;
    return -1;
}

// ============================================================
// ZONE ARRAY: unshift (prepend newest bar data)
// ============================================================
void z_arr_unshift(double h, double l, datetime t, double ha_o, double ha_h, double ha_l, double ha_c)
{
    // grow arrays if needed
    if(z_arr_size >= Z_MAX_SIZE)
    {
        // pop last element (oldest)
        z_arr_size = Z_MAX_SIZE - 1;
    }
    // shift everything right by 1
    int new_size = z_arr_size + 1;
    if(ArraySize(z_a_h) < new_size) {
        ArrayResize(z_a_h,    new_size);
        ArrayResize(z_a_l,    new_size);
        ArrayResize(z_a_t,    new_size);
        ArrayResize(z_a_ha_o, new_size);
        ArrayResize(z_a_ha_h, new_size);
        ArrayResize(z_a_ha_l, new_size);
        ArrayResize(z_a_ha_c, new_size);
        ArrayResize(z_a_maj_h,new_size);
        ArrayResize(z_a_maj_l,new_size);
    }
    for(int i = z_arr_size; i > 0; i--)
    {
        z_a_h[i]     = z_a_h[i-1];
        z_a_l[i]     = z_a_l[i-1];
        z_a_t[i]     = z_a_t[i-1];
        z_a_ha_o[i]  = z_a_ha_o[i-1];
        z_a_ha_h[i]  = z_a_ha_h[i-1];
        z_a_ha_l[i]  = z_a_ha_l[i-1];
        z_a_ha_c[i]  = z_a_ha_c[i-1];
        z_a_maj_h[i] = z_a_maj_h[i-1];
        z_a_maj_l[i] = z_a_maj_l[i-1];
    }
    z_a_h[0]     = h;
    z_a_l[0]     = l;
    z_a_t[0]     = (int)t;
    z_a_ha_o[0]  = ha_o;
    z_a_ha_h[0]  = ha_h;
    z_a_ha_l[0]  = ha_l;
    z_a_ha_c[0]  = ha_c;
    z_a_maj_h[0] = EMPTY_VALUE;
    z_a_maj_l[0] = EMPTY_VALUE;
    z_arr_size   = new_size;
}

// ============================================================
// DRAW HELPERS: BOS/CHOCH line + label
// ============================================================
void DrawStructLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width,
                    string lbl_text, color lbl_clr, bool lbl_above)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);

    string lname = name + "_lbl";
    datetime t_mid = t1 + (t2 - t1) / 2;
    if(ObjectFind(0, lname) < 0)
        ObjectCreate(0, lname, OBJ_TEXT, 0, t_mid, p1);
    ObjectSetString(0, lname, OBJPROP_TEXT, lbl_text);
    ObjectSetInteger(0, lname, OBJPROP_COLOR, lbl_clr);
    ObjectSetInteger(0, lname, OBJPROP_FONTSIZE, 7);
    ObjectSetInteger(0, lname, OBJPROP_ANCHOR, lbl_above ? ANCHOR_LOWER : ANCHOR_UPPER);
    ObjectSetInteger(0, lname, OBJPROP_BACK, false);
}

// Key Level ray
void DrawKeyLevelRay(string name, datetime t1, double price, color clr, string lbl_text, bool is_up)
{
    if(ObjectFind(0, name) >= 0) { ObjectDelete(0, name); }
    ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1 + PeriodSeconds() * 100, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);

    string lname = name + "_lbl";
    if(ObjectFind(0, lname) >= 0) ObjectDelete(0, lname);
    ObjectCreate(0, lname, OBJ_TEXT, 0, t1, price);
    ObjectSetString(0, lname, OBJPROP_TEXT, " " + lbl_text);
    ObjectSetInteger(0, lname, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, lname, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lname, OBJPROP_ANCHOR, is_up ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, lname, OBJPROP_BACK, false);
}

// Tracking dotted ray
void DrawTrackingRay(string name, datetime t1, double price, color clr, string lbl_text, bool lbl_above)
{
    if(price == EMPTY_VALUE || t1 == 0) {
        ObjectDelete(0, name);
        ObjectDelete(0, name + "_lbl");
        return;
    }
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    datetime t2 = (datetime)(t1 + PeriodSeconds() * 50);
    ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);

    string lname = name + "_lbl";
    if(ObjectFind(0, lname) >= 0) ObjectDelete(0, lname);
    ObjectCreate(0, lname, OBJ_TEXT, 0, t2, price);
    ObjectSetString(0, lname, OBJPROP_TEXT, lbl_text);
    ObjectSetInteger(0, lname, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, lname, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lname, OBJPROP_ANCHOR, lbl_above ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
    ObjectSetInteger(0, lname, OBJPROP_BACK, false);
}

// Smart delete struct lines older than threshold_idx
void SmartClearStructLines(int threshold_bar_idx)
{
    int new_count = 0;
    for(int i = 0; i < g_struct_count; i++)
    {
        if(struct_line_x1s[i] <= threshold_bar_idx)
        {
            ObjectDelete(0, struct_line_names[i]);
            ObjectDelete(0, struct_line_names[i] + "_lbl");
        }
        else
        {
            if(new_count != i)
            {
                struct_line_names[new_count] = struct_line_names[i];
                struct_line_x1s[new_count]   = struct_line_x1s[i];
            }
            new_count++;
        }
    }
    g_struct_count = new_count;
}

void PushStructLine(string name, int x1_idx)
{
    if(g_struct_count >= ArraySize(struct_line_names))
    {
        ArrayResize(struct_line_names, g_struct_count + 32);
        ArrayResize(struct_line_x1s,   g_struct_count + 32);
    }
    struct_line_names[g_struct_count] = name;
    struct_line_x1s[g_struct_count]   = x1_idx;
    g_struct_count++;
}

// ============================================================
// OB DRAW + MANAGEMENT
// ============================================================
void DrawOB(double top, double bot, bool isBull, datetime t_start, double imb_t, double imb_b, datetime t_end)
{
    if(!EnableOB) return;

    string base = UniqueObjName(isBull ? "OB_BULL" : "OB_BEAR");

    // Main OB box
    string box_name = base + "_box";
    ObjectCreate(0, box_name, OBJ_RECTANGLE, 0, t_start, top, t_end, bot);
    ObjectSetInteger(0, box_name, OBJPROP_COLOR,   isBull ? c_BuyOB : c_SellOB);
    ObjectSetInteger(0, box_name, OBJPROP_FILL,    true);
    ObjectSetInteger(0, box_name, OBJPROP_BACK,    true);
    ObjectSetInteger(0, box_name, OBJPROP_SELECTABLE, false);

    // Label
    string lbl_name = base + "_lbl";
    ObjectCreate(0, lbl_name, OBJ_TEXT, 0, t_end, (top + bot) / 2.0);
    ObjectSetString(0,  lbl_name, OBJPROP_TEXT, isBull ? "Buy OB" : "Sell OB");
    ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, 7);
    ObjectSetInteger(0, lbl_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    ObjectSetInteger(0, lbl_name, OBJPROP_BACK, false);

    bool has_imb = (imb_t > imb_b);
    string imb_line_t_name = "", imb_line_b_name = "", imb_lbl_name = "";

    if(has_imb)
    {
        imb_line_t_name = base + "_imbt";
        imb_line_b_name = base + "_imbb";
        imb_lbl_name    = base + "_imblbl";

        ObjectCreate(0, imb_line_t_name, OBJ_TREND, 0, t_start, imb_t, t_end, imb_t);
        ObjectSetInteger(0, imb_line_t_name, OBJPROP_COLOR, clrGray);
        ObjectSetInteger(0, imb_line_t_name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, imb_line_t_name, OBJPROP_RAY_RIGHT, false);

        ObjectCreate(0, imb_line_b_name, OBJ_TREND, 0, t_start, imb_b, t_end, imb_b);
        ObjectSetInteger(0, imb_line_b_name, OBJPROP_COLOR, clrGray);
        ObjectSetInteger(0, imb_line_b_name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, imb_line_b_name, OBJPROP_RAY_RIGHT, false);

        ObjectCreate(0, imb_lbl_name, OBJ_TEXT, 0, t_start, (imb_t + imb_b) / 2.0);
        ObjectSetString(0,  imb_lbl_name, OBJPROP_TEXT, "Imbalance");
        ObjectSetInteger(0, imb_lbl_name, OBJPROP_COLOR, clrBlack);
        ObjectSetInteger(0, imb_lbl_name, OBJPROP_FONTSIZE, 7);
        ObjectSetInteger(0, imb_lbl_name, OBJPROP_BACK, false);
    }

    // Register in liveOBs
    if(g_liveOB_count >= ArraySize(liveOBs)) ArrayResize(liveOBs, g_liveOB_count + 16);
    liveOBs[g_liveOB_count].name        = base;
    liveOBs[g_liveOB_count].top         = top;
    liveOBs[g_liveOB_count].bottom      = bot;
    liveOBs[g_liveOB_count].imb_top     = imb_t;
    liveOBs[g_liveOB_count].imb_bot     = imb_b;
    liveOBs[g_liveOB_count].has_imb     = has_imb;
    liveOBs[g_liveOB_count].isBull      = isBull;
    liveOBs[g_liveOB_count].bar_idx     = (int)t_start; // store as time for comparison
    liveOBs[g_liveOB_count].bar_time    = t_start;
    g_liveOB_count++;
}

void DeleteOBByIndex(int idx)
{
    string base = liveOBs[idx].name;
    ObjectDelete(0, base + "_box");
    ObjectDelete(0, base + "_lbl");
    if(liveOBs[idx].has_imb)
    {
        ObjectDelete(0, base + "_imbt");
        ObjectDelete(0, base + "_imbb");
        ObjectDelete(0, base + "_imblbl");
    }
    // shift
    for(int k = idx; k < g_liveOB_count - 1; k++)
        liveOBs[k] = liveOBs[k+1];
    g_liveOB_count--;
}

// Extend all OB boxes to new right edge
void ExtendOBs(datetime t_end)
{
    for(int i = 0; i < g_liveOB_count; i++)
    {
        string base = liveOBs[i].name;
        ObjectSetInteger(0, base + "_box", OBJPROP_TIME, 1, (long)t_end);
        ObjectSetInteger(0, base + "_lbl", OBJPROP_TIME, 0, (long)t_end);
        if(liveOBs[i].has_imb)
        {
            ObjectSetInteger(0, base + "_imbt",   OBJPROP_TIME, 1, (long)t_end);
            ObjectSetInteger(0, base + "_imbb",   OBJPROP_TIME, 1, (long)t_end);
        }
    }
}

// Purge OBs whose bar_time is before threshold_time (mirrors purge_ob(threshold_idx))
void PurgeOBBefore(datetime threshold_time)
{
    for(int i = g_liveOB_count - 1; i >= 0; i--)
    {
        if(liveOBs[i].bar_time < threshold_time)
            DeleteOBByIndex(i);
    }
}

// ============================================================
// check_single_ob — mirrors Pine check_single_ob(offset, isBull, current_limit_offset)
// In MQL5 series mode: offset=0 is current bar, offset+1 is one bar ago
// We work with raw arrays (AsSeries=true), bar i_now = current bar
// offset is bars back from current
// ============================================================
bool CheckSingleOB(int offset, bool isBull,
                   const double &h[], const double &l[], const double &op[], const double &cl[],
                   int rates_total, int i_now, int current_limit_offset,
                   datetime t_end)
{
    if(!EnableOB) return false;
    // offset+1 and offset-1 must be valid
    if(offset + 1 >= rates_total) return false;
    if(offset - 1 < 0) return false;
    // current_limit_offset in Pine = bars_back_break; here we treat as minimum offset
    if(offset - 1 < current_limit_offset) return false;

    bool found = false;
    if(isBull)
    {
        // Pine: close[offset+1] < open[offset+1]  → bearish candle before
        //       low[offset]   < low[offset+1]     → lower low
        //       high[offset+1] < low[offset-1]    → gap up after (imbalance)
        if(cl[offset+1] < op[offset+1] &&
           l[offset]    < l[offset+1]  &&
           h[offset+1]  < l[offset-1])
        {
            double ob_top = h[offset+1];
            double ob_bot = l[offset];
            double imb_top = l[offset-1];
            double imb_bot = h[offset+1];

            // Check mitigation between offset-1 down to current_limit_offset
            bool mitigated = false;
            for(int m = offset - 1; m >= current_limit_offset; m--)
            {
                if(l[m] <= ob_top) { mitigated = true; break; }
                if(l[m] < imb_top)  imb_top = l[m];
            }
            if(!mitigated)
            {
                // bar_idx in Pine = bar_index - (offset+1)
                datetime t_origin = (datetime)(iBarShift(_Symbol, _Period, t_end, false));
                // Use actual time of the bar at [offset+1] bars back from i_now
                // In AsSeries arrays, index offset+1 corresponds to bar time
                // We'll use time[] passed separately — handled in caller
                DrawOB(ob_top, ob_bot, true, (datetime)0, imb_top, imb_bot, t_end); // t_start filled in caller
                found = true;
            }
        }
    }
    else
    {
        // Pine: close[offset+1] > open[offset+1]   → bullish candle
        //       high[offset]   > high[offset+1]    → higher high
        //       low[offset+1]  > high[offset-1]    → gap down after (imbalance)
        if(cl[offset+1] > op[offset+1] &&
           h[offset]    > h[offset+1]  &&
           l[offset+1]  > h[offset-1])
        {
            double ob_top = h[offset];
            double ob_bot = l[offset+1];
            double imb_top = l[offset+1];
            double imb_bot = h[offset-1];

            bool mitigated = false;
            for(int m = offset - 1; m >= current_limit_offset; m--)
            {
                if(h[m] >= ob_bot) { mitigated = true; break; }
                if(h[m] > imb_bot)  imb_bot = h[m];
            }
            if(!mitigated)
            {
                DrawOB(ob_top, ob_bot, false, (datetime)0, imb_top, imb_bot, t_end);
                found = true;
            }
        }
    }
    return found;
}

// Wrapper for scan_origin_obs — scans from origin to break looking for OBs
void ScanOriginOBs(int origin_abs_idx, int break_abs_idx, bool isBull,
                   const double &h[], const double &l[], const double &op[], const double &cl[],
                   const datetime &t[], int rates_total, datetime t_end)
{
    if(!EnableOB) return;
    if(origin_abs_idx < 0 || origin_abs_idx > break_abs_idx) return;

    // In series-mode arrays: abs_idx 0 = current, rates_total-1 = oldest
    // "origin_abs_idx" here is stored as absolute bar index from oldest=0 convention
    // We need to convert: series_offset = (rates_total - 1) - abs_idx
    int bars_back_origin = (rates_total - 1) - origin_abs_idx;
    int bars_back_break  = (rates_total - 1) - break_abs_idx;

    if(bars_back_origin <= bars_back_break) return; // Pine: bars_back_origin > bars_back_break

    for(int j = bars_back_origin; j >= bars_back_break; j--)
    {
        if(j + 1 < rates_total && j - 1 >= 0)
        {
            // Rebuild DrawOB with correct t_start from t[] array
            if(isBull)
            {
                if(cl[j+1] < op[j+1] && l[j] < l[j+1] && h[j+1] < l[j-1])
                {
                    double ob_top = h[j+1], ob_bot = l[j];
                    double imb_top = l[j-1], imb_bot = h[j+1];
                    bool mitigated = false;
                    for(int m = j - 1; m >= bars_back_break; m--)
                    {
                        if(l[m] <= ob_top) { mitigated = true; break; }
                        if(l[m] < imb_top)  imb_top = l[m];
                    }
                    if(!mitigated) DrawOB(ob_top, ob_bot, true, t[j+1], imb_top, imb_bot, t_end);
                }
            }
            else
            {
                if(cl[j+1] > op[j+1] && h[j] > h[j+1] && l[j+1] > h[j-1])
                {
                    double ob_top = h[j], ob_bot = l[j+1];
                    double imb_top = l[j+1], imb_bot = h[j-1];
                    bool mitigated = false;
                    for(int m = j - 1; m >= bars_back_break; m--)
                    {
                        if(h[m] >= ob_bot) { mitigated = true; break; }
                        if(h[m] > imb_bot)  imb_bot = h[m];
                    }
                    if(!mitigated) DrawOB(ob_top, ob_bot, false, t[j+1], imb_top, imb_bot, t_end);
                }
            }
        }
    }
}

// ============================================================
// SD ZONE: add zone (mirrors z_add_sd_zone)
// ============================================================
void z_add_sd_zone(int swing_idx, int bos_idx, bool isSellZone, double broken_level)
{
    if(!ShowZone) return;
    if(z_arr_size == 0) return;

    int ext_idx = swing_idx;
    double actual_broken_level = broken_level;

    if(bos_idx >= 0 && swing_idx >= bos_idx)
    {
        double extreme_val = isSellZone ? z_a_h[bos_idx] : z_a_l[bos_idx];
        ext_idx = bos_idx;
        int count = swing_idx - bos_idx + 1;
        for(int j = 0; j < count; j++)
        {
            int check_idx = bos_idx + j;
            if(check_idx >= z_arr_size) break;
            if(isSellZone) {
                if(z_a_h[check_idx] >= extreme_val) { extreme_val = z_a_h[check_idx]; ext_idx = check_idx; }
            } else {
                if(z_a_l[check_idx] <= extreme_val) { extreme_val = z_a_l[check_idx]; ext_idx = check_idx; }
            }
        }
    }

    if((actual_broken_level == EMPTY_VALUE || actual_broken_level <= 0) && bos_idx >= 0 && swing_idx > bos_idx)
    {
        int check_count = swing_idx - bos_idx;
        double brk_val = isSellZone ? z_a_l[bos_idx + 1] : z_a_h[bos_idx + 1];
        for(int j = 1; j <= check_count; j++)
        {
            int check_idx = bos_idx + j;
            if(check_idx >= z_arr_size) break;
            if(isSellZone) { if(z_a_l[check_idx] < brk_val) brk_val = z_a_l[check_idx]; }
            else            { if(z_a_h[check_idx] > brk_val) brk_val = z_a_h[check_idx]; }
        }
        actual_broken_level = brk_val;
    }

    // HA color: bull=0 (ha_c >= ha_o), bear=1
    int targetColor = isSellZone ? 0 : 1; // sell: look for bull (0), buy: look for bear (1)
    // Wait — Pine: isSellZone → targetColor=0 means HA bull. Let me re-read:
    // Pine: int targetColor = isSellZone ? 0 : 1
    // Then: (ha_c>=ha_o ? 0 : 1) != targetColor means:
    //   isSellZone=true, targetColor=0 → skip bars where color!=0, i.e., skip bear bars, look for bull
    //   isSellZone=false, targetColor=1 → skip bars where color!=1, i.e., skip bull bars, look for bear
    // Confirmed: sell zone looks for bull HA cluster, buy zone looks for bear HA cluster

    int k = ext_idx;
    double zHigh = z_a_ha_h[ext_idx];
    double zLow  = z_a_ha_l[ext_idx];

    // Walk forward to find target-color candle (within ext_idx+10)
    while(k < z_arr_size)
    {
        int cur_color = (z_a_ha_c[k] >= z_a_ha_o[k]) ? 0 : 1;
        if(cur_color == targetColor) break;
        k++;
        if(k > ext_idx + 10) break;
    }

    if(k <= ext_idx + 10 && k < z_arr_size)
    {
        if(isSellZone)
        {
            zLow = z_a_ha_l[k];
            while(k < z_arr_size)
            {
                int cc = (z_a_ha_c[k] >= z_a_ha_o[k]) ? 0 : 1;
                if(cc != targetColor) break;
                if(z_a_ha_l[k] < zLow) zLow = z_a_ha_l[k];
                k++;
            }
            if(z_a_ha_h[ext_idx] > zHigh) zHigh = z_a_ha_h[ext_idx];
        }
        else
        {
            zHigh = z_a_ha_h[k];
            while(k < z_arr_size)
            {
                int cc = (z_a_ha_c[k] >= z_a_ha_o[k]) ? 0 : 1;
                if(cc != targetColor) break;
                if(z_a_ha_h[k] > zHigh) zHigh = z_a_ha_h[k];
                k++;
            }
            if(z_a_ha_l[ext_idx] < zLow) zLow = z_a_ha_l[ext_idx];
        }
    }

    // Validate vs broken_level
    if(actual_broken_level != EMPTY_VALUE && actual_broken_level > 0)
    {
        if(isSellZone && zLow <= actual_broken_level + _Point) {
            zHigh = z_a_ha_h[ext_idx]; zLow = z_a_ha_l[ext_idx];
        }
        else if(!isSellZone && zHigh >= actual_broken_level - _Point) {
            zHigh = z_a_ha_h[ext_idx]; zLow = z_a_ha_l[ext_idx];
        }
    }

    // Draw rectangle using bar times
    datetime tStart = (datetime)z_a_t[ext_idx];
    datetime tEnd   = tStart + (datetime)(PeriodSeconds() * 10);

    string zname = UniqueObjName(isSellZone ? "ZONE_SELL" : "ZONE_BUY");
    ObjectCreate(0, zname, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
    ObjectSetInteger(0, zname, OBJPROP_COLOR,   isSellZone ? c_SellZone : c_BuyZone);
    ObjectSetInteger(0, zname, OBJPROP_FILL,    true);
    ObjectSetInteger(0, zname, OBJPROP_BACK,    true);
    ObjectSetInteger(0, zname, OBJPROP_SELECTABLE, false);

    if(isSellZone)
    {
        if(g_sell_zone_count >= ArraySize(sell_zones)) ArrayResize(sell_zones, g_sell_zone_count + 8);
        sell_zones[g_sell_zone_count].name   = zname;
        sell_zones[g_sell_zone_count].entry  = zLow;   // entry = bottom for sell
        sell_zones[g_sell_zone_count].sl     = zHigh;  // SL = top
        sell_zones[g_sell_zone_count].isSell = true;
        sell_zones[g_sell_zone_count].tStart = tStart;
        g_sell_zone_count++;
        if(g_sell_zone_count > MaxZones)
        {
            ObjectDelete(0, sell_zones[0].name);
            for(int i = 0; i < g_sell_zone_count - 1; i++) sell_zones[i] = sell_zones[i+1];
            g_sell_zone_count--;
        }
    }
    else
    {
        if(g_buy_zone_count >= ArraySize(buy_zones)) ArrayResize(buy_zones, g_buy_zone_count + 8);
        buy_zones[g_buy_zone_count].name   = zname;
        buy_zones[g_buy_zone_count].entry  = zHigh;  // entry = top for buy
        buy_zones[g_buy_zone_count].sl     = zLow;   // SL = bottom
        buy_zones[g_buy_zone_count].isSell = false;
        buy_zones[g_buy_zone_count].tStart = tStart;
        g_buy_zone_count++;
        if(g_buy_zone_count > MaxZones)
        {
            ObjectDelete(0, buy_zones[0].name);
            for(int i = 0; i < g_buy_zone_count - 1; i++) buy_zones[i] = buy_zones[i+1];
            g_buy_zone_count--;
        }
    }
}

// Clear all buy or sell zones
void z_clear_zones(bool isBuy)
{
    if(isBuy) {
        for(int i = 0; i < g_buy_zone_count; i++) ObjectDelete(0, buy_zones[i].name);
        g_buy_zone_count = 0;
    } else {
        for(int i = 0; i < g_sell_zone_count; i++) ObjectDelete(0, sell_zones[i].name);
        g_sell_zone_count = 0;
    }
}

// ============================================================
// OnInit
// ============================================================
int OnInit()
{
    // HA candles
    SetIndexBuffer(0, HAOpen_Buf,  INDICATOR_DATA);
    SetIndexBuffer(1, HAHigh_Buf,  INDICATOR_DATA);
    SetIndexBuffer(2, HALow_Buf,   INDICATOR_DATA);
    SetIndexBuffer(3, HAClose_Buf, INDICATOR_DATA);
    SetIndexBuffer(4, HAColor_Buf, INDICATOR_COLOR_INDEX);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, c_ha_bull);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, c_ha_bear);
    PlotIndexSetString(0, PLOT_LABEL, "HA Open;HA High;HA Low;HA Close");
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    if(!ShowHA) PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

    // Hidden data buffers
    SetIndexBuffer(5, MajTrend_Buf,    INDICATOR_DATA); PlotIndexSetString(1, PLOT_LABEL, "Major Trend");
    SetIndexBuffer(6, MajEvent_Buf,    INDICATOR_DATA); PlotIndexSetString(2, PLOT_LABEL, "Major Event");
    SetIndexBuffer(7, MajProtH_Buf,    INDICATOR_DATA); PlotIndexSetString(3, PLOT_LABEL, "Maj Prot High");
    SetIndexBuffer(8, MajProtL_Buf,    INDICATOR_DATA); PlotIndexSetString(4, PLOT_LABEL, "Maj Prot Low");
    SetIndexBuffer(9,  BuyZoneEntry_Buf,  INDICATOR_DATA);
    SetIndexBuffer(10, BuyZoneSL_Buf,     INDICATOR_DATA);
    SetIndexBuffer(11, SellZoneEntry_Buf, INDICATOR_DATA);
    SetIndexBuffer(12, SellZoneSL_Buf,    INDICATOR_DATA);
    SetIndexBuffer(13, OB_BullTop_Buf, INDICATOR_DATA);
    SetIndexBuffer(14, OB_BullBot_Buf, INDICATOR_DATA);
    SetIndexBuffer(15, OB_BearTop_Buf, INDICATOR_DATA);
    SetIndexBuffer(16, OB_BearBot_Buf, INDICATOR_DATA);

    for(int p = 1; p <= 4; p++) PlotIndexSetInteger(p, PLOT_DRAW_TYPE, DRAW_NONE);

    for(int b = 5; b <= 16; b++) {
        // secondary buffers not plotted
    }

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    ArrayInitialize(HAOpen_Buf, EMPTY_VALUE);
    ArrayInitialize(HAHigh_Buf, EMPTY_VALUE);
    ArrayInitialize(HALow_Buf,  EMPTY_VALUE);
    ArrayInitialize(HAClose_Buf,EMPTY_VALUE);

    return INIT_SUCCEEDED;
}

// ============================================================
// OnDeinit
// ============================================================
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "IND_TV_");
}

// ============================================================
// OnCalculate
// ============================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
    if(rates_total < p_MajSwing * 2 + 2) return 0;

    // Series mode (index 0 = current bar)
    ArraySetAsSeries(time,  true); ArraySetAsSeries(open,  true);
    ArraySetAsSeries(high,  true); ArraySetAsSeries(low,   true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(HAOpen_Buf,  true); ArraySetAsSeries(HAHigh_Buf,  true);
    ArraySetAsSeries(HALow_Buf,   true); ArraySetAsSeries(HAClose_Buf, true);
    ArraySetAsSeries(HAColor_Buf, true);
    ArraySetAsSeries(MajTrend_Buf, true); ArraySetAsSeries(MajEvent_Buf, true);
    ArraySetAsSeries(MajProtH_Buf, true); ArraySetAsSeries(MajProtL_Buf, true);
    ArraySetAsSeries(BuyZoneEntry_Buf,  true); ArraySetAsSeries(BuyZoneSL_Buf,     true);
    ArraySetAsSeries(SellZoneEntry_Buf, true); ArraySetAsSeries(SellZoneSL_Buf,    true);
    ArraySetAsSeries(OB_BullTop_Buf, true); ArraySetAsSeries(OB_BullBot_Buf, true);
    ArraySetAsSeries(OB_BearTop_Buf, true); ArraySetAsSeries(OB_BearBot_Buf, true);

    // Full recalc on first run
    bool is_full_recalc = (prev_calculated == 0);
    if(is_full_recalc)
    {
        ObjectsDeleteAll(0, "IND_TV_");
        g_ha_open_prev  = EMPTY_VALUE;
        g_ha_close_prev = EMPTY_VALUE;
        g_liveOB_count  = 0;
        g_struct_count  = 0;
        g_buy_zone_count  = 0;
        g_sell_zone_count = 0;
        major_trend = 0;
        act_maj_h_price = EMPTY_VALUE; act_maj_h_idx = -1; act_maj_h_active = false;
        act_maj_l_price = EMPTY_VALUE; act_maj_l_idx = -1; act_maj_l_active = false;
        maj_prot_h = EMPTY_VALUE; maj_prot_h_idx = -1;
        maj_prot_l = EMPTY_VALUE; maj_prot_l_idx = -1;
        maj_ext_h  = EMPTY_VALUE; maj_ext_h_idx  = -1;
        maj_ext_l  = EMPTY_VALUE; maj_ext_l_idx  = -1;
        last_maj_h = EMPTY_VALUE; last_maj_h_idx = -1;
        last_maj_l = EMPTY_VALUE; last_maj_l_idx = -1;
        pending_purge = false;
        max_high_state = EMPTY_VALUE; min_low_state = EMPTY_VALUE;
        active_kl_up_name = ""; active_kl_dn_name = "";
        // Zone engine
        z_arr_size = 0;
        z_ActiveHigh_isActive = false; z_ActiveLow_isActive = false;
        z_major_trend = 0;
        z_maj_prot_h = EMPTY_VALUE; z_maj_prot_l = EMPTY_VALUE;
        z_maj_ext_h  = EMPTY_VALUE; z_maj_ext_l  = EMPTY_VALUE;
        z_last_maj_h = EMPTY_VALUE; z_last_maj_l = EMPTY_VALUE;
        z_last_processed_high_time = 0; z_last_processed_low_time = 0;
        z_last_break_dir = 0; z_last_break_type = 0;
        z_latest_break_up_time = 0; z_latest_break_up_lvl = EMPTY_VALUE;
        z_latest_break_dn_time = 0; z_latest_break_dn_lvl = EMPTY_VALUE;
        ArrayInitialize(MajEvent_Buf, 0);
        g_obj_counter = 0;
    }

    // Determine start bar (process oldest to newest = high index to low index in series)
    int start = rates_total - 1;
    if(!is_full_recalc) start = rates_total - prev_calculated;
    if(start >= rates_total) start = rates_total - 1;

    // We iterate from oldest to newest: i goes from start down to 0
    for(int i = start; i >= 0; i--)
    {
        MajEvent_Buf[i] = 0;

        // --------------------------------------------------------
        // STEP 1: Heiken Ashi
        // --------------------------------------------------------
        double ha_c = (open[i] + high[i] + low[i] + close[i]) / 4.0;
        double ha_o;
        if(g_ha_open_prev == EMPTY_VALUE)
            ha_o = (open[i] + close[i]) / 2.0;
        else
            ha_o = (g_ha_open_prev + g_ha_close_prev) / 2.0;
        double ha_h = MathMax(high[i], MathMax(ha_o, ha_c));
        double ha_l = MathMin(low[i],  MathMin(ha_o, ha_c));

        HAOpen_Buf[i]  = ha_o;
        HAHigh_Buf[i]  = ha_h;
        HALow_Buf[i]   = ha_l;
        HAClose_Buf[i] = ha_c;
        HAColor_Buf[i] = (ha_c >= ha_o) ? 0.0 : 1.0;

        g_ha_open_prev  = ha_o;
        g_ha_close_prev = ha_c;

        // --------------------------------------------------------
        // STEP 2: Pivot detection (mirror ta.pivothigh/low)
        // In series mode: center of pivot window = i + p_MajSwing
        // but when i=0, we'd need future bars → only detect confirmed pivots
        // Confirmed pivot: we check bar at [i + p_MajSwing] (older bar)
        // --------------------------------------------------------
        int pivot_center = i + p_MajSwing;
        double raw_ph = EMPTY_VALUE, raw_pl = EMPTY_VALUE;
        if(pivot_center + p_MajSwing < rates_total && pivot_center - p_MajSwing >= 0)
        {
            raw_ph = PivotHigh(high, pivot_center, p_MajSwing, rates_total);
            raw_pl = PivotLow(low,   pivot_center, p_MajSwing, rates_total);
        }

        // Apply Zigzag filter if enabled
        double final_ph = EMPTY_VALUE, final_pl = EMPTY_VALUE;
        if(filter_fractals)
        {
            double out_fph, out_fpl;
            PivotFilter(raw_ph, raw_pl, max_high_state, min_low_state, out_fph, out_fpl);
            final_ph = out_fph;
            final_pl = out_fpl;
        }
        else
        {
            final_ph = raw_ph;
            final_pl = raw_pl;
        }

        // Absolute bar index for pivot (oldest=0, newest=rates_total-1)
        int abs_pivot_idx = (rates_total - 1) - pivot_center;  // not used directly, use time

        bool isRawHigh = (raw_ph != EMPTY_VALUE);
        bool isRawLow  = (raw_pl != EMPTY_VALUE);

        // --------------------------------------------------------
        // STEP 3: Update Active swings from confirmed pivots
        // (mirrors Pine section 6, top part)
        // --------------------------------------------------------
        if(isRawHigh)
        {
            act_maj_h_price  = raw_ph;
            act_maj_h_idx    = pivot_center; // series index
            act_maj_h_active = true;
            last_maj_h       = raw_ph;
            last_maj_h_idx   = pivot_center;
        }
        if(isRawLow)
        {
            act_maj_l_price  = raw_pl;
            act_maj_l_idx    = pivot_center;
            act_maj_l_active = true;
            last_maj_l       = raw_pl;
            last_maj_l_idx   = pivot_center;
        }

        // --------------------------------------------------------
        // STEP 4: Trend tracking (mirrors Pine section 4)
        // --------------------------------------------------------
        if(major_trend == 1)
        {
            if(maj_ext_h == EMPTY_VALUE || high[i] > maj_ext_h)
            {
                maj_ext_h = high[i]; maj_ext_h_idx = i;
                if(last_maj_l != EMPTY_VALUE && last_maj_l_idx >= i) // last_maj_l_idx <= bar_index in Pine (older or equal)
                {
                    maj_prot_l = last_maj_l; maj_prot_l_idx = last_maj_l_idx;
                }
            }
            if(act_maj_l_active && act_maj_l_idx > i) // act_maj_l_idx < maj_ext_h_idx in Pine (older)
            {
                maj_prot_l = act_maj_l_price; maj_prot_l_idx = act_maj_l_idx;
            }
        }
        else if(major_trend == -1)
        {
            if(maj_ext_l == EMPTY_VALUE || low[i] < maj_ext_l)
            {
                maj_ext_l = low[i]; maj_ext_l_idx = i;
                if(last_maj_h != EMPTY_VALUE && last_maj_h_idx >= i)
                {
                    maj_prot_h = last_maj_h; maj_prot_h_idx = last_maj_h_idx;
                }
            }
            if(act_maj_h_active && act_maj_h_idx > i)
            {
                maj_prot_h = act_maj_h_price; maj_prot_h_idx = act_maj_h_idx;
            }
        }
        else
        {
            if(act_maj_h_active && ha_c > act_maj_h_price)
            {
                major_trend = 1; maj_ext_h = high[i]; maj_ext_h_idx = i;
                maj_prot_l = last_maj_l; maj_prot_l_idx = last_maj_l_idx;
            }
            else if(act_maj_l_active && ha_c < act_maj_l_price)
            {
                major_trend = -1; maj_ext_l = low[i]; maj_ext_l_idx = i;
                maj_prot_h = last_maj_h; maj_prot_h_idx = last_maj_h_idx;
            }
        }

        bool is_maj_choch_up = false, is_maj_choch_dn = false;

        // --------------------------------------------------------
        // STEP 5: CHOCH DOWN
        // --------------------------------------------------------
        if(major_trend == 1 && maj_prot_l != EMPTY_VALUE && ha_c < maj_prot_l)
        {
            // Delete old key level up
            if(active_kl_up_name != "") {
                ObjectDelete(0, active_kl_up_name);
                ObjectDelete(0, active_kl_up_name + "_lbl");
                active_kl_up_name = "";
            }

            // Smart clear struct lines older than prot_low bar
            SmartClearStructLines(maj_prot_l_idx);

            // Draw CHOCH line
            string choch_name = UniqueObjName("CHOCH_DN");
            DrawStructLine(choch_name,
                           time[maj_prot_l_idx], maj_prot_l,
                           time[i],              maj_prot_l,
                           c_BOS_Dn, 2, "ChoCh", c_BOS_Dn, true);
            PushStructLine(choch_name, maj_prot_l_idx);
            MajEvent_Buf[i] = -2;

            // Find actual extreme high between now and prot_low
            double actual_ext_h = maj_ext_h;
            int    actual_ext_idx = maj_ext_h_idx;
            if(maj_prot_l_idx >= i && maj_prot_l_idx < rates_total)
            {
                int count = maj_prot_l_idx - i;
                if(count > 0)
                {
                    actual_ext_h = high[i]; actual_ext_idx = i;
                    for(int k = i; k <= maj_prot_l_idx && k < rates_total; k++)
                    {
                        if(high[k] > actual_ext_h) { actual_ext_h = high[k]; actual_ext_idx = k; }
                    }
                }
            }

            // Draw Key Level Down
            active_kl_dn_name = UniqueObjName("KL_DN");
            DrawKeyLevelRay(active_kl_dn_name, time[actual_ext_idx], actual_ext_h, c_KeyLevel, "Major Key Level Down", false);

            // Scan OBs
            ScanOriginOBs(actual_ext_idx, i, false, high, low, open, close, time, rates_total,
                          time[i] + (datetime)(PeriodSeconds() * 10));

            pending_purge = true;
            if(act_maj_l_idx == maj_prot_l_idx) act_maj_l_active = false;

            major_trend = -1; maj_ext_l = low[i]; maj_ext_l_idx = i;
            maj_prot_h = actual_ext_h; maj_prot_h_idx = actual_ext_idx;
            maj_prot_l = EMPTY_VALUE;  maj_prot_l_idx = -1;
            is_maj_choch_dn = true;
        }

        // --------------------------------------------------------
        // STEP 6: CHOCH UP
        // --------------------------------------------------------
        else if(major_trend == -1 && maj_prot_h != EMPTY_VALUE && ha_c > maj_prot_h)
        {
            if(active_kl_dn_name != "") {
                ObjectDelete(0, active_kl_dn_name);
                ObjectDelete(0, active_kl_dn_name + "_lbl");
                active_kl_dn_name = "";
            }

            SmartClearStructLines(maj_prot_h_idx);

            string choch_name = UniqueObjName("CHOCH_UP");
            DrawStructLine(choch_name,
                           time[maj_prot_h_idx], maj_prot_h,
                           time[i],              maj_prot_h,
                           c_BOS_Up, 2, "ChoCh", c_BOS_Up, false);
            PushStructLine(choch_name, maj_prot_h_idx);
            MajEvent_Buf[i] = 2;

            double actual_ext_l = maj_ext_l;
            int    actual_ext_idx = maj_ext_l_idx;
            if(maj_prot_h_idx >= i && maj_prot_h_idx < rates_total)
            {
                int count = maj_prot_h_idx - i;
                if(count > 0)
                {
                    actual_ext_l = low[i]; actual_ext_idx = i;
                    for(int k = i; k <= maj_prot_h_idx && k < rates_total; k++)
                    {
                        if(low[k] < actual_ext_l) { actual_ext_l = low[k]; actual_ext_idx = k; }
                    }
                }
            }

            active_kl_up_name = UniqueObjName("KL_UP");
            DrawKeyLevelRay(active_kl_up_name, time[actual_ext_idx], actual_ext_l, c_KeyLevel, "Major Key Level Up", true);

            ScanOriginOBs(actual_ext_idx, i, true, high, low, open, close, time, rates_total,
                          time[i] + (datetime)(PeriodSeconds() * 10));

            pending_purge = true;
            if(act_maj_h_idx == maj_prot_h_idx) act_maj_h_active = false;

            major_trend = 1; maj_ext_h = high[i]; maj_ext_h_idx = i;
            maj_prot_l = actual_ext_l; maj_prot_l_idx = actual_ext_idx;
            maj_prot_h = EMPTY_VALUE;  maj_prot_h_idx = -1;
            is_maj_choch_up = true;
        }

        // --------------------------------------------------------
        // STEP 7: BOS UP
        // --------------------------------------------------------
        if(act_maj_h_active && ha_c > act_maj_h_price)
        {
            if(!is_maj_choch_up)
            {
                string bos_name = UniqueObjName("BOS_UP");
                DrawStructLine(bos_name,
                               time[act_maj_h_idx], act_maj_h_price,
                               time[i],             act_maj_h_price,
                               c_BOS_Up, 2, "BOS", c_BOS_Up, false);
                PushStructLine(bos_name, act_maj_h_idx);
                MajEvent_Buf[i] = 1;

                if(pending_purge && last_maj_l_idx >= 0 && last_maj_l_idx < rates_total) {
                    PurgeOBBefore(time[last_maj_l_idx]);
                    pending_purge = false;
                }
                if(last_maj_l_idx >= 0)
                    ScanOriginOBs(last_maj_l_idx, i, true, high, low, open, close, time, rates_total,
                                  time[i] + (datetime)(PeriodSeconds() * 10));
            }
            act_maj_h_active = false;
        }

        // --------------------------------------------------------
        // STEP 8: BOS DOWN
        // --------------------------------------------------------
        if(act_maj_l_active && ha_c < act_maj_l_price)
        {
            if(!is_maj_choch_dn)
            {
                string bos_name = UniqueObjName("BOS_DN");
                DrawStructLine(bos_name,
                               time[act_maj_l_idx], act_maj_l_price,
                               time[i],             act_maj_l_price,
                               c_BOS_Dn, 2, "BOS", c_BOS_Dn, true);
                PushStructLine(bos_name, act_maj_l_idx);
                if(MajEvent_Buf[i] == 0) MajEvent_Buf[i] = -1;

                if(pending_purge && last_maj_h_idx >= 0 && last_maj_h_idx < rates_total) {
                    PurgeOBBefore(time[last_maj_h_idx]);
                    pending_purge = false;
                }
                if(last_maj_h_idx >= 0)
                    ScanOriginOBs(last_maj_h_idx, i, false, high, low, open, close, time, rates_total,
                                  time[i] + (datetime)(PeriodSeconds() * 10));
            }
            act_maj_l_active = false;
        }

        // --------------------------------------------------------
        // STEP 9: OB management at swing confirmation
        // --------------------------------------------------------
        if(EnableOB)
        {
            if(isRawLow && major_trend == 1)
            {
                // check_single_ob(p_MajSwing, true, 0) relative to pivot_center bar
                // pivot_center = i + p_MajSwing in series; we check bar at that center
                // offset in Pine = p_MajSwing bars back from current bar at detection time
                // We map: offset=p_MajSwing means bars[pivot_center+p_MajSwing .. pivot_center-p_MajSwing]
                // Simplified: check 3 bars around pivot_center
                int off = p_MajSwing;
                int cc = pivot_center; // "current" bar when pivot fires in Pine = pivot_center+p_MajSwing? 
                // Pine: check_single_ob called when isRawLow fires → bar_index is the detection bar
                // offset=p_MajSwing bars back from detection = pivot_center bar
                // So offset+1 = pivot_center+1, offset-1 = pivot_center-1
                if(cc + 1 < rates_total && cc - 1 >= 0)
                {
                    if(close[cc+1] < open[cc+1] && low[cc] < low[cc+1] && high[cc+1] < low[cc-1])
                    {
                        double ob_top = high[cc+1], ob_bot = low[cc];
                        double imb_top = low[cc-1], imb_bot = high[cc+1];
                        bool mit = false;
                        for(int m = cc - 1; m >= 0; m--) {
                            if(low[m] <= ob_top) { mit = true; break; }
                            if(low[m] < imb_top) imb_top = low[m];
                        }
                        if(!mit) DrawOB(ob_top, ob_bot, true, time[cc+1], imb_top, imb_bot,
                                        time[i] + (datetime)(PeriodSeconds() * 10));
                    }
                }
            }
            if(isRawHigh && major_trend == -1)
            {
                int cc = pivot_center;
                if(cc + 1 < rates_total && cc - 1 >= 0)
                {
                    if(close[cc+1] > open[cc+1] && high[cc] > high[cc+1] && low[cc+1] > high[cc-1])
                    {
                        double ob_top = high[cc], ob_bot = low[cc+1];
                        double imb_top = low[cc+1], imb_bot = high[cc-1];
                        bool mit = false;
                        for(int m = cc - 1; m >= 0; m--) {
                            if(high[m] >= ob_bot) { mit = true; break; }
                            if(high[m] > imb_bot)  imb_bot = high[m];
                        }
                        if(!mit) DrawOB(ob_top, ob_bot, false, time[cc+1], imb_top, imb_bot,
                                        time[i] + (datetime)(PeriodSeconds() * 10));
                    }
                }
            }
        }

        // --------------------------------------------------------
        // STEP 10: OB mitigation check (live OBs)
        // --------------------------------------------------------
        datetime t_end_extend = time[i] + (datetime)(PeriodSeconds() * 10);
        for(int ob_i = g_liveOB_count - 1; ob_i >= 0; ob_i--)
        {
            SActiveOB ob = liveOBs[ob_i];
            if(ob.isBull)
            {
                if(low[i] <= ob.top) { DeleteOBByIndex(ob_i); continue; }
                // Extend + update imbalance
                string base = ob.name;
                ObjectSetInteger(0, base + "_box", OBJPROP_TIME, 1, (long)t_end_extend);
                ObjectSetInteger(0, base + "_lbl", OBJPROP_TIME, 0, (long)t_end_extend);
                if(ob.has_imb)
                {
                    ObjectSetInteger(0, base + "_imbt", OBJPROP_TIME, 1, (long)t_end_extend);
                    ObjectSetInteger(0, base + "_imbb", OBJPROP_TIME, 1, (long)t_end_extend);
                    if(low[i] < ob.imb_top)
                    {
                        liveOBs[ob_i].imb_top = low[i];
                        if(liveOBs[ob_i].imb_top <= liveOBs[ob_i].imb_bot)
                        {
                            ObjectDelete(0, base + "_imbt"); ObjectDelete(0, base + "_imbb");
                            ObjectDelete(0, base + "_imblbl");
                            liveOBs[ob_i].has_imb = false;
                        }
                        else
                        {
                            ObjectSetDouble(0, base + "_imbt", OBJPROP_PRICE, 0, liveOBs[ob_i].imb_top);
                            ObjectSetDouble(0, base + "_imbt", OBJPROP_PRICE, 1, liveOBs[ob_i].imb_top);
                        }
                    }
                }
            }
            else
            {
                if(high[i] >= ob.bottom) { DeleteOBByIndex(ob_i); continue; }
                string base = ob.name;
                ObjectSetInteger(0, base + "_box", OBJPROP_TIME, 1, (long)t_end_extend);
                ObjectSetInteger(0, base + "_lbl", OBJPROP_TIME, 0, (long)t_end_extend);
                if(ob.has_imb)
                {
                    ObjectSetInteger(0, base + "_imbt", OBJPROP_TIME, 1, (long)t_end_extend);
                    ObjectSetInteger(0, base + "_imbb", OBJPROP_TIME, 1, (long)t_end_extend);
                    if(high[i] > ob.imb_bot)
                    {
                        liveOBs[ob_i].imb_bot = high[i];
                        if(liveOBs[ob_i].imb_bot >= liveOBs[ob_i].imb_top)
                        {
                            ObjectDelete(0, base + "_imbt"); ObjectDelete(0, base + "_imbb");
                            ObjectDelete(0, base + "_imblbl");
                            liveOBs[ob_i].has_imb = false;
                        }
                        else
                        {
                            ObjectSetDouble(0, base + "_imbb", OBJPROP_PRICE, 0, liveOBs[ob_i].imb_bot);
                            ObjectSetDouble(0, base + "_imbb", OBJPROP_PRICE, 1, liveOBs[ob_i].imb_bot);
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------
        // STEP 11: Zone engine (mirrors Pine Section 7 — is_new_bar block)
        // We process this for every confirmed bar (i > 0 = not current forming bar)
        // In Pine: is_new_bar runs on bar open → processes previous closed bar
        // --------------------------------------------------------
        if(i > 0)  // bar i+1 was "previous bar" when new bar i opened
        {
            // Unshift previous bar data into zone arrays
            z_arr_unshift(high[i], low[i], time[i], ha_o, ha_h, ha_l, ha_c);

            // --- Check if pivot[1] exists at z_a_t p_MajSwing slots back ---
            // In Pine: ph[1] / pl[1] means the pivot value at previous bar
            // Previous bar pivot fires when pivot_center = i + p_MajSwing
            // We already have final_ph / final_pl from raw pivot check
            // The "previous bar" pivot: we need pivot at bar i+1 which = raw_ph/pl computed at i+1
            // Since we process in order, the pivot at i+1 was computed in prior iteration
            // → We use a 1-bar delayed pivot: check if raw_ph at previous iteration was valid
            // We track this by checking z_a_maj_h at slot p_MajSwing
            if(raw_ph != EMPTY_VALUE && z_arr_size > p_MajSwing)
            {
                // This pivot fires 1 bar later in Pine due to ph[1]
                // So the zone engine sees this pivot on bar i-1 (next iteration)
                // We record it in the array slot
                if(p_MajSwing < z_arr_size)
                {
                    z_a_maj_h[p_MajSwing] = raw_ph;
                    z_ActiveHigh_price    = raw_ph;
                    z_ActiveHigh_time     = (int)z_a_t[p_MajSwing];
                    z_ActiveHigh_isActive = true;
                    z_last_maj_h         = z_ActiveHigh_price;
                    z_last_maj_h_time    = z_ActiveHigh_time;
                }
            }
            if(raw_pl != EMPTY_VALUE && z_arr_size > p_MajSwing)
            {
                if(p_MajSwing < z_arr_size)
                {
                    z_a_maj_l[p_MajSwing] = raw_pl;
                    z_ActiveLow_price     = raw_pl;
                    z_ActiveLow_time      = (int)z_a_t[p_MajSwing];
                    z_ActiveLow_isActive  = true;
                    z_last_maj_l          = z_ActiveLow_price;
                    z_last_maj_l_time     = z_ActiveLow_time;
                }
            }

            // --- Check if new swing creates a zone retroactively ---
            int sw_idx = p_MajSwing;
            if(sw_idx < z_arr_size)
            {
                if(z_a_maj_h[sw_idx] != EMPTY_VALUE)
                {
                    int sw_time = (int)z_a_t[sw_idx];
                    if(sw_time > z_last_processed_high_time)
                    {
                        z_last_processed_high_time = sw_time;
                        if(z_last_break_dir == -1 && z_last_break_type == 1 && sw_time <= z_latest_break_dn_time)
                        {
                            int b_idx = z_get_index_by_time(z_latest_break_dn_time);
                            if(b_idx != -1) z_add_sd_zone(sw_idx, b_idx, true, z_latest_break_dn_lvl);
                        }
                    }
                }
                if(z_a_maj_l[sw_idx] != EMPTY_VALUE)
                {
                    int sw_time = (int)z_a_t[sw_idx];
                    if(sw_time > z_last_processed_low_time)
                    {
                        z_last_processed_low_time = sw_time;
                        if(z_last_break_dir == 1 && z_last_break_type == 1 && sw_time <= z_latest_break_up_time)
                        {
                            int b_idx = z_get_index_by_time(z_latest_break_up_time);
                            if(b_idx != -1) z_add_sd_zone(sw_idx, b_idx, false, z_latest_break_up_lvl);
                        }
                    }
                }
            }

            // Current bar data in zone array = index 0
            double curr_h   = (z_arr_size > 0) ? z_a_h[0]    : EMPTY_VALUE;
            double curr_l   = (z_arr_size > 0) ? z_a_l[0]    : EMPTY_VALUE;
            double curr_ha_c= (z_arr_size > 0) ? z_a_ha_c[0] : EMPTY_VALUE;
            int    curr_t   = (z_arr_size > 0) ? (int)z_a_t[0]: 0;

            // Zone trend extreme tracking
            if(z_major_trend == 1)
            {
                if(curr_h != EMPTY_VALUE && (z_maj_ext_h == EMPTY_VALUE || curr_h > z_maj_ext_h))
                { z_maj_ext_h = curr_h; z_maj_ext_h_time = curr_t; }
            }
            else if(z_major_trend == -1)
            {
                if(curr_l != EMPTY_VALUE && (z_maj_ext_l == EMPTY_VALUE || curr_l < z_maj_ext_l))
                { z_maj_ext_l = curr_l; z_maj_ext_l_time = curr_t; }
            }
            else
            {
                if(z_ActiveHigh_isActive && curr_ha_c != EMPTY_VALUE && curr_ha_c > z_ActiveHigh_price)
                { z_major_trend = 1; z_maj_ext_h = curr_h; z_maj_ext_h_time = curr_t; z_maj_prot_l = z_last_maj_l; z_maj_prot_l_time = z_last_maj_l_time; }
                else if(z_ActiveLow_isActive && curr_ha_c != EMPTY_VALUE && curr_ha_c < z_ActiveLow_price)
                { z_major_trend = -1; z_maj_ext_l = curr_l; z_maj_ext_l_time = curr_t; z_maj_prot_h = z_last_maj_h; z_maj_prot_h_time = z_last_maj_h_time; }
            }

            // Zone mitigation
            for(int j = g_buy_zone_count - 1; j >= 0; j--)
            {
                if(curr_ha_c != EMPTY_VALUE && curr_ha_c < buy_zones[j].sl)
                { ObjectDelete(0, buy_zones[j].name); for(int k=j; k<g_buy_zone_count-1; k++) buy_zones[k]=buy_zones[k+1]; g_buy_zone_count--; }
            }
            for(int j = g_sell_zone_count - 1; j >= 0; j--)
            {
                if(curr_ha_c != EMPTY_VALUE && curr_ha_c > sell_zones[j].sl)
                { ObjectDelete(0, sell_zones[j].name); for(int k=j; k<g_sell_zone_count-1; k++) sell_zones[k]=sell_zones[k+1]; g_sell_zone_count--; }
            }

            bool z_is_choch_up = false, z_is_choch_dn = false;

            // Zone CHOCH DOWN
            if(z_major_trend == 1 && z_maj_prot_l != EMPTY_VALUE && curr_ha_c != EMPTY_VALUE && curr_ha_c < z_maj_prot_l)
            {
                z_clear_zones(true);
                double actual_ext_h = z_maj_ext_h; int actual_ext_time = z_maj_ext_h_time;
                int prot_idx = z_get_index_by_time(z_maj_prot_l_time);
                if(prot_idx != -1)
                {
                    for(int k = 0; k <= prot_idx; k++)
                    {
                        if(k < z_arr_size && z_a_h[k] > actual_ext_h)
                        { actual_ext_h = z_a_h[k]; actual_ext_time = (int)z_a_t[k]; }
                    }
                }
                z_last_break_dir = -1; z_last_break_type = 2;
                z_latest_break_dn_time = curr_t; z_latest_break_dn_lvl = z_maj_prot_l;

                int zone_anchor_idx = z_get_index_by_time(actual_ext_time);
                if(zone_anchor_idx != -1)
                {
                    for(int k = p_MajSwing; k <= zone_anchor_idx; k++)
                    {
                        if(k < z_arr_size && z_a_maj_h[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                    }
                }
                if(zone_anchor_idx != -1) z_add_sd_zone(zone_anchor_idx, 0, true, z_maj_prot_l);

                z_major_trend = -1; z_maj_ext_l = curr_l; z_maj_ext_l_time = curr_t;
                z_maj_prot_h = actual_ext_h; z_maj_prot_h_time = actual_ext_time;
                z_maj_prot_l = EMPTY_VALUE;  z_maj_prot_l_time = 0;
                z_is_choch_dn = true;
            }
            // Zone CHOCH UP
            else if(z_major_trend == -1 && z_maj_prot_h != EMPTY_VALUE && curr_ha_c != EMPTY_VALUE && curr_ha_c > z_maj_prot_h)
            {
                z_clear_zones(false);
                double actual_ext_l = z_maj_ext_l; int actual_ext_time = z_maj_ext_l_time;
                int prot_idx = z_get_index_by_time(z_maj_prot_h_time);
                if(prot_idx != -1)
                {
                    for(int k = 0; k <= prot_idx; k++)
                    {
                        if(k < z_arr_size && z_a_l[k] < actual_ext_l)
                        { actual_ext_l = z_a_l[k]; actual_ext_time = (int)z_a_t[k]; }
                    }
                }
                z_last_break_dir = 1; z_last_break_type = 2;
                z_latest_break_up_time = curr_t; z_latest_break_up_lvl = z_maj_prot_h;

                int zone_anchor_idx = z_get_index_by_time(actual_ext_time);
                if(zone_anchor_idx != -1)
                {
                    for(int k = p_MajSwing; k <= zone_anchor_idx; k++)
                    {
                        if(k < z_arr_size && z_a_maj_l[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                    }
                }
                if(zone_anchor_idx != -1) z_add_sd_zone(zone_anchor_idx, 0, false, z_maj_prot_h);

                z_major_trend = 1; z_maj_ext_h = curr_h; z_maj_ext_h_time = curr_t;
                z_maj_prot_l = actual_ext_l; z_maj_prot_l_time = actual_ext_time;
                z_maj_prot_h = EMPTY_VALUE;  z_maj_prot_h_time = 0;
                z_is_choch_up = true;
            }

            // Zone BOS UP (with protected low shift)
            if(z_ActiveHigh_isActive && curr_ha_c != EMPTY_VALUE && curr_ha_c > z_ActiveHigh_price)
            {
                if(!z_is_choch_up)
                {
                    z_last_break_dir = 1; z_last_break_type = 1;
                    z_latest_break_up_time = curr_t; z_latest_break_up_lvl = z_ActiveHigh_price;

                    // Find lowest low in pullback from active high to now
                    double pb_l = curr_l; int pb_l_t = curr_t;
                    int lookback_idx = z_get_index_by_time(z_ActiveHigh_time);
                    if(lookback_idx > 0)
                    {
                        for(int k = 0; k <= lookback_idx; k++)
                        {
                            if(k < z_arr_size && z_a_l[k] < pb_l)
                            { pb_l = z_a_l[k]; pb_l_t = (int)z_a_t[k]; }
                        }
                    }
                    z_maj_prot_l = pb_l; z_maj_prot_l_time = pb_l_t;

                    int origin_idx = z_get_index_by_time(z_last_maj_l_time);
                    if(origin_idx != -1) z_add_sd_zone(origin_idx, 0, false, z_ActiveHigh_price);
                }
                z_ActiveHigh_isActive = false;
            }

            // Zone BOS DOWN (with protected high shift)
            if(z_ActiveLow_isActive && curr_ha_c != EMPTY_VALUE && curr_ha_c < z_ActiveLow_price)
            {
                if(!z_is_choch_dn)
                {
                    z_last_break_dir = -1; z_last_break_type = 1;
                    z_latest_break_dn_time = curr_t; z_latest_break_dn_lvl = z_ActiveLow_price;

                    // Find highest high in pullback
                    double pb_h = curr_h; int pb_h_t = curr_t;
                    int lookback_idx = z_get_index_by_time(z_ActiveLow_time);
                    if(lookback_idx > 0)
                    {
                        for(int k = 0; k <= lookback_idx; k++)
                        {
                            if(k < z_arr_size && z_a_h[k] > pb_h)
                            { pb_h = z_a_h[k]; pb_h_t = (int)z_a_t[k]; }
                        }
                    }
                    z_maj_prot_h = pb_h; z_maj_prot_h_time = pb_h_t;

                    int origin_idx = z_get_index_by_time(z_last_maj_h_time);
                    if(origin_idx != -1) z_add_sd_zone(origin_idx, 0, true, z_ActiveLow_price);
                }
                z_ActiveLow_isActive = false;
            }
        } // end i > 0 (zone engine)

        // --------------------------------------------------------
        // STEP 12: Fill output buffers at current bar
        // --------------------------------------------------------
        MajTrend_Buf[i] = major_trend;
        MajProtH_Buf[i] = (maj_prot_h != EMPTY_VALUE) ? maj_prot_h : EMPTY_VALUE;
        MajProtL_Buf[i] = (maj_prot_l != EMPTY_VALUE) ? maj_prot_l : EMPTY_VALUE;

        // Buy zone: most recent
        if(g_buy_zone_count > 0)
        {
            BuyZoneEntry_Buf[i] = buy_zones[g_buy_zone_count - 1].entry;
            BuyZoneSL_Buf[i]    = buy_zones[g_buy_zone_count - 1].sl;
        }
        else { BuyZoneEntry_Buf[i] = EMPTY_VALUE; BuyZoneSL_Buf[i] = EMPTY_VALUE; }

        if(g_sell_zone_count > 0)
        {
            SellZoneEntry_Buf[i] = sell_zones[g_sell_zone_count - 1].entry;
            SellZoneSL_Buf[i]    = sell_zones[g_sell_zone_count - 1].sl;
        }
        else { SellZoneEntry_Buf[i] = EMPTY_VALUE; SellZoneSL_Buf[i] = EMPTY_VALUE; }

        // OB export: find latest live bull/bear OB
        g_ob_bull_top = EMPTY_VALUE; g_ob_bull_bot = EMPTY_VALUE;
        g_ob_bear_top = EMPTY_VALUE; g_ob_bear_bot = EMPTY_VALUE;
        for(int ob_i = g_liveOB_count - 1; ob_i >= 0; ob_i--)
        {
            if(liveOBs[ob_i].isBull && g_ob_bull_top == EMPTY_VALUE)
            { g_ob_bull_top = liveOBs[ob_i].top; g_ob_bull_bot = liveOBs[ob_i].bottom; }
            if(!liveOBs[ob_i].isBull && g_ob_bear_top == EMPTY_VALUE)
            { g_ob_bear_top = liveOBs[ob_i].top; g_ob_bear_bot = liveOBs[ob_i].bottom; }
        }
        OB_BullTop_Buf[i] = g_ob_bull_top; OB_BullBot_Buf[i] = g_ob_bull_bot;
        OB_BearTop_Buf[i] = g_ob_bear_top; OB_BearBot_Buf[i] = g_ob_bear_bot;

        // --------------------------------------------------------
        // STEP 13: Tracking lines (only on bar 0 = current bar)
        // --------------------------------------------------------
        if(i == 0 && ShowTrackingLines)
        {
            double g_high_lvl = EMPTY_VALUE, g_low_lvl = EMPTY_VALUE;
            string g_high_text = "", g_low_text = "";
            datetime g_high_t = 0, g_low_t = 0;

            if(major_trend == 1)
            {
                if(maj_ext_h != EMPTY_VALUE)
                { g_high_lvl = maj_ext_h; g_high_text = "Active High"; g_high_t = (maj_ext_h_idx >= 0 && maj_ext_h_idx < rates_total) ? time[maj_ext_h_idx] : 0; }
                if(maj_prot_l != EMPTY_VALUE)
                { g_low_lvl = maj_prot_l; g_low_text = "Protected Low"; g_low_t = (maj_prot_l_idx >= 0 && maj_prot_l_idx < rates_total) ? time[maj_prot_l_idx] : 0; }
            }
            else if(major_trend == -1)
            {
                if(maj_prot_h != EMPTY_VALUE)
                { g_high_lvl = maj_prot_h; g_high_text = "Protected High"; g_high_t = (maj_prot_h_idx >= 0 && maj_prot_h_idx < rates_total) ? time[maj_prot_h_idx] : 0; }
                if(maj_ext_l != EMPTY_VALUE)
                { g_low_lvl = maj_ext_l; g_low_text = "Active Low"; g_low_t = (maj_ext_l_idx >= 0 && maj_ext_l_idx < rates_total) ? time[maj_ext_l_idx] : 0; }
            }

            DrawTrackingRay(track_high_name, g_high_t, g_high_lvl, c_TrackingLine, g_high_text, false);
            DrawTrackingRay(track_low_name,  g_low_t,  g_low_lvl,  c_TrackingLine, g_low_text,  true);

            // Extend zone boxes to current time
            datetime ext_t = time[0] + (datetime)(PeriodSeconds() * 10);
            for(int j = 0; j < g_buy_zone_count;  j++) ObjectSetInteger(0, buy_zones[j].name,  OBJPROP_TIME, 1, (long)ext_t);
            for(int j = 0; j < g_sell_zone_count; j++) ObjectSetInteger(0, sell_zones[j].name, OBJPROP_TIME, 1, (long)ext_t);
        }

    } // end main loop

    return rates_total;
}
//+------------------------------------------------------------------+