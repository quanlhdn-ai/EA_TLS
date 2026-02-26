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

int handleShort = INVALID_HANDLE;
int handleLong  = INVALID_HANDLE;

static double   currentHighVal    = 0.0;
static double   currentLowVal     = 0.0;
static int      lastCrossUpShift   = -1;
static int      lastCrossDownShift = -1;
static int      savedShortPeriod   = 0;
static int      savedLongPeriod    = 0;

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
      return INIT_FAILED;

   currentHighVal    = 0.0;
   currentLowVal     = 0.0;
   lastCrossUpShift   = -1;
   lastCrossDownShift = -1;
   savedShortPeriod  = EMAShortPeriod;
   savedLongPeriod   = EMALongPeriod;

   ObjectDelete(0, "TLS_HighLine");
   ObjectDelete(0, "TLS_LowLine");

   return INIT_SUCCEEDED;
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

   bool parametersChanged = (savedShortPeriod != EMAShortPeriod || savedLongPeriod != EMALongPeriod);
   if(parametersChanged)
   {
      currentHighVal    = 0.0;
      currentLowVal     = 0.0;
      lastCrossUpShift   = -1;
      lastCrossDownShift = -1;
      savedShortPeriod  = EMAShortPeriod;
      savedLongPeriod   = EMALongPeriod;
      ObjectDelete(0, "TLS_HighLine");
      ObjectDelete(0, "TLS_LowLine");
      ArrayInitialize(CrossDotBuffer, EMPTY_VALUE);
      ArrayInitialize(HighLineData, EMPTY_VALUE);
      ArrayInitialize(LowLineData, EMPTY_VALUE);
   }

   double tempShort[], tempLong[];
   ArraySetAsSeries(tempShort, true);
   ArraySetAsSeries(tempLong,  true);

   int copiedShort = CopyBuffer(handleShort, 0, 0, rates_total, tempShort);
   int copiedLong  = CopyBuffer(handleLong,  0, 0, rates_total, tempLong);

   if(copiedShort <= 0 || copiedLong <= 0)
      return 0;

   int validBars = MathMin(copiedShort, copiedLong);

   for(int i = 0; i < validBars; i++)
   {
      ShortMABuffer[i] = tempShort[i];
      LongMABuffer[i]  = tempLong[i];
   }

   bool fullRecalc = (prev_calculated == 0 || parametersChanged);
   int  loopFrom   = fullRecalc
                     ? MathMin(validBars - 2, rates_total - 2)
                     : MathMax(1, MathMin(rates_total - prev_calculated + 1, validBars - 2));

   if(fullRecalc)
   {
      currentHighVal     = 0.0;
      currentLowVal      = 0.0;
      lastCrossUpShift   = -1;
      lastCrossDownShift = -1;
      ArrayInitialize(CrossDotBuffer, EMPTY_VALUE);
      ArrayInitialize(HighLineData,   EMPTY_VALUE);
      ArrayInitialize(LowLineData,    EMPTY_VALUE);
   }

   // ===== MAIN LOOP =====
   for(int i = loopFrom; i >= 1; i--)
   {
      if(tempShort[i]   == EMPTY_VALUE || tempShort[i+1] == EMPTY_VALUE) continue;
      if(tempLong[i]    == EMPTY_VALUE || tempLong[i+1]  == EMPTY_VALUE) continue;

      bool crossUp   = (tempShort[i] >  tempLong[i]) && (tempShort[i+1] <= tempLong[i+1]);
      bool crossDown = (tempShort[i] <  tempLong[i]) && (tempShort[i+1] >= tempLong[i+1]);

      if(crossUp || crossDown)
         CrossDotBuffer[i] = tempShort[i];

      if(crossDown)
      {
         if(lastCrossUpShift > i && lastCrossUpShift >= 0)
         {
            double maxVal = -DBL_MAX;
            int    maxIdx = -1;
            for(int k = lastCrossUpShift; k >= i; k--)
            {
               if(k < validBars && tempShort[k] != EMPTY_VALUE && tempShort[k] > maxVal)
               {
                  maxVal = tempShort[k];
                  maxIdx = k;
               }
            }
            if(maxIdx >= 0)
            {
               currentHighVal = maxVal;
               DrawOrUpdateLevelLine("TLS_HighLine", time[maxIdx], currentHighVal, clrRed);
            }
         }
         lastCrossDownShift = i;
      }

      if(crossUp)
      {
         if(lastCrossDownShift > i && lastCrossDownShift >= 0)
         {
            double minVal = DBL_MAX;
            int    minIdx = -1;
            for(int k = lastCrossDownShift; k >= i; k--)
            {
               if(k < validBars && tempShort[k] != EMPTY_VALUE && tempShort[k] < minVal)
               {
                  minVal = tempShort[k];
                  minIdx = k;
               }
            }
            if(minIdx >= 0)
            {
               currentLowVal = minVal;
               DrawOrUpdateLevelLine("TLS_LowLine", time[minIdx], currentLowVal, clrGreen);
            }
         }
         lastCrossUpShift = i;
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

void OnDeinit(const int reason)
{
   ObjectDelete(0, "TLS_HighLine");
   ObjectDelete(0, "TLS_LowLine");

   if(handleShort != INVALID_HANDLE) IndicatorRelease(handleShort);
   if(handleLong  != INVALID_HANDLE) IndicatorRelease(handleLong);
}