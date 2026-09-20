//+------------------------------------------------------------------+
//|                                        Signal_Candle_Scanner.mq5 |
//|          Quét chart và đánh dấu mọi pinbar / engulfing theo đúng |
//|          luật của thư viện dùng chung Signal_Candle.mqh          |
//|                                   Topic_Signal_Candle — v1.0     |
//+------------------------------------------------------------------+
// Dùng để kiểm chứng bằng mắt: nhìn một phát thấy hết tín hiệu trên chart, không phải
// chạy bot. Chạy được cả trong Strategy Tester chế độ Visual.
//
// Indicator này KHÔNG tự nghĩ ra luật nào cả — nó gọi đúng SC_IsPinbar / SC_IsEngulfing
// của thư viện. Thấy mũi tên ở đâu nghĩa là bot hỏi cây nến đó sẽ nhận được "true".
//
// CÒN VÀO LỆNH HAY KHÔNG LẠI LÀ CHUYỆN KHÁC: mỗi bot còn lớp điều kiện vị trí của riêng
// nó (BOT_CRT đòi nến phải quét qua biên H4 và biên đó chưa dùng...). Mũi tên ở đây là
// điều kiện CẦN về hình dạng nến, không phải lệnh sẽ vào.
//
// Vì pinbar phải hỏi theo chiều, mỗi cây nến được hỏi CẢ HAI chiều: mũi tên xanh dưới
// đáy = tín hiệu MUA, mũi tên đỏ trên đỉnh = tín hiệu BÁN.
//
// Cây nến ĐANG CHẠY không bao giờ được xét — nó còn đổi hình tới lúc đóng.
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#include <Signal_Candle.mqh>   // dùng chung, lấy từ MQL5/Include (bản gốc: Lib_Signal_Candle/)

input group "--- Loai tin hieu ---"
input bool Inp_Ve_Pinbar    = true;    // Đánh dấu pinbar
input bool Inp_Ve_Engulfing = true;    // Đánh dấu engulfing
input int  Inp_SoNenQuet    = 500;     // Số nến quét gần nhất (0 = toàn bộ chart)

// Mỹ thuật để const theo quy ước của repo — muốn đổi thì sửa ở đây rồi compile lại.
const color  CLR_PIN_BUY  = clrDodgerBlue;
const color  CLR_PIN_SELL = clrOrangeRed;
const color  CLR_ENG_BUY  = clrLime;
const color  CLR_ENG_SELL = clrMagenta;
const uchar  ARROW_PIN_UP = 233;   // mũi tên lên (Wingdings)
const uchar  ARROW_PIN_DN = 234;   // mũi tên xuống
const uchar  ARROW_ENG_UP = 241;
const uchar  ARROW_ENG_DN = 242;
const int    ARROW_WIDTH  = 1;
const int    ARROW_SHIFT  = 12;    // đẩy mũi tên ra khỏi nến, tính bằng pixel

double BufPinBuy[], BufPinSell[], BufEngBuy[], BufEngSell[];

void SetupPlot(int idx, double &buf[], string label, color clr, uchar code, int shift_px)
{
   SetIndexBuffer(idx, buf, INDICATOR_DATA);
   PlotIndexSetInteger(idx, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(idx, PLOT_ARROW, code);
   PlotIndexSetInteger(idx, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(idx, PLOT_LINE_WIDTH, ARROW_WIDTH);
   PlotIndexSetInteger(idx, PLOT_ARROW_SHIFT, shift_px);
   PlotIndexSetString (idx, PLOT_LABEL, label);
   PlotIndexSetDouble (idx, PLOT_EMPTY_VALUE, 0.0);
   ArraySetAsSeries(buf, false);
}

int OnInit()
{
   // Mũi tên MUA nằm DƯỚI đáy nến (shift dương = đẩy xuống), mũi tên BÁN nằm TRÊN đỉnh.
   SetupPlot(0, BufPinBuy,  "Pinbar MUA",    CLR_PIN_BUY,  ARROW_PIN_UP,  ARROW_SHIFT);
   SetupPlot(1, BufPinSell, "Pinbar BÁN",    CLR_PIN_SELL, ARROW_PIN_DN, -ARROW_SHIFT);
   SetupPlot(2, BufEngBuy,  "Engulfing MUA", CLR_ENG_BUY,  ARROW_ENG_UP,  ARROW_SHIFT);
   SetupPlot(3, BufEngSell, "Engulfing BÁN", CLR_ENG_SELL, ARROW_ENG_DN, -ARROW_SHIFT);

   IndicatorSetString(INDICATOR_SHORTNAME, "Signal_Candle_Scanner");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
}

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
   if(rates_total < 3) return 0;

   // MQL5 KHÔNG tự xoá buffer indicator, ô chưa ghi có thể chứa giá trị rác. Với
   // PLOT_EMPTY_VALUE = 0 thì rác sẽ thành mũi tên ở mức giá vô lý, kéo giãn cả thang giá.
   // Nên xoá sạch ở lượt tính đầu — cũng là lúc phần ngoài Inp_SoNenQuet không được ghi.
   if(prev_calculated == 0)
   {
      ArrayInitialize(BufPinBuy,  0.0);
      ArrayInitialize(BufPinSell, 0.0);
      ArrayInitialize(BufEngBuy,  0.0);
      ArrayInitialize(BufEngSell, 0.0);
   }

   // i = 1 là cây sớm nhất xét được: engulfing cần cây liền trước (i - 1).
   int first = 1;
   if(Inp_SoNenQuet > 0 && rates_total - Inp_SoNenQuet > first)
      first = rates_total - Inp_SoNenQuet;

   // Lượt đầu quét lại từ đầu; các lượt sau chỉ tính cây mới đóng.
   int start = (prev_calculated > 1) ? prev_calculated - 1 : first;
   if(start < first) start = first;

   int n_pin = 0, n_eng = 0;

   // Dừng ở rates_total - 2: cây cuối (rates_total - 1) đang chạy, chưa đóng, không xét.
   for(int i = start; i <= rates_total - 2; i++)
   {
      BufPinBuy[i] = 0.0; BufPinSell[i] = 0.0; BufEngBuy[i] = 0.0; BufEngSell[i] = 0.0;

      SCandle cur;  cur.o  = open[i];     cur.h  = high[i];
                    cur.l  = low[i];      cur.c  = close[i];
      SCandle prev; prev.o = open[i - 1]; prev.h = high[i - 1];
                    prev.l = low[i - 1];  prev.c = close[i - 1];

      if(Inp_Ve_Pinbar)
      {
         if(SC_IsPinbar( 1, cur)) { BufPinBuy[i]  = low[i];  n_pin++; }
         if(SC_IsPinbar(-1, cur)) { BufPinSell[i] = high[i]; n_pin++; }
      }
      if(Inp_Ve_Engulfing)
      {
         if(SC_IsEngulfing( 1, prev, cur)) { BufEngBuy[i]  = low[i];  n_eng++; }
         if(SC_IsEngulfing(-1, prev, cur)) { BufEngSell[i] = high[i]; n_eng++; }
      }
   }

   // Cây đang chạy luôn để trống, tránh mũi tên nhấp nháy rồi biến mất.
   BufPinBuy[rates_total - 1] = 0.0; BufPinSell[rates_total - 1] = 0.0;
   BufEngBuy[rates_total - 1] = 0.0; BufEngSell[rates_total - 1] = 0.0;

   if(prev_calculated <= 1)
      PrintFormat("[SC][scanner] %s %s · quét %d nến (từ %s): %d pinbar, %d engulfing.",
                  _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                  rates_total - 1 - first, TimeToString(time[first], TIME_DATE|TIME_MINUTES),
                  n_pin, n_eng);

   return rates_total;
}
