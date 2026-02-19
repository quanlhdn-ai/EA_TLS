#property strict
#include <Trade/Trade.mqh>
CTrade trade;

#define ZONE_USED_FILE "TLS_ZoneUsed.dat"
#define LINE_USED_FILE "TLS_LineUsed.dat"

struct ZoneUsedRecord
{
   bool  isBuy;
   double zonePrice;
   datetime usedTime;
};

ZoneUsedRecord usedZones[];
int totalUsedZones = 0;
struct LineUsedRecord
{
   datetime regimeEpoch;
   long lineKey; 
   bool isBuy; 
   datetime usedTime;
};

LineUsedRecord usedLines[];
int totalUsedLines = 0;

//------------------------- Inputs ----------------------------------
input string HAIndicatorName = "TLS_HA";
input string EMAIndicatorName = "TLS_EMA";

// iCustom inputs must match indicator inputs
input color BullColor = C'8,153,129';
input color BearColor = C'242,54,69';

input int EMAShortPeriod = 10;
input int EMALongPeriod = 39;
input ENUM_MA_METHOD EMAMethod = MODE_EMA;

input int SlippagePoints = 30;
input long MagicNumber = 8386272000; // Magic number

// Risk & SL/BE rules
input bool IsAllowBE = true;
input double RiskUSDPerTrade = 100.0; // risk per trade in USD
input int BufferPips = 5;            // SL buffer from HA pair in PIPS
input double SLMaxPips = 500.0;
input int SL_LookbackBars = 500;     // lookback to find nearest HA pair
input double RiskReward = 2.0;       // TP = RiskReward * Risk (R)
input double RangeChannelEMA = 10.0; // distance between HighLine and LowLine in PIPS minimum

//=========================== DD (SESSION, REALIZED) ==================
input double HTF_TP_Prices = 100.0; // HTF_TP
input double DailyDD_Percent = 3.0;
input bool IsCancelPendingsWhenDDHit = true;

// buffer->scan lookback for lines
input int LineScanLookbackBars = 300;

// Cross scan for auto-arm/comment
input int CrossScanLookbackBars = 500;

//=========================== SESSION (BROKER MARKET HOURS) =========
input double NoNewTradesBeforeEndH = 0.1; // forbidden when <= this many hours to session end
input int SessionForceThrottleSec = 120;  // throttle forced cancel/close (seconds)

//=========================== TRADE WINDOW MODE (FULLDAY vs SESSIONS) ========
enum ENUM_TRADE_WINDOW_MODE
{
   TRADEWINDOW_FULLDAY = 0, // FULLDAY
   TRADEWINDOW_SESSIONS = 1 // SESSION
};
input ENUM_TRADE_WINDOW_MODE TradeWindowMode = TRADEWINDOW_FULLDAY;

// Enable each VN session
input bool IsAllowAsia = true;
input bool IsAllowEU = true;
input bool IsAllowNY = true;

// VN session times - hours/minutes
// Asia 08:00-11:00, EU 14:00-18:00, NY 21:00-00:00 (overnight)
input int AsiaStartHour = 8;
input int AsiaStartMin = 0;
input int AsiaEndHour = 11;
input int AsiaEndMin = 0;

input int EUStartHour = 14;
input int EUStartMin = 0;
input int EUEndHour = 18;
input int EUEndMin = 0;

input int NYStartHour = 21;
input int NYStartMin = 0;
input int NYEndHour = 0;
input int NYEndMin = 0;

// Time conversion (server -> VN). IMPORTANT: set broker server offset correctly.
input int VNOffsetFromUTC = 7;
input int ServerOffsetFromUTC = 0;

//=========================== PROFIT TARGET (SESSION, REALIZED) ======
input double DailyProfitTargetUSD = 0.0;
input bool IsForceCloseWhenProfitHit = false;
input bool IsCancelPendingsWhenProfitHit = true;

bool profitBlocked = false;
double sessionProfitTarget = 0.0;

// Chart comment
input bool IsShowChartComment = true;

// Debug
input bool IsDebugOnce = true;

//------------------------- Indicator handles ------------------------
int haHandle = INVALID_HANDLE;
int emaHandle = INVALID_HANDLE;

//======================== PRICE ZONE FILTER =============================
input bool EnablePriceZoneFilter = true;  
input int ZoneActivationPips = 10;
input bool UseSLFromZone   = true;
input int  ZoneSLBufferPips = 30;       

// Buy Zones
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

// Sell Zones
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

double buyZones[];  
double sellZones[];
bool buyZonesUsed[];
bool sellZonesUsed[];
int totalBuyZones = 0;
int totalSellZones = 0;

datetime lastBuyZoneHitTime = 0;
double lastBuyZoneHitPrice = 0.0;
datetime lastSellZoneHitTime = 0;
double lastSellZoneHitPrice = 0.0;

bool buyZoneActivated = false;
bool sellZoneActivated = false;
bool armPendingDeferred = false;

datetime lastBarTime = 0;

// session DD tracking
datetime sessionStartTime = 0;
datetime sessionEndTime = 0;
double sessionStartBalance = 0.0;
double sessionLossLimit = 0.0;
bool ddBlocked = false;
double lastSessionRealizedPnL = 0.0;

// session enforcement throttle
datetime lastSessionForceActionTime = 0;
datetime lastKnownSessionEnd = 0;

// waiting state (armed by cross)
bool waitingBUY = false;
bool waitingSELL = false;

// For comment only
long lastUsedHighKey = 0;
long lastUsedLowKey = 0;
int lastHaBars = 0;
int lastEmaBars = 0;
string currentCrossText = "None"; // "Cross Up" / "Cross Down" / "Cross" / "None"
double currentCrossPrice = 0.0;
datetime currentCrossTime = 0;

//=================== REGIME (one setup per regime) ==================
datetime currentRegimeEpoch = 0;

//============================== UTILS ==============================
void LoadZoneUsedFromFile()
{
   ArrayResize(usedZones, 0);
   totalUsedZones = 0;

   int handle = FileOpen(ZONE_USED_FILE, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("[ZONE_USED] No existing file, starting fresh");
      return;
   }

   while(!FileIsEnding(handle))
   {
      ZoneUsedRecord rec;
      rec.isBuy      = (bool)FileReadInteger(handle);
      rec.zonePrice  = FileReadDouble(handle);
      rec.usedTime   = (datetime)FileReadLong(handle);

      if(rec.zonePrice <= 0)
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
   if(handle == INVALID_HANDLE)
   {
      Print("[ZONE_USED] ERROR: Cannot save to file, error: ", GetLastError());
      return;
   }

   for(int i = 0; i < totalUsedZones; i++)
   {
      FileWriteInteger(handle, (int)usedZones[i].isBuy);
      FileWriteDouble(handle, usedZones[i].zonePrice);
      FileWriteLong(handle, (long)usedZones[i].usedTime);
   }

   FileClose(handle);
   PrintFormat("[ZONE_USED] Saved %d records to file", totalUsedZones);
}

bool IsZoneUsedFromFile(bool isBuy, double zonePrice)
{
   for(int i = 0; i < totalUsedZones; i++)
   {
      if(usedZones[i].isBuy == isBuy &&
         MathAbs(usedZones[i].zonePrice - zonePrice) < 0.1)
         return true;
   }
   return false;
}

void LoadPriceZones()
{
   ArrayResize(buyZones, 0);
   ArrayResize(sellZones, 0);
   totalBuyZones = 0;
   totalSellZones = 0;
   
   double tempBuyZones[10] = {
      BuyZone1, BuyZone2, BuyZone3, BuyZone4, BuyZone5,
      BuyZone6, BuyZone7, BuyZone8, BuyZone9, BuyZone10
   };
   
   double tempSellZones[10] = {
      SellZone1, SellZone2, SellZone3, SellZone4, SellZone5,
      SellZone6, SellZone7, SellZone8, SellZone9, SellZone10
   };
   
   for(int i = 0; i < 10; i++)
   {
      if(tempBuyZones[i] > 0.0)
      {
         ArrayResize(buyZones, totalBuyZones + 1);
         buyZones[totalBuyZones] = NormalizePrice(tempBuyZones[i]);
         totalBuyZones++;
      }
   }
   
   for(int i = 0; i < 10; i++)
   {
      if(tempSellZones[i] > 0.0)
      {
         ArrayResize(sellZones, totalSellZones + 1);
         sellZones[totalSellZones] = NormalizePrice(tempSellZones[i]);
         totalSellZones++;
      }
   }
   
   ArraySort(buyZones);
   ArraySort(sellZones);
   
   // ========== INIT USED ARRAYS ==========
   ArrayResize(buyZonesUsed, totalBuyZones);
   ArrayResize(sellZonesUsed, totalSellZones);
   ArrayFill(buyZonesUsed, 0, totalBuyZones, false);
   ArrayFill(sellZonesUsed, 0, totalSellZones, false);
   
   // ========== RESTORE USED STATE FROM FILE ==========
   for(int i = 0; i < totalBuyZones; i++)
   {
      if(IsZoneUsedFromFile(true, buyZones[i]))
      {
         buyZonesUsed[i] = true;
         PrintFormat("[ZONE_USED] BUY zone restored as USED: %.*f", _Digits, buyZones[i]);
      }
   }
   for(int i = 0; i < totalSellZones; i++)
   {
      if(IsZoneUsedFromFile(false, sellZones[i]))
      {
         sellZonesUsed[i] = true;
         PrintFormat("[ZONE_USED] SELL zone restored as USED: %.*f", _Digits, sellZones[i]);
      }
   }
   
   // ========== LOG ==========
   if(totalBuyZones > 0)
   {
      string buyList = "";
      for(int i = 0; i < totalBuyZones; i++)
         buyList += DoubleToString(buyZones[i], _Digits) + 
                    (buyZonesUsed[i] ? "[USED]" : "") +
                    (i < totalBuyZones-1 ? ", " : "");
      PrintFormat("[ZONE] Loaded %d BUY zones: %s", totalBuyZones, buyList);
   }
   else
   {
      Print("[ZONE] No BUY zones configured");
   }
   
   if(totalSellZones > 0)
   {
      string sellList = "";
      for(int i = 0; i < totalSellZones; i++)
         sellList += DoubleToString(sellZones[i], _Digits) + 
                     (sellZonesUsed[i] ? "[USED]" : "") +
                     (i < totalSellZones-1 ? ", " : "");
      PrintFormat("[ZONE] Loaded %d SELL zones: %s", totalSellZones, sellList);
   }
   else
   {
      Print("[ZONE] No SELL zones configured");
   }
}

bool IsPriceInZone(double currentPrice, double zonePrice, int activationPips)
{
   if(zonePrice <= 0.0)
      return false;
   
   double pip = PipSize();
   double distance = MathAbs(currentPrice - zonePrice);
   double threshold = (double)activationPips * pip;
   
   return (distance <= threshold);
}


bool FindNearestZoneHit(bool isBuy, double &zoneOut, int &zoneIndexOut)
{
   zoneOut = 0.0;
   zoneIndexOut = -1;
   
   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) 
                                : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   int total = isBuy ? totalBuyZones : totalSellZones;
   
   if(total == 0)
      return false;
   
   double nearestZone = 0.0;
   double minDistance = DBL_MAX;
   int nearestIndex = -1;
   
   for(int i = 0; i < total; i++)
   {
      if(isBuy && buyZonesUsed[i])
         continue;
      if(!isBuy && sellZonesUsed[i])
         continue;
      
      double zonePrice = isBuy ? buyZones[i] : sellZones[i];
      
      if(IsPriceInZone(currentPrice, zonePrice, ZoneActivationPips))
      {
         double distance = MathAbs(currentPrice - zonePrice);
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestZone = zonePrice;
            nearestIndex = i;
         }
      }
   }
   
   if(nearestZone > 0.0)
   {
      zoneOut = nearestZone;
      zoneIndexOut = nearestIndex;
      return true;
   }
   
   return false;
}

void UpdateZoneActivation()
{
   if(!EnablePriceZoneFilter)
   {
      buyZoneActivated = true; 
      sellZoneActivated = true;
      return;
   }
   
   datetime now = TimeCurrent();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(!buyZoneActivated)
   {
      double buyZoneHit = 0.0;
      int buyZoneIndex = -1;
      
      if(FindNearestZoneHit(true, buyZoneHit, buyZoneIndex))
      {
         buyZoneActivated = true;
         lastBuyZoneHitPrice = buyZoneHit;
         lastBuyZoneHitTime = now;
         
         PrintFormat("[ZONE][BUY]  ACTIVATED | Zone: %.*f | Index: %d | Current: %.*f", 
                     _Digits, buyZoneHit, buyZoneIndex, _Digits, bid);
         PrintFormat("[ZONE][BUY] → Will stay active until used or opposite cross");
      }
   }
   
   if(!sellZoneActivated)
   {
      double sellZoneHit = 0.0;
      int sellZoneIndex = -1;
      
      if(FindNearestZoneHit(false, sellZoneHit, sellZoneIndex))
      {
         sellZoneActivated = true;
         lastSellZoneHitPrice = sellZoneHit;
         lastSellZoneHitTime = now;
         
         PrintFormat("[ZONE][SELL] ACTIVATED | Zone: %.*f | Index: %d | Current: %.*f", 
                     _Digits, sellZoneHit, sellZoneIndex, _Digits, ask);
         PrintFormat("[ZONE][SELL] → Will stay active until used or opposite cross");
      }
   }
}

void ResetZoneActivation()
{
   if(!EnablePriceZoneFilter)
      return;
   PrintFormat("[ZONE] Zone states reset (cross event)");
}

double PipSize()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // Other CFDs: tick 0.1 = 10 USD → pip = tick
   if (tickValue == 1.0 && tickSize == 0.01)
      return 0.1;

   // Forex 5-digit / gold 3-digit
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

string SideText(bool isBuy) { return (isBuy ? "BUY" : "SELL"); }

//=========================== VN SESSION HELPERS =====================
int VNDeltaHours() { return (VNOffsetFromUTC - ServerOffsetFromUTC); }

datetime GetVNTime() { return (TimeCurrent() + VNDeltaHours() * 3600); }

datetime VNToServer(datetime vnTime) { return (vnTime - VNDeltaHours() * 3600); }

// Window compare on VN time (supports overnight if end <= start)
bool IsInVNWindow(int sh, int sm, int eh, int em)
{
   datetime vn = GetVNTime();
   MqlDateTime t;
   TimeToStruct(vn, t);

   int cur = t.hour * 60 + t.min;
   int st = sh * 60 + sm;
   int en = eh * 60 + em;

   if (en > st)
      return (cur >= st && cur < en);
   return (cur >= st || cur < en); // overnight
}

// Requested session flags
bool IsTradeAsia() { return IsInVNWindow(AsiaStartHour, AsiaStartMin, AsiaEndHour, AsiaEndMin); }
bool IsTradeEU() { return IsInVNWindow(EUStartHour, EUStartMin, EUEndHour, EUEndMin); }
bool IsTradeNY() { return IsInVNWindow(NYStartHour, NYStartMin, NYEndHour, NYEndMin); }

string CurrentVNSessionName()
{
   if (IsTradeAsia())
      return "ASIA";
   if (IsTradeEU())
      return "EU";
   if (IsTradeNY())
      return "NY";
   return "NONE";
}

string VNWindowTextFor(string sess)
{
   if (sess == "ASIA")
      return StringFormat("%02d:%02d -> %02d:%02d", AsiaStartHour, AsiaStartMin, AsiaEndHour, AsiaEndMin);
   if (sess == "EU")
      return StringFormat("%02d:%02d -> %02d:%02d", EUStartHour, EUStartMin, EUEndHour, EUEndMin);
   if (sess == "NY")
      return StringFormat("%02d:%02d -> %02d:%02d", NYStartHour, NYStartMin, NYEndHour, NYEndMin);
   return "N/A";
}

// Get current ENABLED VN session window in SERVER time (for throttle key)
bool GetEnabledVNSessionWindowServer(datetime nowServer, datetime &startServer, datetime &endServer, string &nameOut)
{
   startServer = 0;
   endServer = 0;
   nameOut = "NONE";

   datetime nowVN = nowServer + VNDeltaHours() * 3600;
   MqlDateTime vn;
   TimeToStruct(nowVN, vn);

   struct SessDef
   {
      int sh, sm, eh, em;
      bool enabled;
      string name;
   };
   SessDef s[3] = {
       {AsiaStartHour, AsiaStartMin, AsiaEndHour, AsiaEndMin, IsAllowAsia, "ASIA"},
       {EUStartHour, EUStartMin, EUEndHour, EUEndMin, IsAllowEU, "EU"},
       {NYStartHour, NYStartMin, NYEndHour, NYEndMin, IsAllowNY, "NY"}};

   for (int i = 0; i < 3; i++)
   {
      if (!s[i].enabled)
         continue;

      MqlDateTime a = vn, b = vn;
      a.hour = s[i].sh;
      a.min = s[i].sm;
      a.sec = 0;
      b.hour = s[i].eh;
      b.min = s[i].em;
      b.sec = 0;

      datetime startVN = StructToTime(a);
      datetime endVN = StructToTime(b);
      if (endVN <= startVN)
         endVN += 24 * 60 * 60; // overnight

      if (nowVN >= startVN && nowVN < endVN)
      {
         startServer = VNToServer(startVN);
         endServer = VNToServer(endVN);
         nameOut = s[i].name;
         return true;
      }
   }

   return false;
}

// forbidden in session-mode: outside any ENABLED VN session
bool IsForbiddenByVNSessions(datetime &endOut)
{
   endOut = 0;
   datetime ws = 0, we = 0;
   string nm;
   if (!GetEnabledVNSessionWindowServer(TimeCurrent(), ws, we, nm))
      return true;

   endOut = we;
   return false;
}

//=========================== SESSION BY BROKER HOURS ===============
bool GetCurrentSymbolSessionWindow(datetime now, datetime &sOut, datetime &eOut)
{
   sOut = 0;
   eOut = 0;

   MqlDateTime t;
   TimeToStruct(now, t);
   int dow = t.day_of_week; // 0=Sun ... 6=Sat

   for (int idx = 0; idx < 10; idx++)
   {
      datetime from = 0, to = 0;
      if (!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to))
         break;

      if (from == 0 && to == 0)
         continue;

      // Build today's session window (time part from 'from/to')
      MqlDateTime s = t, e = t;
      MqlDateTime tf, tt;
      TimeToStruct(from, tf);
      TimeToStruct(to, tt);

      s.hour = tf.hour;
      s.min = tf.min;
      s.sec = 0;
      e.hour = tt.hour;
      e.min = tt.min;
      e.sec = 0;

      datetime s0 = StructToTime(s);
      datetime e0 = StructToTime(e);

      // session crosses midnight
      if (e0 <= s0)
         e0 += 24 * 60 * 60;

      // Overnight session adjustment (rare but safe)
      if (now < s0 && (e0 - s0) > 6 * 60 * 60)
      {
         s0 -= 24 * 60 * 60;
         e0 -= 24 * 60 * 60;
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
   datetime now = TimeCurrent();
   return GetCurrentSymbolSessionWindow(now, sOut, eOut);
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
   if (now >= e)
      return 0.0;
   return (double)(e - now) / 3600.0;
}

// forbidden when: outside session (SESSION TRADE) OR <= X hours to session end (FULLDAY TRADE)
bool IsForbiddenBySession(datetime &sessionEndOut)
{
   datetime s, e;
   sessionEndOut = 0;

   if (!IsInMarketSessionNow(s, e))
      return true;

   sessionEndOut = e;
   datetime dummyEnd = 0;
   double h = HoursToSessionEnd(dummyEnd);
   return (h <= NoNewTradesBeforeEndH + 1e-9);
}

// Only routes forbidden logic based on mode.
bool IsForbiddenNow(datetime &endOut)
{
   endOut = 0;
   if (TradeWindowMode == TRADEWINDOW_FULLDAY)
      return IsForbiddenBySession(endOut);
   return IsForbiddenByVNSessions(endOut);
}

//=========================== INDICATOR READY ==========================
bool IndicatorsReady()
{
    static int retryCount = 0;
    static datetime lastRetryTime = 0;
    static datetime lastRecreateTime = 0;
    
    const int MAX_RETRIES = 30;
    const int RETRY_INTERVAL_SEC = 1;
    const int RECREATE_AFTER_SEC = 60;
    
    // Check handles valid
    if (haHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
    {
        Print("[INDICATOR] CRITICAL: Invalid handles | HA:", haHandle, " EMA:", emaHandle);
        return false;
    }

    // Check bars calculated
    long haBars = BarsCalculated(haHandle);
    long emaBars = BarsCalculated(emaHandle);
    
    int requiredBars = EMALongPeriod + 5;

    if(haBars < 10 || emaBars < requiredBars)
    {
        datetime now = TimeCurrent();
        
        if(now != lastRetryTime)
        {
            retryCount++;
            lastRetryTime = now;
            
            PrintFormat("[INDICATOR] Waiting... Retry %d/%d | HA bars: %d/%d | EMA bars: %d/%d",
                       retryCount, MAX_RETRIES, haBars, 10, emaBars, requiredBars);
            
            if(retryCount > MAX_RETRIES)
            {
                datetime timeSinceLastRecreate = now - lastRecreateTime;
                
                if(lastRecreateTime == 0 || timeSinceLastRecreate > RECREATE_AFTER_SEC)
                {
                    Print("[INDICATOR] RECOVERY: Recreating handles (stuck > ", MAX_RETRIES, " seconds)");
                    Print("[INDICATOR] Old handles - HA:", haHandle, " EMA:", emaHandle);
                    
                    // Release old
                    if(haHandle != INVALID_HANDLE) IndicatorRelease(haHandle);
                    if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
                    
                    // Small delay
                    Sleep(100);
                    
                    // Recreate
                    haHandle = iCustom(_Symbol, _Period, HAIndicatorName, BullColor, BearColor);
                    emaHandle = iCustom(_Symbol, _Period, EMAIndicatorName, 
                                        EMAShortPeriod, EMALongPeriod, EMAMethod);
                    
                    Print("[INDICATOR] New handles - HA:", haHandle, " EMA:", emaHandle);
                    
                    if(haHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
                    {
                        Print("[INDICATOR] CRITICAL: Failed to recreate handles!");
                        return false;
                    }
                    
                    lastRecreateTime = now;
                    retryCount = 0;  // Reset counter
                    
                    Print("[INDICATOR] Handles recreated successfully, waiting for data...");
                }
                else
                {
                    PrintFormat("[INDICATOR] Waiting for recreated indicators to load... (%.0fs since recreate)",
                               (double)timeSinceLastRecreate);
                }
            }
        }
        
        return false;
    }
    
    if(retryCount > 0)
    {
        PrintFormat("[INDICATOR] Ready after %d retries | HA bars: %d | EMA bars: %d",
                   retryCount, haBars, emaBars);
        retryCount = 0;
        lastRetryTime = 0;
    }
    
    double hl0[], ll0[], dot0[];
    
    double hlVal, llVal;
    if(!ReadHighLineAtShift(0, hlVal))
    {
        Print("[INDICATOR] Warning: Failed to read HighLine at shift=0");
        return false;
    }
    if(!ReadLowLineAtShift(0, llVal))
    {
        Print("[INDICATOR] Warning: Failed to read LowLine at shift=0");
        return false;
    }
    
    if(CopyBuffer(emaHandle, 2, 0, 1, dot0) != 1)
    {
        Print("[INDICATOR] Warning: Failed to copy Dot buffer");
        return false;
    }
    

    double haClose[];
    if(CopyBuffer(haHandle, 3, 0, 1, haClose) != 1)
    {
        Print("[INDICATOR] Warning: Failed to copy HA Close buffer");
        return false;
    }
    if(haClose[0]==EMPTY_VALUE)
    {
        Print("[INDICATOR] Warning: Empty value in HA Close");
        return false;
    }

    return true;
}

//=========================== INDICATOR READS ===========================
bool ReadHA(int shift, double &haOpen, double &haHigh, double &haLow, double &haClose, double &haColor)
{
   double buf[1];
   if (CopyBuffer(haHandle, 0, shift, 1, buf) != 1)
      return false;
   haOpen = buf[0];
   if (CopyBuffer(haHandle, 1, shift, 1, buf) != 1)
      return false;
   haHigh = buf[0];
   if (CopyBuffer(haHandle, 2, shift, 1, buf) != 1)
      return false;
   haLow = buf[0];
   if (CopyBuffer(haHandle, 3, shift, 1, buf) != 1)
      return false;
   haClose = buf[0];
   if (CopyBuffer(haHandle, 4, shift, 1, buf) != 1)
      return false;
   haColor = buf[0];
   return true;
}

bool ReadHighLineAtShift(int shift, double &v)
{
   double a[1];
   int maxRetry = 5;
   
   for(int i = 0; i < maxRetry; i++)
   {
      ResetLastError();
      int r = CopyBuffer(emaHandle, 3, shift, 1, a);
      
      if(r == 1 && a[0] != EMPTY_VALUE && MathIsValidNumber(a[0]) && a[0] > 0)
      {
         v = a[0];
         return true;
      }
      
      Sleep(50);
   }
   
   PrintFormat("[WARN] ReadHighLineAtShift failed after %d retries | shift=%d lastErr=%d",
               maxRetry, shift, GetLastError());
   return false;
}

bool ReadLowLineAtShift(int shift, double &v)
{
   double a[1];
   int maxRetry = 5;
   
   for(int i = 0; i < maxRetry; i++)
   {
      ResetLastError();
      int r = CopyBuffer(emaHandle, 4, shift, 1, a);
      
      if(r == 1 && a[0] != EMPTY_VALUE && MathIsValidNumber(a[0]) && a[0] > 0)
      {
         v = a[0];
         return true;
      }
      
      Sleep(50);
   }
   
   PrintFormat("[WARN] ReadLowLineAtShift failed after %d retries | shift=%d lastErr=%d",
               maxRetry, shift, GetLastError());
   return false;
}

//=================== EXPOSURE HELPERS ===============================
bool HasPending(ENUM_ORDER_TYPE otype, ulong &ticketOut)
{
   ticketOut = 0;
   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if (tk == 0)
         continue;
      if (!OrderSelect(tk))
         continue;

      if (OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (t == otype)
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
   if (!HasPending(otype, tk))
      return;

   if (OrderSelect(tk))
   {
      bool isBuy = (otype == ORDER_TYPE_BUY_LIMIT);
      double et = OrderGetDouble(ORDER_PRICE_OPEN);
      TG_SendCancelLimitByCross(isBuy, et, (long)tk);
   }

   trade.OrderDelete(tk);
}

bool HasPosition(ENUM_POSITION_TYPE ptype, ulong &ticketOut)
{
   ticketOut = 0;
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

      ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (t == ptype)
      {
         ticketOut = tk;
         return true;
      }
   }
   return false;
}

// Cancel pending if price hits its TP before being filled
void CancelPendingIfTPHit()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if (tk == 0)
         continue;
      if (!OrderSelect(tk))
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

      if (type == ORDER_TYPE_BUY_LIMIT)
      {
         if (bid >= tp)
         {
            double et = OrderGetDouble(ORDER_PRICE_OPEN);
            TG_SendCancelLimitByTPBeforeFilled(true, et, (long)tk);
            trade.OrderDelete(tk);
         }
      }
      else
      {
         if (bid <= tp)
         {
            double et = OrderGetDouble(ORDER_PRICE_OPEN);
            TG_SendCancelLimitByTPBeforeFilled(false, et, (long)tk);
            trade.OrderDelete(tk);
         }
      }
   }
}

//=================== SESSION ENFORCEMENT ============================
// In forbidden zone: cancel ALL pendings (any type) + close ALL positions. Throttled.
void EnforceForbiddenZone()
{
   datetime sessEnd = 0;
   bool forbidden = IsForbiddenNow(sessEnd);

   if (!forbidden)
   {
      lastKnownSessionEnd = 0;
      return;
   }

   datetime now = TimeCurrent();

   bool newKey = (sessEnd > 0 && sessEnd != lastKnownSessionEnd);

   if (!newKey)
   {
      if ((now - lastSessionForceActionTime) < SessionForceThrottleSec)
         return;
   }

   lastSessionForceActionTime = now;
   if (sessEnd > 0)
      lastKnownSessionEnd = sessEnd;

   // cancel all pendings
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong otk = OrderGetTicket(i);
      if (otk == 0)
         continue;
      if (!OrderSelect(otk))
         continue;

      if (OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
          type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
          type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
      {
         trade.OrderDelete(otk);
      }
   }

   // close all positions
   if (forbidden && TradeWindowMode == TRADEWINDOW_FULLDAY)
   {
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ptk = PositionGetTicket(i);
         if (ptk == 0)
            continue;
         if (!PositionSelectByTicket(ptk))
            continue;

         if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         trade.PositionClose(ptk);
      }
   }

   waitingBUY = false;
   waitingSELL = false;
}

//=================== DD (SESSION, REALIZED) =========================
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

      double profit = HistoryDealGetDouble(tk, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(tk, DEAL_SWAP);
      double comm = HistoryDealGetDouble(tk, DEAL_COMMISSION);

      pnl += (profit + swap + comm);
   }
   return pnl;
}

void ResetSessionDDIfNeeded()
{
   datetime now = TimeCurrent();
   datetime s = 0, e = 0;

   if (!GetCurrentSymbolSessionWindow(now, s, e))
      return; // outside session -> don't reset baseline here

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
   {
      sessionEndTime = e;
   }
}

void UpdateSessionProfitGate()
{
   ResetSessionDDIfNeeded();
   if (sessionStartTime == 0)
      return;

   if (DailyProfitTargetUSD <= 0.0)
   {
      profitBlocked = false;
      return;
   }

   double pnl = RealizedPnLInRange(sessionStartTime, TimeCurrent());
   lastSessionRealizedPnL = pnl;

   if (pnl >= DailyProfitTargetUSD - 1e-9)
   {
      profitBlocked = true;

      if (IsCancelPendingsWhenProfitHit)
      {
         for (int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong otk = OrderGetTicket(i);
            if (otk == 0)
               continue;
            if (!OrderSelect(otk))
               continue;

            if (OrderGetString(ORDER_SYMBOL) != _Symbol)
               continue;
            if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
               continue;

            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
                type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
                type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
            {
               trade.OrderDelete(otk);
            }
         }
      }

      if (IsForceCloseWhenProfitHit)
      {
         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ptk = PositionGetTicket(i);
            if (ptk == 0)
               continue;
            if (!PositionSelectByTicket(ptk))
               continue;

            if (PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
               continue;

            trade.PositionClose(ptk);
         }

         waitingBUY = false;
         waitingSELL = false;
      }
   }
}

void UpdateSessionDDGate()
{
   ResetSessionDDIfNeeded();
   if (sessionStartTime == 0)
      return;

   double pnl = RealizedPnLInRange(sessionStartTime, TimeCurrent());
   lastSessionRealizedPnL = pnl;

   double loss = (pnl < 0.0) ? (-pnl) : 0.0;

   bool hitOrPreBlock = (loss >= sessionLossLimit) || ((loss + RiskUSDPerTrade) > sessionLossLimit);

   if (hitOrPreBlock)
   {
      ddBlocked = true;

      if (IsCancelPendingsWhenDDHit)
      {
         for (int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong otk = OrderGetTicket(i);
            if (otk == 0)
               continue;
            if (!OrderSelect(otk))
               continue;

            if (OrderGetString(ORDER_SYMBOL) != _Symbol)
               continue;
            if ((long)OrderGetInteger(ORDER_MAGIC) != MagicNumber)
               continue;

            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
                type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
                type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
            {
               trade.OrderDelete(otk);
            }
         }
      }
   }
}

//=================== SL FROM HA PAIR ===============================
// BUY: 2 HA red consecutive -> SL = min(low1,low2) - buffer
// SELL: 2 HA green consecutive -> SL = max(high1,high2) + buffer
bool FindSLFromNearestOppositeHAPair(bool isBuy, double &slPrice)
{
   double pip = PipSize();
   int maxSh = MathMax(2, SL_LookbackBars);

   for (int sh = 1; sh <= maxSh - 1; sh++)
   {
      double o1, h1, l1, c1, col1;
      double o2, h2, l2, c2, col2;

      if (!ReadHA(sh, o1, h1, l1, c1, col1))
         return false;
      if (!ReadHA(sh + 1, o2, h2, l2, c2, col2))
         return false;

      bool bull1 = (col1 == 0.0);
      bool bear1 = (col1 == 1.0);
      bool bull2 = (col2 == 0.0);
      bool bear2 = (col2 == 1.0);

      if (isBuy)
      {
         if (bear1 && bear2)
         {
            double baseLow = MathMin(l1, l2);
            slPrice = NormalizePrice(baseLow - (double)BufferPips * pip);
            return true;
         }
      }
      else
      {
         if (bull1 && bull2)
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
   if (sl_pips <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double pipValuePer1Lot = tickValue * (pip / tickSize);
   if (pipValuePer1Lot <= 0.0)
      return 0.0;

   double lots = RiskUSDPerTrade / (sl_pips * pipValuePer1Lot);
   return NormalizeVolume(lots);
}

//=================== CROSS SCAN + AUTO ARM ==========================
// UPDATED: Determine Cross direction by EMA short/long (same logic as GetCrossEventOnClosedBar)
bool FindLatestCross(int lookback, int &shiftOut, double &priceOut, string &dirOut, datetime &timeOut)
{
   shiftOut = -1;
   priceOut = 0.0;
   dirOut = "None";
   timeOut = 0;

   double dot[1];

   for (int sh = 1; sh <= lookback; sh++)
   {
      if (CopyBuffer(emaHandle, 2, sh, 1, dot) != 1)
         continue;

      double d = dot[0];
      if (d == 0.0 || d == EMPTY_VALUE)
         continue;

      // found latest dot
      shiftOut = sh;
      priceOut = d;
      timeOut = iTime(_Symbol, _Period, sh);

      // Determine direction by EMA short/long at sh and sh+1
      double s1[1], s2[1], l1[1], l2[1];
      int rs1 = CopyBuffer(emaHandle, 0, sh, 1, s1);
      int rs2 = CopyBuffer(emaHandle, 0, sh + 1, 1, s2);
      int rl1 = CopyBuffer(emaHandle, 1, sh, 1, l1);
      int rl2 = CopyBuffer(emaHandle, 1, sh + 1, 1, l2);

      if (rs1 != 1 || rs2 != 1 || rl1 != 1 || rl2 != 1)
      {
         dirOut = "Cross";
         return true;
      }

      double short1 = s1[0], short2 = s2[0];
      double long1 = l1[0], long2 = l2[0];

      if (short1 > long1 && short2 < long2)
      {
         dirOut = "Cross Up";
         return true;
      }

      if (short1 < long1 && short2 > long2)
      {
         dirOut = "Cross Down";
         return true;
      }

      dirOut = "Cross";
      return true;
   }

   return false;
}

void AutoArmFromLatestCross()
{
   if (waitingBUY || waitingSELL)
      return;

   int sh;
   double p;
   string dir;
   datetime t;
   if (!FindLatestCross(CrossScanLookbackBars, sh, p, dir, t))
      return;

   currentCrossText = dir;
   currentCrossPrice = p;
   currentCrossTime = t;
   
   if(currentRegimeEpoch == 0)
      currentRegimeEpoch = t;

   if (dir == "Cross Up")
   {
      waitingBUY = true;
      waitingSELL = false;
      return;
   }

   if (dir == "Cross Down")
   {
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

   double dot1Arr[1];
   if (CopyBuffer(emaHandle, 2, 1, 1, dot1Arr) != 1)
   {
      currentCrossText = "None";
      currentCrossPrice = 0.0;
      return;
   }

   double dot1 = dot1Arr[0];
   if (dot1 == 0.0 || dot1 == EMPTY_VALUE)
   {
      currentCrossText = "None";
      return;
   }

   currentCrossPrice = dot1;
   eventPrice = dot1;

   // Read EMA10 (buffer 0) & EMA39 (buffer 1) at bar1 and bar2
   double s1[1], s2[1], l1[1], l2[1];
   int rs1 = CopyBuffer(emaHandle, 0, 1, 1, s1); // Short MA bar1
   int rs2 = CopyBuffer(emaHandle, 0, 2, 1, s2); // Short MA bar2
   int rl1 = CopyBuffer(emaHandle, 1, 1, 1, l1); // Long  MA bar1
   int rl2 = CopyBuffer(emaHandle, 1, 2, 1, l2); // Long  MA bar2

   if (rs1 != 1 || rs2 != 1 || rl1 != 1 || rl2 != 1)
   {
      currentCrossText = "Cross";
      return;
   }

   double short1 = s1[0], short2 = s2[0];
   double long1 = l1[0], long2 = l2[0];

   if (short1 > long1 && short2 < long2)
   {
      crossUp = true;
      currentCrossText = "Cross Up";
      PrintFormat("[%s][CROSS][BUY] EMA Cross UP | price=%.*f", _Symbol, _Digits, eventPrice);
      return;
   }

   if (short1 < long1 && short2 > long2)
   {
      crossDown = true;
      currentCrossText = "Cross Down";
      PrintFormat("[%s][CROSS][SELL] EMA Cross DOWN | price=%.*f", _Symbol, _Digits, eventPrice);
      return;
   }

   currentCrossText = "Cross";
}

//=================== ONE-USE PER LINE (PER REGIME) ==================
long LineKey(double price)
{
   return (long)MathRound(price / _Point);
}

string LineUsedName(bool isBuy, long key)
{
   // Regime-based key: same price but different regime epoch => NEW setup
   long epoch = (long)currentRegimeEpoch;
   return _Symbol + "_" + IntegerToString((int)_Period) + "_" +
          (isBuy ? "BUY" : "SELL") + "_E" + (string)epoch + "_K" + (string)key;
}

void LoadLineUsedFromFile()
{
   ArrayResize(usedLines, 0);
   totalUsedLines = 0;
   
   int handle = FileOpen(LINE_USED_FILE, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("[LINE_USED] No existing file, starting fresh");
      return;
   }
   
   while(!FileIsEnding(handle))
   {
      LineUsedRecord rec;
      rec.regimeEpoch = (datetime)FileReadLong(handle);
      rec.lineKey = FileReadLong(handle);
      rec.isBuy = (bool)FileReadInteger(handle);
      rec.usedTime = (datetime)FileReadLong(handle);
      
      if(rec.regimeEpoch == 0)
         break;  // End of valid data
      
      ArrayResize(usedLines, totalUsedLines + 1);
      usedLines[totalUsedLines] = rec;
      totalUsedLines++;
   }
   
   FileClose(handle);
   
   PrintFormat("[LINE_USED] Loaded %d records from file", totalUsedLines);
}

void SaveLineUsedToFile()
{
   int handle = FileOpen(LINE_USED_FILE, FILE_WRITE | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("[LINE_USED] ERROR: Cannot save to file, error: ", GetLastError());
      return;
   }
   
   for(int i = 0; i < totalUsedLines; i++)
   {
      FileWriteLong(handle, (long)usedLines[i].regimeEpoch);
      FileWriteLong(handle, usedLines[i].lineKey);
      FileWriteInteger(handle, (int)usedLines[i].isBuy);
      FileWriteLong(handle, (long)usedLines[i].usedTime);
   }
   
   FileClose(handle);
   
   PrintFormat("[LINE_USED] Saved %d records to file", totalUsedLines);
}

void CleanupOldLineUsedRecords()
{
   datetime now = TimeCurrent();
   datetime threshold = now - (7 * 24 * 60 * 60);  
   
   int newSize = 0;
   for(int i = 0; i < totalUsedLines; i++)
   {
      if(usedLines[i].usedTime >= threshold)
      {
         if(newSize != i)
            usedLines[newSize] = usedLines[i];
         newSize++;
      }
   }
   
   int removed = totalUsedLines - newSize;
   if(removed > 0)
   {
      ArrayResize(usedLines, newSize);
      totalUsedLines = newSize;
      SaveLineUsedToFile();
      PrintFormat("[LINE_USED] Cleaned up %d old records (> 7 days)", removed);
   }
}

bool IsLineUsed(bool isBuy, long key)
{
   if(currentRegimeEpoch == 0)
      return false;
   
   for(int i = 0; i < totalUsedLines; i++)
   {
      if(usedLines[i].regimeEpoch == currentRegimeEpoch &&
         usedLines[i].lineKey == key &&
         usedLines[i].isBuy == isBuy)
      {
         return true;
      }
   }
   
   return false;
}

void MarkLineUsed(bool isBuy, long key)
{
   if(currentRegimeEpoch == 0)
      return;
   
   for(int i = 0; i < totalUsedLines; i++)
   {
      if(usedLines[i].regimeEpoch == currentRegimeEpoch &&
         usedLines[i].lineKey == key &&
         usedLines[i].isBuy == isBuy)
      {
         PrintFormat("[LINE_USED] Already marked: %s key=%I64d epoch=%s",
                     (isBuy ? "BUY" : "SELL"), key,
                     TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES));
         return;
      }
   }
   
   LineUsedRecord rec;
   rec.regimeEpoch = currentRegimeEpoch;
   rec.lineKey = key;
   rec.isBuy = isBuy;
   rec.usedTime = TimeCurrent();
   
   ArrayResize(usedLines, totalUsedLines + 1);
   usedLines[totalUsedLines] = rec;
   totalUsedLines++;
   
   SaveLineUsedToFile();
   
   PrintFormat("[LINE_USED] Marked used: %s key=%I64d epoch=%s (total: %d)",
               (isBuy ? "BUY" : "SELL"), key,
               TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES),
               totalUsedLines);
   
   if(isBuy)
      lastUsedHighKey = key;
   else
      lastUsedLowKey = key;
}

void ResetLineUsedForNewRegime()
{
   PrintFormat("[LINE_USED] New regime started: %s (keeping %d old records)",
               TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES),
               totalUsedLines);
}

void MarkZoneUsed(bool isBuy, double zonePrice)
{
   int total = isBuy ? totalBuyZones : totalSellZones;
   for(int i = 0; i < total; i++)
   {
      double zone = isBuy ? buyZones[i] : sellZones[i];
      if(MathAbs(zone - zonePrice) < 0.1)
      {
         if(isBuy)
         {
            buyZonesUsed[i] = true;
            PrintFormat("[ZONE][BUY] Zone MARKED USED | Price: %.*f | Index: %d",
                        _Digits, zonePrice, i);
         }
         else
         {
            sellZonesUsed[i] = true;
            PrintFormat("[ZONE][SELL] Zone MARKED USED | Price: %.*f | Index: %d",
                        _Digits, zonePrice, i);
         }

         ZoneUsedRecord rec;
         rec.isBuy     = isBuy;
         rec.zonePrice = zonePrice;
         rec.usedTime  = TimeCurrent();

         ArrayResize(usedZones, totalUsedZones + 1);
         usedZones[totalUsedZones] = rec;
         totalUsedZones++;

         SaveZoneUsedToFile();
         break;
      }
   }
}

//=================== BREAKOUT CHECKS =========================
bool CheckBuyBreakoutOnClosedBar(long &highKeyOut)
{
   highKeyOut = 0;
   if (!waitingBUY)
      return false;

   if(EnablePriceZoneFilter)
   {
      if(!buyZoneActivated)
      {
         return false;
      }
      
      PrintFormat("[%s][PASS][BUY]  Zone filter PASSED | Zone: %.*f", 
                  _Symbol, _Digits, lastBuyZoneHitPrice);
   }
   
   double haO, haH, haL, haC, haCol;
   if (!ReadHA(1, haO, haH, haL, haC, haCol))
      return false;

   if (haCol != 0.0)
      return false;

   double highLine1;
   if (!ReadHighLineAtShift(1, highLine1))
      return false;

   PrintFormat("[%s][CHECK][BUY] HAclose=%.*f HighLine=%.*f | HA>Line=%d",
               _Symbol, _Digits, haC, _Digits, highLine1, (haC > highLine1));

   if (haC <= highLine1)
      return false;

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);

   PrintFormat("[%s][CANDLE][BUY] Open=%.*f Close=%.*f | Bull=%d Bear=%d",
               _Symbol, _Digits, o1, _Digits, c1, (c1 >= o1), (c1 < o1));

   if (c1 < o1)
      return false;

   long key = LineKey(highLine1);

   if (IsLineUsed(true, key))
   {
      PrintFormat("[%s][SKIP][BUY] Line already used in regime | key=%I64d epoch=%s",
                  _Symbol, key,
                  (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0"));
      return false;
   }

   double lowLine1;
   if (!ReadLowLineAtShift(1, lowLine1))
      return false;

   double pip = PipSize();
   double rangePips = MathAbs(highLine1 - lowLine1) / pip;

   if (rangePips < RangeChannelEMA)
   {
      PrintFormat("[%s][SKIP][BUY] Range too small -> MARK USED | High=%.5f Low=%.5f Range=%.1f < Min=%.1f",
                  _Symbol, highLine1, lowLine1, rangePips, RangeChannelEMA);
      
      MarkLineUsed(true, key);
      
      highKeyOut = 0;
      return false;
   }

   PrintFormat("[%s][PASS][BUY] All conditions PASSED | line=%.*f key=%I64d range=%.1f",
               _Symbol, _Digits, highLine1, key, rangePips);

   highKeyOut = key;
   return true;
}

bool CheckSellBreakoutOnClosedBar(long &lowKeyOut)
{
   lowKeyOut = 0;
   if (!waitingSELL)
      return false;

   if(EnablePriceZoneFilter)
   {
      if(!sellZoneActivated)
      {
         return false;
      }
      
      PrintFormat("[%s][PASS][SELL]  Zone filter PASSED | Zone: %.*f", 
                  _Symbol, _Digits, lastSellZoneHitPrice);
   }

   double haO, haH, haL, haC, haCol;
   if (!ReadHA(1, haO, haH, haL, haC, haCol))
      return false;

   if (haCol != 1.0)
      return false;

   double lowLine1;
   if (!ReadLowLineAtShift(1, lowLine1))
      return false;

   PrintFormat("[%s][CHECK][SELL] HAclose=%.*f LowLine=%.*f | HA<Line=%d",
               _Symbol, _Digits, haC, _Digits, lowLine1, (haC < lowLine1));

   if (haC >= lowLine1)
      return false;

   double o1 = iOpen(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);

   PrintFormat("[%s][CANDLE][SELL] Open=%.*f Close=%.*f | Bull=%d Bear=%d",
               _Symbol, _Digits, o1, _Digits, c1, (c1 <= o1), (c1 > o1));

   if (c1 > o1)
      return false;

   long key = LineKey(lowLine1);

   if (IsLineUsed(false, key))
   {
      PrintFormat("[%s][SKIP][SELL] Line already used in regime | key=%I64d epoch=%s",
                  _Symbol, key,
                  (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0"));
      return false;
   }

   double highLine1;
   if (!ReadHighLineAtShift(1, highLine1))
      return false;

   double pip = PipSize();
   double rangePips = MathAbs(highLine1 - lowLine1) / pip;

   if (rangePips < RangeChannelEMA)
   {
      PrintFormat("[%s][SKIP][SELL] Range too small -> MARK USED | High=%.5f Low=%.5f Range=%.1f < Min=%.1f",
                  _Symbol, highLine1, lowLine1, rangePips, RangeChannelEMA);
      
      MarkLineUsed(false, key);
      
      lowKeyOut = 0;
      return false;
   }

   PrintFormat("[%s][PASS][SELL] All conditions PASSED | line=%.*f key=%I64d range=%.1f",
               _Symbol, _Digits, lowLine1, key, rangePips);

   lowKeyOut = key;
   return true;
}

//=================== EXECUTE ENTRY ===============================
bool ExecuteEntry(bool isBuy, long lineKey)
{
   // gate by forbidden zone (FULLDAY or SESSIONS)
   datetime endGate = 0;
   if (IsForbiddenNow(endGate))
   {
      PrintFormat("[%s][SKIP][%s] ForbiddenNow | endGate=%s",
                  _Symbol, SideText(isBuy),
                  (endGate > 0 ? TimeToString(endGate, TIME_DATE | TIME_MINUTES) : "N/A"));
      return false;
   }

   // gate by DD
   if (ddBlocked)
   {
      PrintFormat("[%s][SKIP][%s] Blocked by DD", _Symbol, SideText(isBuy));
      return false;
   }

   // gate by Profit Target
   if (profitBlocked)
   {
      PrintFormat("[%s][SKIP][%s] Blocked by ProfitTarget", _Symbol, SideText(isBuy));
      return false;
   }

   double sl;
   if (!FindSLFromNearestOppositeHAPair(isBuy, sl))
   {
      PrintFormat("[%s][SKIP][%s] No SL from HA pair", _Symbol, SideText(isBuy));
      return false;
   }
   double pip = PipSize();

   if(EnablePriceZoneFilter && UseSLFromZone)
   {
      double zonePrice = isBuy ? lastBuyZoneHitPrice : lastSellZoneHitPrice;
      if(zonePrice > 0.0)
      {
         double SLZone = isBuy ? NormalizePrice(zonePrice - ZoneSLBufferPips * pip)
                                   : NormalizePrice(zonePrice + ZoneSLBufferPips * pip);
         sl = SLZone;
      }
   }

   double entryNow = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   entryNow = NormalizePrice(entryNow);

   if (isBuy && sl >= entryNow)
   {
      PrintFormat("[%s][SKIP][BUY] Invalid SL >= entryNow | entryNow=%.*f sl=%.*f lineKey %I64d",
                  _Symbol, _Digits, entryNow, _Digits, sl, lineKey);
      return false;
   }

   if (!isBuy && sl <= entryNow)
   {
      PrintFormat("[%s][SKIP][SELL] Invalid SL <= entryNow | entryNow=%.*f sl=%.*f lineKey %I64d",
                  _Symbol, _Digits, entryNow, _Digits, sl, lineKey);
      return false;
   }

   double riskDist = isBuy ? (entryNow - sl) : (sl - entryNow);
   if (riskDist <= 0)
      return false;

   double riskPips = riskDist / pip;

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   PrintFormat("[%s][SETUP][%s] entryNow=%.*f sl=%.*f riskPips=%.1f SLMax=%.1f lineKey %I64d",
               _Symbol, SideText(isBuy),
               _Digits, entryNow, _Digits, sl, riskPips, SLMaxPips, lineKey,
               (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0"));

   // Case 1: within SL_MAX => MARKET
   if (riskPips <= SLMaxPips + 1e-9)
   {
      double lots = CalcLotsByRiskUSD(entryNow, sl);
      if (lots <= 0)
      {
         PrintFormat("[%s][SKIP][%s] lots<=0 (CalcLotsByRiskUSD) | entry=%.*f sl=%.*f lineKey %I64d",
                     _Symbol, SideText(isBuy), _Digits, entryNow, _Digits, sl, lineKey);
         return false;
      }

      double tp = isBuy ? (entryNow + RiskReward * riskDist) : (entryNow - RiskReward * riskDist);
      tp = NormalizePrice(tp);
      if (_Period != PERIOD_M1)
      {
         double htfTp = isBuy ? (entryNow + HTF_TP_Prices)
                        : (entryNow - HTF_TP_Prices);
         tp = NormalizePrice(htfTp);
      }

      bool isSuccess = false;
      if (isBuy)
         isSuccess = trade.Buy(lots, _Symbol, 0.0, sl, tp, "BUY MARKET");
      else
         isSuccess = trade.Sell(lots, _Symbol, 0.0, sl, tp, "SELL MARKET");

      if (isSuccess)
      {
         double entryFill = trade.ResultPrice();
         PrintFormat("[%s][ORDER][%s] MARKET SENT | ENTRY=%.*f Vol=%.2f SL=%.*f TP=%.*f lineKey %I64d",
                     _Symbol, SideText(isBuy),
                     _Digits, entryFill, lots,
                     _Digits, sl, _Digits, tp, lineKey);

         if(EnablePriceZoneFilter)
         {
            double usedZone = isBuy ? lastBuyZoneHitPrice : lastSellZoneHitPrice;
            MarkZoneUsed(isBuy, usedZone);
         }

         if (isBuy)
            waitingBUY = false;
         else
            waitingSELL = false;
      }
      else
      {
         PrintFormat("[%s][FAIL][%s] MARKET | ret=%d %s | Vol=%.2f SL=%.*f TP=%.*f lineKey %I64d",
                     _Symbol, SideText(isBuy),
                     trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),
                     lots, _Digits, sl, _Digits, tp, lineKey);
      }

      return isSuccess;
   }

   // Case 2: too large => LIMIT so EntryLimit->SL == SL_MAX
   double maxDist = SLMaxPips * pip;

   double entryLimit = isBuy ? (sl + maxDist) : (sl - maxDist);
   entryLimit = NormalizePrice(entryLimit);

   double tpLimit = isBuy ? (entryLimit + RiskReward * maxDist) : (entryLimit - RiskReward * maxDist);
   tpLimit = NormalizePrice(tpLimit);

   double lotsizeLimit = CalcLotsByRiskUSD(entryLimit, sl);
   if (lotsizeLimit <= 0)
   {
      PrintFormat("[%s][SKIP][%s] lots<=0 (CalcLotsByRiskUSD) | entryLimit=%.*f sl=%.*f lineKey %I64d",
                  _Symbol, SideText(isBuy), _Digits, entryLimit, _Digits, sl, lineKey);
      return false;
   }

   if (_Period != PERIOD_M1)
   {
      double htfTp = isBuy ? (entryLimit + HTF_TP_Prices)
                        : (entryLimit - HTF_TP_Prices);
      tpLimit = NormalizePrice(htfTp);
   }

   bool isLimitSuccess = false;
   if (isBuy)
   {
      isLimitSuccess = trade.BuyLimit(lotsizeLimit, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "BUY LIMIT SL_MAX");
      PrintFormat("[%s][ORDER][LIMIT][SEND] side=%s entry=%.*f vol=%.2f sl=%.*f tp=%.*f SLMaxPips=%.1f lineKey=%I64d",
                  _Symbol, SideText(isBuy),
                  _Digits, entryLimit, lotsizeLimit,
                  _Digits, sl,
                  _Digits, tpLimit,
                  SLMaxPips, lineKey);
   }
   else
   {
      isLimitSuccess = trade.SellLimit(lotsizeLimit, entryLimit, _Symbol, sl, tpLimit, ORDER_TIME_GTC, 0, "SELL LIMIT SL_MAX");
      PrintFormat("[%s][ORDER][LIMIT][SEND] side=%s entry=%.*f vol=%.2f sl=%.*f tp=%.*f SLMaxPips=%.1f lineKey=%I64d",
                  _Symbol, SideText(isBuy),
                  _Digits, entryLimit, lotsizeLimit,
                  _Digits, sl,
                  _Digits, tpLimit,
                  SLMaxPips, lineKey);
   }
   if (isLimitSuccess)
   {
      if(EnablePriceZoneFilter)
      {
         double usedZone = isBuy ? lastBuyZoneHitPrice : lastSellZoneHitPrice;
         MarkZoneUsed(isBuy, usedZone);
      }

      if (isBuy)
         waitingBUY = false;
      else
         waitingSELL = false;
   }
   else
   {
      PrintFormat("[%s][FAIL][%s] LIMIT | ret=%d %s | ENTRY=%.*f Vol=%.2f SL=%.*f TP=%.*f lineKey %I64d",
                  _Symbol, SideText(isBuy),
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription(),
                  _Digits, entryLimit, lotsizeLimit,
                  _Digits, sl, _Digits, tpLimit, lineKey);
   }

   return isLimitSuccess;
}

//=================== MANAGEMENT ===============================
void CancelWaitingOnOppositeCross(bool crossUpNow, bool crossDownNow)
{
   if (crossDownNow)
      CancelPending(ORDER_TYPE_BUY_LIMIT);
   if (crossUpNow)
      CancelPending(ORDER_TYPE_SELL_LIMIT);
}

void ManageBreakEvenAndCrossRules(bool crossUpNow, bool crossDownNow)
{
   // DEFAULT LOGIC: M1 TIMEFRAME
   // OVERRIDE for HTF: close position on cross if profitable + BE at ~1R
   if (_Period != PERIOD_M1)
   {
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

         ENUM_POSITION_TYPE ptype =
             (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         bool isProfitable =
             (ptype == POSITION_TYPE_BUY) ? (bid > entry) : (ask < entry);

         if (
             (ptype == POSITION_TYPE_BUY && crossDownNow && isProfitable) ||
             (ptype == POSITION_TYPE_SELL && crossUpNow && isProfitable))
         {
            trade.PositionClose(tk);
         }
      }

      return;
   }

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

      bool isProfitable = (ptype == POSITION_TYPE_BUY) ? (bid > entry) : (ask < entry);

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

         // ===== cross rules (KEEP SAME) =====
         if (crossDownNow)
         {
            if (isProfitable)
               trade.PositionModify(ticket, entry, tp);
            else
               trade.PositionModify(ticket, sl, entry);
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

         // ===== cross rules (KEEP SAME) =====
         if (crossUpNow)
         {
            if (isProfitable)
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
   static bool done = false;
   if (done || !IsDebugOnce)
      return;
   done = true;

   double dot1[1], h1[1], l1[1];

   ResetLastError();
   int r2 = CopyBuffer(emaHandle, 2, 1, 1, dot1);
   int e2 = GetLastError();

   ResetLastError();
   int r3 = CopyBuffer(emaHandle, 3, 1, 1, h1);
   int e3 = GetLastError();

   ResetLastError();
   int r4 = CopyBuffer(emaHandle, 4, 1, 1, l1);
   int e4 = GetLastError();

   string dotText = (r2 == 1 ? (dot1[0] == EMPTY_VALUE ? "EMPTY" : DoubleToString(dot1[0], _Digits)) : "NA");
   string hText = (r3 == 1 ? (h1[0] == EMPTY_VALUE ? "EMPTY" : DoubleToString(h1[0], _Digits)) : "NA");
   string lText = (r4 == 1 ? (l1[0] == EMPTY_VALUE ? "EMPTY" : DoubleToString(l1[0], _Digits)) : "NA");

   Print("DEBUG EMA: r2=", r2, " err2=", e2, " dot1=", dotText,
         " | r3=", r3, " err3=", e3, " high1=", hText,
         " | r4=", r4, " err4=", e4, " low1=", lText,
         " | haBars=", BarsCalculated(haHandle),
         " emaBars=", BarsCalculated(emaHandle));
}

//=================== CHART COMMENT ===============================
string FormatPriceOrNA(double v)
{
   if (v == EMPTY_VALUE)
      return "N/A";
   return DoubleToString(v, _Digits);
}

string CrossDirShort(string t)
{
   if (t == "Cross Up")
      return "Up";
   if (t == "Cross Down")
      return "Down";
   if (t == "Cross")
      return "Cross";
   return "None";
}

string FormatCrossLine()
{
   if (currentCrossText == "None")
      return "Cross : None";

   return "Cross : " + CrossDirShort(currentCrossText) +
          " at " + DoubleToString(currentCrossPrice, _Digits) +
          " at " + TimeToString(currentCrossTime, TIME_DATE | TIME_MINUTES);
}

void UpdateChartComment()
{
   if (!IsShowChartComment)
   {
      Comment("");
      return;
   }

   if (!IndicatorsReady())
   {
      Comment("Indicators not ready...\n");
      return;
   }

   double hl0Arr[1];
   hl0Arr[0] = EMPTY_VALUE;
   double ll0Arr[1];
   ll0Arr[0] = EMPTY_VALUE;

   bool hasH0 = (CopyBuffer(emaHandle, 3, 0, 1, hl0Arr) == 1 && hl0Arr[0] != EMPTY_VALUE);
   bool hasL0 = (CopyBuffer(emaHandle, 4, 0, 1, ll0Arr) == 1 && ll0Arr[0] != EMPTY_VALUE);

   // add range pips on chart comment
   double rangePips = 0.0;
   bool hasRange = (hasH0 && hasL0);
   if (hasRange)
      rangePips = MathAbs(hl0Arr[0] - ll0Arr[0]) / PipSize();

   // Broker session (FULLDAY only)
   datetime s = 0, e = 0;
   bool inSess = IsInMarketSessionNow(s, e);

   double hToEnd = 0.0;
   if (inSess)
   {
      datetime dummy = 0;
      hToEnd = HoursToSessionEnd(dummy);
   }

   // Mode-aware forbidden + endGate (VN end in SESSIONS mode)
   datetime endGate = 0;
   bool forbiddenNow = IsForbiddenNow(endGate);

   // SESSION ONLY
   datetime vnNow = GetVNTime();
   string vnNowText = TimeToString(vnNow, TIME_DATE | TIME_MINUTES);

   string vnSessName = "NONE";
   string vnWindowTxt = "N/A";
   string vnEndTxt = "N/A";

   if (TradeWindowMode == TRADEWINDOW_SESSIONS)
   {
      vnSessName = CurrentVNSessionName();
      vnWindowTxt = VNWindowTextFor(vnSessName);

      if (!forbiddenNow && endGate > 0)
      {
         datetime vnEnd = endGate + VNDeltaHours() * 3600;
         vnEndTxt = TimeToString(vnEnd, TIME_DATE | TIME_MINUTES);
      }
   }

   // PnL/DD
   double pnl = lastSessionRealizedPnL;

   string modeText = (TradeWindowMode == TRADEWINDOW_FULLDAY) ? "FULLDAY" : "SESSIONS";

   string txt = "";
   txt += "TradeMode     : " + modeText + "\n";

    if(EnablePriceZoneFilter)
      {
         txt += "─────────────────────────\n";
         txt += "PRICE ZONE FILTER: ON\n";
         txt += "BuyZoneActive : " + (buyZoneActivated ? " YES" : " NO") + "\n";
         if(buyZoneActivated && lastBuyZoneHitPrice > 0)
            txt += "  └─ Zone: " + DoubleToString(lastBuyZoneHitPrice, _Digits) + 
                  " @ " + TimeToString(lastBuyZoneHitTime, TIME_MINUTES) + "\n";
         
         txt += "SellZoneActive: " + (sellZoneActivated ? " YES" : " NO") + "\n";
         if(sellZoneActivated && lastSellZoneHitPrice > 0)
            txt += "  └─ Zone: " + DoubleToString(lastSellZoneHitPrice, _Digits) + 
                  " @ " + TimeToString(lastSellZoneHitTime, TIME_MINUTES) + "\n";
         
         txt += "TotalBuyZones : " + IntegerToString(totalBuyZones) + "\n";
         txt += "TotalSellZones: " + IntegerToString(totalSellZones) + "\n";
         txt += "─────────────────────────\n";
      }

   // --- SESSIONS: show VN block, HIDE broker MarketSession ---
   if (TradeWindowMode == TRADEWINDOW_SESSIONS)
   {
      txt += "VN Now        : " + vnNowText + "\n";
      txt += "VN Session    : " + vnSessName + "\n";
      txt += "VN Window     : " + vnWindowTxt + "\n";
      txt += "VN End        : " + vnEndTxt + "\n";
      txt += "AllowedNow    : " + (!forbiddenNow ? "YES" : "NO") + "\n";
   }

   // --- FULLDAY: show broker session block ---
   if (TradeWindowMode == TRADEWINDOW_FULLDAY)
   {
      txt += "MarketSession : " + (inSess ? (TimeToString(s, TIME_DATE | TIME_MINUTES) + " -> " + TimeToString(e, TIME_DATE | TIME_MINUTES)) : "N/A") + "\n";
      txt += "InSession     : " + (inSess ? "YES" : "NO") + "\n";
      txt += "Forbidden     : " + (forbiddenNow ? "YES" : "NO") +
             " (<= " + DoubleToString(NoNewTradesBeforeEndH, 1) +
             "h; hLeft=" + DoubleToString(hToEnd, 2) + ")\n";
   }

   // --- Strategy state (always show) ---
   txt += "HighLine(0)   : " + (hasH0 ? FormatPriceOrNA(hl0Arr[0]) : "N/A") + "\n";
   txt += "LowLine(0)    : " + (hasL0 ? FormatPriceOrNA(ll0Arr[0]) : "N/A") + "\n";
   txt += "RangePips     : " + (hasRange ? DoubleToString(rangePips, 1) : "N/A") +
          " (min=" + DoubleToString(RangeChannelEMA, 1) + ")\n";

   txt += FormatCrossLine() + "\n";
   txt += "RegimeEpoch   : " + (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0") + "\n";
   txt += "waitingBUY    : " + (waitingBUY ? "YES" : "NO") + "\n";
   txt += "waitingSELL   : " + (waitingSELL ? "YES" : "NO") + "\n";
   txt += "LastUsedHighK : " + (string)lastUsedHighKey + "\n";
   txt += "LastUsedLowK  : " + (string)lastUsedLowKey + "\n";

   // --- Risk gates ---
   txt += "SessStartBal  : " + DoubleToString(sessionStartBalance, 2) + "\n";
   txt += "SessPnL(real) : " + DoubleToString(pnl, 2) + "\n";
   txt += "DD Limit      : -" + DoubleToString(sessionLossLimit, 2) + "\n";
   txt += "DD Blocked    : " + (ddBlocked ? "YES" : "NO") + "\n";
   txt += "─────────────────────────\n";

   // Log for zones with [USED] and << for active zone (if any)
   for(int i = 0; i < totalBuyZones; i++)
   {
      string usedStr = (i < ArraySize(buyZonesUsed) && buyZonesUsed[i]) ? " [USED]" : "";
      string activeStr = (buyZoneActivated && MathAbs(buyZones[i] - lastBuyZoneHitPrice) < 0.1) ? " <<" : "";
      
      double pip = PipSize();
      double zoneFrom = buyZones[i] - ZoneActivationPips * pip;
      double zoneTo   = buyZones[i] + ZoneActivationPips * pip;
      
      txt += "  [BUY ZONE " + IntegerToString(i+1) + "] " +
            DoubleToString(buyZones[i], _Digits) +
            "  [" + DoubleToString(zoneFrom, _Digits) +
            " - " + DoubleToString(zoneTo,   _Digits) + "]" +
            usedStr + activeStr + "\n";
   }
   for(int i = 0; i < totalSellZones; i++)
   {
      string usedStr = (i < ArraySize(sellZonesUsed) && sellZonesUsed[i]) ? " [USED]" : "";
      string activeStr = (sellZoneActivated && MathAbs(sellZones[i] - lastSellZoneHitPrice) < 0.1) ? " <<" : "";
      
      double pip = PipSize();
      double zoneFrom = sellZones[i] - ZoneActivationPips * pip;
      double zoneTo   = sellZones[i] + ZoneActivationPips * pip;
      
      txt += "  [SELL ZONE " + IntegerToString(i+1) + "] " +
            DoubleToString(sellZones[i], _Digits) +
            "  [" + DoubleToString(zoneFrom, _Digits) +
            " - " + DoubleToString(zoneTo,   _Digits) + "]" +
            usedStr + activeStr + "\n";
   }
   
   Comment(txt);
}

//===================== TELEGRAM MODULE (READ-ONLY) ====================
input bool EnableTelegram = true;
input string TG_BotToken = "YOUR_TOKEN";
input string TG_ChatID = "YOUR_CHAT_ID";

input bool TG_IncludeManual = false;

// --- Anti-duplicate ---
string TG_Key(const string kind, long id)
{
   return "TLS_TG_" + _Symbol + "_" + (string)(int)_Period + "_" + kind + "_" + (string)id;
}
bool TG_Sent(const string kind, long id) { return GlobalVariableCheck(TG_Key(kind, id)); }
void TG_Mark(const string kind, long id) { GlobalVariableSet(TG_Key(kind, id), (double)TimeCurrent()); }

// --- URL encode UTF-8 (Telegram) ---
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

   uchar data[];
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   uchar result[];
   string result_headers;

   ResetLastError();
   int r = WebRequest("POST", url, headers, 5000, data, result, result_headers);
   if (r == -1)
   {
      Print("Telegram WebRequest error: ", GetLastError());
      return;
   }
}

string TG_P(double v) { return DoubleToString(v, _Digits); }

//===================== SAFE HISTORY SELECT (IMPORTANT) =================
bool TG_SelectDealSafe(ulong dealId, int retries = 10, int sleepMs = 50)
{
   for (int i = 0; i < retries; i++)
   {
      datetime to = TimeCurrent();
      datetime from = to - 60 * 60 * 24 * 30;
      HistorySelect(from, to);

      if (HistoryDealSelect(dealId))
         return true;

      Sleep(sleepMs);
   }
   return false;
}

//===================== MESSAGE FORMATS ================================
// Pending created
void TG_SendPendingLimit(bool isBuy, double et, double sl, double tp, long orderId)
{
   if (TG_Sent("PEND_LIM", orderId))
      return;

   string msg =
       string(isBuy ? "BUY LIMIT" : "SELL LIMIT") + "\n" +
       "ET  " + TG_P(et) + "\n" +
       "SL  " + TG_P(sl) + "\n" +
       "TP  " + TG_P(tp);

   TG_Send(msg);
   TG_Mark("PEND_LIM", orderId);
}

// Cancel (generic with reason)
void TG_SendCancelLimit(bool isBuy, double et, long orderId, const string reason)
{
   if (TG_Sent("CANCEL_LIM", orderId))
      return;

   string msg =
       "CANCEL " + string(isBuy ? "BUY LIMIT" : "SELL LIMIT") + "\n" +
       "ET  " + TG_P(et) + "\n" +
       "REASON: " + reason;

   TG_Send(msg);
   TG_Mark("CANCEL_LIM", orderId);
}

void TG_SendCancelLimitByCross(bool isBuy, double et, long orderId)
{
   TG_SendCancelLimit(isBuy, et, orderId, "Opposite cross");
}

void TG_SendCancelLimitByTPBeforeFilled(bool isBuy, double et, long orderId)
{
   TG_SendCancelLimit(isBuy, et, orderId, "TP hit before filled");
}

// Close position (generic with reason)
void TG_SendClosePosition(bool isBuy, double et, long positionId, const string reason)
{
   if (TG_Sent("CLOSE_POS", positionId))
      return;

   string msg =
       "CLOSE " + string(isBuy ? "BUY" : "SELL") + "\n" +
       "ET  " + TG_P(et) + "\n" +
       "REASON: " + reason;

   TG_Send(msg);
   TG_Mark("CLOSE_POS", positionId);
}

// Filled market
void TG_SendOpenMarket(bool isBuy, double et, double sl, double tp, long uniqId)
{
   if (TG_Sent("OPEN_MKT", uniqId))
      return;

   string msg =
       string(isBuy ? "BUY NOW" : "SELL NOW") + "\n" +
       "ET  " + TG_P(et) + "\n" +
       "SL  " + TG_P(sl) + "\n" +
       "TP  " + TG_P(tp);

   TG_Send(msg);
   TG_Mark("OPEN_MKT", uniqId);
}

// Filled limit
void TG_SendLimitFilled(bool isBuy, double et, double sl, double tp, long uniqId)
{
   if (TG_Sent("FILL_LIM", uniqId))
      return;

   string msg =
       string(isBuy ? "BUY LIMIT FILLED" : "SELL LIMIT FILLED") + "\n" +
       "ET  " + TG_P(et) + "\n" +
       "SL  " + TG_P(sl) + "\n" +
       "TP  " + TG_P(tp);

   TG_Send(msg);
   TG_Mark("FILL_LIM", uniqId);
}

// TP/SL
void TG_SendTP(bool isBuyEntry, bool wasLimit, double et, long dealId)
{
   string key = wasLimit ? "TP_LIM" : "TP_MKT";
   if (TG_Sent(key, dealId))
      return;

   string msg =
       "TP hit with " + string(isBuyEntry ? "BUY" : "SELL") +
       (wasLimit ? " LIMIT" : " NOW") +
       " ET = " + TG_P(et);

   TG_Send(msg);
   TG_Mark(key, dealId);
}

void TG_SendSL(bool isBuyEntry, bool wasLimit, double et, long dealId)
{
   string key = wasLimit ? "SL_LIM" : "SL_MKT";
   if (TG_Sent(key, dealId))
      return;

   string msg =
       "SL hit with " + string(isBuyEntry ? "BUY" : "SELL") +
       (wasLimit ? " LIMIT" : " NOW") +
       " ET = " + TG_P(et);

   TG_Send(msg);
   TG_Mark(key, dealId);
}

//===================== HELPERS: origin + SL/TP ========================
bool TG_GetFillOrigin(ulong dealTicket, bool &wasMarket, bool &wasLimit)
{
   wasMarket = false;
   wasLimit = false;

   if (!TG_SelectDealSafe(dealTicket))
      return false;

   ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   if (orderTicket == 0)
      return false;

   if (!HistoryOrderSelect(orderTicket))
      return false;

   ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE);
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

bool TG_GetEntryPriceFromPositionHistory(long positionId, double &etOut, bool &isBuyOut,
                                         long requiredMagic, bool includeManual)
{
   etOut = 0.0;
   isBuyOut = true;

   datetime to = TimeCurrent();
   datetime from = to - 60 * 60 * 24 * 30;
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
      if (!includeManual && magic != requiredMagic)
         continue;
      if (includeManual && magic != requiredMagic && magic != 0)
         continue;

      long pid = (long)HistoryDealGetInteger(dk, DEAL_POSITION_ID);
      if (pid != positionId)
         continue;

      long entry = (long)HistoryDealGetInteger(dk, DEAL_ENTRY);
      if (entry != DEAL_ENTRY_IN)
         continue;

      long dtype = (long)HistoryDealGetInteger(dk, DEAL_TYPE);
      isBuyOut = (dtype == DEAL_TYPE_BUY);

      etOut = HistoryDealGetDouble(dk, DEAL_PRICE);
      return true;
   }
   return false;
}

bool TG_GetSLTPForEntryDeal(ulong dealId, double &slOut, double &tpOut)
{
   slOut = 0.0;
   tpOut = 0.0;

   double dsl = HistoryDealGetDouble(dealId, DEAL_SL);
   double dtp = HistoryDealGetDouble(dealId, DEAL_TP);
   if (dsl > 0.0 || dtp > 0.0)
   {
      slOut = dsl;
      tpOut = dtp;
      return true;
   }

   ulong orderTicket = (ulong)HistoryDealGetInteger(dealId, DEAL_ORDER);
   if (orderTicket > 0 && HistoryOrderSelect(orderTicket))
   {
      slOut = HistoryOrderGetDouble(orderTicket, ORDER_SL);
      tpOut = HistoryOrderGetDouble(orderTicket, ORDER_TP);
      if (slOut > 0.0 || tpOut > 0.0)
         return true;
   }

   if (PositionSelect(_Symbol))
   {
      slOut = PositionGetDouble(POSITION_SL);
      tpOut = PositionGetDouble(POSITION_TP);
      return (slOut > 0.0 || tpOut > 0.0);
   }
   return false;
}

//===================== MAIN EVENT LISTENER ============================
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest &r,
                        const MqlTradeResult &res)
{
   if (t.symbol != _Symbol)
      return;

   // -------- Pending LIMIT created ----------
   if (t.type == TRADE_TRANSACTION_ORDER_ADD)
   {
      ulong orderId = t.order;
      if (orderId == 0)
         return;
      if (!OrderSelect(orderId))
         return;

      long magic = (long)OrderGetInteger(ORDER_MAGIC);
      if (!TG_IncludeManual && magic != MagicNumber)
         return;
      if (TG_IncludeManual && magic != MagicNumber && magic != 0)
         return;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
      {
         bool isBuy = (ot == ORDER_TYPE_BUY_LIMIT);
         TG_SendPendingLimit(isBuy,
                             OrderGetDouble(ORDER_PRICE_OPEN),
                             OrderGetDouble(ORDER_SL),
                             OrderGetDouble(ORDER_TP),
                             (long)orderId);
      }
      return;
   }

   // -------- Deal added (fills + exits) ----------
   if (t.type == TRADE_TRANSACTION_DEAL_ADD)
   {
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
      if (TG_IncludeManual && magic != MagicNumber && magic != 0)
         return;

      long entry = (long)HistoryDealGetInteger(dealId, DEAL_ENTRY);
      long reason = (long)HistoryDealGetInteger(dealId, DEAL_REASON);

      long dtype = (long)HistoryDealGetInteger(dealId, DEAL_TYPE);
      bool isBuyDeal = (dtype == DEAL_TYPE_BUY);

      // ===== ENTRY IN (FILLED) =====
      if (entry == DEAL_ENTRY_IN)
      {
         double et = HistoryDealGetDouble(dealId, DEAL_PRICE);

         double sl = 0.0, tp = 0.0;
         TG_GetSLTPForEntryDeal(dealId, sl, tp);

         bool wasMarket = false, wasLimit = false;
         if (TG_GetFillOrigin(dealId, wasMarket, wasLimit))
         {
            if (wasLimit)
               TG_SendLimitFilled(isBuyDeal, et, sl, tp, (long)dealId);
            else
               TG_SendOpenMarket(isBuyDeal, et, sl, tp, (long)dealId);
         }
         else
         {
            // fallback
            TG_SendOpenMarket(isBuyDeal, et, sl, tp, (long)dealId);
         }
         return;
      }

      // ===== EXIT OUT (TP/SL) =====
      if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         long positionId = (long)HistoryDealGetInteger(dealId, DEAL_POSITION_ID);

         double et = 0.0;
         bool isBuyEntry = true;
         TG_GetEntryPriceFromPositionHistory(positionId, et, isBuyEntry, MagicNumber, TG_IncludeManual);

         bool wasMarket = false, wasLimit = false;
         TG_GetFillOrigin(dealId, wasMarket, wasLimit);

         if (reason == DEAL_REASON_TP)
         {
            TG_SendTP(isBuyEntry, wasLimit, et, (long)dealId);
         }
         else if (reason == DEAL_REASON_SL)
         {
            TG_SendSL(isBuyEntry, wasLimit, et, (long)dealId);
         }
         else
         {
            TG_SendClosePosition(isBuyEntry, et, positionId, "Opposite cross");
         }

         return;
      }
   }
}

//=================== INIT/DEINIT ===============================
int OnInit()
{
   haHandle = iCustom(_Symbol, _Period, HAIndicatorName, BullColor, BearColor);
   if (haHandle == INVALID_HANDLE)
   {
      Print("Failed HA handle. Name=", HAIndicatorName, " err=", GetLastError());
      return INIT_FAILED;
   }

   emaHandle = iCustom(_Symbol, _Period, EMAIndicatorName, EMAShortPeriod, EMALongPeriod, EMAMethod);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("Failed EMA handle. Name=", EMAIndicatorName, " err=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetExpertMagicNumber(MagicNumber);

   LoadLineUsedFromFile();
   CleanupOldLineUsedRecords();
   
   // init DD baseline (only when inside a market session)
   ResetSessionDDIfNeeded();
   currentCrossText = "None";
   currentCrossPrice = 0.0;
   currentCrossTime = 0;
   currentRegimeEpoch = 0;
   
   waitingBUY = false;
   waitingSELL = false;
   lastUsedHighKey = 0;
   lastUsedLowKey = 0;
   
   LoadZoneUsedFromFile();
   LoadPriceZones(); 
   buyZoneActivated = false;
   sellZoneActivated = false;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   SaveLineUsedToFile();
   PrintFormat("[LINE_USED] Saved %d records on EA deinit (reason: %d)", totalUsedLines, reason);

   SaveZoneUsedToFile();
   PrintFormat("[ZONE_USED] Saved %d zone records on EA deinit (reason: %d)", totalUsedZones, reason);

   if (haHandle != INVALID_HANDLE)
      IndicatorRelease(haHandle);
   if (emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

//=================== TICK ===============================
void OnTick()
{
   UpdateZoneActivation();
   UpdateSessionDDGate();
   UpdateSessionProfitGate();

   CancelPendingIfTPHit();

   UpdateChartComment();

   if (!IndicatorsReady())
      return;

   DebugPrintEMAOnce();

   EnforceForbiddenZone();

   datetime endGate = 0;
   bool forbiddenNow = IsForbiddenNow(endGate);

   if (forbiddenNow && TradeWindowMode == TRADEWINDOW_FULLDAY)
      return;

    // =================== AUTO-ARM LOGIC ===================
    static bool didAutoArm = false;
    static datetime lastAutoArmTime = 0;
    static datetime lastSessionStart = 0;
    static int lastSessionDay = 0;
    
    datetime now = TimeCurrent();
    MqlDateTime dtNow;
    TimeToStruct(now, dtNow);
    int currentDay = dtNow.day;
    
    bool shouldAutoArm = false;
    string armReason = "";
    
    if (!didAutoArm)
    {
        shouldAutoArm = true;
        armReason = "First initialization";
    }
    else if(currentDay != lastSessionDay && lastSessionDay > 0)
    {
        shouldAutoArm = true;
        armReason = StringFormat("Day changed (old: %d, new: %d)", lastSessionDay, currentDay);
    }
    else
    {
        datetime s, e;
        if(GetCurrentSymbolSessionWindow(now, s, e))
        {
            if(s != lastSessionStart && lastSessionStart > 0)
            {
                if(MathAbs((int)(s - lastSessionStart)) > 3600)
                {
                    shouldAutoArm = true;
                    armReason = StringFormat("Session changed | Old: %s New: %s",
                                           TimeToString(lastSessionStart, TIME_DATE|TIME_MINUTES),
                                           TimeToString(s, TIME_DATE|TIME_MINUTES));
                }
            }
            lastSessionStart = s;
        }
    }
    
    // Execute auto-arm
    if(shouldAutoArm)
    {
        PrintFormat("[AUTO_ARM] Queued| Reason: %s", armReason);
        
        armPendingDeferred = true;
        didAutoArm = true;
        lastAutoArmTime = now;
        lastSessionDay = currentDay;
    }
   bool crossUpNow = false;
   bool crossDownNow = false;
   double crossPriceNow = 0.0;

   if (IsNewBar())
   {
      if(armPendingDeferred)
      {
         armPendingDeferred = false;
         PrintFormat("[AUTO_ARM] Executed on new bar (deferred, buffers fresh)");
         AutoArmFromLatestCross();
      }
      // Detect REAL cross on last closed bar
      GetCrossEventOnClosedBar(crossUpNow, crossDownNow, crossPriceNow);

      // Start new regime on TRUE cross (epoch = bar1 time)
      if (crossUpNow || crossDownNow){
         currentRegimeEpoch = iTime(_Symbol, _Period, 1);
         if(crossUpNow)
         {
            sellZoneActivated = false;
            PrintFormat("[ZONE] SELL zone deactivated (Cross Up)");
         }
         
         if(crossDownNow)
         {
            buyZoneActivated = false;
            PrintFormat("[ZONE] BUY zone deactivated (Cross Down)");
         }
      }

      // Cancel pending on opposite cross
      CancelWaitingOnOppositeCross(crossUpNow, crossDownNow);

      // Arm waiting regardless of exposure
      if (crossUpNow)
      {
         waitingBUY = true;
         waitingSELL = false;
      }

      if (crossDownNow)
      {
         waitingSELL = true;
         waitingBUY = false;
      }

      if (!ddBlocked && !profitBlocked)
      {
         long highKey = 0, lowKey = 0;

         // ===== BUY =====
         if (CheckBuyBreakoutOnClosedBar(highKey))
         {
            // skip setup to avoid FOMO
            if (TradeWindowMode == TRADEWINDOW_SESSIONS && forbiddenNow)
            {
               PrintFormat("[%s][SKIP][BUY] Breakout OUTSIDE VN session -> MARK USED (anti-FOMO) | lineKey=%I64d epoch=%s endGate=%s",
                           _Symbol, highKey,
                           (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0"),
                           (endGate > 0 ? TimeToString(endGate, TIME_DATE | TIME_MINUTES) : "N/A"));
               MarkLineUsed(true, highKey);
               waitingBUY = false;
            }
            else
            {
               if (ExecuteEntry(true, highKey))
                  MarkLineUsed(true, highKey);
            }
         }

         // ===== SELL =====
         if (CheckSellBreakoutOnClosedBar(lowKey))
         {
            if (TradeWindowMode == TRADEWINDOW_SESSIONS && forbiddenNow)
            {
               PrintFormat("[%s][SKIP][SELL] Breakout OUTSIDE VN session -> MARK USED (anti-FOMO) | lineKey=%I64d epoch=%s endGate=%s",
                           _Symbol, lowKey,
                           (currentRegimeEpoch > 0 ? TimeToString(currentRegimeEpoch, TIME_DATE | TIME_MINUTES) : "0"),
                           (endGate > 0 ? TimeToString(endGate, TIME_DATE | TIME_MINUTES) : "N/A"));
               MarkLineUsed(false, lowKey);
               waitingSELL = false;
            }
            else
            {
               if (ExecuteEntry(false, lowKey))
                  MarkLineUsed(false, lowKey);
            }
         }
      }
   }

   // Manage positions (BE + opposite cross reaction)
   ManageBreakEvenAndCrossRules(crossUpNow, crossDownNow);

   UpdateChartComment();
}