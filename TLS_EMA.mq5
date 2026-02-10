#property strict
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
input int            EMAShortPeriod = 10;
input int            EMALongPeriod  = 39;
input ENUM_MA_METHOD EMAMethod      = MODE_EMA;

//--- Buffers
double ShortMABuffer[];
double LongMABuffer[];
double CrossDotBuffer[];
double HighLineData[];
double LowLineData[];

//--- Handles
int handleShort = INVALID_HANDLE;
int handleLong  = INVALID_HANDLE;

//--- Persistent state
static double   currentHighVal     = 0.0;
static double   currentLowVal      = 0.0;
static int      lastCrossUpIdx     = -1;   // shift index of last crossUp (closed bar)
static int      lastCrossDownIdx   = -1;   // shift index of last crossDown (closed bar)
static datetime lastBarTime0       = 0;

//--- Parameter tracking for reset detection
static int savedShortPeriod = 0;
static int savedLongPeriod = 0;

//+------------------------------------------------------------------+
//| Draw/update level line                                           |
//+------------------------------------------------------------------+
void DrawOrUpdateLevelLine(const string name, const datetime timeStart, const double price, const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, timeStart, price, TimeCurrent(), price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      return;
   }

   datetime t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   double   p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);

   if(t0 != timeStart || p0 != price)
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, timeStart);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent());
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, ShortMABuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, LongMABuffer,   INDICATOR_DATA);
   SetIndexBuffer(2, CrossDotBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, HighLineData,   INDICATOR_DATA);
   SetIndexBuffer(4, LowLineData,    INDICATOR_DATA);

   ArraySetAsSeries(ShortMABuffer,  true);
   ArraySetAsSeries(LongMABuffer,   true);
   ArraySetAsSeries(CrossDotBuffer, true);
   ArraySetAsSeries(HighLineData,   true);
   ArraySetAsSeries(LowLineData,    true);

   PlotIndexSetInteger(2, PLOT_ARROW, 159);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   handleShort = iMA(_Symbol, _Period, EMAShortPeriod, 0, EMAMethod, PRICE_CLOSE);
   handleLong  = iMA(_Symbol, _Period, EMALongPeriod,  0, EMAMethod, PRICE_CLOSE);

   if(handleShort == INVALID_HANDLE || handleLong == INVALID_HANDLE)
      return(INIT_FAILED);
   
   // Initialize parameter tracking
   savedShortPeriod = EMAShortPeriod;
   savedLongPeriod = EMALongPeriod;

   return(INIT_SUCCEEDED);
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
   if(rates_total < EMALongPeriod + 2)
      return 0;

   // Check if parameters changed - force reset
   bool parametersChanged = (savedShortPeriod != EMAShortPeriod || savedLongPeriod != EMALongPeriod);
   
   // Reset on load or parameter change
   if(prev_calculated == 0 || parametersChanged)
   {
      currentHighVal   = 0.0;
      currentLowVal    = 0.0;
      lastCrossUpIdx   = -1;
      lastCrossDownIdx = -1;
      lastBarTime0     = 0;

      ObjectDelete(0, "TLS_HighLine");
      ObjectDelete(0, "TLS_LowLine");
      
      savedShortPeriod = EMAShortPeriod;
      savedLongPeriod = EMALongPeriod;

      // clear buffers once
      for(int j=rates_total-1; j>=0; --j)
      {
         CrossDotBuffer[j] = EMPTY_VALUE;
         HighLineData[j]   = EMPTY_VALUE;
         LowLineData[j]    = EMPTY_VALUE;
      }
   }

   int newBars = 1;
   if(prev_calculated > 0 && !parametersChanged)
   {
      newBars = rates_total - prev_calculated;
      if(newBars < 1) newBars = 1;
      if(newBars > rates_total - 2) newBars = rates_total - 2;
   }
   else
   {
      newBars = rates_total - 2;
      if(newBars < 1) newBars = 1;
   }

   bool isNewBar = (lastBarTime0 != 0 && time[0] != lastBarTime0);
   if(isNewBar && prev_calculated > 0 && !parametersChanged)
   {
      if(lastCrossUpIdx   >= 0) lastCrossUpIdx++;
      if(lastCrossDownIdx >= 0) lastCrossDownIdx++;
   }
   lastBarTime0 = time[0];
   
   if(lastCrossUpIdx >= rates_total) lastCrossUpIdx = rates_total - 1;
   if(lastCrossDownIdx >= rates_total) lastCrossDownIdx = rates_total - 1;

   int far  = MathMax(lastCrossUpIdx, lastCrossDownIdx);
   int need = MathMax(EMALongPeriod * 2 + 10, newBars + 5);
   if(far >= 0) need = MathMax(need, far + 5);
   if(need > rates_total) need = rates_total;

   int copiedShort = CopyBuffer(handleShort, 0, 0, need, ShortMABuffer);
   int copiedLong  = CopyBuffer(handleLong,  0, 0, need, LongMABuffer);
   if(copiedShort <= 0 || copiedLong <= 0)
      return 0;

   if(prev_calculated == 0 || parametersChanged)
   {
      copiedShort = CopyBuffer(handleShort, 0, 0, rates_total, ShortMABuffer);
      copiedLong  = CopyBuffer(handleLong,  0, 0, rates_total, LongMABuffer);
      if(copiedShort <= 0 || copiedLong <= 0) return 0;

      for(int i=rates_total-2; i>=1; --i)
      {
         bool crossUp   = (ShortMABuffer[i] > LongMABuffer[i]) &&
                          (ShortMABuffer[i+1] <= LongMABuffer[i+1]);

         bool crossDown = (ShortMABuffer[i] < LongMABuffer[i]) &&
                          (ShortMABuffer[i+1] >= LongMABuffer[i+1]);

         if(crossUp || crossDown)
            CrossDotBuffer[i] = ShortMABuffer[i];

         if(crossDown)
         {
            lastCrossDownIdx = i;
            if(lastCrossUpIdx >= 0 && lastCrossUpIdx >= i)
            {
               double maxVal = -DBL_MAX;
               int    maxIdx = -1;
               for(int k=lastCrossUpIdx; k>=i; --k)
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
                  DrawOrUpdateLevelLine("TLS_HighLine", time[maxIdx], currentHighVal, clrRed);
               }
            }
         }

         if(crossUp)
         {
            lastCrossUpIdx = i;
            if(lastCrossDownIdx >= 0 && lastCrossDownIdx >= i)
            {
               double minVal = DBL_MAX;
               int    minIdx = -1;
               for(int k=lastCrossDownIdx; k>=i; --k)
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
                  DrawOrUpdateLevelLine("TLS_LowLine", time[minIdx], currentLowVal, clrGreen);
               }
            }
         }

         HighLineData[i] = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
         LowLineData[i]  = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;
      }

      CrossDotBuffer[0] = EMPTY_VALUE;
      HighLineData[0]   = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
      LowLineData[0]    = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;
      HighLineData[1]   = HighLineData[0];
      LowLineData[1]    = LowLineData[0];

      return rates_total;
   }

   int from = MathMin(newBars, rates_total - 2);
   for(int i=from; i>=1; --i)
   {
      bool crossUp   = (ShortMABuffer[i] > LongMABuffer[i]) &&
                       (ShortMABuffer[i+1] <= LongMABuffer[i+1]);

      bool crossDown = (ShortMABuffer[i] < LongMABuffer[i]) &&
                       (ShortMABuffer[i+1] >= LongMABuffer[i+1]);

      // Only set dot on this bar if a new cross happens; otherwise leave whatever history already has
      if(crossUp || crossDown)
         CrossDotBuffer[i] = ShortMABuffer[i];

      if(crossDown)
      {
         lastCrossDownIdx = i;

         if(lastCrossUpIdx >= 0 && lastCrossUpIdx >= i)
         {
            int need2 = MathMax(need, lastCrossUpIdx + 5);
            if(need2 > rates_total) need2 = rates_total;
            if(need2 != need)
            {
               CopyBuffer(handleShort, 0, 0, need2, ShortMABuffer);
               CopyBuffer(handleLong,  0, 0, need2, LongMABuffer);
               need = need2;
            }

            double maxVal = -DBL_MAX;
            int    maxIdx = -1;
            for(int k=lastCrossUpIdx; k>=i; --k)
            {
               if(k < rates_total && ShortMABuffer[k] > maxVal)
               {
                  maxVal = ShortMABuffer[k];
                  maxIdx = k;
               }
            }

            if(maxIdx >= 0)
            {
               currentHighVal = maxVal;
               DrawOrUpdateLevelLine("TLS_HighLine", time[maxIdx], currentHighVal, clrRed);
            }
         }
      }

      if(crossUp)
      {
         lastCrossUpIdx = i;

         if(lastCrossDownIdx >= 0 && lastCrossDownIdx >= i)
         {
            int need2 = MathMax(need, lastCrossDownIdx + 5);
            if(need2 > rates_total) need2 = rates_total;
            if(need2 != need)
            {
               CopyBuffer(handleShort, 0, 0, need2, ShortMABuffer);
               CopyBuffer(handleLong,  0, 0, need2, LongMABuffer);
               need = need2;
            }

            double minVal = DBL_MAX;
            int    minIdx = -1;
            for(int k=lastCrossDownIdx; k>=i; --k)
            {
               if(k < rates_total && ShortMABuffer[k] < minVal)
               {
                  minVal = ShortMABuffer[k];
                  minIdx = k;
               }
            }

            if(minIdx >= 0)
            {
               currentLowVal = minVal;
               DrawOrUpdateLevelLine("TLS_LowLine", time[minIdx], currentLowVal, clrGreen);
            }
         }
      }
   }

   // EA uses shift1 (confirmed closed candle)
   CrossDotBuffer[0] = EMPTY_VALUE;

   HighLineData[0] = (currentHighVal != 0.0) ? currentHighVal : EMPTY_VALUE;
   LowLineData[0]  = (currentLowVal  != 0.0) ? currentLowVal  : EMPTY_VALUE;
   HighLineData[1] = HighLineData[0];
   LowLineData[1]  = LowLineData[0];

   if(currentHighVal != 0.0 && currentHighVal != EMPTY_VALUE && lastCrossUpIdx >= 0 && lastCrossUpIdx < rates_total)
   {
      int highIdx = lastCrossUpIdx;
      if(lastCrossDownIdx >= 0 && lastCrossDownIdx < lastCrossUpIdx)
      {
         double maxVal = -DBL_MAX;
         int maxIdx = -1;
         for(int k=lastCrossUpIdx; k>=lastCrossDownIdx && k>=0; --k)
         {
            if(k < rates_total && ShortMABuffer[k] > maxVal)
            {
               maxVal = ShortMABuffer[k];
               maxIdx = k;
            }
         }
         if(maxIdx >= 0) highIdx = maxIdx;
      }
      DrawOrUpdateLevelLine("TLS_HighLine", time[highIdx], currentHighVal, clrRed);
   }

   if(currentLowVal != 0.0 && currentLowVal != EMPTY_VALUE && lastCrossDownIdx >= 0 && lastCrossDownIdx < rates_total)
   {
      int lowIdx = lastCrossDownIdx;
      if(lastCrossUpIdx >= 0 && lastCrossUpIdx < lastCrossDownIdx)
      {
         double minVal = DBL_MAX;
         int minIdx = -1;
         for(int k=lastCrossDownIdx; k>=lastCrossUpIdx && k>=0; --k)
         {
            if(k < rates_total && ShortMABuffer[k] < minVal)
            {
               minVal = ShortMABuffer[k];
               minIdx = k;
            }
         }
         if(minIdx >= 0) lowIdx = minIdx;
      }
      DrawOrUpdateLevelLine("TLS_LowLine", time[lowIdx], currentLowVal, clrGreen);
   }

   return rates_total;
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