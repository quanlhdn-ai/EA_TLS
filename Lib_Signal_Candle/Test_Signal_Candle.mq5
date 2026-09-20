//+------------------------------------------------------------------+
//|                                           Test_Signal_Candle.mq5 |
//|         Script kiểm thử Signal_Candle.mqh — kéo thả lên chart bất kỳ |
//+------------------------------------------------------------------+
// Giá mẫu đọc từ ảnh chụp TradingView XAUUSD H1 người dùng gửi ngày 2026-09-11 (sai số
// khoảng ±0.3). Kết quả in ra tab Experts, dòng cuối là tổng PASS/FAIL.
#property script_show_inputs false

#include "Signal_Candle.mqh"

int g_pass = 0, g_fail = 0;

SCandle C(double o, double h, double l, double c)
{
   SCandle k; k.o = o; k.h = h; k.l = l; k.c = c;
   return k;
}

void Check(string name, bool got, bool want)
{
   if(got == want) g_pass++; else g_fail++;
   PrintFormat("[SC][test] %s  %-58s  kết quả=%s  mong đợi=%s",
               (got == want ? "PASS" : "FAIL"), name,
               (got ? "CÓ" : "KHÔNG"), (want ? "CÓ" : "KHÔNG"));
}

void OnStart()
{
   // ---------- ENGULFING: 4 mẫu của người dùng -> đều phải nhận ----------
   Check("Engulf mẫu 1 Sell (nến 1 doji giảm)",
         SC_IsEngulfing(-1, C(4394.6, 4396.7, 4388.2, 4393.9), C(4393.9, 4400.1, 4375.0, 4378.7)), true);
   Check("Engulf mẫu 2 Sell",
         SC_IsEngulfing(-1, C(4409.1, 4420.4, 4408.6, 4415.9), C(4415.9, 4421.4, 4401.4, 4403.0)), true);
   Check("Engulf mẫu 3 Buy",
         SC_IsEngulfing( 1, C(4354.1, 4359.7, 4349.2, 4349.9), C(4349.9, 4365.3, 4341.1, 4364.6)), true);
   Check("Engulf mẫu 4 Sell",
         SC_IsEngulfing(-1, C(4328.3, 4334.0, 4326.1, 4329.3), C(4329.3, 4335.7, 4322.6, 4324.5)), true);

   // ---------- ENGULFING: các ca phải loại ----------
   // Trùm biên độ nhưng đóng lưng chừng trong nến 1 (luật cũ của GetChart nhận ca này).
   Check("Engulf loại: trùm nhưng đóng trong biên nến 1",
         SC_IsEngulfing(-1, C(4402.0, 4410.0, 4400.0, 4408.0), C(4406.0, 4412.0, 4398.0, 4403.0)), false);
   // Đóng vượt Low nến 1 nhưng High không trùm.
   Check("Engulf loại: đóng vượt nhưng không trùm High",
         SC_IsEngulfing(-1, C(4402.0, 4410.0, 4400.0, 4408.0), C(4408.0, 4409.0, 4396.0, 4397.0)), false);
   // Hình trùm đẹp nhưng đóng NGƯỢC chiều lệnh.
   Check("Engulf loại: mẫu 3 nhưng xét chiều Sell",
         SC_IsEngulfing(-1, C(4354.1, 4359.7, 4349.2, 4349.9), C(4349.9, 4365.3, 4341.1, 4364.6)), false);

   // ---------- PINBAR ----------
   // Búa chuẩn: thân 1, râu dưới 7 (70%), râu trên 2 (20%).
   Check("Pinbar Buy chuẩn",
         SC_IsPinbar( 1, C(4400.0, 4403.0, 4393.0, 4401.0)), true);
   // Sao băng chuẩn cho Sell: thân 1, râu trên 7, râu dưới 2.
   Check("Pinbar Sell chuẩn",
         SC_IsPinbar(-1, C(4403.0, 4410.0, 4400.0, 4402.0)), true);
   // Kẽ hở 1 của luật cũ: râu đối diện dài gấp 6 lần râu mũi -> phải loại.
   Check("Pinbar loại: râu đối diện dài (luật cũ nhận)",
         SC_IsPinbar( 1, C(4400.0, 4410.0, 4398.5, 4401.0)), false);
   // Kẽ hở 2 của luật cũ: doji thân 0.2, râu dưới 0.3 = 9% biên độ -> phải loại.
   Check("Pinbar loại: doji râu mũi ngắn (luật cũ nhận)",
         SC_IsPinbar( 1, C(4400.0, 4403.0, 4399.7, 4400.2)), false);
   // [v1.1] Búa thân đỏ nay ĐƯỢC NHẬN cho lệnh Buy — màu thân không còn được xét.
   Check("Pinbar nhận: búa thân đỏ khi xét Buy",
         SC_IsPinbar( 1, C(4401.0, 4403.0, 4393.0, 4400.0)), true);
   // Ca đúng bằng ngưỡng: râu mũi đúng 60%, râu đối diện đúng 25% -> nhận.
   Check("Pinbar biên: râu mũi 60%, râu đối diện 25%",
         SC_IsPinbar( 1, C(4406.0, 4410.0, 4400.0, 4407.5)), true);

   // ---------- PINBAR: 6 cây nến THẬT, soi tay trên backtest BOT_CRT 01-11/09/2026 ----------
   // Bốn cây đầu từng bị luật v1.0 loại chỉ vì màu thân; từ v1.1 phải được nhận.
   Check("Thật 08/09 12:15 M5  BUY  · mũi 92.0% / đối diện 1.8% (thân đỏ)",
         SC_IsPinbar( 1, C(4391.885, 4392.006, 4385.152, 4391.455)), true);
   Check("Thật 08/09 04:00 M15 SELL · mũi 74.5% / đối diện 3.9% (thân xanh)",
         SC_IsPinbar(-1, C(4437.870, 4443.097, 4437.660, 4439.049)), true);
   Check("Thật 09/09 00:05 M5  BUY  · mũi 78.0% / đối diện 12.6% (thân đỏ)",
         SC_IsPinbar( 1, C(4349.814, 4350.589, 4344.445, 4349.240)), true);
   Check("Thật 09/09 11:45 M15 SELL · mũi 67.3% / đối diện 18.8% (thân xanh)",
         SC_IsPinbar(-1, C(4405.516, 4415.395, 4403.228, 4407.205)), true);
   // Hai cây "do dự hai đầu" — râu mũi chỉ gấp ~2 lần râu đối diện, phải tiếp tục bị loại.
   Check("Thật 10/09 00:00 M15 BUY  · mũi 56.9% / đối diện 27.9% -> loại",
         SC_IsPinbar( 1, C(4393.941, 4397.204, 4389.640, 4395.097)), false);
   Check("Thật 08/09 20:05 M5  BUY  · mũi 58.4% / đối diện 28.0% -> loại",
         SC_IsPinbar( 1, C(4357.602, 4358.943, 4355.717, 4358.040)), false);

   PrintFormat("[SC][test] TỔNG: %d PASS, %d FAIL", g_pass, g_fail);
}
