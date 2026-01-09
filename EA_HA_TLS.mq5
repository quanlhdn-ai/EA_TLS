//+------------------------------------------------------------------+
//|  EMA(10/39) + Heiken Ashi Breakout EA (Complete v2)              |
//|  Implements items (1) -> (11) as user spec                       |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//============================== INPUTS ==============================
// [1] Common settings 
ENUM_TIMEFRAMES TF = PERIOD_CURRENT; // dynamic timeframe
input double BufferPips               = 5.0;         // Buffer: 5 pip

// EMA to determine structure & pivot: EMA10/EMA39 theo (H+L)/2 => PRICE_MEDIAN
input int    FastEMA                  = 10;
input int    SlowEMA                  = 39;

// Risk per trade (usd)
input double RiskUSDPerTrade          = 50.0;

// [9] SL_max (pip)
input double SLMaxPips                = 50.0;

// [11] Daily Drawdown (% balance open)
input double DailyDDPercent           = 3.0;

// SL/TP management
input bool   EnableMoveToBE           = true;
input int    SlippagePoints           = 30;

// HA swing detection (auto)
input int    HASwingLookback          = 3;
input int    MaxBarsSearchSwing       = 200;

// trade identifiers
input long   MagicNumber              = 2026838627;

//============================== GLOBALS ==============================
int hFast = INVALID_HANDLE;
int hSlow = INVALID_HANDLE;

datetime lastBarTime = 0;

// [1] Swing High/Low confirmed theo logic EMA regime (SDZ)
bool   trendInitialized = false;
bool   trendUp = false;
double trackedHigh = 0.0;
double trackedLow  = 0.0;
double confirmedSwingHigh = 0.0;
double confirmedSwingLow  = 0.0;

// [9][10] Pending intent/orders for SL>SL_max scenario
bool   pendingBuy = false;
bool   pendingSell = false;
ulong  pendingBuyTicket = 0;
ulong  pendingSellTicket = 0;

// [11] Daily DD tracking
datetime dayStartTime = 0;
double   dayStartBalance = 0.0;
bool     tradingLockedToday = false;

//============================== UTILS ==============================
double PipSize()
{
   // Practical pip size:
   // 5/3 digits: pip = 10*point
   // 2 digits (many metals): pip = 10*point (0.1)
   if(_Digits == 5 || _Digits == 3 || _Digits == 2) return 10.0 * _Point;
   return _Point;
}

double NormalizePrice(double p)
{
   return NormalizeDouble(p, _Digits);
}

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

bool IsNewBar()
{
   datetime t = iTime(_Symbol, TF, 0);
   if(t == 0) return false;
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
}

bool CopyEMAs(int shift, double &emaFast, double &emaSlow)
{
   double bFast[], bSlow[];
   ArraySetAsSeries(bFast, true);
   ArraySetAsSeries(bSlow, true);

   if(CopyBuffer(hFast, 0, shift, 1, bFast) != 1) return false;
   if(CopyBuffer(hSlow, 0, shift, 1, bSlow) != 1) return false;

   emaFast = bFast[0];
   emaSlow = bSlow[0];
   return true;
}

bool SelectPositionByIndex(const int index)
{
   ulong ticket = PositionGetTicket(index);
   if(ticket == 0) return false;
   return PositionSelectByTicket(ticket);
}


//-------------------- Heiken Ashi calc --------------------
bool CalcHeikenAshi(int shift, double &haOpen, double &haHigh, double &haLow, double &haClose)
{
   const int N = 20;
   int start = shift + N;
   if(start > 500) start = shift + 50;

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
      double o = rates[i].open;
      double h = rates[i].high;
      double l = rates[i].low;
      double c = rates[i].close;

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

bool IsHAGreen(int shift)
{
   double ho, hh, hl, hc;
   if(!CalcHeikenAshi(shift, ho, hh, hl, hc)) return false;
   return (hc > ho);
}

bool IsHARed(int shift)
{
   double ho, hh, hl, hc;
   if(!CalcHeikenAshi(shift, ho, hh, hl, hc)) return false;
   return (hc < ho);
}

//-------------------- Nearest HA swing (auto fractal-like) --------------------
bool FindNearestHASwingLow(int fromShift, double &swingLow)
{
   int L = MathMax(1, HASwingLookback);
   int maxSearch = MathMax(50, MaxBarsSearchSwing);

   for(int i = fromShift + L; i < fromShift + maxSearch; i++)
   {
      double ho, hh, hl, hc;
      if(!CalcHeikenAshi(i, ho, hh, hl, hc)) break;

      bool isMin = true;
      for(int k=1; k<=L; k++)
      {
         double ho1, hh1, hl1, hc1;
         double ho2, hh2, hl2, hc2;
         if(!CalcHeikenAshi(i-k, ho1, hh1, hl1, hc1)) { isMin=false; break; }
         if(!CalcHeikenAshi(i+k, ho2, hh2, hl2, hc2)) { isMin=false; break; }
         if(!(hl < hl1 && hl < hl2)) { isMin=false; break; }
      }
      if(isMin) { swingLow = hl; return true; }
   }
   return false;
}

bool FindNearestHASwingHigh(int fromShift, double &swingHigh)
{
   int L = MathMax(1, HASwingLookback);
   int maxSearch = MathMax(50, MaxBarsSearchSwing);

   for(int i = fromShift + L; i < fromShift + maxSearch; i++)
   {
      double ho, hh, hl, hc;
      if(!CalcHeikenAshi(i, ho, hh, hl, hc)) break;

      bool isMax = true;
      for(int k=1; k<=L; k++)
      {
         double ho1, hh1, hl1, hc1;
         double ho2, hh2, hl2, hc2;
         if(!CalcHeikenAshi(i-k, ho1, hh1, hl1, hc1)) { isMax=false; break; }
         if(!CalcHeikenAshi(i+k, ho2, hh2, hl2, hc2)) { isMax=false; break; }
         if(!(hh > hh1 && hh > hh2)) { isMax=false; break; }
      }
      if(isMax) { swingHigh = hh; return true; }
   }
   return false;
}

//-------------------- Positions / Orders guard --------------------
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!SelectPositionByIndex(i)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(t == type) count++;
   }
   return count;
}

bool HasBuy()  { return CountPositions(POSITION_TYPE_BUY)  > 0; }
bool HasSell() { return CountPositions(POSITION_TYPE_SELL) > 0; }

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

//-------------------- Risk-based volume --------------------
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

//============================== [11] DAILY DD ==============================
datetime GetDayStart(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

double ClosedPLToday()
{
   // Sum P/L of closed deals today for this symbol+magic
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

      // only closed legs
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
   // Reset at new day
   datetime now = TimeCurrent();
   datetime start = GetDayStart(now);

   if(dayStartTime == 0 || start != dayStartTime)
   {
      dayStartTime = start;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      tradingLockedToday = false;
      // Clear pending on new day (optional safety)
      pendingBuy = pendingSell = false;
      DeletePending(pendingBuyTicket);
      DeletePending(pendingSellTicket);
   }

   double limit = dayStartBalance * (DailyDDPercent / 100.0);
   double pl = ClosedPLToday();

   if(pl <= -limit) tradingLockedToday = true;
}

//============================== [6] BE MANAGEMENT ==============================
void ManageBreakEven()
{
   if(!EnableMoveToBE) return;

   double pip = PipSize();
   double beTriggerOffset = BufferPips * pip;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!SelectPositionByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if(entry <= 0 || sl <= 0) continue;

      // already at BE?
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
      }
   }
}

//============================== [1] CONFIRMED SWINGS via EMA regime ==============================
void UpdateConfirmedSwingsOnNewBar()
{
   // [1] Swing High/Low: confirm by logic EMA10/39
   double f1, s1;
   if(!CopyEMAs(1, f1, s1)) return;

   bool curTrendUp = (f1 > s1);

   double h = iHigh(_Symbol, TF, 1);
   double l = iLow(_Symbol, TF, 1);

   if(!trendInitialized)
   {
      trendInitialized = true;
      trendUp = curTrendUp;
      trackedHigh = h;
      trackedLow  = l;
      return;
   }

   if(curTrendUp)
   {
      if(!trendUp)
      {
         // Down -> Up => confirm swing low
         if(trackedLow > 0) confirmedSwingLow = trackedLow;
         trackedHigh = h;
      }
      else
      {
         trackedHigh = MathMax(trackedHigh, h);
      }
   }
   else
   {
      if(trendUp)
      {
         // Up -> Down => confirm swing high
         if(trackedHigh > 0) confirmedSwingHigh = trackedHigh;
         trackedLow = l;
      }
      else
      {
         trackedLow = MathMin(trackedLow, l);
      }
   }

   trendUp = curTrendUp;
}

//============================== [7] SAFETY when opposite pivot while in trade ==============================
void ApplyOppositePivotSafety(bool pivotBuy, bool pivotSell)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!SelectPositionByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double profit= PositionGetDouble(POSITION_PROFIT);

      if(entry <= 0) continue;

      bool needAction = false;
      if(type == POSITION_TYPE_BUY  && pivotSell) needAction = true;
      if(type == POSITION_TYPE_SELL && pivotBuy)  needAction = true;
      if(!needAction) continue;

      trade.SetExpertMagicNumber(MagicNumber);

      if(profit > 0.0)
      {
         // move SL to entry (BE)
         if(MathAbs(sl - entry) > _Point*2)
            trade.PositionModify(_Symbol, entry, tp);
      }
      else if(profit < 0.0)
      {
         // set TP to entry for break-even exit on retrace
         if(MathAbs(tp - entry) > _Point*2)
            trade.PositionModify(_Symbol, sl, entry);
      }
   }
}

//============================== [10] Cancel pending intent on opposite pivot ==============================
void CancelPendingOnOppositePivot(bool pivotBuy, bool pivotSell)
{
   // [10] If a BUY setup is pending (SL > SL_max) and a SELL pivot appears, cancel the BUY setup.
   if(pivotSell && pendingBuy)
   {
      DeletePending(pendingBuyTicket);
      pendingBuy = false;
   }

   // [10] If a SELL setup is pending (SL > SL_max) and a BUY pivot appears, cancel the SELL setup.
   if(pivotBuy && pendingSell)
   {
      DeletePending(pendingSellTicket);
      pendingSell = false;
   }
}

//============================== ORDER PLACEMENT ==============================
bool PlaceMarketBuy(double sl, double tp)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double vol = CalcVolumeByRisk(ask, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   return trade.Buy(vol, _Symbol, ask, sl, tp, "BUY Market");
}

bool PlaceMarketSell(double sl, double tp)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double vol = CalcVolumeByRisk(bid, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   return trade.Sell(vol, _Symbol, bid, sl, tp, "SELL Market");
}

bool PlaceBuyLimit(double entry, double sl, double tp, ulong &outTicket)
{
   double vol = CalcVolumeByRisk(entry, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   bool ok = trade.BuyLimit(vol, NormalizePrice(entry), _Symbol, NormalizePrice(sl), NormalizePrice(tp), ORDER_TIME_GTC, 0, "BUY LIMIT SL_MAX");
   if(ok) outTicket = (ulong)trade.ResultOrder();
   return ok;
}

bool PlaceSellLimit(double entry, double sl, double tp, ulong &outTicket)
{
   double vol = CalcVolumeByRisk(entry, sl);
   if(vol <= 0) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   bool ok = trade.SellLimit(vol, NormalizePrice(entry), _Symbol, NormalizePrice(sl), NormalizePrice(tp), ORDER_TIME_GTC, 0, "SELL LIMIT SL_MAX");
   if(ok) outTicket = (ulong)trade.ResultOrder();
   return ok;
}

//============================== [3][4][5][8][9] ENTRY LOGIC ==============================
void CheckAndTradeOnNewBar()
{
   // [11] block new trades if Daily DD hit
   if(tradingLockedToday) return;

   // Evaluate on last closed bar (shift=1)
   double f1, s1, f2, s2;
   if(!CopyEMAs(1, f1, s1)) return;
   if(!CopyEMAs(2, f2, s2)) return;

   // [2] PIVOT
   bool pivotBuy  = (f2 <= s2 && f1 > s1);
   bool pivotSell = (f2 >= s2 && f1 < s1);

   // [7] SAFETY when opposite pivot while positions exist
   ApplyOppositePivotSafety(pivotBuy, pivotSell);

   // [10] CANCEL pending when opposite pivot appears
   CancelPendingOnOppositePivot(pivotBuy, pivotSell);

   // [1] Need confirmed swing reference
   double swingH = confirmedSwingHigh;
   double swingL = confirmedSwingLow;
   if(swingH <= 0 && swingL <= 0) return;

   // [3] Breakout candle confirmation: HA + normal candle color
   double haO, haH, haL, haC;
   if(!CalcHeikenAshi(1, haO, haH, haL, haC)) return;

   bool haGreen = (haC > haO);
   bool haRed   = (haC < haO);

   bool normalGreen = (iClose(_Symbol, TF, 1) > iOpen(_Symbol, TF, 1));
   bool normalRed   = (iClose(_Symbol, TF, 1) < iOpen(_Symbol, TF, 1));

   bool breakAbove = (swingH > 0 && haC > swingH);
   bool breakBelow = (swingL > 0 && haC < swingL);

   double pip = PipSize();
   double buffer = BufferPips * pip;

   // [8] Hedge allowed but no stacking: max 1 BUY + 1 SELL
   // Also: if pending exists but ticket gone, clear state
   if(pendingBuy && !PendingExists(pendingBuyTicket))  { pendingBuy=false; pendingBuyTicket=0; }
   if(pendingSell && !PendingExists(pendingSellTicket)) { pendingSell=false; pendingSellTicket=0; }

   //==================== BUY scenario ====================
   // [3] BUY: pivot BUY + breakout above swingH + normal green + HA green
   if(pivotBuy && breakAbove && normalGreen && haGreen)
   {
      // Don't stack BUY; also don't create another pending BUY if already pending
      if(!HasBuy() && !pendingBuy)
      {
         // [4] SL = nearest HA swing low - buffer
         double haSwingLow;
         if(FindNearestHASwingLow(1, haSwingLow))
         {
            double sl = NormalizePrice(haSwingLow - buffer);

            // planned "market entry" would be at new bar ask
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(ask <= 0) return;

            double distPips = MathAbs(ask - sl) / pip;

            // [9] SL_max logic
            if(distPips <= SLMaxPips + 1e-9)
            {
               // [5] TP = 2R - buffer
               double R = MathAbs(ask - sl);
               double tpDist = 2.0 * R - buffer;
               if(tpDist > pip)
               {
                  double tp = NormalizePrice(ask + tpDist);
                  PlaceMarketBuy(sl, tp);
               }
            }
            else
            {
               // [9] Entry->SL > SL_max => set entry so that entry->SL == SL_max
               // BUY: SL below, so plannedEntry = SL + SLMaxPips*pip (closer to SL, lower than current ask)
               double plannedEntry = NormalizePrice(sl + SLMaxPips * pip);

               // Only place BuyLimit if plannedEntry is below current ask (otherwise it would trigger immediately/incorrectly)
               if(plannedEntry < ask - _Point*2)
               {
                  double R = MathAbs(plannedEntry - sl);
                  double tpDist = 2.0 * R - buffer;
                  if(tpDist > pip)
                  {
                     double tp = NormalizePrice(plannedEntry + tpDist);
                     ulong tk=0;
                     if(PlaceBuyLimit(plannedEntry, sl, tp, tk))
                     {
                        pendingBuy = true;
                        pendingBuyTicket = tk;
                     }
                  }
               }
               // If plannedEntry is not below ask, we simply skip (no safe SLmax entry possible at this moment)
            }
         }
      }
   }

   //==================== SELL scenario ====================
   // [3] SELL: pivot SELL + breakout below swingL + normal red + HA red
   if(pivotSell && breakBelow && normalRed && haRed)
   {
      if(!HasSell() && !pendingSell)
      {
         // [4] SL = nearest HA swing high + buffer
         double haSwingHigh;
         if(FindNearestHASwingHigh(1, haSwingHigh))
         {
            double sl = NormalizePrice(haSwingHigh + buffer);

            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(bid <= 0) return;

            double distPips = MathAbs(bid - sl) / pip;

            // [9] SL_max logic
            if(distPips <= SLMaxPips + 1e-9)
            {
               // [5] TP = 2R - buffer
               double R = MathAbs(bid - sl);
               double tpDist = 2.0 * R - buffer;
               if(tpDist > pip)
               {
                  double tp = NormalizePrice(bid - tpDist);
                  PlaceMarketSell(sl, tp);
               }
            }
            else
            {
               // [9] Entry->SL > SL_max => planned entry so entry->SL == SL_max
               // SELL: SL above, so plannedEntry = SL - SLMaxPips*pip (closer to SL, higher than current bid)
               double plannedEntry = NormalizePrice(sl - SLMaxPips * pip);

               // Place SellLimit only if plannedEntry is above current bid
               if(plannedEntry > bid + _Point*2)
               {
                  double R = MathAbs(plannedEntry - sl);
                  double tpDist = 2.0 * R - buffer;
                  if(tpDist > pip)
                  {
                     double tp = NormalizePrice(plannedEntry - tpDist);
                     ulong tk=0;
                     if(PlaceSellLimit(plannedEntry, sl, tp, tk))
                     {
                        pendingSell = true;
                        pendingSellTicket = tk;
                     }
                  }
               }
            }
         }
      }
   }
}

//============================== MQL5 LIFECYCLE ==============================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   // [1] EMA PRICE_MEDIAN = (H+L)/2
   hFast = iMA(_Symbol, TF, FastEMA, 0, MODE_EMA, PRICE_MEDIAN);
   hSlow = iMA(_Symbol, TF, SlowEMA, 0, MODE_EMA, PRICE_MEDIAN);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE) return INIT_FAILED;

   lastBarTime = iTime(_Symbol, TF, 0);

   // init daily dd
   dayStartTime = GetDayStart(TimeCurrent());
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   tradingLockedToday = false;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
}

void OnTick()
{
   // [11] Update daily DD lock (and reset at new day)
   UpdateDailyDDLock();

   // [6] Move SL to BE when +1R(-buffer)
   ManageBreakEven();

   // Only run core logic once per new bar
   if(!IsNewBar()) return;

   // [1] Update confirmed swings based on EMA regime shifts
   UpdateConfirmedSwingsOnNewBar();

   // [3][4][5][8][9][10] Evaluate signals + trade/pending
   CheckAndTradeOnNewBar();
}
