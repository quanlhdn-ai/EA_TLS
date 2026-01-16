#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1

//--- Plot settings
#property indicator_label1  "HA Open;HA High;HA Low;HA Close"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// --- KHAI BÁO MÀU SẮC TRADINGVIEW (RGB) ---
// Màu Xanh TV: R=8, G=153, B=129
// Màu Đỏ TV:   R=242, G=54, B=69
#property indicator_color1  C'8,153,129', C'242,54,69'

//--- Inputs (Mặc định dùng màu TV luôn)
input color InpBullColor = C'8,153,129';   // TV Teal Green
input color InpBearColor = C'242,54,69';   // TV Red

//--- Buffers
double         HAOpenBuffer[];
double         HAHighBuffer[];
double         HALowBuffer[];
double         HACloseBuffer[];
double         HAColorBuffer[]; // 0 for Bull, 1 for Bear

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, HAOpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, HAHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, HALowBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, HACloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, HAColorBuffer, INDICATOR_COLOR_INDEX);
   
   // Gán màu vào Index vẽ
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpBullColor);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpBearColor);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   int start = prev_calculated;
   if(start < 1)
     {
      start = 1;
      HAOpenBuffer[0] = (open[0] + close[0]) / 2;
      HACloseBuffer[0] = (open[0] + high[0] + low[0] + close[0]) / 4;
      HAHighBuffer[0] = high[0];
      HALowBuffer[0] = low[0];
     }
   else start--;

   for(int i = start; i < rates_total; i++)
     {
      HACloseBuffer[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      HAOpenBuffer[i] = (HAOpenBuffer[i-1] + HACloseBuffer[i-1]) / 2.0;
      HAHighBuffer[i] = MathMax(high[i], MathMax(HAOpenBuffer[i], HACloseBuffer[i]));
      HALowBuffer[i] = MathMin(low[i], MathMin(HAOpenBuffer[i], HACloseBuffer[i]));

      if(HACloseBuffer[i] >= HAOpenBuffer[i])
         HAColorBuffer[i] = 0; // Bull (Màu Xanh TV)
      else
         HAColorBuffer[i] = 1; // Bear (Màu Đỏ TV)
     }

   return(rates_total);
  }