//+------------------------------------------------------------------+
//|                                          TLS_SMC_Indicator.mq5   |
//|          (đổi tên từ Combo_Structure_MajorSwing_HA_BOS_Zone_     |
//|                                  Anchor_forBotChart.mq5, 08/2026)|
//|                                  Focus: Protected Sweep Promotion|
//|                                  Status: Ultimate SMC Master     |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & Quân (anhtuan02t1)"
#property version   "50.00" 
#property indicator_chart_window

// Tăng buffer lên 30: 4 đường mZone tính toán ngầm cho Bot EA + 4 buffer hiển thị riêng cho nến HA
// (tách khỏi buffer tính toán HAOpen/HAHigh/HALow/HAClose để khi ẩn nến không làm vỡ công thức đệ quy HA Open)
#property indicator_buffers 30
#property indicator_plots   18

#property indicator_type1   DRAW_ARROW
#property indicator_type2   DRAW_ARROW
#property indicator_type3   DRAW_LINE
#property indicator_type4   DRAW_COLOR_CANDLES
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

input group "--- Hiển thị Major (Hiện/Ẩn) ---"
input bool  ShowEMALine           = true;        // Major_Đường EMA (21)
input bool  ShowHACandles         = true;        // Major_Nến Heikin Ashi
input bool  ShowMajorSwingPoints  = true;        // Major_Điểm Swing High/Low
input bool  ShowMajorBOS          = true;        // Major_Đường BOS
input bool  ShowMajorCHOCH        = true;        // Major_Đường CHOCH
input bool  ShowKeyLevel          = true;        // Major_Đường Key Level
input bool  ShowSDZones           = true;        // Major_Vùng Supply/Demand Zone
input bool  ShowTrackingLines     = true;        // Major_Đường Tracking (Active High/Low)
input bool  ShowWeakHighLow       = true;        // Major_Đường Weak High/Low
input bool  ShowLastMajorHighLow  = false;       // Major_Đường mốc Đỉnh/Đáy gần nhất

input group "--- Hiển thị Minor (Hiện/Ẩn) ---"
input bool  ShowMinorSwingPoints  = true;        // Minor_Điểm Swing High/Low
input bool  ShowMinorBOSCHOCH     = true;        // Minor_Đường BOS/CHOCH

input group "--- Swing Settings (Major & Minor) ---"
input int   PeriodsInMajorSwing   = 9;           // Số nến Swing Major
input int   PeriodsInMinorSwing   = 5;           // Số nến Swing Minor

// --- Cố định (gỡ khỏi Inputs cho gọn, giữ nguyên giá trị mặc định cũ) ---
// Lưu ý: MovingAveragePeriods đổi giá trị thì phải sửa luôn số "(21)" trong
// comment của ShowEMALine ở trên cho khớp (không tự động liên kết được).
const int   MaxBOSLines           = 5;
const int   MaxMinorBOSLines      = 3;
const int   MaxZones              = 1;
const int   MovingAveragePeriods  = 21;
const color MajorSwingColor       = C'80,80,80';
const int   MajorSwingSize        = 5;
const color TrackingLineColor     = clrMagenta;
const color LastMajorLineColor    = clrBlue;
const color BOS_Up_Color          = clrDodgerBlue;
const color BOS_Down_Color        = clrRed;
const color KeyLevel_Color        = clrOrange;
const color BuyZoneColor          = C'190,235,210';
const color SellZoneColor         = C'255,200,200';
const int   MinorSwingSize        = 1;
const color Minor_BOS_Up_Color    = C'120,220,220';
const color Minor_BOS_Down_Color  = C'255,180,180';
const color MovingAvergeColor     = C'80,80,80';
const color InpBullColor          = C'8,153,129';
const color InpBearColor          = C'242,54,69';

double majorSwingHigh[], majorSwingLow[], EMA_Buffer[];
double HAOpen[], HAHigh[], HALow[], HAClose[], HAColor[];
double HAOpenDisp[], HAHighDisp[], HALowDisp[], HACloseDisp[]; // Bản hiển thị riêng của nến HA (ShowHACandles=false -> EMPTY_VALUE), không đụng tới buffer tính toán phía trên
double minorSwingHigh[], minorSwingLow[];

double MajorTrendBuffer[], MinorTrendBuffer[];
double MajorEventBuffer[], MinorEventBuffer[];
double MajorProtHighBuffer[], MajorProtLowBuffer[];
double MinorProtHighBuffer[], MinorProtLowBuffer[];
double BuyZoneEntryBuffer[], BuyZoneSLBuffer[];
double SellZoneSLBuffer[], SellZoneEntryBuffer[];

// Các Buffer tính toán ngầm lưu thông tin mZone cho BOT sử dụng
double MinorBuyZoneEntryBuffer[], MinorBuyZoneSLBuffer[], MinorSellZoneSLBuffer[], MinorSellZoneEntryBuffer[];

int ma_handle;
int lookBackMajor, lookBackMinor;

struct TSwing { double price; datetime time; bool isActive; int idx; };
struct TZone  { string name; double entryPrice; double stopPrice; };
struct TLevelSrc { double price; datetime time; string text; color clr; string objName; bool enabled; };

TSwing ActiveHigh = {EMPTY_VALUE, 0, false, -1}; TSwing ActiveLow  = {EMPTY_VALUE, 0, false, -1};
TSwing ActiveMinorHigh = {EMPTY_VALUE, 0, false, -1}; TSwing ActiveMinorLow  = {EMPTY_VALUE, 0, false, -1};

string BOSUpQueue[]; string BOSDnQueue[];
TZone BuyZonesQueue[]; TZone SellZonesQueue[];
string MinorBOSUpQueue[]; string MinorBOSDnQueue[];

// Queue lưu trữ ngầm cấu trúc mZone
TZone MinorBuyZonesQueue[]; TZone MinorSellZonesQueue[];

// Lưu trữ riêng đường CHOCH (tách khỏi BOS queue để tránh bị evict bởi MaxBOSLines)
string g_choch_up_name = "";
string g_choch_dn_name = "";
string g_minor_choch_up_name = "";
string g_minor_choch_dn_name = "";

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

double maj_confirmed_extreme_high = EMPTY_VALUE; datetime maj_confirmed_extreme_high_time = 0;
double maj_confirmed_extreme_low = EMPTY_VALUE;  datetime maj_confirmed_extreme_low_time = 0;

// Các biến quản lý Radar Major
bool pending_prot_high_update = false;
bool pending_prot_low_update = false;
datetime processed_prot_weak_high_time = 0;
datetime processed_prot_weak_low_time = 0;
datetime prot_anchor_time = 0;
int prot_anchor_idx = -1;
int prot_breakout_idx = -1;

// Biến môi trường Minor
int minor_trend = 0; 
double min_prot_high = EMPTY_VALUE; datetime min_prot_high_time = 0; int min_prot_high_idx = -1;
double min_prot_low = EMPTY_VALUE;  datetime min_prot_low_time = 0;  int min_prot_low_idx = -1;
double min_extreme_high = EMPTY_VALUE;   datetime min_extreme_high_time = 0; int min_extreme_high_idx = -1;
double min_extreme_low = EMPTY_VALUE;    datetime min_extreme_low_time = 0;  int min_extreme_low_idx = -1;
double last_min_high = EMPTY_VALUE; datetime last_min_high_time = 0; int last_min_high_idx = -1;
double last_min_low = EMPTY_VALUE;  datetime last_min_low_time = 0;  int last_min_low_idx = -1;

double min_confirmed_extreme_high = EMPTY_VALUE; datetime min_confirmed_extreme_high_time = 0;
double min_confirmed_extreme_low = EMPTY_VALUE;  datetime min_confirmed_extreme_low_time = 0;

// Các biến quản lý Radar Minor (Fractal)
bool min_pending_prot_high_update = false;
bool min_pending_prot_low_update = false;
datetime min_processed_prot_weak_high_time = 0;
datetime min_processed_prot_weak_low_time = 0;
datetime min_prot_anchor_time = 0;
int min_prot_anchor_idx = -1;
int min_prot_breakout_idx = -1;

double g_high_lvl = EMPTY_VALUE; datetime g_high_time = 0; string g_high_text = "";
double g_low_lvl = EMPTY_VALUE;  datetime g_low_time = 0;  string g_low_text = "";

bool is_maj_prot_high_sweep = false;
bool is_maj_prot_low_sweep = false;
bool is_min_prot_high_sweep = false;
bool is_min_prot_low_sweep = false;

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop, bool draw_graphic);
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize);
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown);
void PushBOS(string &queue[], string name, int max_count);
void ClearQueue(string &queue[]);
void ClearZoneQueue(TZone &queue[]);
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count);
void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time);
datetime GetRightEdgeTime(datetime current_time);
void DrawLevelGroup(TLevelSrc &src[], datetime current_time, bool isDown);
void UpdateLevelLabels(datetime current_time);

int OnInit()
{
   lookBackMajor = PeriodsInMajorSwing * 2; lookBackMinor = PeriodsInMinorSwing * 2; 
   SetIndexBuffer(0, majorSwingHigh, INDICATOR_DATA); PlotIndexSetInteger(0, PLOT_ARROW, 159); PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MajorSwingSize); PlotIndexSetInteger(0, PLOT_LINE_COLOR, MajorSwingColor); PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   SetIndexBuffer(1, majorSwingLow, INDICATOR_DATA); PlotIndexSetInteger(1, PLOT_ARROW, 159); PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MajorSwingSize); PlotIndexSetInteger(1, PLOT_LINE_COLOR, MajorSwingColor); PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   if(!ShowMajorSwingPoints) { PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE); PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE); }
   else { PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_ARROW); PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW); }
   SetIndexBuffer(2, EMA_Buffer, INDICATOR_DATA); PlotIndexSetInteger(2, PLOT_LINE_COLOR, MovingAvergeColor);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, ShowEMALine ? DRAW_LINE : DRAW_NONE);
   // Plot nến (buffer 3-7) đọc từ 4 buffer hiển thị riêng (HA*Disp) + buffer màu chung.
   // Buffer tính toán thật (HAOpen/HAHigh/HALow/HAClose, dùng cho toàn bộ logic Trend/Zone) nằm ở buffer 26-29 (INDICATOR_CALCULATIONS), không bị ảnh hưởng khi ẩn nến.
   // Lưu ý: KHÔNG đổi PLOT_DRAW_TYPE của plot nến lúc runtime — DRAW_COLOR_CANDLES không hỗ trợ tốt việc chuyển DRAW_NONE qua PlotIndexSetInteger (gây lỗi hiển thị vô số chấm tròn);
   // việc ẩn/hiện nến được xử lý bằng cách nạp EMPTY_VALUE vào buffer hiển thị trong OnCalculate.
   SetIndexBuffer(3, HAOpenDisp, INDICATOR_DATA); SetIndexBuffer(4, HAHighDisp, INDICATOR_DATA); SetIndexBuffer(5, HALowDisp, INDICATOR_DATA); SetIndexBuffer(6, HACloseDisp, INDICATOR_DATA); SetIndexBuffer(7, HAColor, INDICATOR_COLOR_INDEX);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpBullColor); PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpBearColor);
   SetIndexBuffer(26, HAOpen, INDICATOR_CALCULATIONS); SetIndexBuffer(27, HAHigh, INDICATOR_CALCULATIONS); SetIndexBuffer(28, HALow, INDICATOR_CALCULATIONS); SetIndexBuffer(29, HAClose, INDICATOR_CALCULATIONS);

   SetIndexBuffer(8, minorSwingHigh, INDICATOR_DATA); PlotIndexSetInteger(4, PLOT_ARROW, 159); PlotIndexSetInteger(4, PLOT_LINE_WIDTH, MinorSwingSize); PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   SetIndexBuffer(9, minorSwingLow, INDICATOR_DATA);  PlotIndexSetInteger(5, PLOT_ARROW, 159); PlotIndexSetInteger(5, PLOT_LINE_WIDTH, MinorSwingSize); PlotIndexSetDouble(9, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   if(!ShowMinorSwingPoints) { PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE); PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE); }
   else { PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_ARROW); PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_ARROW); }

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

   // Cài đặt 4 buffer ngầm của mZone cho hệ thống (Không hiển thị đồ thị - INDICATOR_CALCULATIONS)
   SetIndexBuffer(22, MinorBuyZoneEntryBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(23, MinorBuyZoneSLBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(24, MinorSellZoneSLBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(25, MinorSellZoneEntryBuffer, INDICATOR_CALCULATIONS);

   ma_handle = iMA(_Symbol, _Period, MovingAveragePeriods, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(ChartID(), "IND_SMC_"); }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   int lookBack_max = MathMax(lookBackMajor, lookBackMinor);
   if(rates_total < lookBack_max + 1) return(0);

   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(open, true); ArraySetAsSeries(close, true); ArraySetAsSeries(time, true);
   ArraySetAsSeries(majorSwingHigh, true); ArraySetAsSeries(majorSwingLow, true); ArraySetAsSeries(EMA_Buffer, true);
   ArraySetAsSeries(HAOpen, true); ArraySetAsSeries(HAHigh, true); ArraySetAsSeries(HALow, true); ArraySetAsSeries(HAClose, true); ArraySetAsSeries(HAColor, true);
   ArraySetAsSeries(HAOpenDisp, true); ArraySetAsSeries(HAHighDisp, true); ArraySetAsSeries(HALowDisp, true); ArraySetAsSeries(HACloseDisp, true);
   ArraySetAsSeries(minorSwingHigh, true); ArraySetAsSeries(minorSwingLow, true);
   
   ArraySetAsSeries(MajorTrendBuffer, true); ArraySetAsSeries(MinorTrendBuffer, true);
   ArraySetAsSeries(MajorEventBuffer, true); ArraySetAsSeries(MinorEventBuffer, true);
   ArraySetAsSeries(MajorProtHighBuffer, true); ArraySetAsSeries(MajorProtLowBuffer, true);
   ArraySetAsSeries(MinorProtHighBuffer, true); ArraySetAsSeries(MinorProtLowBuffer, true);
   ArraySetAsSeries(BuyZoneEntryBuffer, true); ArraySetAsSeries(BuyZoneSLBuffer, true);
   ArraySetAsSeries(SellZoneSLBuffer, true); ArraySetAsSeries(SellZoneEntryBuffer, true);

   // Thiết lập chuỗi Series cho mZone buffer phục vụ Bot
   ArraySetAsSeries(MinorBuyZoneEntryBuffer, true); ArraySetAsSeries(MinorBuyZoneSLBuffer, true);
   ArraySetAsSeries(MinorSellZoneSLBuffer, true); ArraySetAsSeries(MinorSellZoneEntryBuffer, true);

   if(prev_calculated == 0) {
      ObjectsDeleteAll(ChartID(), "IND_SMC_");
      ArrayInitialize(majorSwingHigh, EMPTY_VALUE); ArrayInitialize(majorSwingLow, EMPTY_VALUE);
      ArrayInitialize(HAOpenDisp, EMPTY_VALUE); ArrayInitialize(HAHighDisp, EMPTY_VALUE); ArrayInitialize(HALowDisp, EMPTY_VALUE); ArrayInitialize(HACloseDisp, EMPTY_VALUE);
      ArrayInitialize(minorSwingHigh, EMPTY_VALUE); ArrayInitialize(minorSwingLow, EMPTY_VALUE);
      ArrayInitialize(MajorTrendBuffer, EMPTY_VALUE); ArrayInitialize(MinorTrendBuffer, EMPTY_VALUE);
      ArrayInitialize(MajorEventBuffer, 0); ArrayInitialize(MinorEventBuffer, 0); 
      ArrayInitialize(MajorProtHighBuffer, EMPTY_VALUE); ArrayInitialize(MajorProtLowBuffer, EMPTY_VALUE);
      ArrayInitialize(MinorProtHighBuffer, EMPTY_VALUE); ArrayInitialize(MinorProtLowBuffer, EMPTY_VALUE);
      ArrayInitialize(BuyZoneEntryBuffer, EMPTY_VALUE); ArrayInitialize(BuyZoneSLBuffer, EMPTY_VALUE);
      ArrayInitialize(SellZoneSLBuffer, EMPTY_VALUE); ArrayInitialize(SellZoneEntryBuffer, EMPTY_VALUE);
      
      ArrayInitialize(MinorBuyZoneEntryBuffer, EMPTY_VALUE); ArrayInitialize(MinorBuyZoneSLBuffer, EMPTY_VALUE);
      ArrayInitialize(MinorSellZoneSLBuffer, EMPTY_VALUE); ArrayInitialize(MinorSellZoneEntryBuffer, EMPTY_VALUE);

      ActiveHigh.isActive = false; ActiveLow.isActive = false; ActiveMinorHigh.isActive = false; ActiveMinorLow.isActive = false; 
      ActiveHigh.idx = -1; ActiveLow.idx = -1; ActiveMinorHigh.idx = -1; ActiveMinorLow.idx = -1;
      
      major_trend = 0; maj_prot_high = EMPTY_VALUE; maj_prot_high_time = 0; maj_prot_high_idx = -1;
      maj_prot_low = EMPTY_VALUE;  maj_prot_low_time = 0;  maj_prot_low_idx = -1;
      maj_extreme_high = EMPTY_VALUE;   maj_extreme_high_time = 0; maj_extreme_high_idx = -1;
      maj_extreme_low = EMPTY_VALUE;    maj_extreme_low_time = 0;  maj_extreme_low_idx = -1;
      last_maj_high = EMPTY_VALUE; last_maj_high_time = 0; last_maj_high_idx = -1;
      last_maj_low = EMPTY_VALUE;  last_maj_low_time = 0;  last_maj_low_idx = -1;
      
      maj_confirmed_extreme_high = EMPTY_VALUE; maj_confirmed_extreme_high_time = 0;
      maj_confirmed_extreme_low = EMPTY_VALUE;  maj_confirmed_extreme_low_time = 0;

      pending_prot_high_update = false; pending_prot_low_update = false;
      processed_prot_weak_high_time = 0; processed_prot_weak_low_time = 0;
      prot_anchor_time = 0; prot_anchor_idx = -1; prot_breakout_idx = -1;

      minor_trend = 0; min_prot_high = EMPTY_VALUE; min_prot_high_time = 0; min_prot_high_idx = -1;
      min_prot_low = EMPTY_VALUE;  min_prot_low_time = 0;  min_prot_low_idx = -1;
      min_extreme_high = EMPTY_VALUE;   min_extreme_high_time = 0; min_extreme_high_idx = -1;
      min_extreme_low = EMPTY_VALUE;    min_extreme_low_time = 0;  min_extreme_low_idx = -1;
      last_min_high = EMPTY_VALUE; last_min_high_time = 0; last_min_high_idx = -1;
      last_min_low = EMPTY_VALUE;  last_min_low_time = 0;  last_min_low_idx = -1;
      
      min_confirmed_extreme_high = EMPTY_VALUE; min_confirmed_extreme_high_time = 0;
      min_confirmed_extreme_low = EMPTY_VALUE;  min_confirmed_extreme_low_time = 0;

      min_pending_prot_high_update = false; min_pending_prot_low_update = false;
      min_processed_prot_weak_high_time = 0; min_processed_prot_weak_low_time = 0;
      min_prot_anchor_time = 0; min_prot_anchor_idx = -1; min_prot_breakout_idx = -1;
      
      is_maj_prot_high_sweep = false; is_maj_prot_low_sweep = false;
      is_min_prot_high_sweep = false; is_min_prot_low_sweep = false;

      last_processed_high_time = 0; last_processed_low_time = 0; 
      last_break_dir = 0; last_break_type = 0;
      latest_break_up_time = 0; latest_break_up_idx = -1; latest_break_up_level = EMPTY_VALUE;
      latest_break_down_time = 0; latest_break_down_idx = -1; latest_break_down_level = EMPTY_VALUE;

      ArrayResize(BOSUpQueue, 0); ArrayResize(BOSDnQueue, 0); ArrayResize(BuyZonesQueue, 0); ArrayResize(SellZonesQueue, 0);
      ArrayResize(MinorBOSUpQueue, 0); ArrayResize(MinorBOSDnQueue, 0);
      ArrayResize(MinorBuyZonesQueue, 0); ArrayResize(MinorSellZonesQueue, 0);
      g_choch_up_name = ""; g_choch_dn_name = "";
      g_minor_choch_up_name = ""; g_minor_choch_dn_name = "";
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
      if(prot_breakout_idx >= 0) prot_breakout_idx += shift;
      if(prot_anchor_idx >= 0) prot_anchor_idx += shift;
      if(min_prot_breakout_idx >= 0) min_prot_breakout_idx += shift;
      if(min_prot_anchor_idx >= 0) min_prot_anchor_idx += shift;
   }

   int limit = (prev_calculated == 0) ? rates_total - lookBack_max - 1 : (rates_total - prev_calculated) + lookBack_max;
   if (limit >= rates_total - lookBack_max) limit = rates_total - lookBack_max - 1;

   for(int i = limit + lookBack_max; i >= 0; i--) {
      HAClose[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      if(i >= rates_total - 1) HAOpen[i] = (open[i] + close[i]) / 2.0; else HAOpen[i] = (HAOpen[i+1] + HAClose[i+1]) / 2.0;
      HAHigh[i] = MathMax(high[i], MathMax(HAOpen[i], HAClose[i])); HALow[i]  = MathMin(low[i], MathMin(HAOpen[i], HAClose[i]));
      HAColor[i] = (HAClose[i] >= HAOpen[i]) ? 0 : 1;
      if (ShowHACandles) { HAOpenDisp[i] = HAOpen[i]; HAHighDisp[i] = HAHigh[i]; HALowDisp[i] = HALow[i]; HACloseDisp[i] = HAClose[i]; }
      else { HAOpenDisp[i] = EMPTY_VALUE; HAHighDisp[i] = EMPTY_VALUE; HALowDisp[i] = EMPTY_VALUE; HACloseDisp[i] = EMPTY_VALUE; }
   }
   int ema_copy_count = (prev_calculated == 0) ? rates_total : (rates_total - prev_calculated + 1);
   if(CopyBuffer(ma_handle, 0, 0, ema_copy_count, EMA_Buffer) <= 0) return(0);

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

      if(maj_prot_high != EMPTY_VALUE && !is_maj_prot_high_sweep) { if(maj_prot_high_idx >= 0 && maj_prot_high_idx < rates_total && majorSwingHigh[maj_prot_high_idx] == EMPTY_VALUE) { maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1; } }
      if(maj_prot_low != EMPTY_VALUE && !is_maj_prot_low_sweep) { if(maj_prot_low_idx >= 0 && maj_prot_low_idx < rates_total && majorSwingLow[maj_prot_low_idx] == EMPTY_VALUE) { maj_prot_low = EMPTY_VALUE; maj_prot_low_idx = -1; } }
      if(min_prot_high != EMPTY_VALUE && !is_min_prot_high_sweep) { if(min_prot_high_idx >= 0 && min_prot_high_idx < rates_total && minorSwingHigh[min_prot_high_idx] == EMPTY_VALUE) { min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1; } }
      if(min_prot_low != EMPTY_VALUE && !is_min_prot_low_sweep) { if(min_prot_low_idx >= 0 && min_prot_low_idx < rates_total && minorSwingLow[min_prot_low_idx] == EMPTY_VALUE) { min_prot_low = EMPTY_VALUE; min_prot_low_idx = -1; } }

      // ==========================================
      // MAJOR SWING TRACKING
      // ==========================================
      int swingMajor_idx = i + PeriodsInMajorSwing;
      if (swingMajor_idx < rates_total) {
         if(majorSwingHigh[swingMajor_idx] != EMPTY_VALUE) { 
            ActiveHigh.price = majorSwingHigh[swingMajor_idx]; ActiveHigh.time = time[swingMajor_idx]; ActiveHigh.isActive = true; ActiveHigh.idx = swingMajor_idx;
            last_maj_high = ActiveHigh.price; last_maj_high_time = ActiveHigh.time; last_maj_high_idx = swingMajor_idx;
            
            if (major_trend == 1 && majorSwingHigh[swingMajor_idx] == maj_extreme_high) {
                maj_confirmed_extreme_high = majorSwingHigh[swingMajor_idx]; maj_confirmed_extreme_high_time = time[swingMajor_idx];
            }

            if (time[swingMajor_idx] > last_processed_high_time) {
                last_processed_high_time = time[swingMajor_idx];
                if (last_break_dir == -1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_down_time) {
                    int b_idx = latest_break_down_idx;
                    if (b_idx != -1) {
                        string zone_name = "IND_SMC_ZONE_SELL_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZone(zone_name, swingMajor_idx, b_idx, true, latest_break_down_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                        PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                }
            }
         }
         
         if(majorSwingLow[swingMajor_idx] != EMPTY_VALUE) { 
            ActiveLow.price = majorSwingLow[swingMajor_idx]; ActiveLow.time = time[swingMajor_idx]; ActiveLow.isActive = true; ActiveLow.idx = swingMajor_idx;
            last_maj_low = ActiveLow.price; last_maj_low_time = ActiveLow.time; last_maj_low_idx = swingMajor_idx;
            
            if (major_trend == -1 && majorSwingLow[swingMajor_idx] == maj_extreme_low) {
                maj_confirmed_extreme_low = majorSwingLow[swingMajor_idx]; maj_confirmed_extreme_low_time = time[swingMajor_idx];
            }

            if (time[swingMajor_idx] > last_processed_low_time) {
                last_processed_low_time = time[swingMajor_idx];
                if (last_break_dir == 1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_up_time) {
                    int b_idx = latest_break_up_idx;
                    if (b_idx != -1) {
                        string zone_name = "IND_SMC_ZONE_BUY_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZone(zone_name, swingMajor_idx, b_idx, false, latest_break_up_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                        PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                    }
                }
            }
         }
      }
      
      // ==========================================
      // MINOR SWING TRACKING (FRACTAL)
      // ==========================================
      int swingMinor_idx = i + PeriodsInMinorSwing;
      if (swingMinor_idx < rates_total) {
         if(minorSwingHigh[swingMinor_idx] != EMPTY_VALUE) { 
            ActiveMinorHigh.price = minorSwingHigh[swingMinor_idx]; ActiveMinorHigh.time = time[swingMinor_idx]; ActiveMinorHigh.isActive = true; ActiveMinorHigh.idx = swingMinor_idx; 
            last_min_high = ActiveMinorHigh.price; last_min_high_time = ActiveMinorHigh.time; last_min_high_idx = swingMinor_idx; 
            
            if (minor_trend == 1 && minorSwingHigh[swingMinor_idx] == min_extreme_high) {
                min_confirmed_extreme_high = minorSwingHigh[swingMinor_idx]; min_confirmed_extreme_high_time = time[swingMinor_idx];
            }
         }
         
         if(minorSwingLow[swingMinor_idx] != EMPTY_VALUE) { 
            ActiveMinorLow.price = minorSwingLow[swingMinor_idx]; ActiveMinorLow.time = time[swingMinor_idx]; ActiveMinorLow.isActive = true; ActiveMinorLow.idx = swingMinor_idx; 
            last_min_low = ActiveMinorLow.price; last_min_low_time = ActiveMinorLow.time; last_min_low_idx = swingMinor_idx;
            
            if (minor_trend == -1 && minorSwingLow[swingMinor_idx] == min_extreme_low) {
                min_confirmed_extreme_low = minorSwingLow[swingMinor_idx]; min_confirmed_extreme_low_time = time[swingMinor_idx];
            }
         }
      }

      if (major_trend == 1) {
         if (maj_extreme_high == EMPTY_VALUE || high[i] > maj_extreme_high) { maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i; }
      } else if (major_trend == -1) {
         if (maj_extreme_low == EMPTY_VALUE || low[i] < maj_extreme_low) { maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i; }
      }

      if (minor_trend == 1) { 
         if (min_extreme_high == EMPTY_VALUE || high[i] > min_extreme_high) { min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i; } 
      } else if (minor_trend == -1) { 
         if (min_extreme_low == EMPTY_VALUE || low[i] < min_extreme_low) { min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i; } 
      }

      if(i > 0)
      {
         // KHỞI TẠO XU HƯỚNG MỒI (DEADLOCK PREVENTION)
         if (major_trend == 0) {
            if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) { 
                major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i; 
                maj_prot_low = (last_maj_low != EMPTY_VALUE) ? last_maj_low : low[i]; maj_prot_low_time = (last_maj_low_time != 0) ? last_maj_low_time : time[i]; maj_prot_low_idx = (last_maj_low_idx != -1) ? last_maj_low_idx : i; 
                is_maj_prot_low_sweep = false; 
            } 
            else if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) { 
                major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i; 
                maj_prot_high = (last_maj_high != EMPTY_VALUE) ? last_maj_high : high[i]; maj_prot_high_time = (last_maj_high_time != 0) ? last_maj_high_time : time[i]; maj_prot_high_idx = (last_maj_high_idx != -1) ? last_maj_high_idx : i; 
                is_maj_prot_high_sweep = false; 
            }
         }
         
         if (minor_trend == 0) {
            if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) { 
                minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i; 
                min_prot_low = (last_min_low != EMPTY_VALUE) ? last_min_low : low[i]; min_prot_low_time = (last_min_low_time != 0) ? last_min_low_time : time[i]; min_prot_low_idx = (last_min_low_idx != -1) ? last_min_low_idx : i; 
                is_min_prot_low_sweep = false; 
            } 
            else if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) { 
                minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i; 
                min_prot_high = (last_min_high != EMPTY_VALUE) ? last_min_high : high[i]; min_prot_high_time = (last_min_high_time != 0) ? last_min_high_time : time[i]; min_prot_high_idx = (last_min_high_idx != -1) ? last_min_high_idx : i; 
                is_min_prot_high_sweep = false; 
            }
         }

         // =========================================================================
         // MAJOR: KÍCH HOẠT RADAR PENDING & THỰC THI
         // =========================================================================
         // Uptrend: HA phá Weak High → Immediate set Protected Low = last_maj_low + D5 scan
         // Radar tiếp tục tìm D4 mới hơn (gần BOS hơn, chưa confirm lúc trigger)
         if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE &&
             HAClose[i] > maj_confirmed_extreme_high &&
             processed_prot_weak_high_time != maj_confirmed_extreme_high_time) {
             processed_prot_weak_high_time = maj_confirmed_extreme_high_time;
             if (last_maj_low != EMPTY_VALUE) {
                 double imm_d4 = last_maj_low; datetime imm_d4_t = last_maj_low_time; int imm_d4_idx = last_maj_low_idx;
                 double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                 for (int k = last_maj_low_idx; k >= i; k--) {
                     if (low[k] < imm_d5) { imm_d5 = low[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                 }
                 if (imm_d5 < imm_d4) { maj_prot_low = imm_d5; maj_prot_low_time = imm_d5_t; maj_prot_low_idx = imm_d5_idx; is_maj_prot_low_sweep = true; }
                 else                  { maj_prot_low = imm_d4; maj_prot_low_time = imm_d4_t; maj_prot_low_idx = imm_d4_idx; is_maj_prot_low_sweep = false; }
                 pending_prot_low_update = true;
                 prot_anchor_time = last_maj_low_time;
                 prot_anchor_idx = last_maj_low_idx;
                 prot_breakout_idx = i;
             }
         }

         // Downtrend: HA phá Weak Low → Immediate set Protected High = last_maj_high + D5 scan
         // Radar tiếp tục tìm D4 mới hơn (gần BOS hơn, chưa confirm lúc trigger)
         if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE &&
             HAClose[i] < maj_confirmed_extreme_low &&
             processed_prot_weak_low_time != maj_confirmed_extreme_low_time) {
             processed_prot_weak_low_time = maj_confirmed_extreme_low_time;
             if (last_maj_high != EMPTY_VALUE) {
                 double imm_d4 = last_maj_high; datetime imm_d4_t = last_maj_high_time; int imm_d4_idx = last_maj_high_idx;
                 double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                 for (int k = last_maj_high_idx; k >= i; k--) {
                     if (high[k] > imm_d5) { imm_d5 = high[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                 }
                 if (imm_d5 > imm_d4) { maj_prot_high = imm_d5; maj_prot_high_time = imm_d5_t; maj_prot_high_idx = imm_d5_idx; is_maj_prot_high_sweep = true; }
                 else                  { maj_prot_high = imm_d4; maj_prot_high_time = imm_d4_t; maj_prot_high_idx = imm_d4_idx; is_maj_prot_high_sweep = false; }
                 pending_prot_high_update = true;
                 prot_anchor_time = last_maj_high_time;
                 prot_anchor_idx = last_maj_high_idx;
                 prot_breakout_idx = i;
             }
         }

         if (major_trend == 1 && pending_prot_low_update && prot_breakout_idx != -1) {
             double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
             int anchor_idx = prot_anchor_idx;
             if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx) {
                 for(int k = prot_breakout_idx; k <= anchor_idx; k++) {
                     if (majorSwingLow[k] != EMPTY_VALUE) { d4_val = majorSwingLow[k]; d4_time = time[k]; d4_idx = k; break; }
                 }
                 if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = prot_breakout_idx; k <= d4_idx; k++) {
                         if (d5_val == EMPTY_VALUE || low[k] < d5_val) { d5_val = low[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val < d4_val) { maj_prot_low = d5_val; maj_prot_low_time = d5_time; maj_prot_low_idx = d5_idx; is_maj_prot_low_sweep = true; } 
                     else { maj_prot_low = d4_val; maj_prot_low_time = d4_time; maj_prot_low_idx = d4_idx; is_maj_prot_low_sweep = false; }
                     
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) { pending_prot_low_update = false; }
                 } else {
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) { pending_prot_low_update = false; }
                 }
             } else { pending_prot_low_update = false; }
         }

         if (major_trend == -1 && pending_prot_high_update && prot_breakout_idx != -1) {
             double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
             int anchor_idx = prot_anchor_idx;
             if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx) {
                 for(int k = prot_breakout_idx; k <= anchor_idx; k++) {
                     if (majorSwingHigh[k] != EMPTY_VALUE) { d4_val = majorSwingHigh[k]; d4_time = time[k]; d4_idx = k; break; }
                 }
                 if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = prot_breakout_idx; k <= d4_idx; k++) {
                         if (d5_val == EMPTY_VALUE || high[k] > d5_val) { d5_val = high[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val > d4_val) { maj_prot_high = d5_val; maj_prot_high_time = d5_time; maj_prot_high_idx = d5_idx; is_maj_prot_high_sweep = true; } 
                     else { maj_prot_high = d4_val; maj_prot_high_time = d4_time; maj_prot_high_idx = d4_idx; is_maj_prot_high_sweep = false; }
                     
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) { pending_prot_high_update = false; }
                 } else {
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) { pending_prot_high_update = false; }
                 }
             } else { pending_prot_high_update = false; }
         }

         // =========================================================================
         // MINOR: KÍCH HOẠT RADAR PENDING & THỰC THI (FRACTAL)
         // =========================================================================
         // Minor Uptrend: HA phá Weak High → Immediate set Protected Low = last_min_low + D5 scan
         if (minor_trend == 1 && min_confirmed_extreme_high != EMPTY_VALUE &&
             HAClose[i] > min_confirmed_extreme_high &&
             min_processed_prot_weak_high_time != min_confirmed_extreme_high_time) {
             min_processed_prot_weak_high_time = min_confirmed_extreme_high_time;
             if (last_min_low != EMPTY_VALUE) {
                 double imm_d4 = last_min_low; datetime imm_d4_t = last_min_low_time; int imm_d4_idx = last_min_low_idx;
                 double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                 for (int k = last_min_low_idx; k >= i; k--) {
                     if (low[k] < imm_d5) { imm_d5 = low[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                 }
                 if (imm_d5 < imm_d4) { min_prot_low = imm_d5; min_prot_low_time = imm_d5_t; min_prot_low_idx = imm_d5_idx; is_min_prot_low_sweep = true; }
                 else                  { min_prot_low = imm_d4; min_prot_low_time = imm_d4_t; min_prot_low_idx = imm_d4_idx; is_min_prot_low_sweep = false; }
                 min_pending_prot_low_update = true;
                 min_prot_anchor_time = last_min_low_time;
                 min_prot_anchor_idx = last_min_low_idx;
                 min_prot_breakout_idx = i;
             }
         }

         // Minor Downtrend: HA phá Weak Low → Immediate set Protected High = last_min_high + D5 scan
         if (minor_trend == -1 && min_confirmed_extreme_low != EMPTY_VALUE &&
             HAClose[i] < min_confirmed_extreme_low &&
             min_processed_prot_weak_low_time != min_confirmed_extreme_low_time) {
             min_processed_prot_weak_low_time = min_confirmed_extreme_low_time;
             if (last_min_high != EMPTY_VALUE) {
                 double imm_d4 = last_min_high; datetime imm_d4_t = last_min_high_time; int imm_d4_idx = last_min_high_idx;
                 double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                 for (int k = last_min_high_idx; k >= i; k--) {
                     if (high[k] > imm_d5) { imm_d5 = high[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                 }
                 if (imm_d5 > imm_d4) { min_prot_high = imm_d5; min_prot_high_time = imm_d5_t; min_prot_high_idx = imm_d5_idx; is_min_prot_high_sweep = true; }
                 else                  { min_prot_high = imm_d4; min_prot_high_time = imm_d4_t; min_prot_high_idx = imm_d4_idx; is_min_prot_high_sweep = false; }
                 min_pending_prot_high_update = true;
                 min_prot_anchor_time = last_min_high_time;
                 min_prot_anchor_idx = last_min_high_idx;
                 min_prot_breakout_idx = i;
             }
         }

         if (minor_trend == 1 && min_pending_prot_low_update && min_prot_breakout_idx != -1) {
             double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
             int anchor_idx = min_prot_anchor_idx;
             if (anchor_idx != -1 && min_prot_breakout_idx <= anchor_idx) {
                 for(int k = min_prot_breakout_idx; k <= anchor_idx; k++) {
                     if (minorSwingLow[k] != EMPTY_VALUE) { d4_val = minorSwingLow[k]; d4_time = time[k]; d4_idx = k; break; }
                 }
                 if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = min_prot_breakout_idx; k <= d4_idx; k++) {
                         if (d5_val == EMPTY_VALUE || low[k] < d5_val) { d5_val = low[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val < d4_val) { min_prot_low = d5_val; min_prot_low_time = d5_time; min_prot_low_idx = d5_idx; is_min_prot_low_sweep = true; } 
                     else { min_prot_low = d4_val; min_prot_low_time = d4_time; min_prot_low_idx = d4_idx; is_min_prot_low_sweep = false; }
                     
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) { min_pending_prot_low_update = false; }
                 } else {
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) { min_pending_prot_low_update = false; }
                 }
             } else { min_pending_prot_low_update = false; }
         }

         if (minor_trend == -1 && min_pending_prot_high_update && min_prot_breakout_idx != -1) {
             double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
             int anchor_idx = min_prot_anchor_idx;
             if (anchor_idx != -1 && min_prot_breakout_idx <= anchor_idx) {
                 for(int k = min_prot_breakout_idx; k <= anchor_idx; k++) {
                     if (minorSwingHigh[k] != EMPTY_VALUE) { d4_val = minorSwingHigh[k]; d4_time = time[k]; d4_idx = k; break; }
                 }
                 if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = min_prot_breakout_idx; k <= d4_idx; k++) {
                         if (d5_val == EMPTY_VALUE || high[k] > d5_val) { d5_val = high[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val > d4_val) { min_prot_high = d5_val; min_prot_high_time = d5_time; min_prot_high_idx = d5_idx; is_min_prot_high_sweep = true; } 
                     else { min_prot_high = d4_val; min_prot_high_time = d4_time; min_prot_high_idx = d4_idx; is_min_prot_high_sweep = false; }
                     
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) { min_pending_prot_high_update = false; }
                 } else {
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) { min_pending_prot_high_update = false; }
                 }
             } else { min_pending_prot_high_update = false; }
         }

         // Dọn dẹp quét vùng nến phá vỡ SL đối với cấu trúc Major Zone
         for(int j = ArraySize(BuyZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] < BuyZonesQueue[j].stopPrice) { ObjectDelete(ChartID(), BuyZonesQueue[j].name); for(int k = j; k < ArraySize(BuyZonesQueue) - 1; k++) BuyZonesQueue[k] = BuyZonesQueue[k+1]; ArrayResize(BuyZonesQueue, ArraySize(BuyZonesQueue) - 1); } }
         for(int j = ArraySize(SellZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] > SellZonesQueue[j].stopPrice) { ObjectDelete(ChartID(), SellZonesQueue[j].name); for(int k = j; k < ArraySize(SellZonesQueue) - 1; k++) SellZonesQueue[k] = SellZonesQueue[k+1]; ArrayResize(SellZonesQueue, ArraySize(SellZonesQueue) - 1); } }

         // Quét dọn bộ nhớ và xóa mảng ngầm khi giá vi phạm điểm SL của Minor Zone (mZone)
         for(int j = ArraySize(MinorBuyZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] < MinorBuyZonesQueue[j].stopPrice) { ObjectDelete(ChartID(), MinorBuyZonesQueue[j].name); for(int k = j; k < ArraySize(MinorBuyZonesQueue) - 1; k++) MinorBuyZonesQueue[k] = MinorBuyZonesQueue[k+1]; ArrayResize(MinorBuyZonesQueue, ArraySize(MinorBuyZonesQueue) - 1); } }
         for(int j = ArraySize(MinorSellZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] > MinorSellZonesQueue[j].stopPrice) { ObjectDelete(ChartID(), MinorSellZonesQueue[j].name); for(int k = j; k < ArraySize(MinorSellZonesQueue) - 1; k++) MinorSellZonesQueue[k] = MinorSellZonesQueue[k+1]; ArrayResize(MinorSellZonesQueue, ArraySize(MinorSellZonesQueue) - 1); } }

         // =========================================================================
         // MAJOR: CHOCH & BOS LOGIC
         // =========================================================================
         bool is_major_choch_up = false; bool is_major_choch_dn = false;

         if (major_trend == 1 && maj_prot_low != EMPTY_VALUE && HAClose[i] < maj_prot_low) {
            string choch_name = "IND_SMC_CHOCH_DN_" + IntegerToString((long)maj_prot_low_time);
            if(ObjectFind(ChartID(), choch_name) < 0) {
               if (ShowMajorCHOCH) {
                   CreateBOSLine(choch_name, maj_prot_low_time, maj_prot_low, time[i], BOS_Down_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                   if(g_choch_up_name != "") { ObjectDelete(ChartID(), g_choch_up_name); ObjectDelete(ChartID(), g_choch_up_name + "_lbl"); g_choch_up_name = ""; }
                   g_choch_dn_name = choch_name;
               }
               MajorEventBuffer[i] = -2; ClearZoneQueue(BuyZonesQueue);

               double actual_extreme_high = maj_extreme_high; datetime actual_extreme_time = maj_extreme_high_time; int actual_extreme_idx = maj_extreme_high_idx;
               int prot_idx = maj_prot_low_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int highest_idx = ArrayMaximum(high, i, count);
                   if (highest_idx != -1) { actual_extreme_high = high[highest_idx]; actual_extreme_time = time[highest_idx]; actual_extreme_idx = highest_idx; }
               }
               
               ObjectDelete(ChartID(), "IND_SMC_MAJOR_KEY_LEVEL"); ObjectDelete(ChartID(), "IND_SMC_MAJOR_KEY_LEVEL_lbl");
               if (ShowKeyLevel) CreateRayLine("IND_SMC_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_high, KeyLevel_Color, "Major Key Level Down", true);
               
               last_break_dir = -1; last_break_type = 2; 
               latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = maj_prot_low;

               int zone_anchor_idx = actual_extreme_idx; 
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && majorSwingHigh[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if(zone_anchor_idx != -1) {
                  string zone_name = "IND_SMC_ZONE_SELL_CHOCH_" + IntegerToString((long)time[i]);
                  double zEntry, zStop;
                  CreateZone(zone_name, zone_anchor_idx, i, true, maj_prot_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                  PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
               }
               
               if (ActiveLow.time == maj_prot_low_time) ActiveLow.isActive = false; 
               ClearQueue(BOSUpQueue); 
               major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i;
               
               maj_confirmed_extreme_high = EMPTY_VALUE;
               maj_prot_high = actual_extreme_high; maj_prot_high_time = actual_extreme_time; maj_prot_high_idx = actual_extreme_idx; maj_prot_low = EMPTY_VALUE; maj_prot_low_idx = -1;
               is_maj_prot_high_sweep = true; 
               
               pending_prot_high_update = true;
               prot_anchor_time = actual_extreme_time;
               prot_anchor_idx = actual_extreme_idx;
               prot_breakout_idx = i;
               pending_prot_low_update = false;
            }
            is_major_choch_dn = true;
         }
         else if (major_trend == -1 && maj_prot_high != EMPTY_VALUE && HAClose[i] > maj_prot_high) {
            string choch_name = "IND_SMC_CHOCH_UP_" + IntegerToString((long)maj_prot_high_time);
            if(ObjectFind(ChartID(), choch_name) < 0) {
               if (ShowMajorCHOCH) {
                   CreateBOSLine(choch_name, maj_prot_high_time, maj_prot_high, time[i], BOS_Up_Color, "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                   if(g_choch_dn_name != "") { ObjectDelete(ChartID(), g_choch_dn_name); ObjectDelete(ChartID(), g_choch_dn_name + "_lbl"); g_choch_dn_name = ""; }
                   g_choch_up_name = choch_name;
               }
               MajorEventBuffer[i] = 2; ClearZoneQueue(SellZonesQueue);

               double actual_extreme_low = maj_extreme_low; datetime actual_extreme_time = maj_extreme_low_time; int actual_extreme_idx = maj_extreme_low_idx;
               int prot_idx = maj_prot_high_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int lowest_idx = ArrayMinimum(low, i, count);
                   if (lowest_idx != -1) { actual_extreme_low = low[lowest_idx]; actual_extreme_time = time[lowest_idx]; actual_extreme_idx = lowest_idx; }
               }
               
               ObjectDelete(ChartID(), "IND_SMC_MAJOR_KEY_LEVEL"); ObjectDelete(ChartID(), "IND_SMC_MAJOR_KEY_LEVEL_lbl");
               if (ShowKeyLevel) CreateRayLine("IND_SMC_MAJOR_KEY_LEVEL", actual_extreme_time, actual_extreme_low, KeyLevel_Color, "Major Key Level Up", false);
               
               last_break_dir = 1; last_break_type = 2; 
               latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = maj_prot_high;

               int zone_anchor_idx = actual_extreme_idx; 
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && majorSwingLow[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if(zone_anchor_idx != -1) {
                  string zone_name = "IND_SMC_ZONE_BUY_CHOCH_" + IntegerToString((long)time[i]);
                  double zEntry, zStop;
                  CreateZone(zone_name, zone_anchor_idx, i, false, maj_prot_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                  PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
               }
               
               if (ActiveHigh.time == maj_prot_high_time) ActiveHigh.isActive = false; ClearQueue(BOSDnQueue); 
               major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i;
               
               maj_confirmed_extreme_low = EMPTY_VALUE;
               maj_prot_low = actual_extreme_low; maj_prot_low_time = actual_extreme_time; maj_prot_low_idx = actual_extreme_idx; maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1;
               is_maj_prot_low_sweep = true; 
               
               pending_prot_low_update = true;
               prot_anchor_time = actual_extreme_time;
               prot_anchor_idx = actual_extreme_idx;
               prot_breakout_idx = i;
               pending_prot_high_update = false;
            }
            is_major_choch_up = true;
         }

         if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) {
            if (!is_major_choch_up) { 
                string bos_name = "IND_SMC_BOS_UP_" + IntegerToString((long)ActiveHigh.time);
                if(ObjectFind(ChartID(), bos_name) < 0) {
                   if (ShowMajorBOS) {
                       CreateBOSLine(bos_name, ActiveHigh.time, ActiveHigh.price, time[i], BOS_Up_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                       PushBOS(BOSUpQueue, bos_name, MaxBOSLines);
                   }
                   MajorEventBuffer[i] = 1;
                   last_break_dir = 1; last_break_type = 1;
                   latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = ActiveHigh.price;

                   int origin_idx = last_maj_low_idx;
                   if (origin_idx != -1) {
                      string zone_name = "IND_SMC_ZONE_BUY_BOS_" + IntegerToString((long)last_maj_low_time);
                      double zEntry, zStop;
                      CreateZone(zone_name, origin_idx, i, false, ActiveHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                      PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveHigh.isActive = false; 
         }

         if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) {
            if (!is_major_choch_dn) { 
                string bos_name = "IND_SMC_BOS_DN_" + IntegerToString((long)ActiveLow.time);
                if(ObjectFind(ChartID(), bos_name) < 0) {
                   if (ShowMajorBOS) {
                       CreateBOSLine(bos_name, ActiveLow.time, ActiveLow.price, time[i], BOS_Down_Color, "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                       PushBOS(BOSDnQueue, bos_name, MaxBOSLines);
                   }
                   MajorEventBuffer[i] = -1;
                   last_break_dir = -1; last_break_type = 1;
                   latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = ActiveLow.price;

                   int origin_idx = last_maj_high_idx;
                   if (origin_idx != -1) {
                      string zone_name = "IND_SMC_ZONE_SELL_BOS_" + IntegerToString((long)last_maj_high_time);
                      double zEntry, zStop;
                      CreateZone(zone_name, origin_idx, i, true, ActiveLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, ShowSDZones);
                      PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveLow.isActive = false;
         }

         // =========================================================================
         // MINOR: CHOCH & BOS LOGIC (FRACTAL) - ĐỒNG BỘ MZONE TÍNH TOÁN NGẦM
         // =========================================================================
         bool is_minor_choch_up = false; bool is_minor_choch_dn = false;

         if (minor_trend == 1 && min_prot_low != EMPTY_VALUE && HAClose[i] < min_prot_low) {
            string m_choch_name = "IND_SMC_mCHOCH_DN_" + IntegerToString((long)min_prot_low_time);
            if(ObjectFind(ChartID(), m_choch_name) < 0) {
               if (ShowMinorBOSCHOCH) {
                   CreateBOSLine(m_choch_name, min_prot_low_time, min_prot_low, time[i], Minor_BOS_Down_Color, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                   if(g_minor_choch_up_name != "") { ObjectDelete(ChartID(), g_minor_choch_up_name); ObjectDelete(ChartID(), g_minor_choch_up_name + "_lbl"); g_minor_choch_up_name = ""; }
                   g_minor_choch_dn_name = m_choch_name;
               }
               MinorEventBuffer[i] = -2;

               double actual_extreme_high = min_extreme_high; datetime actual_extreme_time = min_extreme_high_time; int actual_extreme_idx = min_extreme_high_idx;
               int prot_idx = min_prot_low_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int highest_idx = ArrayMaximum(high, i, count);
                   if (highest_idx != -1) { actual_extreme_high = high[highest_idx]; actual_extreme_time = time[highest_idx]; actual_extreme_idx = highest_idx; }
               }
               
               // Tạo mZone ngầm khi Minor CHOCH Down xảy ra
               int zone_anchor_idx = actual_extreme_idx;
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMinorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && minorSwingHigh[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if (zone_anchor_idx != -1) {
                   string m_zone_name = "IND_SMC_mZONE_SELL_CHOCH_" + IntegerToString((long)time[i]);
                   double zEntry, zStop;
                   CreateZone(m_zone_name, zone_anchor_idx, i, true, min_prot_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, false);
                   PushZone(MinorSellZonesQueue, m_zone_name, zEntry, zStop, MaxZones);
               }

               if (ActiveMinorLow.time == min_prot_low_time) ActiveMinorLow.isActive = false; 
               ClearQueue(MinorBOSUpQueue); ClearZoneQueue(MinorBuyZonesQueue);
               minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i;
               
               min_confirmed_extreme_high = EMPTY_VALUE;
               min_prot_high = actual_extreme_high; min_prot_high_time = actual_extreme_time; min_prot_high_idx = actual_extreme_idx; min_prot_low = EMPTY_VALUE; min_prot_low_idx = -1;
               is_min_prot_high_sweep = true; 
               
               min_pending_prot_high_update = true;
               min_prot_anchor_time = actual_extreme_time;
               min_prot_anchor_idx = actual_extreme_idx;
               min_prot_breakout_idx = i;
               min_pending_prot_low_update = false;
            }
            is_minor_choch_dn = true;
         }
         else if (minor_trend == -1 && min_prot_high != EMPTY_VALUE && HAClose[i] > min_prot_high) {
            string m_choch_name = "IND_SMC_mCHOCH_UP_" + IntegerToString((long)min_prot_high_time);
            if(ObjectFind(ChartID(), m_choch_name) < 0) {
               if (ShowMinorBOSCHOCH) {
                   CreateBOSLine(m_choch_name, min_prot_high_time, min_prot_high, time[i], Minor_BOS_Up_Color, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                   if(g_minor_choch_dn_name != "") { ObjectDelete(ChartID(), g_minor_choch_dn_name); ObjectDelete(ChartID(), g_minor_choch_dn_name + "_lbl"); g_minor_choch_dn_name = ""; }
                   g_minor_choch_up_name = m_choch_name;
               }
               MinorEventBuffer[i] = 2;

               double actual_extreme_low = min_extreme_low; datetime actual_extreme_time = min_extreme_low_time; int actual_extreme_idx = min_extreme_low_idx;
               int prot_idx = min_prot_high_idx;
               if (prot_idx != -1 && prot_idx >= i) {
                   int count = prot_idx - i + 1;
                   int lowest_idx = ArrayMinimum(low, i, count);
                   if (lowest_idx != -1) { actual_extreme_low = low[lowest_idx]; actual_extreme_time = time[lowest_idx]; actual_extreme_idx = lowest_idx; }
               }
               
               // Tạo mZone ngầm khi Minor CHOCH Up xảy ra
               int zone_anchor_idx = actual_extreme_idx;
               if (actual_extreme_idx != -1) {
                   for (int k = i + PeriodsInMinorSwing; k <= actual_extreme_idx; k++) {
                       if (k < rates_total && minorSwingLow[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                   }
               }
               if (zone_anchor_idx != -1) {
                   string m_zone_name = "IND_SMC_mZONE_BUY_CHOCH_" + IntegerToString((long)time[i]);
                   double zEntry, zStop;
                   CreateZone(m_zone_name, zone_anchor_idx, i, false, min_prot_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, false);
                   PushZone(MinorBuyZonesQueue, m_zone_name, zEntry, zStop, MaxZones);
               }

               if (ActiveMinorHigh.time == min_prot_high_time) ActiveMinorHigh.isActive = false; ClearQueue(MinorBOSDnQueue); ClearZoneQueue(MinorSellZonesQueue);
               minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i;
               
               min_confirmed_extreme_low = EMPTY_VALUE;
               min_prot_low = actual_extreme_low; min_prot_low_time = actual_extreme_time; min_prot_low_idx = actual_extreme_idx; min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1;
               is_min_prot_low_sweep = true; 
               
               min_pending_prot_low_update = true;
               min_prot_anchor_time = actual_extreme_time;
               min_prot_anchor_idx = actual_extreme_idx;
               min_prot_breakout_idx = i;
               min_pending_prot_high_update = false;
            }
            is_minor_choch_up = true;
         }

         if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) {
            if (!is_minor_choch_up) { 
                string m_bos_name = "IND_SMC_mBOS_UP_" + IntegerToString((long)ActiveMinorHigh.time);
                if(ObjectFind(ChartID(), m_bos_name) < 0) {
                   if (ShowMinorBOSCHOCH) {
                       CreateBOSLine(m_bos_name, ActiveMinorHigh.time, ActiveMinorHigh.price, time[i], Minor_BOS_Up_Color, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                       PushBOS(MinorBOSUpQueue, m_bos_name, MaxMinorBOSLines);
                   }
                   MinorEventBuffer[i] = 1; 

                   // Đẩy mZone ngầm của Minor BOS Up vào hệ thống bộ nhớ
                   int origin_idx = last_min_low_idx;
                   if (origin_idx != -1) {
                      string m_zone_name = "IND_SMC_mZONE_BUY_BOS_" + IntegerToString((long)last_min_low_time);
                      double zEntry, zStop;
                      CreateZone(m_zone_name, origin_idx, i, false, ActiveMinorHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, false);
                      PushZone(MinorBuyZonesQueue, m_zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveMinorHigh.isActive = false; 
         }

         if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) {
            if (!is_minor_choch_dn) { 
                string m_bos_name = "IND_SMC_mBOS_DN_" + IntegerToString((long)ActiveMinorLow.time);
                if(ObjectFind(ChartID(), m_bos_name) < 0) {
                   if (ShowMinorBOSCHOCH) {
                       CreateBOSLine(m_bos_name, ActiveMinorLow.time, ActiveMinorLow.price, time[i], Minor_BOS_Down_Color, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                       PushBOS(MinorBOSDnQueue, m_bos_name, MaxMinorBOSLines);
                   }
                   MinorEventBuffer[i] = -1; 

                   // Đẩy mZone ngầm của Minor BOS Down vào hệ thống bộ nhớ
                   int origin_idx = last_min_high_idx;
                   if (origin_idx != -1) {
                      string m_zone_name = "IND_SMC_mZONE_SELL_BOS_" + IntegerToString((long)last_min_high_time);
                      double zEntry, zStop;
                      CreateZone(m_zone_name, origin_idx, i, true, ActiveMinorLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, false);
                      PushZone(MinorSellZonesQueue, m_zone_name, zEntry, zStop, MaxZones);
                   }
                }
            }
            ActiveMinorLow.isActive = false;
         }
      } // Kết thúc block i > 0

      MajorTrendBuffer[i] = major_trend; MinorTrendBuffer[i] = minor_trend;
      MajorProtHighBuffer[i] = maj_prot_high; MajorProtLowBuffer[i]  = maj_prot_low;
      MinorProtHighBuffer[i] = min_prot_high; MinorProtLowBuffer[i]  = min_prot_low;

      if (ArraySize(BuyZonesQueue) > 0) { BuyZoneEntryBuffer[i] = BuyZonesQueue[0].entryPrice; BuyZoneSLBuffer[i] = BuyZonesQueue[0].stopPrice; } else { BuyZoneEntryBuffer[i] = EMPTY_VALUE; BuyZoneSLBuffer[i] = EMPTY_VALUE; }
      if (ArraySize(SellZonesQueue) > 0) { SellZoneSLBuffer[i] = SellZonesQueue[0].stopPrice; SellZoneEntryBuffer[i] = SellZonesQueue[0].entryPrice; } else { SellZoneSLBuffer[i] = EMPTY_VALUE; SellZoneEntryBuffer[i] = EMPTY_VALUE; }

      // Cập nhật giá trị mZone vào Buffer ngầm ở mỗi nến để Bot lấy thông tin bất kỳ lúc nào
      if (ArraySize(MinorBuyZonesQueue) > 0) { MinorBuyZoneEntryBuffer[i] = MinorBuyZonesQueue[0].entryPrice; MinorBuyZoneSLBuffer[i] = MinorBuyZonesQueue[0].stopPrice; } else { MinorBuyZoneEntryBuffer[i] = EMPTY_VALUE; MinorBuyZoneSLBuffer[i] = EMPTY_VALUE; }
      if (ArraySize(MinorSellZonesQueue) > 0) { MinorSellZoneEntryBuffer[i] = MinorSellZonesQueue[0].entryPrice; MinorSellZoneSLBuffer[i] = MinorSellZonesQueue[0].stopPrice; } else { MinorSellZoneEntryBuffer[i] = EMPTY_VALUE; MinorSellZoneSLBuffer[i] = EMPTY_VALUE; }

      if (i == 0) {
         if (major_trend == -1 && maj_prot_high != EMPTY_VALUE) { g_high_lvl = maj_prot_high; g_high_time = maj_prot_high_time; g_high_text = "Protected High"; } else if (ActiveHigh.isActive) { g_high_lvl = ActiveHigh.price; g_high_time = ActiveHigh.time; g_high_text = "Active High"; } else { g_high_lvl = EMPTY_VALUE; }
         if (major_trend == 1 && maj_prot_low != EMPTY_VALUE) { g_low_lvl = maj_prot_low; g_low_time = maj_prot_low_time; g_low_text = "Protected Low"; } else if (ActiveLow.isActive) { g_low_lvl = ActiveLow.price; g_low_time = ActiveLow.time; g_low_text = "Active Low"; } else { g_low_lvl = EMPTY_VALUE; }

         UpdateLevelLabels(time[0]);

         if ((ShowTrackingLines || ShowWeakHighLow || ShowLastMajorHighLow) && MQLInfoInteger(MQL_TESTER)) ChartRedraw(ChartID());
      }
   }
   return(rates_total);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if (id == CHARTEVENT_CHART_CHANGE) {
       if (ShowTrackingLines || ShowWeakHighLow || ShowLastMajorHighLow) {
           datetime t[];
           if (CopyTime(_Symbol, _Period, 0, 1, t) > 0) {
               UpdateLevelLabels(t[0]);
               ChartRedraw(ChartID());
           }
       }
   }
}

datetime GetRightEdgeTime(datetime current_time) { 
    if (MQLInfoInteger(MQL_TESTER)) return current_time + PeriodSeconds() * 15;
    int width = (int)ChartGetInteger(ChartID(), CHART_WIDTH_IN_BARS); 
    int first = (int)ChartGetInteger(ChartID(), CHART_FIRST_VISIBLE_BAR); 
    int future_offset = width - first - 2; if (future_offset < 1) future_offset = 1; 
    return current_time + future_offset * PeriodSeconds();
}

void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time) {
   if (p1 == EMPTY_VALUE || t1 == 0) { ObjectDelete(ChartID(), name + "_ray"); ObjectDelete(ChartID(), name + "_lbl"); return; }
   string ray_name = name + "_ray";
   if(ObjectFind(ChartID(), ray_name) < 0) { ObjectCreate(ChartID(), ray_name, OBJ_TREND, 0, t1, p1, current_time + PeriodSeconds(), p1); ObjectSetInteger(ChartID(), ray_name, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), ray_name, OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(ChartID(), ray_name, OBJPROP_WIDTH, 1); ObjectSetInteger(ChartID(), ray_name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(ChartID(), ray_name, OBJPROP_BACK, false); } else { ObjectSetInteger(ChartID(), ray_name, OBJPROP_TIME, 0, t1); ObjectSetDouble(ChartID(), ray_name, OBJPROP_PRICE, 0, p1); ObjectSetInteger(ChartID(), ray_name, OBJPROP_TIME, 1, current_time + PeriodSeconds()); ObjectSetDouble(ChartID(), ray_name, OBJPROP_PRICE, 1, p1); }
   // Nhãn luôn xoá-và-tạo-lại (thay vì ObjectSetInteger cập nhật tại chỗ) để đảm bảo vị trí/nội dung luôn khớp lần tính mới nhất,
   // tránh trường hợp nhãn "kẹt" ở toạ độ cũ khi text đổi độ dài (do gộp nhãn) hoặc khi cập nhật object OBJ_TEXT không refresh vị trí trên một số bản MT5.
   string lbl_name = name + "_lbl"; datetime label_time = GetRightEdgeTime(current_time);
   ObjectDelete(ChartID(), lbl_name);
   ObjectCreate(ChartID(), lbl_name, OBJ_TEXT, 0, label_time, p1);
   ObjectSetInteger(ChartID(), lbl_name, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), lbl_name, OBJPROP_FONTSIZE, 8); ObjectSetInteger(ChartID(), lbl_name, OBJPROP_BACK, false); ObjectSetInteger(ChartID(), lbl_name, OBJPROP_SELECTABLE, false);
   ObjectSetString(ChartID(), lbl_name, OBJPROP_TEXT, text + "  "); ObjectSetInteger(ChartID(), lbl_name, OBJPROP_ANCHOR, isDown ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
}

void DrawLevelGroup(TLevelSrc &src[], datetime current_time, bool isDown) {
   int n = ArraySize(src);
   bool used[]; ArrayResize(used, n); ArrayInitialize(used, false);
   for(int a = 0; a < n; a++) {
      bool valid_a = src[a].enabled && src[a].price != EMPTY_VALUE;
      if(!valid_a || used[a]) {
         if(!valid_a) { ObjectDelete(ChartID(), src[a].objName + "_ray"); ObjectDelete(ChartID(), src[a].objName + "_lbl"); }
         continue;
      }
      string txt = src[a].text;
      for(int b = a + 1; b < n; b++) {
         bool valid_b = src[b].enabled && src[b].price != EMPTY_VALUE;
         if(!valid_b || used[b]) continue;
         if(MathAbs(src[b].price - src[a].price) < _Point) {
            txt += " | " + src[b].text; used[b] = true;
            ObjectDelete(ChartID(), src[b].objName + "_ray"); ObjectDelete(ChartID(), src[b].objName + "_lbl");
         }
      }
      CreateTrackingRayWithLabel(src[a].objName, src[a].time, src[a].price, src[a].clr, txt, isDown, current_time);
   }
}

// Gom 3 nhóm mốc Đỉnh/Đáy Major (Active/Protected, Weak/Extreme, Last Major) theo từng phía High/Low.
// Nếu 2+ mốc trùng giá (cùng 1 điểm Swing) thì gộp chung 1 đường + 1 nhãn "TextA | TextB" thay vì vẽ chồng nhiều object.
void UpdateLevelLabels(datetime current_time) {
   TLevelSrc highSrc[3];
   highSrc[0].price = g_high_lvl; highSrc[0].time = g_high_time; highSrc[0].text = g_high_text; highSrc[0].clr = TrackingLineColor; highSrc[0].objName = "IND_SMC_TRACK_HIGH"; highSrc[0].enabled = ShowTrackingLines;
   highSrc[1].price = (major_trend == 1) ? maj_confirmed_extreme_high : EMPTY_VALUE; highSrc[1].time = maj_confirmed_extreme_high_time; highSrc[1].text = "Weak High"; highSrc[1].clr = clrOrange; highSrc[1].objName = "IND_SMC_EXTREME_HIGH"; highSrc[1].enabled = ShowWeakHighLow;
   highSrc[2].price = last_maj_high; highSrc[2].time = last_maj_high_time; highSrc[2].text = "Last Major High"; highSrc[2].clr = LastMajorLineColor; highSrc[2].objName = "IND_SMC_LASTMAJOR_HIGH"; highSrc[2].enabled = ShowLastMajorHighLow;
   DrawLevelGroup(highSrc, current_time, true);

   TLevelSrc lowSrc[3];
   lowSrc[0].price = g_low_lvl; lowSrc[0].time = g_low_time; lowSrc[0].text = g_low_text; lowSrc[0].clr = TrackingLineColor; lowSrc[0].objName = "IND_SMC_TRACK_LOW"; lowSrc[0].enabled = ShowTrackingLines;
   lowSrc[1].price = (major_trend == -1) ? maj_confirmed_extreme_low : EMPTY_VALUE; lowSrc[1].time = maj_confirmed_extreme_low_time; lowSrc[1].text = "Weak Low"; lowSrc[1].clr = clrOrange; lowSrc[1].objName = "IND_SMC_EXTREME_LOW"; lowSrc[1].enabled = ShowWeakHighLow;
   lowSrc[2].price = last_maj_low; lowSrc[2].time = last_maj_low_time; lowSrc[2].text = "Last Major Low"; lowSrc[2].clr = LastMajorLineColor; lowSrc[2].objName = "IND_SMC_LASTMAJOR_LOW"; lowSrc[2].enabled = ShowLastMajorHighLow;
   DrawLevelGroup(lowSrc, current_time, false);
}

void ClearQueue(string &queue[]) { for(int i=0; i<ArraySize(queue); i++) { ObjectDelete(ChartID(), queue[i]); ObjectDelete(ChartID(), queue[i] + "_lbl"); } ArrayResize(queue, 0); }
void ClearZoneQueue(TZone &queue[]) { for(int i=0; i<ArraySize(queue); i++) { ObjectDelete(ChartID(), queue[i].name); } ArrayResize(queue, 0); }
void PushBOS(string &queue[], string name, int max_count) { for(int i=0; i<ArraySize(queue); i++) if(queue[i] == name) return; int size = ArraySize(queue); ArrayResize(queue, size + 1); queue[size] = name; if(ArraySize(queue) > max_count) { ObjectDelete(ChartID(), queue[0]); ObjectDelete(ChartID(), queue[0] + "_lbl"); for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1]; ArrayResize(queue, ArraySize(queue) - 1); } }
void PushZone(TZone &queue[], string name, double entry, double stop, int max_count) { for(int i=0; i<ArraySize(queue); i++) { if(queue[i].name == name) { queue[i].entryPrice = entry; queue[i].stopPrice = stop; return; } } int size = ArraySize(queue); ArrayResize(queue, size + 1); queue[size].name = name; queue[size].entryPrice = entry; queue[size].stopPrice = stop; if(ArraySize(queue) > max_count) { ObjectDelete(ChartID(), queue[0].name); for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1]; ArrayResize(queue, ArraySize(queue) - 1); } }
void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize) { ObjectCreate(ChartID(), name, OBJ_TREND, 0, t1, p1, t2, p1); ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), name, OBJPROP_STYLE, style); ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, width); ObjectSetInteger(ChartID(), name, OBJPROP_RAY_RIGHT, false); ObjectSetInteger(ChartID(), name, OBJPROP_BACK, false); datetime t_mid = t1 + (t2 - t1) / 2; string lbl = name + "_lbl"; ObjectCreate(ChartID(), lbl, OBJ_TEXT, 0, t_mid, p1); ObjectSetString(ChartID(), lbl, OBJPROP_TEXT, text); ObjectSetInteger(ChartID(), lbl, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), lbl, OBJPROP_ANCHOR, anchor); ObjectSetInteger(ChartID(), lbl, OBJPROP_FONTSIZE, fontSize); ObjectSetInteger(ChartID(), lbl, OBJPROP_BACK, false); }
void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown) { ObjectCreate(ChartID(), name, OBJ_TREND, 0, t1, p1, t1 + PeriodSeconds()*100, p1); ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), name, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 2); ObjectSetInteger(ChartID(), name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(ChartID(), name, OBJPROP_BACK, false); string lbl = name + "_lbl"; ObjectCreate(ChartID(), lbl, OBJ_TEXT, 0, t1, p1); ObjectSetString(ChartID(), lbl, OBJPROP_TEXT, " " + text); ObjectSetInteger(ChartID(), lbl, OBJPROP_COLOR, clr); ObjectSetInteger(ChartID(), lbl, OBJPROP_ANCHOR, isDown ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER); ObjectSetInteger(ChartID(), lbl, OBJPROP_FONTSIZE, 8); ObjectSetInteger(ChartID(), lbl, OBJPROP_BACK, false); }

void CreateZone(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level, const datetime &time[], const double &h[], const double &l[], const double &ha_h[], const double &ha_l[], const double &ha_color[], int total, double &out_entry, double &out_stop, bool draw_graphic) {
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
   
   // Nếu draw_graphic = false (mZone của Minor luôn false, hoặc ShowSDZones = false phía Major), hàm chỉ tính toán lấy giá trị Entry/SL rồi ngắt tại đây.
   if (!draw_graphic) return;
   
   if(ObjectFind(ChartID(), name) >= 0) {
       double old_zHigh = ObjectGetDouble(ChartID(), name, OBJPROP_PRICE, 0); double old_zLow = ObjectGetDouble(ChartID(), name, OBJPROP_PRICE, 1);
       if (MathAbs(old_zHigh - zHigh) < _Point && MathAbs(old_zLow - zLow) < _Point) return; 
       ObjectDelete(ChartID(), name);
   }
   datetime tStart = time[ext_idx]; datetime tEnd = time[0] + PeriodSeconds() * 1000; 
   ObjectCreate(ChartID(), name, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
   ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, isSellZone ? SellZoneColor : BuyZoneColor); ObjectSetInteger(ChartID(), name, OBJPROP_FILL, true); ObjectSetInteger(ChartID(), name, OBJPROP_BACK, true); 
}
//+------------------------------------------------------------------+