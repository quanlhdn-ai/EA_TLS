//+------------------------------------------------------------------+
//|                                                Signal_Candle.mqh |
//|                     Thư viện nến tín hiệu dùng chung cho các bot |
//|                                   Topic_Signal_Candle — v1.1     |
//+------------------------------------------------------------------+
// Chỉ xét HÌNH DẠNG nến. Điều kiện vị trí (nến phải nằm ở mốc / Zone / biên nào) là việc
// của từng bot, không đưa vào đây — để một định nghĩa nến dùng được cho mọi chiến lược.
//
// Quy ước chiều: dir = 1 là tín hiệu MUA, dir = -1 là tín hiệu BÁN.
//
// Định nghĩa chốt với người dùng ngày 2026-09-11, đối chiếu trên 4 mẫu engulfing XAUUSD H1.
//
// PINBAR (1 nến) — KHÔNG xét màu thân nến:
//   1. Râu phía quét ("mũi") >= 1.5 x thân.
//   2. Râu mũi >= 60% biên độ (High - Low).
//   3. Râu phía đối diện <= 25% biên độ.
//   Điều 2 và 3 vá hai kẽ hở của luật cũ chỉ so râu với thân: nến có râu đối diện dài
//   hơn râu mũi, và nến doji thân rất nhỏ, đều từng lọt.
//
//   [v1.1 — 2026-09-12] BỎ ĐIỀU KIỆN "nến đóng thuận chiều lệnh" có ở v1.0.
//   Bằng chứng: soi 6 cây nến bị BOT_CRT loại trong backtest 01-11/09/2026 (XAUUSD
//   M5/M15), 4 cây trượt DUY NHẤT vì màu thân trong khi cả 3 điều kiện hình dạng đều
//   đạt thoáng. Ca nặng nhất 2026.09.08 12:15 M5: râu mũi 92.0% biên độ, râu đối diện
//   1.8%, quét thủng biên rồi đóng lùi sâu vào trong — bị loại chỉ vì giá đóng thấp hơn
//   giá mở 4.3 pip trên cây biên độ 69 pip. Ở quy mô đó màu nến là nhiễu, không phải
//   cấu trúc. Điều kiện màu vốn bê từ bot GetChart sang, ở đó nó có lý do riêng (bot đó
//   bỏ ràng buộc "râu phải chọc qua mốc"). Trong thư viện này lý do đó đã thừa: nến xu
//   hướng trơn có thân > 40% biên độ nên tự trượt ngưỡng râu mũi >= 60%.
//   Búa thân đỏ và sao băng thân xanh nay đều được nhận, đúng định nghĩa kinh điển.
//   Một cây nến vẫn KHÔNG THỂ vừa là pinbar mua vừa là pinbar bán, vì râu trên và râu
//   dưới không thể cùng chiếm >= 60% biên độ.
//
// ENGULFING (2 nến — nến 1 là cây trước, nến 2 là cây tín hiệu):
//   1. Nến 2 đóng THUẬN chiều lệnh.
//   2. Nến 2 trùm CẢ High LẪN Low của nến 1.
//   3. Nến 2 đóng cửa VƯỢT RA NGOÀI biên nến 1 (mua: đóng > High1, bán: đóng < Low1).
//   KHÔNG xét màu nến 1 — người dùng chốt: chỉ cần bao trùm, nến 1 cùng màu hay doji
//   đều được (mẫu 1 là doji giảm trước cây giảm trùm, vẫn là engulfing hợp lệ).
//+------------------------------------------------------------------+
#ifndef SIGNAL_CANDLE_MQH
#define SIGNAL_CANDLE_MQH

// ==================================================================
// HẰNG SỐ (tham số hình thức, không đưa vào Inputs)
// ==================================================================
// Với bộ ngưỡng hiện tại, điều 2 của pinbar được điều 3 + 4 kéo theo (râu mũi >= 60% nên
// thân <= 40%, và 60% = 1.5 x 40%). Vẫn giữ để luật không bị lỏng ra nếu sau này hạ 60%.
const double SC_PIN_WICK_BODY_RATIO = 1.5;    // Râu mũi / thân tối thiểu
const double SC_PIN_NOSE_MIN_RANGE  = 0.60;   // Râu mũi tối thiểu (tỷ lệ biên độ)
const double SC_PIN_OPP_MAX_RANGE   = 0.25;   // Râu đối diện tối đa (tỷ lệ biên độ)

// Dung sai so sánh số thực, để ca đúng bằng ngưỡng không bị lệch do sai số dấu phẩy động.
const double SC_EPS = 1e-9;

// ==================================================================
// DỮ LIỆU NẾN
// ==================================================================
struct SCandle { double o; double h; double l; double c; };

// Nạp nến theo shift. Trả false khi chưa có dữ liệu (lịch sử chưa tải xong).
bool SC_LoadCandle(string sym, ENUM_TIMEFRAMES tf, int shift, SCandle &k)
{
   k.o = iOpen (sym, tf, shift);
   k.h = iHigh (sym, tf, shift);
   k.l = iLow  (sym, tf, shift);
   k.c = iClose(sym, tf, shift);
   return (k.o > 0 && k.h > 0 && k.l > 0 && k.c > 0 && k.h >= k.l);
}

// ==================================================================
// PINBAR
// ==================================================================
bool SC_IsPinbar(int dir, const SCandle &k)
{
   double range = k.h - k.l;
   if(range <= 0) return false;

   // KHÔNG xét màu thân nến — xem ghi chú [v1.1] ở đầu file.
   double top  = MathMax(k.o, k.c);
   double bot  = MathMin(k.o, k.c);
   double body = top - bot;
   double nose = (dir == 1) ? (bot - k.l) : (k.h - top);   // râu phía quét
   double opp  = (dir == 1) ? (k.h - top) : (bot - k.l);   // râu phía đối diện
   if(nose <= 0) return false;

   return (nose >= body  * SC_PIN_WICK_BODY_RATIO - SC_EPS)
       && (nose >= range * SC_PIN_NOSE_MIN_RANGE  - SC_EPS)
       && (opp  <= range * SC_PIN_OPP_MAX_RANGE   + SC_EPS);
}

// ==================================================================
// ENGULFING
// ==================================================================
// prev = nến 1 (cây trước), cur = nến 2 (cây tín hiệu).
bool SC_IsEngulfing(int dir, const SCandle &prev, const SCandle &cur)
{
   bool with_trade = (dir == 1) ? (cur.c > cur.o) : (cur.c < cur.o);
   if(!with_trade) return false;

   bool covers = (cur.h >= prev.h - SC_EPS) && (cur.l <= prev.l + SC_EPS);
   bool closes_out = (dir == 1) ? (cur.c > prev.h) : (cur.c < prev.l);
   return covers && closes_out;
}

// ==================================================================
// TIỆN ÍCH ĐỌC THẲNG TỪ CHART
// ==================================================================
// shift = cây tín hiệu (mặc định 1 = cây vừa đóng). Engulfing lấy thêm cây shift + 1.
bool SC_IsPinbarAt(string sym, ENUM_TIMEFRAMES tf, int dir, int shift = 1)
{
   SCandle k;
   if(!SC_LoadCandle(sym, tf, shift, k)) return false;
   return SC_IsPinbar(dir, k);
}

bool SC_IsEngulfingAt(string sym, ENUM_TIMEFRAMES tf, int dir, int shift = 1)
{
   SCandle prev, cur;
   if(!SC_LoadCandle(sym, tf, shift + 1, prev)) return false;
   if(!SC_LoadCandle(sym, tf, shift,     cur))  return false;
   return SC_IsEngulfing(dir, prev, cur);
}

#endif // SIGNAL_CANDLE_MQH
