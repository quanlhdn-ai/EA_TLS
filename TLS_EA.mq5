//+------------------------------------------------------------------+
//|                                                   TLS_IFVG.mq5  |
//|                    IFVG Zone Entry EA  v4.10                     |
//|                                                                  |
//|  STRATEGY:                                                       |
//|  - Zones AUTO-CALCULATED from session open price                 |
//|  - BUY zones  = open - spacing*1, open - spacing*2, ...         |
//|  - SELL zones = open + spacing*1, open + spacing*2, ...         |
//|  - Zones reset on each new session open                          |
//|  - Zones NEVER marked used → can trigger multiple times          |
//|                                                                  |
//|  ENTRY:                                                          |
//|  - Zone activates when price enters within ZoneActivationPips    |
//|  - IFVG appears after zone activation → enter immediately        |
//|  - Fixed lot size, NO SL / NO TP on individual orders            |
//|                                                                  |
//|  GROUP TP (checked every tick):                                  |
//|  - avgEntry = weighted average of all open positions             |
//|  - TP price = avgEntry ± TpPips                                  |
//|  - When price reaches TP price → close ALL positions             |
//|                                                                  |
//|  GROUP SL (checked every tick):                                  |
//|  - Total floating loss >= SlPercent% of account balance          |
//|  - → close ALL positions immediately                             |
//|                                                                  |
//|  POST-CLOSE:                                                     |
//|  - Zones remain valid; price re-enters zone + IFVG → re-enter   |
//+------------------------------------------------------------------+
#property copyright "TLS_IFVG EA"
#property version   "4.10"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//=========================== INPUTS =================================
// Telegram
input bool   EnableTelegram   = true;
input string TG_BotToken      = "YOUR_TOKEN";
input string TG_ChatID        = "YOUR_CHAT_ID";
input bool   TG_IncludeManual = false;

// IFVG Indicator
input string IFVGIndicatorName  = "TLS_iFVG";
input int    IFVGLookback       = 300;
input color  IFVGBuyColor       = C'13,186,186';
input color  IFVGSellColor      = C'220,50,50';
input int    IFVGAlpha          = 55;
input int    IFVGExtendBars     = 30;
input int    ForceReinitMinutes = 60;

// Display
input bool IsShowChartComment = true;

// Entry
input double FixedLotSize   = 0.01;

// Group TP
input double TpPips = 100.0;          // TP in pips from weighted average entry

// Group SL
input double SlPercent = 20.0;        // Close ALL when total floating loss >= X% of balance

// Execution
input int  SlippagePoints = 30;
input long MagicNumber    = 8386272000;

// Price Zone
input int ZoneActivationPips = 100;

// Auto Zone
input double ZoneSpacingPips = 50.0;
input int    ZoneCount       = 10;

//=========================== GLOBALS ================================
bool     buyZoneActivated      = false;
bool     sellZoneActivated     = false;
datetime lastBuyZoneHitTime    = 0;
double   lastBuyZoneHitPrice   = 0.0;
int      lastBuyZoneHitIdx     = -1;
datetime lastSellZoneHitTime   = 0;
double   lastSellZoneHitPrice  = 0.0;
int      lastSellZoneHitIdx    = -1;
datetime buyZoneActivatedTime  = 0;
datetime sellZoneActivatedTime = 0;
datetime lastReinitTime        = 0;

int ifvgHandle = INVALID_HANDLE;

double buyZones[];
double sellZones[];
bool   buyZoneHasPosition[];   // true = lệnh đang mở thuộc zone này, chưa được vào lại
bool   sellZoneHasPosition[];
int    totalBuyZones  = 0;
int    totalSellZones = 0;

datetime lastBarTime        = 0;
datetime lastBuySignalTime  = 0;
datetime lastSellSignalTime = 0;

double   currentSessionOpen     = 0.0;
datetime currentSessionOpenTime = 0;

//=========================== UTILS ==================================
double PipSize()
{
   if (_Digits == 3 || _Digits == 5)
      return 100.0 * _Point;
   return _Point;
}

double NormalizePrice(double p) { return NormalizeDouble(p, _Digits); }

double NormalizeVolume(double vol)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (vol < vmin)  vol = vmin;
   if (vol > vmax)  vol = vmax;
   vol = MathFloor(vol / vstep) * vstep;
   int digits = 2;
   double tmp = vstep;
   while (tmp < 1.0 && digits < 8) { tmp *= 10.0; digits++; }
   return NormalizeDouble(vol, digits);
}

bool IsNewBar()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if (t0 != lastBarTime) { lastBarTime = t0; return true; }
   return false;
}

string SideText(bool isBuy) { return isBuy ? "BUY" : "SELL"; }

void ForceReinitIndicators()
{
   datetime now = TimeCurrent();
   if (ForceReinitMinutes <= 0) return;
   if ((now - lastReinitTime) < (datetime)(ForceReinitMinutes * 60)) return;
   PrintFormat("[REINIT] Recreating IFVG handle after %d min", ForceReinitMinutes);
   if (ifvgHandle != INVALID_HANDLE) { IndicatorRelease(ifvgHandle); ifvgHandle = INVALID_HANDLE; }
   Sleep(200);
   ifvgHandle = iCustom(_Symbol, _Period, IFVGIndicatorName,
                        IFVGLookback, IFVGBuyColor, IFVGSellColor,
                        IFVGAlpha, IFVGExtendBars);
   if (ifvgHandle == INVALID_HANDLE)
      PrintFormat("[REINIT] FAILED!");
   else
   { lastReinitTime = now; PrintFormat("[REINIT] Done handle=%d", ifvgHandle); }
}

//=========================== GROUP POSITION HELPERS =================

int CountOpenPositions(bool isBuy)
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy  && pt == POSITION_TYPE_BUY)  count++;
      if (!isBuy && pt == POSITION_TYPE_SELL) count++;
   }
   return count;
}

// Weighted average entry of all open positions for direction
// Returns 0 if none open
double GetAverageEntry(bool isBuy)
{
   double weighted = 0.0, totalLots = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy  && pt != POSITION_TYPE_BUY)  continue;
      if (!isBuy && pt != POSITION_TYPE_SELL) continue;
      double lots = PositionGetDouble(POSITION_VOLUME);
      weighted  += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
      totalLots += lots;
   }
   return (totalLots > 0.0) ? (weighted / totalLots) : 0.0;
}

// Total floating PnL for direction (profit positive, loss negative)
double GetFloatingPnL(bool isBuy)
{
   double pnl = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy  && pt != POSITION_TYPE_BUY)  continue;
      if (!isBuy && pt != POSITION_TYPE_SELL) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

// Close all open positions for direction
void CloseAllPositions(bool isBuy, const string reason)
{
   PrintFormat("[CLOSE_ALL][%s] Reason: %s", SideText(isBuy), reason);
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy  && pt != POSITION_TYPE_BUY)  continue;
      if (!isBuy && pt != POSITION_TYPE_SELL) continue;
      if (!trade.PositionClose(tk, SlippagePoints))
         PrintFormat("[CLOSE_ALL][%s] FAIL ticket=%I64u ret=%d %s",
                     SideText(isBuy), tk,
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else
         PrintFormat("[CLOSE_ALL][%s] Closed ticket=%I64u", SideText(isBuy), tk);
   }
}

//=========================== ZONE POSITION SYNC =====================
// Mỗi tick: reset flag nếu không còn lệnh nào open thuộc direction đó.
// Vì mỗi zone chỉ có tối đa 1 lệnh, ta dùng comment lệnh để biết zone nào.
// Cách đơn giản nhất: nếu không còn lệnh BUY nào mở → reset tất cả buyZoneHasPosition
// Tương tự SELL. (Chiến lược 1 lệnh/zone, không mix nhiều zone cùng lúc.)
// Nếu muốn hỗ trợ nhiều zone đồng thời active, dùng GlobalVariable lưu zoneIdx theo ticket.
void SyncZonePositionFlags()
{
   // BUY: nếu không còn lệnh buy nào mở → mở lại tất cả zone
   if (CountOpenPositions(true) == 0)
   {
      bool anyWasLocked = false;
      for (int i = 0; i < totalBuyZones; i++)
         if (buyZoneHasPosition[i]) { buyZoneHasPosition[i] = false; anyWasLocked = true; }
      if (anyWasLocked)
         PrintFormat("[ZONE_SYNC][BUY] Tất cả lệnh BUY đã đóng → reset zone locks");
   }

   // SELL: nếu không còn lệnh sell nào mở → mở lại tất cả zone
   if (CountOpenPositions(false) == 0)
   {
      bool anyWasLocked = false;
      for (int i = 0; i < totalSellZones; i++)
         if (sellZoneHasPosition[i]) { sellZoneHasPosition[i] = false; anyWasLocked = true; }
      if (anyWasLocked)
         PrintFormat("[ZONE_SYNC][SELL] Tất cả lệnh SELL đã đóng → reset zone locks");
   }
}

//=========================== GROUP TP / SL MONITOR ==================
// Called every tick — checks both TP and SL conditions for each direction
void CheckGroupExits()
{
   // Sync zone locks trước — nếu lệnh đã đóng bên ngoài (manual/SL broker) thì unlock zone
   SyncZonePositionFlags();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slLimit = balance * (SlPercent / 100.0); // loss threshold in USD
   double pip     = PipSize();

   // ----- BUY group -----
   if (CountOpenPositions(true) > 0)
   {
      double avgEntry = GetAverageEntry(true);
      double tpPrice  = NormalizePrice(avgEntry + TpPips * pip);
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double floatPnL = GetFloatingPnL(true);

      // TP hit
      if (bid >= tpPrice)
      {
         PrintFormat("[GROUP_TP][BUY] bid=%.*f >= tpPrice=%.*f (avgEntry=%.*f + %.1fpips) | PnL=%.2f",
                     _Digits, bid, _Digits, tpPrice, _Digits, avgEntry, TpPips, floatPnL);
         TG_SendGroupClose(true, "TP", avgEntry, tpPrice, floatPnL);
         CloseAllPositions(true, "GROUP TP");
         return;
      }

      // SL hit — floating loss >= SlPercent% of balance
      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][BUY] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         TG_SendGroupClose(true, "SL", avgEntry, bid, floatPnL);
         CloseAllPositions(true, "GROUP SL");
         return;
      }
   }

   // ----- SELL group -----
   if (CountOpenPositions(false) > 0)
   {
      double avgEntry = GetAverageEntry(false);
      double tpPrice  = NormalizePrice(avgEntry - TpPips * pip);
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double floatPnL = GetFloatingPnL(false);

      // TP hit
      if (ask <= tpPrice)
      {
         PrintFormat("[GROUP_TP][SELL] ask=%.*f <= tpPrice=%.*f (avgEntry=%.*f - %.1fpips) | PnL=%.2f",
                     _Digits, ask, _Digits, tpPrice, _Digits, avgEntry, TpPips, floatPnL);
         TG_SendGroupClose(false, "TP", avgEntry, tpPrice, floatPnL);
         CloseAllPositions(false, "GROUP TP");
         return;
      }

      // SL hit
      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][SELL] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         TG_SendGroupClose(false, "SL", avgEntry, ask, floatPnL);
         CloseAllPositions(false, "GROUP SL");
         return;
      }
   }
}

//=========================== SESSION HELPERS ========================
bool GetCurrentSymbolSessionWindow(datetime now, datetime &sOut, datetime &eOut)
{
   sOut = 0; eOut = 0;
   MqlDateTime t; TimeToStruct(now, t);
   int dow = t.day_of_week;
   for (int idx = 0; idx < 10; idx++)
   {
      datetime from = 0, to = 0;
      if (!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to)) break;
      if (from == 0 && to == 0) continue;
      MqlDateTime s = t, e = t, tf, tt;
      TimeToStruct(from, tf); TimeToStruct(to, tt);
      s.hour = tf.hour; s.min = tf.min; s.sec = 0;
      e.hour = tt.hour; e.min = tt.min; e.sec = 0;
      datetime s0 = StructToTime(s), e0 = StructToTime(e);
      if (e0 <= s0) e0 += 86400;
      if (now < s0 && (e0 - s0) > 6*3600) { s0 -= 86400; e0 -= 86400; }
      if (now >= s0 && now < e0) { sOut = s0; eOut = e0; return true; }
   }
   return false;
}

//=========================== AUTO ZONE CALCULATION ==================
double GetSessionOpenPrice()
{
   datetime now = TimeCurrent(), sStart = 0, sEnd = 0;
   if (!GetCurrentSymbolSessionWindow(now, sStart, sEnd))
   {
      MqlDateTime t; TimeToStruct(now, t);
      t.hour = 0; t.min = 0; t.sec = 0;
      int idx = iBarShift(_Symbol, PERIOD_D1, StructToTime(t), false);
      if (idx >= 0) return iOpen(_Symbol, PERIOD_D1, idx);
      return 0.0;
   }
   int barIdx = iBarShift(_Symbol, _Period, sStart, false);
   if (barIdx < 0) return 0.0;
   return iOpen(_Symbol, _Period, barIdx);
}

void BuildZonesFromOpen(double openPrice)
{
   if (openPrice <= 0.0) return;
   double pip = PipSize(), spacing = ZoneSpacingPips * pip;
   int    count = MathMax(1, ZoneCount);
   ArrayResize(buyZones, count); ArrayResize(sellZones, count);
   ArrayResize(buyZoneHasPosition, count); ArrayResize(sellZoneHasPosition, count);
   ArrayFill(buyZoneHasPosition,  0, count, false);
   ArrayFill(sellZoneHasPosition, 0, count, false);
   totalBuyZones = count; totalSellZones = count;
   for (int i = 0; i < count; i++)
   {
      buyZones[i]  = NormalizePrice(openPrice - spacing * (i + 1));
      sellZones[i] = NormalizePrice(openPrice + spacing * (i + 1));
   }
   buyZoneActivated  = false; sellZoneActivated  = false;
   lastBuyZoneHitPrice  = 0.0; lastBuyZoneHitIdx  = -1;
   lastSellZoneHitPrice = 0.0; lastSellZoneHitIdx = -1;
   buyZoneActivatedTime = 0;   sellZoneActivatedTime = 0;
   PrintFormat("[ZONE_AUTO] Built %d BUY + %d SELL from Open=%.*f (spacing=%.1f pip)",
               count, count, _Digits, openPrice, ZoneSpacingPips);
   for (int i = 0; i < count; i++)
      PrintFormat("[ZONE_AUTO]  BUY[%d]=%.*f  SELL[%d]=%.*f",
                  i+1, _Digits, buyZones[i], i+1, _Digits, sellZones[i]);
}

void CheckAndUpdateSessionZones()
{
   datetime now = TimeCurrent(), sStart = 0, sEnd = 0;
   if (!GetCurrentSymbolSessionWindow(now, sStart, sEnd)) return;
   if (sStart != currentSessionOpenTime)
   {
      PrintFormat("[ZONE_AUTO] NEW SESSION prev=%s → new=%s",
                  TimeToString(currentSessionOpenTime, TIME_DATE|TIME_MINUTES),
                  TimeToString(sStart, TIME_DATE|TIME_MINUTES));
      currentSessionOpenTime = sStart;
      double op = GetSessionOpenPrice();
      if (op > 0.0) { currentSessionOpen = op; BuildZonesFromOpen(op); }
      else PrintFormat("[ZONE_AUTO] WARN: Could not get session open!");
   }
}

//=========================== ZONE ACTIVATION ========================
void UpdateZoneActivation()
{
   datetime now = TimeCurrent();
   double pip = PipSize(), threshold = ZoneActivationPips * pip;

   // ----- BUY -----
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double nearZone = 0.0; int nearIdx = -1; double minD = DBL_MAX;
      for (int i = 0; i < totalBuyZones; i++)
      {
         double d = MathAbs(bid - buyZones[i]);
         if (d <= threshold && d < minD) { minD = d; nearZone = buyZones[i]; nearIdx = i; }
      }
      if (nearIdx >= 0)
      {
         if (!buyZoneActivated)
         {
            buyZoneActivated = true; lastBuyZoneHitPrice = nearZone;
            lastBuyZoneHitIdx = nearIdx; lastBuyZoneHitTime = now;
            buyZoneActivatedTime = iTime(_Symbol, _Period, 0);
            PrintFormat("[ZONE][BUY] ACTIVATED Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
         }
         else if (nearIdx != lastBuyZoneHitIdx)
         {
            lastBuyZoneHitPrice = nearZone; lastBuyZoneHitIdx = nearIdx;
            lastBuyZoneHitTime = now; buyZoneActivatedTime = iTime(_Symbol, _Period, 0);
            PrintFormat("[ZONE][BUY] SWITCH → Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
         }
      }
   }

   // ----- SELL -----
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double nearZone = 0.0; int nearIdx = -1; double minD = DBL_MAX;
      for (int i = 0; i < totalSellZones; i++)
      {
         double d = MathAbs(ask - sellZones[i]);
         if (d <= threshold && d < minD) { minD = d; nearZone = sellZones[i]; nearIdx = i; }
      }
      if (nearIdx >= 0)
      {
         if (!sellZoneActivated)
         {
            sellZoneActivated = true; lastSellZoneHitPrice = nearZone;
            lastSellZoneHitIdx = nearIdx; lastSellZoneHitTime = now;
            sellZoneActivatedTime = iTime(_Symbol, _Period, 0);
            PrintFormat("[ZONE][SELL] ACTIVATED Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
         }
         else if (nearIdx != lastSellZoneHitIdx)
         {
            lastSellZoneHitPrice = nearZone; lastSellZoneHitIdx = nearIdx;
            lastSellZoneHitTime = now; sellZoneActivatedTime = iTime(_Symbol, _Period, 0);
            PrintFormat("[ZONE][SELL] SWITCH → Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
         }
      }
   }
}

//=========================== EXECUTE ENTRY ==========================
bool ExecuteEntry(bool isBuy)
{
   double lots = NormalizeVolume(FixedLotSize);
   if (lots <= 0.0) { PrintFormat("[SKIP][%s] lots=0", SideText(isBuy)); return false; }

   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entry = NormalizePrice(entry);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   // Open order WITHOUT SL and TP (0.0 = no SL/TP)
   bool ok = isBuy ? trade.Buy(lots,  _Symbol, 0.0, 0.0, 0.0, "IFVG BUY")
                   : trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, "IFVG SELL");

   if (ok)
   {
      double filled = trade.ResultPrice();

      // Compute new average entry for display
      double weighted = filled * lots, totalL = lots;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if (!PositionSelectByTicket(tk)) continue;
         if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if (isBuy  && pt != POSITION_TYPE_BUY)  continue;
         if (!isBuy && pt != POSITION_TYPE_SELL) continue;
         if (PositionGetDouble(POSITION_PRICE_OPEN) == filled && PositionGetDouble(POSITION_VOLUME) == lots) continue; // skip just-opened
         double pl = PositionGetDouble(POSITION_VOLUME);
         weighted += PositionGetDouble(POSITION_PRICE_OPEN) * pl;
         totalL   += pl;
      }
      double avgEntry = weighted / totalL;
      double pip      = PipSize();
      double tpPrice  = isBuy ? NormalizePrice(avgEntry + TpPips * pip)
                              : NormalizePrice(avgEntry - TpPips * pip);

      PrintFormat("[ORDER][%s] Filled=%.*f Lots=%.2f | AvgEntry=%.*f | GroupTP=%.*f (%.1f pip) | Positions=%d",
                  SideText(isBuy), _Digits, filled, lots,
                  _Digits, avgEntry, _Digits, tpPrice, TpPips,
                  CountOpenPositions(isBuy));

      TG_SendOpenMarket(isBuy, filled, avgEntry, tpPrice, (long)trade.ResultDeal());
   }
   else
   {
      PrintFormat("[FAIL][%s] ret=%d %s", SideText(isBuy),
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   return ok;
}

//=========================== IFVG SIGNAL CHECK ======================
void CheckIFVGSignals()
{
   if (ifvgHandle == INVALID_HANDLE) return;
   int scanBars = MathMin(IFVGLookback, Bars(_Symbol, _Period) - 1);
   if (scanBars <= 0) return;

   double buyTop[], buyBot[], sellTop[], sellBot[], invTime[];
   if (CopyBuffer(ifvgHandle, 0, 1, scanBars, buyTop)  != scanBars) { PrintFormat("[IFVG][WARN] buf0"); return; }
   if (CopyBuffer(ifvgHandle, 1, 1, scanBars, buyBot)  != scanBars) { PrintFormat("[IFVG][WARN] buf1"); return; }
   if (CopyBuffer(ifvgHandle, 2, 1, scanBars, sellTop) != scanBars) { PrintFormat("[IFVG][WARN] buf2"); return; }
   if (CopyBuffer(ifvgHandle, 3, 1, scanBars, sellBot) != scanBars) { PrintFormat("[IFVG][WARN] buf3"); return; }
   if (CopyBuffer(ifvgHandle, 4, 1, scanBars, invTime) != scanBars) { PrintFormat("[IFVG][WARN] buf4"); return; }

   MqlRates rates[];
   if (CopyRates(_Symbol, _Period, 1, scanBars, rates) != scanBars) { PrintFormat("[IFVG][WARN] rates"); return; }

   // ----- BUY -----
   PrintFormat("[IFVG][BUY] ZoneActive=%s activatedTime=%s lastSignal=%s",
               buyZoneActivated?"YES":"NO",
               TimeToString(buyZoneActivatedTime, TIME_DATE|TIME_MINUTES),
               TimeToString(lastBuySignalTime, TIME_DATE|TIME_MINUTES));

   if (buyZoneActivated && lastBuyZoneHitIdx >= 0 && lastBuyZoneHitIdx < totalBuyZones)
   {
      // Skip nếu zone đang có lệnh mở
      if (buyZoneHasPosition[lastBuyZoneHitIdx])
      {
         PrintFormat("[IFVG][BUY] SKIP: zone idx=%d đang có lệnh mở, chờ đóng mới vào lại",
                     lastBuyZoneHitIdx);
      }
      else
      {
      bool found = false;
      for (int i = 0; i < scanBars && !found; i++)
      {
         if (!MathIsValidNumber(buyTop[i]) || buyTop[i] <= 0.0 || buyTop[i] >= 1e10) continue;
         datetime invBarTime = (datetime)invTime[i];
         if (invBarTime <= 0) continue;
         datetime barTime = iTime(_Symbol, _Period, i + 1);
         if (barTime == lastBuySignalTime)    { PrintFormat("[IFVG][BUY] bar=%d SKIP already fired", i+1); continue; }
         if (invBarTime < buyZoneActivatedTime) { PrintFormat("[IFVG][BUY] bar=%d SKIP invTime before activation", i+1); continue; }
         if (rates[i].close <= buyTop[i])     { PrintFormat("[IFVG][BUY] bar=%d SKIP close not above top", i+1); continue; }
         PrintFormat("[IFVG][BUY] bar=%d PASS close=%.*f > top=%.*f | invTime=%s",
                     i+1, _Digits, rates[i].close, _Digits, buyTop[i],
                     TimeToString(invBarTime, TIME_DATE|TIME_MINUTES));
         lastBuySignalTime = barTime;
         if (ExecuteEntry(true))
            buyZoneHasPosition[lastBuyZoneHitIdx] = true;
         found = true;
      }
      if (!found) PrintFormat("[IFVG][BUY] No valid signal in %d bars", scanBars);
      }
   }

   // ----- SELL -----
   PrintFormat("[IFVG][SELL] ZoneActive=%s activatedTime=%s lastSignal=%s",
               sellZoneActivated?"YES":"NO",
               TimeToString(sellZoneActivatedTime, TIME_DATE|TIME_MINUTES),
               TimeToString(lastSellSignalTime, TIME_DATE|TIME_MINUTES));

   if (sellZoneActivated && lastSellZoneHitIdx >= 0 && lastSellZoneHitIdx < totalSellZones)
   {
      // Skip nếu zone đang có lệnh mở
      if (sellZoneHasPosition[lastSellZoneHitIdx])
      {
         PrintFormat("[IFVG][SELL] SKIP: zone idx=%d đang có lệnh mở, chờ đóng mới vào lại",
                     lastSellZoneHitIdx);
      }
      else
      {
      bool found = false;
      for (int i = 0; i < scanBars && !found; i++)
      {
         if (!MathIsValidNumber(sellTop[i]) || sellTop[i] <= 0.0 || sellTop[i] >= 1e10) continue;
         datetime invBarTime = (datetime)invTime[i];
         if (invBarTime <= 0) continue;
         datetime barTime = iTime(_Symbol, _Period, i + 1);
         if (barTime == lastSellSignalTime)    { PrintFormat("[IFVG][SELL] bar=%d SKIP already fired", i+1); continue; }
         if (invBarTime < sellZoneActivatedTime) { PrintFormat("[IFVG][SELL] bar=%d SKIP invTime before activation", i+1); continue; }
         if (rates[i].close >= sellBot[i])     { PrintFormat("[IFVG][SELL] bar=%d SKIP close not below bot", i+1); continue; }
         PrintFormat("[IFVG][SELL] bar=%d PASS close=%.*f < bot=%.*f | invTime=%s",
                     i+1, _Digits, rates[i].close, _Digits, sellBot[i],
                     TimeToString(invBarTime, TIME_DATE|TIME_MINUTES));
         lastSellSignalTime = barTime;
         if (ExecuteEntry(false))
            sellZoneHasPosition[lastSellZoneHitIdx] = true;
         found = true;
      }
      if (!found) PrintFormat("[IFVG][SELL] No valid signal in %d bars", scanBars);
      }
   }
}

//=========================== CHART COMMENT ==========================
void UpdateChartComment()
{
   if (!IsShowChartComment) { Comment(""); return; }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slLimit = balance * (SlPercent / 100.0);
   double pip     = PipSize();

   string txt = "";
   txt += "IFVG Handle  : " + (ifvgHandle != INVALID_HANDLE ? "OK" : "FAIL") + "\n";
   txt += "Balance      : " + DoubleToString(balance, 2) + "\n";
   txt += "SL Limit     : -" + DoubleToString(slLimit, 2) +
          " (" + DoubleToString(SlPercent, 1) + "% of balance)\n";
   txt += "--------------------------------------------\n";
   txt += "Session Open : " + DoubleToString(currentSessionOpen, _Digits) +
          " @ " + TimeToString(currentSessionOpenTime, TIME_DATE|TIME_MINUTES) + "\n";
   txt += "Lot Size     : " + DoubleToString(FixedLotSize, 2) + " (fixed, no SL/TP on orders)\n";
   txt += "TP Pips      : " + DoubleToString(TpPips, 1) + " pip from avg entry\n";
   txt += "--------------------------------------------\n";

   // BUY group
   int buyCount = CountOpenPositions(true);
   txt += "Open BUY     : " + IntegerToString(buyCount) + " positions\n";
   if (buyCount > 0)
   {
      double avg    = GetAverageEntry(true);
      double tpP    = NormalizePrice(avg + TpPips * pip);
      double fPnL   = GetFloatingPnL(true);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      txt += "  AvgEntry  : " + DoubleToString(avg, _Digits) + "\n";
      txt += "  GroupTP   : " + DoubleToString(tpP, _Digits) +
             " (" + DoubleToString((tpP - bid) / pip, 1) + " pip away)\n";
      txt += "  FloatPnL  : " + DoubleToString(fPnL, 2) + "\n";
   }

   // SELL group
   int sellCount = CountOpenPositions(false);
   txt += "Open SELL    : " + IntegerToString(sellCount) + " positions\n";
   if (sellCount > 0)
   {
      double avg   = GetAverageEntry(false);
      double tpP   = NormalizePrice(avg - TpPips * pip);
      double fPnL  = GetFloatingPnL(false);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      txt += "  AvgEntry  : " + DoubleToString(avg, _Digits) + "\n";
      txt += "  GroupTP   : " + DoubleToString(tpP, _Digits) +
             " (" + DoubleToString((ask - tpP) / pip, 1) + " pip away)\n";
      txt += "  FloatPnL  : " + DoubleToString(fPnL, 2) + "\n";
   }

   txt += "--------------------------------------------\n";
   txt += "BuyZone  : " + (buyZoneActivated  ? "ACTIVE" : "waiting") + "\n";
   if (buyZoneActivated  && lastBuyZoneHitPrice  > 0)
      txt += "  └─ " + DoubleToString(lastBuyZoneHitPrice,  _Digits) +
             " (idx=" + IntegerToString(lastBuyZoneHitIdx)  + ")\n";
   txt += "SellZone : " + (sellZoneActivated ? "ACTIVE" : "waiting") + "\n";
   if (sellZoneActivated && lastSellZoneHitPrice > 0)
      txt += "  └─ " + DoubleToString(lastSellZoneHitPrice, _Digits) +
             " (idx=" + IntegerToString(lastSellZoneHitIdx) + ")\n";
   txt += "--------------------------------------------\n";

   for (int i = 0; i < totalBuyZones; i++)
      txt += "  [BUY " + IntegerToString(i+1) + "] " +
             DoubleToString(buyZones[i], _Digits) + " ±" + IntegerToString(ZoneActivationPips) + "pip" +
             (buyZoneActivated && lastBuyZoneHitIdx==i ? " <<ACTIVE" : "") +
             (buyZoneHasPosition[i] ? " [LOCKED]" : "") + "\n";
   for (int i = 0; i < totalSellZones; i++)
      txt += "  [SEL " + IntegerToString(i+1) + "] " +
             DoubleToString(sellZones[i], _Digits) + " ±" + IntegerToString(ZoneActivationPips) + "pip" +
             (sellZoneActivated && lastSellZoneHitIdx==i ? " <<ACTIVE" : "") +
             (sellZoneHasPosition[i] ? " [LOCKED]" : "") + "\n";

   Comment(txt);
}

//=========================== TELEGRAM ===============================
string TG_UrlEncode(const string s)
{
   uchar a[]; StringToCharArray(s, a, 0, WHOLE_ARRAY, CP_UTF8);
   string o = "";
   for (int i = 0; i < ArraySize(a); i++)
   {
      int c = (int)a[i];
      if ((c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='-'||c=='_'||c=='.'||c=='~')
         o += CharToString((ushort)c);
      else if (c==' ')  o += "%20";
      else if (c=='\n') o += "%0A";
      else o += StringFormat("%%%02X", c);
   }
   return o;
}

void TG_Send(const string msg)
{
   if (!EnableTelegram) return;
   if (StringLen(TG_BotToken)<10 || StringLen(TG_ChatID)<3) return;
   string url  = "https://api.telegram.org/bot" + TG_BotToken + "/sendMessage";
   string body = "chat_id=" + TG_UrlEncode(TG_ChatID) + "&text=" + TG_UrlEncode(msg);
   uchar data[], result[]; string rh;
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, data, result, rh);
}

string TG_Key(const string kind, long id)
{ return "TLS_IFVG_TG_" + _Symbol + "_" + (string)(int)_Period + "_" + kind + "_" + (string)id; }
bool TG_Sent(const string kind, long id) { return GlobalVariableCheck(TG_Key(kind, id)); }
void TG_Mark(const string kind, long id) { GlobalVariableSet(TG_Key(kind, id), (double)TimeCurrent()); }
string TG_P(double v) { return DoubleToString(v, _Digits); }

bool TG_SelectDealSafe(ulong dealId)
{
   for (int i = 0; i < 10; i++)
   {
      HistorySelect(TimeCurrent()-86400*30, TimeCurrent());
      if (HistoryDealSelect(dealId)) return true;
      Sleep(50);
   }
   return false;
}

void TG_SendOpenMarket(bool isBuy, double filled, double avgEntry, double groupTP, long uid)
{
   if (TG_Sent("OPEN", uid)) return;
   string dir = isBuy ? "🟢 BUY" : "🔴 SELL";
   TG_Send(dir + " ENTRY"
           + "\nFilled   : " + TG_P(filled)
           + "\nAvgEntry : " + TG_P(avgEntry)
           + "\nGroupTP  : " + TG_P(groupTP)
           + " (" + DoubleToString(TpPips, 1) + " pip)");
   TG_Mark("OPEN", uid);
}

// Unique key for group close uses timestamp so it can fire multiple times
void TG_SendGroupClose(bool isBuy, const string reason,
                       double avgEntry, double closePrice, double pnl)
{
   string dir = isBuy ? "BUY" : "SELL";
   string emoji = (pnl >= 0.0) ? "✅" : "❌";
   TG_Send(emoji + " GROUP " + reason + " | " + dir
           + "\nAvgEntry   : " + TG_P(avgEntry)
           + "\nClosePrice : " + TG_P(closePrice)
           + "\nPnL        : " + DoubleToString(pnl, 2));
}

//=========================== TRADE TRANSACTION ======================
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest     &r,
                        const MqlTradeResult      &res)
{
   if (t.symbol != _Symbol)                    return;
   if (t.type   != TRADE_TRANSACTION_DEAL_ADD) return;
   if (t.deal   == 0)                          return;
   if (!TG_SelectDealSafe(t.deal))             return;
   if (HistoryDealGetString(t.deal, DEAL_SYMBOL) != _Symbol) return;
   long magic = (long)HistoryDealGetInteger(t.deal, DEAL_MAGIC);
   if (!TG_IncludeManual && magic != MagicNumber) return;
   // Group close notifications handled in CheckGroupExits() before closing
}

//=========================== INIT / DEINIT ==========================
int OnInit()
{
   ifvgHandle = iCustom(_Symbol, _Period, IFVGIndicatorName,
                        IFVGLookback, IFVGBuyColor, IFVGSellColor,
                        IFVGAlpha, IFVGExtendBars);
   if (ifvgHandle == INVALID_HANDLE)
   {
      PrintFormat("[INIT] FAILED to load '%s' err=%d", IFVGIndicatorName, GetLastError());
      return INIT_FAILED;
   }
   PrintFormat("[INIT] handle=%d | Lot=%.2f | TpPips=%.1f | SlPercent=%.1f%%",
               ifvgHandle, FixedLotSize, TpPips, SlPercent);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   currentSessionOpen = 0.0; currentSessionOpenTime = 0;
   totalBuyZones = 0; totalSellZones = 0;
   buyZoneActivated  = false; sellZoneActivated  = false;
   lastBuyZoneHitPrice  = 0.0; lastBuyZoneHitIdx  = -1;
   lastSellZoneHitPrice = 0.0; lastSellZoneHitIdx = -1;
   buyZoneActivatedTime = 0;   sellZoneActivatedTime = 0;

   CheckAndUpdateSessionZones();

   lastBuySignalTime  = iTime(_Symbol, _Period, 1);
   lastSellSignalTime = iTime(_Symbol, _Period, 1);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   if (ifvgHandle != INVALID_HANDLE) IndicatorRelease(ifvgHandle);
}

//=========================== TICK ===================================
void OnTick()
{
   CheckAndUpdateSessionZones();
   ForceReinitIndicators();
   UpdateZoneActivation();
   CheckGroupExits();      // <-- every tick: monitor group TP and group SL

   if (!IsNewBar()) return;
   UpdateChartComment();
   CheckIFVGSignals();
}