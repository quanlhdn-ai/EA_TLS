//+------------------------------------------------------------------+
//|                                                   TLS_IFVG.mq5  |
//|                    IFVG Zone Entry EA  v4.12                     |
//|                                                                  |
//|  STRATEGY:                                                       |
//|  - Zones AUTO-CALCULATED from session open price                 |
//|  - BUY zones  = open - spacing*1, open - spacing*2, ...         |
//|  - SELL zones = open + spacing*1, open + spacing*2, ...         |
//|  - Zones reset on each new session open                          |
//|                                                                  |
//|  REBUILD OPPOSITE ZONES (new in v4.12):                         |
//|  - Chạm BUY zone idx>=1 (zone 2+) & ExecuteEntry BUY success:  |
//|    SELL[j] = triggerBuyPrice + spacing*2 + spacing*j            |
//|  - Chạm SELL zone idx>=1 (zone 2+) & ExecuteEntry SELL success:|
//|    BUY[j] = triggerSellPrice - spacing*2 - spacing*j            |
//|  - Chạm zone 1 (idx=0): không rebuild gì                        |
//|  - Rebuild liên tục mỗi lần vào lệnh thành công                 |
//|                                                                  |
//|  ENTRY:                                                          |
//|  - Zone activates when price enters within ZoneActivationPips    |
//|  - IFVG appears after zone activation → enter immediately        |
//|  - Fixed lot size, NO SL / NO TP on individual orders            |
//|                                                                  |
//|  GROUP TP (checked every tick):                                  |
//|  - TpUSD = FixedLotSize × pip_value_per_lot × TpPips            |
//|  - When total floating PnL >= TpUSD → close ALL positions        |
//|                                                                  |
//|  GROUP SL (checked every tick):                                  |
//|  - Total floating loss >= SlPercent% of account balance          |
//|  - → close ALL positions immediately                             |
//|                                                                  |
//|  POST-CLOSE:                                                     |
//|  - Zones remain valid; price re-enters zone + IFVG → re-enter   |
//+------------------------------------------------------------------+
#property copyright "TLS_IFVG EA"
#property version   "4.12"
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
input int IFVGDisplacement  = 3;
input int IFVGAtrPeriod     = 20;

// Display
input bool IsShowChartComment = true;

// Entry
input double FixedLotSize   = 0.01;

// Group TP
input double TpPips = 100.0;          // TP tính theo pip × FixedLotSize → ra USD cố định

// Group SL
input double SlPercent = 100.0;        // Close ALL when total floating loss >= X% of balance

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
bool   buyZoneHasPosition[];
bool   sellZoneHasPosition[];
int    totalBuyZones  = 0;
int    totalSellZones = 0;

datetime lastBarTime        = 0;
datetime lastBuySignalTime  = 0;
datetime lastSellSignalTime = 0;

double   currentSessionOpen     = 0.0;
datetime currentSessionOpenTime = 0;

// Zone 1 gốc — lưu khi BuildZonesFromOpen, dùng để log reference
double originalBuyZone1  = 0.0;
double originalSellZone1 = 0.0;

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

double CalcTpUSD()
{
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0.0) return 0.0;
   double pipVal = tickVal / tickSize * PipSize();
   return FixedLotSize * pipVal * TpPips;
}

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
                     IFVGAlpha, IFVGExtendBars,
                     IFVGDisplacement, IFVGAtrPeriod);
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
void SyncZonePositionFlags()
{
   if (CountOpenPositions(true) == 0)
   {
      bool anyWasLocked = false;
      for (int i = 0; i < totalBuyZones; i++)
         if (buyZoneHasPosition[i]) { buyZoneHasPosition[i] = false; anyWasLocked = true; }
      if (anyWasLocked)
         PrintFormat("[ZONE_SYNC][BUY] Tất cả lệnh BUY đã đóng → reset zone locks");
   }

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
void CheckGroupExits()
{
   SyncZonePositionFlags();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double slLimit = balance * (SlPercent / 100.0);
   double tpUSD   = CalcTpUSD();

   // ----- BUY group -----
   if (CountOpenPositions(true) > 0)
   {
      double floatPnL = GetFloatingPnL(true);
      double avgEntry = GetAverageEntry(true);
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if (floatPnL >= tpUSD)
      {
         PrintFormat("[GROUP_TP][BUY] PnL=%.2f >= TpUSD=%.2f (%.2flot × %.1fpip) | AvgEntry=%.*f",
                     floatPnL, tpUSD, FixedLotSize, TpPips, _Digits, avgEntry);
         TG_SendGroupClose(true, "TP", avgEntry, bid, floatPnL);
         CloseAllPositions(true, "GROUP TP");
         lastBuySignalTime = iTime(_Symbol, _Period, 0);
         buyZoneActivated  = false;
         return;
      }

      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][BUY] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         TG_SendGroupClose(true, "SL", avgEntry, bid, floatPnL);
         CloseAllPositions(true, "GROUP SL");
         lastBuySignalTime = iTime(_Symbol, _Period, 0);
         buyZoneActivated  = false;
         return;
      }
   }

   // ----- SELL group -----
   if (CountOpenPositions(false) > 0)
   {
      double floatPnL = GetFloatingPnL(false);
      double avgEntry = GetAverageEntry(false);
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if (floatPnL >= tpUSD)
      {
         PrintFormat("[GROUP_TP][SELL] PnL=%.2f >= TpUSD=%.2f (%.2flot × %.1fpip) | AvgEntry=%.*f",
                     floatPnL, tpUSD, FixedLotSize, TpPips, _Digits, avgEntry);
         TG_SendGroupClose(false, "TP", avgEntry, ask, floatPnL);
         CloseAllPositions(false, "GROUP TP");
         lastSellSignalTime = iTime(_Symbol, _Period, 0);
         sellZoneActivated  = false;
         return;
      }

      if (floatPnL < 0.0 && (-floatPnL) >= slLimit)
      {
         PrintFormat("[GROUP_SL][SELL] floatLoss=%.2f >= slLimit=%.2f (%.1f%% of balance=%.2f)",
                     -floatPnL, slLimit, SlPercent, balance);
         TG_SendGroupClose(false, "SL", avgEntry, ask, floatPnL);
         CloseAllPositions(false, "GROUP SL");
         lastSellSignalTime = iTime(_Symbol, _Period, 0);
         sellZoneActivated  = false;
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

   // Lưu zone 1 gốc để reference
   originalBuyZone1  = buyZones[0];
   originalSellZone1 = sellZones[0];

   buyZoneActivated  = false; sellZoneActivated  = false;
   lastBuyZoneHitPrice  = 0.0; lastBuyZoneHitIdx  = -1;
   lastSellZoneHitPrice = 0.0; lastSellZoneHitIdx = -1;
   buyZoneActivatedTime = 0;   sellZoneActivatedTime = 0;

   PrintFormat("[ZONE_AUTO] Built %d BUY + %d SELL from Open=%.*f (spacing=%.1f pip)",
               count, count, _Digits, openPrice, ZoneSpacingPips);
   PrintFormat("[ZONE_AUTO] originalBuyZone1=%.*f originalSellZone1=%.*f",
               _Digits, originalBuyZone1, _Digits, originalSellZone1);
   for (int i = 0; i < count; i++)
      PrintFormat("[ZONE_AUTO]  BUY[%d]=%.*f  SELL[%d]=%.*f",
                  i+1, _Digits, buyZones[i], i+1, _Digits, sellZones[i]);
}

//=========================== REBUILD OPPOSITE ZONES =================
// Công thức:
//   Chạm BUY idx>=1: SELL[j] = triggerBuyPrice + spacing*2 + spacing*j
//   Chạm SELL idx>=1: BUY[j]  = triggerSellPrice - spacing*2 - spacing*j
//
// Ví dụ (Open=5139, spacing=25):
//   BUY2(5089,idx=1) → anchor=5089+50=5139 → SELL:[5139,5164,5189,5214,5239] ✓
//   BUY3(5064,idx=2) → anchor=5064+50=5114 → SELL:[5114,5139,5164,5189,5214] ✓
//   SELL2(5189,idx=1)→ anchor=5189-50=5139 → BUY: [5139,5114,5089,5064,5039] ✓
//   SELL3(5214,idx=2)→ anchor=5214-50=5164 → BUY: [5164,5139,5114,5089,5064] ✓
void RebuildOppositeZones(bool wasBuy, double triggerZonePrice, int triggerZoneIdx)
{
   // Chỉ rebuild khi chạm zone 2 trở đi (idx >= 1)
   if (triggerZoneIdx < 1)
   {
      PrintFormat("[ZONE_REBUILD] idx=%d < 1 → skip rebuild", triggerZoneIdx);
      return;
   }

   double pip     = PipSize();
   double spacing = ZoneSpacingPips * pip;
   int    count   = MathMax(1, ZoneCount);

   if (wasBuy)
   {
      // anchor = triggerBuyPrice + spacing*2
      double anchor = triggerZonePrice + spacing * 2.0;

      ArrayResize(sellZones, count);
      ArrayResize(sellZoneHasPosition, count);
      ArrayFill(sellZoneHasPosition, 0, count, false);
      totalSellZones = count;

      for (int j = 0; j < count; j++)
         sellZones[j] = NormalizePrice(anchor + spacing * j);

      // Reset SELL activation state toàn bộ
      sellZoneActivated     = false;
      lastSellZoneHitPrice  = 0.0;
      lastSellZoneHitIdx    = -1;
      lastSellZoneHitTime   = 0;
      sellZoneActivatedTime = 0;
      lastSellSignalTime    = 0;

      PrintFormat("[ZONE_REBUILD][SELL] BUY[%d]=%.*f → anchor=%.*f | new SELL zones:",
                  triggerZoneIdx+1, _Digits, triggerZonePrice, _Digits, anchor);
      for (int j = 0; j < count; j++)
         PrintFormat("[ZONE_REBUILD][SELL]  [%d] = %.*f", j+1, _Digits, sellZones[j]);
   }
   else
   {
      // anchor = triggerSellPrice - spacing*2
      double anchor = triggerZonePrice - spacing * 2.0;

      ArrayResize(buyZones, count);
      ArrayResize(buyZoneHasPosition, count);
      ArrayFill(buyZoneHasPosition, 0, count, false);
      totalBuyZones = count;

      for (int j = 0; j < count; j++)
         buyZones[j] = NormalizePrice(anchor - spacing * j);

      // Reset BUY activation state toàn bộ
      buyZoneActivated     = false;
      lastBuyZoneHitPrice  = 0.0;
      lastBuyZoneHitIdx    = -1;
      lastBuyZoneHitTime   = 0;
      buyZoneActivatedTime = 0;
      lastBuySignalTime    = 0;

      PrintFormat("[ZONE_REBUILD][BUY] SELL[%d]=%.*f → anchor=%.*f | new BUY zones:",
                  triggerZoneIdx+1, _Digits, triggerZonePrice, _Digits, anchor);
      for (int j = 0; j < count; j++)
         PrintFormat("[ZONE_REBUILD][BUY]  [%d] = %.*f", j+1, _Digits, buyZones[j]);
   }
}

//=========================== CHECK AND UPDATE SESSION ZONES =========
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
            RebuildOppositeZones(true, nearZone, nearIdx);
         }
         else if (nearIdx != lastBuyZoneHitIdx)
         {
            lastBuyZoneHitPrice = nearZone; lastBuyZoneHitIdx = nearIdx;
            lastBuyZoneHitTime = now; buyZoneActivatedTime = iTime(_Symbol, _Period, 0);
            PrintFormat("[ZONE][BUY] SWITCH → Zone=%.*f Idx=%d", _Digits, nearZone, nearIdx);
            RebuildOppositeZones(true, nearZone, nearIdx);
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
            RebuildOppositeZones(false, nearZone, nearIdx);
         }
         else if (nearIdx != lastSellZoneHitIdx)
         {
            lastSellZoneHitPrice = nearZone; lastSellZoneHitIdx = nearIdx;
            lastSellZoneHitTime = now; sellZoneActivatedTime = iTime(_Symbol, _Period, 0);
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
   if (lots <= 0.0) { PrintFormat("[SKIP][%s] lots=0", SideText(isBuy)); return false; }

   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entry = NormalizePrice(entry);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   bool ok = isBuy ? trade.Buy(lots,  _Symbol, 0.0, 0.0, 0.0, "IFVG BUY")
                   : trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, "IFVG SELL");

   if (ok)
   {
      double filled = trade.ResultPrice();

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
         if (PositionGetDouble(POSITION_PRICE_OPEN) == filled && PositionGetDouble(POSITION_VOLUME) == lots) continue;
         double pl = PositionGetDouble(POSITION_VOLUME);
         weighted += PositionGetDouble(POSITION_PRICE_OPEN) * pl;
         totalL   += pl;
      }
      double avgEntry = weighted / totalL;
      double tpUSD    = CalcTpUSD();

      PrintFormat("[ORDER][%s] Filled=%.*f Lots=%.2f | AvgEntry=%.*f | GroupTP=$%.2f (%.2flot×%.1fpip) | Positions=%d",
                  SideText(isBuy), _Digits, filled, lots,
                  _Digits, avgEntry, tpUSD, FixedLotSize, TpPips,
                  CountOpenPositions(isBuy));

      TG_SendOpenMarket(isBuy, filled, avgEntry, tpUSD, (long)trade.ResultDeal());
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
            if (barTime == lastBuySignalTime)     { PrintFormat("[IFVG][BUY] bar=%d SKIP already fired", i+1); continue; }
            if (invBarTime < buyZoneActivatedTime) { PrintFormat("[IFVG][BUY] bar=%d SKIP invTime before activation", i+1); continue; }
            if (rates[i].close <= buyTop[i])      { PrintFormat("[IFVG][BUY] bar=%d SKIP close not above top", i+1); continue; }
            PrintFormat("[IFVG][BUY] bar=%d PASS close=%.*f > top=%.*f | invTime=%s",
                        i+1, _Digits, rates[i].close, _Digits, buyTop[i],
                        TimeToString(invBarTime, TIME_DATE|TIME_MINUTES));
            lastBuySignalTime = barTime;

            if (ExecuteEntry(true))
            {
               buyZoneHasPosition[lastBuyZoneHitIdx] = true;
            }
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
            if (!MathIsValidNumber(sellBot[i]) || sellBot[i] <= 0.0 || sellBot[i] >= 1e10) continue;
            datetime invBarTime = (datetime)invTime[i];
            if (invBarTime <= 0) continue;
            datetime barTime = iTime(_Symbol, _Period, i + 1);
            if (barTime == lastSellSignalTime)     { PrintFormat("[IFVG][SELL] bar=%d SKIP already fired", i+1); continue; }
            if (invBarTime < sellZoneActivatedTime) { PrintFormat("[IFVG][SELL] bar=%d SKIP invTime before activation", i+1); continue; }
            if (rates[i].close >= sellBot[i])      { PrintFormat("[IFVG][SELL] bar=%d SKIP close not below bottom", i+1); continue; }
            PrintFormat("[IFVG][SELL] bar=%d PASS close=%.*f < bottom=%.*f | invTime=%s",
                        i+1, _Digits, rates[i].close, _Digits, sellBot[i],
                        TimeToString(invBarTime, TIME_DATE|TIME_MINUTES));
            lastSellSignalTime = barTime;

            if (ExecuteEntry(false))
            {
               sellZoneHasPosition[lastSellZoneHitIdx] = true;
            }
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
   double tpUSD   = CalcTpUSD();

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
          " @ " + TimeToString(currentSessionOpenTime, TIME_DATE|TIME_MINUTES) + "\n";
   txt += "OrigBuyZ1    : " + DoubleToString(originalBuyZone1,  _Digits) + "\n";
   txt += "OrigSellZ1   : " + DoubleToString(originalSellZone1, _Digits) + "\n";
   txt += "Lot Size     : " + DoubleToString(FixedLotSize, 2) + " (fixed, no SL/TP on orders)\n";
   txt += "--------------------------------------------\n";

   // BUY group
   int buyCount = CountOpenPositions(true);
   txt += "Open BUY     : " + IntegerToString(buyCount) + " positions\n";
   if (buyCount > 0)
   {
      double avg   = GetAverageEntry(true);
      double fPnL  = GetFloatingPnL(true);
      double need  = tpUSD - fPnL;
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
      double avg   = GetAverageEntry(false);
      double fPnL  = GetFloatingPnL(false);
      double need  = tpUSD - fPnL;
      txt += "  AvgEntry  : " + DoubleToString(avg, _Digits) + "\n";
      txt += "  GroupTP   : $" + DoubleToString(tpUSD, 2) +
             " (PnL=" + DoubleToString(fPnL, 2) +
             " / need $" + DoubleToString(need, 2) + " more)\n";
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

   double tpUSD = CalcTpUSD();
   PrintFormat("[INIT] handle=%d | Lot=%.2f | TpPips=%.1f → TpUSD=$%.2f | SlPercent=%.1f%%",
               ifvgHandle, FixedLotSize, TpPips, tpUSD, SlPercent);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   currentSessionOpen = 0.0; currentSessionOpenTime = 0;
   originalBuyZone1   = 0.0; originalSellZone1      = 0.0;
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
   CheckGroupExits();

   if (!IsNewBar()) return;
   UpdateChartComment();
   CheckIFVGSignals();
}