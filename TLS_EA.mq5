#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//------------------------- Inputs ----------------------------------
input string InpHAIndicatorName  = "TLS_HA";
input string InpEMAIndicatorName = "TLS_EMA";

// iCustom inputs must match indicator inputs
input color InpBullColor = C'8,153,129';
input color InpBearColor = C'242,54,69';

input int            InpShortPeriod = 10;
input int            InpLongPeriod  = 39;
input ENUM_MA_METHOD InpMethod      = MODE_EMA;

input int    InpSlippagePoints     = 30;
input long   InpMagic              = 272727;

// Risk & SL/BE rules
input double RiskUSDPerTrade       = 50.0;  // fixed risk per trade (account currency)
input int    BufferPips            = 5;     // buffer in PIPS (converted by PipSize())
input double SLMaxPips             = 50.0;  // SL_MAX in PIPS
input int    InpSL_LookbackBars    = 200;   // lookback to find nearest HA pair
input double RiskReward            = 2.0;   // TP = RiskReward * Risk (R)

// buffer->scan lookback for lines
input int    LineScanLookbackBars  = 300;

// Cross scan for auto-arm/comment
input int    CrossScanLookbackBars = 500;  // scan to find latest cross dot

// Daily DD
input double InpDailyDD_Percent    = 3.0;   // realized daily DD limit (% of start-day balance)
input bool   InpCancelPendingsWhenDDHit = true;

// Chart comment
input bool   InpShowChartComment   = true;

// Debug
input bool   InpDebugOnce          = true;

//------------------------- Indicator handles ------------------------
int haHandle  = INVALID_HANDLE;
int emaHandle = INVALID_HANDLE;

//------------------------- State -----------------------------------
datetime lastBarTime = 0;

// day tracking
int      dayKey = 0;
double   dayStartBalance = 0.0;
double   dayLossLimit = 0.0;
bool     ddBlocked = false;

// waiting state (armed by cross)
bool     waitingBUY  = false;
bool     waitingSELL = false;

// ---------- NEW: one-use-per-line tracking ----------
long activeHighKey    = 0;  // current HighLine key (resets when HighLine changes)
long activeLowKey     = 0;  // current LowLine key (resets when LowLine changes)
long usedHighLineKey  = 0;  // HighLine key already USED (market OR limit placed)
long usedLowLineKey   = 0;  // LowLine key already USED (market OR limit placed)

// current cross (for comment)
string   currentCrossText  = "None";  // "Cross Up" / "Cross Down" / "Cross" / "None"
double   currentCrossPrice = 0.0;
datetime currentCrossTime  = 0;

// last BarsCalculated (for comment)
int lastHaBars  = 0;
int lastEmaBars = 0;

//============================== UTILS ==============================
double PipSize()
{
   // 5/3 digits: pip=10*point ; 2 digits metals: pip=10*point ; others: point
   if(_Digits == 5 || _Digits == 3 || _Digits == 2) return 100.0 * _Point;
   return _Point;
}

double NormalizePrice(double p){ return NormalizeDouble(p, _Digits); }

double NormalizeVolume(double vol)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vol < vmin) vol = vmin;
   if(vol > vmax) vol = vmax;

   vol = MathFloor(vol / vstep) * vstep;

   int digits = 2;
   double tmp = vstep;
   while(tmp < 1.0 && digits < 8) { tmp *= 10.0; digits++; }
   return NormalizeDouble(vol, digits);
}

bool IsNewBar()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 != lastBarTime)
   {
      lastBarTime = t0;
      return true;
   }
   return false;
}

int TodayKey()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   return (t.year * 10000 + t.mon * 100 + t.day);
}

void ResetDayIfNeeded()
{
   int k = TodayKey();
   if(k != dayKey || dayKey == 0)
   {
      dayKey = k;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dayLossLimit = dayStartBalance * (InpDailyDD_Percent / 100.0);
      ddBlocked = false;
   }
}

double RealizedLossToday()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   t.hour = 0; t.min = 0; t.sec = 0;
   datetime dayStart = StructToTime(t);
   datetime now = TimeCurrent();

   if(!HistorySelect(dayStart, now)) return 0.0;

   double loss = 0.0;
   int deals = (int)HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      long magic = (long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(magic != InpMagic) continue;

      string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      if(sym != _Symbol) continue;

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double net = profit + swap + comm;

      if(net < 0) loss += (-net);
   }
   return loss;
}

void UpdateDailyDDGate()
{
   ResetDayIfNeeded();
   double loss = RealizedLossToday();

   if(loss >= dayLossLimit)
   {
      ddBlocked = true;

      if(InpCancelPendingsWhenDDHit)
      {
         int total = OrdersTotal();
         for(int i = total - 1; i >= 0; i--)
         {
            ulong tk = OrderGetTicket(i);
            if(tk == 0) continue;
            if(!OrderSelect(tk)) continue;

            if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
            if((long)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
               trade.OrderDelete(tk);
         }
      }
   }
}

// ---- NEW: stable line key (integer in points) ----
long LineKey(double price)
{
   return (long)MathRound(price / _Point);
}

// ---- NEW: reset “used” when line changes value ----
void UpdateLineKeysAndResetIfChanged()
{
   double hlArr[1];
   double llArr[1];

   bool hasH = (CopyBuffer(emaHandle, 3, 0, 1, hlArr) == 1 && hlArr[0] != EMPTY_VALUE);
   bool hasL = (CopyBuffer(emaHandle, 4, 0, 1, llArr) == 1 && llArr[0] != EMPTY_VALUE);

   if(hasH)
   {
      long k = LineKey(hlArr[0]);
      if(activeHighKey == 0) activeHighKey = k;
      if(k != activeHighKey)
      {
         // HighLine changed -> reset usage for new line
         activeHighKey   = k;
         usedHighLineKey = 0;
      }
   }

   if(hasL)
   {
      long k = LineKey(llArr[0]);
      if(activeLowKey == 0) activeLowKey = k;
      if(k != activeLowKey)
      {
         activeLowKey   = k;
         usedLowLineKey = 0;
      }
   }
}

//=========================== INDICATOR READY ==========================
bool IndicatorsReady()
{
   if(haHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE) return false;

   lastHaBars  = BarsCalculated(haHandle);
   lastEmaBars = BarsCalculated(emaHandle);

   if(lastHaBars < 10) return false;
   if(lastEmaBars < (InpLongPeriod + 5)) return false;

   return true;
}

//=========================== INDICATOR READS ===========================
bool ReadHA(int shift, double &haOpen, double &haHigh, double &haLow, double &haClose, double &haColor)
{
   double buf[1];
   if(CopyBuffer(haHandle, 0, shift, 1, buf) != 1) return false; haOpen  = buf[0];
   if(CopyBuffer(haHandle, 1, shift, 1, buf) != 1) return false; haHigh  = buf[0];
   if(CopyBuffer(haHandle, 2, shift, 1, buf) != 1) return false; haLow   = buf[0];
   if(CopyBuffer(haHandle, 3, shift, 1, buf) != 1) return false; haClose = buf[0];
   if(CopyBuffer(haHandle, 4, shift, 1, buf) != 1) return false; haColor = buf[0];
   return true;
}

// Read line exactly at shift (no scan)
bool ReadHighLineAtShift(int shift, double &v)
{
   double a[1];
   if(CopyBuffer(emaHandle, 3, shift, 1, a) != 1) return false;
   v = a[0];
   return (v != EMPTY_VALUE);
}

bool ReadLowLineAtShift(int shift, double &v)
{
   double a[1];
   if(CopyBuffer(emaHandle, 4, shift, 1, a) != 1) return false;
   v = a[0];
   return (v != EMPTY_VALUE);
}

//=================== EXPOSURE HELPERS ===============================
bool HasPending(ENUM_ORDER_TYPE otype, ulong &ticketOut)
{
   ticketOut = 0;
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!OrderSelect(tk)) continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == otype)
      {
         ticketOut = tk;
         return true;
      }
   }
   return false;
}

void CancelPending(ENUM_ORDER_TYPE otype)
{
   ulong tk;
   if(HasPending(otype, tk))
      trade.OrderDelete(tk);
}

bool HasPosition(ENUM_POSITION_TYPE ptype, ulong &ticketOut)
{
   ticketOut = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(t == ptype)
      {
         ticketOut = tk;
         return true;
      }
   }
   return false;
}

bool HasBuyExposure()
{
   ulong tk=0;
   if(HasPosition(POSITION_TYPE_BUY, tk)) return true;
   if(HasPending(ORDER_TYPE_BUY_LIMIT, tk)) return true;
   return false;
}

bool HasSellExposure()
{
   ulong tk=0;
   if(HasPosition(POSITION_TYPE_SELL, tk)) return true;
   if(HasPending(ORDER_TYPE_SELL_LIMIT, tk)) return true;
   return false;
}

// Cancel pending if price hits its TP before being filled
void CancelPendingIfTPHit()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!OrderSelect(tk)) continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT) continue;

      double tp = OrderGetDouble(ORDER_TP);
      if(tp <= 0) continue;

      if(type == ORDER_TYPE_BUY_LIMIT)
      {
         if(bid >= tp) trade.OrderDelete(tk);
      }
      else
      {
         if(bid <= tp) trade.OrderDelete(tk);
      }
   }
}

//=================== SL FROM HA PAIR ===============================
// BUY: 2 HA red consecutive -> SL = min(low1,low2) - buffer
// SELL: 2 HA green consecutive -> SL = max(high1,high2) + buffer
bool FindSLFromNearestOppositeHAPair(bool isBuy, double &slPrice)
{
   double pip = PipSize();
   int maxSh = MathMax(2, InpSL_LookbackBars);

   for(int sh = 1; sh <= maxSh - 1; sh++)
   {
      double o1,h1,l1,c1,col1;
      double o2,h2,l2,c2,col2;

      if(!ReadHA(sh,   o1,h1,l1,c1,col1)) return false;
      if(!ReadHA(sh+1, o2,h2,l2,c2,col2)) return false;

      bool bull1 = (col1 == 0.0);
      bool bear1 = (col1 == 1.0);
      bool bull2 = (col2 == 0.0);
      bool bear2 = (col2 == 1.0);

      if(isBuy)
      {
         if(bear1 && bear2)
         {
            double baseLow = MathMin(l1, l2);
            slPrice = NormalizePrice(baseLow - (double)BufferPips * pip);
            return true;
         }
      }
      else
      {
         if(bull1 && bull2)
         {
            double baseHigh = MathMax(h1, h2);
            slPrice = NormalizePrice(baseHigh + (double)BufferPips * pip);
            return true;
         }
      }
   }
   return false;
}

//=================== LOT SIZING ===============================
double CalcLotsByRiskUSD(double entry, double sl)
{
   double pip = PipSize();
   double sl_pips = MathAbs(entry - sl) / pip;
   if(sl_pips <= 0.0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double pipValuePer1Lot = tickValue * (pip / tickSize);
   if(pipValuePer1Lot <= 0.0) return 0.0;

   double lots = RiskUSDPerTrade / (sl_pips * pipValuePer1Lot);
   return NormalizeVolume(lots);
}

//=================== CROSS SCAN + AUTO ARM ==========================
bool FindLatestCross(int lookback, int &shiftOut, double &priceOut, string &dirOut, datetime &timeOut)
{
   shiftOut = -1;
   priceOut = 0.0;
   dirOut   = "None";
   timeOut  = 0;

   double dot[1];

   for(int sh = 1; sh <= lookback; sh++)
   {
      if(CopyBuffer(emaHandle, 2, sh, 1, dot) != 1)
         continue;

      double d = dot[0];
      if(d == 0.0 || d == EMPTY_VALUE)
         continue;

      // found latest cross dot at shift=sh
      shiftOut = sh;
      priceOut = d;
      timeOut  = iTime(_Symbol, _Period, sh);

      // infer direction using line buffer at sh vs sh+1
      double low1[1], low2[1], high1[1], high2[1];
      int rL1 = CopyBuffer(emaHandle, 4, sh,   1, low1);
      int rL2 = CopyBuffer(emaHandle, 4, sh+1, 1, low2);
      int rH1 = CopyBuffer(emaHandle, 3, sh,   1, high1);
      int rH2 = CopyBuffer(emaHandle, 3, sh+1, 1, high2);

      if(rL1==1 && rL2==1)
      {
         bool lowNow  = (low1[0] != EMPTY_VALUE);
         bool lowPrev = (low2[0] != EMPTY_VALUE);
         if(lowNow && (!lowPrev || MathAbs(low1[0]-low2[0]) > (_Point*0.5)))
         {
            dirOut = "Cross Up";
            return true;
         }
      }

      if(rH1==1 && rH2==1)
      {
         bool highNow  = (high1[0] != EMPTY_VALUE);
         bool highPrev = (high2[0] != EMPTY_VALUE);
         if(highNow && (!highPrev || MathAbs(high1[0]-high2[0]) > (_Point*0.5)))
         {
            dirOut = "Cross Down";
            return true;
         }
      }

      // dot exists but ambiguous
      dirOut = "Cross";
      return true;
   }

   return false;
}

// Auto-arm only sets waiting flags based on latest cross (no “1 bar after cross” rule)
void AutoArmFromLatestCross()
{
   if(waitingBUY || waitingSELL) return;

   int sh; double p; string dir; datetime t;
   if(!FindLatestCross(CrossScanLookbackBars, sh, p, dir, t))
      return;

   currentCrossText  = dir;
   currentCrossPrice = p;
   currentCrossTime  = t;

   if(dir == "Cross Up")
   {
      if(!HasBuyExposure())
         waitingBUY = true;

      waitingSELL = false;
      return;
   }

   if(dir == "Cross Down")
   {
      if(!HasSellExposure())
         waitingSELL = true;

      waitingBUY = false;
      return;
   }
}

//=================== CROSS EVENT =====================
void GetCrossEventOnClosedBar(bool &crossUp, bool &crossDown, double &eventPrice)
{
   crossUp = false;
   crossDown = false;
   eventPrice = 0.0;

   currentCrossTime = iTime(_Symbol, _Period, 1);

   // 1) Require DOT on bar1 (indicator buffer 2)
   double dot1Arr[1];
   if(CopyBuffer(emaHandle, 2, 1, 1, dot1Arr) != 1)
   {
      currentCrossText  = "None";
      currentCrossPrice = 0.0;
      return;
   }

   double dot1 = dot1Arr[0];
   if(dot1 == 0.0 || dot1 == EMPTY_VALUE)
   {
      currentCrossText = "None";
      return;
   }

   currentCrossPrice = dot1;
   eventPrice        = dot1;

   // 2) Read EMA10 (buffer 0) & EMA39 (buffer 1) at bar1 and bar2
   double s1[1], s2[1], l1[1], l2[1];
   int rs1 = CopyBuffer(emaHandle, 0, 1, 1, s1); // Short MA bar1
   int rs2 = CopyBuffer(emaHandle, 0, 2, 1, s2); // Short MA bar2
   int rl1 = CopyBuffer(emaHandle, 1, 1, 1, l1); // Long  MA bar1
   int rl2 = CopyBuffer(emaHandle, 1, 2, 1, l2); // Long  MA bar2

   if(rs1 != 1 || rs2 != 1 || rl1 != 1 || rl2 != 1)
   {
      currentCrossText = "Cross";
      return;
   }

   double short1 = s1[0], short2 = s2[0];
   double long1  = l1[0], long2  = l2[0];

   // 3) Exact same event definition as indicator
   if(short1 > long1 && short2 <= long2)
   {
      crossUp = true;
      currentCrossText = "Cross Up";
      return;
   }

   if(short1 < long1 && short2 >= long2)
   {
      crossDown = true;
      currentCrossText = "Cross Down";
      return;
   }

   // DOT existed but event condition not met (rare), mark ambiguous
   currentCrossText = "Cross";
}

//=================== BREAKOUT CHECKS =========================
// Rule: if HighLine/LowLine already USED once -> never use again until line changes
bool CheckBuyBreakoutOnClosedBar(long &highKeyOut)
{
   highKeyOut = 0;
   if(!waitingBUY) return false;
   if(HasBuyExposure()) { waitingBUY = false; return false; }

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 <= o1) return false; // nến thường xanh

   double haO,haH,haL,haC,haCol;
   if(!ReadHA(1, haO,haH,haL,haC,haCol)) return false;
   if(haCol != 0.0) return false; // HA xanh

   double highLine1;
   if(!ReadHighLineAtShift(1, highLine1)) return false;

   if(c1 <= highLine1) return false; // break HighLine

   long key = LineKey(highLine1);

   // Block if this line already used (market or limit already placed)
   if(usedHighLineKey != 0 && key == usedHighLineKey) return false;

   highKeyOut = key;
   return true;
}

bool CheckSellBreakoutOnClosedBar(long &lowKeyOut)
{
   lowKeyOut = 0;
   if(!waitingSELL) return false;
   if(HasSellExposure()) { waitingSELL = false; return false; }

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 >= o1) return false; // nến thường đỏ

   double haO,haH,haL,haC,haCol;
   if(!ReadHA(1, haO,haH,haL,haC,haCol)) return false;
   if(haCol != 1.0) return false; // HA đỏ

   double lowLine1;
   if(!ReadLowLineAtShift(1, lowLine1)) return false;

   if(c1 >= lowLine1) return false; // break LowLine

   long key = LineKey(lowLine1);

   if(usedLowLineKey != 0 && key == usedLowLineKey) return false;

   lowKeyOut = key;
   return true;
}

//=================== EXECUTE ENTRY ===============================
// IMPORTANT RULE: mark line USED when order successfully placed (MARKET or LIMIT).
bool ExecuteEntry(bool isBuy, long lineKey)
{
   if(ddBlocked) return false;

   // exposure rule
   if(isBuy)
   {
      if(HasBuyExposure()) return false;
   }
   else
   {
      if(HasSellExposure()) return false;
   }

   double sl;
   if(!FindSLFromNearestOppositeHAPair(isBuy, sl)) return false;

   double pip = PipSize();

   double entryNow = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entryNow = NormalizePrice(entryNow);

   if(isBuy && sl >= entryNow) return false;
   if(!isBuy && sl <= entryNow) return false;

   double riskDist = isBuy ? (entryNow - sl) : (sl - entryNow);
   if(riskDist <= 0) return false;

   double riskPips = riskDist / pip;

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetExpertMagicNumber(InpMagic);

   // Case 1: within SL_MAX => MARKET
   if(riskPips <= SLMaxPips + 1e-9)
   {
      double lots = CalcLotsByRiskUSD(entryNow, sl);
      if(lots <= 0) return false;

      double tp = isBuy ? (entryNow + RiskReward * riskDist) : (entryNow - RiskReward * riskDist);
      tp = NormalizePrice(tp);

      bool ok = false;
      if(isBuy) ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "BUY HA+EMA");
      else      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "SELL HA+EMA");

      if(ok)
      {
         if(isBuy) usedHighLineKey = lineKey;
         else      usedLowLineKey  = lineKey;

         if(isBuy) waitingBUY = false; else waitingSELL = false;
      }
      return ok;
   }

   // Case 2: too large => LIMIT so EntryLimit->SL == SL_MAX
   double maxDist = SLMaxPips * pip;

   double entryLimit = isBuy ? (sl + maxDist) : (sl - maxDist);
   entryLimit = NormalizePrice(entryLimit);

   double tpLimit = isBuy ? (entryLimit + RiskReward * maxDist) : (entryLimit - RiskReward * maxDist);
   tpLimit = NormalizePrice(tpLimit);

   double lots2 = CalcLotsByRiskUSD(entryLimit, sl);
   if(lots2 <= 0) return false;

   bool ok2 = false;
   if(isBuy)
      ok2 = trade.BuyLimit(lots2, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "BUY LIMIT SL_MAX");
   else
      ok2 = trade.SellLimit(lots2, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "SELL LIMIT SL_MAX");

   if(ok2)
   {
      // IMPORTANT: even if later canceled/unfilled, this line is considered USED
      if(isBuy) usedHighLineKey = lineKey;
      else      usedLowLineKey  = lineKey;

      if(isBuy) waitingBUY = false; else waitingSELL = false;
   }

   return ok2;
}

//=================== MANAGEMENT ===============================
void CancelWaitingOnOppositeCross(bool crossUpNow, bool crossDownNow)
{
   if(crossDownNow) CancelPending(ORDER_TYPE_BUY_LIMIT);
   if(crossUpNow)   CancelPending(ORDER_TYPE_SELL_LIMIT);
}

void ManageBreakEvenAndCrossRules(bool crossUpNow, bool crossDownNow)
{
   double pip = PipSize();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong ticket = tk;
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      bool isProfitable = (ptype == POSITION_TYPE_BUY) ? (bid > entry) : (ask < entry);

      double R = (ptype == POSITION_TYPE_BUY) ? (entry - sl) : (sl - entry);
      if(R <= 0) continue;

      double threshold = R - (double)BufferPips * pip;
      if(threshold < 0) threshold = 0;

      if(ptype == POSITION_TYPE_BUY)
      {
         if((bid - entry) >= threshold)
         {
            if(sl < entry) trade.PositionModify(ticket, entry, tp);
         }

         if(crossDownNow)
         {
            if(isProfitable)
               trade.PositionModify(ticket, entry, tp);
            else
               trade.PositionModify(ticket, sl, entry);
         }
      }
      else
      {
         if((entry - ask) >= threshold)
         {
            if(sl > entry) trade.PositionModify(ticket, entry, tp);
         }

         if(crossUpNow)
         {
            if(isProfitable)
               trade.PositionModify(ticket, entry, tp);
            else
               trade.PositionModify(ticket, sl, entry);
         }
      }
   }
}

//=================== DEBUG ONCE ===============================
void DebugPrintEMAOnce()
{
   static bool done=false;
   if(done || !InpDebugOnce) return;
   done = true;

   double b2[1], b3[1], b4[1];
   int r2 = CopyBuffer(emaHandle, 2, 1, 1, b2); // CrossDot bar1
   int r3 = CopyBuffer(emaHandle, 3, 0, 1, b3); // HighLine current
   int r4 = CopyBuffer(emaHandle, 4, 0, 1, b4); // LowLine current

   Print("DEBUG EMA: r2=",r2," dot1=", (r2==1?DoubleToString(b2[0],_Digits):"NA"),
         " r3=",r3," high0=", (r3==1?DoubleToString(b3[0],_Digits):"NA"),
         " r4=",r4," low0=",  (r4==1?DoubleToString(b4[0],_Digits):"NA"),
         " haBars=", BarsCalculated(haHandle),
         " emaBars=", BarsCalculated(emaHandle),
         " err=", GetLastError());
}

//=================== CHART COMMENT ===============================
string FormatPriceOrNA(double v)
{
   if(v == EMPTY_VALUE) return "N/A";
   return DoubleToString(v, _Digits);
}

string CrossDirShort(string t)
{
   if(t == "Cross Up")   return "Up";
   if(t == "Cross Down") return "Down";
   if(t == "Cross")      return "Cross";
   return "None";
}

string FormatCrossLine()
{
   if(currentCrossText == "None")
      return "Cross : None";

   return "Cross : " + CrossDirShort(currentCrossText) +
          " at " + DoubleToString(currentCrossPrice, _Digits) +
          " at " + TimeToString(currentCrossTime, TIME_DATE|TIME_MINUTES);
}

void UpdateChartComment()
{
   if(!InpShowChartComment)
   {
      Comment("");
      return;
   }

   if(!IndicatorsReady())
   {
      Comment("Indicators not ready...\n");
      return;
   }

   double hl0Arr[1];
   double ll0Arr[1];

   bool hasH0 = (CopyBuffer(emaHandle, 3, 0, 1, hl0Arr) == 1 && hl0Arr[0] != EMPTY_VALUE);
   bool hasL0 = (CopyBuffer(emaHandle, 4, 0, 1, ll0Arr) == 1 && ll0Arr[0] != EMPTY_VALUE);


   string txt =
      "HighLine(0)   : " + (hasH0 ? FormatPriceOrNA(hl0Arr[0]) : "N/A") + "\n"
      "LowLine(0)    : " + (hasL0 ? FormatPriceOrNA(ll0Arr[0]) : "N/A") + "\n"
      + FormatCrossLine() + "\n"
      "waitingBUY    : " + (waitingBUY  ? "YES" : "NO") + "\n"
      "waitingSELL   : " + (waitingSELL ? "YES" : "NO") + "\n"
      "usedHighKey   : " + IntegerToString((int)usedHighLineKey) + "\n"
      "usedLowKey    : " + IntegerToString((int)usedLowLineKey) + "\n"
      "Daily DD Hit  : " + (ddBlocked ? "YES" : "NO") + "\n";

   Comment(txt);
}

//=================== INIT/DEINIT ===============================
int OnInit()
{
   haHandle = iCustom(_Symbol, _Period, InpHAIndicatorName, InpBullColor, InpBearColor);
   if(haHandle == INVALID_HANDLE)
   {
      Print("Failed HA handle. Name=", InpHAIndicatorName, " err=", GetLastError());
      return INIT_FAILED;
   }

   emaHandle = iCustom(_Symbol, _Period, InpEMAIndicatorName, InpShortPeriod, InpLongPeriod, InpMethod);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed EMA handle. Name=", InpEMAIndicatorName, " err=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetExpertMagicNumber(InpMagic);

   ResetDayIfNeeded();

   currentCrossText  = "None";
   currentCrossPrice = 0.0;
   currentCrossTime  = 0;

   waitingBUY = false;
   waitingSELL = false;

   activeHighKey = 0;
   activeLowKey  = 0;
   usedHighLineKey = 0;
   usedLowLineKey  = 0;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   if(haHandle  != INVALID_HANDLE) IndicatorRelease(haHandle);
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
}

//=================== TICK ===============================
void OnTick()
{
   UpdateDailyDDGate();
   CancelPendingIfTPHit();

   // Always update comment
   UpdateChartComment();

   if(!IndicatorsReady())
      return;

   DebugPrintEMAOnce();

   // Update line keys and reset used if line changed
   UpdateLineKeysAndResetIfChanged();

   // Auto-arm exactly once after indicators ready
   static bool didAutoArm = false;
   if(!didAutoArm)
   {
      AutoArmFromLatestCross();
      didAutoArm = true;
   }

   bool crossUpNow = false;
   bool crossDownNow = false;
   double crossPriceNow = 0.0;

   if(IsNewBar())
   {
      // Detect REAL cross on last closed bar
      GetCrossEventOnClosedBar(crossUpNow, crossDownNow, crossPriceNow);

      // Cancel pending on opposite cross
      CancelWaitingOnOppositeCross(crossUpNow, crossDownNow);

      // Arm waiting states on cross (break can happen same bar or later; we don't care)
      if(crossUpNow)
      {
         if(!HasBuyExposure())
            waitingBUY = true;
         waitingSELL = false;
      }

      if(crossDownNow)
      {
         if(!HasSellExposure())
            waitingSELL = true;
         waitingBUY = false;
      }

      // Trigger entries on breakout bar (bar1) whenever conditions meet
      if(!ddBlocked)
      {
         long highKey = 0, lowKey = 0;

         if(CheckBuyBreakoutOnClosedBar(highKey))
         {
            ExecuteEntry(true, highKey);
         }

         if(CheckSellBreakoutOnClosedBar(lowKey))
         {
            ExecuteEntry(false, lowKey);
         }
      }
   }

   // Manage positions (BE + opposite cross reaction)
   ManageBreakEvenAndCrossRules(crossUpNow, crossDownNow);

   UpdateChartComment();
}
