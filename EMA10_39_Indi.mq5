//+------------------------------------------------------------------+
//| TZTLS_EMA_Pivot_HighLowLine_Mode3_FIXLINE.mq5                     |
//| MODE #3: log history once on attach, then only log new pivots     |
//| FIX: rebuild & draw latest HighLine/LowLine immediately on attach |
//| EMA only | Current TF | HL2 (PRICE_MEDIAN)                        |
//| Updates:                                                         |
//| - CROSS_UP/DOWN -> PIVOT BUY/SELL                                 |
//| - Last Pivot always shows last pivot (keeps value until new pivot)|
//+------------------------------------------------------------------+
#property strict
#property version "1.32"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "EMA 10 (HL2)"
#property indicator_type1   DRAW_LINE
#property indicator_width1  2

#property indicator_label2  "EMA 39 (HL2)"
#property indicator_type2   DRAW_LINE
#property indicator_width2  2

input int  ShortPeriod = 10;
input int  LongPeriod  = 39;

input bool DrawPivotDot = true;
input color PivotColor  = clrPurple;
input int   PivotDotCode = 159; // dot
input int   PivotDotSize = 3;

input bool DrawHighLowLines = true;
input color HighLineColor = clrRed;
input color LowLineColor  = clrLime;
input int   LineWidth = 1;

input int  HistoryBarsToScan = 100;     // window size
input bool PrintHistoryOnce  = true;    // log list once on attach
input bool PrintNewPivotOnly = true;    // realtime only
input bool ShowChartSummary  = true;    // Comment() summary

double emaShort[];
double emaLong[];

int hEmaShort = INVALID_HANDLE;
int hEmaLong  = INVALID_HANDLE;

string OBJ_PREFIX;
string OBJ_HIGHLINE;
string OBJ_LOWLINE;

static bool history_logged = false;
datetime lastClosedBarTime = 0;

// last cross times (for realtime building)
datetime lastCrossUpTime   = 0;
datetime lastCrossDownTime = 0;

// nearest swing values
double highLineValue = 0.0;
double lowLineValue  = 0.0;

// --- FIX: last pivot info persists ---
string   gLastPivotText  = "N/A";
double   gLastPivotPrice = 0.0;   // EMA10 at pivot bar
datetime gLastPivotTime  = 0;

//---------------- Helpers ----------------
bool CrossOver(double prevA, double prevB, double currA, double currB){ return (prevA <= prevB && currA > currB); }
bool CrossUnder(double prevA, double prevB, double currA, double currB){ return (prevA >= prevB && currA < currB); }

bool IsNewClosedBar(const datetime &time[])
{
   if(time[1] != 0 && time[1] != lastClosedBarTime)
   {
      lastClosedBarTime = time[1];
      return true;
   }
   return false;
}

void DeleteByPrefix(const string prefix)
{
   for(int i=ObjectsTotal(0)-1; i>=0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawPivot(datetime t, double price)
{
   if(!DrawPivotDot) return;

   string name = OBJ_PREFIX + "_PIVOT_" + IntegerToString((int)t);
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, PivotDotCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, PivotColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, PivotDotSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawOrReplaceRayLine(const string objName, datetime t1, double y, color c)
{
   if(!DrawHighLowLines) return;

   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   datetime t2 = TimeCurrent();
   ObjectCreate(0, objName, OBJ_TREND, 0, t1, y, t2, y);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, c);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

void UpdateChartSummary()
{
   if(!ShowChartSummary) return;

   string pivotInfo = gLastPivotText;
   if(gLastPivotTime != 0)
   {
      pivotInfo += " | " + TimeToString(gLastPivotTime, TIME_DATE|TIME_MINUTES)
                +  " | " + DoubleToString(gLastPivotPrice, 3);
   }

   Comment(
      "SwingHigh (HighLine): ", DoubleToString(highLineValue, 3), "\n",
      "SwingLow  (LowLine) : ", DoubleToString(lowLineValue, 3),  "\n",
      "Last Pivot          : ", pivotInfo
   );
}

//---------------- Build latest lines from history window ----------------
// Process chronologically within last N bars to produce the latest HighLine/LowLine
void RebuildLinesFromHistory(const datetime &time[])
{
   int N = MathMax(20, HistoryBarsToScan);
   int maxShift = MathMin(N + 2, ArraySize(emaShort) - 3); // need i+1
   if(maxShift < 3) return;

   // We'll walk from oldest -> newest in the window: shift=maxShift down to 2
   int lastUpShift = -1;
   int lastDownShift = -1;

   highLineValue = 0.0;
   lowLineValue  = 0.0;

   for(int i = maxShift; i >= 2; i--)
   {
      double prevS = emaShort[i+1], prevL = emaLong[i+1];
      double currS = emaShort[i],   currL = emaLong[i];
      if(prevS==EMPTY_VALUE || prevL==EMPTY_VALUE || currS==EMPTY_VALUE || currL==EMPTY_VALUE) continue;

      bool up   = CrossOver(prevS, prevL, currS, currL);
      bool down = CrossUnder(prevS, prevL, currS, currL);

      if(up)
      {
         // PIVOT BUY => LowLine = min(EMA10) from lastDown -> now
         if(lastDownShift > 0)
         {
            double minVal = emaShort[i];
            int minShift  = i;
            for(int k=i; k<=lastDownShift && k<ArraySize(emaShort); k++)
            {
               if(emaShort[k] != EMPTY_VALUE && emaShort[k] < minVal)
               {
                  minVal = emaShort[k];
                  minShift = k;
               }
            }
            lowLineValue = minVal;
            DrawOrReplaceRayLine(OBJ_LOWLINE, time[minShift], minVal, LowLineColor);
         }

         lastUpShift = i;
         lastCrossUpTime = time[i];      // keep for realtime
         DrawPivot(time[i], currS);

         // keep last pivot (if this is the newest pivot encountered so far in chronological walk, it will end up last)
         gLastPivotText  = "PIVOT BUY";
         gLastPivotTime  = time[i];
         gLastPivotPrice = currS;
      }

      if(down)
      {
         // PIVOT SELL => HighLine = max(EMA10) from lastUp -> now
         if(lastUpShift > 0)
         {
            double maxVal = emaShort[i];
            int maxShift2 = i;
            for(int k=i; k<=lastUpShift && k<ArraySize(emaShort); k++)
            {
               if(emaShort[k] != EMPTY_VALUE && emaShort[k] > maxVal)
               {
                  maxVal = emaShort[k];
                  maxShift2 = k;
               }
            }
            highLineValue = maxVal;
            DrawOrReplaceRayLine(OBJ_HIGHLINE, time[maxShift2], maxVal, HighLineColor);
         }

         lastDownShift = i;
         lastCrossDownTime = time[i];    // keep for realtime
         DrawPivot(time[i], currS);

         gLastPivotText  = "PIVOT SELL";
         gLastPivotTime  = time[i];
         gLastPivotPrice = currS;
      }
   }
}

//---------------- History log once ----------------
void LogHistoryOnce(const datetime &time[])
{
   if(!PrintHistoryOnce) return;

   int N = MathMax(20, HistoryBarsToScan);
   int maxShift = MathMin(N + 2, ArraySize(emaShort) - 3);

   string pivotsText = "";
   int pivotCount = 0;

   for(int i=2; i<=maxShift; i++)
   {
      double prevS = emaShort[i+1], prevL = emaLong[i+1];
      double currS = emaShort[i],   currL = emaLong[i];
      if(prevS==EMPTY_VALUE || prevL==EMPTY_VALUE || currS==EMPTY_VALUE || currL==EMPTY_VALUE) continue;

      bool up   = CrossOver(prevS, prevL, currS, currL);
      bool down = CrossUnder(prevS, prevL, currS, currL);

      if(up || down)
      {
         pivotCount++;
         pivotsText += StringFormat("#%d %s %s  EMA10=%.3f EMA39=%.3f\n",
                                    pivotCount,
                                    (up ? "PIVOT BUY " : "PIVOT SELL"),
                                    TimeToString(time[i], TIME_DATE|TIME_MINUTES),
                                    currS, currL);
      }
   }

   Print("---------- HISTORY PIVOTS (last ", N, " bars) ", _Symbol, " ", EnumToString(_Period), " ----------");
   if(pivotsText == "") Print("(no pivots found)");
   else Print("\n", pivotsText);
   Print("--------------------------------------------------------------------------");
   PrintFormat("Nearest SwingHigh(HighLine)=%.3f | SwingLow(LowLine)=%.3f", highLineValue, lowLineValue);
}

//---------------- Init/Deinit ----------------
int OnInit()
{
   SetIndexBuffer(0, emaShort, INDICATOR_DATA);
   SetIndexBuffer(1, emaLong,  INDICATOR_DATA);
   ArraySetAsSeries(emaShort, true);
   ArraySetAsSeries(emaLong,  true);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrGreen);

   hEmaShort = iMA(_Symbol, _Period, ShortPeriod, 0, MODE_EMA, PRICE_MEDIAN);
   hEmaLong  = iMA(_Symbol, _Period, LongPeriod,  0, MODE_EMA, PRICE_MEDIAN);
   if(hEmaShort == INVALID_HANDLE || hEmaLong == INVALID_HANDLE)
      return INIT_FAILED;

   OBJ_PREFIX   = "TZTLS_" + _Symbol + "_" + IntegerToString(_Period);
   OBJ_HIGHLINE = OBJ_PREFIX + "_HIGHLINE";
   OBJ_LOWLINE  = OBJ_PREFIX + "_LOWLINE";

   // Only delete OUR objects (by prefix), not the user's manual lines
   DeleteByPrefix(OBJ_PREFIX);

   history_logged = false;
   lastCrossUpTime = 0;
   lastCrossDownTime = 0;
   highLineValue = 0;
   lowLineValue = 0;

   gLastPivotText  = "N/A";
   gLastPivotTime  = 0;
   gLastPivotPrice = 0.0;

   Print("[INIT] Mode#3 FIXLINE v1.32: history logged once + draw HighLine/LowLine immediately + persistent Last Pivot.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteByPrefix(OBJ_PREFIX);
   Comment("");

   if(hEmaShort != INVALID_HANDLE) IndicatorRelease(hEmaShort);
   if(hEmaLong  != INVALID_HANDLE) IndicatorRelease(hEmaLong);
}

//---------------- Calculate ----------------
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
   if(rates_total < LongPeriod + 10) return 0;

   if(CopyBuffer(hEmaShort, 0, 0, rates_total, emaShort) < rates_total) return prev_calculated;
   if(CopyBuffer(hEmaLong,  0, 0, rates_total, emaLong)  < rates_total) return prev_calculated;

   // (1) On attach: rebuild + draw lines immediately, then log history ONCE
   if(prev_calculated == 0 && !history_logged)
   {
      RebuildLinesFromHistory(time);
      LogHistoryOnce(time);
      history_logged = true;

      if(gLastPivotTime == 0)
         gLastPivotText = "HISTORY loaded";

      UpdateChartSummary();
      ChartRedraw();
      return rates_total;
   }

   // (2) Realtime: only on new closed bar
   if(!IsNewClosedBar(time))
      return rates_total;

   double s2 = emaShort[2], l2 = emaLong[2];
   double s1 = emaShort[1], l1 = emaLong[1];

   bool pivotBuy  = CrossOver(s2, l2, s1, l1);   // formerly crossUp
   bool pivotSell = CrossUnder(s2, l2, s1, l1);  // formerly crossDown

   if(pivotBuy)
   {
      lastCrossUpTime = time[1];
      DrawPivot(time[1], s1);

      // LowLine = min EMA10 from lastCrossDown -> now
      if(lastCrossDownTime != 0)
      {
         int endShift = iBarShift(_Symbol, _Period, lastCrossDownTime, true);
         int startShift = 1;
         if(endShift >= startShift)
         {
            double minVal = emaShort[startShift];
            int minShift  = startShift;
            for(int i=startShift; i<=endShift && i<ArraySize(emaShort); i++)
            {
               if(emaShort[i] != EMPTY_VALUE && emaShort[i] < minVal)
               { minVal = emaShort[i]; minShift = i; }
            }
            lowLineValue = minVal;
            DrawOrReplaceRayLine(OBJ_LOWLINE, time[minShift], minVal, LowLineColor);
         }
      }

      // --- persist last pivot ---
      gLastPivotText  = "PIVOT BUY";
      gLastPivotTime  = time[1];
      gLastPivotPrice = s1;

      if(PrintNewPivotOnly)
         PrintFormat("[PIVOT NEW] PIVOT BUY  %s EMA10=%.3f EMA39=%.3f | LowLine=%.3f HighLine=%.3f",
                     TimeToString(time[1], TIME_DATE|TIME_MINUTES), s1, l1, lowLineValue, highLineValue);
   }

   if(pivotSell)
   {
      lastCrossDownTime = time[1];
      DrawPivot(time[1], s1);

      // HighLine = max EMA10 from lastCrossUp -> now
      if(lastCrossUpTime != 0)
      {
         int endShift = iBarShift(_Symbol, _Period, lastCrossUpTime, true);
         int startShift = 1;
         if(endShift >= startShift)
         {
            double maxVal = emaShort[startShift];
            int maxShift  = startShift;
            for(int i=startShift; i<=endShift && i<ArraySize(emaShort); i++)
            {
               if(emaShort[i] != EMPTY_VALUE && emaShort[i] > maxVal)
               { maxVal = emaShort[i]; maxShift = i; }
            }
            highLineValue = maxVal;
            DrawOrReplaceRayLine(OBJ_HIGHLINE, time[maxShift], maxVal, HighLineColor);
         }
      }

      gLastPivotText  = "PIVOT SELL";
      gLastPivotTime  = time[1];
      gLastPivotPrice = s1;

      if(PrintNewPivotOnly)
         PrintFormat("[PIVOT NEW] PIVOT SELL %s EMA10=%.3f EMA39=%.3f | LowLine=%.3f HighLine=%.3f",
                     TimeToString(time[1], TIME_DATE|TIME_MINUTES), s1, l1, lowLineValue, highLineValue);
   }

   UpdateChartSummary();
   ChartRedraw();
   return rates_total;
}
