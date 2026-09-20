//+------------------------------------------------------------------+
//|                                          Signal_Candle_Stats.mq5 |
//|      Đo sức mạnh THẬT của từng mẫu nến trên chính dữ liệu của ta |
//|                                   Topic_Signal_Candle — v1.0     |
//+------------------------------------------------------------------+
// Quét toàn bộ lịch sử, mỗi lần một mẫu nến xuất hiện thì mô phỏng một lệnh giả định và
// ghi lại kết quả. In bảng tổng kết ra tab Experts + ghi CSV từng lần khớp vào MQL5/Files.
//
// MỤC ĐÍCH: chọn mẫu nến bằng SỐ LIỆU của chính cặp và khung mình giao dịch, thay vì tin
// tỷ lệ in trong sách (đo trên cổ phiếu, khung ngày, thời kỳ khác).
//
// ====================== CÁCH MÔ PHỎNG (đọc kỹ trước khi tin số) ======================
// · Vào lệnh: giá ĐÓNG của cây nến cuối cùng trong mẫu. Không trượt giá, không spread,
//   không hoa hồng — đây là phép đo sức mạnh của MẪU, không phải backtest chiến lược.
// · SL: mút râu ngược hướng của CẢ cụm nến (mua = đáy thấp nhất, bán = đỉnh cao nhất).
//   R = khoảng cách từ giá vào tới SL. Mọi kết quả quy ra bội số R nên so sánh được
//   giữa các mẫu có kích thước nến khác nhau.
// · Duyệt từng cây kế tiếp, tối đa Inp_ForwardBars cây:
//     - chạm SL trước  -> thua (-1R)
//     - chạm mục tiêu  -> thắng (+1R hoặc +2R)
//   Trong CÙNG một cây mà giá chạm cả hai thì tính THUA. Dữ liệu nến không cho biết cái
//   nào đến trước, nên chọn giả định bi quan — số liệu ra sẽ hơi xấu hơn thực tế, thà vậy
//   còn hơn tô hồng.
// · Chưa ngã ngũ trong Inp_ForwardBars cây thì tính theo giá đóng cây cuối (netR).
// · Các mẫu ĐƯỢC ĐO ĐỘC LẬP và có thể chồng nhau: một cây vừa là marubozu vừa là nến 3
//   của engulfing thì được đếm ở cả hai dòng. Đừng cộng các dòng lại với nhau.
//
// ====================== ĐỊNH NGHĨA CÁC MẪU ĐANG ĐO ======================
// Ký hiệu: body = |C-O| · range = H-L · trên = H-max(O,C) · dưới = min(O,C)-L
//
// 1. PINBAR    (1 nến) — lấy thẳng từ thư viện Signal_Candle.mqh v1.1
// 2. ENGULFING (2 nến) — lấy thẳng từ thư viện
// 3. STAR      (3 nến, sao mai / sao hôm) — mua:
//      nến 1 giảm, body1 >= 50% range1 · body2 <= 35% body1 · thân nến 2 nằm tại hoặc
//      dưới giá đóng nến 1 · nến 3 tăng và đóng vượt quá 50% thân nến 1
// 4. CPR       (2 nến, quét-và-đóng-lại) — mua:
//      Low2 < Low1 · Close2 > Close1 · Close2 nằm ở 1/3 TRÊN biên độ nến 2
// 5. MARU      (1 nến, động lượng) — hướng = hướng thân:
//      body >= 70% range · râu ngược hướng <= 10% range
// 6. IBBRK     (3 nến, mẹ bồng con rồi phá vỡ) — mua:
//      nến 2 nằm trọn trong nến 1 (H2<=H1, L2>=L1) · nến 3 đóng vượt hẳn H1
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.00"
#property script_show_inputs

#include <Signal_Candle.mqh>

input ENUM_TIMEFRAMES Inp_TF            = PERIOD_CURRENT; // Khung đo (PERIOD_CURRENT = khung chart)
input int    Inp_Bars                   = 100000;   // Số nến lịch sử quét
input int    Inp_ForwardBars            = 20;       // Số nến theo dõi sau tín hiệu
input double Inp_MinRisk_Pips           = 3.0;      // Bỏ qua mẫu có R nhỏ hơn (pip) — tránh nến tí hon
input bool   Inp_GhiCSV                 = true;     // Ghi file CSV từng lần khớp vào MQL5/Files

#define SC_PAT_COUNT 6

string  g_ten[SC_PAT_COUNT]  = {"PINBAR", "ENGULFING", "STAR", "CPR", "MARU", "IBBRK"};
int     g_n[SC_PAT_COUNT], g_nBuy[SC_PAT_COUNT];
// Hai mức chốt được phân giải ĐỘC LẬP với nhau: lệnh chốt ở 1R đã đóng xong từ lâu thì
// việc giá sau đó quay về chạm SL không còn liên quan. Gộp chung một biến là sai.
int     g_w1[SC_PAT_COUNT], g_l1[SC_PAT_COUNT], g_o1[SC_PAT_COUNT];   // chốt tại 1R
int     g_w2[SC_PAT_COUNT], g_l2[SC_PAT_COUNT], g_o2[SC_PAT_COUNT];   // chốt tại 2R
double  g_mfe[SC_PAT_COUNT], g_mae[SC_PAT_COUNT];

// Kích thước 1 pip — sao y GetPipSize() của BOT_CRT/BOT_TLS để số liệu cùng đơn vị.
double PipSize(string sym)
{
   string s = sym; StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
   if(StringFind(s, "JPY") >= 0) return 0.01;
   long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits == 5 || digits == 4) return 0.0001;
   if(digits == 3 || digits == 2) return 0.01;
   return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0;
}

double Body (const MqlRates &k) { return MathAbs(k.close - k.open); }
double Rng  (const MqlRates &k) { return k.high - k.low; }
double BodyT(const MqlRates &k) { return MathMax(k.open, k.close); }
double BodyB(const MqlRates &k) { return MathMin(k.open, k.close); }

SCandle ToSC(const MqlRates &k)
{
   SCandle c; c.o = k.open; c.h = k.high; c.l = k.low; c.c = k.close;
   return c;
}

// --- 3. STAR: sao mai (dir=1) / sao hôm (dir=-1) ---
bool IsStar(int dir, const MqlRates &k1, const MqlRates &k2, const MqlRates &k3)
{
   double r1 = Rng(k1), b1 = Body(k1);
   if(r1 <= 0 || b1 < 0.50 * r1) return false;
   if(Body(k2) > 0.35 * b1) return false;

   double mid1 = (k1.open + k1.close) / 2.0;
   if(dir == 1)
   {
      if(k1.close >= k1.open) return false;          // nến 1 phải giảm
      if(BodyB(k2) > k1.close) return false;         // thân nến 2 nằm tại/dưới đáy thân nến 1
      return (k3.close > k3.open && k3.close > mid1);
   }
   if(k1.close <= k1.open) return false;             // nến 1 phải tăng
   if(BodyT(k2) < k1.close) return false;
   return (k3.close < k3.open && k3.close < mid1);
}

// --- 4. CPR: quét đáy/đỉnh nến trước rồi đóng lại ngược phía ---
bool IsCPR(int dir, const MqlRates &k1, const MqlRates &k2)
{
   double r2 = Rng(k2);
   if(r2 <= 0) return false;
   if(dir == 1)
      return (k2.low < k1.low) && (k2.close > k1.close)
          && (k2.close >= k2.low + 2.0 / 3.0 * r2);
   return (k2.high > k1.high) && (k2.close < k1.close)
       && (k2.close <= k2.high - 2.0 / 3.0 * r2);
}

// --- 5. MARU: nến động lượng, thân chiếm gần hết biên độ ---
bool IsMaru(int dir, const MqlRates &k)
{
   double r = Rng(k);
   if(r <= 0 || Body(k) < 0.70 * r) return false;
   if(dir == 1)  return (k.close > k.open) && ((k.high - BodyT(k)) <= 0.10 * r);
   return (k.close < k.open) && ((BodyB(k) - k.low) <= 0.10 * r);
}

// --- 6. IBBRK: nến con nằm trong nến mẹ, cây thứ 3 đóng vượt biên nến mẹ ---
bool IsInsideBreak(int dir, const MqlRates &k1, const MqlRates &k2, const MqlRates &k3)
{
   if(!(k2.high <= k1.high && k2.low >= k1.low)) return false;
   if(dir == 1) return (k3.close > k1.high);
   return (k3.close < k1.low);
}

// Mô phỏng 1 lệnh giả định và cộng vào thống kê của mẫu idx.
void DoKetQua(int idx, int dir, const MqlRates &rates[], int i, int nBars,
              double entry, double sl, double pip, int fh)
{
   double risk = MathAbs(entry - sl);
   if(risk < Inp_MinRisk_Pips * pip) return;

   double tp1 = (dir == 1) ? entry + risk       : entry - risk;
   double tp2 = (dir == 1) ? entry + 2.0 * risk : entry - 2.0 * risk;

   int    res1 = 0, res2 = 0;  // 0 = chưa ngã ngũ · +1 = chạm mục tiêu trước · -1 = chạm SL trước
   double mfe = 0, mae = 0;
   int    last = MathMin(i + Inp_ForwardBars, nBars - 1);

   for(int j = i + 1; j <= last; j++)
   {
      double fav = (dir == 1) ? (rates[j].high - entry) : (entry - rates[j].low);
      double adv = (dir == 1) ? (entry - rates[j].low)  : (rates[j].high - entry);
      if(fav > mfe) mfe = fav;
      if(adv > mae) mae = adv;

      // SL xét TRƯỚC trong cùng một cây — giả định bi quan, xem ghi chú đầu file.
      bool chamSL = (dir == 1) ? (rates[j].low  <= sl)  : (rates[j].high >= sl);
      bool chamT1 = (dir == 1) ? (rates[j].high >= tp1) : (rates[j].low  <= tp1);
      bool chamT2 = (dir == 1) ? (rates[j].high >= tp2) : (rates[j].low  <= tp2);

      if(res1 == 0) { if(chamSL) res1 = -1; else if(chamT1) res1 = 1; }
      if(res2 == 0) { if(chamSL) res2 = -1; else if(chamT2) res2 = 1; }
      if(res1 != 0 && res2 != 0) break;
   }

   double netR = ((dir == 1) ? (rates[last].close - entry) : (entry - rates[last].close)) / risk;

   g_n[idx]++;
   g_mfe[idx] += mfe / risk;
   g_mae[idx] += mae / risk;
   if(dir == 1) g_nBuy[idx]++;

   if(res1 ==  1) g_w1[idx]++; else if(res1 == -1) g_l1[idx]++; else g_o1[idx]++;
   if(res2 ==  1) g_w2[idx]++; else if(res2 == -1) g_l2[idx]++; else g_o2[idx]++;

   if(fh != INVALID_HANDLE)
      FileWrite(fh, TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES), g_ten[idx],
                (dir == 1 ? "BUY" : "SELL"),
                DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                DoubleToString(risk / pip, 1), DoubleToString(mfe / risk, 2),
                DoubleToString(mae / risk, 2), DoubleToString(netR, 2),
                IntegerToString(res1), IntegerToString(res2));
}

void OnStart()
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = (Inp_TF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : Inp_TF;
   double pip = PipSize(sym);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int n = CopyRates(sym, tf, 0, Inp_Bars, rates);
   if(n < 100)
   {
      PrintFormat("[SC][stats] Không đủ dữ liệu (%d nến). Mở chart khung đó và kéo lùi cho nạp lịch sử rồi chạy lại.", n);
      return;
   }

   int fh = INVALID_HANDLE;
   string tenFile = StringFormat("SC_Stats_%s_%s.csv", sym, EnumToString(tf));
   if(Inp_GhiCSV)
   {
      fh = FileOpen(tenFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh != INVALID_HANDLE)
         FileWrite(fh, "time", "pattern", "dir", "entry", "sl", "riskPips",
                   "mfeR", "maeR", "netR", "res1R", "res2R");
   }

   ArrayInitialize(g_n,  0); ArrayInitialize(g_nBuy, 0);
   ArrayInitialize(g_w1, 0); ArrayInitialize(g_l1, 0); ArrayInitialize(g_o1, 0);
   ArrayInitialize(g_w2, 0); ArrayInitialize(g_l2, 0); ArrayInitialize(g_o2, 0);
   ArrayInitialize(g_mfe, 0); ArrayInitialize(g_mae, 0);

   // i = cây tín hiệu (cây cuối của mẫu). Cần i-2 cho mẫu 3 nến, và chừa đủ cây phía sau.
   int cuoi = n - 2 - Inp_ForwardBars;     // n-1 là cây đang chạy, không xét
   for(int i = 2; i <= cuoi; i++)
   {
      for(int d = 0; d < 2; d++)
      {
         int dir = (d == 0) ? 1 : -1;
         double lowPat, highPat, entry, sl;

         // --- 1 nến: PINBAR, MARU ---
         entry = rates[i].close;
         sl    = (dir == 1) ? rates[i].low : rates[i].high;
         if(SC_IsPinbar(dir, ToSC(rates[i])))
            DoKetQua(0, dir, rates, i, n, entry, sl, pip, fh);
         if(IsMaru(dir, rates[i]))
            DoKetQua(4, dir, rates, i, n, entry, sl, pip, fh);

         // --- 2 nến: ENGULFING, CPR ---
         lowPat  = MathMin(rates[i].low,  rates[i - 1].low);
         highPat = MathMax(rates[i].high, rates[i - 1].high);
         sl      = (dir == 1) ? lowPat : highPat;
         if(SC_IsEngulfing(dir, ToSC(rates[i - 1]), ToSC(rates[i])))
            DoKetQua(1, dir, rates, i, n, entry, sl, pip, fh);
         if(IsCPR(dir, rates[i - 1], rates[i]))
            DoKetQua(3, dir, rates, i, n, entry, sl, pip, fh);

         // --- 3 nến: STAR, IBBRK ---
         lowPat  = MathMin(lowPat,  rates[i - 2].low);
         highPat = MathMax(highPat, rates[i - 2].high);
         sl      = (dir == 1) ? lowPat : highPat;
         if(IsStar(dir, rates[i - 2], rates[i - 1], rates[i]))
            DoKetQua(2, dir, rates, i, n, entry, sl, pip, fh);
         if(IsInsideBreak(dir, rates[i - 2], rates[i - 1], rates[i]))
            DoKetQua(5, dir, rates, i, n, entry, sl, pip, fh);
      }
   }

   if(fh != INVALID_HANDLE) FileClose(fh);

   PrintFormat("[SC][stats] ===== %s %s · %d nến (%s -> %s) · theo dõi %d cây · SL = mút râu cụm nến =====",
               sym, EnumToString(tf), cuoi - 1,
               TimeToString(rates[2].time, TIME_DATE),
               TimeToString(rates[cuoi].time, TIME_DATE), Inp_ForwardBars);
   Print("[SC][stats] Mau        | so lan || chot 1R: thang% thua% chuaro%   KV || chot 2R: thang% thua% chuaro%   KV || avgMFE avgMAE | %BUY");
   for(int p = 0; p < SC_PAT_COUNT; p++)
   {
      if(g_n[p] == 0) { PrintFormat("[SC][stats] %-10s | 0 lần — không xuất hiện", g_ten[p]); continue; }
      double N = (double)g_n[p];
      // Kỳ vọng tính trên TOÀN BỘ số lần khớp: lần chưa ngã ngũ tính 0R (hoà) cho gọn,
      // muốn xét kỹ hơn thì đọc cột netR trong CSV.
      double kv1 = (g_w1[p] * 1.0 - g_l1[p] * 1.0) / N;
      double kv2 = (g_w2[p] * 2.0 - g_l2[p] * 1.0) / N;
      PrintFormat("[SC][stats] %-10s | %6d ||          %6.1f %5.1f %7.1f %+5.2fR ||          %6.1f %5.1f %7.1f %+5.2fR || %6.2f %6.2f | %4.0f",
                  g_ten[p], g_n[p],
                  g_w1[p] * 100.0 / N, g_l1[p] * 100.0 / N, g_o1[p] * 100.0 / N, kv1,
                  g_w2[p] * 100.0 / N, g_l2[p] * 100.0 / N, g_o2[p] * 100.0 / N, kv2,
                  g_mfe[p] / N, g_mae[p] / N, g_nBuy[p] * 100.0 / N);
   }
   if(Inp_GhiCSV)
      PrintFormat("[SC][stats] Đã ghi CSV: MQL5/Files/%s", tenFile);
}
