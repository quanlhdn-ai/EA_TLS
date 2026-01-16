#property indicator_chart_window
#property indicator_buffers 5       // Tăng lên 5 buffer
#property indicator_plots   5       // Tăng lên 3 hình vẽ (2 đường MA + 1 Chấm)

//--- Plot 1: Short MA
#property indicator_label1  "Short MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- Plot 2: Long MA
#property indicator_label2  "Long MA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- Plot 3: Cross Dot (Chấm tròn giao cắt) - MỚI
#property indicator_label3  "Cross Dot"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrBlue
#property indicator_width3  5

//--- Buffer ẩn (Không vẽ, chỉ chứa dữ liệu cho Bot)
#property indicator_label4  "High Line Data"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Low Line Data"
#property indicator_type5   DRAW_NONE

//--- Inputs
input int      InpShortPeriod = 10;       // Short Period
input int      InpLongPeriod  = 39;       // Long Period
input ENUM_MA_METHOD InpMethod = MODE_EMA; // MA Method

//--- Buffers
double         ShortMABuffer[];
double         LongMABuffer[];
double         CrossDotBuffer[]; // Buffer chứa chấm tròn
double         HighLineData[]; 
double         LowLineData[];  

//--- Global variables
int            handleShort;
int            handleLong;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // 1. Mapping buffers
   SetIndexBuffer(0, ShortMABuffer, INDICATOR_DATA);
   SetIndexBuffer(1, LongMABuffer, INDICATOR_DATA);
   SetIndexBuffer(2, CrossDotBuffer, INDICATOR_DATA); // Buffer chấm tròn
   SetIndexBuffer(3, HighLineData, INDICATOR_DATA);
   SetIndexBuffer(4, LowLineData, INDICATOR_DATA);

   // 2. Cài đặt hình dáng cho chấm tròn
   PlotIndexSetInteger(2, PLOT_ARROW, 159); // 159 là mã Wingdings của chấm tròn đặc
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0); // Giá trị rỗng không vẽ

   // 3. Khởi tạo Handle MA
   handleShort = iMA(_Symbol, _Period, InpShortPeriod, 0, InpMethod, PRICE_CLOSE);
   handleLong  = iMA(_Symbol, _Period, InpLongPeriod, 0, InpMethod, PRICE_CLOSE);

   if(handleShort == INVALID_HANDLE || handleLong == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Hàm vẽ đường kẻ (Object)                                         |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime timeStart, double price, color clr)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TREND, 0, timeStart, price, TimeCurrent(), price);
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); 
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Iteration function                                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpLongPeriod) return(0);

   int start = prev_calculated;
   if(start < InpLongPeriod) start = InpLongPeriod;
   if(start > 0) start--; 

   int copiedShort = CopyBuffer(handleShort, 0, 0, rates_total, ShortMABuffer);
   int copiedLong  = CopyBuffer(handleLong, 0, 0, rates_total, LongMABuffer);
   if(copiedShort <= 0 || copiedLong <= 0) return(0);

   // --- BIẾN TĨNH ---
   static double currentHighVal = 0.0;
   static double currentLowVal  = 0.0;
   static int    lastCrossUpIdx = 0;
   static int    lastCrossDownIdx = 0;

   // Reset khi load lại
   if(prev_calculated == 0) 
   {
      currentHighVal = 0.0;
      currentLowVal = 0.0;
      lastCrossUpIdx = 0;
      lastCrossDownIdx = 0;
      ObjectsDeleteAll(0, "TLS_HighLine");
      ObjectsDeleteAll(0, "TLS_LowLine");
   }

   for(int i = start; i < rates_total; i++)
     {
      bool crossUp   = (ShortMABuffer[i] > LongMABuffer[i]) && (ShortMABuffer[i-1] <= LongMABuffer[i-1]);
      bool crossDown = (ShortMABuffer[i] < LongMABuffer[i]) && (ShortMABuffer[i-1] >= LongMABuffer[i-1]);

      // --- LOGIC VẼ CHẤM TRÒN ---
      if(crossUp || crossDown)
        {
         // Vẽ chấm tròn ngay tại giá trị của Short MA
         CrossDotBuffer[i] = ShortMABuffer[i];
        }
      else
        {
         CrossDotBuffer[i] = 0.0; // Không vẽ
        }

      // --- LOGIC HIGH LINE ---
      if(crossDown)
        {
         lastCrossDownIdx = i;
         if(lastCrossUpIdx > 0)
           {
            double maxVal = -1.0;
            int maxIdx = -1;
            
            for(int k = i; k >= lastCrossUpIdx; k--)
              {
               if(ShortMABuffer[k] > maxVal)
                 {
                  maxVal = ShortMABuffer[k];
                  maxIdx = k;
                 }
              }
            currentHighVal = maxVal;
            DrawLevelLine("TLS_HighLine", time[maxIdx], currentHighVal, clrRed);
           }
        }

      // --- LOGIC LOW LINE ---
      if(crossUp)
        {
         lastCrossUpIdx = i;
         if(lastCrossDownIdx > 0)
           {
            double minVal = 9999999.0;
            int minIdx = -1;

            for(int k = i; k >= lastCrossDownIdx; k--)
              {
               if(ShortMABuffer[k] < minVal)
                 {
                  minVal = ShortMABuffer[k];
                  minIdx = k;
                 }
              }
            currentLowVal = minVal;
            DrawLevelLine("TLS_LowLine", time[minIdx], currentLowVal, clrGreen);
           }
        }

      // Dữ liệu Buffer cho Bot
      HighLineData[i] = (currentHighVal > 0) ? currentHighVal : EMPTY_VALUE;
      LowLineData[i]  = (currentLowVal > 0)  ? currentLowVal  : EMPTY_VALUE;
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "TLS_HighLine");
   ObjectsDeleteAll(0, "TLS_LowLine");
   IndicatorRelease(handleShort);
   IndicatorRelease(handleLong);
  }
//+------------------------------------------------------------------+