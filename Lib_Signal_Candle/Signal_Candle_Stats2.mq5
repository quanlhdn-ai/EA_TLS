//+------------------------------------------------------------------+
//|                                         Signal_Candle_Stats2.mq5 |
//|   Đo mẫu nến CÓ BỐI CẢNH — kèm nhóm đối chứng, phân giải bằng M1 |
//|                                   Topic_Signal_Candle — v2.0     |
//+------------------------------------------------------------------+
// Bản v1 (Signal_Candle_Stats.mq5) đo mẫu nến TRẦN, không bối cảnh, và kết luận: sáu mẫu
// đều có kỳ vọng bằng không. Bản v2 trả lời câu hỏi thật sự đáng giá:
//
//     TRONG BỐI CẢNH MÀ BOT THỰC SỰ VÀO LỆNH, thêm điều kiện nến có tốt lên không?
//
// ====================== CỔNG BỐI CẢNH (sao theo BOT_CRT) ======================
// Với mỗi cây nến khung tín hiệu, biên lấy từ nến H4 LIỀN KỀ ĐÃ ĐÓNG (giống nguồn
// ADJACENT của BOT_CRT). Cổng mở khi đủ cả ba:
//   1. Nến liền TRƯỚC đóng cửa BÊN TRONG biên  — "đi từ trong ra", không phải đang ở ngoài sẵn
//   2. Râu nến hiện tại VƯỢT QUA biên           — cú quét thanh khoản
//   3. Nến hiện tại ĐÓNG LẠI BÊN TRONG biên     — bị từ chối
// Mỗi giá trị biên chỉ dùng ĐÚNG MỘT LẦN cho mỗi phía (sao cờ lineUsed của BOT_CRT).
//
// ====================== NHÓM ĐỐI CHỨNG — điểm cốt lõi ======================
// MỌI lần cổng mở đều được ghi lại, kèm cờ đánh dấu lúc đó có mẫu nến nào. Nhờ vậy tính
// được HIỆU SỐ: nhóm CÓ mẫu so với nhóm KHÔNG có mẫu, trong cùng một bối cảnh.
// Nếu hiệu số bằng không thì mẫu nến chỉ là trang trí — chính bối cảnh mới tạo ra kết quả.
//
// ====================== MÔ PHỎNG ======================
// Vào tại giá đóng nến tín hiệu · SL tại mút râu quét · R = |vào - SL| · mục tiêu 1R và 2R.
// Phân giải bằng nến M1 (chính xác hơn nhiều so với v1). Đoạn lịch sử không có M1 thì lùi
// về phân giải bằng nến khung tín hiệu, và cột res_src ghi rõ dùng cách nào.
// Vẫn KHÔNG tính spread/hoa hồng: đây là phép đo phần TĂNG THÊM của mẫu nến, hai nhóm
// chịu chung một khoản phí nên hiệu số không đổi.
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "2.00"
#property script_show_inputs

#include <Signal_Candle.mqh>

input ENUM_TIMEFRAMES Inp_TF        = PERIOD_CURRENT;  // Khung tín hiệu (PERIOD_CURRENT = khung chart)
input ENUM_TIMEFRAMES Inp_TF_Bien   = PERIOD_H4;       // Khung lấy biên
input int    Inp_Bars               = 200000;   // Số nến khung tín hiệu quét
input int    Inp_M1_Bars            = 600000;   // Số nến M1 nạp để phân giải TP/SL
input int    Inp_ForwardBars        = 20;       // Theo dõi tối đa (số nến khung tín hiệu)
input double Inp_MinRisk_Pips       = 3.0;      // Bỏ qua tín hiệu có R nhỏ hơn (pip)
input bool   Inp_GhiCSV             = true;     // Ghi CSV từng lần cổng mở

#define PAT_N 6
string g_ten[PAT_N] = {"PINBAR", "ENGULFING", "CPR", "STAR", "MARU", "IBBRK"};

// Thống kê: [mẫu][0 = KHÔNG có mẫu · 1 = CÓ mẫu]
int    s_n[PAT_N][2];
double s_sum1[PAT_N][2], s_sq1[PAT_N][2];   // kết quả khi chốt 1R (+1 / -1 / 0)
double s_sum2[PAT_N][2], s_sq2[PAT_N][2];   // kết quả khi chốt 2R (+2 / -1 / 0)
int    g_tongCong = 0, g_boQua = 0, g_dungM1 = 0;
double g_a1 = 0, g_a2 = 0;                  // tổng kết quả của TOÀN BỘ nhóm đối chứng

MqlRates g_ltf[], g_bien[], g_m1[];

double PipSize(string sym)
{
   string s = sym; StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
   if(StringFind(s, "JPY") >= 0) return 0.01;
   long d = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(d == 5 || d == 4) return 0.0001;
   if(d == 3 || d == 2) return 0.01;
   return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0;
}

SCandle ToSC(const MqlRates &k) { SCandle c; c.o = k.open; c.h = k.high; c.l = k.low; c.c = k.close; return c; }
double  Body(const MqlRates &k) { return MathAbs(k.close - k.open); }
double  Rng (const MqlRates &k) { return k.high - k.low; }
double  BodT(const MqlRates &k) { return MathMax(k.open, k.close); }
double  BodB(const MqlRates &k) { return MathMin(k.open, k.close); }

// --- Bốn mẫu ứng viên, định nghĩa y hệt bản v1 để hai lượt đo so sánh được ---
bool IsStar(int dir, const MqlRates &k1, const MqlRates &k2, const MqlRates &k3)
{
   double r1 = Rng(k1), b1 = Body(k1);
   if(r1 <= 0 || b1 < 0.50 * r1 || Body(k2) > 0.35 * b1) return false;
   double mid1 = (k1.open + k1.close) / 2.0;
   if(dir == 1)
      return (k1.close < k1.open) && (BodB(k2) <= k1.close) && (k3.close > k3.open) && (k3.close > mid1);
   return (k1.close > k1.open) && (BodT(k2) >= k1.close) && (k3.close < k3.open) && (k3.close < mid1);
}

bool IsCPR(int dir, const MqlRates &k1, const MqlRates &k2)
{
   double r2 = Rng(k2);
   if(r2 <= 0) return false;
   if(dir == 1) return (k2.low  < k1.low)  && (k2.close > k1.close) && (k2.close >= k2.low  + 2.0 / 3.0 * r2);
   return             (k2.high > k1.high) && (k2.close < k1.close) && (k2.close <= k2.high - 2.0 / 3.0 * r2);
}

bool IsMaru(int dir, const MqlRates &k)
{
   double r = Rng(k);
   if(r <= 0 || Body(k) < 0.70 * r) return false;
   if(dir == 1) return (k.close > k.open) && ((k.high - BodT(k)) <= 0.10 * r);
   return              (k.close < k.open) && ((BodB(k) - k.low)  <= 0.10 * r);
}

bool IsInsideBreak(int dir, const MqlRates &k1, const MqlRates &k2, const MqlRates &k3)
{
   if(!(k2.high <= k1.high && k2.low >= k1.low)) return false;
   if(dir == 1) return (k3.close > k1.high);
   return              (k3.close < k1.low);
}

// Tìm cây cuối cùng có time <= t (nhị phân). Trả -1 nếu không có.
int TimIndex(const MqlRates &arr[], datetime t)
{
   int lo = 0, hi = ArraySize(arr) - 1, res = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(arr[mid].time <= t) { res = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return res;
}

// Phân giải TP/SL trên một mảng nến bất kỳ, bắt đầu từ index start tới hết cửa sổ.
// Trả res1/res2 (+1 chạm mục tiêu trước · -1 chạm SL trước · 0 chưa ngã ngũ).
void PhanGiai(const MqlRates &arr[], int start, int stop, int dir,
              double entry, double sl, double tp1, double tp2,
              int &res1, int &res2, double &mfe, double &mae)
{
   res1 = 0; res2 = 0; mfe = 0; mae = 0;
   for(int j = start; j <= stop; j++)
   {
      double fav = (dir == 1) ? (arr[j].high - entry) : (entry - arr[j].low);
      double adv = (dir == 1) ? (entry - arr[j].low)  : (arr[j].high - entry);
      if(fav > mfe) mfe = fav;
      if(adv > mae) mae = adv;

      bool chamSL = (dir == 1) ? (arr[j].low  <= sl)  : (arr[j].high >= sl);
      bool chamT1 = (dir == 1) ? (arr[j].high >= tp1) : (arr[j].low  <= tp1);
      bool chamT2 = (dir == 1) ? (arr[j].high >= tp2) : (arr[j].low  <= tp2);

      if(res1 == 0) { if(chamSL) res1 = -1; else if(chamT1) res1 = 1; }
      if(res2 == 0) { if(chamSL) res2 = -1; else if(chamT2) res2 = 1; }
      if(res1 != 0 && res2 != 0) return;
   }
}

void CongVao(int idx, int coMau, double kq1, double kq2)
{
   s_n[idx][coMau]++;
   s_sum1[idx][coMau] += kq1; s_sq1[idx][coMau] += kq1 * kq1;
   s_sum2[idx][coMau] += kq2; s_sq2[idx][coMau] += kq2 * kq2;
}

void InBang(string tieuDe, bool mucTieu2R)
{
   Print("[SC][v2] " + tieuDe);
   Print("[SC][v2] Mau       |   CO mau: n     KV |  KHONG co: n     KV |  chenh lech    se      t");
   for(int p = 0; p < PAT_N; p++)
   {
      int n1 = s_n[p][1], n0 = s_n[p][0];
      if(n1 < 5 || n0 < 5) { PrintFormat("[SC][v2] %-9s | quá ít mẫu (có %d / không %d)", g_ten[p], n1, n0); continue; }
      double sum1 = mucTieu2R ? s_sum2[p][1] : s_sum1[p][1];
      double sq1  = mucTieu2R ? s_sq2 [p][1] : s_sq1 [p][1];
      double sum0 = mucTieu2R ? s_sum2[p][0] : s_sum1[p][0];
      double sq0  = mucTieu2R ? s_sq2 [p][0] : s_sq1 [p][0];

      double m1 = sum1 / n1, m0 = sum0 / n0;
      double v1 = MathMax(sq1 / n1 - m1 * m1, 0.0);
      double v0 = MathMax(sq0 / n0 - m0 * m0, 0.0);
      double se = MathSqrt(v1 / n1 + v0 / n0);
      double t  = (se > 0) ? (m1 - m0) / se : 0;
      PrintFormat("[SC][v2] %-9s | %10d %+6.3fR | %10d %+6.3fR | %+9.3fR %6.3f %+6.2f",
                  g_ten[p], n1, m1, n0, m0, m1 - m0, se, t);
   }
}

void OnStart()
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = (Inp_TF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : Inp_TF;
   double pip = PipSize(sym);

   ArraySetAsSeries(g_ltf, false); ArraySetAsSeries(g_bien, false); ArraySetAsSeries(g_m1, false);
   int n    = CopyRates(sym, tf,            0, Inp_Bars,    g_ltf);
   int nb   = CopyRates(sym, Inp_TF_Bien,   0, Inp_Bars,    g_bien);
   int nm1  = CopyRates(sym, PERIOD_M1,     0, Inp_M1_Bars, g_m1);
   if(n < 100 || nb < 10)
   {
      PrintFormat("[SC][v2] Không đủ dữ liệu: khung tín hiệu %d nến, khung biên %d nến.", n, nb);
      return;
   }
   PrintFormat("[SC][v2] Nạp: %d nến %s · %d nến biên %s · %d nến M1%s",
               n, EnumToString(tf), nb, EnumToString(Inp_TF_Bien), nm1,
               nm1 > 0 ? StringFormat(" (từ %s)", TimeToString(g_m1[0].time, TIME_DATE)) : " — sẽ phân giải bằng khung tín hiệu");

   int fh = INVALID_HANDLE;
   string tenFile = StringFormat("SC_Stats2_%s_%s.csv", sym, EnumToString(tf));
   if(Inp_GhiCSV)
   {
      fh = FileOpen(tenFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh != INVALID_HANDLE)
         FileWrite(fh, "time", "dir", "entry", "sl", "riskPips", "res1R", "res2R", "mfeR", "maeR",
                   "res_src", "res1_ltf", "res1_m1", "res2_ltf", "res2_m1",
                   "PINBAR", "ENGULFING", "CPR", "STAR", "MARU", "IBBRK");
   }

   ArrayInitialize(s_n, 0);
   ArrayInitialize(s_sum1, 0); ArrayInitialize(s_sq1, 0);
   ArrayInitialize(s_sum2, 0); ArrayInitialize(s_sq2, 0);

   double daDungTren = 0, daDungDuoi = 0;   // giá trị biên đã dùng cho mỗi phía
   int    soM1 = MathMax(1, (int)(Inp_ForwardBars * PeriodSeconds(tf) / 60));
   int    cuoi = n - 2 - Inp_ForwardBars;

   for(int i = 2; i <= cuoi; i++)
   {
      int kb = TimIndex(g_bien, g_ltf[i].time);
      if(kb < 1) continue;
      double hi = g_bien[kb - 1].high;     // biên nến H4 LIỀN KỀ đã đóng
      double lo = g_bien[kb - 1].low;

      for(int d = 0; d < 2; d++)
      {
         int dir = (d == 0) ? 1 : -1;

         // --- Cổng bối cảnh ---
         bool mo;
         if(dir == -1)
            mo = (g_ltf[i - 1].close < hi) && (g_ltf[i].high > hi) && (g_ltf[i].close < hi)
              && (hi != daDungTren);
         else
            mo = (g_ltf[i - 1].close > lo) && (g_ltf[i].low  < lo) && (g_ltf[i].close > lo)
              && (lo != daDungDuoi);
         if(!mo) continue;

         double entry = g_ltf[i].close;
         double sl    = (dir == 1) ? g_ltf[i].low : g_ltf[i].high;   // mút râu quét
         double risk  = MathAbs(entry - sl);
         if(risk < Inp_MinRisk_Pips * pip) { g_boQua++; continue; }

         // Đốt biên: mỗi giá trị biên chỉ xét đúng một lần cho mỗi phía.
         if(dir == -1) daDungTren = hi; else daDungDuoi = lo;

         double tp1 = (dir == 1) ? entry + risk       : entry - risk;
         double tp2 = (dir == 1) ? entry + 2.0 * risk : entry - 2.0 * risk;

         // --- Phân giải HAI CÁCH trên cùng một tín hiệu ---
         // Phải đo cả hai thì mới tách được: chênh lệch giữa các mẫu nến là THẬT, hay chỉ
         // là sản phẩm của quy ước "chạm cả hai trong một cây thì tính thua" ở khung lớn.
         // So sánh chỉ có nghĩa trên đúng những tín hiệu được phân giải bằng cả hai cách.
         int    r1L, r2L, r1M = 0, r2M = 0; double mfeL, maeL, mfeM = 0, maeM = 0;
         bool   coM1 = false;

         PhanGiai(g_ltf, i + 1, MathMin(i + Inp_ForwardBars, n - 2), dir, entry, sl, tp1, tp2,
                  r1L, r2L, mfeL, maeL);

         datetime tVao = g_ltf[i].time + PeriodSeconds(tf);   // thời điểm nến tín hiệu đóng
         int im1 = (nm1 > 0) ? TimIndex(g_m1, tVao) : -1;
         // TimIndex trả cây CUỐI CÙNG có time <= tVao. Nếu cây đó mở đúng tại tVao thì nó
         // CHÍNH LÀ phút đầu tiên sau khi vào lệnh, phải tính; nếu không thì lấy cây kế.
         int start = -1;
         if(im1 >= 0) start = (g_m1[im1].time == tVao) ? im1 : im1 + 1;
         if(start >= 0 && start + soM1 - 1 <= nm1 - 1)
         {
            PhanGiai(g_m1, start, start + soM1 - 1, dir, entry, sl, tp1, tp2, r1M, r2M, mfeM, maeM);
            coM1 = true; g_dungM1++;
         }

         // Số liệu chính lấy theo M1 khi có — đó là cách đo chính xác hơn.
         int    res1 = coM1 ? r1M : r1L,  res2 = coM1 ? r2M : r2L;
         double mfe  = coM1 ? mfeM : mfeL, mae = coM1 ? maeM : maeL;
         string src  = coM1 ? "M1" : EnumToString(tf);

         double kq1 = (res1 == 1) ? 1.0 : ((res1 == -1) ? -1.0 : 0.0);
         double kq2 = (res2 == 1) ? 2.0 : ((res2 == -1) ? -1.0 : 0.0);
         g_tongCong++; g_a1 += kq1; g_a2 += kq2;

         SCandle c0 = ToSC(g_ltf[i]), c1 = ToSC(g_ltf[i - 1]);
         bool co[PAT_N];
         co[0] = SC_IsPinbar(dir, c0);
         co[1] = SC_IsEngulfing(dir, c1, c0);
         co[2] = IsCPR(dir, g_ltf[i - 1], g_ltf[i]);
         co[3] = IsStar(dir, g_ltf[i - 2], g_ltf[i - 1], g_ltf[i]);
         co[4] = IsMaru(dir, g_ltf[i]);
         co[5] = IsInsideBreak(dir, g_ltf[i - 2], g_ltf[i - 1], g_ltf[i]);
         for(int p = 0; p < PAT_N; p++) CongVao(p, co[p] ? 1 : 0, kq1, kq2);

         if(fh != INVALID_HANDLE)
            FileWrite(fh, TimeToString(g_ltf[i].time, TIME_DATE | TIME_MINUTES),
                      (dir == 1 ? "BUY" : "SELL"),
                      DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                      DoubleToString(risk / pip, 1), IntegerToString(res1), IntegerToString(res2),
                      DoubleToString(mfe / risk, 2), DoubleToString(mae / risk, 2), src,
                      IntegerToString(r1L), (coM1 ? IntegerToString(r1M) : "NA"),
                      IntegerToString(r2L), (coM1 ? IntegerToString(r2M) : "NA"),
                      (co[0] ? "1" : "0"), (co[1] ? "1" : "0"), (co[2] ? "1" : "0"),
                      (co[3] ? "1" : "0"), (co[4] ? "1" : "0"), (co[5] ? "1" : "0"));
      }
   }
   if(fh != INVALID_HANDLE) FileClose(fh);

   PrintFormat("[SC][v2] ===== %s %s · biên %s · theo dõi %d nến · %s -> %s =====",
               sym, EnumToString(tf), EnumToString(Inp_TF_Bien), Inp_ForwardBars,
               TimeToString(g_ltf[2].time, TIME_DATE), TimeToString(g_ltf[cuoi].time, TIME_DATE));
   if(g_tongCong == 0) { Print("[SC][v2] Cổng không mở lần nào — kiểm lại khung biên."); return; }

   PrintFormat("[SC][v2] NHÓM ĐỐI CHỨNG (mọi lần cổng mở, KHÔNG lọc nến): %d lệnh · KV 1R = %+.3fR · KV 2R = %+.3fR",
               g_tongCong, g_a1 / g_tongCong, g_a2 / g_tongCong);
   PrintFormat("[SC][v2] Phân giải bằng M1: %d / %d lần (%.0f%%) · bỏ qua vì R quá nhỏ: %d",
               g_dungM1, g_tongCong, g_dungM1 * 100.0 / g_tongCong, g_boQua);
   InBang("--- CHỐT TẠI 1R ---", false);
   InBang("--- CHỐT TẠI 2R ---", true);
   Print("[SC][v2] Cột 't' là hiệu số chia cho sai số. |t| < 2 nghĩa là KHÔNG phân biệt được với nhiễu.");
   if(Inp_GhiCSV) PrintFormat("[SC][v2] Đã ghi CSV: MQL5/Files/%s", tenFile);
}
