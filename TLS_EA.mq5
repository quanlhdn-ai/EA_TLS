//+------------------------------------------------------------------+
//|                                                   TLS_IFVG.mq5  |
//|                    IFVG Zone Entry EA  v2.00                     |
//|                                                                  |
//|  STRATEGY:                                                       |
//|  - Read IFVG buffers from IFVG indicator                        |
//|  - If new IFVG BUY appears AND midpoint inside a BUY price zone |
//|    -> BUY NOW at market                                          |
//|  - If new IFVG SELL appears AND midpoint inside a SELL zone     |
//|    -> SELL NOW at market                                         |
//|  - SL (BUY)  = zone_bottom - ZoneSLBufferPips                   |
//|  - SL (SELL) = zone_top    + ZoneSLBufferPips                   |
//|  - TP = RiskReward * Risk distance                              |
//|  - Each price zone fires only once (MarkZoneUsed)               |
//|  - BE: move SL to entry when profit >= R - BufferPips           |
//+------------------------------------------------------------------+
#property copyright "TLS_IFVG EA"
#property version "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//=========================== DEFINES ================================
#define ZONE_USED_FILE "TLS_IFVG_ZoneUsed.dat"

//=========================== STRUCTS ================================
struct ZoneUsedRecord
{
   bool isBuy;
   double zonePrice;
   datetime usedTime;
};

ZoneUsedRecord usedZones[];
int totalUsedZones = 0;

//=========================== INPUTS =================================
// Telegram
input bool EnableTelegram = true;
input string TG_BotToken = "YOUR_TOKEN";
input string TG_ChatID = "YOUR_CHAT_ID";
input bool TG_IncludeManual = false;

// IFVG Indicator
input string IFVGIndicatorName = "IFVG";
input int IFVGLookback = 300;
input color IFVGBuyColor = C'13,186,186';
input color IFVGSellColor = C'220,50,50';
input int IFVGAlpha = 55;
input int IFVGExtendBars = 30;
input int scanBarsOnSignalCheck = 5;

// Display
input bool IsShowChartComment = true;

// DD tracking
input double DailyDD_Percent = 3.0;
datetime sessionStartTime    = 0;
double   sessionStartBalance = 0.0;
double   sessionLossLimit    = 0.0;
bool     ddBlocked           = false;
double   lastSessionRealizedPnL = 0.0;

// Risk
input double RiskUSDPerTrade = 100.0; // Risk per trade in USD
input double RiskReward = 2.0;        // TP = RiskReward * Risk
input int SlippagePoints = 30;
input long MagicNumber = 8386272000;

// Break Even
input bool IsAllowBE = true;
input int BufferPips = 5;

// Price Zone Filter
input int ZoneActivationPips = 100;
input int ZoneSLBufferPips = 300;

// BUY Zones (center price)
input double BuyZone1 = 0.0;
input double BuyZone2 = 0.0;
input double BuyZone3 = 0.0;
input double BuyZone4 = 0.0;
input double BuyZone5 = 0.0;
input double BuyZone6 = 0.0;
input double BuyZone7 = 0.0;
input double BuyZone8 = 0.0;
input double BuyZone9 = 0.0;
input double BuyZone10 = 0.0;

// SELL Zones (center price)
input double SellZone1 = 0.0;
input double SellZone2 = 0.0;
input double SellZone3 = 0.0;
input double SellZone4 = 0.0;
input double SellZone5 = 0.0;
input double SellZone6 = 0.0;
input double SellZone7 = 0.0;
input double SellZone8 = 0.0;
input double SellZone9 = 0.0;
input double SellZone10 = 0.0;

//=========================== GLOBALS ================================
int ifvgHandle = INVALID_HANDLE;

double buyZones[];
double sellZones[];
bool buyZonesUsed[];
bool sellZonesUsed[];
int totalBuyZones = 0;
int totalSellZones = 0;

datetime lastBarTime = 0;

// Prevent re-firing on same bar
datetime lastBuySignalTime = 0;
datetime lastSellSignalTime = 0;

//=========================== UTILS ==================================
double PipSize()
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
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
   double pipValuePer1Lot = tickValue * (pip / tickSize);
   if (pipValuePer1Lot <= 0.0)
      return 0.0;
   return NormalizeVolume(RiskUSDPerTrade / (slPips * pipValuePer1Lot));
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

//=========================== ZONE USED FILE =========================
void LoadZoneUsedFromFile()
{
   ArrayResize(usedZones, 0);
   totalUsedZones = 0;
   int h = FileOpen(ZONE_USED_FILE, FILE_READ | FILE_BIN);
   if (h == INVALID_HANDLE)
      return;
   while (!FileIsEnding(h))
   {
      ZoneUsedRecord rec;
      rec.isBuy = (bool)FileReadInteger(h);
      rec.zonePrice = FileReadDouble(h);
      rec.usedTime = (datetime)FileReadLong(h);
      if (rec.zonePrice <= 0)
         break;
      ArrayResize(usedZones, totalUsedZones + 1);
      usedZones[totalUsedZones++] = rec;
   }
   FileClose(h);
   PrintFormat("[ZONE_USED] Loaded %d records", totalUsedZones);
}

void SaveZoneUsedToFile()
{
   int h = FileOpen(ZONE_USED_FILE, FILE_WRITE | FILE_BIN);
   if (h == INVALID_HANDLE)
      return;
   for (int i = 0; i < totalUsedZones; i++)
   {
      FileWriteInteger(h, (int)usedZones[i].isBuy);
      FileWriteDouble(h, usedZones[i].zonePrice);
      FileWriteLong(h, (long)usedZones[i].usedTime);
   }
   FileClose(h);
}

bool IsZoneUsedFromFile(bool isBuy, double zonePrice)
{
   for (int i = 0; i < totalUsedZones; i++)
      if (usedZones[i].isBuy == isBuy && MathAbs(usedZones[i].zonePrice - zonePrice) < 0.1)
         return true;
   return false;
}

void MarkZoneUsed(bool isBuy, double zonePrice)
{
   int total = isBuy ? totalBuyZones : totalSellZones;
   for (int i = 0; i < total; i++)
   {
      double z = isBuy ? buyZones[i] : sellZones[i];
      if (MathAbs(z - zonePrice) >= 0.1)
         continue;

      if (isBuy)
         buyZonesUsed[i] = true;
      else
         sellZonesUsed[i] = true;

      ZoneUsedRecord rec;
      rec.isBuy = isBuy;
      rec.zonePrice = zonePrice;
      rec.usedTime = TimeCurrent();
      ArrayResize(usedZones, totalUsedZones + 1);
      usedZones[totalUsedZones++] = rec;
      SaveZoneUsedToFile();

      PrintFormat("[ZONE] %s zone MARKED USED: %.*f", SideText(isBuy), _Digits, zonePrice);
      break;
   }
}

//=========================== LOAD ZONES =============================
void LoadPriceZones()
{
   ArrayResize(buyZones, 0);
   totalBuyZones = 0;
   ArrayResize(sellZones, 0);
   totalSellZones = 0;

   double tempBuy[10] = {BuyZone1, BuyZone2, BuyZone3, BuyZone4, BuyZone5,
                         BuyZone6, BuyZone7, BuyZone8, BuyZone9, BuyZone10};
   double tempSell[10] = {SellZone1, SellZone2, SellZone3, SellZone4, SellZone5,
                          SellZone6, SellZone7, SellZone8, SellZone9, SellZone10};

   for (int i = 0; i < 10; i++)
      if (tempBuy[i] > 0.0)
      {
         ArrayResize(buyZones, totalBuyZones + 1);
         buyZones[totalBuyZones++] = NormalizePrice(tempBuy[i]);
      }
   for (int i = 0; i < 10; i++)
      if (tempSell[i] > 0.0)
      {
         ArrayResize(sellZones, totalSellZones + 1);
         sellZones[totalSellZones++] = NormalizePrice(tempSell[i]);
      }

   ArrayResize(buyZonesUsed, totalBuyZones);
   ArrayResize(sellZonesUsed, totalSellZones);
   ArrayFill(buyZonesUsed, 0, totalBuyZones, false);
   ArrayFill(sellZonesUsed, 0, totalSellZones, false);

   for (int i = 0; i < totalBuyZones; i++)
      if (IsZoneUsedFromFile(true, buyZones[i]))
         buyZonesUsed[i] = true;
   for (int i = 0; i < totalSellZones; i++)
      if (IsZoneUsedFromFile(false, sellZones[i]))
         sellZonesUsed[i] = true;

   PrintFormat("[ZONE] Loaded %d BUY zones, %d SELL zones", totalBuyZones, totalSellZones);
}

//=========================== ZONE HELPERS ===========================
// Returns index of zone whose range [center-half, center+half] contains price
// Returns -1 if none found or already used
int FindZoneForPrice(bool isBuy, double price)
{
   double pip = PipSize();
   double halfWidth = ZoneActivationPips * pip;
   int total = isBuy ? totalBuyZones : totalSellZones;

   for (int i = 0; i < total; i++)
   {
      if (isBuy && buyZonesUsed[i])
         continue;
      if (!isBuy && sellZonesUsed[i])
         continue;

      double center = isBuy ? buyZones[i] : sellZones[i];
      if (price >= center - halfWidth && price <= center + halfWidth)
         return i;
   }
   return -1;
}

double GetZoneBottom(bool isBuy, int idx)
{
   double pip = PipSize();
   double center = isBuy ? buyZones[idx] : sellZones[idx];
   return center - ZoneActivationPips * pip;
}

double GetZoneTop(bool isBuy, int idx)
{
   double pip = PipSize();
   double center = isBuy ? buyZones[idx] : sellZones[idx];
   return center + ZoneActivationPips * pip;
}

//=========================== DD / PROFIT ============================
bool GetCurrentSymbolSessionWindow(datetime now, datetime &sOut, datetime &eOut)
{
   sOut = 0;
   eOut = 0;

   MqlDateTime t;
   TimeToStruct(now, t);
   int dow = t.day_of_week;

   for(int idx = 0; idx < 10; idx++)
   {
      datetime from = 0, to = 0;
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to))
         break;
      if(from == 0 && to == 0)
         continue;

      MqlDateTime s = t, e = t;
      MqlDateTime tf, tt;
      TimeToStruct(from, tf);
      TimeToStruct(to,   tt);

      s.hour = tf.hour; s.min = tf.min; s.sec = 0;
      e.hour = tt.hour; e.min = tt.min; e.sec = 0;

      datetime s0 = StructToTime(s);
      datetime e0 = StructToTime(e);

      if(e0 <= s0)
         e0 += 24 * 60 * 60;

      // overnight session adjustment
      if(now < s0 && (e0 - s0) > 6 * 60 * 60)
      {
         s0 -= 24 * 60 * 60;
         e0 -= 24 * 60 * 60;
      }

      if(now >= s0 && now < e0)
      {
         sOut = s0;
         eOut = e0;
         return true;
      }
   }
   return false;
}

double RealizedPnLInRange(datetime fromTime, datetime toTime)
{
   if (!HistorySelect(fromTime, toTime))
      return 0.0;
   double pnl = 0.0;
   int deals = (int)HistoryDealsTotal();
   for (int i = 0; i < deals; i++)
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
   datetime now = TimeCurrent();
   datetime s   = 0, e = 0;

   if(!GetCurrentSymbolSessionWindow(now, s, e))
      return;

   if(sessionStartTime == 0 || s != sessionStartTime)
   {
      sessionStartTime    = s;
      sessionStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      sessionLossLimit    = sessionStartBalance * (DailyDD_Percent / 100.0);
      ddBlocked           = false;
      lastSessionRealizedPnL = 0.0;

      double pnl  = RealizedPnLInRange(sessionStartTime, TimeCurrent());
      lastSessionRealizedPnL = pnl;
      double loss = (pnl < 0.0) ? -pnl : 0.0;
      if((loss >= sessionLossLimit) || ((loss + RiskUSDPerTrade) > sessionLossLimit))
         ddBlocked = true;
   }
}

void UpdateSessionDDGate()
{
   if(ddBlocked) return;

   ResetSessionDDIfNeeded();
   if(sessionStartTime == 0) return;

   double pnl  = RealizedPnLInRange(sessionStartTime, TimeCurrent());
   lastSessionRealizedPnL = pnl;
   double loss = (pnl < 0.0) ? -pnl : 0.0;
   if((loss >= sessionLossLimit) || ((loss + RiskUSDPerTrade) > sessionLossLimit))
      ddBlocked = true;
}

//=========================== BREAK EVEN ============================
// BUY:  when bid - entry >= R - BufferPips  → move SL to entry
// SELL: when entry - ask >= R - BufferPips  → move SL to entry
void ManageBreakEven()
{
   if (!IsAllowBE)
      return;

   double pip = PipSize();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
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
         if ((bid - entry) >= threshold && sl < entry)
         {
            trade.PositionModify(tk, entry, tp);
            PrintFormat("[BE][BUY] SL moved to entry=%.*f | bid=%.*f profit_pips=%.1f",
                        _Digits, entry, _Digits, bid, (bid - entry) / pip);
         }
      }
      else
      {
         if ((entry - ask) >= threshold && sl > entry)
         {
            trade.PositionModify(tk, entry, tp);
            PrintFormat("[BE][SELL] SL moved to entry=%.*f | ask=%.*f profit_pips=%.1f",
                        _Digits, entry, _Digits, ask, (entry - ask) / pip);
         }
      }
   }
}

//=========================== EXECUTE ENTRY ==========================
bool ExecuteEntry(bool isBuy, int zoneIdx)
{
   if (ddBlocked)
   {
      PrintFormat("[SKIP][%s] DD blocked", SideText(isBuy));
      return false;
   }

   double pip = PipSize();

   // SL = zone edge + buffer
   double sl;
   if (isBuy)
      sl = NormalizePrice(GetZoneBottom(true, zoneIdx) - ZoneSLBufferPips * pip);
   else
      sl = NormalizePrice(GetZoneTop(false, zoneIdx) + ZoneSLBufferPips * pip);

   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entry = NormalizePrice(entry);

   if (isBuy && sl >= entry)
   {
      PrintFormat("[SKIP][BUY] SL >= entry | entry=%.*f sl=%.*f", _Digits, entry, _Digits, sl);
      return false;
   }
   if (!isBuy && sl <= entry)
   {
      PrintFormat("[SKIP][SELL] SL <= entry | entry=%.*f sl=%.*f", _Digits, entry, _Digits, sl);
      return false;
   }

   double riskDist = isBuy ? (entry - sl) : (sl - entry);
   if (riskDist <= 0)
      return false;

   double lots = CalcLotsByRiskUSD(entry, sl);
   if (lots <= 0)
   {
      PrintFormat("[SKIP][%s] lots=0", SideText(isBuy));
      return false;
   }

   double tp;
   tp = isBuy ? NormalizePrice(entry + RiskReward * riskDist)
              : NormalizePrice(entry - RiskReward * riskDist);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "IFVG BUY")
                   : trade.Sell(lots, _Symbol, 0.0, sl, tp, "IFVG SELL");

   if (ok)
   {
      double filled = trade.ResultPrice();
      PrintFormat("[ORDER][%s] MARKET | Entry=%.*f Lots=%.2f SL=%.*f TP=%.*f",
                  SideText(isBuy), _Digits, filled, lots, _Digits, sl, _Digits, tp);

      double zoneCenter = isBuy ? buyZones[zoneIdx] : sellZones[zoneIdx];
      MarkZoneUsed(isBuy, zoneCenter);
      TG_SendOpenMarket(isBuy, filled, sl, tp, (long)trade.ResultDeal());
   }
   else
   {
      PrintFormat("[FAIL][%s] ret=%d %s", SideText(isBuy),
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   return ok;
}

//=========================== IFVG SIGNAL CHECK ======================
// Called on new bar. Reads IFVG buffers at bar 1 (just closed).
// Buffer 0 = BuyTop, 1 = BuyBot, 2 = SellTop, 3 = SellBot
void CheckIFVGSignals()
{
   if (ifvgHandle == INVALID_HANDLE)
      return;

   double buyTop[], buyBot[], sellTop[], sellBot[];
   if (CopyBuffer(ifvgHandle, 0, 1, scanBarsOnSignalCheck, buyTop) != scanBarsOnSignalCheck)
      return;
   if (CopyBuffer(ifvgHandle, 1, 1, scanBarsOnSignalCheck, buyBot) != scanBarsOnSignalCheck)
      return;
   if (CopyBuffer(ifvgHandle, 2, 1, scanBarsOnSignalCheck, sellTop) != scanBarsOnSignalCheck)
      return;
   if (CopyBuffer(ifvgHandle, 3, 1, scanBarsOnSignalCheck, sellBot) != scanBarsOnSignalCheck)
      return;

   // BUY
   for (int i = 0; i < scanBarsOnSignalCheck; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i + 1);
      if (buyTop[i] <= 0 || buyTop[i] == EMPTY_VALUE)
         continue;
      if (barTime == lastBuySignalTime)
         continue;

      double midpoint = (buyTop[i] + buyBot[i]) / 2.0;
      int zoneIdx = FindZoneForPrice(true, midpoint);

      PrintFormat("[IFVG][BUY] bar=%d | Top=%.*f Bot=%.*f Mid=%.*f ZoneIdx=%d",
                  i + 1, _Digits, buyTop[i], _Digits, buyBot[i], _Digits, midpoint, zoneIdx);

      if (zoneIdx >= 0)
      {
         lastBuySignalTime = barTime;
         ExecuteEntry(true, zoneIdx);
         break;
      }
   }

   // SELL
   for (int i = 0; i < scanBarsOnSignalCheck; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i + 1);
      if (sellTop[i] <= 0 || sellTop[i] == EMPTY_VALUE)
         continue;
      if (barTime == lastSellSignalTime)
         continue;

      double midpoint = (sellTop[i] + sellBot[i]) / 2.0;
      int zoneIdx = FindZoneForPrice(false, midpoint);

      PrintFormat("[IFVG][SELL] bar=%d | Top=%.*f Bot=%.*f Mid=%.*f ZoneIdx=%d",
                  i + 1, _Digits, sellTop[i], _Digits, sellBot[i], _Digits, midpoint, zoneIdx);

      if (zoneIdx >= 0)
      {
         lastSellSignalTime = barTime;
         ExecuteEntry(false, zoneIdx);
         break;
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

   string txt = "";
   txt += "IFVG Handle  : " + (ifvgHandle != INVALID_HANDLE ? "OK" : "FAIL") + "\n";
   txt += "DD Blocked   : " + (ddBlocked ? "YES" : "NO") + "\n";
   txt += "PnL (today)  : " + DoubleToString(lastSessionRealizedPnL, 2) + "\n";
   txt += "DD Limit     : -" + DoubleToString(sessionLossLimit, 2) + "\n";
   txt += "-----------------------------------------\n";

   double pip = PipSize();
   for (int i = 0; i < totalBuyZones; i++)
   {
      string used = buyZonesUsed[i] ? " [USED]" : "";
      double zFrom = buyZones[i] - ZoneActivationPips * pip;
      double zTo = buyZones[i] + ZoneActivationPips * pip;
      txt += "[BUY  " + IntegerToString(i + 1) + "] " +
             DoubleToString(buyZones[i], _Digits) +
             "  [" + DoubleToString(zFrom, _Digits) + " - " + DoubleToString(zTo, _Digits) + "]" +
             used + "\n";
   }
   for (int i = 0; i < totalSellZones; i++)
   {
      string used = sellZonesUsed[i] ? " [USED]" : "";
      double zFrom = sellZones[i] - ZoneActivationPips * pip;
      double zTo = sellZones[i] + ZoneActivationPips * pip;
      txt += "[SELL " + IntegerToString(i + 1) + "] " +
             DoubleToString(sellZones[i], _Digits) +
             "  [" + DoubleToString(zFrom, _Digits) + " - " + DoubleToString(zTo, _Digits) + "]" +
             used + "\n";
   }

   Comment(txt);
}

//=========================== TELEGRAM ===============================
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
   WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, data, result, rh);
}

string TG_Key(const string kind, long id)
{
   return "TLS_IFVG_TG_" + _Symbol + "_" + (string)(int)_Period + "_" + kind + "_" + (string)id;
}
bool TG_Sent(const string kind, long id) { return GlobalVariableCheck(TG_Key(kind, id)); }
void TG_Mark(const string kind, long id) { GlobalVariableSet(TG_Key(kind, id), (double)TimeCurrent()); }
string TG_P(double v) { return DoubleToString(v, _Digits); }

bool TG_SelectDealSafe(ulong dealId)
{
   for (int i = 0; i < 10; i++)
   {
      datetime to = TimeCurrent(), from = to - 86400 * 30;
      HistorySelect(from, to);
      if (HistoryDealSelect(dealId))
         return true;
      Sleep(50);
   }
   return false;
}

void TG_SendOpenMarket(bool isBuy, double et, double sl, double tp, long uid)
{
   if (TG_Sent("OPEN_MKT", uid))
      return;
   TG_Send(string(isBuy ? "BUY NOW" : "SELL NOW") +
           "\nET  " + TG_P(et) + "\nSL  " + TG_P(sl) + "\nTP  " + TG_P(tp));
   TG_Mark("OPEN_MKT", uid);
}

void TG_SendTP(bool isBuyEntry, double et, long dealId)
{
   if (TG_Sent("TP_MKT", dealId))
      return;
   TG_Send("TP hit with " + string(isBuyEntry ? "BUY" : "SELL") + " NOW\nET = " + TG_P(et));
   TG_Mark("TP_MKT", dealId);
}

void TG_SendSL(bool isBuyEntry, double et, long dealId)
{
   if (TG_Sent("SL_MKT", dealId))
      return;
   TG_Send("SL hit with " + string(isBuyEntry ? "BUY" : "SELL") + " NOW\nET = " + TG_P(et));
   TG_Mark("SL_MKT", dealId);
}

bool TG_GetEntryFromHistory(long positionId, double &etOut, bool &isBuyOut)
{
   etOut = 0.0;
   isBuyOut = true;
   datetime to = TimeCurrent(), from = to - 86400 * 30;
   if (!HistorySelect(from, to))
      return false;
   int deals = (int)HistoryDealsTotal();
   for (int i = deals - 1; i >= 0; i--)
   {
      ulong dk = HistoryDealGetTicket(i);
      if (dk == 0)
         continue;
      if (HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol)
         continue;
      long magic = (long)HistoryDealGetInteger(dk, DEAL_MAGIC);
      if (!TG_IncludeManual && magic != MagicNumber)
         continue;
      if ((long)HistoryDealGetInteger(dk, DEAL_POSITION_ID) != positionId)
         continue;
      if (HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      isBuyOut = (HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_BUY);
      etOut = HistoryDealGetDouble(dk, DEAL_PRICE);
      return true;
   }
   return false;
}

//=========================== TRADE TRANSACTION ======================
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest &r,
                        const MqlTradeResult &res)
{
   if (t.symbol != _Symbol)
      return;
   if (t.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealId = t.deal;
   if (dealId == 0)
      return;
   if (!TG_SelectDealSafe(dealId))
      return;
   if (HistoryDealGetString(dealId, DEAL_SYMBOL) != _Symbol)
      return;

   long magic = (long)HistoryDealGetInteger(dealId, DEAL_MAGIC);
   if (!TG_IncludeManual && magic != MagicNumber)
      return;

   long entry = (long)HistoryDealGetInteger(dealId, DEAL_ENTRY);
   long reason = (long)HistoryDealGetInteger(dealId, DEAL_REASON);

   if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      long posId = (long)HistoryDealGetInteger(dealId, DEAL_POSITION_ID);
      double et = 0.0;
      bool isBuyEntry = true;
      TG_GetEntryFromHistory(posId, et, isBuyEntry);

      if (reason == DEAL_REASON_TP)
         TG_SendTP(isBuyEntry, et, (long)dealId);
      else if (reason == DEAL_REASON_SL)
         TG_SendSL(isBuyEntry, et, (long)dealId);
   }
}

//=========================== INIT / DEINIT ==========================
int OnInit()
{
   ifvgHandle = iCustom(_Symbol, _Period, IFVGIndicatorName,
                        IFVGLookback, IFVGBuyColor, IFVGSellColor,
                        IFVGAlpha, IFVGExtendBars);
   if (ifvgHandle == INVALID_HANDLE)
   {
      PrintFormat("[INIT] FAILED to load IFVG indicator '%s' err=%d", IFVGIndicatorName, GetLastError());
      return INIT_FAILED;
   }
   PrintFormat("[INIT] IFVG handle=%d", ifvgHandle);

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   LoadZoneUsedFromFile();
   LoadPriceZones();
   ResetSessionDDIfNeeded();

   lastBuySignalTime = iTime(_Symbol, _Period, 1);
   lastSellSignalTime = iTime(_Symbol, _Period, 1);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   SaveZoneUsedToFile();
   if (ifvgHandle != INVALID_HANDLE)
      IndicatorRelease(ifvgHandle);
}

//=========================== TICK ===================================
void OnTick()
{
   ManageBreakEven();
   
   if (!IsNewBar())
   return;
   UpdateSessionDDGate();
   UpdateChartComment();
   CheckIFVGSignals();
}