#property copyright "Zone SMC by AnhTuan"
#property version "46.00"
#property indicator_chart_window

#property indicator_buffers 26
#property indicator_plots 18

#property indicator_type1 DRAW_ARROW
#property indicator_type2 DRAW_ARROW
#property indicator_type3 DRAW_LINE
#property indicator_type4 DRAW_COLOR_CANDLES
#property indicator_color1 C '80,80,80'
#property indicator_color2 C '80,80,80'
#property indicator_color4 C '8,153,129', C '242,54,69'

#property indicator_type5 DRAW_ARROW
#property indicator_type6 DRAW_ARROW
#property indicator_color5 C '0,190,190'
#property indicator_color6 C '0,190,190'

#property indicator_type7 DRAW_NONE
#property indicator_type8 DRAW_NONE
#property indicator_type9 DRAW_NONE
#property indicator_type10 DRAW_NONE
#property indicator_type11 DRAW_NONE
#property indicator_type12 DRAW_NONE
#property indicator_type13 DRAW_NONE
#property indicator_type14 DRAW_NONE
#property indicator_type15 DRAW_NONE
#property indicator_type16 DRAW_NONE
#property indicator_type17 DRAW_NONE
#property indicator_type18 DRAW_NONE

input group "--- Major Swing Settings ---" input color MajorSwingColor = C '80,80,80';
input int MajorSwingSize = 5;
input int PeriodsInMajorSwing = 9;

input group "--- Structure Tracking Graphics (RAY) ---" input bool ShowTrackingLines = true;
input color TrackingLineColor = clrMagenta;

input group "--- Strong Level Settings ---" input color StrongHighColor = clrRed;
input color StrongLowColor = clrRed;
input color StrongBuyZoneColor = C '255,153,0';   // Viền Cam cho Strong Buy Zone
input color StrongSellZoneColor = C '255,51,102'; // Viền Tím Đỏ cho Strong Sell Zone

input group "--- Structure Settings (BOS/CHOCH) ---" input int MaxBOSLines = 5;
input color BOS_Up_Color = clrDodgerBlue;
input color BOS_Down_Color = clrRed;
input color KeyLevel_Color = clrOrange;

input group "--- SD Zone Settings ---" input int MaxZones = 1;
input color BuyZoneColor = C '190,235,210';
input color SellZoneColor = C '255,200,200';

input group "--- Minor Swing Settings (Trigger) ---" input bool ShowMinorStructure = true;
input int PeriodsInMinorSwing = 5;
input int MinorSwingSize = 1;
input int MaxMinorBOSLines = 3;
input color Minor_BOS_Up_Color = C '120,220,220';
input color Minor_BOS_Down_Color = C '255,180,180';

input group "--- Moving Average ---" input int MovingAveragePeriods = 21;
input color MovingAvergeColor = C '80,80,80';

input group "--- Heiken Ashi (TV Colors) ---" input color InpBullColor = C '8,153,129';
input color InpBearColor = C '242,54,69';

double majorSwingHigh[], majorSwingLow[], EMA_Buffer[];
double HAOpen[], HAHigh[], HALow[], HAClose[], HAColor[];
double minorSwingHigh[], minorSwingLow[];

double MajorTrendBuffer[], MinorTrendBuffer[];
double MajorEventBuffer[], MinorEventBuffer[];
double MajorProtHighBuffer[], MajorProtLowBuffer[];
double MinorProtHighBuffer[], MinorProtLowBuffer[];
double BuyZoneEntryBuffer[], BuyZoneSLBuffer[];
double SellZoneSLBuffer[], SellZoneEntryBuffer[];
double BOS_Up_Level[];   // buffer 22: carry-forward BOS UP level
double BOS_Dn_Level[];   // buffer 23: carry-forward BOS DN level
double CHOCH_Up_Level[]; // buffer 24: carry-forward CHOCH UP level
double CHOCH_Dn_Level[]; // buffer 25: carry-forward CHOCH DN level

int ma_handle;
int lookBackMajor, lookBackMinor;

struct TSwing
{
    double price;
    datetime time;
    bool isActive;
    int idx;
};
struct TZone
{
    string name;
    double entryPrice;
    double stopPrice;
};

TSwing ActiveHigh = {EMPTY_VALUE, 0, false, -1};
TSwing ActiveLow = {EMPTY_VALUE, 0, false, -1};
TSwing ActiveMinorHigh = {EMPTY_VALUE, 0, false, -1};
TSwing ActiveMinorLow = {EMPTY_VALUE, 0, false, -1};

string BOSUpQueue[];
string BOSDnQueue[];
TZone BuyZonesQueue[];
TZone SellZonesQueue[];
string MinorBOSUpQueue[];
string MinorBOSDnQueue[];

datetime last_processed_high_time = 0;
datetime last_processed_low_time = 0;

int last_break_dir = 0;
int last_break_type = 0;
datetime latest_break_up_time = 0;
int latest_break_up_idx = -1;
double latest_break_up_level = EMPTY_VALUE;
datetime latest_break_down_time = 0;
int latest_break_down_idx = -1;
double latest_break_down_level = EMPTY_VALUE;

int major_trend = 0;
double maj_prot_high = EMPTY_VALUE;
datetime maj_prot_high_time = 0;
int maj_prot_high_idx = -1;
double maj_prot_low = EMPTY_VALUE;
datetime maj_prot_low_time = 0;
int maj_prot_low_idx = -1;
double maj_extreme_high = EMPTY_VALUE;
datetime maj_extreme_high_time = 0;
int maj_extreme_high_idx = -1;
double maj_extreme_low = EMPTY_VALUE;
datetime maj_extreme_low_time = 0;
int maj_extreme_low_idx = -1;
double last_maj_high = EMPTY_VALUE;
datetime last_maj_high_time = 0;
int last_maj_high_idx = -1;
double last_maj_low = EMPTY_VALUE;
datetime last_maj_low_time = 0;
int last_maj_low_idx = -1;

double maj_confirmed_extreme_high = EMPTY_VALUE;
datetime maj_confirmed_extreme_high_time = 0;
double maj_confirmed_extreme_low = EMPTY_VALUE;
datetime maj_confirmed_extreme_low_time = 0;

double maj_strong_high = EMPTY_VALUE;
datetime maj_strong_high_time = 0;
int maj_strong_high_idx = -1;
double maj_strong_low = EMPTY_VALUE;
datetime maj_strong_low_time = 0;
int maj_strong_low_idx = -1;
datetime last_strong_high_update_time = 0;
datetime last_strong_low_update_time = 0;
bool pending_strong_high_update = false;
bool pending_strong_low_update = false;
double pending_weak_high_level = EMPTY_VALUE;
double pending_weak_low_level = EMPTY_VALUE;
datetime processed_weak_high_time = 0;
datetime processed_weak_low_time = 0;

bool pending_prot_high_update = false;
bool pending_prot_low_update = false;
datetime processed_prot_weak_high_time = 0;
datetime processed_prot_weak_low_time = 0;
datetime prot_anchor_time = 0;
int prot_breakout_idx = -1;

int minor_trend = 0;
double min_prot_high = EMPTY_VALUE;
datetime min_prot_high_time = 0;
int min_prot_high_idx = -1;
double min_prot_low = EMPTY_VALUE;
datetime min_prot_low_time = 0;
int min_prot_low_idx = -1;
double min_extreme_high = EMPTY_VALUE;
datetime min_extreme_high_time = 0;
int min_extreme_high_idx = -1;
double min_extreme_low = EMPTY_VALUE;
datetime min_extreme_low_time = 0;
int min_extreme_low_idx = -1;
double last_min_high = EMPTY_VALUE;
datetime last_min_high_time = 0;
int last_min_high_idx = -1;
double last_min_low = EMPTY_VALUE;
datetime last_min_low_time = 0;
int last_min_low_idx = -1;

double g_high_lvl = EMPTY_VALUE;
datetime g_high_time = 0;
string g_high_text = "";
double g_low_lvl = EMPTY_VALUE;
datetime g_low_time = 0;
string g_low_text = "";

bool is_maj_prot_high_sweep = false;
bool is_maj_prot_low_sweep = false;
bool is_min_prot_high_sweep = false;
bool is_min_prot_low_sweep = false;

// =========================================================================
// PATCH v46.01: Carry-forward internal vars — EA reads buffer moi bar
// =========================================================================
double last_bos_up_level = EMPTY_VALUE;
double last_bos_dn_level = EMPTY_VALUE;
double last_choch_up_level = EMPTY_VALUE;
double last_choch_dn_level = EMPTY_VALUE;

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop);
void CreateStrongZone(string name, int ext_idx, bool isSellZone, const datetime &time[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total);
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize);
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown);
void PushBOS(string &queue[], string name, int max_count);
void ClearQueue(string &queue[]);
void ClearZoneQueue(TZone &queue[]);
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count);
void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time);
datetime GetRightEdgeTime(datetime current_time);

int OnInit()
{
    lookBackMajor = PeriodsInMajorSwing * 2;
    lookBackMinor = PeriodsInMinorSwing * 2;
    SetIndexBuffer(0, majorSwingHigh, INDICATOR_DATA);
    PlotIndexSetInteger(0, PLOT_ARROW, 159);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MajorSwingSize);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, MajorSwingColor);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(1, majorSwingLow, INDICATOR_DATA);
    PlotIndexSetInteger(1, PLOT_ARROW, 159);
    PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MajorSwingSize);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, MajorSwingColor);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(2, EMA_Buffer, INDICATOR_DATA);
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, MovingAvergeColor);
    SetIndexBuffer(3, HAOpen, INDICATOR_DATA);
    SetIndexBuffer(4, HAHigh, INDICATOR_DATA);
    SetIndexBuffer(5, HALow, INDICATOR_DATA);
    SetIndexBuffer(6, HAClose, INDICATOR_DATA);
    SetIndexBuffer(7, HAColor, INDICATOR_COLOR_INDEX);
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpBullColor);
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpBearColor);

    SetIndexBuffer(8, minorSwingHigh, INDICATOR_DATA);
    PlotIndexSetInteger(4, PLOT_ARROW, 159);
    PlotIndexSetInteger(4, PLOT_LINE_WIDTH, MinorSwingSize);
    PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(9, minorSwingLow, INDICATOR_DATA);
    PlotIndexSetInteger(5, PLOT_ARROW, 159);
    PlotIndexSetInteger(5, PLOT_LINE_WIDTH, MinorSwingSize);
    PlotIndexSetDouble(9, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    if (!ShowMinorStructure)
    {
        PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
        PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
    }
    else
    {
        PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_ARROW);
        PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_ARROW);
    }

    PlotIndexSetString(0, PLOT_LABEL, "Major Swing High");
    PlotIndexSetString(1, PLOT_LABEL, "Major Swing Low");
    PlotIndexSetString(2, PLOT_LABEL, "EMA");
    PlotIndexSetString(3, PLOT_LABEL, "HA Open;HA High;HA Low;HA Close");
    PlotIndexSetString(4, PLOT_LABEL, "Minor Swing High");
    PlotIndexSetString(5, PLOT_LABEL, "Minor Swing Low");
    SetIndexBuffer(10, MajorTrendBuffer, INDICATOR_DATA);
    PlotIndexSetString(6, PLOT_LABEL, "Major Trend");
    SetIndexBuffer(11, MinorTrendBuffer, INDICATOR_DATA);
    PlotIndexSetString(7, PLOT_LABEL, "Minor Trend");
    SetIndexBuffer(12, MajorEventBuffer, INDICATOR_DATA);
    PlotIndexSetString(8, PLOT_LABEL, "Major Event");
    SetIndexBuffer(13, MinorEventBuffer, INDICATOR_DATA);
    PlotIndexSetString(9, PLOT_LABEL, "Minor Event");
    SetIndexBuffer(14, MajorProtHighBuffer, INDICATOR_DATA);
    PlotIndexSetString(10, PLOT_LABEL, "Major KeyLevel High");
    SetIndexBuffer(15, MajorProtLowBuffer, INDICATOR_DATA);
    PlotIndexSetString(11, PLOT_LABEL, "Major KeyLevel Low");
    SetIndexBuffer(16, MinorProtHighBuffer, INDICATOR_DATA);
    PlotIndexSetString(12, PLOT_LABEL, "Minor Prot High");
    SetIndexBuffer(17, MinorProtLowBuffer, INDICATOR_DATA);
    PlotIndexSetString(13, PLOT_LABEL, "Minor Prot Low");
    SetIndexBuffer(18, BuyZoneEntryBuffer, INDICATOR_DATA);
    PlotIndexSetString(14, PLOT_LABEL, "Buy Zone Entry");
    SetIndexBuffer(19, BuyZoneSLBuffer, INDICATOR_DATA);
    PlotIndexSetString(15, PLOT_LABEL, "Buy Zone SL");
    SetIndexBuffer(20, SellZoneSLBuffer, INDICATOR_DATA);
    PlotIndexSetString(16, PLOT_LABEL, "Sell Zone SL");
    SetIndexBuffer(21, SellZoneEntryBuffer, INDICATOR_DATA);
    PlotIndexSetString(17, PLOT_LABEL, "Sell Zone Entry");

    // Buffer 22-25: carry-forward — ghi lien tuc moi bar cho EA doc
    SetIndexBuffer(22, BOS_Up_Level, INDICATOR_DATA);
    PlotIndexSetDouble(22, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(23, BOS_Dn_Level, INDICATOR_DATA);
    PlotIndexSetDouble(23, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(24, CHOCH_Up_Level, INDICATOR_DATA);
    PlotIndexSetDouble(24, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    SetIndexBuffer(25, CHOCH_Dn_Level, INDICATOR_DATA);
    PlotIndexSetDouble(25, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    ma_handle = iMA(_Symbol, _Period, MovingAveragePeriods, 0, MODE_EMA, PRICE_CLOSE);
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "IND_SMC_"); }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
    int lookBack_max = MathMax(lookBackMajor, lookBackMinor);
    if (rates_total < lookBack_max + 1)
        return (0);

    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(majorSwingHigh, true);
    ArraySetAsSeries(majorSwingLow, true);
    ArraySetAsSeries(EMA_Buffer, true);
    ArraySetAsSeries(HAOpen, true);
    ArraySetAsSeries(HAHigh, true);
    ArraySetAsSeries(HALow, true);
    ArraySetAsSeries(HAClose, true);
    ArraySetAsSeries(HAColor, true);
    ArraySetAsSeries(minorSwingHigh, true);
    ArraySetAsSeries(minorSwingLow, true);
    ArraySetAsSeries(MajorTrendBuffer, true);
    ArraySetAsSeries(MinorTrendBuffer, true);
    ArraySetAsSeries(MajorEventBuffer, true);
    ArraySetAsSeries(MinorEventBuffer, true);
    ArraySetAsSeries(MajorProtHighBuffer, true);
    ArraySetAsSeries(MajorProtLowBuffer, true);
    ArraySetAsSeries(MinorProtHighBuffer, true);
    ArraySetAsSeries(MinorProtLowBuffer, true);
    ArraySetAsSeries(BuyZoneEntryBuffer, true);
    ArraySetAsSeries(BuyZoneSLBuffer, true);
    ArraySetAsSeries(SellZoneSLBuffer, true);
    ArraySetAsSeries(SellZoneEntryBuffer, true);
    ArraySetAsSeries(BOS_Up_Level, true);
    ArraySetAsSeries(BOS_Dn_Level, true);
    ArraySetAsSeries(CHOCH_Up_Level, true);
    ArraySetAsSeries(CHOCH_Dn_Level, true);

    if (prev_calculated == 0)
    {
        ObjectsDeleteAll(0, "IND_SMC_");
        ArrayInitialize(majorSwingHigh, EMPTY_VALUE);
        ArrayInitialize(majorSwingLow, EMPTY_VALUE);
        ArrayInitialize(minorSwingHigh, EMPTY_VALUE);
        ArrayInitialize(minorSwingLow, EMPTY_VALUE);
        ArrayInitialize(MajorTrendBuffer, EMPTY_VALUE);
        ArrayInitialize(MinorTrendBuffer, EMPTY_VALUE);
        ArrayInitialize(MajorEventBuffer, 0);
        ArrayInitialize(MinorEventBuffer, 0);
        ArrayInitialize(MajorProtHighBuffer, EMPTY_VALUE);
        ArrayInitialize(MajorProtLowBuffer, EMPTY_VALUE);
        ArrayInitialize(MinorProtHighBuffer, EMPTY_VALUE);
        ArrayInitialize(MinorProtLowBuffer, EMPTY_VALUE);
        ArrayInitialize(BuyZoneEntryBuffer, EMPTY_VALUE);
        ArrayInitialize(BuyZoneSLBuffer, EMPTY_VALUE);
        ArrayInitialize(SellZoneSLBuffer, EMPTY_VALUE);
        ArrayInitialize(SellZoneEntryBuffer, EMPTY_VALUE);
        ArrayInitialize(BOS_Up_Level, EMPTY_VALUE);
        ArrayInitialize(BOS_Dn_Level, EMPTY_VALUE);
        ArrayInitialize(CHOCH_Up_Level, EMPTY_VALUE);
        ArrayInitialize(CHOCH_Dn_Level, EMPTY_VALUE);

        ActiveHigh.isActive = false;
        ActiveLow.isActive = false;
        ActiveMinorHigh.isActive = false;
        ActiveMinorLow.isActive = false;
        ActiveHigh.idx = -1;
        ActiveLow.idx = -1;
        ActiveMinorHigh.idx = -1;
        ActiveMinorLow.idx = -1;

        major_trend = 0;
        maj_prot_high = EMPTY_VALUE;
        maj_prot_high_time = 0;
        maj_prot_high_idx = -1;
        maj_prot_low = EMPTY_VALUE;
        maj_prot_low_time = 0;
        maj_prot_low_idx = -1;
        maj_extreme_high = EMPTY_VALUE;
        maj_extreme_high_time = 0;
        maj_extreme_high_idx = -1;
        maj_extreme_low = EMPTY_VALUE;
        maj_extreme_low_time = 0;
        maj_extreme_low_idx = -1;
        last_maj_high = EMPTY_VALUE;
        last_maj_high_time = 0;
        last_maj_high_idx = -1;
        last_maj_low = EMPTY_VALUE;
        last_maj_low_time = 0;
        last_maj_low_idx = -1;
        maj_confirmed_extreme_high = EMPTY_VALUE;
        maj_confirmed_extreme_high_time = 0;
        maj_confirmed_extreme_low = EMPTY_VALUE;
        maj_confirmed_extreme_low_time = 0;
        maj_strong_high = EMPTY_VALUE;
        maj_strong_high_time = 0;
        maj_strong_high_idx = -1;
        maj_strong_low = EMPTY_VALUE;
        maj_strong_low_time = 0;
        maj_strong_low_idx = -1;
        last_strong_high_update_time = 0;
        last_strong_low_update_time = 0;
        pending_strong_high_update = false;
        pending_strong_low_update = false;
        pending_weak_high_level = EMPTY_VALUE;
        pending_weak_low_level = EMPTY_VALUE;
        processed_weak_high_time = 0;
        processed_weak_low_time = 0;
        pending_prot_high_update = false;
        pending_prot_low_update = false;
        processed_prot_weak_high_time = 0;
        processed_prot_weak_low_time = 0;
        prot_anchor_time = 0;
        prot_breakout_idx = -1;
        minor_trend = 0;
        min_prot_high = EMPTY_VALUE;
        min_prot_high_time = 0;
        min_prot_high_idx = -1;
        min_prot_low = EMPTY_VALUE;
        min_prot_low_time = 0;
        min_prot_low_idx = -1;
        min_extreme_high = EMPTY_VALUE;
        min_extreme_high_time = 0;
        min_extreme_high_idx = -1;
        min_extreme_low = EMPTY_VALUE;
        min_extreme_low_time = 0;
        min_extreme_low_idx = -1;
        last_min_high = EMPTY_VALUE;
        last_min_high_time = 0;
        last_min_high_idx = -1;
        last_min_low = EMPTY_VALUE;
        last_min_low_time = 0;
        last_min_low_idx = -1;
        is_maj_prot_high_sweep = false;
        is_maj_prot_low_sweep = false;
        is_min_prot_high_sweep = false;
        is_min_prot_low_sweep = false;
        last_processed_high_time = 0;
        last_processed_low_time = 0;
        last_break_dir = 0;
        last_break_type = 0;
        latest_break_up_time = 0;
        latest_break_up_idx = -1;
        latest_break_up_level = EMPTY_VALUE;
        latest_break_down_time = 0;
        latest_break_down_idx = -1;
        latest_break_down_level = EMPTY_VALUE;
        ArrayResize(BOSUpQueue, 0);
        ArrayResize(BOSDnQueue, 0);
        ArrayResize(BuyZonesQueue, 0);
        ArrayResize(SellZonesQueue, 0);
        ArrayResize(MinorBOSUpQueue, 0);
        ArrayResize(MinorBOSDnQueue, 0);

        // PATCH: Reset carry-forward vars
        last_bos_up_level = EMPTY_VALUE;
        last_bos_dn_level = EMPTY_VALUE;
        last_choch_up_level = EMPTY_VALUE;
        last_choch_dn_level = EMPTY_VALUE;
    }

    if (prev_calculated > 0 && rates_total > prev_calculated)
    {
        int shift = rates_total - prev_calculated;
        if (ActiveHigh.idx >= 0)
            ActiveHigh.idx += shift;
        if (ActiveLow.idx >= 0)
            ActiveLow.idx += shift;
        if (ActiveMinorHigh.idx >= 0)
            ActiveMinorHigh.idx += shift;
        if (ActiveMinorLow.idx >= 0)
            ActiveMinorLow.idx += shift;
        if (maj_prot_high_idx >= 0)
            maj_prot_high_idx += shift;
        if (maj_prot_low_idx >= 0)
            maj_prot_low_idx += shift;
        if (maj_extreme_high_idx >= 0)
            maj_extreme_high_idx += shift;
        if (maj_extreme_low_idx >= 0)
            maj_extreme_low_idx += shift;
        if (last_maj_high_idx >= 0)
            last_maj_high_idx += shift;
        if (last_maj_low_idx >= 0)
            last_maj_low_idx += shift;
        if (latest_break_up_idx >= 0)
            latest_break_up_idx += shift;
        if (latest_break_down_idx >= 0)
            latest_break_down_idx += shift;
        if (min_prot_high_idx >= 0)
            min_prot_high_idx += shift;
        if (min_prot_low_idx >= 0)
            min_prot_low_idx += shift;
        if (min_extreme_high_idx >= 0)
            min_extreme_high_idx += shift;
        if (min_extreme_low_idx >= 0)
            min_extreme_low_idx += shift;
        if (last_min_high_idx >= 0)
            last_min_high_idx += shift;
        if (last_min_low_idx >= 0)
            last_min_low_idx += shift;
        if (prot_breakout_idx >= 0)
            prot_breakout_idx += shift;
        if (maj_strong_high_idx >= 0)
            maj_strong_high_idx += shift;
        if (maj_strong_low_idx >= 0)
            maj_strong_low_idx += shift;
    }

    int limit = (prev_calculated == 0) ? rates_total - lookBack_max - 1 : (rates_total - prev_calculated) + lookBack_max;
    if (limit >= rates_total - lookBack_max)
        limit = rates_total - lookBack_max - 1;

    for (int i = limit + lookBack_max; i >= 0; i--)
    {
        HAClose[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
        if (i >= rates_total - 1)
            HAOpen[i] = (open[i] + close[i]) / 2.0;
        else
            HAOpen[i] = (HAOpen[i + 1] + HAClose[i + 1]) / 2.0;
        HAHigh[i] = MathMax(high[i], MathMax(HAOpen[i], HAClose[i]));
        HALow[i] = MathMin(low[i], MathMin(HAOpen[i], HAClose[i]));
        HAColor[i] = (HAClose[i] >= HAOpen[i]) ? 0 : 1;
    }
    if (CopyBuffer(ma_handle, 0, 0, rates_total, EMA_Buffer) <= 0)
        return (0);

    for (int k = 0; k <= PeriodsInMajorSwing && k < rates_total; k++)
    {
        majorSwingHigh[k] = EMPTY_VALUE;
        majorSwingLow[k] = EMPTY_VALUE;
    }
    for (int k = 0; k <= PeriodsInMinorSwing && k < rates_total; k++)
    {
        minorSwingHigh[k] = EMPTY_VALUE;
        minorSwingLow[k] = EMPTY_VALUE;
    }

    for (int i = 0; i <= limit && !IsStopped(); i++)
    {
        majorSwingHigh[i + PeriodsInMajorSwing] = EMPTY_VALUE;
        majorSwingLow[i + PeriodsInMajorSwing] = EMPTY_VALUE;
        minorSwingHigh[i + PeriodsInMinorSwing] = EMPTY_VALUE;
        minorSwingLow[i + PeriodsInMinorSwing] = EMPTY_VALUE;
        if (i > 0)
        {
            if (ArrayMaximum(high, i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing)
                majorSwingHigh[i + PeriodsInMajorSwing] = high[i + PeriodsInMajorSwing];
            if (ArrayMinimum(low, i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing)
                majorSwingLow[i + PeriodsInMajorSwing] = low[i + PeriodsInMajorSwing];
            if (ArrayMaximum(high, i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing)
                minorSwingHigh[i + PeriodsInMinorSwing] = high[i + PeriodsInMinorSwing];
            if (ArrayMinimum(low, i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing)
                minorSwingLow[i + PeriodsInMinorSwing] = low[i + PeriodsInMinorSwing];
        }
    }

    int bos_limit = (prev_calculated == 0) ? limit : (rates_total - prev_calculated) + 1;

    for (int i = bos_limit; i >= 0; i--)
    {
        MajorEventBuffer[i] = 0;
        MinorEventBuffer[i] = 0;

        if (ActiveHigh.isActive)
        {
            if (ActiveHigh.idx >= 0 && ActiveHigh.idx < rates_total && majorSwingHigh[ActiveHigh.idx] == EMPTY_VALUE)
                ActiveHigh.isActive = false;
        }
        if (ActiveLow.isActive)
        {
            if (ActiveLow.idx >= 0 && ActiveLow.idx < rates_total && majorSwingLow[ActiveLow.idx] == EMPTY_VALUE)
                ActiveLow.isActive = false;
        }
        if (ActiveMinorHigh.isActive)
        {
            if (ActiveMinorHigh.idx >= 0 && ActiveMinorHigh.idx < rates_total && minorSwingHigh[ActiveMinorHigh.idx] == EMPTY_VALUE)
                ActiveMinorHigh.isActive = false;
        }
        if (ActiveMinorLow.isActive)
        {
            if (ActiveMinorLow.idx >= 0 && ActiveMinorLow.idx < rates_total && minorSwingLow[ActiveMinorLow.idx] == EMPTY_VALUE)
                ActiveMinorLow.isActive = false;
        }

        if (maj_prot_high != EMPTY_VALUE && !is_maj_prot_high_sweep)
        {
            if (maj_prot_high_idx >= 0 && maj_prot_high_idx < rates_total && majorSwingHigh[maj_prot_high_idx] == EMPTY_VALUE)
            {
                maj_prot_high = EMPTY_VALUE;
                maj_prot_high_idx = -1;
            }
        }
        if (maj_prot_low != EMPTY_VALUE && !is_maj_prot_low_sweep)
        {
            if (maj_prot_low_idx >= 0 && maj_prot_low_idx < rates_total && majorSwingLow[maj_prot_low_idx] == EMPTY_VALUE)
            {
                maj_prot_low = EMPTY_VALUE;
                maj_prot_low_idx = -1;
            }
        }
        if (min_prot_high != EMPTY_VALUE && !is_min_prot_high_sweep)
        {
            if (min_prot_high_idx >= 0 && min_prot_high_idx < rates_total && minorSwingHigh[min_prot_high_idx] == EMPTY_VALUE)
            {
                min_prot_high = EMPTY_VALUE;
                min_prot_high_idx = -1;
            }
        }
        if (min_prot_low != EMPTY_VALUE && !is_min_prot_low_sweep)
        {
            if (min_prot_low_idx >= 0 && min_prot_low_idx < rates_total && minorSwingLow[min_prot_low_idx] == EMPTY_VALUE)
            {
                min_prot_low = EMPTY_VALUE;
                min_prot_low_idx = -1;
            }
        }

        int swingMajor_idx = i + PeriodsInMajorSwing;
        if (swingMajor_idx < rates_total)
        {
            if (majorSwingHigh[swingMajor_idx] != EMPTY_VALUE)
            {
                ActiveHigh.price = majorSwingHigh[swingMajor_idx];
                ActiveHigh.time = time[swingMajor_idx];
                ActiveHigh.isActive = true;
                ActiveHigh.idx = swingMajor_idx;
                last_maj_high = ActiveHigh.price;
                last_maj_high_time = ActiveHigh.time;
                last_maj_high_idx = swingMajor_idx;
                if (major_trend == 1 && majorSwingHigh[swingMajor_idx] == maj_extreme_high)
                {
                    maj_confirmed_extreme_high = majorSwingHigh[swingMajor_idx];
                    maj_confirmed_extreme_high_time = time[swingMajor_idx];
                }
                if (time[swingMajor_idx] > last_processed_high_time)
                {
                    last_processed_high_time = time[swingMajor_idx];
                    if (last_break_dir == -1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_down_time)
                    {
                        int b_idx = latest_break_down_idx;
                        if (b_idx != -1)
                        {
                            string zone_name = "IND_SMC_ZONE_SELL_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                            double zEntry, zStop;
                            CreateZone(zone_name, swingMajor_idx, b_idx, true, latest_break_down_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                            PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                        }
                    }
                }
            }
            if (majorSwingLow[swingMajor_idx] != EMPTY_VALUE)
            {
                ActiveLow.price = majorSwingLow[swingMajor_idx];
                ActiveLow.time = time[swingMajor_idx];
                ActiveLow.isActive = true;
                ActiveLow.idx = swingMajor_idx;
                last_maj_low = ActiveLow.price;
                last_maj_low_time = ActiveLow.time;
                last_maj_low_idx = swingMajor_idx;
                if (major_trend == -1 && majorSwingLow[swingMajor_idx] == maj_extreme_low)
                {
                    maj_confirmed_extreme_low = majorSwingLow[swingMajor_idx];
                    maj_confirmed_extreme_low_time = time[swingMajor_idx];
                }
                if (time[swingMajor_idx] > last_processed_low_time)
                {
                    last_processed_low_time = time[swingMajor_idx];
                    if (last_break_dir == 1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_up_time)
                    {
                        int b_idx = latest_break_up_idx;
                        if (b_idx != -1)
                        {
                            string zone_name = "IND_SMC_ZONE_BUY_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                            double zEntry, zStop;
                            CreateZone(zone_name, swingMajor_idx, b_idx, false, latest_break_up_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                            PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                        }
                    }
                }
            }
        }

        int swingMinor_idx = i + PeriodsInMinorSwing;
        if (swingMinor_idx < rates_total)
        {
            if (minorSwingHigh[swingMinor_idx] != EMPTY_VALUE)
            {
                ActiveMinorHigh.price = minorSwingHigh[swingMinor_idx];
                ActiveMinorHigh.time = time[swingMinor_idx];
                ActiveMinorHigh.isActive = true;
                ActiveMinorHigh.idx = swingMinor_idx;
                last_min_high = ActiveMinorHigh.price;
                last_min_high_time = ActiveMinorHigh.time;
                last_min_high_idx = swingMinor_idx;
            }
            if (minorSwingLow[swingMinor_idx] != EMPTY_VALUE)
            {
                ActiveMinorLow.price = minorSwingLow[swingMinor_idx];
                ActiveMinorLow.time = time[swingMinor_idx];
                ActiveMinorLow.isActive = true;
                ActiveMinorLow.idx = swingMinor_idx;
                last_min_low = ActiveMinorLow.price;
                last_min_low_time = ActiveMinorLow.time;
                last_min_low_idx = swingMinor_idx;
            }
        }

        if (major_trend == 1)
        {
            if (maj_extreme_high == EMPTY_VALUE || high[i] > maj_extreme_high)
            {
                maj_extreme_high = high[i];
                maj_extreme_high_time = time[i];
                maj_extreme_high_idx = i;
            }
        }
        else if (major_trend == -1)
        {
            if (maj_extreme_low == EMPTY_VALUE || low[i] < maj_extreme_low)
            {
                maj_extreme_low = low[i];
                maj_extreme_low_time = time[i];
                maj_extreme_low_idx = i;
            }
        }
        if (minor_trend == 1)
        {
            if (min_extreme_high == EMPTY_VALUE || high[i] > min_extreme_high)
            {
                min_extreme_high = high[i];
                min_extreme_high_time = time[i];
                min_extreme_high_idx = i;
            }
        }
        else if (minor_trend == -1)
        {
            if (min_extreme_low == EMPTY_VALUE || low[i] < min_extreme_low)
            {
                min_extreme_low = low[i];
                min_extreme_low_time = time[i];
                min_extreme_low_idx = i;
            }
        }

        if (i > 0)
        {
            if (major_trend == 0)
            {
                if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price)
                {
                    major_trend = 1;
                    maj_extreme_high = high[i];
                    maj_extreme_high_time = time[i];
                    maj_extreme_high_idx = i;
                    maj_prot_low = (last_maj_low != EMPTY_VALUE) ? last_maj_low : low[i];
                    maj_prot_low_time = (last_maj_low_time != 0) ? last_maj_low_time : time[i];
                    maj_prot_low_idx = (last_maj_low_idx != -1) ? last_maj_low_idx : i;
                    maj_strong_low = maj_prot_low;
                    maj_strong_low_time = maj_prot_low_time;
                    maj_strong_low_idx = maj_prot_low_idx;
                    last_strong_low_update_time = time[i];
                    is_maj_prot_low_sweep = false;
                }
                else if (ActiveLow.isActive && HAClose[i] < ActiveLow.price)
                {
                    major_trend = -1;
                    maj_extreme_low = low[i];
                    maj_extreme_low_time = time[i];
                    maj_extreme_low_idx = i;
                    maj_prot_high = (last_maj_high != EMPTY_VALUE) ? last_maj_high : high[i];
                    maj_prot_high_time = (last_maj_high_time != 0) ? last_maj_high_time : time[i];
                    maj_prot_high_idx = (last_maj_high_idx != -1) ? last_maj_high_idx : i;
                    maj_strong_high = maj_prot_high;
                    maj_strong_high_time = maj_prot_high_time;
                    maj_strong_high_idx = maj_prot_high_idx;
                    last_strong_high_update_time = time[i];
                    is_maj_prot_high_sweep = false;
                }
            }

            if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE &&
                HAClose[i] > maj_confirmed_extreme_high &&
                processed_prot_weak_high_time != maj_confirmed_extreme_high_time)
            {
                processed_prot_weak_high_time = maj_confirmed_extreme_high_time;
                prot_anchor_time = maj_confirmed_extreme_high_time;
                prot_breakout_idx = i;
                double temp_d4_val = EMPTY_VALUE;
                datetime temp_d4_time = 0;
                int temp_d4_idx = -1;
                int anchor_idx = -1;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] == prot_anchor_time)
                    {
                        anchor_idx = k;
                        break;
                    }
                }
                if (anchor_idx != -1)
                {
                    for (int k = i; k <= anchor_idx; k++)
                    {
                        if (majorSwingLow[k] != EMPTY_VALUE)
                        {
                            temp_d4_val = majorSwingLow[k];
                            temp_d4_time = time[k];
                            temp_d4_idx = k;
                            break;
                        }
                    }
                }
                if (temp_d4_val != EMPTY_VALUE)
                {
                    double temp_d5_val = EMPTY_VALUE;
                    datetime temp_d5_time = 0;
                    int temp_d5_idx = -1;
                    for (int k = i; k <= temp_d4_idx; k++)
                    {
                        if (temp_d5_val == EMPTY_VALUE || low[k] < temp_d5_val)
                        {
                            temp_d5_val = low[k];
                            temp_d5_time = time[k];
                            temp_d5_idx = k;
                        }
                    }
                    if (temp_d5_val != EMPTY_VALUE && temp_d5_val < temp_d4_val)
                    {
                        maj_prot_low = temp_d5_val;
                        maj_prot_low_time = temp_d5_time;
                        maj_prot_low_idx = temp_d5_idx;
                        is_maj_prot_low_sweep = true;
                    }
                    else
                    {
                        maj_prot_low = temp_d4_val;
                        maj_prot_low_time = temp_d4_time;
                        maj_prot_low_idx = temp_d4_idx;
                        is_maj_prot_low_sweep = false;
                    }
                }
                pending_prot_low_update = true;
            }

            if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE &&
                HAClose[i] < maj_confirmed_extreme_low &&
                processed_prot_weak_low_time != maj_confirmed_extreme_low_time)
            {
                processed_prot_weak_low_time = maj_confirmed_extreme_low_time;
                prot_anchor_time = maj_confirmed_extreme_low_time;
                prot_breakout_idx = i;
                double temp_d4_val = EMPTY_VALUE;
                datetime temp_d4_time = 0;
                int temp_d4_idx = -1;
                int anchor_idx = -1;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] == prot_anchor_time)
                    {
                        anchor_idx = k;
                        break;
                    }
                }
                if (anchor_idx != -1)
                {
                    for (int k = i; k <= anchor_idx; k++)
                    {
                        if (majorSwingHigh[k] != EMPTY_VALUE)
                        {
                            temp_d4_val = majorSwingHigh[k];
                            temp_d4_time = time[k];
                            temp_d4_idx = k;
                            break;
                        }
                    }
                }
                if (temp_d4_val != EMPTY_VALUE)
                {
                    double temp_d5_val = EMPTY_VALUE;
                    datetime temp_d5_time = 0;
                    int temp_d5_idx = -1;
                    for (int k = i; k <= temp_d4_idx; k++)
                    {
                        if (temp_d5_val == EMPTY_VALUE || high[k] > temp_d5_val)
                        {
                            temp_d5_val = high[k];
                            temp_d5_time = time[k];
                            temp_d5_idx = k;
                        }
                    }
                    if (temp_d5_val != EMPTY_VALUE && temp_d5_val > temp_d4_val)
                    {
                        maj_prot_high = temp_d5_val;
                        maj_prot_high_time = temp_d5_time;
                        maj_prot_high_idx = temp_d5_idx;
                        is_maj_prot_high_sweep = true;
                    }
                    else
                    {
                        maj_prot_high = temp_d4_val;
                        maj_prot_high_time = temp_d4_time;
                        maj_prot_high_idx = temp_d4_idx;
                        is_maj_prot_high_sweep = false;
                    }
                }
                pending_prot_high_update = true;
            }

            if (major_trend == 1 && pending_prot_low_update && prot_breakout_idx != -1)
            {
                double d4_val = EMPTY_VALUE;
                datetime d4_time = 0;
                int d4_idx = -1;
                int anchor_idx = -1;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] == prot_anchor_time)
                    {
                        anchor_idx = k;
                        break;
                    }
                }
                if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx)
                {
                    for (int k = prot_breakout_idx; k <= anchor_idx; k++)
                    {
                        if (majorSwingLow[k] != EMPTY_VALUE)
                        {
                            d4_val = majorSwingLow[k];
                            d4_time = time[k];
                            d4_idx = k;
                            break;
                        }
                    }
                    if (d4_val != EMPTY_VALUE)
                    {
                        double d5_val = EMPTY_VALUE;
                        datetime d5_time = 0;
                        int d5_idx = -1;
                        for (int k = prot_breakout_idx; k <= d4_idx; k++)
                        {
                            if (d5_val == EMPTY_VALUE || low[k] < d5_val)
                            {
                                d5_val = low[k];
                                d5_time = time[k];
                                d5_idx = k;
                            }
                        }
                        if (d5_val != EMPTY_VALUE && d5_val < d4_val)
                        {
                            maj_prot_low = d5_val;
                            maj_prot_low_time = d5_time;
                            maj_prot_low_idx = d5_idx;
                            is_maj_prot_low_sweep = true;
                        }
                        else
                        {
                            maj_prot_low = d4_val;
                            maj_prot_low_time = d4_time;
                            maj_prot_low_idx = d4_idx;
                            is_maj_prot_low_sweep = false;
                        }
                        if (prot_breakout_idx - i >= PeriodsInMajorSwing)
                        {
                            pending_prot_low_update = false;
                        }
                    }
                    else
                    {
                        if (prot_breakout_idx - i >= PeriodsInMajorSwing)
                        {
                            pending_prot_low_update = false;
                        }
                    }
                }
                else
                {
                    pending_prot_low_update = false;
                }
            }

            if (major_trend == -1 && pending_prot_high_update && prot_breakout_idx != -1)
            {
                double d4_val = EMPTY_VALUE;
                datetime d4_time = 0;
                int d4_idx = -1;
                int anchor_idx = -1;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] == prot_anchor_time)
                    {
                        anchor_idx = k;
                        break;
                    }
                }
                if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx)
                {
                    for (int k = prot_breakout_idx; k <= anchor_idx; k++)
                    {
                        if (majorSwingHigh[k] != EMPTY_VALUE)
                        {
                            d4_val = majorSwingHigh[k];
                            d4_time = time[k];
                            d4_idx = k;
                            break;
                        }
                    }
                    if (d4_val != EMPTY_VALUE)
                    {
                        double d5_val = EMPTY_VALUE;
                        datetime d5_time = 0;
                        int d5_idx = -1;
                        for (int k = prot_breakout_idx; k <= d4_idx; k++)
                        {
                            if (d5_val == EMPTY_VALUE || high[k] > d5_val)
                            {
                                d5_val = high[k];
                                d5_time = time[k];
                                d5_idx = k;
                            }
                        }
                        if (d5_val != EMPTY_VALUE && d5_val > d4_val)
                        {
                            maj_prot_high = d5_val;
                            maj_prot_high_time = d5_time;
                            maj_prot_high_idx = d5_idx;
                            is_maj_prot_high_sweep = true;
                        }
                        else
                        {
                            maj_prot_high = d4_val;
                            maj_prot_high_time = d4_time;
                            maj_prot_high_idx = d4_idx;
                            is_maj_prot_high_sweep = false;
                        }
                        if (prot_breakout_idx - i >= PeriodsInMajorSwing)
                        {
                            pending_prot_high_update = false;
                        }
                    }
                    else
                    {
                        if (prot_breakout_idx - i >= PeriodsInMajorSwing)
                        {
                            pending_prot_high_update = false;
                        }
                    }
                }
                else
                {
                    pending_prot_high_update = false;
                }
            }

            if (minor_trend == 1)
            {
                bool is_min_ha_break_up = (min_extreme_high != EMPTY_VALUE && HAClose[i] > min_extreme_high);
                if (is_min_ha_break_up)
                {
                    double d4_val = EMPTY_VALUE;
                    datetime d4_time = 0;
                    int d4_idx = -1;
                    if (last_min_low != EMPTY_VALUE && last_min_low_time <= time[i])
                    {
                        d4_val = last_min_low;
                        d4_time = last_min_low_time;
                        d4_idx = last_min_low_idx;
                    }
                    if (ActiveMinorLow.isActive && ActiveMinorLow.time < min_extreme_high_time)
                    {
                        d4_val = ActiveMinorLow.price;
                        d4_time = ActiveMinorLow.time;
                        d4_idx = ActiveMinorLow.idx;
                    }
                    if (d4_idx != -1)
                    {
                        double d5_val = EMPTY_VALUE;
                        datetime d5_time = 0;
                        int d5_idx = -1;
                        for (int k = i; k <= d4_idx; k++)
                        {
                            if (d5_val == EMPTY_VALUE || low[k] < d5_val)
                            {
                                d5_val = low[k];
                                d5_time = time[k];
                                d5_idx = k;
                            }
                        }
                        if (d5_val != EMPTY_VALUE && d5_val < d4_val)
                        {
                            min_prot_low = d5_val;
                            min_prot_low_time = d5_time;
                            min_prot_low_idx = d5_idx;
                            is_min_prot_low_sweep = true;
                        }
                        else
                        {
                            min_prot_low = d4_val;
                            min_prot_low_time = d4_time;
                            min_prot_low_idx = d4_idx;
                            is_min_prot_low_sweep = false;
                        }
                    }
                }
            }
            else if (minor_trend == -1)
            {
                bool is_min_ha_break_dn = (min_extreme_low != EMPTY_VALUE && HAClose[i] < min_extreme_low);
                if (is_min_ha_break_dn)
                {
                    double d4_val = EMPTY_VALUE;
                    datetime d4_time = 0;
                    int d4_idx = -1;
                    if (last_min_high != EMPTY_VALUE && last_min_high_time <= time[i])
                    {
                        d4_val = last_min_high;
                        d4_time = last_min_high_time;
                        d4_idx = last_min_high_idx;
                    }
                    if (ActiveMinorHigh.isActive && ActiveMinorHigh.time < min_extreme_low_time)
                    {
                        d4_val = ActiveMinorHigh.price;
                        d4_time = ActiveMinorHigh.time;
                        d4_idx = ActiveMinorHigh.idx;
                    }
                    if (d4_idx != -1)
                    {
                        double d5_val = EMPTY_VALUE;
                        datetime d5_time = 0;
                        int d5_idx = -1;
                        for (int k = i; k <= d4_idx; k++)
                        {
                            if (d5_val == EMPTY_VALUE || high[k] > d5_val)
                            {
                                d5_val = high[k];
                                d5_time = time[k];
                                d5_idx = k;
                            }
                        }
                        if (d5_val != EMPTY_VALUE && d5_val > d4_val)
                        {
                            min_prot_high = d5_val;
                            min_prot_high_time = d5_time;
                            min_prot_high_idx = d5_idx;
                            is_min_prot_high_sweep = true;
                        }
                        else
                        {
                            min_prot_high = d4_val;
                            min_prot_high_time = d4_time;
                            min_prot_high_idx = d4_idx;
                            is_min_prot_high_sweep = false;
                        }
                    }
                }
            }
            else
            {
                if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price)
                {
                    minor_trend = 1;
                    min_extreme_high = high[i];
                    min_extreme_high_time = time[i];
                    min_extreme_high_idx = i;
                    min_prot_low = last_min_low;
                    min_prot_low_time = last_min_low_time;
                    min_prot_low_idx = last_min_low_idx;
                    is_min_prot_low_sweep = false;
                }
                else if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price)
                {
                    minor_trend = -1;
                    min_extreme_low = low[i];
                    min_extreme_low_time = time[i];
                    min_extreme_low_idx = i;
                    min_prot_high = last_min_high;
                    min_prot_high_time = last_min_high_time;
                    min_prot_high_idx = last_min_high_idx;
                    is_min_prot_high_sweep = false;
                }
            }

            for (int j = ArraySize(BuyZonesQueue) - 1; j >= 0; j--)
            {
                if (HAClose[i] < BuyZonesQueue[j].stopPrice)
                {
                    ObjectDelete(0, BuyZonesQueue[j].name);
                    for (int k = j; k < ArraySize(BuyZonesQueue) - 1; k++)
                        BuyZonesQueue[k] = BuyZonesQueue[k + 1];
                    ArrayResize(BuyZonesQueue, ArraySize(BuyZonesQueue) - 1);
                }
            }
            for (int j = ArraySize(SellZonesQueue) - 1; j >= 0; j--)
            {
                if (HAClose[i] > SellZonesQueue[j].stopPrice)
                {
                    ObjectDelete(0, SellZonesQueue[j].name);
                    for (int k = j; k < ArraySize(SellZonesQueue) - 1; k++)
                        SellZonesQueue[k] = SellZonesQueue[k + 1];
                    ArrayResize(SellZonesQueue, ArraySize(SellZonesQueue) - 1);
                }
            }

            // =========================================================================
            // CHOCH LOGIC KÍCH HOẠT THEO STRONG LEVEL
            // =========================================================================
            bool is_major_choch_up = false;
            bool is_major_choch_dn = false;

            if (major_trend == 1 && maj_strong_low != EMPTY_VALUE && HAClose[i] < maj_strong_low)
            {
                string choch_name = "IND_SMC_CHOCH_DN_" + IntegerToString((long)maj_strong_low_time);
                if (ObjectFind(0, choch_name) < 0)
                {
                    CreateBOSLine(choch_name, maj_strong_low_time, maj_strong_low, time[i], BOS_Down_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                    PushBOS(BOSDnQueue, choch_name, MaxBOSLines);
                    MajorEventBuffer[i] = -2;

                    // PATCH: Carry-forward CHOCH DN — reset tat ca phia nguoc lai
                    last_choch_dn_level = maj_strong_low;
                    last_choch_up_level = EMPTY_VALUE;
                    last_bos_up_level = EMPTY_VALUE;
                    last_bos_dn_level = EMPTY_VALUE;

                    ClearZoneQueue(BuyZonesQueue);
                    double actual_extreme_high = maj_extreme_high;
                    datetime actual_extreme_time = maj_extreme_high_time;
                    int actual_extreme_idx = maj_extreme_high_idx;
                    int strong_idx = maj_strong_low_idx;
                    if (strong_idx != -1 && strong_idx >= i)
                    {
                        int count = strong_idx - i + 1;
                        int highest_idx = ArrayMaximum(high, i, count);
                        if (highest_idx != -1)
                        {
                            actual_extreme_high = high[highest_idx];
                            actual_extreme_time = time[highest_idx];
                            actual_extreme_idx = highest_idx;
                        }
                    }
                    ObjectDelete(0, "IND_SMC_MAJOR_KEY_LEVEL");
                    ObjectDelete(0, "IND_SMC_MAJOR_KEY_LEVEL_lbl");
                    CreateRayLine("IND_SMC_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_high, KeyLevel_Color, "Major Key Level Down", true);
                    last_break_dir = -1;
                    last_break_type = 2;
                    latest_break_down_time = time[i];
                    latest_break_down_idx = i;
                    latest_break_down_level = maj_strong_low;
                    int zone_anchor_idx = actual_extreme_idx;
                    if (actual_extreme_idx != -1)
                    {
                        for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++)
                        {
                            if (k < rates_total && majorSwingHigh[k] != EMPTY_VALUE)
                            {
                                zone_anchor_idx = k;
                                break;
                            }
                        }
                    }
                    if (zone_anchor_idx != -1)
                    {
                        string zone_name = "IND_SMC_ZONE_SELL_CHOCH_" + IntegerToString((long)time[i]);
                        double zEntry, zStop;
                        CreateZone(zone_name, zone_anchor_idx, i, true, maj_strong_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                    if (ActiveLow.time == maj_strong_low_time)
                        ActiveLow.isActive = false;
                    ClearQueue(BOSUpQueue);
                    major_trend = -1;
                    maj_extreme_low = low[i];
                    maj_extreme_low_time = time[i];
                    maj_extreme_low_idx = i;
                    maj_confirmed_extreme_high = EMPTY_VALUE;
                    double temp_d4_val = EMPTY_VALUE;
                    datetime temp_d4_time = 0;
                    int temp_d4_idx = -1;
                    if (actual_extreme_idx != -1)
                    {
                        for (int k = i; k <= actual_extreme_idx; k++)
                        {
                            if (majorSwingHigh[k] != EMPTY_VALUE)
                            {
                                temp_d4_val = majorSwingHigh[k];
                                temp_d4_time = time[k];
                                temp_d4_idx = k;
                                break;
                            }
                        }
                    }
                    if (temp_d4_val != EMPTY_VALUE)
                    {
                        double temp_d5_val = EMPTY_VALUE;
                        datetime temp_d5_time = 0;
                        int temp_d5_idx = -1;
                        for (int k = i; k <= temp_d4_idx; k++)
                        {
                            if (temp_d5_val == EMPTY_VALUE || high[k] > temp_d5_val)
                            {
                                temp_d5_val = high[k];
                                temp_d5_time = time[k];
                                temp_d5_idx = k;
                            }
                        }
                        if (temp_d5_val != EMPTY_VALUE && temp_d5_val > temp_d4_val)
                        {
                            maj_prot_high = temp_d5_val;
                            maj_prot_high_time = temp_d5_time;
                            maj_prot_high_idx = temp_d5_idx;
                            is_maj_prot_high_sweep = true;
                        }
                        else
                        {
                            maj_prot_high = temp_d4_val;
                            maj_prot_high_time = temp_d4_time;
                            maj_prot_high_idx = temp_d4_idx;
                            is_maj_prot_high_sweep = false;
                        }
                    }
                    else
                    {
                        maj_prot_high = actual_extreme_high;
                        maj_prot_high_time = actual_extreme_time;
                        maj_prot_high_idx = actual_extreme_idx;
                        is_maj_prot_high_sweep = true;
                    }
                    pending_prot_high_update = true;
                    prot_anchor_time = actual_extreme_time;
                    prot_breakout_idx = i;
                    maj_prot_low = EMPTY_VALUE;
                    maj_prot_low_idx = -1;
                    pending_prot_low_update = false;
                    maj_strong_low = EMPTY_VALUE;
                    maj_strong_low_time = 0;
                    maj_strong_low_idx = -1;
                    pending_strong_low_update = false;
                    pending_strong_high_update = false;
                }
                is_major_choch_dn = true;
            }
            else if (major_trend == -1 && maj_strong_high != EMPTY_VALUE && HAClose[i] > maj_strong_high)
            {
                string choch_name = "IND_SMC_CHOCH_UP_" + IntegerToString((long)maj_strong_high_time);
                if (ObjectFind(0, choch_name) < 0)
                {
                    CreateBOSLine(choch_name, maj_strong_high_time, maj_strong_high, time[i], BOS_Up_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                    PushBOS(BOSUpQueue, choch_name, MaxBOSLines);
                    MajorEventBuffer[i] = 2;

                    // PATCH: Carry-forward CHOCH UP — reset tat ca phia nguoc lai
                    last_choch_up_level = maj_strong_high;
                    last_choch_dn_level = EMPTY_VALUE;
                    last_bos_dn_level = EMPTY_VALUE;
                    last_bos_up_level = EMPTY_VALUE;

                    ClearZoneQueue(SellZonesQueue);
                    double actual_extreme_low = maj_extreme_low;
                    datetime actual_extreme_time = maj_extreme_low_time;
                    int actual_extreme_idx = maj_extreme_low_idx;
                    int strong_idx = maj_strong_high_idx;
                    if (strong_idx != -1 && strong_idx >= i)
                    {
                        int count = strong_idx - i + 1;
                        int lowest_idx = ArrayMinimum(low, i, count);
                        if (lowest_idx != -1)
                        {
                            actual_extreme_low = low[lowest_idx];
                            actual_extreme_time = time[lowest_idx];
                            actual_extreme_idx = lowest_idx;
                        }
                    }
                    ObjectDelete(0, "IND_SMC_MAJOR_KEY_LEVEL");
                    ObjectDelete(0, "IND_SMC_MAJOR_KEY_LEVEL_lbl");
                    CreateRayLine("IND_SMC_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_low, KeyLevel_Color, "Major Key Level Up", false);
                    last_break_dir = 1;
                    last_break_type = 2;
                    latest_break_up_time = time[i];
                    latest_break_up_idx = i;
                    latest_break_up_level = maj_strong_high;
                    int zone_anchor_idx = actual_extreme_idx;
                    if (actual_extreme_idx != -1)
                    {
                        for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++)
                        {
                            if (k < rates_total && majorSwingLow[k] != EMPTY_VALUE)
                            {
                                zone_anchor_idx = k;
                                break;
                            }
                        }
                    }
                    if (zone_anchor_idx != -1)
                    {
                        string zone_name = "IND_SMC_ZONE_BUY_CHOCH_" + IntegerToString((long)time[i]);
                        double zEntry, zStop;
                        CreateZone(zone_name, zone_anchor_idx, i, false, maj_strong_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                    if (ActiveHigh.time == maj_strong_high_time)
                        ActiveHigh.isActive = false;
                    ClearQueue(BOSDnQueue);
                    major_trend = 1;
                    maj_extreme_high = high[i];
                    maj_extreme_high_time = time[i];
                    maj_extreme_high_idx = i;
                    maj_confirmed_extreme_low = EMPTY_VALUE;
                    double temp_d4_val = EMPTY_VALUE;
                    datetime temp_d4_time = 0;
                    int temp_d4_idx = -1;
                    if (actual_extreme_idx != -1)
                    {
                        for (int k = i; k <= actual_extreme_idx; k++)
                        {
                            if (majorSwingLow[k] != EMPTY_VALUE)
                            {
                                temp_d4_val = majorSwingLow[k];
                                temp_d4_time = time[k];
                                temp_d4_idx = k;
                                break;
                            }
                        }
                    }
                    if (temp_d4_val != EMPTY_VALUE)
                    {
                        double temp_d5_val = EMPTY_VALUE;
                        datetime temp_d5_time = 0;
                        int temp_d5_idx = -1;
                        for (int k = i; k <= temp_d4_idx; k++)
                        {
                            if (temp_d5_val == EMPTY_VALUE || low[k] < temp_d5_val)
                            {
                                temp_d5_val = low[k];
                                temp_d5_time = time[k];
                                temp_d5_idx = k;
                            }
                        }
                        if (temp_d5_val != EMPTY_VALUE && temp_d5_val < temp_d4_val)
                        {
                            maj_prot_low = temp_d5_val;
                            maj_prot_low_time = temp_d5_time;
                            maj_prot_low_idx = temp_d5_idx;
                            is_maj_prot_low_sweep = true;
                        }
                        else
                        {
                            maj_prot_low = temp_d4_val;
                            maj_prot_low_time = temp_d4_time;
                            maj_prot_low_idx = temp_d4_idx;
                            is_maj_prot_low_sweep = false;
                        }
                    }
                    else
                    {
                        maj_prot_low = actual_extreme_low;
                        maj_prot_low_time = actual_extreme_time;
                        maj_prot_low_idx = actual_extreme_idx;
                        is_maj_prot_low_sweep = true;
                    }
                    pending_prot_low_update = true;
                    prot_anchor_time = actual_extreme_time;
                    prot_breakout_idx = i;
                    maj_prot_high = EMPTY_VALUE;
                    maj_prot_high_idx = -1;
                    pending_prot_high_update = false;
                    maj_strong_high = EMPTY_VALUE;
                    maj_strong_high_time = 0;
                    maj_strong_high_idx = -1;
                    pending_strong_low_update = false;
                    pending_strong_high_update = false;
                }
                is_major_choch_up = true;
            }

            if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price)
            {
                if (!is_major_choch_up)
                {
                    string bos_name = "IND_SMC_BOS_UP_" + IntegerToString((long)ActiveHigh.time);
                    if (ObjectFind(0, bos_name) < 0)
                    {
                        CreateBOSLine(bos_name, ActiveHigh.time, ActiveHigh.price, time[i], BOS_Up_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                        PushBOS(BOSUpQueue, bos_name, MaxBOSLines);
                        MajorEventBuffer[i] = 1;
                        last_break_dir = 1;
                        last_break_type = 1;
                        latest_break_up_time = time[i];
                        latest_break_up_idx = i;
                        latest_break_up_level = ActiveHigh.price;

                        // PATCH: Carry-forward BOS UP — reset phia dn
                        last_bos_up_level = ActiveHigh.price;
                        last_bos_dn_level = EMPTY_VALUE;

                        int origin_idx = last_maj_low_idx;
                        if (origin_idx != -1)
                        {
                            string zone_name = "IND_SMC_ZONE_BUY_BOS_" + IntegerToString((long)last_maj_low_time);
                            double zEntry, zStop;
                            CreateZone(zone_name, origin_idx, i, false, ActiveHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                            PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                        }
                    }
                }
                ActiveHigh.isActive = false;
            }

            if (ActiveLow.isActive && HAClose[i] < ActiveLow.price)
            {
                if (!is_major_choch_dn)
                {
                    string bos_name = "IND_SMC_BOS_DN_" + IntegerToString((long)ActiveLow.time);
                    if (ObjectFind(0, bos_name) < 0)
                    {
                        CreateBOSLine(bos_name, ActiveLow.time, ActiveLow.price, time[i], BOS_Down_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                        PushBOS(BOSDnQueue, bos_name, MaxBOSLines);
                        MajorEventBuffer[i] = -1;
                        last_break_dir = -1;
                        last_break_type = 1;
                        latest_break_down_time = time[i];
                        latest_break_down_idx = i;
                        latest_break_down_level = ActiveLow.price;

                        // PATCH: Carry-forward BOS DN — reset phia up
                        last_bos_dn_level = ActiveLow.price;
                        last_bos_up_level = EMPTY_VALUE;

                        int origin_idx = last_maj_high_idx;
                        if (origin_idx != -1)
                        {
                            string zone_name = "IND_SMC_ZONE_SELL_BOS_" + IntegerToString((long)last_maj_high_time);
                            double zEntry, zStop;
                            CreateZone(zone_name, origin_idx, i, true, ActiveLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                            PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                        }
                    }
                }
                ActiveLow.isActive = false;
            }

            // =========================================================================
            // STRONG LEVEL UPDATE
            // =========================================================================
            if (major_trend == 1 && maj_strong_low != EMPTY_VALUE && HAClose[i] < maj_strong_low)
            {
                maj_strong_low = EMPTY_VALUE;
                maj_strong_low_time = 0;
                maj_strong_low_idx = -1;
                pending_strong_low_update = false;
            }
            if (major_trend == -1 && maj_strong_high != EMPTY_VALUE && HAClose[i] > maj_strong_high)
            {
                maj_strong_high = EMPTY_VALUE;
                maj_strong_high_time = 0;
                maj_strong_high_idx = -1;
                pending_strong_high_update = false;
            }
            if (is_major_choch_up)
            {
                maj_strong_low = maj_prot_low;
                maj_strong_low_time = maj_prot_low_time;
                maj_strong_low_idx = maj_prot_low_idx;
                last_strong_low_update_time = time[i];
                pending_strong_low_update = false;
                pending_weak_high_level = EMPTY_VALUE;
                processed_weak_high_time = 0;
            }
            if (is_major_choch_dn)
            {
                maj_strong_high = maj_prot_high;
                maj_strong_high_time = maj_prot_high_time;
                maj_strong_high_idx = maj_prot_high_idx;
                last_strong_high_update_time = time[i];
                pending_strong_high_update = false;
                pending_weak_low_level = EMPTY_VALUE;
                processed_weak_low_time = 0;
            }
            if (major_trend == 1 && pending_strong_low_update)
            {
                if (maj_confirmed_extreme_high != EMPTY_VALUE && maj_confirmed_extreme_high != pending_weak_high_level)
                {
                    pending_strong_low_update = false;
                }
            }
            if (major_trend == -1 && pending_strong_high_update)
            {
                if (maj_confirmed_extreme_low != EMPTY_VALUE && maj_confirmed_extreme_low != pending_weak_low_level)
                {
                    pending_strong_high_update = false;
                }
            }
            if (major_trend == 1 && pending_strong_low_update)
            {
                double min_swing_val = EMPTY_VALUE;
                datetime min_swing_time = 0;
                int min_swing_idx = -1;
                int end_idx = i;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] <= last_strong_low_update_time)
                    {
                        end_idx = k;
                        break;
                    }
                }
                for (int k = i; k <= end_idx; k++)
                {
                    if (majorSwingLow[k] != EMPTY_VALUE)
                    {
                        if (min_swing_val == EMPTY_VALUE || majorSwingLow[k] < min_swing_val)
                        {
                            min_swing_val = majorSwingLow[k];
                            min_swing_time = time[k];
                            min_swing_idx = k;
                        }
                    }
                }
                if (min_swing_val != EMPTY_VALUE)
                {
                    double absolute_min_val = EMPTY_VALUE;
                    datetime absolute_min_time = 0;
                    int absolute_min_idx = -1;
                    for (int k = i; k <= min_swing_idx; k++)
                    {
                        if (absolute_min_val == EMPTY_VALUE || low[k] < absolute_min_val)
                        {
                            absolute_min_val = low[k];
                            absolute_min_time = time[k];
                            absolute_min_idx = k;
                        }
                    }
                    if (absolute_min_val != EMPTY_VALUE && absolute_min_val < min_swing_val)
                    {
                        maj_strong_low = absolute_min_val;
                        maj_strong_low_time = absolute_min_time;
                        maj_strong_low_idx = absolute_min_idx;
                    }
                    else
                    {
                        maj_strong_low = min_swing_val;
                        maj_strong_low_time = min_swing_time;
                        maj_strong_low_idx = min_swing_idx;
                    }
                    last_strong_low_update_time = time[i];
                    pending_strong_low_update = false;
                }
            }
            if (major_trend == -1 && pending_strong_high_update)
            {
                double max_swing_val = EMPTY_VALUE;
                datetime max_swing_time = 0;
                int max_swing_idx = -1;
                int end_idx = i;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] <= last_strong_high_update_time)
                    {
                        end_idx = k;
                        break;
                    }
                }
                for (int k = i; k <= end_idx; k++)
                {
                    if (majorSwingHigh[k] != EMPTY_VALUE)
                    {
                        if (max_swing_val == EMPTY_VALUE || majorSwingHigh[k] > max_swing_val)
                        {
                            max_swing_val = majorSwingHigh[k];
                            max_swing_time = time[k];
                            max_swing_idx = k;
                        }
                    }
                }
                if (max_swing_val != EMPTY_VALUE)
                {
                    double absolute_max_val = EMPTY_VALUE;
                    datetime absolute_max_time = 0;
                    int absolute_max_idx = -1;
                    for (int k = i; k <= max_swing_idx; k++)
                    {
                        if (absolute_max_val == EMPTY_VALUE || high[k] > absolute_max_val)
                        {
                            absolute_max_val = high[k];
                            absolute_max_time = time[k];
                            absolute_max_idx = k;
                        }
                    }
                    if (absolute_max_val != EMPTY_VALUE && absolute_max_val > max_swing_val)
                    {
                        maj_strong_high = absolute_max_val;
                        maj_strong_high_time = absolute_max_time;
                        maj_strong_high_idx = absolute_max_idx;
                    }
                    else
                    {
                        maj_strong_high = max_swing_val;
                        maj_strong_high_time = max_swing_time;
                        maj_strong_high_idx = max_swing_idx;
                    }
                    last_strong_high_update_time = time[i];
                    pending_strong_high_update = false;
                }
            }
            if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE &&
                HAClose[i] > maj_confirmed_extreme_high &&
                processed_weak_high_time != maj_confirmed_extreme_high_time)
            {
                processed_weak_high_time = maj_confirmed_extreme_high_time;
                double min_swing_val = EMPTY_VALUE;
                datetime min_swing_time = 0;
                int min_swing_idx = -1;
                int end_idx = i;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] <= last_strong_low_update_time)
                    {
                        end_idx = k;
                        break;
                    }
                }
                for (int k = i; k <= end_idx; k++)
                {
                    if (majorSwingLow[k] != EMPTY_VALUE)
                    {
                        if (min_swing_val == EMPTY_VALUE || majorSwingLow[k] < min_swing_val)
                        {
                            min_swing_val = majorSwingLow[k];
                            min_swing_time = time[k];
                            min_swing_idx = k;
                        }
                    }
                }
                if (min_swing_val != EMPTY_VALUE)
                {
                    double absolute_min_val = EMPTY_VALUE;
                    datetime absolute_min_time = 0;
                    int absolute_min_idx = -1;
                    for (int k = i; k <= min_swing_idx; k++)
                    {
                        if (absolute_min_val == EMPTY_VALUE || low[k] < absolute_min_val)
                        {
                            absolute_min_val = low[k];
                            absolute_min_time = time[k];
                            absolute_min_idx = k;
                        }
                    }
                    if (absolute_min_val != EMPTY_VALUE && absolute_min_val < min_swing_val)
                    {
                        maj_strong_low = absolute_min_val;
                        maj_strong_low_time = absolute_min_time;
                        maj_strong_low_idx = absolute_min_idx;
                    }
                    else
                    {
                        maj_strong_low = min_swing_val;
                        maj_strong_low_time = min_swing_time;
                        maj_strong_low_idx = min_swing_idx;
                    }
                    last_strong_low_update_time = time[i];
                    pending_strong_low_update = false;
                }
                else
                {
                    pending_strong_low_update = true;
                    pending_weak_high_level = maj_confirmed_extreme_high;
                }
            }
            if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE &&
                HAClose[i] < maj_confirmed_extreme_low &&
                processed_weak_low_time != maj_confirmed_extreme_low_time)
            {
                processed_weak_low_time = maj_confirmed_extreme_low_time;
                double max_swing_val = EMPTY_VALUE;
                datetime max_swing_time = 0;
                int max_swing_idx = -1;
                int end_idx = i;
                for (int k = i; k < rates_total; k++)
                {
                    if (time[k] <= last_strong_high_update_time)
                    {
                        end_idx = k;
                        break;
                    }
                }
                for (int k = i; k <= end_idx; k++)
                {
                    if (majorSwingHigh[k] != EMPTY_VALUE)
                    {
                        if (max_swing_val == EMPTY_VALUE || majorSwingHigh[k] > max_swing_val)
                        {
                            max_swing_val = majorSwingHigh[k];
                            max_swing_time = time[k];
                            max_swing_idx = k;
                        }
                    }
                }
                if (max_swing_val != EMPTY_VALUE)
                {
                    double absolute_max_val = EMPTY_VALUE;
                    datetime absolute_max_time = 0;
                    int absolute_max_idx = -1;
                    for (int k = i; k <= max_swing_idx; k++)
                    {
                        if (absolute_max_val == EMPTY_VALUE || high[k] > absolute_max_val)
                        {
                            absolute_max_val = high[k];
                            absolute_max_time = time[k];
                            absolute_max_idx = k;
                        }
                    }
                    if (absolute_max_val != EMPTY_VALUE && absolute_max_val > max_swing_val)
                    {
                        maj_strong_high = absolute_max_val;
                        maj_strong_high_time = absolute_max_time;
                        maj_strong_high_idx = absolute_max_idx;
                    }
                    else
                    {
                        maj_strong_high = max_swing_val;
                        maj_strong_high_time = max_swing_time;
                        maj_strong_high_idx = max_swing_idx;
                    }
                    last_strong_high_update_time = time[i];
                    pending_strong_high_update = false;
                }
                else
                {
                    pending_strong_high_update = true;
                    pending_weak_low_level = maj_confirmed_extreme_low;
                }
            }

        } // Kết thúc block i > 0

        MajorTrendBuffer[i] = major_trend;
        MinorTrendBuffer[i] = minor_trend;
        MajorProtHighBuffer[i] = maj_prot_high;
        MajorProtLowBuffer[i] = maj_prot_low;
        MinorProtHighBuffer[i] = min_prot_high;
        MinorProtLowBuffer[i] = min_prot_low;

        if (ArraySize(BuyZonesQueue) > 0)
        {
            BuyZoneEntryBuffer[i] = BuyZonesQueue[0].entryPrice;
            BuyZoneSLBuffer[i] = BuyZonesQueue[0].stopPrice;
        }
        else
        {
            BuyZoneEntryBuffer[i] = EMPTY_VALUE;
            BuyZoneSLBuffer[i] = EMPTY_VALUE;
        }
        if (ArraySize(SellZonesQueue) > 0)
        {
            SellZoneSLBuffer[i] = SellZonesQueue[0].stopPrice;
            SellZoneEntryBuffer[i] = SellZonesQueue[0].entryPrice;
        }
        else
        {
            SellZoneSLBuffer[i] = EMPTY_VALUE;
            SellZoneEntryBuffer[i] = EMPTY_VALUE;
        }

        // PATCH: Ghi carry-forward buffer moi bar — EA doc [1] la co ngay
        BOS_Up_Level[i] = last_bos_up_level;
        BOS_Dn_Level[i] = last_bos_dn_level;
        CHOCH_Up_Level[i] = last_choch_up_level;
        CHOCH_Dn_Level[i] = last_choch_dn_level;

        if (i == 0)
        {
            if (major_trend == -1 && maj_prot_high != EMPTY_VALUE)
            {
                g_high_lvl = maj_prot_high;
                g_high_time = maj_prot_high_time;
                g_high_text = "Protected High";
            }
            else if (ActiveHigh.isActive)
            {
                g_high_lvl = ActiveHigh.price;
                g_high_time = ActiveHigh.time;
                g_high_text = "Active High";
            }
            else
            {
                g_high_lvl = EMPTY_VALUE;
            }
            if (major_trend == 1 && maj_prot_low != EMPTY_VALUE)
            {
                g_low_lvl = maj_prot_low;
                g_low_time = maj_prot_low_time;
                g_low_text = "Protected Low";
            }
            else if (ActiveLow.isActive)
            {
                g_low_lvl = ActiveLow.price;
                g_low_time = ActiveLow.time;
                g_low_text = "Active Low";
            }
            else
            {
                g_low_lvl = EMPTY_VALUE;
            }

            if (ShowTrackingLines)
            {
                CreateTrackingRayWithLabel("IND_SMC_TRACK_HIGH", g_high_time, g_high_lvl, TrackingLineColor, g_high_text, true, time[0]);
                CreateTrackingRayWithLabel("IND_SMC_TRACK_LOW", g_low_time, g_low_lvl, TrackingLineColor, g_low_text, false, time[0]);
                if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE)
                {
                    CreateTrackingRayWithLabel("IND_SMC_EXTREME_HIGH", maj_confirmed_extreme_high_time, maj_confirmed_extreme_high, clrOrange, "Weak High", false, time[0]);
                }
                else
                {
                    ObjectDelete(0, "IND_SMC_EXTREME_HIGH_ray");
                    ObjectDelete(0, "IND_SMC_EXTREME_HIGH_lbl");
                }
                if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE)
                {
                    CreateTrackingRayWithLabel("IND_SMC_EXTREME_LOW", maj_confirmed_extreme_low_time, maj_confirmed_extreme_low, clrOrange, "Weak Low", true, time[0]);
                }
                else
                {
                    ObjectDelete(0, "IND_SMC_EXTREME_LOW_ray");
                    ObjectDelete(0, "IND_SMC_EXTREME_LOW_lbl");
                }
                if (major_trend == -1 && maj_strong_high != EMPTY_VALUE)
                {
                    CreateTrackingRayWithLabel("IND_SMC_STRONG_HIGH", maj_strong_high_time, maj_strong_high, StrongHighColor, "Strong High", false, time[0]);
                    if (maj_strong_high_idx != -1)
                        CreateStrongZone("IND_SMC_ACTIVE_STRONG_SELL_ZONE", maj_strong_high_idx, true, time, HAHigh, HALow, HAColor, rates_total);
                }
                else
                {
                    ObjectDelete(0, "IND_SMC_STRONG_HIGH_ray");
                    ObjectDelete(0, "IND_SMC_STRONG_HIGH_lbl");
                    ObjectDelete(0, "IND_SMC_ACTIVE_STRONG_SELL_ZONE");
                }
                if (major_trend == 1 && maj_strong_low != EMPTY_VALUE)
                {
                    CreateTrackingRayWithLabel("IND_SMC_STRONG_LOW", maj_strong_low_time, maj_strong_low, StrongLowColor, "Strong Low", true, time[0]);
                    if (maj_strong_low_idx != -1)
                        CreateStrongZone("IND_SMC_ACTIVE_STRONG_BUY_ZONE", maj_strong_low_idx, false, time, HAHigh, HALow, HAColor, rates_total);
                }
                else
                {
                    ObjectDelete(0, "IND_SMC_STRONG_LOW_ray");
                    ObjectDelete(0, "IND_SMC_STRONG_LOW_lbl");
                    ObjectDelete(0, "IND_SMC_ACTIVE_STRONG_BUY_ZONE");
                }
                if (MQLInfoInteger(MQL_TESTER))
                    ChartRedraw(0);
            }
            else
            {
                ObjectDelete(0, "IND_SMC_TRACK_HIGH_ray");
                ObjectDelete(0, "IND_SMC_TRACK_HIGH_lbl");
                ObjectDelete(0, "IND_SMC_TRACK_LOW_ray");
                ObjectDelete(0, "IND_SMC_TRACK_LOW_lbl");
                ObjectDelete(0, "IND_SMC_EXTREME_HIGH_ray");
                ObjectDelete(0, "IND_SMC_EXTREME_HIGH_lbl");
                ObjectDelete(0, "IND_SMC_EXTREME_LOW_ray");
                ObjectDelete(0, "IND_SMC_EXTREME_LOW_lbl");
                ObjectDelete(0, "IND_SMC_STRONG_HIGH_ray");
                ObjectDelete(0, "IND_SMC_STRONG_HIGH_lbl");
                ObjectDelete(0, "IND_SMC_STRONG_LOW_ray");
                ObjectDelete(0, "IND_SMC_STRONG_LOW_lbl");
                ObjectDelete(0, "IND_SMC_ACTIVE_STRONG_SELL_ZONE");
                ObjectDelete(0, "IND_SMC_ACTIVE_STRONG_BUY_ZONE");
            }
        }
    }
    return (rates_total);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if (id == CHARTEVENT_CHART_CHANGE)
    {
        if (ShowTrackingLines)
        {
            datetime t[];
            if (CopyTime(_Symbol, _Period, 0, 1, t) > 0)
            {
                CreateTrackingRayWithLabel("IND_SMC_TRACK_HIGH", g_high_time, g_high_lvl, TrackingLineColor, g_high_text, true, t[0]);
                CreateTrackingRayWithLabel("IND_SMC_TRACK_LOW", g_low_time, g_low_lvl, TrackingLineColor, g_low_text, false, t[0]);
                if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE)
                    CreateTrackingRayWithLabel("IND_SMC_EXTREME_HIGH", maj_confirmed_extreme_high_time, maj_confirmed_extreme_high, clrOrange, "Weak High", false, t[0]);
                if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE)
                    CreateTrackingRayWithLabel("IND_SMC_EXTREME_LOW", maj_confirmed_extreme_low_time, maj_confirmed_extreme_low, clrOrange, "Weak Low", true, t[0]);
                if (major_trend == -1 && maj_strong_high != EMPTY_VALUE)
                    CreateTrackingRayWithLabel("IND_SMC_STRONG_HIGH", maj_strong_high_time, maj_strong_high, StrongHighColor, "Strong High", false, t[0]);
                if (major_trend == 1 && maj_strong_low != EMPTY_VALUE)
                    CreateTrackingRayWithLabel("IND_SMC_STRONG_LOW", maj_strong_low_time, maj_strong_low, StrongLowColor, "Strong Low", true, t[0]);
                ChartRedraw();
            }
        }
    }
}

datetime GetRightEdgeTime(datetime current_time)
{
    if (MQLInfoInteger(MQL_TESTER))
        return current_time + PeriodSeconds() * 15;
    int width = (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS);
    int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
    int future_offset = width - first - 2;
    if (future_offset < 1)
        future_offset = 1;
    return current_time + future_offset * PeriodSeconds();
}

void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time)
{
    if (p1 == EMPTY_VALUE || t1 == 0)
    {
        ObjectDelete(0, name + "_ray");
        ObjectDelete(0, name + "_lbl");
        return;
    }
    string ray_name = name + "_ray";
    if (ObjectFind(0, ray_name) < 0)
    {
        ObjectCreate(0, ray_name, OBJ_TREND, 0, t1, p1, current_time + PeriodSeconds(), p1);
        ObjectSetInteger(0, ray_name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, ray_name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, ray_name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, ray_name, OBJPROP_RAY_RIGHT, true);
        ObjectSetInteger(0, ray_name, OBJPROP_BACK, false);
    }
    else
    {
        ObjectSetInteger(0, ray_name, OBJPROP_TIME, 0, t1);
        ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 0, p1);
        ObjectSetInteger(0, ray_name, OBJPROP_TIME, 1, current_time + PeriodSeconds());
        ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 1, p1);
    }
    string lbl_name = name + "_lbl";
    datetime label_time = GetRightEdgeTime(current_time);
    if (ObjectFind(0, lbl_name) < 0)
    {
        ObjectCreate(0, lbl_name, OBJ_TEXT, 0, label_time, p1);
        ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, lbl_name, OBJPROP_BACK, false);
        ObjectSetInteger(0, lbl_name, OBJPROP_SELECTABLE, false);
    }
    else
    {
        ObjectSetInteger(0, lbl_name, OBJPROP_TIME, 0, label_time);
        ObjectSetDouble(0, lbl_name, OBJPROP_PRICE, 0, p1);
    }
    ObjectSetString(0, lbl_name, OBJPROP_TEXT, text + "  ");
    ObjectSetInteger(0, lbl_name, OBJPROP_ANCHOR, isDown ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
}

void ClearQueue(string &queue[])
{
    for (int i = 0; i < ArraySize(queue); i++)
    {
        ObjectDelete(0, queue[i]);
        ObjectDelete(0, queue[i] + "_lbl");
    }
    ArrayResize(queue, 0);
}
void ClearZoneQueue(TZone &queue[])
{
    for (int i = 0; i < ArraySize(queue); i++)
    {
        ObjectDelete(0, queue[i].name);
    }
    ArrayResize(queue, 0);
}
void PushBOS(string &queue[], string name, int max_count)
{
    for (int i = 0; i < ArraySize(queue); i++)
        if (queue[i] == name)
            return;
    int size = ArraySize(queue);
    ArrayResize(queue, size + 1);
    queue[size] = name;
    if (ArraySize(queue) > max_count)
    {
        ObjectDelete(0, queue[0]);
        ObjectDelete(0, queue[0] + "_lbl");
        for (int i = 0; i < ArraySize(queue) - 1; i++)
            queue[i] = queue[i + 1];
        ArrayResize(queue, ArraySize(queue) - 1);
    }
}
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count)
{
    for (int i = 0; i < ArraySize(queue); i++)
    {
        if (queue[i].name == name)
        {
            queue[i].entryPrice = entry;
            queue[i].stopPrice = stop;
            return;
        }
    }
    int size = ArraySize(queue);
    ArrayResize(queue, size + 1);
    queue[size].name = name;
    queue[size].entryPrice = entry;
    queue[size].stopPrice = stop;
    if (ArraySize(queue) > max_count)
    {
        ObjectDelete(0, queue[0].name);
        for (int i = 0; i < ArraySize(queue) - 1; i++)
            queue[i] = queue[i + 1];
        ArrayResize(queue, ArraySize(queue) - 1);
    }
}
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize)
{
    ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p1);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    datetime t_mid = t1 + (t2 - t1) / 2;
    string lbl = name + "_lbl";
    ObjectCreate(0, lbl, OBJ_TEXT, 0, t_mid, p1);
    ObjectSetString(0, lbl, OBJPROP_TEXT, text);
    ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
}
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown)
{
    ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t1 + PeriodSeconds() * 100, p1);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    string lbl = name + "_lbl";
    ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, p1);
    ObjectSetString(0, lbl, OBJPROP_TEXT, " " + text);
    ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isDown ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
}

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop)
{
    int ext_idx = swing_idx;
    if (bos_idx >= 0 && swing_idx >= bos_idx)
    {
        int count = swing_idx - bos_idx + 1;
        if (isSellZone)
            ext_idx = ArrayMaximum(h, bos_idx, count);
        else
            ext_idx = ArrayMinimum(l, bos_idx, count);
    }
    double actual_broken_level = broken_level;
    if ((actual_broken_level <= 0 || actual_broken_level == EMPTY_VALUE) && bos_idx >= 0 && swing_idx > bos_idx)
    {
        int check_count = swing_idx - bos_idx;
        if (isSellZone)
        {
            int brk_idx = ArrayMinimum(l, bos_idx + 1, check_count);
            if (brk_idx != -1)
                actual_broken_level = l[brk_idx];
        }
        else
        {
            int brk_idx = ArrayMaximum(h, bos_idx + 1, check_count);
            if (brk_idx != -1)
                actual_broken_level = h[brk_idx];
        }
    }
    int targetColor = isSellZone ? 0 : 1;
    int k = ext_idx;
    double zHigh = ha_h[ext_idx];
    double zLow = ha_l[ext_idx];
    while (k < total && ha_color[k] != targetColor && k <= ext_idx + 10)
    {
        k++;
    }
    if (k <= ext_idx + 10 && k < total)
    {
        if (isSellZone)
        {
            zLow = ha_l[k];
            while (k < total && ha_color[k] == targetColor)
            {
                zLow = MathMin(zLow, ha_l[k]);
                k++;
            }
            zHigh = MathMax(zHigh, ha_h[ext_idx]);
        }
        else
        {
            zHigh = ha_h[k];
            while (k < total && ha_color[k] == targetColor)
            {
                zHigh = MathMax(zHigh, ha_h[k]);
                k++;
            }
            zLow = MathMin(zLow, ha_l[ext_idx]);
        }
    }
    if (actual_broken_level > 0 && actual_broken_level != EMPTY_VALUE)
    {
        if (isSellZone && zLow <= actual_broken_level + _Point)
        {
            zHigh = ha_h[ext_idx];
            zLow = ha_l[ext_idx];
        }
        else if (!isSellZone && zHigh >= actual_broken_level - _Point)
        {
            zHigh = ha_h[ext_idx];
            zLow = ha_l[ext_idx];
        }
    }
    out_stop = isSellZone ? zHigh : zLow;
    out_entry = isSellZone ? zLow : zHigh;
    if (ObjectFind(0, name) >= 0)
    {
        double old_zHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
        double old_zLow = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
        if (MathAbs(old_zHigh - zHigh) < _Point && MathAbs(old_zLow - zLow) < _Point)
            return;
        ObjectDelete(0, name);
    }
    datetime tStart = time[ext_idx];
    datetime tEnd = time[0] + PeriodSeconds() * 1000;
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
    ObjectSetInteger(0, name, OBJPROP_COLOR, isSellZone ? SellZoneColor : BuyZoneColor);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void CreateStrongZone(string name, int ext_idx, bool isSellZone, const datetime &time[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total)
{
    if (ext_idx < 0 || ext_idx >= total)
        return;
    int targetColor = isSellZone ? 0 : 1;
    int k = ext_idx;
    double zHigh = ha_h[ext_idx];
    double zLow = ha_l[ext_idx];
    while (k < total && ha_color[k] != targetColor && k <= ext_idx + 10)
    {
        k++;
    }
    if (k <= ext_idx + 10 && k < total)
    {
        if (isSellZone)
        {
            zLow = ha_l[k];
            while (k < total && ha_color[k] == targetColor)
            {
                zLow = MathMin(zLow, ha_l[k]);
                k++;
            }
            zHigh = MathMax(zHigh, ha_h[ext_idx]);
        }
        else
        {
            zHigh = ha_h[k];
            while (k < total && ha_color[k] == targetColor)
            {
                zHigh = MathMax(zHigh, ha_h[k]);
                k++;
            }
            zLow = MathMin(zLow, ha_l[ext_idx]);
        }
    }
    datetime tStart = time[ext_idx];
    datetime tEnd = time[0] + PeriodSeconds() * 1000;
    if (ObjectFind(0, name) >= 0)
    {
        double old_zHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
        double old_zLow = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
        datetime old_tStart = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
        if (MathAbs(old_zHigh - zHigh) < _Point && MathAbs(old_zLow - zLow) < _Point && old_tStart == tStart)
            return;
        ObjectDelete(0, name);
    }
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
    ObjectSetInteger(0, name, OBJPROP_COLOR, isSellZone ? StrongSellZoneColor : StrongBuyZoneColor);
    ObjectSetInteger(0, name, OBJPROP_FILL, false); // Nền rỗng, để lộ Zone sóng phụ
    ObjectSetInteger(0, name, OBJPROP_BACK, false); // Không chìm xuống dưới
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);    // Viền dày 2px
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
}
//+------------------------------------------------------------------+