//+------------------------------------------------------------------+
//| TZTLS_EA_Pivot_HighLowLine_HA_Breakout.mq5                        |
//| MATCH 100% Pine logic (inclusive range, pivot-confirm-on-close)   |
//| + Added:                                                         |
//|   1) Cancel opposite pending LIMIT on new pivot (ROBUST)          |
//|   2) SL based on nearest HA opposite-color RUN (>=2 candles)      |
//|      - BUY  -> nearest HA RED run (pair) low                      |
//|      - SELL -> nearest HA GREEN run (pair) high                   |
//|   3) Cancel opposite pending BEFORE opening opposite entry        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//============================== INPUTS ==============================
input ENUM_TIMEFRAMES TF              = PERIOD_CURRENT;

input int    ShortPeriod              = 10;     // EMA10
input int    LongPeriod               = 39;     // EMA39
input double BufferPips               = 5.0;

input double RiskUSDPerTrade          = 50.0;
input double SLMaxPips                = 50.0;
input double DailyDDPercent           = 3.0;

input bool   EnableMoveToBE           = true;
input int    SlippagePoints           = 30;

// ---- NEW: HA "pair/run" SL reference ----
input int    HAPairMinCandles         = 2;     // minimum consecutive HA candles
input int    HAPairMaxLookbackBars    = 200;   // search back bars for nearest run

// Trade identifiers
input long   MagicNumber              = 2026838627;

// Visuals + logs
input bool   DrawPivotDot             = true;
input color  PivotColor               = clrPurple;
input int    PivotDotCode             = 159;    // dot
input int    PivotDotSize             = 3;

input bool   DrawHighLowLines         = true;
input color  HighLineColor            = clrRed;
input color  LowLineColor             = clrLime;
input int    LineWidth                = 1;

input int    HistoryBarsToScan        = 100;
input bool   PrintHistoryOnce         = true;
input bool   PrintNewPivotOnly        = true;
input bool   ShowChartSummary         = true;

//============================== GLOBALS ==============================
int hEmaShort = INVALID_HANDLE;
int hEmaLong  = INVALID_HANDLE;

double emaShort[];
double emaLong[];

string OBJ_PREFIX;
string OBJ_HIGHLINE;
string OBJ_LOWLINE;

datetime lastClosedBarTime = 0;

// last pivot times for building swings
datetime lastCrossUpTime   = 0;  // time of last pivot BUY (crossover) bar (CLOSED bar time)
datetime lastCrossDownTime = 0;  // time of last pivot SELL (crossunder) bar (CLOSED bar time)

// latest swing values
double highLineValue = 0.0;
double lowLineValue  = 0.0;

// Persistent last pivot info
string   gLastPivotText  = "N/A";
double   gLastPivotPrice = 0.0;   // EMA10 at pivot bar
datetime gLastPivotTime  = 0;

// Strategy WAIT state
bool     WAIT_BUY = false;
bool     WAIT_SELL = false;
datetime waitBuyStartTime = 0;
datetime waitSellStartTime = 0;

// Pending orders (SL_max scenario) - kept for UI only
bool   pendingBuy = false;
bool   pendingSell = false;
ulong  pendingBuyTicket = 0;
ulong  pendingSellTicket = 0;

// Daily DD tracking
datetime dayStartTime = 0;
double   dayStartBalance = 0.0;
bool     tradingLockedToday = false;

//============================== BASIC UTILS ==============================
double PipSize()
{
   // 5/3 digits: pip=10*point ; 2 digits metals: pip=10*point ; others: point
   if(_Digits == 5 || _Digits == 3 || _Digits == 2) return 100.0 * _Point;
   return _Point;
}
double NormalizePrice(double p){ return NormalizeDouble(p, _Digits); }

double NormalizeVolume(double vol)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vol < vmin) vol = vmin;
   if(vol > vmax) vol = vmax;

   vol = MathFloor(vol / vstep) * vstep;

   int digits = 2;
   double tmp = vstep;
   while(tmp < 1.0 && digits < 8) { tmp *= 10.0; digits++; }
   return NormalizeDouble(vol, digits);
}

bool IsNewClosedBar()
{
   datetime t1 = iTime(_Symbol, TF, 1);
   if(t1 != 0 && t1 != lastClosedBarTime)
   {
      lastClosedBarTime = t1;
      return true;
   }
   return false;
}

bool CopyEMAsAll(int count)
{
   ArrayResize(emaShort, count);
   ArrayResize(emaLong,  count);
   ArraySetAsSeries(emaShort, true);
   ArraySetAsSeries(emaLong,  true);

   if(CopyBuffer(hEmaShort, 0, 0, count, emaShort) < count) return false;
   if(CopyBuffer(hEmaLong,  0, 0, count, emaLong)  < count) return false;
   return true;
}

bool CrossOver(double prevA, double prevB, double currA, double currB){ return (prevA <= prevB && currA > currB); }
bool CrossUnder(double prevA, double prevB, double currA, double currB){ return (prevA >= prevB && currA < currB); }

//============================== OBJECT DRAW ==============================
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
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT,  false);

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
      "WAIT_BUY : ", (WAIT_BUY?"true":"false"), " | WAIT_SELL: ", (WAIT_SELL?"true":"false"), "\n",
      "PendingBuy: ", (pendingBuy?"true":"false"), " | PendingSell: ", (pendingSell?"true":"false"), "\n",
      "Last Pivot          : ", pivotInfo, "\n",
      "DailyLock           : ", (tradingLockedToday?"LOCKED":"OK")
   );
}

//============================== BUILD SWING LINES (history) ==============================
void RebuildLinesFromHistory()
{
   int N = MathMax(20, HistoryBarsToScan);
   int count = N + 300;
   if(!CopyEMAsAll(count)) return;

   datetime timeArr[];
   ArraySetAsSeries(timeArr, true);
   if(CopyTime(_Symbol, TF, 0, count, timeArr) < count) return;

   int maxShift = MathMin(N + 2, ArraySize(emaShort) - 3);
   if(maxShift < 3) return;

   int lastUpShift = -1;
   int lastDownShift = -1;

   highLineValue = 0.0;
   lowLineValue  = 0.0;

   for(int i=maxShift; i>=2; i--)
   {
      double prevS = emaShort[i+1], prevL = emaLong[i+1];
      double currS = emaShort[i],   currL = emaLong[i];
      if(prevS==EMPTY_VALUE || prevL==EMPTY_VALUE || currS==EMPTY_VALUE || currL==EMPTY_VALUE) continue;

      bool up   = CrossOver(prevS, prevL, currS, currL);
      bool down = CrossUnder(prevS, prevL, currS, currL);

      if(up)
      {
         if(lastDownShift > 0)
         {
            double minVal = currS;
            int minShift = i;
            for(int k=i; k<=lastDownShift && k<ArraySize(emaShort); k++)
            {
               if(emaShort[k] != EMPTY_VALUE && emaShort[k] < minVal)
               { minVal = emaShort[k]; minShift = k; }
            }
            lowLineValue = minVal;
            DrawOrReplaceRayLine(OBJ_LOWLINE, timeArr[minShift], minVal, LowLineColor);
         }

         lastUpShift = i;
         lastCrossUpTime = timeArr[i];
         DrawPivot(timeArr[i], currS);

         gLastPivotText  = "PIVOT BUY";
         gLastPivotTime  = timeArr[i];
         gLastPivotPrice = currS;
      }

      if(down)
      {
         if(lastUpShift > 0)
         {
            double maxVal = currS;
            int maxShift2 = i;
            for(int k=i; k<=lastUpShift && k<ArraySize(emaShort); k++)
            {
               if(emaShort[k] != EMPTY_VALUE && emaShort[k] > maxVal)
               { maxVal = emaShort[k]; maxShift2 = k; }
            }
            highLineValue = maxVal;
            DrawOrReplaceRayLine(OBJ_HIGHLINE, timeArr[maxShift2], maxVal, HighLineColor);
         }

         lastDownShift = i;
         lastCrossDownTime = timeArr[i];
         DrawPivot(timeArr[i], currS);

         gLastPivotText  = "PIVOT SELL";
         gLastPivotTime  = timeArr[i];
         gLastPivotPrice = currS;
      }
   }
}

//============================== LOG HISTORY ONCE ==============================
void LogHistoryOnce()
{
   if(!PrintHistoryOnce) return;

   int N = MathMax(20, HistoryBarsToScan);
   int count = N + 300;
   if(!CopyEMAsAll(count)) return;

   datetime timeArr[];
   ArraySetAsSeries(timeArr, true);
   if(CopyTime(_Symbol, TF, 0, count, timeArr) < count) return;

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
                                    TimeToString(timeArr[i], TIME_DATE|TIME_MINUTES),
                                    currS, currL);
      }
   }

   Print("---------- HISTORY PIVOTS (last ", N, " bars) ", _Symbol, " ", EnumToString(TF), " ----------");
   if(pivotsText == "") Print("(no pivots found)");
   else Print("\n", pivotsText);
   Print("--------------------------------------------------------------------------");
   PrintFormat("Nearest SwingHigh(HighLine)=%.3f | SwingLow(LowLine)=%.3f", highLineValue, lowLineValue);
}

//============================== DAILY DD ==============================
datetime GetDayStart(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

double ClosedPLToday()
{
   datetime now = TimeCurrent();
   if(!HistorySelect(dayStartTime, now)) return 0.0;

   double sum = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      if((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      sum += (profit + swap + comm);
   }
   return sum;
}

void UpdateDailyDDLock()
{
   datetime now = TimeCurrent();
   datetime start = GetDayStart(now);

   if(dayStartTime == 0 || start != dayStartTime)
   {
      dayStartTime = start;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      tradingLockedToday = false;

      WAIT_BUY = WAIT_SELL = false;
      waitBuyStartTime = waitSellStartTime = 0;

      pendingBuy = pendingSell = false;
      pendingBuyTicket = pendingSellTicket = 0;
   }

   double limit = dayStartBalance * (DailyDDPercent / 100.0);
   double pl = ClosedPLToday();
   if(pl <= -limit) tradingLockedToday = true;
}

//============================== HA CALC ==============================
bool CalcHeikenAshi(int shift, double &haOpen, double &haHigh, double &haLow, double &haClose)
{
   const int N = 30;
   int start = shift + N;
   if(start > 500) start = shift + 100;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, TF, 0, start + 3, rates) < start + 3) return false;

   double haO[], haC[], haH[], haL[];
   ArrayResize(haO, start + 3);
   ArrayResize(haC, start + 3);
   ArrayResize(haH, start + 3);
   ArrayResize(haL, start + 3);
   ArraySetAsSeries(haO, true);
   ArraySetAsSeries(haC, true);
   ArraySetAsSeries(haH, true);
   ArraySetAsSeries(haL, true);

   for(int i = start; i >= 0; i--)
   {
      double o = rates[i].open, h = rates[i].high, l = rates[i].low, c = rates[i].close;

      haC[i] = (o + h + l + c) / 4.0;
      if(i == start) haO[i] = (o + c) / 2.0;
      else          haO[i] = (haO[i+1] + haC[i+1]) / 2.0;

      haH[i] = MathMax(h, MathMax(haO[i], haC[i]));
      haL[i] = MathMin(l, MathMin(haO[i], haC[i]));
   }

   haOpen  = haO[shift];
   haClose = haC[shift];
   haHigh  = haH[shift];
   haLow   = haL[shift];
   return true;
}

//============================== NEW: HA RUN ("PAIR") SEARCH FOR SL ==============================
// BUY SL reference: nearest HA RED run (>=min candles) -> take LOWEST haLow in that run
bool FindNearestHARedRunLow(int fromShift, double &outLow)
{
   int minN = MathMax(2, HAPairMinCandles);
   int maxSearch = MathMax(50, HAPairMaxLookbackBars);

   for(int i = fromShift + 1; i < fromShift + maxSearch; i++)
   {
      double o, h, l, c;
      if(!CalcHeikenAshi(i, o, h, l, c)) return false;

      bool red = (c < o);
      if(!red) continue;

      int runCount = 1;
      double runLow = l;

      for(int j = i + 1; j < fromShift + maxSearch; j++)
      {
         double o2, h2, l2, c2;
         if(!CalcHeikenAshi(j, o2, h2, l2, c2)) break;
         bool red2 = (c2 < o2);
         if(!red2) break;

         runCount++;
         if(l2 < runLow) runLow = l2;
      }

      if(runCount >= minN)
      {
         outLow = runLow;
         return true;
      }

      i = i + runCount - 1; // skip this run
   }
   return false;
}

// SELL SL reference: nearest HA GREEN run (>=min candles) -> take HIGHEST haHigh in that run
bool FindNearestHAGreenRunHigh(int fromShift, double &outHigh)
{
   int minN = MathMax(2, HAPairMinCandles);
   int maxSearch = MathMax(50, HAPairMaxLookbackBars);

   for(int i = fromShift + 1; i < fromShift + maxSearch; i++)
   {
      double o, h, l, c;
      if(!CalcHeikenAshi(i, o, h, l, c)) return false;

      bool green = (c > o);
      if(!green) continue;

      int runCount = 1;
      double runHigh = h;

      for(int j = i + 1; j < fromShift + maxSearch; j++)
      {
         double o2, h2, l2, c2;
         if(!CalcHeikenAshi(j, o2, h2, l2, c2)) break;
         bool green2 = (c2 > o2);
         if(!green2) break;

         runCount++;
         if(h2 > runHigh) runHigh = h2;
      }

      if(runCount >= minN)
      {
         outHigh = runHigh;
         return true;
      }

      i = i + runCount - 1;
   }
   return false;
}

//============================== POSITIONS / PENDING ==============================
bool HasPosition(ENUM_POSITION_TYPE type)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) return true;
   }
   return false;
}
bool HasBuy(){ return HasPosition(POSITION_TYPE_BUY); }
bool HasSell(){ return HasPosition(POSITION_TYPE_SELL); }

bool PendingExists(ulong ticket)
{
   if(ticket == 0) return false;
   if(!OrderSelect(ticket)) return false;
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) return false;
   if((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber) return false;
   return true;
}

bool DeletePending(ulong &ticket)
{
   if(ticket == 0) return true;
   if(!PendingExists(ticket)) { ticket = 0; return true; }
   trade.SetExpertMagicNumber(MagicNumber);
   bool ok = trade.OrderDelete(ticket);
   if(ok) ticket = 0;
   return ok;
}

//============================== NEW: ROBUST CANCEL OF ALL PENDINGS BY SIDE ==============================
bool IsBuySidePending(ENUM_ORDER_TYPE t)
{
   return (t==ORDER_TYPE_BUY_LIMIT || t==ORDER_TYPE_BUY_STOP || t==ORDER_TYPE_BUY_STOP_LIMIT);
}
bool IsSellSidePending(ENUM_ORDER_TYPE t)
{
   return (t==ORDER_TYPE_SELL_LIMIT || t==ORDER_TYPE_SELL_STOP || t==ORDER_TYPE_SELL_STOP_LIMIT);
}

void CancelAllPendingBySide(bool cancelBuySide, bool cancelSellSide, const string reason)
{
   trade.SetExpertMagicNumber(MagicNumber);

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;

      if(!OrderSelect(tk))
         continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym != _Symbol) continue;

      long mg = (long)OrderGetInteger(ORDER_MAGIC);
      if(mg != MagicNumber) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      bool isPending =
         (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT ||
          type==ORDER_TYPE_SELL_LIMIT|| type==ORDER_TYPE_SELL_STOP|| type==ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending) continue;

      bool isBuySide  = (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
      bool isSellSide = (type==ORDER_TYPE_SELL_LIMIT|| type==ORDER_TYPE_SELL_STOP|| type==ORDER_TYPE_SELL_STOP_LIMIT);

      if( (cancelBuySide && isBuySide) || (cancelSellSide && isSellSide) )
      {
         bool ok = trade.OrderDelete(tk);
         int err = GetLastError();
         PrintFormat("[CANCEL] %s | %s ticket=%I64u type=%d %s (err=%d)",
                     reason, _Symbol, (long)tk, (int)type, (ok?"OK":"FAIL"), err);
      }
   }

   // reset local UI flags (do not rely on them for actual cancel logic)
   if(cancelBuySide)  { pendingBuy=false;  pendingBuyTicket=0;  }
   if(cancelSellSide) { pendingSell=false; pendingSellTicket=0; }
}

//============================== RISK VOLUME ==============================
double CalcVolumeByRisk(double entry, double sl)
{
   double dist = MathAbs(entry - sl);
   if(dist <= 0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;

   double lossPerLot = (dist / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.0;

   return NormalizeVolume(RiskUSDPerTrade / lossPerLot);
}

//============================== ORDERS ==============================
bool PlaceMarketBuy(double sl, double tp)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double vol = CalcVolumeByRisk(ask, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   bool ok = trade.Buy(vol, _Symbol, ask, sl, tp, "BUY Market");
   if(ok) PrintFormat("[ORDER] BUY market vol=%.2f SL=%.5f TP=%.5f", vol, sl, tp);
   return ok;
}

bool PlaceMarketSell(double sl, double tp)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double vol = CalcVolumeByRisk(bid, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   bool ok = trade.Sell(vol, _Symbol, bid, sl, tp, "SELL Market");
   if(ok) PrintFormat("[ORDER] SELL market vol=%.2f SL=%.5f TP=%.5f", vol, sl, tp);
   return ok;
}

bool PlaceBuyLimit(double entry, double sl, double tp, ulong &outTicket)
{
   double vol = CalcVolumeByRisk(entry, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   bool ok = trade.BuyLimit(vol, NormalizePrice(entry), _Symbol,
                            NormalizePrice(sl), NormalizePrice(tp),
                            ORDER_TIME_GTC, 0, "BUY LIMIT SL_MAX");
   if(ok) outTicket = (ulong)trade.ResultOrder();
   return ok;
}

bool PlaceSellLimit(double entry, double sl, double tp, ulong &outTicket)
{
   double vol = CalcVolumeByRisk(entry, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   bool ok = trade.SellLimit(vol, NormalizePrice(entry), _Symbol,
                             NormalizePrice(sl), NormalizePrice(tp),
                             ORDER_TIME_GTC, 0, "SELL LIMIT SL_MAX");
   if(ok) outTicket = (ulong)trade.ResultOrder();
   return ok;
}

//============================== BE MANAGEMENT ==============================
void ManageBreakEven()
{
   if(!EnableMoveToBE) return;

   double pip = PipSize();
   double beTriggerOffset = BufferPips * pip;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if(entry <= 0 || sl <= 0) continue;

      if(MathAbs(sl - entry) <= (_Point*2)) continue;

      double R = MathAbs(entry - sl);
      double trigger = R - beTriggerOffset;
      if(trigger <= 0) trigger = R;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool move = false;
      if(type == POSITION_TYPE_BUY)  { if((bid - entry) >= trigger) move = true; }
      if(type == POSITION_TYPE_SELL) { if((entry - ask) >= trigger) move = true; }

      if(move)
      {
         trade.SetExpertMagicNumber(MagicNumber);
         trade.PositionModify(_Symbol, entry, tp);
         PrintFormat("[BE] Move SL to BE entry=%.5f", entry);
      }
   }
}

//============================== PINE-MATCHED SWING RANGE HELPERS ==============================
bool PineFindMaxFromPivotToLast(datetime lastOppPivotTime, int pivotShift, double &outVal, int &outShift)
{
   outVal = 0.0; outShift = -1;
   if(lastOppPivotTime == 0) return false;

   int endShift = iBarShift(_Symbol, TF, lastOppPivotTime, false);
   if(endShift < pivotShift) return false;
   if(endShift >= ArraySize(emaShort)) return false;

   double maxVal = emaShort[pivotShift];
   int maxShift = pivotShift;

   for(int k=pivotShift; k<=endShift; k++)
   {
      double v = emaShort[k];
      if(v == EMPTY_VALUE) continue;
      if(v > maxVal) { maxVal = v; maxShift = k; }
   }

   outVal = maxVal;
   outShift = maxShift;
   return true;
}

bool PineFindMinFromPivotToLast(datetime lastOppPivotTime, int pivotShift, double &outVal, int &outShift)
{
   outVal = 0.0; outShift = -1;
   if(lastOppPivotTime == 0) return false;

   int endShift = iBarShift(_Symbol, TF, lastOppPivotTime, false);
   if(endShift < pivotShift) return false;
   if(endShift >= ArraySize(emaShort)) return false;

   double minVal = emaShort[pivotShift];
   int minShift = pivotShift;

   for(int k=pivotShift; k<=endShift; k++)
   {
      double v = emaShort[k];
      if(v == EMPTY_VALUE) continue;
      if(v < minVal) { minVal = v; minShift = k; }
   }

   outVal = minVal;
   outShift = minShift;
   return true;
}

//============================== PIVOT UPDATE ==============================
void OnPivotBuy(datetime t, double ema10, double ema39)
{
   DrawPivot(t, ema10);

   double minVal; int minShift;
   if(PineFindMinFromPivotToLast(lastCrossDownTime, 1, minVal, minShift))
   {
      lowLineValue = minVal;
      datetime tLine = iTime(_Symbol, TF, minShift);
      DrawOrReplaceRayLine(OBJ_LOWLINE, tLine, minVal, LowLineColor);
   }

   lastCrossUpTime = t;

   gLastPivotText  = "PIVOT BUY";
   gLastPivotTime  = t;
   gLastPivotPrice = ema10;

   WAIT_BUY = true;
   WAIT_SELL = false;
   waitBuyStartTime = t;

   if(PrintNewPivotOnly)
      PrintFormat("[PIVOT NEW] PIVOT BUY  %s EMA10=%.5f EMA39=%.5f | LowLine=%.5f HighLine=%.5f",
                  TimeToString(t, TIME_DATE|TIME_MINUTES), ema10, ema39, lowLineValue, highLineValue);
}

void OnPivotSell(datetime t, double ema10, double ema39)
{
   DrawPivot(t, ema10);

   double maxVal; int maxShift;
   if(PineFindMaxFromPivotToLast(lastCrossUpTime, 1, maxVal, maxShift))
   {
      highLineValue = maxVal;
      datetime tLine = iTime(_Symbol, TF, maxShift);
      DrawOrReplaceRayLine(OBJ_HIGHLINE, tLine, maxVal, HighLineColor);
   }

   lastCrossDownTime = t;

   gLastPivotText  = "PIVOT SELL";
   gLastPivotTime  = t;
   gLastPivotPrice = ema10;

   WAIT_SELL = true;
   WAIT_BUY = false;
   waitSellStartTime = t;

   if(PrintNewPivotOnly)
      PrintFormat("[PIVOT NEW] PIVOT SELL %s EMA10=%.5f EMA39=%.5f | LowLine=%.5f HighLine=%.5f",
                  TimeToString(t, TIME_DATE|TIME_MINUTES), ema10, ema39, lowLineValue, highLineValue);
}

//============================== STRATEGY: WAIT -> BREAKOUT -> ENTRY NEXT CANDLE ==============================
void CheckEntryOnNewBar()
{
   if(tradingLockedToday) return;

   // keep UI flags roughly correct (not relied upon)
   if(pendingBuy  && !PendingExists(pendingBuyTicket))   { pendingBuy=false;  pendingBuyTicket=0; }
   if(pendingSell && !PendingExists(pendingSellTicket))  { pendingSell=false; pendingSellTicket=0; }

   datetime t1 = iTime(_Symbol, TF, 1);
   if(t1 == 0) return;

   double c1 = iClose(_Symbol, TF, 1);
   double o1 = iOpen (_Symbol, TF, 1);
   bool normalGreen = (c1 > o1);
   bool normalRed   = (c1 < o1);

   double haO, haH, haL, haC;
   if(!CalcHeikenAshi(1, haO, haH, haL, haC)) return;
   bool haGreen = (haC > haO);
   bool haRed   = (haC < haO);

   double pip = PipSize();
   double buffer = BufferPips * pip;

   //==================== BUY ====================
   if(WAIT_BUY && highLineValue > 0)
   {
      if(waitBuyStartTime != 0 && t1 > waitBuyStartTime)
      {
         bool breakout = (c1 > highLineValue);
         if(breakout && haGreen && normalGreen)
         {
            if(!HasBuy())
            {
               // IMPORTANT: before BUY, cancel SELL pendings
               CancelAllPendingBySide(false, true, "Before BUY entry -> cancel SELL pendings");

               // NEW SL: nearest HA RED run low
               double haRedRunLow;
               if(FindNearestHARedRunLow(1, haRedRunLow))
               {
                  double sl = NormalizePrice(haRedRunLow - buffer);
                  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  if(ask <= 0) return;

                  double distPips = MathAbs(ask - sl) / pip;

                  if(distPips <= SLMaxPips + 1e-9)
                  {
                     double R = MathAbs(ask - sl);
                     double tpDist = 2.0*R - buffer;
                     if(tpDist > pip)
                     {
                        double tp = NormalizePrice(ask + tpDist);
                        PrintFormat("[CONFIRM BUY] %s close=%.5f > HighLine=%.5f | SL(HA red run)=%.5f",
                                    TimeToString(t1, TIME_DATE|TIME_MINUTES), c1, highLineValue, sl);
                        if(PlaceMarketBuy(sl, tp)) WAIT_BUY = false;
                     }
                  }
                  else
                  {
                     double plannedEntry = NormalizePrice(sl + SLMaxPips*pip);
                     if(plannedEntry < ask - _Point*2)
                     {
                        double R = MathAbs(plannedEntry - sl);
                        double tpDist = 2.0*R - buffer;
                        if(tpDist > pip)
                        {
                           double tp = NormalizePrice(plannedEntry + tpDist);
                           ulong tk=0;
                           PrintFormat("[CONFIRM BUY] SL too far (%.1f pips). Place BuyLimit @%.5f (SLmax=%.1f)",
                                       distPips, plannedEntry, SLMaxPips);
                           if(PlaceBuyLimit(plannedEntry, sl, tp, tk))
                           {
                              pendingBuy = true;
                              pendingBuyTicket = tk;
                              WAIT_BUY = false;
                           }
                        }
                     }
                  }
               }
               else
               {
                  Print("[BUY] No HA red run found for SL.");
               }
            }
         }
      }
   }

   //==================== SELL ====================
   if(WAIT_SELL && lowLineValue > 0)
   {
      if(waitSellStartTime != 0 && t1 > waitSellStartTime)
      {
         bool breakout = (c1 < lowLineValue);
         if(breakout && haRed && normalRed)
         {
            if(!HasSell())
            {
               // IMPORTANT: before SELL, cancel BUY pendings
               CancelAllPendingBySide(true, false, "Before SELL entry -> cancel BUY pendings");

               // NEW SL: nearest HA GREEN run high
               double haGreenRunHigh;
               if(FindNearestHAGreenRunHigh(1, haGreenRunHigh))
               {
                  double sl = NormalizePrice(haGreenRunHigh + buffer);
                  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  if(bid <= 0) return;

                  double distPips = MathAbs(bid - sl) / pip;

                  if(distPips <= SLMaxPips + 1e-9)
                  {
                     double R = MathAbs(bid - sl);
                     double tpDist = 2.0*R - buffer;
                     if(tpDist > pip)
                     {
                        double tp = NormalizePrice(bid - tpDist);
                        PrintFormat("[CONFIRM SELL] %s close=%.5f < LowLine=%.5f | SL(HA green run)=%.5f",
                                    TimeToString(t1, TIME_DATE|TIME_MINUTES), c1, lowLineValue, sl);
                        if(PlaceMarketSell(sl, tp)) WAIT_SELL = false;
                     }
                  }
                  else
                  {
                     double plannedEntry = NormalizePrice(sl - SLMaxPips*pip);
                     if(plannedEntry > bid + _Point*2)
                     {
                        double R = MathAbs(plannedEntry - sl);
                        double tpDist = 2.0*R - buffer;
                        if(tpDist > pip)
                        {
                           double tp = NormalizePrice(plannedEntry - tpDist);
                           ulong tk=0;
                           PrintFormat("[CONFIRM SELL] SL too far (%.1f pips). Place SellLimit @%.5f (SLmax=%.1f)",
                                       distPips, plannedEntry, SLMaxPips);
                           if(PlaceSellLimit(plannedEntry, sl, tp, tk))
                           {
                              pendingSell = true;
                              pendingSellTicket = tk;
                              WAIT_SELL = false;
                           }
                        }
                     }
                  }
               }
               else
               {
                  Print("[SELL] No HA green run found for SL.");
               }
            }
         }
      }
   }
}

//============================== ON NEW BAR: detect pivot + trade ==============================
void OnNewClosedBar()
{
   int need = MathMax(HistoryBarsToScan + 20, LongPeriod + 80);
   if(!CopyEMAsAll(need)) return;

   double s2 = emaShort[2], l2 = emaLong[2];
   double s1 = emaShort[1], l1 = emaLong[1];

   bool pivotBuy  = CrossOver(s2, l2, s1, l1);
   bool pivotSell = CrossUnder(s2, l2, s1, l1);

   datetime tPivot = iTime(_Symbol, TF, 1);

   // ROBUST: cancel opposite side pendings immediately on pivot flip
   if(pivotBuy)
      CancelAllPendingBySide(false, true, "Pivot BUY -> cancel SELL pendings");
   if(pivotSell)
      CancelAllPendingBySide(true, false, "Pivot SELL -> cancel BUY pendings");

   if(pivotBuy)  OnPivotBuy(tPivot, s1, l1);
   if(pivotSell) OnPivotSell(tPivot, s1, l1);

   CheckEntryOnNewBar();

   UpdateChartSummary();
   ChartRedraw();
}

//============================== LIFECYCLE ==============================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   hEmaShort = iMA(_Symbol, TF, ShortPeriod, 0, MODE_EMA, PRICE_MEDIAN);
   hEmaLong  = iMA(_Symbol, TF, LongPeriod,  0, MODE_EMA, PRICE_MEDIAN);
   if(hEmaShort == INVALID_HANDLE || hEmaLong == INVALID_HANDLE)
      return INIT_FAILED;

   OBJ_PREFIX   = "TZTLS_EA_" + _Symbol + "_" + IntegerToString((int)TF) + "_" + IntegerToString((int)MagicNumber);
   OBJ_HIGHLINE = OBJ_PREFIX + "_HIGHLINE";
   OBJ_LOWLINE  = OBJ_PREFIX + "_LOWLINE";

   DeleteByPrefix(OBJ_PREFIX);

   dayStartTime = GetDayStart(TimeCurrent());
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   tradingLockedToday = false;

   RebuildLinesFromHistory();
   if(PrintHistoryOnce) LogHistoryOnce();

   if(gLastPivotTime == 0)
      gLastPivotText = "HISTORY loaded";

   UpdateChartSummary();
   ChartRedraw();

   Print("[INIT] EA loaded: Pine-matched lines + SL by HA opposite-color run + robust cancel opposite pendings (pivot + before entry).");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteByPrefix(OBJ_PREFIX);
   Comment("");

   if(hEmaShort != INVALID_HANDLE) IndicatorRelease(hEmaShort);
   if(hEmaLong  != INVALID_HANDLE) IndicatorRelease(hEmaLong);
}

void OnTick()
{
   UpdateDailyDDLock();
   ManageBreakEven();

   UpdateChartSummary();

   if(!IsNewClosedBar())
      return;

   if(!tradingLockedToday)
      OnNewClosedBar();
}
//+------------------------------------------------------------------+
