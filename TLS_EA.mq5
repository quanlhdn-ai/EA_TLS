#property copyright "TLS_IFVG EA"
#property version "4.12"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//=========================== INPUTS =================================
// IFVG Indicator
input string IFVGIndicatorName = "TLS_iFVG";
input int IFVGLookback = 50;
input color IFVGBuyColor = C'13,186,186';
input color IFVGSellColor = C'220,50,50';
input int IFVGAlpha = 55;
input int IFVGExtendBars = 30;
input int IFVGDisplacement = 3;
input int IFVGAtrPeriod = 20;

// Display
input bool IsShowChartComment = true;

// Entry
input double FixedLotSize = 0.01;

// Group TP
input double TpPips = 5.0;  // TP tính theo pip
input double SLPips = 50.0; // SL tính theo pip

// Group SL
input double SlPercent = 10.0; // Close ALL when total floating loss >= X% of balance

// Execution
input int SlippagePoints = 30;
input long MagicNumber = 8386272000;

// Price Zone
input int ZoneActivationPips = 100;

// Auto Zone
input double ZoneSpacingPips = 250.0;
input int ZoneCount = 5;

//=========================== GLOBALS ================================
bool buyZoneActivated = false;
bool sellZoneActivated = false;
datetime lastBuyZoneHitTime = 0;
double lastBuyZoneHitPrice = 0.0;
int lastBuyZoneHitIdx = -1;
datetime lastSellZoneHitTime = 0;
double lastSellZoneHitPrice = 0.0;
int lastSellZoneHitIdx = -1;
datetime buyZoneActivatedTime = 0;
datetime sellZoneActivatedTime = 0;
datetime lastSellZoneActivatedTime = 0;
datetime lastBuyZoneActivatedTime = 0;
double lastSellIFVGBottom = 0.0;
double lastBuyIFVGTop = 0.0;

int ifvgHandle = INVALID_HANDLE;

double buyZones[];
double sellZones[];
bool buyZoneHasPosition[];
bool sellZoneHasPosition[];
int totalBuyZones = 0;
int totalSellZones = 0;

datetime lastBarTime = 0;
datetime lastBuySignalTime = 0;
datetime lastSellSignalTime = 0;

double currentSessionOpen = 0.0;
datetime currentSessionOpenTime = 0;
double originalBuyZone1 = 0.0;
double originalSellZone1 = 0.0;
string GV_PREFIX = "TLS_EA_"; 

//=========================== UTILS ==================================
void SaveZoneState()
{
   GlobalVariableSet(GV_PREFIX + "totalBuy", totalBuyZones);
   GlobalVariableSet(GV_PREFIX + "totalSell", totalSellZones);
   for (int i = 0; i < totalBuyZones; i++)
      GlobalVariableSet(GV_PREFIX + "buy_" + IntegerToString(i), buyZones[i]);
   for (int i = 0; i < totalSellZones; i++)
      GlobalVariableSet(GV_PREFIX + "sell_" + IntegerToString(i), sellZones[i]);
}

bool LoadZoneState()
{
   double totalBuy = 0, totalSell = 0;
   if (!GlobalVariableGet(GV_PREFIX + "totalBuy", totalBuy)) return false;
   if (!GlobalVariableGet(GV_PREFIX + "totalSell", totalSell)) return false;
   if (totalBuy <= 0 || totalSell <= 0) return false;

   int nBuy = (int)totalBuy;
   int nSell = (int)totalSell;

   ArrayResize(buyZones, nBuy);
   ArrayResize(sellZones, nSell);
   ArrayResize(buyZoneHasPosition, nBuy);
   ArrayResize(sellZoneHasPosition, nSell);
   ArrayFill(buyZoneHasPosition, 0, nBuy, false);
   ArrayFill(sellZoneHasPosition, 0, nSell, false);
   totalBuyZones = nBuy;
   totalSellZones = nSell;

   for (int i = 0; i < nBuy; i++)
   {
      double v = 0;
      if (!GlobalVariableGet(GV_PREFIX + "buy_" + IntegerToString(i), v)) return false;
      buyZones[i] = v;
   }
   for (int i = 0; i < nSell; i++)
   {
      double v = 0;
      if (!GlobalVariableGet(GV_PREFIX + "sell_" + IntegerToString(i), v)) return false;
      sellZones[i] = v;
   }

   originalBuyZone1 = buyZones[0];
   originalSellZone1 = sellZones[0];

   PrintFormat("[ZONE_RESTORE] Loaded %d BUY + %d SELL zones", nBuy, nSell);
   for (int i = 0; i < nBuy; i++)
      PrintFormat("[ZONE_RESTORE]  BUY[%d]=%.*f", i+1, _Digits, buyZones[i]);
   for (int i = 0; i < nSell; i++)
      PrintFormat("[ZONE_RESTORE]  SELL[%d]=%.*f", i+1, _Digits, sellZones[i]);

   return true;
}

double PipSize()
{
   if (_Digits == 3 || _Digits == 5)
      return 100.0 * _Point;
   return _Point;
}

double NormalizePrice(double p) { return NormalizeDouble(p, _Digits); }

double NormalizeVolume(double vol)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (vol < vmin)
      vol = vmin;
   if (vol > vmax)
      vol = vmax;
   vol = MathFloor(vol / vstep) * vstep;
   int digits = 2;
   double tmp = vstep;
   while (tmp < 1.0 && digits < 8)
   {
      tmp *= 10.0;
      digits++;
   }
   return NormalizeDouble(vol, digits);
}

bool IsNewBar()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if (t0 != lastBarTime)
   {
      lastBarTime = t0;
      return true;
   }
   return false;
}

string SideText(bool isBuy) { return isBuy ? "BUY" : "SELL"; }

double CalcTpUSD()
{
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0.0)
      return 0.0;
   double pipVal = tickVal / tickSize * PipSize();
   return FixedLotSize * pipVal * TpPips;
}

//=========================== GROUP POSITION HELPERS =================

int CountOpenPositions(bool isBuy)
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy && pt == POSITION_TYPE_BUY)
         count++;
      if (!isBuy && pt == POSITION_TYPE_SELL)
         count++;
   }
   return count;
}

double GetAverageEntry(bool isBuy)
{
   double weighted = 0.0, totalLots = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy && pt != POSITION_TYPE_BUY)
         continue;
      if (!isBuy && pt != POSITION_TYPE_SELL)
         continue;
      double lots = PositionGetDouble(POSITION_VOLUME);
      weighted += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
      totalLots += lots;
   }
   return (totalLots > 0.0) ? (weighted / totalLots) : 0.0;
}

double GetFloatingPnL(bool isBuy)
{
   double pnl = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy && pt != POSITION_TYPE_BUY)
         continue;
      if (!isBuy && pt != POSITION_TYPE_SELL)
         continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

void CloseAllPositions(bool isBuy, const string reason)
{
   PrintFormat("[CLOSE_ALL][%s] Reason: %s", SideText(isBuy), reason);
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (isBuy && pt != POSITION_TYPE_BUY)
         continue;
      if (!isBuy && pt != POSITION_TYPE_SELL)
         continue;
      if (!trade.PositionClose(tk, SlippagePoints))
         PrintFormat("[CLOSE_ALL][%s] FAIL ticket=%I64u ret=%d %s",
                     SideText(isBuy), tk,
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else
         PrintFormat("[CLOSE_ALL][%s] Closed ticket=%I64u", SideText(isBuy), tk);
   }
}

//=========================== ZONE POSITION SYNC =====================
void SyncZonePositionFlags()
{
   if (CountOpenPositions(true) == 0)
   {
      bool anyWasLocked = false;
      for (int i = 0; i < totalBuyZones; i++)
         if (buyZoneHasPosition[i])
         {
            buyZoneHasPosition[i] = false;
            anyWasLocked = true;
         }
      if (anyWasLocked)
         PrintFormat("[ZONE_SYNC][BUY] Tất cả lệnh BUY đã đóng → reset zone locks");
   }

   if (CountOpenPositions(false) == 0)
   {
      bool anyWasLocked = false;
      for (int i = 0; i < totalSellZones; i++)
         if (sellZoneHasPosition[i])
         {
            sellZoneHasPosition[i] = false;
            anyWasLocked = true;
         }
      if (anyWasLocked)
         PrintFormat("[ZONE_SYNC][SELL] Tất cả lệnh SELL đã đóng → reset zone locks");
   }
}

//=========================== GROUP TP / SL MONITOR ==================
void CheckGroupExits()
{
   SyncZonePositionFlags();

   if (SLPips > 0.0)
   {
      double tpUSD = CalcTpUSD();

      if (CountOpenPositions(true) > 0)
      {
         double floatPnL = GetFloatingPnL(true);
         double avgEntry = GetAverageEntry(true);
         if (floatPnL >= tpUSD)
         {
            PrintFormat("[GROUP_TP][BUY] PnL=%.2f >= TpUSD=%.2f | AvgEntry=%.*f",
                        floatPnL, tpUSD, _Digits, avgEntry);
            CloseAllPositions(true, "GROUP TP");
            lastBuySignalTime = iTime(_Symbol, _Period, 0);
            buyZoneActivated = false;
            return;
         }
      }

      if (CountOpenPositions(false) > 0)
      {
         double floatPnL = GetFloatingPnL(false);
         double avgEntry = GetAverageEntry(false);
         if (floatPnL >= tpUSD)
         {
            PrintFormat("[GROUP_TP][SELL] PnL=%.2f >= TpUSD=%.2f | AvgEntry=%.*f",
                        floatPnL, tpUSD, _Digits, avgEntry);
            CloseAllPositions(false, "GROUP TP");
            lastSellSignalTime = iTime(_Symbol, _Period, 0);
            sellZoneActivated = false;
            return;
         }
      }
      return;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slLimit = balance * (SlPercent / 100.0);
   double tpUSD = CalcTpUSD();

   // ----- BUY group -----
   if (CountOpenPositions(true) > 0)
   {
      double floatPnL = GetFloatingPnL(true);
      double avgEntry = GetAverageEntry(true);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if (floatPnL >= tpUSD)
      {
         PrintFormat("[GROUP_TP][BUY] PnL=%.2f >= TpUSD=%.2f (%.2flot × %.1fpip) | AvgEntry=%.*f",
                     floatPnL, tpUSD, FixedLotSize, TpPips, _Digits, avgEntry);
         CloseAllPositions(true, "GROUP TP");
         lastBuySignalTime = iTime(_Symbol, _Period, 0);
         buyZoneActivated = false;
         return;
      }

      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][BUY] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         CloseAllPositions(true, "GROUP SL");
         lastBuySignalTime = iTime(_Symbol, _Period, 0);
         buyZoneActivated = false;
         return;
      }
   }

   // ----- SELL group -----
   if (CountOpenPositions(false) > 0)
   {
      double floatPnL = GetFloatingPnL(false);
      double avgEntry = GetAverageEntry(false);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if (floatPnL >= tpUSD)
      {
         PrintFormat("[GROUP_TP][SELL] PnL=%.2f >= TpUSD=%.2f (%.2flot × %.1fpip) | AvgEntry=%.*f",
                     floatPnL, tpUSD, FixedLotSize, TpPips, _Digits, avgEntry);
         CloseAllPositions(false, "GROUP TP");
         lastSellSignalTime = iTime(_Symbol, _Period, 0);
         sellZoneActivated = false;
         return;
      }

      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][SELL] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         CloseAllPositions(false, "GROUP SL");
         lastSellSignalTime = iTime(_Symbol, _Period, 0);
         sellZoneActivated = false;
         return;
      }
   }
}

//=========================== SESSION HELPERS ========================
bool GetCurrentSymbolSessionWindow(datetime now, datetime &sOut, datetime &eOut)
{
   sOut = 0;
   eOut = 0;
   MqlDateTime t;
   TimeToStruct(now, t);
   int dow = t.day_of_week;
   for (int idx = 0; idx < 10; idx++)
   {
      datetime from = 0, to = 0;
      if (!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to))
         break;
      if (from == 0 && to == 0)
         continue;
      MqlDateTime s = t, e = t, tf, tt;
      TimeToStruct(from, tf);
      TimeToStruct(to, tt);
      s.hour = tf.hour;
      s.min = tf.min;
      s.sec = 0;
      e.hour = tt.hour;
      e.min = tt.min;
      e.sec = 0;
      datetime s0 = StructToTime(s), e0 = StructToTime(e);
      if (e0 <= s0)
         e0 += 86400;
      if (now < s0 && (e0 - s0) > 6 * 3600)
      {
         s0 -= 86400;
         e0 -= 86400;
      }
      if (now >= s0 && now < e0)
      {
         sOut = s0;
         eOut = e0;
         return true;
      }
   }
   return false;
}

//=========================== AUTO ZONE CALCULATION ==================
double GetSessionOpenPrice()
{
   datetime now = TimeCurrent(), sStart = 0, sEnd = 0;
   if (!GetCurrentSymbolSessionWindow(now, sStart, sEnd))
   {
      MqlDateTime t;
      TimeToStruct(now, t);
      t.hour = 0;
      t.min = 0;
      t.sec = 0;
      int idx = iBarShift(_Symbol, PERIOD_D1, StructToTime(t), false);
      if (idx >= 0)
         return iOpen(_Symbol, PERIOD_D1, idx);
      return 0.0;
   }
   int barIdx = iBarShift(_Symbol, _Period, sStart, false);
   if (barIdx < 0)
      return 0.0;
   return iOpen(_Symbol, _Period, barIdx);
}

void BuildZonesFromOpen(double openPrice)
{
   if (openPrice <= 0.0)
      return;
   double pip = PipSize(), spacing = ZoneSpacingPips * pip;
   int count = MathMax(1, ZoneCount);
   ArrayResize(buyZones, count);
   ArrayResize(sellZones, count);
   ArrayResize(buyZoneHasPosition, count);
   ArrayResize(sellZoneHasPosition, count);
   ArrayFill(buyZoneHasPosition, 0, count, false);
   ArrayFill(sellZoneHasPosition, 0, count, false);
   totalBuyZones = count;
   totalSellZones = count;
   for (int i = 0; i < count; i++)
   {
      buyZones[i] = NormalizePrice(openPrice - spacing * (i + 1));
      sellZones[i] = NormalizePrice(openPrice + spacing * (i + 1));
   }

   buyZoneActivated = false;
   sellZoneActivated = false;
   lastBuyZoneHitPrice = 0.0;
   lastBuyZoneHitIdx = -1;
   lastSellZoneHitPrice = 0.0;
   lastSellZoneHitIdx = -1;
   buyZoneActivatedTime = 0;
   sellZoneActivatedTime = 0;

   PrintFormat("[ZONE_AUTO] Built %d BUY + %d SELL from Open=%.*f (spacing=%.1f pip)",
               count, count, _Digits, openPrice, ZoneSpacingPips);
   for (int i = 0; i < count; i++)
      PrintFormat("[ZONE_AUTO]  BUY[%d]=%.*f  SELL[%d]=%.*f",
                  i + 1, _Digits, buyZones[i], i + 1, _Digits, sellZones[i]);
   SaveZoneState();
}

//=========================== REBUILD OPPOSITE ZONES =================
void RebuildOppositeZones(bool wasBuy, double triggerZonePrice, int triggerZoneIdx)
{
   if (triggerZoneIdx < 0)
   {
      PrintFormat("[ZONE_REBUILD] idx=%d < 0 → skip rebuild", triggerZoneIdx);
      return;
   }

   double pip = PipSize();
   double spacing = ZoneSpacingPips * pip;
   int count = MathMax(1, ZoneCount);

   if (wasBuy)
   {
      // anchor = triggerBuyPrice + spacing
      double anchor = triggerZonePrice + spacing;

      ArrayResize(sellZones, count);
      ArrayResize(sellZoneHasPosition, count);
      ArrayFill(sellZoneHasPosition, 0, count, false);
      totalSellZones = count;

      // Rebuild SELL zones
      for (int j = 0; j < count; j++)
         sellZones[j] = NormalizePrice(anchor + spacing * j);

      // Rebuild BUY zones — trigger trở thành buy[0]
      for (int j = 0; j < count; j++)
         buyZones[j] = NormalizePrice(triggerZonePrice - spacing * j);

      // Reset SELL activation state toàn bộ
      sellZoneActivated = false;
      lastSellZoneHitPrice = 0.0;
      lastSellZoneHitIdx = -1;
      lastSellZoneHitTime = 0;
      sellZoneActivatedTime = 0;
      if (NormalizeDouble(triggerZonePrice, _Digits) != NormalizeDouble(lastBuyZoneHitPrice, _Digits))
      {
         lastSellIFVGBottom = 0.0;
         lastBuyIFVGTop = 0.0;
      }

      PrintFormat("[ZONE_REBUILD][SELL] BUY[%d]=%.*f → anchor=%.*f | new SELL zones:",
                  triggerZoneIdx + 1, _Digits, triggerZonePrice, _Digits, anchor);
      for (int j = 0; j < count; j++)
         PrintFormat("[ZONE_REBUILD][SELL]  [%d] = %.*f", j + 1, _Digits, sellZones[j]);

      SaveZoneState();
   }
   else
   {
      // anchor = triggerSellPrice - spacing
      double anchor = triggerZonePrice - spacing;

      ArrayResize(buyZones, count);
      ArrayResize(buyZoneHasPosition, count);
      ArrayFill(buyZoneHasPosition, 0, count, false);
      totalBuyZones = count;

      // Rebuild BUY zones
      for (int j = 0; j < count; j++)
         buyZones[j] = NormalizePrice(anchor - spacing * j);

      // Rebuild SELL zones — trigger trở thành sell[0]
      for (int j = 0; j < count; j++)
         sellZones[j] = NormalizePrice(triggerZonePrice + spacing * j);

      // Reset BUY activation state toàn bộ
      buyZoneActivated = false;
      lastBuyZoneHitPrice = 0.0;
      lastBuyZoneHitIdx = -1;
      lastBuyZoneHitTime = 0;
      buyZoneActivatedTime = 0;
      if (NormalizeDouble(triggerZonePrice, _Digits) != NormalizeDouble(lastSellZoneHitPrice, _Digits))
      {
         lastBuyIFVGTop = 0.0;
         lastSellIFVGBottom = 0.0;
      }
      PrintFormat("[ZONE_REBUILD][BUY] SELL[%d]=%.*f → anchor=%.*f | new BUY zones:",
                  triggerZoneIdx + 1, _Digits, triggerZonePrice, _Digits, anchor);
      for (int j = 0; j < count; j++)
         PrintFormat("[ZONE_REBUILD][BUY]  [%d] = %.*f", j + 1, _Digits, buyZones[j]);

      SaveZoneState();
   }
}

//=========================== CHECK AND UPDATE SESSION ZONES =========
void CheckAndUpdateSessionZones()
{
   datetime now = TimeCurrent(), sStart = 0, sEnd = 0;
   if (!GetCurrentSymbolSessionWindow(now, sStart, sEnd))
      return;
   if (sStart != currentSessionOpenTime)
   {
      PrintFormat("[ZONE_AUTO] NEW SESSION prev=%s → new=%s",
                  TimeToString(currentSessionOpenTime, TIME_DATE | TIME_MINUTES),
                  TimeToString(sStart, TIME_DATE | TIME_MINUTES));
      currentSessionOpenTime = sStart;
      double op = GetSessionOpenPrice();
      if (op > 0.0)
      {
         currentSessionOpen = op;
         BuildZonesFromOpen(op);
      }
      else
         PrintFormat("[ZONE_AUTO] WARN: Could not get session open!");
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
      double nearZone = 0.0;
      int nearIdx = -1;
      double minD = DBL_MAX;
      for (int i = 0; i < totalBuyZones; i++)
      {
         double d = MathAbs(bid - buyZones[i]);
         if (d <= threshold && d < minD)
         {
            minD = d;
            nearZone = buyZones[i];
            nearIdx = i;
         }
      }
      if (nearIdx >= 0)
      {
         if (!buyZoneActivated)
         {
            buyZoneActivated = true;
            lastBuyZoneHitPrice = nearZone;
            lastBuyZoneHitIdx = nearIdx;
            lastBuyZoneHitTime = now;
            buyZoneActivatedTime = now;
            lastBuyZoneActivatedTime = now;
            PrintFormat("[ZONE][BUY] ACTIVATED Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
            RebuildOppositeZones(true, nearZone, nearIdx);
         }
         else if (nearIdx != lastBuyZoneHitIdx)
         {
            lastBuyZoneHitPrice = nearZone;
            lastBuyZoneHitIdx = nearIdx;
            lastBuyZoneHitTime = now;
            buyZoneActivatedTime = now;
            lastBuyZoneActivatedTime = now;
            PrintFormat("[ZONE][BUY] SWITCH → Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
            RebuildOppositeZones(true, nearZone, nearIdx);
         }
      }
   }

   // ----- SELL -----
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double nearZone = 0.0;
      int nearIdx = -1;
      double minD = DBL_MAX;
      for (int i = 0; i < totalSellZones; i++)
      {
         double d = MathAbs(ask - sellZones[i]);
         if (d <= threshold && d < minD)
         {
            minD = d;
            nearZone = sellZones[i];
            nearIdx = i;
         }
      }
      if (nearIdx >= 0)
      {
         if (!sellZoneActivated)
         {
            sellZoneActivated = true;
            lastSellZoneHitPrice = nearZone;
            lastSellZoneHitIdx = nearIdx;
            lastSellZoneHitTime = now;
            sellZoneActivatedTime = now;
            lastSellZoneActivatedTime = now;
            PrintFormat("[ZONE][SELL] ACTIVATED Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
            RebuildOppositeZones(false, nearZone, nearIdx);
         }
         else if (nearIdx != lastSellZoneHitIdx)
         {
            lastSellZoneHitPrice = nearZone;
            lastSellZoneHitIdx = nearIdx;
            lastSellZoneHitTime = now;
            sellZoneActivatedTime = now;
            lastSellZoneActivatedTime = now;
            PrintFormat("[ZONE][SELL] SWITCH → Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
            RebuildOppositeZones(false, nearZone, nearIdx);
         }
      }
   }
}

//=========================== EXECUTE ENTRY ==========================
bool ExecuteEntry(bool isBuy)
{
   double lots = NormalizeVolume(FixedLotSize);
   if (lots <= 0.0)
   {
      PrintFormat("[SKIP][%s] lots=0", SideText(isBuy));
      return false;
   }

   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entry = NormalizePrice(entry);

   double sl = 0.0;
   double SL50 = 50.0;
   if (SLPips > 0.0)
   {
      sl = isBuy ? NormalizePrice(entry - SL50 * PipSize())
                 : NormalizePrice(entry + SL50 * PipSize());
   }

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, 0.0, "IFVG BUY")
                   : trade.Sell(lots, _Symbol, 0.0, sl, 0.0, "IFVG SELL");

   if (ok)
   {
      double filled = trade.ResultPrice();

      double weighted = filled * lots, totalL = lots;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if (!PositionSelectByTicket(tk))
            continue;
         if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if (isBuy && pt != POSITION_TYPE_BUY)
            continue;
         if (!isBuy && pt != POSITION_TYPE_SELL)
            continue;
         if (PositionGetDouble(POSITION_PRICE_OPEN) == filled && PositionGetDouble(POSITION_VOLUME) == lots)
            continue;
         double pl = PositionGetDouble(POSITION_VOLUME);
         weighted += PositionGetDouble(POSITION_PRICE_OPEN) * pl;
         totalL += pl;
      }
      double avgEntry = weighted / totalL;
      double tpUSD = CalcTpUSD();

      PrintFormat("[ORDER][%s] Filled=%.*f Lots=%.2f | AvgEntry=%.*f | GroupTP=$%.2f (%.2flot×%.1fpip) | Positions=%d",
                  SideText(isBuy), _Digits, filled, lots,
                  _Digits, avgEntry, tpUSD, FixedLotSize, TpPips,
                  CountOpenPositions(isBuy));
                  
      if (SLPips > 0.0)
      {
         double filled = trade.ResultPrice();
         double slFinal = isBuy ? NormalizePrice(filled - SLPips * PipSize())
                                : NormalizePrice(filled + SLPips * PipSize());

         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong tk = PositionGetTicket(i);
            if (!PositionSelectByTicket(tk))
               continue;
            if (PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
               continue;
            ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (isBuy && pt != POSITION_TYPE_BUY)
               continue;
            if (!isBuy && pt != POSITION_TYPE_SELL)
               continue;
            if (PositionGetDouble(POSITION_PRICE_OPEN) != filled)
               continue;

            if (!trade.PositionModify(tk, slFinal, 0.0))
               PrintFormat("[WARN][%s] Modify SL failed ret=%d %s",
                           SideText(isBuy), trade.ResultRetcode(),
                           trade.ResultRetcodeDescription());
            else
               PrintFormat("[ORDER][%s] SL modified to %.*f", SideText(isBuy), _Digits, slFinal);
            break;
         }
      }
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
   if (ifvgHandle == INVALID_HANDLE)
      return;

   double buyTop[1], buyBot[1], sellTop[1], sellBot[1], invTime[1];
   if (CopyBuffer(ifvgHandle, 0, 1, 1, buyTop) != 1)
   {
      PrintFormat("[IFVG][WARN] buf0");
      return;
   }
   if (CopyBuffer(ifvgHandle, 1, 1, 1, buyBot) != 1)
   {
      PrintFormat("[IFVG][WARN] buf1");
      return;
   }
   if (CopyBuffer(ifvgHandle, 2, 1, 1, sellTop) != 1)
   {
      PrintFormat("[IFVG][WARN] buf2");
      return;
   }
   if (CopyBuffer(ifvgHandle, 3, 1, 1, sellBot) != 1)
   {
      PrintFormat("[IFVG][WARN] buf3");
      return;
   }
   if (CopyBuffer(ifvgHandle, 4, 1, 1, invTime) != 1)
   {
      PrintFormat("[IFVG][WARN] buf4");
      return;
   }
   // ----- BUY -----
   PrintFormat("[IFVG][BUY] ZoneActive=%s activatedTime=%s lastSignal=%s",
               buyZoneActivated ? "YES" : "NO",
               TimeToString(buyZoneActivatedTime, TIME_DATE | TIME_MINUTES),
               TimeToString(lastBuySignalTime, TIME_DATE | TIME_MINUTES));

   if (buyZoneActivated && lastBuyZoneHitIdx >= 0 && lastBuyZoneHitIdx < totalBuyZones)
   {
      if (lastSellZoneActivatedTime > lastBuyZoneActivatedTime)
      {
         PrintFormat("[IFVG][BUY] SKIP: SELL zone hit lúc %s sau BUY zone %s → chờ BUY zone hit lại",
                     TimeToString(lastSellZoneActivatedTime, TIME_DATE | TIME_MINUTES),
                     TimeToString(lastBuyZoneActivatedTime, TIME_DATE | TIME_MINUTES));
      }
      else if (buyZoneHasPosition[lastBuyZoneHitIdx])
      {
         PrintFormat("[IFVG][BUY] SKIP: zone idx=%d đang có lệnh mở, chờ đóng mới vào lại",
                     lastBuyZoneHitIdx);
      }
      else
      {
         if (MathIsValidNumber(buyTop[0]) && buyTop[0] > 0.0 && buyTop[0] < 1e10 && invTime[0] > 0)
         {
            datetime ifvgBuyTime = (datetime)invTime[0];
            datetime lastClosedBarTime = iTime(_Symbol, _Period, 1);

            if (ifvgBuyTime != lastClosedBarTime)
            {
               PrintFormat("[IFVG][BUY] SKIP bar=1 repaint invTime=%s != lastBar=%s",
                           TimeToString(ifvgBuyTime, TIME_DATE | TIME_MINUTES),
                           TimeToString(lastClosedBarTime, TIME_DATE | TIME_MINUTES));
            }
            else if (lastSellZoneActivatedTime > 0 &&
                     ifvgBuyTime > lastSellZoneActivatedTime &&
                     ifvgBuyTime < buyZoneActivatedTime)
            {
               PrintFormat("[IFVG][BUY] SKIP IFVG formed during SELL zone context");
            }
            else if (lastClosedBarTime == lastBuySignalTime)
            {
               PrintFormat("[IFVG][BUY] SKIP already fired");
            }
            else if (ifvgBuyTime <= MathMax(buyZoneActivatedTime, lastSellZoneActivatedTime))
            {
               PrintFormat("[IFVG][BUY] SKIP ifvgBuyTime=%s <= threshold=%s",
                           TimeToString(ifvgBuyTime, TIME_DATE | TIME_MINUTES),
                           TimeToString(MathMax(buyZoneActivatedTime, lastSellZoneActivatedTime), TIME_DATE | TIME_MINUTES));
            }
            else if (NormalizeDouble(buyTop[0], _Digits) == NormalizeDouble(lastBuyIFVGTop, _Digits))
            {
               PrintFormat("[IFVG][BUY] SKIP same IFVG top=%.*f already used", _Digits, buyTop[0]);
            }
            else
            {
               double lastClose = iClose(_Symbol, _Period, 1);
               double prevClose = iClose(_Symbol, _Period, 2);

               if (prevClose > buyTop[0])
               {
                  PrintFormat("[IFVG][BUY] SKIP not first close above top prevClose=%.*f top=%.*f",
                              _Digits, prevClose, _Digits, buyTop[0]);
                  lastBuyIFVGTop = buyTop[0];
               }
               else if (lastClose <= buyTop[0])
               {
                  PrintFormat("[IFVG][BUY] SKIP close not above top lastClose=%.*f top=%.*f",
                              _Digits, lastClose, _Digits, buyTop[0]);
                  lastBuyIFVGTop = buyTop[0];
               }
               else
               {
                  PrintFormat("[IFVG][BUY] PASS lastClose=%.*f > top=%.*f | invTime=%s",
                              _Digits, lastClose, _Digits, buyTop[0],
                              TimeToString(ifvgBuyTime, TIME_DATE | TIME_MINUTES));
                  lastBuySignalTime = lastClosedBarTime;
                  lastBuyIFVGTop = buyTop[0];
                  if (ExecuteEntry(true))
                     buyZoneHasPosition[lastBuyZoneHitIdx] = true;
               }
            }
         }
         else
         {
            PrintFormat("[IFVG][BUY] No valid IFVG on last bar");
         }
      }
   }

   // ----- SELL -----
   PrintFormat("[IFVG][SELL] ZoneActive=%s activatedTime=%s lastSignal=%s",
               sellZoneActivated ? "YES" : "NO",
               TimeToString(sellZoneActivatedTime, TIME_DATE | TIME_MINUTES),
               TimeToString(lastSellSignalTime, TIME_DATE | TIME_MINUTES));

   if (sellZoneActivated && lastSellZoneHitIdx >= 0 && lastSellZoneHitIdx < totalSellZones)
   {
      if (lastBuyZoneActivatedTime > lastSellZoneActivatedTime)
      {
         PrintFormat("[IFVG][SELL] SKIP: BUY zone hit lúc %s sau SELL zone %s → chờ SELL zone hit lại",
                     TimeToString(lastBuyZoneActivatedTime, TIME_DATE | TIME_MINUTES),
                     TimeToString(lastSellZoneActivatedTime, TIME_DATE | TIME_MINUTES));
      }
      else if (sellZoneHasPosition[lastSellZoneHitIdx])
      {
         PrintFormat("[IFVG][SELL] SKIP: zone idx=%d đang có lệnh mở, chờ đóng mới vào lại",
                     lastSellZoneHitIdx);
      }
      else
      {
         if (MathIsValidNumber(sellBot[0]) && sellBot[0] > 0.0 && sellBot[0] < 1e10 && invTime[0] > 0)
         {
            datetime ifvgSellTime = (datetime)invTime[0];
            datetime lastClosedBarTime = iTime(_Symbol, _Period, 1);

            if (ifvgSellTime != lastClosedBarTime)
            {
               PrintFormat("[IFVG][SELL] SKIP repaint invTime=%s != lastBar=%s",
                           TimeToString(ifvgSellTime, TIME_DATE | TIME_MINUTES),
                           TimeToString(lastClosedBarTime, TIME_DATE | TIME_MINUTES));
            }

            else if (lastBuyZoneActivatedTime > 0 &&
                     ifvgSellTime > lastBuyZoneActivatedTime &&
                     ifvgSellTime < sellZoneActivatedTime)
            {
               PrintFormat("[IFVG][SELL] SKIP IFVG formed during BUY zone context");
            }
            else if (lastClosedBarTime == lastSellSignalTime)
            {
               PrintFormat("[IFVG][SELL] SKIP already fired");
            }
            else if (ifvgSellTime <= MathMax(sellZoneActivatedTime, lastBuyZoneActivatedTime))
            {
               PrintFormat("[IFVG][SELL] SKIP ifvgSellTime=%s <= threshold=%s",
                           TimeToString(ifvgSellTime, TIME_DATE | TIME_MINUTES),
                           TimeToString(MathMax(sellZoneActivatedTime, lastBuyZoneActivatedTime), TIME_DATE | TIME_MINUTES));
            }
            else if (NormalizeDouble(sellBot[0], _Digits) == NormalizeDouble(lastSellIFVGBottom, _Digits))
            {

               PrintFormat("[IFVG][SELL] SKIP same IFVG bottom=%.*f already used", _Digits, sellBot[0]);
            }
            else
            {
               double lastClose = iClose(_Symbol, _Period, 1);
               double prevClose = iClose(_Symbol, _Period, 2);

               if (prevClose < sellBot[0])
               {
                  PrintFormat("[IFVG][SELL] SKIP not first close below bottom prevClose=%.*f bot=%.*f",
                              _Digits, prevClose, _Digits, sellBot[0]);
                  lastSellIFVGBottom = sellBot[0];
               }
               else if (lastClose >= sellBot[0])
               {
                  PrintFormat("[IFVG][SELL] SKIP close not below bottom lastClose=%.*f bot=%.*f",
                              _Digits, lastClose, _Digits, sellBot[0]);
                  lastSellIFVGBottom = sellBot[0];
               }
               else
               {
                  PrintFormat("[IFVG][SELL] PASS lastClose=%.*f < bottom=%.*f | invTime=%s",
                              _Digits, lastClose, _Digits, sellBot[0],
                              TimeToString(ifvgSellTime, TIME_DATE | TIME_MINUTES));
                  lastSellSignalTime = lastClosedBarTime;
                  lastSellIFVGBottom = sellBot[0];
                  if (ExecuteEntry(false))
                     sellZoneHasPosition[lastSellZoneHitIdx] = true;
               }
            }
         }
         else
         {
            PrintFormat("[IFVG][SELL] No valid IFVG on last bar");
         }
      }
   }
}

//=========================== CHART COMMENT ==========================
void UpdateChartComment()
{
   if (!IsShowChartComment)
   {
      Comment("");
      return;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slLimit = balance * (SlPercent / 100.0);
   double tpUSD = CalcTpUSD();

   string txt = "";
   txt += "IFVG Handle  : " + (ifvgHandle != INVALID_HANDLE ? "OK" : "FAIL") + "\n";
   txt += "Balance      : " + DoubleToString(balance, 2) + "\n";
   txt += "SL Limit     : -" + DoubleToString(slLimit, 2) +
          " (" + DoubleToString(SlPercent, 1) + "% of balance)\n";
   txt += "TP Target    : $" + DoubleToString(tpUSD, 2) +
          " (" + DoubleToString(FixedLotSize, 2) + "lot × " +
          DoubleToString(TpPips, 1) + "pip)\n";
   txt += "--------------------------------------------\n";
   txt += "Session Open : " + DoubleToString(currentSessionOpen, _Digits) +
          " @ " + TimeToString(currentSessionOpenTime, TIME_DATE | TIME_MINUTES) + "\n";
   txt += "Lot Size     : " + DoubleToString(FixedLotSize, 2) + " (fixed, no SL/TP on orders)\n";
   txt += "--------------------------------------------\n";

   // BUY group
   int buyCount = CountOpenPositions(true);
   txt += "Open BUY     : " + IntegerToString(buyCount) + " positions\n";
   if (buyCount > 0)
   {
      double avg = GetAverageEntry(true);
      double fPnL = GetFloatingPnL(true);
      double need = tpUSD - fPnL;
      txt += "  AvgEntry  : " + DoubleToString(avg, _Digits) + "\n";
      txt += "  GroupTP   : $" + DoubleToString(tpUSD, 2) +
             " (PnL=" + DoubleToString(fPnL, 2) +
             " / need $" + DoubleToString(need, 2) + " more)\n";
      txt += "  FloatPnL  : " + DoubleToString(fPnL, 2) + "\n";
   }

   // SELL group
   int sellCount = CountOpenPositions(false);
   txt += "Open SELL    : " + IntegerToString(sellCount) + " positions\n";
   if (sellCount > 0)
   {
      double avg = GetAverageEntry(false);
      double fPnL = GetFloatingPnL(false);
      double need = tpUSD - fPnL;
      txt += "  AvgEntry  : " + DoubleToString(avg, _Digits) + "\n";
      txt += "  GroupTP   : $" + DoubleToString(tpUSD, 2) +
             " (PnL=" + DoubleToString(fPnL, 2) +
             " / need $" + DoubleToString(need, 2) + " more)\n";
      txt += "  FloatPnL  : " + DoubleToString(fPnL, 2) + "\n";
   }

   txt += "--------------------------------------------\n";
   txt += "BuyZone  : " + (buyZoneActivated ? "ACTIVE" : "waiting") + "\n";
   if (buyZoneActivated && lastBuyZoneHitPrice > 0)
      txt += "  └─ " + DoubleToString(lastBuyZoneHitPrice, _Digits) +
             " (idx=" + IntegerToString(lastBuyZoneHitIdx) + ")\n";
   txt += "SellZone : " + (sellZoneActivated ? "ACTIVE" : "waiting") + "\n";
   if (sellZoneActivated && lastSellZoneHitPrice > 0)
      txt += "  └─ " + DoubleToString(lastSellZoneHitPrice, _Digits) +
             " (idx=" + IntegerToString(lastSellZoneHitIdx) + ")\n";
   txt += "--------------------------------------------\n";

   for (int i = 0; i < totalBuyZones; i++)
      txt += "  [BUY " + IntegerToString(i + 1) + "] " +
             DoubleToString(buyZones[i], _Digits) + " ±" + IntegerToString(ZoneActivationPips) + "pip" +
             (buyZoneActivated && lastBuyZoneHitIdx == i ? " <<ACTIVE" : "") +
             (buyZoneHasPosition[i] ? " [LOCKED]" : "") + "\n";
   for (int i = 0; i < totalSellZones; i++)
      txt += "  [SEL " + IntegerToString(i + 1) + "] " +
             DoubleToString(sellZones[i], _Digits) + " ±" + IntegerToString(ZoneActivationPips) + "pip" +
             (sellZoneActivated && lastSellZoneHitIdx == i ? " <<ACTIVE" : "") +
             (sellZoneHasPosition[i] ? " [LOCKED]" : "") + "\n";

   Comment(txt);
}

//=========================== INIT / DEINIT ==========================
int OnInit()
{
   ifvgHandle = iCustom(_Symbol, _Period, IFVGIndicatorName,
                        IFVGLookback, IFVGBuyColor, IFVGSellColor,
                        IFVGAlpha, IFVGExtendBars,
                        IFVGDisplacement, IFVGAtrPeriod);
   if (ifvgHandle == INVALID_HANDLE)
   {
      PrintFormat("[INIT] FAILED to load '%s' err=%d", IFVGIndicatorName, GetLastError());
      return INIT_FAILED;
   }

   double tpUSD = CalcTpUSD();
   PrintFormat("[INIT] handle=%d | Lot=%.2f | TpPips=%.1f → TpUSD=$%.2f | SlPercent=%.1f%%",
               ifvgHandle, FixedLotSize, TpPips, tpUSD, SlPercent);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   currentSessionOpen = 0.0;
   currentSessionOpenTime = 0;
   totalBuyZones = 0;
   totalSellZones = 0;
   buyZoneActivated = false;
   sellZoneActivated = false;
   lastBuyZoneHitPrice = 0.0;
   lastBuyZoneHitIdx = -1;
   lastSellZoneHitPrice = 0.0;
   lastSellZoneHitIdx = -1;
   buyZoneActivatedTime = 0;
   sellZoneActivatedTime = 0;
   lastSellIFVGBottom = 0.0;
   lastBuyIFVGTop = 0.0;
   lastSellZoneActivatedTime = 0;
   lastBuyZoneActivatedTime = 0;
   if (!LoadZoneState())
      CheckAndUpdateSessionZones();

   lastBuySignalTime = iTime(_Symbol, _Period, 1);
   lastSellSignalTime = iTime(_Symbol, _Period, 1);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   if (ifvgHandle != INVALID_HANDLE)
      IndicatorRelease(ifvgHandle);
}

//=========================== TICK ===================================
void OnTick()
{
   CheckAndUpdateSessionZones();
   UpdateZoneActivation();
   CheckGroupExits();

   if (!IsNewBar())
      return;
   UpdateChartComment();
   CheckIFVGSignals();
}