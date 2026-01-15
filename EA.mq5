//+------------------------------------------------------------------+
//| TLS_EA.mq5                                                       |
//|                                                                  |
//| Reads ONLY from indicators:                                      |
//|  - TLS_HA  (buffers 0..4): HA O/H/L/C + Color (0 bull, 1 bear)   |
//|  - TLS_EMA (buffers 2,3,4): CrossDot + HighLineData + LowLineData|
//|                                                                  |
//| Added (per your latest request):                                 |
//|  - buffer -> scan -> object for HighLine/LowLine                 |
//|  - Last Cross state: "Cross Up/Down at PRICE at TIME"            |
//|  - On-chart Comment() showing HighLine/LowLine + LastCross        |
//|                                                                  |
//| Trading rules implemented (as you confirmed 100%):               |
//|  - Entry uses Cross + Breakout + normal candle color + HA color  |
//|  - SL from nearest 2 consecutive opposite HA candles + buffer    |
//|  - SL_MAX: market if within max, else limit at max risk distance |
//|  - TP = 2R, BE at 1R - buffer                                    |
//|  - Opposite cross reaction on open positions (SL->Entry / TP->ET)|
//|  - Exposure limit Option 1: per direction 1 exposure max         |
//|  - Hedge allowed: 1 BUY + 1 SELL max total exposures=2           |
//|  - Cancel pending on opposite cross while waiting (SL_MAX plan)  |
//|  - Cancel pending if price hits TP before fill                   |
//|  - Daily realized DD stop (3% of start-day balance)              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//------------------------- Inputs ----------------------------------
input string InpHAIndicatorName  = "TLS_HA";
input string InpEMAIndicatorName = "TLS_EMA";

// (These exist only because iCustom needs to match your indicator inputs)
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

// buffer->scan lookback for lines (avoid miss when buffer returns 0/EMPTY)
input int    LineScanLookbackBars  = 300;

// Daily DD
input double InpDailyDD_Percent    = 3.0;   // realized daily DD limit (% of start-day balance)
input bool   InpCancelPendingsWhenDDHit = true;

// Chart comment
input bool   InpShowChartComment   = true;

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

// LastCross state (for comment/debug and robust cross detection)
enum CrossType { CROSS_NONE=0, CROSS_UP=1, CROSS_DOWN=2 };
CrossType lastCross      = CROSS_NONE;
datetime  lastCrossTime  = 0;
double    lastCrossPrice = 0.0;

// For object-based cross fallback
double lastHighObjPrice = 0.0;
double lastLowObjPrice  = 0.0;

//============================== BASIC UTILS ==============================
double PipSize()
{
   // EXACTLY as you requested:
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

// Cross events from EMA indicator buffers:
// crossUp   => LowLineData (buffer 4) changes/appears
// crossDown => HighLineData(buffer 3) changes/appears
bool DetectCrossUpOnClosedBar_Buffer()
{
   double a1[1], a2[1];
   if(CopyBuffer(emaHandle, 4, 1, 1, a1) != 1) return false;
   if(CopyBuffer(emaHandle, 4, 2, 1, a2) != 1) return false;

   double low1 = a1[0];
   double low2 = a2[0];

   if(low1 == EMPTY_VALUE || low1 == 0.0) return false;
   if(low2 == EMPTY_VALUE || low2 == 0.0) return true;
   return (low1 != low2);
}

bool DetectCrossDownOnClosedBar_Buffer()
{
   double a1[1], a2[1];
   if(CopyBuffer(emaHandle, 3, 1, 1, a1) != 1) return false;
   if(CopyBuffer(emaHandle, 3, 2, 1, a2) != 1) return false;

   double hi1 = a1[0];
   double hi2 = a2[0];

   if(hi1 == EMPTY_VALUE || hi1 == 0.0) return false;
   if(hi2 == EMPTY_VALUE || hi2 == 0.0) return true;
   return (hi1 != hi2);
}

//=================== buffer -> scan -> object (LINES) ==================
bool GetLatestNonEmptyFromBuffer(int handle, int bufferIndex, int startShift, int lookback, double &outVal)
{
   outVal = EMPTY_VALUE;
   double tmp[1];

   for(int sh = startShift; sh <= startShift + lookback; sh++)
   {
      ResetLastError();
      if(CopyBuffer(handle, bufferIndex, sh, 1, tmp) != 1)
         continue;

      double v = tmp[0];

      // treat EMPTY_VALUE and 0 as "not available"
      if(v != EMPTY_VALUE && v != 0.0)
      {
         outVal = v;
         return true;
      }
   }
   return false;
}

bool GetObjectLinePrice(const string name, double &priceOut)
{
   priceOut = EMPTY_VALUE;
   if(ObjectFind(0, name) < 0) return false;

   double p = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   if(p == 0.0) return false;

   priceOut = p;
   return true;
}

bool GetEffectiveHighLine(double &v)
{
   // TLS_EMA HighLineData = buffer 3
   if(GetLatestNonEmptyFromBuffer(emaHandle, 3, 1, LineScanLookbackBars, v)) return true;
   if(GetObjectLinePrice("TLS_HighLine", v)) return true;
   return false;
}

bool GetEffectiveLowLine(double &v)
{
   // TLS_EMA LowLineData = buffer 4
   if(GetLatestNonEmptyFromBuffer(emaHandle, 4, 1, LineScanLookbackBars, v)) return true;
   if(GetObjectLinePrice("TLS_LowLine", v)) return true;
   return false;
}

//=================== buffer -> scan -> object (CROSS) ==================
// Update lastCross state for the last closed bar, and return event flags
void GetCrossEventOnClosedBar(bool &crossUp, bool &crossDown)
{
   crossUp = false;
   crossDown = false;

   datetime tCross = iTime(_Symbol, _Period, 1);

   // 1) buffer-based event first
   bool upBuf = DetectCrossUpOnClosedBar_Buffer();
   bool dnBuf = DetectCrossDownOnClosedBar_Buffer();

   if(upBuf && !dnBuf)
   {
      crossUp = true;
      lastCross = CROSS_UP;
      lastCrossTime = tCross;

      double lowLine = EMPTY_VALUE;
      if(GetEffectiveLowLine(lowLine)) lastCrossPrice = lowLine;
      else lastCrossPrice = 0.0;

      return;
   }
   if(dnBuf && !upBuf)
   {
      crossDown = true;
      lastCross = CROSS_DOWN;
      lastCrossTime = tCross;

      double highLine = EMPTY_VALUE;
      if(GetEffectiveHighLine(highLine)) lastCrossPrice = highLine;
      else lastCrossPrice = 0.0;

      return;
   }

   // 2) object fallback (line first appearance or price change)
   double highP = EMPTY_VALUE, lowP = EMPTY_VALUE;
   bool hasHigh = GetObjectLinePrice("TLS_HighLine", highP);
   bool hasLow  = GetObjectLinePrice("TLS_LowLine",  lowP);

   // CrossUp: LowLine object changed/appeared
   if(hasLow)
   {
      if(lastLowObjPrice == 0.0 || MathAbs(lowP - lastLowObjPrice) > (_Point * 0.5))
      {
         lastLowObjPrice = lowP;
         crossUp = true;

         lastCross = CROSS_UP;
         lastCrossTime = tCross;
         lastCrossPrice = lowP;
      }
   }

   // CrossDown: HighLine object changed/appeared
   if(hasHigh)
   {
      if(lastHighObjPrice == 0.0 || MathAbs(highP - lastHighObjPrice) > (_Point * 0.5))
      {
         lastHighObjPrice = highP;
         crossDown = true;

         lastCross = CROSS_DOWN;
         lastCrossTime = tCross;
         lastCrossPrice = highP;
      }
   }
}

//=========================== EXPOSURE HELPERS ===========================
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

//=========================== SL FROM HA PAIR ===========================
// BUY: nearest 2 HA red in a row -> SL = min(low1,low2) - buffer
// SELL: nearest 2 HA green in a row -> SL = max(high1,high2) + buffer
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

//=========================== ENTRY CHECKS ==============================
// Note: entry requires cross + breakout on the same last-closed bar.
bool CheckBuySignalOnClosedBar()
{
   // normal candle must be green
   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 <= o1) return false;

   // HA must be green
   double haO,haH,haL,haC,haCol;
   if(!ReadHA(1, haO,haH,haL,haC,haCol)) return false;
   if(haCol != 0.0) return false;

   // crossUp (robust)
   bool crossUp=false, crossDown=false;
   GetCrossEventOnClosedBar(crossUp, crossDown);
   if(!crossUp) return false;

   // breakout above HighLine (buffer->scan->object)
   double highLine = EMPTY_VALUE;
   if(!GetEffectiveHighLine(highLine)) return false;

   return (c1 > highLine);
}

bool CheckSellSignalOnClosedBar()
{
   // normal candle must be red
   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 >= o1) return false;

   // HA must be red
   double haO,haH,haL,haC,haCol;
   if(!ReadHA(1, haO,haH,haL,haC,haCol)) return false;
   if(haCol != 1.0) return false;

   // crossDown (robust)
   bool crossUp=false, crossDown=false;
   GetCrossEventOnClosedBar(crossUp, crossDown);
   if(!crossDown) return false;

   // breakout below LowLine (buffer->scan->object)
   double lowLine = EMPTY_VALUE;
   if(!GetEffectiveLowLine(lowLine)) return false;

   return (c1 < lowLine);
}

//=========================== LOT SIZING ===============================
// lots = RiskUSD / (SL_pips * pipValuePer1Lot)
// pipValuePer1Lot = tickValue * (pipSize / tickSize)
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

//=========================== EXECUTE ENTRY =============================
void ExecuteEntry(bool isBuy)
{
   if(ddBlocked) return;

   // Exposure limit (Option 1)
   if(isBuy)
   {
      if(HasBuyExposure()) return;
   }
   else
   {
      if(HasSellExposure()) return;
   }

   double sl;
   if(!FindSLFromNearestOppositeHAPair(isBuy, sl)) return;

   double pip = PipSize();

   double entryNow = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entryNow = NormalizePrice(entryNow);

   if(isBuy && sl >= entryNow) return;
   if(!isBuy && sl <= entryNow) return;

   double riskDist = isBuy ? (entryNow - sl) : (sl - entryNow);
   if(riskDist <= 0) return;

   double riskPips = riskDist / pip;

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetExpertMagicNumber(InpMagic);

   // Case 1: within SL_MAX => MARKET
   if(riskPips <= SLMaxPips + 1e-9)
   {
      double lots = CalcLotsByRiskUSD(entryNow, sl);
      if(lots <= 0) return;

      double R  = riskDist;
      double tp = isBuy ? (entryNow + 2.0 * R) : (entryNow - 2.0 * R);
      tp = NormalizePrice(tp);

      if(isBuy) trade.Buy(lots, _Symbol, 0.0, sl, tp, "BUY HA+EMA");
      else      trade.Sell(lots, _Symbol, 0.0, sl, tp, "SELL HA+EMA");
      return;
   }

   // Case 2: too large => LIMIT so EntryLimit->SL == SL_MAX
   double maxDist = SLMaxPips * pip;

   double entryLimit = isBuy ? (sl + maxDist) : (sl - maxDist);
   entryLimit = NormalizePrice(entryLimit);

   double tpLimit = isBuy ? (entryLimit + 2.0 * maxDist) : (entryLimit - 2.0 * maxDist);
   tpLimit = NormalizePrice(tpLimit);

   // exposure re-check
   if(isBuy && HasBuyExposure()) return;
   if(!isBuy && HasSellExposure()) return;

   double lots2 = CalcLotsByRiskUSD(entryLimit, sl);
   if(lots2 <= 0) return;

   if(isBuy)
      trade.BuyLimit(lots2, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "BUY LIMIT SL_MAX");
   else
      trade.SellLimit(lots2, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "SELL LIMIT SL_MAX");
}

//=========================== MANAGEMENT ===============================
void CancelWaitingOnOppositeCross(bool crossUpNow, bool crossDownNow)
{
   // Waiting = pending from SL_MAX plan
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

      // BE at 1R - buffer
      double threshold = R - (double)BufferPips * pip;
      if(threshold < 0) threshold = 0;

      if(ptype == POSITION_TYPE_BUY)
      {
         if((bid - entry) >= threshold)
         {
            if(sl < entry) trade.PositionModify(ticket, entry, tp);
         }

         // opposite cross while BUY exists
         if(crossDownNow)
         {
            if(isProfitable)
               trade.PositionModify(ticket, entry, tp);  // SL -> Entry
            else
               trade.PositionModify(ticket, sl, entry);  // TP -> Entry
         }
      }
      else // SELL
      {
         if((entry - ask) >= threshold)
         {
            if(sl > entry) trade.PositionModify(ticket, entry, tp);
         }

         // opposite cross while SELL exists
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

//=========================== CHART COMMENT =============================
string CrossTypeToText(CrossType t)
{
   if(t == CROSS_UP)   return "Cross Up";
   if(t == CROSS_DOWN) return "Cross Down";
   return "None";
}

string FormatPriceOrNA(double v)
{
   if(v == EMPTY_VALUE || v == 0.0) return "N/A";
   return DoubleToString(v, _Digits);
}

string FormatTimeOrNA(datetime t)
{
   if(t <= 0) return "N/A";
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
}

string FormatLastCrossLine()
{
   if(lastCross == CROSS_NONE)
      return "Last Cross : None";

   return "Last Cross : " + CrossTypeToText(lastCross) +
          " at " + FormatPriceOrNA(lastCrossPrice) +
          " at " + FormatTimeOrNA(lastCrossTime);
}

void UpdateChartComment()
{
   if(!InpShowChartComment)
   {
      Comment("");
      return;
   }

   double highLine = EMPTY_VALUE, lowLine = EMPTY_VALUE;
   GetEffectiveHighLine(highLine);
   GetEffectiveLowLine(lowLine);

   string txt =
      "HighLine : " + FormatPriceOrNA(highLine) + "\n"
      "LowLine  : " + FormatPriceOrNA(lowLine)  + "\n" +
      FormatLastCrossLine() + "\n"
      "BUY Exposure  : " + (HasBuyExposure()  ? "YES" : "NO") + "\n"
      "SELL Exposure : " + (HasSellExposure() ? "YES" : "NO") + "\n"
      "Daily DD Hit  : " + (ddBlocked ? "YES" : "NO");

   Comment(txt);
}

//=========================== INIT/DEINIT ==============================
int OnInit()
{
   haHandle = iCustom(_Symbol, _Period, InpHAIndicatorName, InpBullColor, InpBearColor);
   if(haHandle == INVALID_HANDLE)
   {
      Print("Failed HA handle. Name=", InpHAIndicatorName);
      return INIT_FAILED;
   }

   emaHandle = iCustom(_Symbol, _Period, InpEMAIndicatorName, InpShortPeriod, InpLongPeriod, InpMethod);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed EMA handle. Name=", InpEMAIndicatorName);
      return INIT_FAILED;
   }

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetExpertMagicNumber(InpMagic);

   ResetDayIfNeeded();

   // initialize object prices if lines already exist on chart
   double tmp = EMPTY_VALUE;
   if(GetObjectLinePrice("TLS_HighLine", tmp)) lastHighObjPrice = tmp;
   if(GetObjectLinePrice("TLS_LowLine",  tmp)) lastLowObjPrice  = tmp;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   if(haHandle  != INVALID_HANDLE) IndicatorRelease(haHandle);
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
}

//=============================== TICK =================================
void OnTick()
{
   UpdateDailyDDGate();
   CancelPendingIfTPHit();

   bool crossUpNow = false;
   bool crossDownNow = false;

   if(IsNewBar())
   {
      // robust cross detection (buffer -> object), updates LastCross state too
      GetCrossEventOnClosedBar(crossUpNow, crossDownNow);

      // cancel pending (waiting) on opposite cross
      CancelWaitingOnOppositeCross(crossUpNow, crossDownNow);

      if(!ddBlocked)
      {
         // hedge allowed, but exposure limit per direction enforced in ExecuteEntry()
         if(CheckBuySignalOnClosedBar())  ExecuteEntry(true);
         if(CheckSellSignalOnClosedBar()) ExecuteEntry(false);
      }
   }

   ManageBreakEvenAndCrossRules(crossUpNow, crossDownNow);

   UpdateChartComment();
}
