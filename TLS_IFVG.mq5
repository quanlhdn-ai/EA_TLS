//+------------------------------------------------------------------+
//|                                                       IFVG.mq5  |
//|              Inversion Fair Value Gap  –  BUY & SELL Zones      |
//|                                          v4.00                  |
//+------------------------------------------------------------------+
//
//  THEORY
//  ──────
//  FVG = 3-candle pattern
//
//  Bearish FVG:  low[c1] > high[c3]
//    Zone top    = low[c1]
//    Zone bottom = high[c3]
//    Invalidated (wick OR close breaks above top):
//      high[j] > top OR close[j] > top
//    → Becomes BULLISH IFVG (support zone for long entries)
//    Kill: price past bottom → low[j] < bottom OR close[j] < bottom
//
//  Bullish FVG:  high[c1] < low[c3]
//    Zone top    = low[c3]
//    Zone bottom = high[c1]
//    Invalidated (wick OR close breaks below bottom):
//      low[j] < bottom OR close[j] < bottom
//    → Becomes BEARISH IFVG (resistance zone for short entries)
//    Kill: price past top → high[j] > top OR close[j] > top
//
//  NOTE: No "fill required before kill" — zone is killed the moment
//        price passes the kill level, regardless of prior interaction.
//
//+------------------------------------------------------------------+
#property copyright   "IFVG Buy & Sell Zones"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//--- Inputs
input int    InpLookback   = 300;            // Lookback bars
input color  InpBuyColor   = C'13,186,186';  // BUY  zone color (teal)
input color  InpSellColor  = C'220,50,50';   // SELL zone color (red)
input int    InpAlpha      = 55;             // Fill opacity 0-255
input int    InpExtendBars = 30;             // Bars to extend a live zone right

#define PFX "IFVG4_"

enum ZONE_TYPE { ZONE_BUY = 0, ZONE_SELL = 1 };

struct Zone
{
   int        c2;       // middle bar index of original FVG
   double     top;      // upper price edge
   double     bottom;   // lower price edge
   int        inv_bar;  // bar that invalidated the FVG (-1 = not yet)
   bool       alive;    // false = zone killed
   bool       drawn;    // true once chart object created
   ZONE_TYPE  ztype;
};

Zone g_zones[];
int  g_count = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   ChartClean();
   g_count = 0;
   ArrayResize(g_zones, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { ChartClean(); }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < 5) return 0;

   if(prev_calculated == 0)
   {
      ChartClean();
      g_count = 0;
      ArrayResize(g_zones, 0);
   }

   int from = MathMax(1, rates_total - InpLookback);

   // ================================================================
   // PASS 1 – Detect new FVGs and register them
   //   c1 = i-1 | c2 = i | c3 = i+1
   //   Loop to rates_total-2 so c3 is always a valid index
   // ================================================================
   for(int i = from; i <= rates_total - 2; i++)
   {
      int c1 = i - 1;
      int c2 = i;
      int c3 = i + 1;

      //--- Bearish FVG → future BULLISH IFVG
      //    Condition: gap between c1 low and c3 high
      if(low[c1] > high[c3] && ZoneByC2(c2, ZONE_BUY) < 0)
      {
         int k = g_count;
         ArrayResize(g_zones, k + 1);
         g_zones[k].c2      = c2;
         g_zones[k].top     = low[c1];
         g_zones[k].bottom  = high[c3];
         g_zones[k].inv_bar = -1;
         g_zones[k].alive   = false;
         g_zones[k].drawn   = false;
         g_zones[k].ztype   = ZONE_BUY;
         g_count++;
      }

      //--- Bullish FVG → future BEARISH IFVG
      //    Condition: gap between c1 high and c3 low
      if(high[c1] < low[c3] && ZoneByC2(c2, ZONE_SELL) < 0)
      {
         int k = g_count;
         ArrayResize(g_zones, k + 1);
         g_zones[k].c2      = c2;
         g_zones[k].top     = low[c3];
         g_zones[k].bottom  = high[c1];
         g_zones[k].inv_bar = -1;
         g_zones[k].alive   = false;
         g_zones[k].drawn   = false;
         g_zones[k].ztype   = ZONE_SELL;
         g_count++;
      }
   }

   // ================================================================
   // PASS 2 – Find inv_bar for unresolved zones
   //
   //   BULLISH IFVG: Bearish FVG broken when wick or close > top
   //     high[j] > top OR close[j] > top
   //
   //   BEARISH IFVG: Bullish FVG broken when wick or close < bottom
   //     low[j] < bottom OR close[j] < bottom
   // ================================================================
   for(int k = 0; k < g_count; k++)
   {
      if(g_zones[k].inv_bar >= 0) continue;

      int    c3start = g_zones[k].c2 + 1;
      double zt      = g_zones[k].top;
      double zb      = g_zones[k].bottom;

      for(int j = c3start + 1; j < rates_total; j++)
      {
         if(g_zones[k].ztype == ZONE_BUY)
         {
            if(high[j] > zt || close[j] > zt)
            {
               g_zones[k].inv_bar = j;
               g_zones[k].alive   = true;
               break;
            }
         }
         else
         {
            if(low[j] < zb || close[j] < zb)
            {
               g_zones[k].inv_bar = j;
               g_zones[k].alive   = true;
               break;
            }
         }
      }
   }

   // ================================================================
   // PASS 3 – Draw newly alive zones starting at time[inv_bar]
   // ================================================================
   for(int k = 0; k < g_count; k++)
   {
      if(!g_zones[k].alive || g_zones[k].drawn) continue;

      int inv = g_zones[k].inv_bar;
      if(inv < 0 || inv >= rates_total) continue;

      color zc = (g_zones[k].ztype == ZONE_BUY) ? InpBuyColor : InpSellColor;
      ZoneDraw(k, time[inv], g_zones[k].top, g_zones[k].bottom, zc);
      g_zones[k].drawn = true;
   }

   // ================================================================
   // PASS 4 – Kill zone if price passes the kill level
   //
   //   BULLISH IFVG killed when price falls past bottom:
   //     low[j] < bottom OR close[j] < bottom
   //
   //   BEARISH IFVG killed when price rises past top:
   //     high[j] > top OR close[j] > top
   //
   //   No "fill required" — zone is killed the moment price
   //   crosses the kill level, regardless of prior interaction.
   //   Scan starts at inv_bar+1 — the inv_bar itself is the bar
   //   that broke the FVG, not a valid kill candidate.
   // ================================================================
   for(int k = 0; k < g_count; k++)
   {
      if(!g_zones[k].alive || !g_zones[k].drawn) continue;

      int    jstart = g_zones[k].inv_bar + 1;
      double zt     = g_zones[k].top;
      double zb     = g_zones[k].bottom;

      if(jstart >= rates_total) continue;

      for(int j = jstart; j < rates_total; j++)
      {
         if(g_zones[k].ztype == ZONE_BUY)
         {
            // Bullish IFVG killed: price falls past bottom (wick or close)
            if(low[j] < zb || close[j] < zb)
            {
               g_zones[k].alive = false;
               TrimZone(k, time[j]);
               break;
            }
         }
         else
         {
            // Bearish IFVG killed: price rises past top (wick or close)
            if(high[j] > zt || close[j] > zt)
            {
               g_zones[k].alive = false;
               TrimZone(k, time[j]);
               break;
            }
         }
      }
   }

   // ================================================================
   // PASS 5 – Extend alive zones to current bar + InpExtendBars
   // ================================================================
   datetime t_right = time[rates_total - 1]
                      + (datetime)(PeriodSeconds() * InpExtendBars);

   for(int k = 0; k < g_count; k++)
   {
      if(!g_zones[k].alive || !g_zones[k].drawn) continue;
      string rn = ZoneRectName(k);
      if(ObjectFind(0, rn) >= 0)
         ObjectSetInteger(0, rn, OBJPROP_TIME, 1, t_right);
   }

   ChartRedraw(0);
   return rates_total;
}

//+------------------------------------------------------------------+
//  HELPERS
//+------------------------------------------------------------------+
int ZoneByC2(int c2, ZONE_TYPE zt)
{
   for(int k = 0; k < g_count; k++)
      if(g_zones[k].c2 == c2 && g_zones[k].ztype == zt)
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
   if(ObjectFind(0, rn) >= 0)
      ObjectSetInteger(0, rn, OBJPROP_TIME, 1,
                       (long)t_kill + PeriodSeconds());
}

//+------------------------------------------------------------------+
void ZoneDraw(int k, datetime t_start, double top, double bot, color zc)
{
   string rn  = ZoneRectName(k);
   string tn  = ZoneTxtName(k);
   if(ObjectFind(0, rn) >= 0) return;

   color    fill  = ColorBlend(zc, InpAlpha);
   datetime t_end = t_start + (datetime)(PeriodSeconds() * 10);
   string   lbl   = (g_zones[k].ztype == ZONE_BUY) ? "iFVG Buy" : "iFVG Sell";

   ObjectCreate(0, rn, OBJ_RECTANGLE, 0, t_start, top, t_end, bot);
   ObjectSetInteger(0, rn, OBJPROP_COLOR,      fill);
   ObjectSetInteger(0, rn, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, rn, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, rn, OBJPROP_FILL,       true);
   ObjectSetInteger(0, rn, OBJPROP_BACK,       true);
   ObjectSetInteger(0, rn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rn, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, rn, OBJPROP_ZORDER,     0);

   ObjectCreate(0, tn, OBJ_TEXT, 0, t_start, top);
   ObjectSetString(0,  tn, OBJPROP_TEXT,       lbl);
   ObjectSetInteger(0, tn, OBJPROP_COLOR,      zc);
   ObjectSetInteger(0, tn, OBJPROP_FONTSIZE,   7);
   ObjectSetInteger(0, tn, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, tn, OBJPROP_BACK,       true);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tn, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
color ColorBlend(color clr, int alpha)
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   int fg_r = (int)((clr >> 16) & 0xFF);
   int fg_g = (int)((clr >>  8) & 0xFF);
   int fg_b = (int)( clr        & 0xFF);

   int bg_r = (int)((bg >> 16) & 0xFF);
   int bg_g = (int)((bg >>  8) & 0xFF);
   int bg_b = (int)( bg        & 0xFF);

   int a = MathMax(0, MathMin(255, alpha));

   int r = fg_r * a / 255 + bg_r * (255 - a) / 255;
   int g = fg_g * a / 255 + bg_g * (255 - a) / 255;
   int b = fg_b * a / 255 + bg_b * (255 - a) / 255;

   return (color)(MathMin(r,255) << 16 | MathMin(g,255) << 8 | MathMin(b,255));
}

//+------------------------------------------------------------------+
void ChartClean()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PFX) == 0)
         ObjectDelete(0, n);
   }
}