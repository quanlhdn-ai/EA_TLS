#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

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

//--- Plot 3: Cross Dot
#property indicator_label3  "Cross Dot"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrBlue
#property indicator_width3  5

//--- Hidden buffers
#property indicator_label4  "High Line Data"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Low Line Data"
#property indicator_type5   DRAW_NONE

//--- Inputs
input int            InpShortPeriod = 10;
input int            InpLongPeriod  = 39;
input ENUM_MA_METHOD InpMethod      = MODE_EMA;

//--- Buffers
double ShortMABuffer[];
double LongMABuffer[];
double CrossDotBuffer[];
double HighLineData[];
double LowLineData[];

//--- Global variables
int handleShort;
int handleLong;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, ShortMABuffer, INDICATOR_DATA);
   SetIndexBuffer(1, LongMABuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, CrossDotBuffer,INDICATOR_DATA);
   SetIndexBuffer(3, HighLineData,  INDICATOR_DATA);
   SetIndexBuffer(4, LowLineData,   INDICATOR_DATA);

   ArraySetAsSeries(ShortMABuffer, true);
   ArraySetAsSeries(LongMABuffer, true);
   ArraySetAsSeries(CrossDotBuffer, true);
   ArraySetAsSeries(HighLineData, true);
   ArraySetAsSeries(LowLineData, true);

   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);


   PlotIndexSetInteger(2, PLOT_ARROW, 159);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   handleShort = iMA(_Symbol, _Period, InpShortPeriod, 0, InpMethod, PRICE_CLOSE);
   handleLong  = iMA(_Symbol, _Period, InpLongPeriod,  0, InpMethod, PRICE_CLOSE);

   if(handleShort == INVALID_HANDLE || handleLong == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Draw level line                                                  |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime timeStart, double price, color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

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
   if(rates_total < InpLongPeriod + 2) return(0);

   int copiedShort = CopyBuffer(handleShort, 0, 0, rates_total, ShortMABuffer);
   int copiedLong  = CopyBuffer(handleLong,  0, 0, rates_total, LongMABuffer);
   if(copiedShort <= 0 || copiedLong <= 0) return(0);

   // --- STATIC STATE ---
   static double currentHighVal = 0.0;
   static double currentLowVal  = 0.0;
   static int    lastCrossUpIdx   = -1;
   static int    lastCrossDownIdx = -1;

   // Reset on load
   if(prev_calculated == 0)
   {
      currentHighVal   = 0.0;
      currentLowVal    = 0.0;
      lastCrossUpIdx   = -1;
      lastCrossDownIdx = -1;

      ObjectDelete(0, "TLS_HighLine");
      ObjectDelete(0, "TLS_LowLine");
   }


   int clr_from = rates_total - 1;
   int clr_to   = 0;
   for(int j = clr_from; j >= clr_to; j--)
      CrossDotBuffer[j] = EMPTY_VALUE;

   for(int i = rates_total - 2; i >= 1; i--)
   {
      bool crossUp   = (ShortMABuffer[i] > LongMABuffer[i]) &&
                       (ShortMABuffer[i+1] <= LongMABuffer[i+1]);

      bool crossDown = (ShortMABuffer[i] < LongMABuffer[i]) &&
                       (ShortMABuffer[i+1] >= LongMABuffer[i+1]);

      // --- DOT ---
      if(crossUp || crossDown)
         CrossDotBuffer[i] = ShortMABuffer[i];
      else
         CrossDotBuffer[i] = EMPTY_VALUE;

      // --- LOGIC HIGH LINE ---
      if(crossDown)
      {
         lastCrossDownIdx = i;
         if(lastCrossUpIdx >= 0 && lastCrossUpIdx >= i)
         {
            double maxVal = -DBL_MAX;
            int    maxIdx = -1;

            for(int k = lastCrossUpIdx; k >= i; k--)
            {
               if(ShortMABuffer[k] > maxVal)
               {
                  maxVal = ShortMABuffer[k];
                  maxIdx = k;
               }
            }

            if(maxIdx >= 0)
            {
               currentHighVal = maxVal;
               DrawLevelLine("TLS_HighLine", time[maxIdx], currentHighVal, clrRed);
            }
         }
      }

      // --- LOGIC LOW LINE ---
      if(crossUp)
      {
         lastCrossUpIdx = i;
         if(lastCrossDownIdx >= 0 && lastCrossDownIdx >= i)
         {
            double minVal = DBL_MAX;
            int    minIdx = -1;

            for(int k = lastCrossDownIdx; k >= i; k--)
            {
               if(ShortMABuffer[k] < minVal)
               {
                  minVal = ShortMABuffer[k];
                  minIdx = k;
               }
            }

            if(minIdx >= 0)
            {
               currentLowVal = minVal;
               DrawLevelLine("TLS_LowLine", time[minIdx], currentLowVal, clrGreen);
            }
         }
      }

      // --- Data buffers for bot ---
      HighLineData[i] = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
      LowLineData[i]  = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;
   }

   CrossDotBuffer[0] = EMPTY_VALUE;
   HighLineData[0]   = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
   LowLineData[0]    = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;
   HighLineData[1] = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
   LowLineData[1]  = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;


   return(rates_total);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, "TLS_HighLine");
   ObjectDelete(0, "TLS_LowLine");

   if(handleShort != INVALID_HANDLE) IndicatorRelease(handleShort);
   if(handleLong  != INVALID_HANDLE) IndicatorRelease(handleLong);
}