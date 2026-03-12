//+------------------------------------------------------------------+
//|                                                    TLS_iFVG.mq5 |
//|                    IFVG Buy & Sell Zones  v2.0                   |
//|                                                                  |
//|  THEORY (based on Pine IFVG_Chinh logic):                       |
//|                                                                  |
//|  FVG = 3-candle pattern with displacement filter                 |
//|                                                                  |
//|  Bearish FVG:  low[c1] > high[c3]                               |
//|    + c2 displacement: low[c2] <= low[c1] AND high[c2] >= high[c3]
//|    + fvg_len > ATR(20) * InpDisplacement / 10                   |
//|    Zone top    = low[c1]                                         |
//|    Zone bottom = high[c3]                                        |
//|    Invalidated: close[j] > top  (close only, no wick)           |
//|    → Becomes BULLISH IFVG (support zone for long entries)        |
//|    Kill: close[j] < bottom  (close only, no wick)               |
//|                                                                  |
//|  Bullish FVG:  high[c1] < low[c3]                               |
//|    + c2 displacement: low[c2] <= low[c3] AND high[c2] >= high[c1]
//|    + fvg_len > ATR(20) * InpDisplacement / 10                   |
//|    Zone top    = low[c3]   → HIGHER price (cạnh trên)           |
//|    Zone bottom = high[c1]  → LOWER price  (cạnh dưới)           |
//|    Invalidated: close[j] < bottom = high[c1]  (close only)      |
//|    → Becomes BEARISH IFVG (resistance zone for short entries)    |
//|    Kill: close[j] > top = low[c3]  (close only)                 |
//+------------------------------------------------------------------+
#property copyright "IFVG Buy & Sell Zones v2.0"
#property strict
#property indicator_chart_window

#property indicator_buffers 5
#property indicator_plots 4

#property indicator_label1 "BuyTop"
#property indicator_type1 DRAW_NONE

#property indicator_label2 "BuyBottom"
#property indicator_type2 DRAW_NONE

#property indicator_label3 "SellTop"
#property indicator_type3 DRAW_NONE

#property indicator_label4 "SellBottom"
#property indicator_type4 DRAW_NONE

double BufBuyTop[];
double BufBuyBot[];
double BufSellTop[];
double BufSellBot[];
double BufInvTime[];

//--- Inputs
input int InpLookback = 300;
input color InpBuyColor = C '13,186,186';
input color InpSellColor = C '220,50,50';
input int InpAlpha = 55;
input int InpExtendBars = 30;
input int InpDisplacement = 3; // ATR displacement filter (same as Pine disp_x)
input int InpAtrPeriod = 20;   // ATR period for displacement check

#define PFX "IFVG4_"

enum ZONE_TYPE
{
   ZONE_BUY = 0,
   ZONE_SELL = 1
};

struct Zone
{
   int c2;
   double top;
   double bottom;
   int inv_bar;
   bool alive;
   bool drawn;
   ZONE_TYPE ztype;
};

Zone g_zones[];
int g_count = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufBuyTop, INDICATOR_DATA);
   SetIndexBuffer(1, BufBuyBot, INDICATOR_DATA);
   SetIndexBuffer(2, BufSellTop, INDICATOR_DATA);
   SetIndexBuffer(3, BufSellBot, INDICATOR_DATA);

   ArraySetAsSeries(BufBuyTop, false);
   ArraySetAsSeries(BufBuyBot, false);
   ArraySetAsSeries(BufSellTop, false);
   ArraySetAsSeries(BufSellBot, false);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   SetIndexBuffer(4, BufInvTime, INDICATOR_CALCULATIONS);
   ArraySetAsSeries(BufInvTime, false);

   ChartClean();
   g_count = 0;
   ArrayResize(g_zones, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { ChartClean(); }

//+------------------------------------------------------------------+
//| ATR-based displacement check (Pine: avg_over * disp_x / 10)     |
//| fvg_len > sum(high[i]-low[i], 0..period) / period * disp / 10   |
//+------------------------------------------------------------------+
double CalcATR(const double &high[], const double &low[], int bar, int period)
{
   if (bar < period)
      return 0.0;
   double sum = 0.0;
   for (int i = bar - period; i < bar; i++)
      sum += high[i] - low[i];
   return sum / period;
}

bool PassDisplacement(double fvgLen, const double &high[], const double &low[], int bar)
{
   if (InpDisplacement <= 0)
      return true;
   double atr = CalcATR(high, low, bar, InpAtrPeriod);
   if (atr <= 0.0)
      return true;
   return fvgLen > atr * InpDisplacement / 10.0;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if (rates_total < InpAtrPeriod + 5)
      return 0;

   int resetFrom = (prev_calculated > 1) ? prev_calculated - 1 : 0;
   for (int i = resetFrom; i < rates_total; i++)
   {
      BufBuyTop[i] = EMPTY_VALUE;
      BufBuyBot[i] = EMPTY_VALUE;
      BufSellTop[i] = EMPTY_VALUE;
      BufSellBot[i] = EMPTY_VALUE;
      BufInvTime[i] = 0.0;
   }

   if (prev_calculated == 0)
   {
      ChartClean();
      g_count = 0;
      ArrayResize(g_zones, 0);
   }

   int from = MathMax(InpAtrPeriod + 2, rates_total - InpLookback);

   // ================================================================
   // PASS 1 – Detect new FVGs with displacement + c2 touch filter
   // ================================================================
   for (int i = from; i <= rates_total - 2; i++)
   {
      int c1 = i - 1, c2 = i, c3 = i + 1;

      //--- Bearish FVG → future BULLISH IFVG
      //    Gap: low[c1] > high[c3]
      //    c2 touches gap: low[c2] <= low[c1] AND high[c2] >= high[c3]
      //    (Pine: tf_l.get(1) <= tf_h.get(2) AND tf_h.get(1) >= tf_l.get(0))
      if (low[c1] > high[c3] && ZoneByC2(c2, ZONE_BUY) < 0)
      {
         double fvgLen = low[c1] - high[c3];
         bool c2touch = (low[c2] <= low[c1]) && (high[c2] >= high[c3]);
         if (c2touch && PassDisplacement(fvgLen, high, low, c2))
         {
            int k = g_count;
            ArrayResize(g_zones, k + 1);
            g_zones[k].c2 = c2;
            g_zones[k].top = low[c1];
            g_zones[k].bottom = high[c3];
            g_zones[k].inv_bar = -1;
            g_zones[k].alive = false;
            g_zones[k].drawn = false;
            g_zones[k].ztype = ZONE_BUY;
            g_count++;
         }
      }

      //--- Bullish FVG → future BEARISH IFVG
      //    Gap: high[c1] < low[c3]
      //    c2 touches gap: low[c2] <= low[c3] AND high[c2] >= high[c1]
      //    Zone top    = low[c3]  → HIGHER price (cạnh trên thực sự)
      //    Zone bottom = high[c1] → LOWER price  (cạnh dưới thực sự)
      //    Invalidated: close < bottom (close < high[c1])
      if (high[c1] < low[c3] && ZoneByC2(c2, ZONE_SELL) < 0)
      {
         double fvgLen = low[c3] - high[c1];
         bool c2touch = (low[c2] <= low[c3]) && (high[c2] >= high[c1]);
         if (c2touch && PassDisplacement(fvgLen, high, low, c2))
         {
            int k = g_count;
            ArrayResize(g_zones, k + 1);
            g_zones[k].c2 = c2;
            g_zones[k].top = low[c3];     // higher price = cạnh trên
            g_zones[k].bottom = high[c1]; // lower price  = cạnh dưới
            g_zones[k].inv_bar = -1;
            g_zones[k].alive = false;
            g_zones[k].drawn = false;
            g_zones[k].ztype = ZONE_SELL;
            g_count++;
         }
      }
   }

   // ================================================================
   // PASS 2 – Find inv_bar (CLOSE only, no wick — Pine logic)
   //
   //   BULLISH IFVG: Bearish FVG broken when close > top
   //   BEARISH IFVG: Bullish FVG broken when close < bottom
   // ================================================================
   for (int k = 0; k < g_count; k++)
   {
      if (g_zones[k].inv_bar >= 0)
         continue;

      int c3start = g_zones[k].c2 + 1;
      double zt = g_zones[k].top;
      double zb = g_zones[k].bottom;

      for (int j = c3start + 1; j < rates_total; j++)
      {
         if (g_zones[k].ztype == ZONE_BUY)
         {
            // Bearish FVG invalidated: close breaks above top (close only)
            if (close[j] > zt)
            {
               g_zones[k].inv_bar = j;
               g_zones[k].alive = true;
               break;
            }
         }
         else
         {
            // Bullish FVG invalidated: close breaks below bottom = high[c1] (close only)
            // bottom = high[c1] = lower edge of the gap
            if (close[j] < zb)
            {
               g_zones[k].inv_bar = j;
               g_zones[k].alive = true;
               break;
            }
         }
      }
   }

   // ================================================================
   // PASS 3 – Draw newly alive zones
   // ================================================================
   for (int k = 0; k < g_count; k++)
   {
      if (!g_zones[k].alive || g_zones[k].drawn)
         continue;
      int inv = g_zones[k].inv_bar;
      if (inv < 0 || inv >= rates_total)
         continue;

      color zc = (g_zones[k].ztype == ZONE_BUY) ? InpBuyColor : InpSellColor;
      ZoneDraw(k, time[inv], g_zones[k].top, g_zones[k].bottom, zc);
      g_zones[k].drawn = true;
   }

   // ================================================================
   // PASS 4 – Kill zone (CLOSE only — Pine logic)
   //
   //   BULLISH IFVG killed: close < bottom
   //   BEARISH IFVG killed: close > top
   //
   //   Scan starts at inv_bar+1
   // ================================================================
   for (int k = 0; k < g_count; k++)
   {
      if (!g_zones[k].alive || !g_zones[k].drawn)
         continue;

      int jstart = g_zones[k].inv_bar + 1;
      double zt = g_zones[k].top;
      double zb = g_zones[k].bottom;

      if (jstart >= rates_total)
         continue;

      for (int j = jstart; j < rates_total; j++)
      {
         if (g_zones[k].ztype == ZONE_BUY)
         {
            // Bullish IFVG killed: close falls past bottom (close only)
            if (close[j] < zb)
            {
               g_zones[k].alive = false;
               TrimZone(k, time[j]);
               break;
            }
         }
         else
         {
            // Bearish IFVG killed: close rises past top (close only)
            if (close[j] > zt)
            {
               g_zones[k].alive = false;
               TrimZone(k, time[j]);
               break;
            }
         }
      }
   }

   // ================================================================
   // PASS 5 – Fill buffers for alive zones
   // ================================================================
   datetime t_right = time[rates_total - 1] + (datetime)(PeriodSeconds() * InpExtendBars);

   for (int k = 0; k < g_count; k++)
   {
      if (!g_zones[k].alive || !g_zones[k].drawn)
         continue;
      int inv = g_zones[k].inv_bar;
      if (inv < 0)
         continue;

      for (int bar = inv; bar < rates_total; bar++)
      {
         if (!g_zones[k].alive)
            break;

         if (g_zones[k].ztype == ZONE_BUY)
         {
            BufBuyTop[bar] = g_zones[k].top;
            BufBuyBot[bar] = g_zones[k].bottom;
         }
         else
         {
            BufSellTop[bar] = g_zones[k].top;
            BufSellBot[bar] = g_zones[k].bottom;
         }
         BufInvTime[bar] = (bar == inv) ? (double)time[inv] : 0.0;
      }

      string rn = ZoneRectName(k);
      if (ObjectFind(0, rn) >= 0)
         ObjectSetInteger(0, rn, OBJPROP_TIME, 1, t_right);
   }

   ChartRedraw(0);
   return rates_total;
}

//+------------------------------------------------------------------+
int ZoneByC2(int c2, ZONE_TYPE zt)
{
   for (int k = 0; k < g_count; k++)
      if (g_zones[k].c2 == c2 && g_zones[k].ztype == zt)
         return k;
   return -1;
}

string ZoneRectName(int k)
{
   string t = (g_zones[k].ztype == ZONE_BUY) ? "B" : "S";
   return PFX + "R_" + t + IntegerToString(g_zones[k].c2);
}

string ZoneTxtName(int k)
{
   string t = (g_zones[k].ztype == ZONE_BUY) ? "B" : "S";
   return PFX + "T_" + t + IntegerToString(g_zones[k].c2);
}

void TrimZone(int k, datetime t_kill)
{
   string rn = ZoneRectName(k);
   if (ObjectFind(0, rn) >= 0)
      ObjectSetInteger(0, rn, OBJPROP_TIME, 1, (long)t_kill + PeriodSeconds());
}

void ZoneDraw(int k, datetime t_start, double top, double bot, color zc)
{
   string rn = ZoneRectName(k);
   string tn = ZoneTxtName(k);
   if (ObjectFind(0, rn) >= 0)
      return;

   color fill = ColorBlend(zc, InpAlpha);
   datetime t_end = t_start + (datetime)(PeriodSeconds() * 10);
   string lbl = (g_zones[k].ztype == ZONE_BUY) ? "iFVG Buy" : "iFVG Sell";

   ObjectCreate(0, rn, OBJ_RECTANGLE, 0, t_start, top, t_end, bot);
   ObjectSetInteger(0, rn, OBJPROP_COLOR, fill);
   ObjectSetInteger(0, rn, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, rn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, rn, OBJPROP_FILL, true);
   ObjectSetInteger(0, rn, OBJPROP_BACK, true);
   ObjectSetInteger(0, rn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, rn, OBJPROP_ZORDER, 0);

   ObjectCreate(0, tn, OBJ_TEXT, 0, t_start, top);
   ObjectSetString(0, tn, OBJPROP_TEXT, lbl);
   ObjectSetInteger(0, tn, OBJPROP_COLOR, zc);
   ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, tn, OBJPROP_BACK, true);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
}

color ColorBlend(color clr, int alpha)
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int fg_r = (int)((clr >> 16) & 0xFF);
   int fg_g = (int)((clr >> 8) & 0xFF);
   int fg_b = (int)(clr & 0xFF);
   int bg_r = (int)((bg >> 16) & 0xFF);
   int bg_g = (int)((bg >> 8) & 0xFF);
   int bg_b = (int)(bg & 0xFF);
   int a = MathMax(0, MathMin(255, alpha));
   int r = fg_r * a / 255 + bg_r * (255 - a) / 255;
   int g = fg_g * a / 255 + bg_g * (255 - a) / 255;
   int b = fg_b * a / 255 + bg_b * (255 - a) / 255;
   return (color)(MathMin(r, 255) << 16 | MathMin(g, 255) << 8 | MathMin(b, 255));
}

void ChartClean()
{
   for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, -1);
      if (StringFind(n, PFX) == 0)
         ObjectDelete(0, n);
   }
}