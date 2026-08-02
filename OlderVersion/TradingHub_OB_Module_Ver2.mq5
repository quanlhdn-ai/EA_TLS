//+------------------------------------------------------------------+
//|                                  Combo_MajorSwing_HA_BOS_Zone_V80|
//|                                  Focus: Cache Buster & Perfect Sync|
//|                                  Status: Ultimate SMC Master + OB  |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "30.80" // Phiên bản V80 tích hợp OB
#property indicator_chart_window

#property indicator_buffers 22
#property indicator_plots   18

#property indicator_type1   DRAW_ARROW
#property indicator_type2   DRAW_ARROW
#property indicator_type3   DRAW_LINE
#property indicator_type4   DRAW_NONE
#property indicator_color1   C'80,80,80' 
#property indicator_color2   C'80,80,80' 
#property indicator_color4  C'8,153,129', C'242,54,69' 

#property indicator_type5   DRAW_ARROW
#property indicator_type6   DRAW_ARROW
#property indicator_color5   C'0,190,190' 
#property indicator_color6   C'0,190,190' 

#property indicator_type7   DRAW_NONE
#property indicator_type8   DRAW_NONE
#property indicator_type9   DRAW_NONE
#property indicator_type10  DRAW_NONE
#property indicator_type11  DRAW_NONE
#property indicator_type12  DRAW_NONE
#property indicator_type13  DRAW_NONE
#property indicator_type14  DRAW_NONE
#property indicator_type15  DRAW_NONE
#property indicator_type16  DRAW_NONE
#property indicator_type17  DRAW_NONE
#property indicator_type18  DRAW_NONE

input group "--- Display Toggles (Công tắc Hiển thị) ---"
input bool  ShowEMA               = true;  // Hiển thị đường EMA
input bool  ShowZones             = true;  // Hiển thị hộp Supply/Demand Zone

input group "--- Major Swing Settings ---"
input color MajorSwingColor       = C'80,80,80'; 
input int   MajorSwingSize        = 5;          
input int   PeriodsInMajorSwing   = 9;

input group "--- Structure Tracking Graphics (RAY) ---"
input bool  ShowTrackingLines     = true;        
input color TrackingLineColor     = clrMagenta; 

input group "--- Structure Settings (BOS/CHOCH) ---"
input int   MaxBOSLines           = 5;          
input color BOS_Up_Color          = clrDodgerBlue;
input color BOS_Down_Color        = clrRed;
input color KeyLevel_Color        = clrOrange; 

input group "--- SD Zone Settings ---"
input int   MaxZones              = 1;          
input color BuyZoneColor          = C'190,235,210'; 
input color SellZoneColor         = C'255,200,200'; 

// --- [THÊM MỚI TỪ V100]: CẤU HÌNH ORDER BLOCK ---
input group "--- Valid Order Block Settings ---"
input bool   EnableOB              = true;            
input color  BuyOB_Color           = C'255,250,205'; 
input color  SellOB_Color          = C'255,250,205'; 

input group "--- Minor Swing Settings (Trigger) ---"
input bool  ShowMinorStructure    = true;        
input int   PeriodsInMinorSwing   = 5;          
input int   MinorSwingSize        = 1;          
input int   MaxMinorBOSLines      = 3;          
input color Minor_BOS_Up_Color    = C'120,220,220'; 
input color Minor_BOS_Down_Color  = C'255,180,180'; 

input group "--- Moving Average ---"
input int   MovingAveragePeriods  = 21;
input color MovingAvergeColor     = C'80,80,80';

input group "--- Heiken Ashi (TV Colors) ---"
input bool  ShowHACandles         = false; // Hiển thị nến Heiken Ashi
input color InpBullColor          = C'8,153,129'; 
input color InpBearColor          = C'242,54,69'; 

double majorSwingHigh[], majorSwingLow[], EMA_Buffer[];
double HAOpen[], HAHigh[], HALow[], HAClose[], HAColor[];
double minorSwingHigh[], minorSwingLow[];

double MajorTrendBuffer[], MinorTrendBuffer[];
double MajorEventBuffer[], MinorEventBuffer[];
double MajorProtHighBuffer[], MajorProtLowBuffer[];
double MinorProtHighBuffer[], MinorProtLowBuffer[];
double BuyZoneEntryBuffer[], BuyZoneSLBuffer[];
double SellZoneSLBuffer[], SellZoneEntryBuffer[];

int ma_handle;
int lookBackMajor, lookBackMinor;

struct TSwing { double price; datetime time; bool isActive; int idx; };
struct TZone  { string name; double entryPrice; double stopPrice; };

// --- [THÊM MỚI TỪ V100]: STRUCT ORDER BLOCK ---
struct ActiveOB {
    string name;
    datetime time; 
    double top;
    double bottom;
    bool isBull;
};
ActiveOB liveOBs[];
bool pending_purge = false;

TSwing ActiveHigh = {EMPTY_VALUE, 0, false, -1}; TSwing ActiveLow  = {EMPTY_VALUE, 0, false, -1};
TSwing ActiveMinorHigh = {EMPTY_VALUE, 0, false, -1}; TSwing ActiveMinorLow  = {EMPTY_VALUE, 0, false, -1};

string BOSUpQueue[]; string BOSDnQueue[];
TZone BuyZonesQueue[]; TZone SellZonesQueue[];
string MinorBOSUpQueue[]; string MinorBOSDnQueue[];

datetime last_processed_high_time = 0; 
datetime last_processed_low_time = 0;  

int last_break_dir = 0; 
int last_break_type = 0; 
datetime latest_break_up_time = 0; int latest_break_up_idx = -1; double latest_break_up_level = EMPTY_VALUE;
datetime latest_break_down_time = 0; int latest_break_down_idx = -1; double latest_break_down_level = EMPTY_VALUE;

int major_trend = 0; 
double maj_prot_high = EMPTY_VALUE; datetime maj_prot_high_time = 0; int maj_prot_high_idx = -1;
double maj_prot_low = EMPTY_VALUE;  datetime maj_prot_low_time = 0;  int maj_prot_low_idx = -1;
double maj_extreme_high = EMPTY_VALUE;   datetime maj_extreme_high_time = 0; int maj_extreme_high_idx = -1;
double maj_extreme_low = EMPTY_VALUE;    datetime maj_extreme_low_time = 0;  int maj_extreme_low_idx = -1;
double last_maj_high = EMPTY_VALUE; datetime last_maj_high_time = 0; int last_maj_high_idx = -1;
double last_maj_low = EMPTY_VALUE;  datetime last_maj_low_time = 0;  int last_maj_low_idx = -1;

int minor_trend = 0; 
double min_prot_high = EMPTY_VALUE; datetime min_prot_high_time = 0; int min_prot_high_idx = -1;
double min_prot_low = EMPTY_VALUE;  datetime min_prot_low_time = 0;  int min_prot_low_idx = -1;
double min_extreme_high = EMPTY_VALUE;   datetime min_extreme_high_time = 0; int min_extreme_high_idx = -1;
double min_extreme_low = EMPTY_VALUE;    datetime min_extreme_low_time = 0;  int min_extreme_low_idx = -1;
double last_min_high = EMPTY_VALUE; datetime last_min_high_time = 0; int last_min_high_idx = -1;
double last_min_low = EMPTY_VALUE;  datetime last_min_low_time = 0;  int last_min_low_idx = -1;

double g_high_lvl = EMPTY_VALUE; datetime g_high_time = 0; string g_high_text = "";
double g_low_lvl = EMPTY_VALUE;  datetime g_low_time = 0;  string g_low_text = "";

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop);
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize);
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown);
void PushBOS(string &queue[], string name, int max_count);
void ClearQueue(string &queue[]);
void ClearZoneQueue(TZone &queue[]);
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count);
void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time);
datetime GetRightEdgeTime(datetime current_time);

// ==============================================================================
// CÁC HÀM XỬ LÝ ORDER BLOCK TỪ V100
// ==============================================================================
void DrawOBBox(string name, datetime t1, double top, double bot, bool isBull, string lbl_text, color obColor) {
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, TimeCurrent() + PeriodSeconds()*1000, bot);
    ObjectSetInteger(0, name, OBJPROP_COLOR, obColor);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    string lbl = name + "_LBL";
    ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, isBull ? bot : top);
    ObjectSetString(0, lbl, OBJPROP_TEXT, lbl_text);
    ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isBull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
}

void PurgeOBsBeforeTime(datetime threshold_time) {
    for(int obj = ArraySize(liveOBs) - 1; obj >= 0; obj--) {
        if (liveOBs[obj].time < threshold_time) {
            ObjectDelete(0, liveOBs[obj].name);
            ObjectDelete(0, liveOBs[obj].name + "_LBL");
            ArrayRemove(liveOBs, obj, 1);
        }
    }
}

bool CheckAndDrawSingleOB(int idx, bool isBull, const double &h[], const double &l[], const double &o[], const double &c[], const datetime &t[], int current_i) {
    if (idx < 1 || idx >= ArraySize(h) - 1) return false;
    if (isBull) {
        if (c[idx+1] < o[idx+1] && l[idx] < l[idx+1] && h[idx+1] < l[idx-1]) {
            double ob_top = h[idx+1]; double ob_bot = l[idx];   
            string name = "OB_MASTER_OB_BULL_" + IntegerToString((long)t[idx+1]);
            if (ObjectFind(0, name) >= 0) return true; 
            bool mitigated = false;
            for (int m = idx - 1; m >= current_i; m--) { if (l[m] <= ob_top) { mitigated = true; break; } }
            if (!mitigated) {
                DrawOBBox(name, t[idx+1], ob_top, ob_bot, true, " Buy OB", BuyOB_Color);
                int sz = ArraySize(liveOBs); ArrayResize(liveOBs, sz + 1);
                liveOBs[sz].name = name; liveOBs[sz].time = t[idx+1]; liveOBs[sz].top = ob_top; liveOBs[sz].bottom = ob_bot; liveOBs[sz].isBull = true;
                return true;
            }
        }
    } else {
        if (c[idx+1] > o[idx+1] && h[idx] > h[idx+1] && l[idx+1] > h[idx-1]) {
            double ob_top = h[idx]; double ob_bot = l[idx+1]; 
            string name = "OB_MASTER_OB_BEAR_" + IntegerToString((long)t[idx+1]);
            if (ObjectFind(0, name) >= 0) return true;
            bool mitigated = false;
            for (int m = idx - 1; m >= current_i; m--) { if (h[m] >= ob_bot) { mitigated = true; break; } }
            if (!mitigated) {
                DrawOBBox(name, t[idx+1], ob_top, ob_bot, false, " Sell OB", SellOB_Color);
                int sz = ArraySize(liveOBs); ArrayResize(liveOBs, sz + 1);
                liveOBs[sz].name = name; liveOBs[sz].time = t[idx+1]; liveOBs[sz].top = ob_top; liveOBs[sz].bottom = ob_bot; liveOBs[sz].isBull = false;
                return true;
            }
        }
    }
    return false;
}

void FindAndDrawOriginOBs(int break_idx, int origin_idx, bool isBull, const double &h[], const double &l[], const double &o[], const double &c[], const datetime &t[]) {
    if (!EnableOB || origin_idx == -1 || origin_idx <= break_idx) return;
    for (int k = origin_idx; k > break_idx; k--) { CheckAndDrawSingleOB(k, isBull, h, l, o, c, t, break_idx); }
}
// ==============================================================================

int OnInit()
{
   ObjectsDeleteAll(0, "OB_MASTER_"); 
   ObjectsDeleteAll(0, "OB_MASTER_"); 
   ArrayResize(liveOBs, 0); 
   pending_purge = false;

   lookBackMajor = PeriodsInMajorSwing * 2; lookBackMinor = PeriodsInMinorSwing * 2; 
   
   SetIndexBuffer(0, majorSwingHigh, INDICATOR_DATA); PlotIndexSetInteger(0, PLOT_ARROW, 159); PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MajorSwingSize); PlotIndexSetInteger(0, PLOT_LINE_COLOR, MajorSwingColor); PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE); 
   SetIndexBuffer(1, majorSwingLow, INDICATOR_DATA); PlotIndexSetInteger(1, PLOT_ARROW, 159); PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MajorSwingSize); PlotIndexSetInteger(1, PLOT_LINE_COLOR, MajorSwingColor); PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE); 
   SetIndexBuffer(2, EMA_Buffer, INDICATOR_DATA); 
   if(!ShowEMA) {
       PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE); // Ẩn EMA
   } else {
       PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_LINE); // Hiện EMA
       PlotIndexSetInteger(2, PLOT_LINE_COLOR, MovingAvergeColor);
   }
   // --- CẤU HÌNH BỘ ĐỆM CHO NẾN HA ---
   SetIndexBuffer(3, HAOpen, INDICATOR_DATA); SetIndexBuffer(4, HAHigh, INDICATOR_DATA); SetIndexBuffer(5, HALow, INDICATOR_DATA); SetIndexBuffer(6, HAClose, INDICATOR_DATA); SetIndexBuffer(7, HAColor, INDICATOR_COLOR_INDEX);
   
   // Bắt buộc gán Plot 3 là dạng nến (DRAW_COLOR_CANDLES) để MT5 gom 4 bộ đệm lại, tránh bị rác chấm li ti
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES); 
   
   // Dùng màu "tàng hình" (clrNONE) để ẩn nến đi thay vì tắt DRAW_TYPE
   if(!ShowHACandles) { 
       PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, clrNONE); 
       PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, clrNONE); 
   } else { 
       PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpBullColor); 
       PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpBearColor); 
   }
   
   // --- CẤU HÌNH BỘ ĐỆM CHO MINOR SWING ---
   SetIndexBuffer(8, minorSwingHigh, INDICATOR_DATA); PlotIndexSetInteger(4, PLOT_ARROW, 159); PlotIndexSetInteger(4, PLOT_LINE_WIDTH, MinorSwingSize); PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE); 
   SetIndexBuffer(9, minorSwingLow, INDICATOR_DATA);  PlotIndexSetInteger(5, PLOT_ARROW, 159); PlotIndexSetInteger(5, PLOT_LINE_WIDTH, MinorSwingSize); PlotIndexSetDouble(9, PLOT_EMPTY_VALUE, EMPTY_VALUE); 
   if(!ShowMinorStructure) { PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE); PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE); } 
   else { PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_ARROW); PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_ARROW); }

   // --- KHAI BÁO NHÃN VÀ CÁC BỘ ĐỆM DATA NGẦM ---
   PlotIndexSetString(0, PLOT_LABEL, "Major Swing High"); PlotIndexSetString(1, PLOT_LABEL, "Major Swing Low");
   PlotIndexSetString(2, PLOT_LABEL, "EMA"); PlotIndexSetString(3, PLOT_LABEL, "HA Open;HA High;HA Low;HA Close"); 
   PlotIndexSetString(4, PLOT_LABEL, "Minor Swing High"); PlotIndexSetString(5, PLOT_LABEL, "Minor Swing Low");
   
   SetIndexBuffer(10, MajorTrendBuffer, INDICATOR_DATA); PlotIndexSetString(6, PLOT_LABEL, "Major Trend");
   SetIndexBuffer(11, MinorTrendBuffer, INDICATOR_DATA); PlotIndexSetString(7, PLOT_LABEL, "Minor Trend");
   SetIndexBuffer(12, MajorEventBuffer, INDICATOR_DATA); PlotIndexSetString(8, PLOT_LABEL, "Major Event");
   SetIndexBuffer(13, MinorEventBuffer, INDICATOR_DATA); PlotIndexSetString(9, PLOT_LABEL, "Minor Event");
   SetIndexBuffer(14, MajorProtHighBuffer, INDICATOR_DATA); PlotIndexSetString(10, PLOT_LABEL, "Major KeyLevel High");
   SetIndexBuffer(15, MajorProtLowBuffer, INDICATOR_DATA);  PlotIndexSetString(11, PLOT_LABEL, "Major KeyLevel Low");
   SetIndexBuffer(16, MinorProtHighBuffer, INDICATOR_DATA); PlotIndexSetString(12, PLOT_LABEL, "Minor Prot High");
   SetIndexBuffer(17, MinorProtLowBuffer, INDICATOR_DATA);  PlotIndexSetString(13, PLOT_LABEL, "Minor Prot Low");
   SetIndexBuffer(18, BuyZoneEntryBuffer, INDICATOR_DATA);  PlotIndexSetString(14, PLOT_LABEL, "Buy Zone Entry");
   SetIndexBuffer(19, BuyZoneSLBuffer, INDICATOR_DATA);     PlotIndexSetString(15, PLOT_LABEL, "Buy Zone SL");
   SetIndexBuffer(20, SellZoneSLBuffer, INDICATOR_DATA);    PlotIndexSetString(16, PLOT_LABEL, "Sell Zone SL");
   SetIndexBuffer(21, SellZoneEntryBuffer, INDICATOR_DATA); PlotIndexSetString(17, PLOT_LABEL, "Sell Zone Entry");

   ma_handle = iMA(_Symbol, _Period, MovingAveragePeriods, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
    ObjectsDeleteAll(0, "OB_MASTER_"); 
    ObjectsDeleteAll(0, "OB_MASTER_"); 
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   int lookBack_max = MathMax(lookBackMajor, lookBackMinor);
   if(rates_total < lookBack_max + 1) return(0);

   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(open, true); ArraySetAsSeries(close, true); ArraySetAsSeries(time, true);
   ArraySetAsSeries(majorSwingHigh, true); ArraySetAsSeries(majorSwingLow, true); ArraySetAsSeries(EMA_Buffer, true);
   ArraySetAsSeries(HAOpen, true); ArraySetAsSeries(HAHigh, true); ArraySetAsSeries(HALow, true); ArraySetAsSeries(HAClose, true); ArraySetAsSeries(HAColor, true);
   ArraySetAsSeries(minorSwingHigh, true); ArraySetAsSeries(minorSwingLow, true);
   
   ArraySetAsSeries(MajorTrendBuffer, true); ArraySetAsSeries(MinorTrendBuffer, true);
   ArraySetAsSeries(MajorEventBuffer, true); ArraySetAsSeries(MinorEventBuffer, true);
   ArraySetAsSeries(MajorProtHighBuffer, true); ArraySetAsSeries(MajorProtLowBuffer, true);
   ArraySetAsSeries(MinorProtHighBuffer, true); ArraySetAsSeries(MinorProtLowBuffer, true);
   ArraySetAsSeries(BuyZoneEntryBuffer, true); ArraySetAsSeries(BuyZoneSLBuffer, true);
   ArraySetAsSeries(SellZoneSLBuffer, true); ArraySetAsSeries(SellZoneEntryBuffer, true);

   if(prev_calculated == 0) {
      ObjectsDeleteAll(0, "OB_MASTER_");
      ObjectsDeleteAll(0, "OB_MASTER_");
      ArrayResize(liveOBs, 0);
      pending_purge = false;

      ArrayInitialize(majorSwingHigh, EMPTY_VALUE); ArrayInitialize(majorSwingLow, EMPTY_VALUE);
      ArrayInitialize(minorSwingHigh, EMPTY_VALUE); ArrayInitialize(minorSwingLow, EMPTY_VALUE);
      ArrayInitialize(MajorTrendBuffer, EMPTY_VALUE); ArrayInitialize(MinorTrendBuffer, EMPTY_VALUE);
      ArrayInitialize(MajorEventBuffer, 0); ArrayInitialize(MinorEventBuffer, 0); 
      ArrayInitialize(MajorProtHighBuffer, EMPTY_VALUE); ArrayInitialize(MajorProtLowBuffer, EMPTY_VALUE);
      ArrayInitialize(MinorProtHighBuffer, EMPTY_VALUE); ArrayInitialize(MinorProtLowBuffer, EMPTY_VALUE);
      ArrayInitialize(BuyZoneEntryBuffer, EMPTY_VALUE); ArrayInitialize(BuyZoneSLBuffer, EMPTY_VALUE);
      ArrayInitialize(SellZoneSLBuffer, EMPTY_VALUE); ArrayInitialize(SellZoneEntryBuffer, EMPTY_VALUE);
      
      ActiveHigh.isActive = false; ActiveLow.isActive = false; ActiveMinorHigh.isActive = false; ActiveMinorLow.isActive = false; 
      ActiveHigh.idx = -1; ActiveLow.idx = -1; ActiveMinorHigh.idx = -1; ActiveMinorLow.idx = -1;
      
      major_trend = 0; maj_prot_high = EMPTY_VALUE; maj_prot_low = EMPTY_VALUE; maj_extreme_high = EMPTY_VALUE; maj_extreme_low = EMPTY_VALUE; last_maj_high = EMPTY_VALUE; last_maj_low = EMPTY_VALUE;
      maj_prot_high_idx = -1; maj_prot_low_idx = -1; maj_extreme_high_idx = -1; maj_extreme_low_idx = -1; last_maj_high_idx = -1; last_maj_low_idx = -1;

      minor_trend = 0; min_prot_high = EMPTY_VALUE; min_prot_low = EMPTY_VALUE; min_extreme_high = EMPTY_VALUE; min_extreme_low = EMPTY_VALUE; last_min_high = EMPTY_VALUE; last_min_low = EMPTY_VALUE;
      min_prot_high_idx = -1; min_prot_low_idx = -1; min_extreme_high_idx = -1; min_extreme_low_idx = -1; last_min_high_idx = -1; last_min_low_idx = -1;
      
      last_processed_high_time = 0; last_processed_low_time = 0; 
      last_break_dir = 0; last_break_type = 0;
      latest_break_up_time = 0; latest_break_up_idx = -1; latest_break_up_level = EMPTY_VALUE;
      latest_break_down_time = 0; latest_break_down_idx = -1; latest_break_down_level = EMPTY_VALUE;

      ArrayResize(BOSUpQueue, 0); ArrayResize(BOSDnQueue, 0); ArrayResize(BuyZonesQueue, 0); ArrayResize(SellZonesQueue, 0);
      ArrayResize(MinorBOSUpQueue, 0); ArrayResize(MinorBOSDnQueue, 0); 
   }

   if (prev_calculated > 0 && rates_total > prev_calculated) {
      int shift = rates_total - prev_calculated;
      if(ActiveHigh.idx >= 0) ActiveHigh.idx += shift;
      if(ActiveLow.idx >= 0) ActiveLow.idx += shift;
      if(ActiveMinorHigh.idx >= 0) ActiveMinorHigh.idx += shift;
      if(ActiveMinorLow.idx >= 0) ActiveMinorLow.idx += shift;
      if(maj_prot_high_idx >= 0) maj_prot_high_idx += shift;
      if(maj_prot_low_idx >= 0) maj_prot_low_idx += shift;
      if(maj_extreme_high_idx >= 0) maj_extreme_high_idx += shift;
      if(maj_extreme_low_idx >= 0) maj_extreme_low_idx += shift;
      if(last_maj_high_idx >= 0) last_maj_high_idx += shift;
      if(last_maj_low_idx >= 0) last_maj_low_idx += shift;
      if(latest_break_up_idx >= 0) latest_break_up_idx += shift;
      if(latest_break_down_idx >= 0) latest_break_down_idx += shift;
      if(min_prot_high_idx >= 0) min_prot_high_idx += shift;
      if(min_prot_low_idx >= 0) min_prot_low_idx += shift;
      if(min_extreme_high_idx >= 0) min_extreme_high_idx += shift;
      if(min_extreme_low_idx >= 0) min_extreme_low_idx += shift;
      if(last_min_high_idx >= 0) last_min_high_idx += shift;
      if(last_min_low_idx >= 0) last_min_low_idx += shift;
   }

   int limit = (prev_calculated == 0) ? rates_total - lookBack_max - 1 : (rates_total - prev_calculated) + lookBack_max;
   if (limit >= rates_total - lookBack_max) limit = rates_total - lookBack_max - 1;

   for(int i = limit + lookBack_max; i >= 0; i--) {
      HAClose[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      if(i >= rates_total - 1) HAOpen[i] = (open[i] + close[i]) / 2.0; else HAOpen[i] = (HAOpen[i+1] + HAClose[i+1]) / 2.0;
      HAHigh[i] = MathMax(high[i], MathMax(HAOpen[i], HAClose[i])); HALow[i]  = MathMin(low[i], MathMin(HAOpen[i], HAClose[i]));
      HAColor[i] = (HAClose[i] >= HAOpen[i]) ? 0 : 1; 
   }
   if(CopyBuffer(ma_handle, 0, 0, rates_total, EMA_Buffer) <= 0) return(0);

   for(int k = 0; k <= PeriodsInMajorSwing && k < rates_total; k++) { majorSwingHigh[k] = EMPTY_VALUE; majorSwingLow[k]  = EMPTY_VALUE; }
   for(int k = 0; k <= PeriodsInMinorSwing && k < rates_total; k++) { minorSwingHigh[k] = EMPTY_VALUE; minorSwingLow[k]  = EMPTY_VALUE; }

   for(int i = 0; i <= limit && !IsStopped(); i++) {
      majorSwingHigh[i + PeriodsInMajorSwing] = EMPTY_VALUE; majorSwingLow[i + PeriodsInMajorSwing]  = EMPTY_VALUE;
      minorSwingHigh[i + PeriodsInMinorSwing] = EMPTY_VALUE; minorSwingLow[i + PeriodsInMinorSwing]  = EMPTY_VALUE;
      if (i > 0) {
          if(ArrayMaximum(high, i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing) majorSwingHigh[i + PeriodsInMajorSwing] = high[i + PeriodsInMajorSwing];
          if(ArrayMinimum(low, i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing) majorSwingLow[i + PeriodsInMajorSwing] = low[i + PeriodsInMajorSwing];
          if(ArrayMaximum(high, i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing) minorSwingHigh[i + PeriodsInMinorSwing] = high[i + PeriodsInMinorSwing];
          if(ArrayMinimum(low, i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing) minorSwingLow[i + PeriodsInMinorSwing] = low[i + PeriodsInMinorSwing];
      }
   }

   int bos_limit = (prev_calculated == 0) ? limit : (rates_total - prev_calculated) + 1;
   
   for(int i = bos_limit; i >= 0; i--)
   {
      MajorEventBuffer[i] = 0; MinorEventBuffer[i] = 0;

      if(ActiveHigh.isActive) { if(ActiveHigh.idx >= 0 && ActiveHigh.idx < rates_total && majorSwingHigh[ActiveHigh.idx] == EMPTY_VALUE) ActiveHigh.isActive = false; }
      if(ActiveLow.isActive) { if(ActiveLow.idx >= 0 && ActiveLow.idx < rates_total && majorSwingLow[ActiveLow.idx] == EMPTY_VALUE) ActiveLow.isActive = false; }
      if(ActiveMinorHigh.isActive) { if(ActiveMinorHigh.idx >= 0 && ActiveMinorHigh.idx < rates_total && minorSwingHigh[ActiveMinorHigh.idx] == EMPTY_VALUE) ActiveMinorHigh.isActive = false; }
      if(ActiveMinorLow.isActive) { if(ActiveMinorLow.idx >= 0 && ActiveMinorLow.idx < rates_total && minorSwingLow[ActiveMinorLow.idx] == EMPTY_VALUE) ActiveMinorLow.isActive = false; }

      if(maj_prot_high != EMPTY_VALUE) { if(maj_prot_high_idx >= 0 && maj_prot_high_idx < rates_total && majorSwingHigh[maj_prot_high_idx] == EMPTY_VALUE) { maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1; } }
      if(maj_prot_low != EMPTY_VALUE) { if(maj_prot_low_idx >= 0 && maj_prot_low_idx < rates_total && majorSwingLow[maj_prot_low_idx] == EMPTY_VALUE) { maj_prot_low = EMPTY_VALUE; maj_prot_low_idx = -1; } }
      if(min_prot_high != EMPTY_VALUE) { if(min_prot_high_idx >= 0 && min_prot_high_idx < rates_total && minorSwingHigh[min_prot_high_idx] == EMPTY_VALUE) { min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1; } }
      if(min_prot_low != EMPTY_VALUE) { if(min_prot_low_idx >= 0 && min_prot_low_idx < rates_total && minorSwingLow[min_prot_low_idx] == EMPTY_VALUE) { min_prot_low = EMPTY_VALUE; min_prot_low_idx = -1; } }

      int swingMajor_idx = i + PeriodsInMajorSwing;
      if (swingMajor_idx < rates_total) {
         if(majorSwingHigh[swingMajor_idx] != EMPTY_VALUE) { 
            ActiveHigh.price = majorSwingHigh[swingMajor_idx]; ActiveHigh.time = time[swingMajor_idx]; ActiveHigh.isActive = true; ActiveHigh.idx = swingMajor_idx;
            last_maj_high = ActiveHigh.price; last_maj_high_time = ActiveHigh.time; last_maj_high_idx = swingMajor_idx;
            
            if (time[swingMajor_idx] > last_processed_high_time) {
                last_processed_high_time = time[swingMajor_idx];
                if (last_break_dir == -1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_down_time) {
                    int b_idx = latest_break_down_idx;
                    if (b_idx != -1) {
                        string zone_name = "OB_MASTER_ZONE_SELL_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZone(zone_name, swingMajor_idx, b_idx, true, latest_break_down_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                }
            }
         }
         
         if(majorSwingLow[swingMajor_idx] != EMPTY_VALUE) { 
            ActiveLow.price = majorSwingLow[swingMajor_idx]; ActiveLow.time = time[swingMajor_idx]; ActiveLow.isActive = true; ActiveLow.idx = swingMajor_idx;
            last_maj_low = ActiveLow.price; last_maj_low_time = ActiveLow.time; last_maj_low_idx = swingMajor_idx;
            
            if (time[swingMajor_idx] > last_processed_low_time) {
                last_processed_low_time = time[swingMajor_idx];
                if (last_break_dir == 1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_up_time) {
                    int b_idx = latest_break_up_idx;
                    if (b_idx != -1) {
                        string zone_name = "OB_MASTER_ZONE_BUY_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZone(zone_name, swingMajor_idx, b_idx, false, latest_break_up_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                }
            }
         }
      }
      
      int swingMinor_idx = i + PeriodsInMinorSwing;
      if (swingMinor_idx < rates_total) {
         if(minorSwingHigh[swingMinor_idx] != EMPTY_VALUE) { ActiveMinorHigh.price = minorSwingHigh[swingMinor_idx]; ActiveMinorHigh.time = time[swingMinor_idx]; ActiveMinorHigh.isActive = true; ActiveMinorHigh.idx = swingMinor_idx; last_min_high = ActiveMinorHigh.price; last_min_high_time = ActiveMinorHigh.time; last_min_high_idx = swingMinor_idx; }
         if(minorSwingLow[swingMinor_idx] != EMPTY_VALUE) { ActiveMinorLow.price = minorSwingLow[swingMinor_idx]; ActiveMinorLow.time = time[swingMinor_idx]; ActiveMinorLow.isActive = true; ActiveMinorLow.idx = swingMinor_idx; last_min_low = ActiveMinorLow.price; last_min_low_time = ActiveMinorLow.time; last_min_low_idx = swingMinor_idx;}
      }

      if (major_trend == 1) {
         if (maj_extreme_high == EMPTY_VALUE || high[i] > maj_extreme_high) { maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i; if (last_maj_low != EMPTY_VALUE && last_maj_low_time <= time[i]) { maj_prot_low = last_maj_low; maj_prot_low_time = last_maj_low_time; maj_prot_low_idx = last_maj_low_idx; } }
         if (ActiveLow.isActive && ActiveLow.time < maj_extreme_high_time) { maj_prot_low = ActiveLow.price; maj_prot_low_time = ActiveLow.time; maj_prot_low_idx = ActiveLow.idx; }
      } else if (major_trend == -1) {
         if (maj_extreme_low == EMPTY_VALUE || low[i] < maj_extreme_low) { maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i; if (last_maj_high != EMPTY_VALUE && last_maj_high_time <= time[i]) { maj_prot_high = last_maj_high; maj_prot_high_time = last_maj_high_time; maj_prot_high_idx = last_maj_high_idx; } }
         if (ActiveHigh.isActive && ActiveHigh.time < maj_extreme_low_time) { maj_prot_high = ActiveHigh.price; maj_prot_high_time = ActiveHigh.time; maj_prot_high_idx = ActiveHigh.idx; }
      } else {
         if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) { major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i; maj_prot_low = last_maj_low; maj_prot_low_time = last_maj_low_time; maj_prot_low_idx = last_maj_low_idx; } 
         else if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) { major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i; maj_prot_high = last_maj_high; maj_prot_high_time = last_maj_high_time; maj_prot_high_idx = last_maj_high_idx; }
      }

      if (minor_trend == 1) { 
         if (min_extreme_high == EMPTY_VALUE || high[i] > min_extreme_high) { min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i; if (last_min_low != EMPTY_VALUE && last_min_low_time <= time[i]) { min_prot_low = last_min_low; min_prot_low_time = last_min_low_time; min_prot_low_idx = last_min_low_idx; } } 
         if (ActiveMinorLow.isActive && ActiveMinorLow.time < min_extreme_high_time) { min_prot_low = ActiveMinorLow.price; min_prot_low_time = ActiveMinorLow.time; min_prot_low_idx = ActiveMinorLow.idx;}
      } else if (minor_trend == -1) { 
         if (min_extreme_low == EMPTY_VALUE || low[i] < min_extreme_low) { min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i; if (last_min_high != EMPTY_VALUE && last_min_high_time <= time[i]) { min_prot_high = last_min_high; min_prot_high_time = last_min_high_time; min_prot_high_idx = last_min_high_idx; } } 
         if (ActiveMinorHigh.isActive && ActiveMinorHigh.time < min_extreme_low_time) { min_prot_high = ActiveMinorHigh.price; min_prot_high_time = ActiveMinorHigh.time; min_prot_high_idx = ActiveMinorHigh.idx; }
      } else { 
         if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) { minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i; min_prot_low = last_min_low; min_prot_low_time = last_min_low_time; min_prot_low_idx = last_min_low_idx; } 
         else if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) { minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i; min_prot_high = last_min_high; min_prot_high_time = last_min_high_time; min_prot_high_idx = last_min_high_idx; }
      }

      if(i > 0)
      {
         for(int j = ArraySize(BuyZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] < BuyZonesQueue[j].stopPrice) { ObjectDelete(0, BuyZonesQueue[j].name); for(int k = j; k < ArraySize(BuyZonesQueue) - 1; k++) BuyZonesQueue[k] = BuyZonesQueue[k+1]; ArrayResize(BuyZonesQueue, ArraySize(BuyZonesQueue) - 1); } }
         for(int j = ArraySize(SellZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] > SellZonesQueue[j].stopPrice) { ObjectDelete(0, SellZonesQueue[j].name); for(int k = j; k < ArraySize(SellZonesQueue) - 1; k++) SellZonesQueue[k] = SellZonesQueue[k+1]; ArrayResize(SellZonesQueue, ArraySize(SellZonesQueue) - 1); } }

         // [V80 FIX] LỚP BẢO VỆ CHOCH
         bool is_major_choch_up = false; bool is_major_choch_dn = false;

         // 1. SỰ KIỆN: CHOCH GIẢM
         if (major_trend == 1 && maj_prot_low != EMPTY_VALUE && HAClose[i] < maj_prot_low) {
            string choch_name = "OB_MASTER_CHOCH_DN_" + IntegerToString((long)maj_prot_low_time);
            if(ObjectFind(0, choch_name) < 0) {
               CreateBOSLine(choch_name, maj_prot_low_time, maj_prot_low, time[i], BOS_Down_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
               PushBOS(BOSDnQueue, choch_name, MaxBOSLines);
               MajorEventBuffer[i] = -2; ClearZoneQueue(BuyZonesQueue);

               double actual_extreme_high = maj_extreme_high; datetime actual_extreme_time = maj_extreme_high_time; int actual_extreme_idx = maj_extreme_high_idx;
               int prot_idx = maj_prot_low_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int highest_idx = ArrayMaximum(high, i, count);
                   if (highest_idx != -1) { actual_extreme_high = high[highest_idx]; actual_extreme_time = time[highest_idx]; actual_extreme_idx = highest_idx; }
               }
               
               ObjectDelete(0, "OB_MASTER_MAJOR_KEY_LEVEL"); ObjectDelete(0, "OB_MASTER_MAJOR_KEY_LEVEL_lbl");
               CreateRayLine("OB_MASTER_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_high, KeyLevel_Color, "Major Key Level Down", true);
               
               // [THÊM OB]: Tìm OB Nguồn từ Choch về Đỉnh Cực Trị & Đặt cờ Thanh trừng
               FindAndDrawOriginOBs(i, actual_extreme_idx, false, high, low, open, close, time);
               pending_purge = true;

               last_break_dir = -1; last_break_type = 2; 
               latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = maj_prot_low;

               int zone_anchor_idx = actual_extreme_idx; 
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && majorSwingHigh[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if(zone_anchor_idx != -1) {
                  string zone_name = "OB_MASTER_ZONE_SELL_CHOCH_" + IntegerToString((long)time[i]);
                  double zEntry, zStop;
                  CreateZone(zone_name, zone_anchor_idx, i, true, maj_prot_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                  PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
               }
               
               if (ActiveLow.time == maj_prot_low_time) ActiveLow.isActive = false; 
               ClearQueue(BOSUpQueue); 
               major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i;
               maj_prot_high = actual_extreme_high; maj_prot_high_time = actual_extreme_time; maj_prot_high_idx = actual_extreme_idx; maj_prot_low = EMPTY_VALUE; maj_prot_low_idx = -1;
            }
            is_major_choch_dn = true;
         }
         // 2. SỰ KIỆN: CHOCH TĂNG
         else if (major_trend == -1 && maj_prot_high != EMPTY_VALUE && HAClose[i] > maj_prot_high) {
            string choch_name = "OB_MASTER_CHOCH_UP_" + IntegerToString((long)maj_prot_high_time);
            if(ObjectFind(0, choch_name) < 0) {
               CreateBOSLine(choch_name, maj_prot_high_time, maj_prot_high, time[i], BOS_Up_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
               PushBOS(BOSUpQueue, choch_name, MaxBOSLines);
               MajorEventBuffer[i] = 2; ClearZoneQueue(SellZonesQueue);

               double actual_extreme_low = maj_extreme_low; datetime actual_extreme_time = maj_extreme_low_time; int actual_extreme_idx = maj_extreme_low_idx;
               int prot_idx = maj_prot_high_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int lowest_idx = ArrayMinimum(low, i, count);
                   if (lowest_idx != -1) { actual_extreme_low = low[lowest_idx]; actual_extreme_time = time[lowest_idx]; actual_extreme_idx = lowest_idx; }
               }
               
               ObjectDelete(0, "OB_MASTER_MAJOR_KEY_LEVEL"); ObjectDelete(0, "OB_MASTER_MAJOR_KEY_LEVEL_lbl");
               CreateRayLine("OB_MASTER_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_low, KeyLevel_Color, "Major Key Level Up", false);
               
               // [THÊM OB]: Tìm OB Nguồn từ Choch về Đáy Cực Trị & Đặt cờ Thanh trừng
               FindAndDrawOriginOBs(i, actual_extreme_idx, true, high, low, open, close, time);
               pending_purge = true;

               last_break_dir = 1; last_break_type = 2; 
               latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = maj_prot_high;

               int zone_anchor_idx = actual_extreme_idx; 
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && majorSwingLow[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if(zone_anchor_idx != -1) {
                  string zone_name = "OB_MASTER_ZONE_BUY_CHOCH_" + IntegerToString((long)time[i]);
                  double zEntry, zStop;
                  CreateZone(zone_name, zone_anchor_idx, i, false, maj_prot_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                  PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
               }
               
               if (ActiveHigh.time == maj_prot_high_time) ActiveHigh.isActive = false; ClearQueue(BOSDnQueue); 
               major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i;
               maj_prot_low = actual_extreme_low; maj_prot_low_time = actual_extreme_time; maj_prot_low_idx = actual_extreme_idx; maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1;
            }
            is_major_choch_up = true;
         }

         // 3. SỰ KIỆN: BOS TĂNG
         if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) {
            if (!is_major_choch_up) { 
                string bos_name = "OB_MASTER_BOS_UP_" + IntegerToString((long)ActiveHigh.time);
                if(ObjectFind(0, bos_name) < 0) {
                   CreateBOSLine(bos_name, ActiveHigh.time, ActiveHigh.price, time[i], BOS_Up_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                   PushBOS(BOSUpQueue, bos_name, MaxBOSLines);
                   MajorEventBuffer[i] = 1; 
                   
                   // [THÊM OB]: Thực thi thanh trừng nếu cờ đang mở & Tìm OB Nguồn của BOS
                   if (pending_purge) { PurgeOBsBeforeTime(last_maj_low_time); pending_purge = false; }
                   if (last_maj_low_idx != -1) FindAndDrawOriginOBs(i, last_maj_low_idx, true, high, low, open, close, time);

                   last_break_dir = 1; last_break_type = 1; 
                   latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = ActiveHigh.price;

                   int origin_idx = last_maj_low_idx;
                   if (origin_idx != -1) {
                      string zone_name = "OB_MASTER_ZONE_BUY_BOS_" + IntegerToString((long)last_maj_low_time);
                      double zEntry, zStop;
                      CreateZone(zone_name, origin_idx, i, false, ActiveHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                      PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveHigh.isActive = false; 
         }

         // 4. SỰ KIỆN: BOS GIẢM
         if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) {
            if (!is_major_choch_dn) { 
                string bos_name = "OB_MASTER_BOS_DN_" + IntegerToString((long)ActiveLow.time);
                if(ObjectFind(0, bos_name) < 0) {
                   CreateBOSLine(bos_name, ActiveLow.time, ActiveLow.price, time[i], BOS_Down_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                   PushBOS(BOSDnQueue, bos_name, MaxBOSLines);
                   MajorEventBuffer[i] = -1; 
                   
                   // [THÊM OB]: Thực thi thanh trừng nếu cờ đang mở & Tìm OB Nguồn của BOS
                   if (pending_purge) { PurgeOBsBeforeTime(last_maj_high_time); pending_purge = false; }
                   if (last_maj_high_idx != -1) FindAndDrawOriginOBs(i, last_maj_high_idx, false, high, low, open, close, time);

                   last_break_dir = -1; last_break_type = 1; 
                   latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = ActiveLow.price;

                   int origin_idx = last_maj_high_idx;
                   if (origin_idx != -1) {
                      string zone_name = "OB_MASTER_ZONE_SELL_BOS_" + IntegerToString((long)last_maj_high_time);
                      double zEntry, zStop;
                      CreateZone(zone_name, origin_idx, i, true, ActiveLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                      PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveLow.isActive = false;
         }

         // --- [MINOR STRUCTURE LOGIC GIỮ NGUYÊN...] ---
         if (minor_trend == 1 && min_prot_low != EMPTY_VALUE && HAClose[i] < min_prot_low) {
            if (!is_major_choch_dn) {
               string choch_name = "OB_MASTER_MINOR_CHOCH_DN_" + IntegerToString((long)min_prot_low_time);
               if(ObjectFind(0, choch_name) < 0) {
                  if(ShowMinorStructure) { CreateBOSLine(choch_name, min_prot_low_time, min_prot_low, time[i], Minor_BOS_Down_Color, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6); PushBOS(MinorBOSDnQueue, choch_name, MaxMinorBOSLines); }
                  MinorEventBuffer[i] = -2; ClearQueue(MinorBOSUpQueue); 
               }
               if (ActiveMinorLow.time == min_prot_low_time) ActiveMinorLow.isActive = false; 
               minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i;
               min_prot_high = min_extreme_high; min_prot_high_time = min_extreme_high_time; min_prot_high_idx = min_extreme_high_idx; min_prot_low = EMPTY_VALUE; min_prot_low_idx = -1;
            }
         } 
         else if (minor_trend == -1 && min_prot_high != EMPTY_VALUE && HAClose[i] > min_prot_high) {
            if (!is_major_choch_up) {
               string choch_name = "OB_MASTER_MINOR_CHOCH_UP_" + IntegerToString((long)min_prot_high_time);
               if(ObjectFind(0, choch_name) < 0) {
                  if(ShowMinorStructure) { CreateBOSLine(choch_name, min_prot_high_time, min_prot_high, time[i], Minor_BOS_Up_Color, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6); PushBOS(MinorBOSUpQueue, choch_name, MaxMinorBOSLines); }
                  MinorEventBuffer[i] = 2; ClearQueue(MinorBOSDnQueue); 
               }
               if (ActiveMinorHigh.time == min_prot_high_time) ActiveMinorHigh.isActive = false; 
               minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i;
               min_prot_low = min_extreme_low; min_prot_low_time = min_extreme_low_time; min_prot_low_idx = min_extreme_low_idx; min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1;
            }
         }

         if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) {
            if (!is_major_choch_up) {
                string bos_name = "OB_MASTER_MINOR_BOS_UP_" + IntegerToString((long)ActiveMinorHigh.time);
                if(ObjectFind(0, bos_name) < 0) {
                   if(ShowMinorStructure) { CreateBOSLine(bos_name, ActiveMinorHigh.time, ActiveMinorHigh.price, time[i], Minor_BOS_Up_Color, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6); PushBOS(MinorBOSUpQueue, bos_name, MaxMinorBOSLines); }
                   MinorEventBuffer[i] = 1; 
                }
            }
            ActiveMinorHigh.isActive = false;
         }

         if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) {
            if (!is_major_choch_dn) {
                string bos_name = "OB_MASTER_MINOR_BOS_DN_" + IntegerToString((long)ActiveMinorLow.time);
                if(ObjectFind(0, bos_name) < 0) {
                   if(ShowMinorStructure) { CreateBOSLine(bos_name, ActiveMinorLow.time, ActiveMinorLow.price, time[i], Minor_BOS_Down_Color, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6); PushBOS(MinorBOSDnQueue, bos_name, MaxMinorBOSLines); }
                   MinorEventBuffer[i] = -1; 
                }
            }
            ActiveMinorLow.isActive = false;
         }
         
         // =========================================================
         // [THÊM MỚI TỪ V100]: QUÉT TÌM OB TIẾP DIỄN VÀ OB BỊ CHẠM
         // =========================================================
         if (EnableOB) { // KHÔNG dùng i > 0 theo yêu cầu giữ nguyên của bạn
             int k = i + 1; 
             if (k + 1 < rates_total && k - 1 >= 0) {
                 if (major_trend == 1) { 
                     CheckAndDrawSingleOB(k, true, high, low, open, close, time, i); 
                 } else if (major_trend == -1) { 
                     CheckAndDrawSingleOB(k, false, high, low, open, close, time, i); 
                 }
             }
         }

         for(int obj = ArraySize(liveOBs) - 1; obj >= 0; obj--) {
             if (liveOBs[obj].isBull) {
                 if (low[i] <= liveOBs[obj].top) { 
                     ObjectDelete(0, liveOBs[obj].name); ObjectDelete(0, liveOBs[obj].name + "_LBL");
                     ArrayRemove(liveOBs, obj, 1);
                 }
             } else {
                 if (high[i] >= liveOBs[obj].bottom) { 
                     ObjectDelete(0, liveOBs[obj].name); ObjectDelete(0, liveOBs[obj].name + "_LBL");
                     ArrayRemove(liveOBs, obj, 1);
                 }
             }
         }
      }

      MajorTrendBuffer[i] = major_trend; MinorTrendBuffer[i] = minor_trend;
      MajorProtHighBuffer[i] = maj_prot_high; MajorProtLowBuffer[i]  = maj_prot_low;
      MinorProtHighBuffer[i] = min_prot_high; MinorProtLowBuffer[i]  = min_prot_low;

      if (ArraySize(BuyZonesQueue) > 0) { BuyZoneEntryBuffer[i] = BuyZonesQueue[0].entryPrice; BuyZoneSLBuffer[i] = BuyZonesQueue[0].stopPrice; } else { BuyZoneEntryBuffer[i] = EMPTY_VALUE; BuyZoneSLBuffer[i] = EMPTY_VALUE; }
      if (ArraySize(SellZonesQueue) > 0) { SellZoneSLBuffer[i] = SellZonesQueue[0].stopPrice; SellZoneEntryBuffer[i] = SellZonesQueue[0].entryPrice; } else { SellZoneSLBuffer[i] = EMPTY_VALUE; SellZoneEntryBuffer[i] = EMPTY_VALUE; }

      if (i == 0) {
         if (major_trend == -1 && maj_prot_high != EMPTY_VALUE) { g_high_lvl = maj_prot_high; g_high_time = maj_prot_high_time; g_high_text = "Protected High"; } else if (ActiveHigh.isActive) { g_high_lvl = ActiveHigh.price; g_high_time = ActiveHigh.time; g_high_text = "Active High"; } else { g_high_lvl = EMPTY_VALUE; }
         if (major_trend == 1 && maj_prot_low != EMPTY_VALUE) { g_low_lvl = maj_prot_low; g_low_time = maj_prot_low_time; g_low_text = "Protected Low"; } else if (ActiveLow.isActive) { g_low_lvl = ActiveLow.price; g_low_time = ActiveLow.time; g_low_text = "Active Low"; } else { g_low_lvl = EMPTY_VALUE; }
         if (ShowTrackingLines) { CreateTrackingRayWithLabel("OB_MASTER_TRACK_HIGH", g_high_time, g_high_lvl, TrackingLineColor, g_high_text, false, time[0]); CreateTrackingRayWithLabel("OB_MASTER_TRACK_LOW", g_low_time, g_low_lvl, TrackingLineColor, g_low_text, true, time[0]); } else { ObjectDelete(0, "OB_MASTER_TRACK_HIGH_ray"); ObjectDelete(0, "OB_MASTER_TRACK_HIGH_lbl"); ObjectDelete(0, "OB_MASTER_TRACK_LOW_ray");  ObjectDelete(0, "OB_MASTER_TRACK_LOW_lbl"); }
      }
   }
   return(rates_total);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if (id == CHARTEVENT_CHART_CHANGE) {
       if (ShowTrackingLines) { datetime t[]; if (CopyTime(_Symbol, _Period, 0, 1, t) > 0) { CreateTrackingRayWithLabel("OB_MASTER_TRACK_HIGH", g_high_time, g_high_lvl, TrackingLineColor, g_high_text, false, t[0]); CreateTrackingRayWithLabel("OB_MASTER_TRACK_LOW", g_low_time, g_low_lvl, TrackingLineColor, g_low_text, true, t[0]); ChartRedraw(); } }
   }
}

datetime GetRightEdgeTime(datetime current_time) { 
    int width = (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS); 
    int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR); 
    int future_offset = width - first - 2; if (future_offset < 1) future_offset = 1; 
    return current_time + future_offset * PeriodSeconds();
}

void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time) { 
   if (p1 == EMPTY_VALUE || t1 == 0) { ObjectDelete(0, name + "_ray"); ObjectDelete(0, name + "_lbl"); return; }
   string ray_name = name + "_ray";
   if(ObjectFind(0, ray_name) < 0) { ObjectCreate(0, ray_name, OBJ_TREND, 0, t1, p1, current_time + PeriodSeconds(), p1); ObjectSetInteger(0, ray_name, OBJPROP_COLOR, clr); ObjectSetInteger(0, ray_name, OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(0, ray_name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, ray_name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0, ray_name, OBJPROP_BACK, false); } else { ObjectSetInteger(0, ray_name, OBJPROP_TIME, 0, t1); ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 0, p1); ObjectSetInteger(0, ray_name, OBJPROP_TIME, 1, current_time + PeriodSeconds()); ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 1, p1); }
   string lbl_name = name + "_lbl"; datetime label_time = GetRightEdgeTime(current_time); 
   if(ObjectFind(0, lbl_name) < 0) { ObjectCreate(0, lbl_name, OBJ_TEXT, 0, label_time, p1); ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, clr); ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lbl_name, OBJPROP_BACK, false); ObjectSetInteger(0, lbl_name, OBJPROP_SELECTABLE, false); } else { ObjectSetInteger(0, lbl_name, OBJPROP_TIME, 0, label_time); ObjectSetDouble(0, lbl_name, OBJPROP_PRICE, 0, p1); }
   ObjectSetString(0, lbl_name, OBJPROP_TEXT, text + "  "); ObjectSetInteger(0, lbl_name, OBJPROP_ANCHOR, isDown ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER); 
}

void ClearQueue(string &queue[]) { for(int i=0; i<ArraySize(queue); i++) { ObjectDelete(0, queue[i]); ObjectDelete(0, queue[i] + "_lbl"); } ArrayResize(queue, 0); }
void ClearZoneQueue(TZone &queue[]) { for(int i=0; i<ArraySize(queue); i++) { ObjectDelete(0, queue[i].name); } ArrayResize(queue, 0); }
void PushBOS(string &queue[], string name, int max_count) { for(int i=0; i<ArraySize(queue); i++) if(queue[i] == name) return; int size = ArraySize(queue); ArrayResize(queue, size + 1); queue[size] = name; if(ArraySize(queue) > max_count) { ObjectDelete(0, queue[0]); ObjectDelete(0, queue[0] + "_lbl"); for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1]; ArrayResize(queue, ArraySize(queue) - 1); } }
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count) { for(int i=0; i<ArraySize(queue); i++) { if(queue[i].name == name) { queue[i].entryPrice = entry; queue[i].stopPrice = stop; return; } } int size = ArraySize(queue); ArrayResize(queue, size + 1); queue[size].name = name; queue[size].entryPrice = entry; queue[size].stopPrice = stop; if(ArraySize(queue) > max_count) { ObjectDelete(0, queue[0].name); for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1]; ArrayResize(queue, ArraySize(queue) - 1); } }
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize) { ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p1); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, style); ObjectSetInteger(0, name, OBJPROP_WIDTH, width); ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); ObjectSetInteger(0, name, OBJPROP_BACK, false); datetime t_mid = t1 + (t2 - t1) / 2; string lbl = name + "_lbl"; ObjectCreate(0, lbl, OBJ_TEXT, 0, t_mid, p1); ObjectSetString(0, lbl, OBJPROP_TEXT, text); ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr); ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, anchor); ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, fontSize); ObjectSetInteger(0, lbl, OBJPROP_BACK, false); }
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown) { ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t1 + PeriodSeconds()*100, p1); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, name, OBJPROP_WIDTH, 2); ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0, name, OBJPROP_BACK, false); string lbl = name + "_lbl"; ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, p1); ObjectSetString(0, lbl, OBJPROP_TEXT, " " + text); ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr); ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isDown ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER); ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lbl, OBJPROP_BACK, false); }

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop) {
   int ext_idx = swing_idx; 
   if (bos_idx >= 0 && swing_idx >= bos_idx) { int count = swing_idx - bos_idx + 1; if(isSellZone) ext_idx = ArrayMaximum(h, bos_idx, count); else ext_idx = ArrayMinimum(l, bos_idx, count); }
   double actual_broken_level = broken_level;
   if ((actual_broken_level <= 0 || actual_broken_level == EMPTY_VALUE) && bos_idx >= 0 && swing_idx > bos_idx) {
       int check_count = swing_idx - bos_idx;
       if (isSellZone) { int brk_idx = ArrayMinimum(l, bos_idx + 1, check_count); if (brk_idx != -1) actual_broken_level = l[brk_idx]; } else { int brk_idx = ArrayMaximum(h, bos_idx + 1, check_count); if (brk_idx != -1) actual_broken_level = h[brk_idx]; }
   }
   int targetColor = isSellZone ? 0 : 1; int k = ext_idx; 
   double zHigh = ha_h[ext_idx]; double zLow  = ha_l[ext_idx];
   while(k < total && ha_color[k] != targetColor && k <= ext_idx + 10) { k++; }
   if(k <= ext_idx + 10 && k < total) {
       if(isSellZone) { zLow = ha_l[k]; while(k < total && ha_color[k] == targetColor) { zLow = MathMin(zLow, ha_l[k]); k++; } zHigh = MathMax(zHigh, ha_h[ext_idx]); } else { zHigh = ha_h[k]; while(k < total && ha_color[k] == targetColor) { zHigh = MathMax(zHigh, ha_h[k]); k++; } zLow = MathMin(zLow, ha_l[ext_idx]); }
   }
   if (actual_broken_level > 0 && actual_broken_level != EMPTY_VALUE) {
       if (isSellZone && zLow <= actual_broken_level + _Point) { zHigh = ha_h[ext_idx]; zLow = ha_l[ext_idx]; } else if (!isSellZone && zHigh >= actual_broken_level - _Point) { zHigh = ha_h[ext_idx]; zLow = ha_l[ext_idx]; }
   }
   out_stop  = isSellZone ? zHigh : zLow; out_entry = isSellZone ? zLow : zHigh;
   if(!ShowZones) return;
   if(ObjectFind(0, name) >= 0) {
       double old_zHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 0); double old_zLow = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
       if (MathAbs(old_zHigh - zHigh) < _Point && MathAbs(old_zLow - zLow) < _Point) return; 
       ObjectDelete(0, name);
   }
   datetime tStart = time[ext_idx]; datetime tEnd = time[0] + PeriodSeconds() * 1000; 
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isSellZone ? SellZoneColor : BuyZoneColor); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); 
}
//+------------------------------------------------------------------+