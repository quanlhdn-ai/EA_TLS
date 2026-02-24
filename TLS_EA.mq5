#property strict
#include <Trade/Trade.mqh>
CTrade trade;

#define ZONE_USED_FILE "TLS_ZoneUsed.dat"

struct ZoneUsedRecord
{
   bool isBuy;
   double zonePrice;
   datetime usedTime;
};

ZoneUsedRecord usedZones[];
int totalUsedZones = 0;

//--- Buy Lines
input double LineBUY1 = 0.0;
input double LineBUY2 = 0.0;
input double LineBUY3 = 0.0;
input double LineBUY4 = 0.0;
input double LineBUY5 = 0.0;
input double LineBUY6 = 0.0;
input double LineBUY7 = 0.0;
input double LineBUY8 = 0.0;
input double LineBUY9 = 0.0;
input double LineBUY10 = 0.0;

//--- Sell Lines
input double LineSELL1 = 0.0;
input double LineSELL2 = 0.0;
input double LineSELL3 = 0.0;
input double LineSELL4 = 0.0;
input double LineSELL5 = 0.0;
input double LineSELL6 = 0.0;
input double LineSELL7 = 0.0;
input double LineSELL8 = 0.0;
input double LineSELL9 = 0.0;
input double LineSELL10 = 0.0;

//=================== INPUTS ===============================
//--- Risk
input double RiskUSDPerTrade = 100.0;
input double RiskReward = 2.0;
input double DailyDD_Percent = 3.0;
input int ZoneSLBufferPips = 100;
input bool IsAllowBE = true;
input int BufferPips = 5;

input int SlippagePoints = 30;
input long MagicNumber = 8386272000;
//--- Daily DD
input bool IsCancelPendingsWhenDDHit = true;

//--- Profit target
input double DailyProfitTargetUSD = 0.0;
input bool IsForceCloseWhenProfitHit = false;
input bool IsCancelPendingsWhenProfitHit = true;

//--- Session
input double NoNewTradesBeforeEndH = 0.0;
input int SessionForceThrottleSec = 120;

//--- Chart
input bool IsShowChartComment = true;


//--- Telegram
input bool EnableTelegram = true;
input string TG_BotToken = "YOUR_TOKEN";
input string TG_ChatID = "YOUR_CHAT_ID";
input bool TG_IncludeManual = false;

//=================== ZONE ARRAYS ===============================
double buyZones[];
double sellZones[];
bool buyZonesUsed[];
bool sellZonesUsed[];
int totalBuyZones = 0;
int totalSellZones = 0;

int activeBuyLineIdx = -1;
int activeSellLineIdx = -1;

//--- DD / session
datetime sessionStartTime = 0;
datetime sessionEndTime = 0;
double sessionStartBalance = 0.0;
double sessionLossLimit = 0.0;
bool ddBlocked = false;
double lastSessionRealizedPnL = 0.0;

double sessionProfitTarget = 0.0;
bool profitBlocked = false;

datetime lastSessionForceActionTime = 0;
datetime lastKnownSessionEnd = 0;

//=================== FILE PERSISTENCE ===============================
void LoadZoneUsedFromFile()
{
   ArrayResize(usedZones, 0);
   totalUsedZones = 0;

   int handle = FileOpen(ZONE_USED_FILE, FILE_READ | FILE_BIN);
   if (handle == INVALID_HANDLE)
   {
      Print("[ZONE_USED] No existing file, starting fresh");
      return;
   }

   while (!FileIsEnding(handle))
   {
      ZoneUsedRecord rec;
      rec.isBuy = (bool)FileReadInteger(handle);
      rec.zonePrice = FileReadDouble(handle);
      rec.usedTime = (datetime)FileReadLong(handle);
      if (rec.zonePrice <= 0)
         break;
      ArrayResize(usedZones, totalUsedZones + 1);
      usedZones[totalUsedZones] = rec;
      totalUsedZones++;
   }

   FileClose(handle);
   PrintFormat("[ZONE_USED] Loaded %d records from file", totalUsedZones);
}

void SaveZoneUsedToFile()
{
   int handle = FileOpen(ZONE_USED_FILE, FILE_WRITE | FILE_BIN);
   if (handle == INVALID_HANDLE)
   {
      PrintFormat("[ZONE_USED] ERROR: Cannot save, err=%d", GetLastError());
      return;
   }
   for (int i = 0; i < totalUsedZones; i++)
   {
      FileWriteInteger(handle, (int)usedZones[i].isBuy);
      FileWriteDouble(handle, usedZones[i].zonePrice);
      FileWriteLong(handle, (long)usedZones[i].usedTime);
   }
   FileClose(handle);
   PrintFormat("[ZONE_USED] Saved %d records", totalUsedZones);
}

bool IsZoneUsedFromFile(bool isBuy, double zonePrice)
{
   for (int i = 0; i < totalUsedZones; i++)
      if (usedZones[i].isBuy == isBuy && MathAbs(usedZones[i].zonePrice - zonePrice) < 0.1)
         return true;
   return false;
}

//=================== LOAD LINES ===============================
void LoadPriceZones()
{
   double rawBuy[] = {LineBUY1, LineBUY2, LineBUY3, LineBUY4, LineBUY5,
                      LineBUY6, LineBUY7, LineBUY8, LineBUY9, LineBUY10};
   double rawSell[] = {LineSELL1, LineSELL2, LineSELL3, LineSELL4, LineSELL5,
                       LineSELL6, LineSELL7, LineSELL8, LineSELL9, LineSELL10};

   ArrayResize(buyZones, 0);
   ArrayResize(buyZonesUsed, 0);
   ArrayResize(sellZones, 0);
   ArrayResize(sellZonesUsed, 0);
   totalBuyZones = totalSellZones = 0;

   for (int i = 0; i < 10; i++)
      if (rawBuy[i] > 0.0)
      {
         ArrayResize(buyZones, totalBuyZones + 1);
         ArrayResize(buyZonesUsed, totalBuyZones + 1);
         buyZones[totalBuyZones] = NormalizePrice(rawBuy[i]);
         buyZonesUsed[totalBuyZones] = false;
         totalBuyZones++;
      }

   for (int i = 0; i < 10; i++)
      if (rawSell[i] > 0.0)
      {
         ArrayResize(sellZones, totalSellZones + 1);
         ArrayResize(sellZonesUsed, totalSellZones + 1);
         sellZones[totalSellZones] = NormalizePrice(rawSell[i]);
         sellZonesUsed[totalSellZones] = false;
         totalSellZones++;
      }

   ArraySort(buyZones);
   ArraySort(sellZones);

   for (int i = 0; i < totalBuyZones; i++)
      if (IsZoneUsedFromFile(true, buyZones[i]))
      {
         buyZonesUsed[i] = true;
         PrintFormat("[ZONE_USED] BUY restored USED: %.*f", _Digits, buyZones[i]);
      }
   for (int i = 0; i < totalSellZones; i++)
      if (IsZoneUsedFromFile(false, sellZones[i]))
      {
         sellZonesUsed[i] = true;
         PrintFormat("[ZONE_USED] SELL restored USED: %.*f", _Digits, sellZones[i]);
      }

   if (totalBuyZones > 0)
   {
      string s = "";
      for (int i = 0; i < totalBuyZones; i++)
         s += DoubleToString(buyZones[i], _Digits) + (buyZonesUsed[i] ? "[USED]" : "") + (i < totalBuyZones - 1 ? ", " : "");
      PrintFormat("[ZONE] %d BUY: %s", totalBuyZones, s);
   }
   if (totalSellZones > 0)
   {
      string s = "";
      for (int i = 0; i < totalSellZones; i++)
         s += DoubleToString(sellZones[i], _Digits) + (sellZonesUsed[i] ? "[USED]" : "") + (i < totalSellZones - 1 ? ", " : "");
      PrintFormat("[ZONE] %d SELL: %s", totalSellZones, s);
   }
}

//=================== MARK ZONE USED ===============================
void MarkZoneUsed(bool isBuy, int idx)
{
   if (idx < 0)
      return;

   if (isBuy && idx < totalBuyZones)
   {
      buyZonesUsed[idx] = true;
      PrintFormat("[ZONE][BUY ] idx=%d price=%.*f -> USED", idx, _Digits, buyZones[idx]);

      ZoneUsedRecord rec;
      rec.isBuy = true;
      rec.zonePrice = buyZones[idx];
      rec.usedTime = TimeCurrent();
      ArrayResize(usedZones, totalUsedZones + 1);
      usedZones[totalUsedZones] = rec;
      totalUsedZones++;
      SaveZoneUsedToFile();
   }
   else if (!isBuy && idx < totalSellZones)
   {
      sellZonesUsed[idx] = true;
      PrintFormat("[ZONE][SELL] idx=%d price=%.*f -> USED", idx, _Digits, sellZones[idx]);

      ZoneUsedRecord rec;
      rec.isBuy = false;
      rec.zonePrice = sellZones[idx];
      rec.usedTime = TimeCurrent();
      ArrayResize(usedZones, totalUsedZones + 1);
      usedZones[totalUsedZones] = rec;
      totalUsedZones++;
      SaveZoneUsedToFile();
   }
}

//=================== UTILS ===============================
double PipSize()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if (tickValue == 1.0 && tickSize == 0.01)
      return 0.1;
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

double CalcLotsByRiskUSD(double entry, double sl)
{
   double pip = PipSize();
   double slPips = MathAbs(entry - sl) / pip;
   if (slPips <= 0.0)
      return 0.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;
   double pipValPer1Lot = tickValue * (pip / tickSize);
   if (pipValPer1Lot <= 0.0)
      return 0.0;
   return NormalizeVolume(RiskUSDPerTrade / (slPips * pipValPer1Lot));
}

string SideText(bool isBuy) { return isBuy ? "BUY" : "SELL"; }

//=================== SESSION (BROKER HOURS) ===============================
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
      if (now < s0 && (e0 - s0) > 21600)
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

bool IsInMarketSessionNow(datetime &sOut, datetime &eOut)
{
   return GetCurrentSymbolSessionWindow(TimeCurrent(), sOut, eOut);
}

double HoursToSessionEnd(datetime &endOut)
{
   datetime s, e;
   if (!IsInMarketSessionNow(s, e))
   {
      endOut = 0;
      return 9999.0;
   }
   endOut = e;
   datetime now = TimeCurrent();
   return (now >= e) ? 0.0 : (double)(e - now) / 3600.0;
}

bool IsForbiddenBySession(datetime &sessEndOut)
{
   datetime s, e;
   sessEndOut = 0;
   if (!IsInMarketSessionNow(s, e))
      return true;
   sessEndOut = e;
   datetime dummy = 0;
   return (HoursToSessionEnd(dummy) <= NoNewTradesBeforeEndH + 1e-9);
}

void EnforceForbiddenZone()
{
   datetime sessEnd = 0;
   if (!IsForbiddenBySession(sessEnd))
   {
      lastKnownSessionEnd = 0;
      return;
   }

   datetime now = TimeCurrent();
   bool newKey = (sessEnd > 0 && sessEnd != lastKnownSessionEnd);
   if (!newKey && (now - lastSessionForceActionTime) < SessionForceThrottleSec)
      return;

   lastSessionForceActionTime = now;
   if (sessEnd > 0)
      lastKnownSessionEnd = sessEnd;

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong otk = OrderGetTicket(i);
      if (otk == 0 || !OrderSelect(otk))
         continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
          type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         trade.OrderDelete(otk);
   }
}

//=================== DD + PROFIT GATE ===============================
double RealizedPnLInRange(datetime fromTime, datetime toTime)
{
   if (!HistorySelect(fromTime, toTime))
      return 0.0;
   double pnl = 0.0;
   int n = (int)HistoryDealsTotal();
   for (int i = 0; i < n; i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if (tk == 0)
         continue;
      if ((long)HistoryDealGetInteger(tk, DEAL_MAGIC) != MagicNumber)
         continue;
      if (HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if (entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      pnl += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
   }
   return pnl;
}

void ResetSessionDDIfNeeded()
{
   datetime now = TimeCurrent(), s = 0, e = 0;
   if (!GetCurrentSymbolSessionWindow(now, s, e))
      return;
   if (sessionStartTime == 0 || s != sessionStartTime)
   {
      sessionStartTime = s;
      sessionEndTime = e;
      sessionStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      sessionLossLimit = sessionStartBalance * (DailyDD_Percent / 100.0);
      sessionProfitTarget = DailyProfitTargetUSD;
      ddBlocked = false;
      profitBlocked = false;
      lastSessionRealizedPnL = 0.0;
   }
   else
      sessionEndTime = e;
}

void UpdateSessionDDGate()
{
   ResetSessionDDIfNeeded();
   if (sessionStartTime == 0)
      return;

   double pnl = RealizedPnLInRange(sessionStartTime, TimeCurrent());
   lastSessionRealizedPnL = pnl;
   double loss = (pnl < 0.0) ? -pnl : 0.0;

   if (loss >= sessionLossLimit || (loss + RiskUSDPerTrade) > sessionLossLimit)
   {
      ddBlocked = true;
      if (IsCancelPendingsWhenDDHit)
         for (int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong otk = OrderGetTicket(i);
            if (otk == 0 || !OrderSelect(otk))
               continue;
            if (OrderGetString(ORDER_SYMBOL) != _Symbol)
               continue;
            if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
               continue;
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
               trade.OrderDelete(otk);
         }
   }
}

void UpdateSessionProfitGate()
{
   ResetSessionDDIfNeeded();
   if (DailyProfitTargetUSD <= 0.0)
   {
      profitBlocked = false;
      return;
   }
   if (sessionStartTime == 0)
      return;

   double pnl = RealizedPnLInRange(sessionStartTime, TimeCurrent());
   lastSessionRealizedPnL = pnl;

   if (pnl >= DailyProfitTargetUSD - 1e-9)
   {
      profitBlocked = true;
      if (IsCancelPendingsWhenProfitHit)
         for (int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong otk = OrderGetTicket(i);
            if (otk == 0 || !OrderSelect(otk))
               continue;
            if (OrderGetString(ORDER_SYMBOL) != _Symbol)
               continue;
            if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
               continue;
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
               trade.OrderDelete(otk);
         }
      if (IsForceCloseWhenProfitHit)
         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ptk = PositionGetTicket(i);
            if (ptk == 0 || !PositionSelectByTicket(ptk))
               continue;
            if (PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
               continue;
            trade.PositionClose(ptk);
         }
   }
}

//=================== HELPERS ===============================
int NextUnusedLineIdx(bool isBuy)
{
   int total = isBuy ? totalBuyZones : totalSellZones;
   for (int i = 0; i < total; i++)
      if (!(isBuy ? buyZonesUsed[i] : sellZonesUsed[i]))
         return i;
   return -1;
}

ulong HasPendingTicket(bool isBuy)
{
   ENUM_ORDER_TYPE otype = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if (tk == 0 || !OrderSelect(tk))
         continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      if ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == otype)
         return tk;
   }
   return 0;
}

bool HasPosition(ENUM_POSITION_TYPE ptype, ulong &ticketOut)
{
   ticketOut = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == ptype)
      {
         ticketOut = tk;
         return true;
      }
   }
   return false;
}

//=================== SYNC STATE ===============================
bool CheckFilledInHistory(bool isBuy, double linePrice)
{
   if (!HistorySelect(TimeCurrent() - 86400 * 7, TimeCurrent()))
      return false;
   int n = (int)HistoryDealsTotal();
   for (int i = n - 1; i >= 0; i--)
   {
      ulong dk = HistoryDealGetTicket(i);
      if (dk == 0)
         continue;
      if (HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol)
         continue;
      if ((long)HistoryDealGetInteger(dk, DEAL_MAGIC) != MagicNumber)
         continue;
      if ((long)HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      long dtype = (long)HistoryDealGetInteger(dk, DEAL_TYPE);
      if (isBuy && dtype != DEAL_TYPE_BUY)
         continue;
      if (!isBuy && dtype != DEAL_TYPE_SELL)
         continue;
      if (MathAbs(HistoryDealGetDouble(dk, DEAL_PRICE) - linePrice) < linePrice * 0.001)
         return true;
   }
   return false;
}

void SyncZoneState()
{
   // BUY
   if (activeBuyLineIdx >= 0 && HasPendingTicket(true) == 0)
   {
      if (CheckFilledInHistory(true, buyZones[activeBuyLineIdx]))
      {
         PrintFormat("[SYNC][BUY ] idx=%d filled -> USED", activeBuyLineIdx);
         MarkZoneUsed(true, activeBuyLineIdx);
      }
      else
         PrintFormat("[SYNC][BUY ] idx=%d cancelled externally -> will re-place", activeBuyLineIdx);
      activeBuyLineIdx = -1;
   }
   // SELL
   if (activeSellLineIdx >= 0 && HasPendingTicket(false) == 0)
   {
      if (CheckFilledInHistory(false, sellZones[activeSellLineIdx]))
      {
         PrintFormat("[SYNC][SELL] idx=%d filled -> USED", activeSellLineIdx);
         MarkZoneUsed(false, activeSellLineIdx);
      }
      else
         PrintFormat("[SYNC][SELL] idx=%d cancelled externally -> will re-place", activeSellLineIdx);
      activeSellLineIdx = -1;
   }
}

//=================== PLACE LIMIT ===============================
bool PlaceLimitForLine(bool isBuy, int idx)
{
   double linePrice = isBuy ? buyZones[idx] : sellZones[idx];
   double pip = PipSize();
   double entryLimit = NormalizePrice(linePrice);
   double sl = isBuy ? NormalizePrice(entryLimit - ZoneSLBufferPips * pip)
                     : NormalizePrice(entryLimit + ZoneSLBufferPips * pip);
   double riskDist = MathAbs(entryLimit - sl);
   if (riskDist <= 0)
      return false;

   double tp = isBuy ? NormalizePrice(entryLimit + RiskReward * riskDist)
                     : NormalizePrice(entryLimit - RiskReward * riskDist);
   double lots = CalcLotsByRiskUSD(entryLimit, sl);
   if (lots <= 0)
   {
      PrintFormat("[SKIP][%s] lots<=0 | entry=%.*f sl=%.*f", SideText(isBuy), _Digits, entryLimit, _Digits, sl);
      return false;
   }

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   bool ok = isBuy
                 ? trade.BuyLimit(lots, entryLimit, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "BUY LINE")
                 : trade.SellLimit(lots, entryLimit, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SELL LINE");

   if (ok)
   {
      PrintFormat("[ORDER][%s] PLACED | idx=%d entry=%.*f sl=%.*f tp=%.*f lots=%.2f",
                  SideText(isBuy), idx, _Digits, entryLimit, _Digits, sl, _Digits, tp, lots);
      if (isBuy)
         activeBuyLineIdx = idx;
      else
         activeSellLineIdx = idx;
   }
   else
      PrintFormat("[FAIL][%s] ret=%d %s | idx=%d entry=%.*f",
                  SideText(isBuy), trade.ResultRetcode(), trade.ResultRetcodeDescription(),
                  idx, _Digits, entryLimit);
   return ok;
}

//=================== MANAGE ORDERS ===============================
void ManageLineOrders()
{
   if (ddBlocked || profitBlocked)
      return;
   datetime sessEnd = 0;
   if (IsForbiddenBySession(sessEnd))
      return;

   // BUY
   ulong dummy = 0;
   if (HasPendingTicket(true) == 0 && !HasPosition(POSITION_TYPE_BUY, dummy))
   {
      int idx = NextUnusedLineIdx(true);
      if (idx >= 0)
         PlaceLimitForLine(true, idx);
   }

   // SELL
   if (HasPendingTicket(false) == 0 && !HasPosition(POSITION_TYPE_SELL, dummy))
   {
      int idx = NextUnusedLineIdx(false);
      if (idx >= 0)
         PlaceLimitForLine(false, idx);
   }
}

void CancelPendingIfTPHit()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if (tk == 0 || !OrderSelect(tk))
         continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
         continue;
      double tp = OrderGetDouble(ORDER_TP);
      if (tp <= 0)
         continue;

      if (type == ORDER_TYPE_BUY_LIMIT && bid >= tp)
      {
         TG_SendCancelLimitByTPBeforeFilled(true, OrderGetDouble(ORDER_PRICE_OPEN), (long)tk);
         if (activeBuyLineIdx >= 0)
         {
            MarkZoneUsed(true, activeBuyLineIdx);
            activeBuyLineIdx = -1;
         }
         trade.OrderDelete(tk);
      }
      if (type == ORDER_TYPE_SELL_LIMIT && bid <= tp)
      {
         TG_SendCancelLimitByTPBeforeFilled(false, OrderGetDouble(ORDER_PRICE_OPEN), (long)tk);
         if (activeSellLineIdx >= 0)
         {
            MarkZoneUsed(false, activeSellLineIdx);
            activeSellLineIdx = -1;
         }
         trade.OrderDelete(tk);
      }
   }
}

//=================== BREAK-EVEN ===============================
void ManageBreakEven()
{
   double pip = PipSize();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (tk == 0)
         continue;
      if (!PositionSelectByTicket(tk))
         continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ulong ticket = tk;
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double R = (ptype == POSITION_TYPE_BUY) ? (entry - sl) : (sl - entry);
      if (R <= 0)
         continue;

      double threshold = R - (double)BufferPips * pip;
      if (threshold < 0)
         threshold = 0;

      if (ptype == POSITION_TYPE_BUY)
      {
         // ===== BE at ~1R (OPTIONAL) =====
         if (IsAllowBE)
         {
            if ((bid - entry) >= threshold)
            {
               if (sl < entry)
                  trade.PositionModify(ticket, entry, tp);
            }
         }
      }
      else
      {
         // ===== BE at ~1R (OPTIONAL) =====
         if (IsAllowBE)
         {
            if ((entry - ask) >= threshold)
            {
               if (sl > entry)
                  trade.PositionModify(ticket, entry, tp);
            }
         }
      }
   }
}

//=================== CHART COMMENT ===============================
void UpdateChartComment()
{
   if (!IsShowChartComment)
   {
      Comment("");
      return;
   }

   datetime s = 0, e = 0;
   bool inSess = IsInMarketSessionNow(s, e);
   datetime dummy = 0;
   double hToEnd = HoursToSessionEnd(dummy);
   datetime sessEnd = 0;
   bool forbidden = IsForbiddenBySession(sessEnd);

   string txt = "";
   txt += "MarketSession : " + (inSess ? TimeToString(s, TIME_DATE | TIME_MINUTES) + " -> " + TimeToString(e, TIME_DATE | TIME_MINUTES) : "N/A") + "\n";
   txt += "Forbidden     : " + (forbidden ? "YES" : "NO") + " (hLeft=" + DoubleToString(hToEnd, 2) + ")\n";
   txt += "DD Blocked    : " + (ddBlocked ? "YES" : "NO") + "\n";
   txt += "ProfitBlocked : " + (profitBlocked ? "YES" : "NO") + "\n";
   txt += "SessPnL       : " + DoubleToString(lastSessionRealizedPnL, 2) + "\n";
   txt += "DD Limit      : -" + DoubleToString(sessionLossLimit, 2) + "\n";
   txt += "ActiveBuyIdx  : " + (activeBuyLineIdx >= 0 ? IntegerToString(activeBuyLineIdx) : "-") + "\n";
   txt += "ActiveSellIdx : " + (activeSellLineIdx >= 0 ? IntegerToString(activeSellLineIdx) : "-") + "\n";
   txt += "─────────────────────────────\n";

   double pip = PipSize();
   for (int i = 0; i < totalBuyZones; i++)
   {
      string state = buyZonesUsed[i] ? " [USED]"
                                     : (i == activeBuyLineIdx ? " [PENDING]" : " [WAITING]");
      double isl = buyZones[i] - ZoneSLBufferPips * pip;
      double itp = buyZones[i] + RiskReward * ZoneSLBufferPips * pip;
      txt += "  [BUY " + IntegerToString(i + 1) + "] " + DoubleToString(buyZones[i], _Digits) + "  SL=" + DoubleToString(isl, _Digits) + "  TP=" + DoubleToString(itp, _Digits) + state + "\n";
   }
   for (int i = 0; i < totalSellZones; i++)
   {
      string state = sellZonesUsed[i] ? " [USED]"
                                      : (i == activeSellLineIdx ? " [PENDING]" : " [WAITING]");
      double isl = sellZones[i] + ZoneSLBufferPips * pip;
      double itp = sellZones[i] - RiskReward * ZoneSLBufferPips * pip;
      txt += "  [SELL " + IntegerToString(i + 1) + "] " + DoubleToString(sellZones[i], _Digits) + "  SL=" + DoubleToString(isl, _Digits) + "  TP=" + DoubleToString(itp, _Digits) + state + "\n";
   }
   Comment(txt);
}

//=================== TELEGRAM ===============================
string TG_Key(const string kind, long id)
{
   return "TLS_TG_" + _Symbol + "_" + (string)(int)_Period + "_" + kind + "_" + (string)id;
}
bool TG_Sent(const string kind, long id) { return GlobalVariableCheck(TG_Key(kind, id)); }
void TG_Mark(const string kind, long id) { GlobalVariableSet(TG_Key(kind, id), (double)TimeCurrent()); }

string TG_UrlEncode(const string s)
{
   uchar a[];
   StringToCharArray(s, a, 0, WHOLE_ARRAY, CP_UTF8);
   string o = "";
   for (int i = 0; i < ArraySize(a); i++)
   {
      int c = (int)a[i];
      if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~')
         o += CharToString((ushort)c);
      else if (c == ' ')
         o += "%20";
      else if (c == '\n')
         o += "%0A";
      else
         o += StringFormat("%%%02X", c);
   }
   return o;
}

void TG_Send(const string msg)
{
   if (!EnableTelegram)
      return;
   if (StringLen(TG_BotToken) < 10 || StringLen(TG_ChatID) < 3)
      return;
   string url = "https://api.telegram.org/bot" + TG_BotToken + "/sendMessage";
   string body = "chat_id=" + TG_UrlEncode(TG_ChatID) + "&text=" + TG_UrlEncode(msg);
   uchar data[], result[];
   string rh;
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   int r = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, data, result, rh);
   if (r == -1)
      Print("[TG] error: ", GetLastError());
}

string TG_P(double v) { return DoubleToString(v, _Digits); }

void TG_SendPendingLimit(bool isBuy, double et, double sl, double tp, long orderId)
{
   if (TG_Sent("PEND_LIM", orderId))
      return;
   TG_Send(SideText(isBuy) + " LIMIT\nET  " + TG_P(et) + "\nSL  " + TG_P(sl) + "\nTP  " + TG_P(tp));
   TG_Mark("PEND_LIM", orderId);
}

void TG_SendCancelLimit(bool isBuy, double et, long orderId, const string reason)
{
   if (TG_Sent("CANCEL_LIM", orderId))
      return;
   TG_Send("CANCEL " + SideText(isBuy) + " LIMIT\nET  " + TG_P(et) + "\nREASON: " + reason);
   TG_Mark("CANCEL_LIM", orderId);
}

void TG_SendCancelLimitByTPBeforeFilled(bool isBuy, double et, long orderId)
{
   TG_SendCancelLimit(isBuy, et, orderId, "TP hit before filled");
}

bool TG_SelectDealSafe(ulong dealId, int retries = 10, int sleepMs = 50)
{
   for (int i = 0; i < retries; i++)
   {
      HistorySelect(TimeCurrent() - 2592000, TimeCurrent());
      if (HistoryDealSelect(dealId))
         return true;
      Sleep(sleepMs);
   }
   return false;
}

bool TG_GetFillOrigin(ulong dealTicket, bool &wasMarket, bool &wasLimit)
{
   wasMarket = wasLimit = false;
   if (!TG_SelectDealSafe(dealTicket))
      return false;
   ulong otk = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   if (otk == 0 || !HistoryOrderSelect(otk))
      return false;
   ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(otk, ORDER_TYPE);
   if (ot == ORDER_TYPE_BUY || ot == ORDER_TYPE_SELL)
   {
      wasMarket = true;
      return true;
   }
   if (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
   {
      wasLimit = true;
      return true;
   }
   return false;
}

bool TG_GetEntryPriceFromPositionHistory(long positionId, double &etOut, bool &isBuyOut)
{
   etOut = 0.0;
   isBuyOut = true;
   if (!HistorySelect(TimeCurrent() - 2592000, TimeCurrent()))
      return false;
   int n = (int)HistoryDealsTotal();
   for (int i = n - 1; i >= 0; i--)
   {
      ulong dk = HistoryDealGetTicket(i);
      if (dk == 0)
         continue;
      if (HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol)
         continue;
      long magic = (long)HistoryDealGetInteger(dk, DEAL_MAGIC);
      if (!TG_IncludeManual && magic != MagicNumber)
         continue;
      if (TG_IncludeManual && magic != MagicNumber && magic != 0)
         continue;
      if ((long)HistoryDealGetInteger(dk, DEAL_POSITION_ID) != positionId)
         continue;
      if ((long)HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      isBuyOut = ((long)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_BUY);
      etOut = HistoryDealGetDouble(dk, DEAL_PRICE);
      return true;
   }
   return false;
}

bool TG_GetSLTPForEntryDeal(ulong dealId, double &slOut, double &tpOut)
{
   slOut = tpOut = 0.0;
   double ds = HistoryDealGetDouble(dealId, DEAL_SL);
   double dt = HistoryDealGetDouble(dealId, DEAL_TP);
   if (ds > 0.0 || dt > 0.0)
   {
      slOut = ds;
      tpOut = dt;
      return true;
   }
   ulong otk = (ulong)HistoryDealGetInteger(dealId, DEAL_ORDER);
   if (otk > 0 && HistoryOrderSelect(otk))
   {
      slOut = HistoryOrderGetDouble(otk, ORDER_SL);
      tpOut = HistoryOrderGetDouble(otk, ORDER_TP);
      if (slOut > 0.0 || tpOut > 0.0)
         return true;
   }
   return false;
}

void TG_SendTP(bool isBuyEntry, bool wasLimit, double et, long dealId)
{
   string key = wasLimit ? "TP_LIM" : "TP_MKT";
   if (TG_Sent(key, dealId))
      return;
   TG_Send("TP hit | " + SideText(isBuyEntry) + (wasLimit ? " LIMIT" : " NOW") + "\nET  " + TG_P(et));
   TG_Mark(key, dealId);
}

void TG_SendSL(bool isBuyEntry, bool wasLimit, double et, long dealId)
{
   string key = wasLimit ? "SL_LIM" : "SL_MKT";
   if (TG_Sent(key, dealId))
      return;
   TG_Send("SL hit | " + SideText(isBuyEntry) + (wasLimit ? " LIMIT" : " NOW") + "\nET  " + TG_P(et));
   TG_Mark(key, dealId);
}

//=================== OnTradeTransaction ===============================
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest &r,
                        const MqlTradeResult &res)
{
   if (t.symbol != _Symbol)
      return;

   //--- Pending placed
   if (t.type == TRADE_TRANSACTION_ORDER_ADD)
   {
      ulong oid = t.order;
      if (oid == 0 || !OrderSelect(oid))
         return;
      long magic = (long)OrderGetInteger(ORDER_MAGIC);
      if (!TG_IncludeManual && magic != MagicNumber)
         return;
      if (TG_IncludeManual && magic != MagicNumber && magic != 0)
         return;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
         TG_SendPendingLimit(ot == ORDER_TYPE_BUY_LIMIT,
                             OrderGetDouble(ORDER_PRICE_OPEN),
                             OrderGetDouble(ORDER_SL),
                             OrderGetDouble(ORDER_TP), (long)oid);
      return;
   }

   //--- Deal added
   if (t.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong did = t.deal;
      if (did == 0 || !TG_SelectDealSafe(did))
         return;
      if (HistoryDealGetString(did, DEAL_SYMBOL) != _Symbol)
         return;
      long magic = (long)HistoryDealGetInteger(did, DEAL_MAGIC);
      if (!TG_IncludeManual && magic != MagicNumber)
         return;
      if (TG_IncludeManual && magic != MagicNumber && magic != 0)
         return;

      long dentry = (long)HistoryDealGetInteger(did, DEAL_ENTRY);
      long reason = (long)HistoryDealGetInteger(did, DEAL_REASON);
      bool isBuy = ((long)HistoryDealGetInteger(did, DEAL_TYPE) == DEAL_TYPE_BUY);

      //--- FILLED → mark used + TG
      if (dentry == DEAL_ENTRY_IN)
      {
         if (isBuy && activeBuyLineIdx >= 0)
         {
            MarkZoneUsed(true, activeBuyLineIdx);
            activeBuyLineIdx = -1;
         }
         if (!isBuy && activeSellLineIdx >= 0)
         {
            MarkZoneUsed(false, activeSellLineIdx);
            activeSellLineIdx = -1;
         }

         double et = HistoryDealGetDouble(did, DEAL_PRICE);
         double sl = 0, tp = 0;
         TG_GetSLTPForEntryDeal(did, sl, tp);
         bool wm = false, wl = false;
         TG_GetFillOrigin(did, wm, wl);
         string msg = (isBuy ? (wl ? "BUY LIMIT FILLED" : "BUY NOW")
                             : (wl ? "SELL LIMIT FILLED" : "SELL NOW")) +
                      "\nET  " + TG_P(et) + "\nSL  " + TG_P(sl) + "\nTP  " + TG_P(tp);
         TG_Send(msg);
         return;
      }

      //--- EXIT
      if (dentry == DEAL_ENTRY_OUT || dentry == DEAL_ENTRY_OUT_BY)
      {
         long posId = (long)HistoryDealGetInteger(did, DEAL_POSITION_ID);
         double et = 0.0;
         bool buyEntry = true;
         TG_GetEntryPriceFromPositionHistory(posId, et, buyEntry);
         bool wm = false, wl = false;
         TG_GetFillOrigin(did, wm, wl);
         if (reason == DEAL_REASON_TP)
            TG_SendTP(buyEntry, wl, et, (long)did);
         else if (reason == DEAL_REASON_SL)
            TG_SendSL(buyEntry, wl, et, (long)did);
      }
   }
}

//=================== INIT / DEINIT / TICK ===============================
int OnInit()
{
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   LoadZoneUsedFromFile();
   LoadPriceZones();
   ResetSessionDDIfNeeded();

   activeBuyLineIdx = -1;
   activeSellLineIdx = -1;

   PrintFormat("[INIT] Line Entry | %s %s | Buy=%d Sell=%d",
               _Symbol, EnumToString(_Period), totalBuyZones, totalSellZones);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   SaveZoneUsedToFile();
   PrintFormat("[DEINIT] Saved %d zone records (reason=%d)", totalUsedZones, reason);
}

void OnTick()
{
   SyncZoneState();
   UpdateSessionDDGate();
   UpdateSessionProfitGate();
   // CancelPendingIfTPHit();
   EnforceForbiddenZone();
   ManageLineOrders();
   ManageBreakEven();
   UpdateChartComment();
}