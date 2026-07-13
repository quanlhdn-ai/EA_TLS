//+------------------------------------------------------------------+
//|                                             CRT_MultiTF_EA.mq5   |
//|                                                          AnhTuan |
//+------------------------------------------------------------------+
#property copyright "AnhTuan"
#property version   "1.05"

// ==============================================================================
// CRT_Project — Bot AE đa khung thời gian.
//
// BƯỚC 1 (xong): Vẽ High/Low + đường giữa 50% của HTF (mặc định H4).
//   Giá trị gọi mọi lúc: HTF_High(), HTF_Low(), HTF_Mid(), HTF_Ready()
//
// BƯỚC 2 (xong): Quét râu HTF trên khung LTF (mặc định M15) — CẢ HAI CHIỀU.
//   Lưu: CRT_SweptLow()/CRT_SweptHigh() + HasSwept...(); thông báo Journal/Dashboard/mũi tên.
//
// BƯỚC 3: Vào lệnh theo BOS/CHOCH (CSMC_Engine) trên khung Entry (mặc định M1).
//   - Sau khi quét râu M15 XÁC NHẬN -> "arm" theo hướng (dưới=BUY, trên=SELL).
//   - Nếu Entry TF có BOS/CHOCH thuận hướng -> vào lệnh market.
//   - Chưa có thì chờ; NGỪNG arming + huỷ pending khi giá chạm biên đối diện
//     (BUY: chạm H4 High; SELL: chạm H4 Low) hoặc khi H4 sang range mới.
//   - Vol theo risk %/tài khoản (SL = râu quét); chốt an toàn tài khoản -%;
//     tối đa N lệnh; TP tại Middle hoặc biên đối diện.
// ==============================================================================

#include <Trade/Trade.mqh>
#include <CSMC_Engine.mqh>   // cần có trong MQL5/Include (dùng chung với BOT_HEDGING)

input group "=== HTF (High Time Frame) ==="
input ENUM_TIMEFRAMES Inp_HTF              = PERIOD_H4;  // Khung cao làm cơ sở High/Low
input int              Inp_ExtendBars      = 20;         // Số nến (chart hiện tại) kéo dài line sang phải

input group "=== HIỂN THỊ HTF ==="
input color            Inp_ColorHigh       = clrRed;
input color            Inp_ColorLow        = clrLimeGreen;
input int              Inp_LineWidth       = 2;
input ENUM_LINE_STYLE  Inp_LineStyle       = STYLE_SOLID;
input bool             Inp_ShowLabel       = true;
input int              Inp_LabelFontSize   = 9;
input int              Inp_LabelOffsetBars = 2;          // Số nến dịch chữ label sang phải so với đầu mút line

input group "=== ĐƯỜNG GIỮA (50%) ==="
input bool              Inp_ShowMidLine    = true;
input color             Inp_ColorMid       = clrSilver;  // xám nhạt
input int               Inp_MidLineWidth   = 1;
input ENUM_LINE_STYLE   Inp_MidLineStyle   = STYLE_DOT;

input group "=== LTF (Low Time Frame) — QUÉT RÂU ==="
input ENUM_TIMEFRAMES  Inp_LTF             = PERIOD_M15; // Khung thấp dùng phát hiện quét râu
input bool             Inp_DetectLowSweep  = true;       // Bật phát hiện quét râu DƯỚI (H4 Low)
input bool             Inp_DetectHighSweep = true;       // Bật phát hiện quét râu TRÊN (H4 High)
input bool             Inp_MarkSweep       = true;       // Vẽ mũi tên đánh dấu swept low/high
input color            Inp_ColorSweepLow   = clrDodgerBlue;
input color            Inp_ColorSweepHigh  = clrOrangeRed;

input group "=== DASHBOARD ==="
input bool             Inp_ShowDashboard   = true;
input int              Inp_DashX           = 10;         // Khoảng cách mép trái (px)
input int              Inp_DashY           = 18;         // Khoảng cách mép trên (px)
input int              Inp_DashFontSize    = 9;

enum ENUM_CRT_TP { CRT_TP_MIDDLE, CRT_TP_BOUNDARY };     // TP: đường Middle | biên đối diện

input group "=== VÀO LỆNH (Entry) ==="
input bool             Inp_EnableTrading   = true;
input ENUM_TIMEFRAMES  Inp_EntryTF         = PERIOD_M1;  // Khung tìm BOS/CHOCH để vào lệnh
input long             Inp_MagicNumber     = 20260713;
input int              Inp_Slippage        = 30;
input bool             Inp_ShowStructure   = true;       // Vẽ BOS/CHOCH của engine entry lên chart
input bool             Inp_ShowZones       = false;      // Vẽ rectangle zone (foreground trên M1 sẽ đè nến)
input int              Inp_EntrySwingMajor = 5;          // PeriodsInMajorSwing cho engine entry
input int              Inp_EntrySwingMinor = 3;          // PeriodsInMinorSwing cho engine entry

input group "=== RISK / TP ==="
input double           Inp_RiskPercent      = 1.0;       // % tài khoản risk mỗi lệnh (SL = râu quét)
input double           Inp_AccountSL_Percent= 3.0;       // Đóng tất cả khi tài khoản âm quá % này
input int              Inp_MaxTrades        = 2;         // Số lệnh tối đa đồng thời
input int              Inp_SL_BufferPoints  = 20;        // Đệm SL ngoài râu quét (points)
input ENUM_CRT_TP      Inp_TP_Target        = CRT_TP_MIDDLE; // TP tại Middle hay biên đối diện

string   g_prefix     = "CRT_HTF_";
string   g_entryPrefix= "CRT_ENT_";
string   g_nameHighLine, g_nameLowLine, g_nameMidLine, g_nameHighLabel, g_nameLowLabel;
string   g_nameSweepLowArrow, g_nameSweepHighArrow;

datetime g_lastHTFBarTime = 0;  // phát hiện nến HTF mới đóng
datetime g_lastCurBarTime = 0;  // phát hiện nến mới trên chart hiện tại (điểm kết thúc line)
datetime g_lastLTFBarTime = 0;  // phát hiện nến LTF mới đóng

bool     g_hasData = false;
double   g_htfHigh = 0;
double   g_htfLow  = 0;

datetime g_highStartTime = 0;
datetime g_lowStartTime  = 0;
datetime g_midStartTime  = 0;

// --- Theo dõi quét râu DƯỚI ---
bool     g_sweepLowActive    = false;
double   g_sweepLowExtreme   = 0;      // đáy chạy của cụm nến đang quét
datetime g_sweepLowStartTime = 0;
bool     g_hasSweptLow  = false;
double   g_sweptLow     = 0;
datetime g_sweptLowTime = 0;

// --- Theo dõi quét râu TRÊN ---
bool     g_sweepHighActive    = false;
double   g_sweepHighExtreme   = 0;     // đỉnh chạy của cụm nến đang quét
datetime g_sweepHighStartTime = 0;
bool     g_hasSweptHigh  = false;
double   g_sweptHigh     = 0;
datetime g_sweptHighTime = 0;

string   g_lastEventMsg = "";

// --- Vào lệnh (BOS/CHOCH) ---
CTrade      g_trade;
CSMC_Engine g_entryEngine;
double      g_startBalance      = 0;
bool        g_halted            = false;
datetime    g_lastEntryBarTime  = 0;
datetime    g_lastActedBreakTime= 0;

bool        g_armed          = false;  // đang chờ vào lệnh sau khi quét xác nhận
int         g_armDir         = 0;      // +1 = BUY (quét dưới), -1 = SELL (quét trên)
double      g_armOppBoundary = 0;      // biên đối diện để huỷ arming

//============================ ACCESSOR (gọi mọi lúc) =================
double HTF_High()         { return g_htfHigh; }
double HTF_Low()          { return g_htfLow;  }
double HTF_Mid()          { return g_hasData ? (g_htfHigh + g_htfLow) / 2.0 : 0.0; }
bool   HTF_Ready()        { return g_hasData; }
double CRT_SweptLow()     { return g_sweptLow;  }
bool   CRT_HasSweptLow()  { return g_hasSweptLow; }
double CRT_SweptHigh()    { return g_sweptHigh; }
bool   CRT_HasSweptHigh() { return g_hasSweptHigh; }

//+------------------------------------------------------------------+
int OnInit()
{
   g_nameHighLine       = g_prefix + "HighLine";
   g_nameLowLine        = g_prefix + "LowLine";
   g_nameMidLine        = g_prefix + "MidLine";
   g_nameHighLabel      = g_prefix + "HighLabel";
   g_nameLowLabel       = g_prefix + "LowLabel";
   g_nameSweepLowArrow  = g_prefix + "SweepLowArrow";
   g_nameSweepHighArrow = g_prefix + "SweepHighArrow";

   g_lastHTFBarTime  = 0;
   g_lastCurBarTime  = 0;
   g_lastLTFBarTime  = 0;
   g_hasData         = false;
   g_sweepLowActive  = false;
   g_sweepHighActive = false;

   // --- Vào lệnh ---
   g_trade.SetExpertMagicNumber(Inp_MagicNumber);
   g_trade.SetDeviationInPoints(Inp_Slippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_startBalance      = AccountInfoDouble(ACCOUNT_BALANCE);
   g_halted            = false;
   g_lastEntryBarTime  = 0;
   g_lastActedBreakTime= 0;
   g_armed             = false;
   g_armDir            = 0;

   // showZone=Inp_ShowZones: mặc định tắt rectangle zone (isHTF=false vẽ foreground đè nến).
   // Zone vẫn được tính & lưu giá trị (current_buy/sell_zone_entry/sl) để dùng cho lọc entry.
   g_entryEngine.Init(_Symbol, Inp_EntryTF, g_entryPrefix, false, false, Inp_ShowStructure,
        clrDodgerBlue, clrOrangeRed, clrGray, clrDeepSkyBlue, clrRed, clrNONE, clrNONE,
        Inp_EntrySwingMajor, Inp_EntrySwingMinor, 5, 8, 8, Inp_ShowZones);

   RefreshAll(true);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);      // line, label, arrow, dashboard
   ObjectsDeleteAll(0, g_entryPrefix); // BOS/CHOCH của engine entry
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   RefreshAll(false);
   ProcessLTFSweep();

   if(Inp_EnableTrading)
   {
      CheckAccountStop();
      if(!g_halted)
      {
         CheckDisarmBoundary();  // theo giá, mỗi tick

         datetime eb = iTime(_Symbol, Inp_EntryTF, 0);
         if(eb != g_lastEntryBarTime)
         {
            g_lastEntryBarTime = eb;
            g_entryEngine.Update();
            ProcessEntryLogic();
         }
      }
   }

   UpdateDashboard();
}

//+------------------------------------------------------------------+
void RefreshAll(bool forceUpdate)
{
   bool priceChanged = UpdateHTFPrice(forceUpdate);
   bool timeChanged  = UpdateCurrentBarTime(forceUpdate);

   if(!g_hasData)
      return;

   if(priceChanged || timeChanged || forceUpdate)
      DrawAll();
}

//+------------------------------------------------------------------+
bool UpdateHTFPrice(bool force)
{
   datetime htfBarTime = iTime(_Symbol, Inp_HTF, 1);
   if(htfBarTime == 0)
      return false;

   if(!force && htfBarTime == g_lastHTFBarTime)
      return false;

   double htfHigh = iHigh(_Symbol, Inp_HTF, 1);
   double htfLow  = iLow(_Symbol, Inp_HTF, 1);
   if(htfHigh <= 0 || htfLow <= 0)
      return false;

   g_lastHTFBarTime = htfBarTime;
   g_htfHigh = htfHigh;
   g_htfLow  = htfLow;
   g_hasData = true;

   ComputeStartTimes(htfBarTime);

   // H4 vừa cập nhật range mới -> reset toàn bộ trạng thái quét (context cũ hết hiệu lực).
   g_sweepLowActive  = false;
   g_sweepHighActive = false;
   g_hasSweptLow     = false;
   g_hasSweptHigh    = false;
   g_lastEventMsg    = "";
   ObjectDelete(0, g_nameSweepLowArrow);
   ObjectDelete(0, g_nameSweepHighArrow);

   // Range mới -> ngừng arming cũ (không huỷ lệnh đã khớp, chỉ huỷ pending chờ).
   if(g_armed)
   {
      g_armed = false;
      CancelEAPendings();
   }

   return true;
}

//+------------------------------------------------------------------+
bool UpdateCurrentBarTime(bool force)
{
   datetime curBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBarTime == 0)
      return false;

   if(!force && curBarTime == g_lastCurBarTime)
      return false;

   g_lastCurBarTime = curBarTime;
   return true;
}

//+------------------------------------------------------------------+
void ComputeStartTimes(datetime htfOpen)
{
   datetime htfEnd = htfOpen + PeriodSeconds(Inp_HTF) - 1;

   int sOld = iBarShift(_Symbol, PERIOD_CURRENT, htfOpen, false);
   int sNew = iBarShift(_Symbol, PERIOD_CURRENT, htfEnd,  false);

   if(sOld < 0 || sNew < 0)
   {
      g_highStartTime = htfOpen;
      g_lowStartTime  = htfOpen;
      g_midStartTime  = htfOpen;
      return;
   }

   int loShift = MathMin(sNew, sOld);
   int hiShift = MathMax(sNew, sOld);

   double maxH = -DBL_MAX;
   double minL =  DBL_MAX;
   int    hiIdx = hiShift;
   int    loIdx = hiShift;

   for(int s = loShift; s <= hiShift; s++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, s);
      double l = iLow(_Symbol,  PERIOD_CURRENT, s);
      if(h > maxH) { maxH = h; hiIdx = s; }
      if(l < minL) { minL = l; loIdx = s; }
   }

   g_highStartTime = iTime(_Symbol, PERIOD_CURRENT, hiIdx);
   g_lowStartTime  = iTime(_Symbol, PERIOD_CURRENT, loIdx);
   g_midStartTime  = iTime(_Symbol, PERIOD_CURRENT, hiShift);
}

//+------------------------------------------------------------------+
void DrawAll()
{
   datetime endTime   = g_lastCurBarTime + Inp_ExtendBars * PeriodSeconds(PERIOD_CURRENT);
   datetime labelTime = endTime + Inp_LabelOffsetBars * PeriodSeconds(PERIOD_CURRENT);

   DrawLevelLine(g_nameHighLine, g_highStartTime, endTime, g_htfHigh, Inp_ColorHigh, Inp_LineWidth, Inp_LineStyle);
   DrawLevelLine(g_nameLowLine,  g_lowStartTime,  endTime, g_htfLow,  Inp_ColorLow,  Inp_LineWidth, Inp_LineStyle);

   if(Inp_ShowMidLine)
      DrawLevelLine(g_nameMidLine, g_midStartTime, endTime, HTF_Mid(), Inp_ColorMid, Inp_MidLineWidth, Inp_MidLineStyle);

   if(Inp_ShowLabel)
   {
      string tfName = TFToString(Inp_HTF);
      DrawLevelLabel(g_nameHighLabel, labelTime, g_htfHigh,
                      StringFormat("%s High: %s", tfName, DoubleToString(g_htfHigh, _Digits)), Inp_ColorHigh);
      DrawLevelLabel(g_nameLowLabel, labelTime, g_htfLow,
                      StringFormat("%s Low: %s", tfName, DoubleToString(g_htfLow, _Digits)), Inp_ColorLow);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Xử lý quét râu trên khung LTF — chạy trên nến LTF ĐÃ ĐÓNG (không repaint).
//+------------------------------------------------------------------+
void ProcessLTFSweep()
{
   if(!g_hasData)
      return;

   datetime ltfBar0 = iTime(_Symbol, Inp_LTF, 0);
   if(ltfBar0 == 0)
      return;
   if(ltfBar0 == g_lastLTFBarTime)
      return; // chưa có nến LTF mới đóng

   bool firstInit = (g_lastLTFBarTime == 0);
   g_lastLTFBarTime = ltfBar0;
   if(firstInit)
      return; // lần đầu chỉ lấy mốc

   // Nến LTF vừa đóng = shift 1
   double highC  = iHigh(_Symbol,  Inp_LTF, 1);
   double lowC   = iLow(_Symbol,   Inp_LTF, 1);
   double closeC = iClose(_Symbol, Inp_LTF, 1);
   datetime tC   = iTime(_Symbol,  Inp_LTF, 1);

   double h4Low  = g_htfLow;
   double h4High = g_htfHigh;

   //================= QUÉT RÂU DƯỚI (H4 Low) =================
   if(Inp_DetectLowSweep)
   {
      if(!g_sweepLowActive)
      {
         if(lowC < h4Low)
         {
            g_sweepLowActive    = true;
            g_sweepLowExtreme   = lowC;
            g_sweepLowStartTime = tC;
            if(closeC > h4Low)
               ConfirmLowSweep(tC);
         }
      }
      else
      {
         if(lowC < g_sweepLowExtreme)
            g_sweepLowExtreme = lowC;
         if(closeC > h4Low)
            ConfirmLowSweep(tC);
      }
   }

   //================= QUÉT RÂU TRÊN (H4 High) =================
   if(Inp_DetectHighSweep)
   {
      if(!g_sweepHighActive)
      {
         if(highC > h4High)
         {
            g_sweepHighActive    = true;
            g_sweepHighExtreme   = highC;
            g_sweepHighStartTime = tC;
            if(closeC < h4High)
               ConfirmHighSweep(tC);
         }
      }
      else
      {
         if(highC > g_sweepHighExtreme)
            g_sweepHighExtreme = highC;
         if(closeC < h4High)
            ConfirmHighSweep(tC);
      }
   }
}

//+------------------------------------------------------------------+
void ConfirmLowSweep(datetime tConfirm)
{
   g_sweptLow     = g_sweepLowExtreme;
   g_sweptLowTime = tConfirm;
   g_hasSweptLow  = true;
   g_sweepLowActive = false;

   g_lastEventMsg = StringFormat("QUÉT RÂU DƯỚI ✔  H4 Low=%s | Swept Low=%s | @%s",
                       DoubleToString(g_htfLow, _Digits),
                       DoubleToString(g_sweptLow, _Digits),
                       TimeToString(tConfirm, TIME_DATE|TIME_MINUTES));

   PrintFormat("[CRT][%s][LTF %s] %s (cụm quét từ %s)",
               _Symbol, TFToString(Inp_LTF), g_lastEventMsg,
               TimeToString(g_sweepLowStartTime, TIME_DATE|TIME_MINUTES));

   if(Inp_MarkSweep)
      MarkConfirmCandle(g_nameSweepLowArrow, OBJ_ARROW_UP, tConfirm, false, Inp_ColorSweepLow);

   ArmSetup(+1); // quét dưới -> chờ BUY
}

//+------------------------------------------------------------------+
void ConfirmHighSweep(datetime tConfirm)
{
   g_sweptHigh     = g_sweepHighExtreme;
   g_sweptHighTime = tConfirm;
   g_hasSweptHigh  = true;
   g_sweepHighActive = false;

   g_lastEventMsg = StringFormat("QUÉT RÂU TRÊN ✔  H4 High=%s | Swept High=%s | @%s",
                       DoubleToString(g_htfHigh, _Digits),
                       DoubleToString(g_sweptHigh, _Digits),
                       TimeToString(tConfirm, TIME_DATE|TIME_MINUTES));

   PrintFormat("[CRT][%s][LTF %s] %s (cụm quét từ %s)",
               _Symbol, TFToString(Inp_LTF), g_lastEventMsg,
               TimeToString(g_sweepHighStartTime, TIME_DATE|TIME_MINUTES));

   if(Inp_MarkSweep)
      MarkConfirmCandle(g_nameSweepHighArrow, OBJ_ARROW_DOWN, tConfirm, true, Inp_ColorSweepHigh);

   ArmSetup(-1); // quét trên -> chờ SELL
}

//+------------------------------------------------------------------+
// Trỏ mũi tên vào ĐÚNG cây nến xác nhận trên TF ĐANG CHẠY:
//   - Tìm cây nến (TF hiện tại) CUỐI CÙNG nằm trong cây LTF xác nhận
//     (vd chạy M1, LTF M15 -> cây M1 đóng cửa của cây M15 xác nhận).
//   - Đặt tại đỉnh (quét trên) / đáy (quét dưới) của chính cây nến đó.
//+------------------------------------------------------------------+
void MarkConfirmCandle(string name, ENUM_OBJECT type, datetime ltfBarOpen, bool isHigh, color clr)
{
   datetime ltfClose = ltfBarOpen + PeriodSeconds(Inp_LTF);

   int shift = iBarShift(_Symbol, PERIOD_CURRENT, ltfClose - 1, false);
   if(shift < 0)
      shift = iBarShift(_Symbol, PERIOD_CURRENT, ltfBarOpen, false);
   if(shift < 0)
      return;

   datetime t     = iTime(_Symbol, PERIOD_CURRENT, shift);
   double   price = isHigh ? iHigh(_Symbol, PERIOD_CURRENT, shift)
                           : iLow(_Symbol,  PERIOD_CURRENT, shift);
   ENUM_ARROW_ANCHOR anchor = isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP;

   DrawSweepArrow(name, type, t, price, clr, anchor);
}

//+------------------------------------------------------------------+
void DrawSweepArrow(string name, ENUM_OBJECT type, datetime t, double price, color clr, ENUM_ARROW_ANCHOR anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, type, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ChartRedraw(0);
}

//============================ VÀO LỆNH (BOS/CHOCH) ==================
// Bật arming sau khi quét râu xác nhận. dir: +1 BUY (quét dưới), -1 SELL (quét trên).
//+------------------------------------------------------------------+
void ArmSetup(int dir)
{
   g_armed  = true;
   g_armDir = dir;
   g_armOppBoundary = (dir > 0) ? g_htfHigh : g_htfLow; // biên đối diện
   g_lastActedBreakTime = 0; // cho phép nhận break mới cho setup này
   PrintFormat("[CRT] ARM %s · chờ BOS/CHOCH %s trên %s (biên đối diện %s)",
               dir > 0 ? "BUY" : "SELL",
               dir > 0 ? "LÊN" : "XUỐNG",
               TFToString(Inp_EntryTF),
               DoubleToString(g_armOppBoundary, _Digits));
}

//+------------------------------------------------------------------+
// Ngừng arming + huỷ pending khi giá chạm biên đối diện (theo giá, mỗi tick).
//+------------------------------------------------------------------+
void CheckDisarmBoundary()
{
   if(!g_armed)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool hit = (g_armDir > 0 && ask >= g_armOppBoundary)   // BUY: chạm H4 High
           || (g_armDir < 0 && bid <= g_armOppBoundary);  // SELL: chạm H4 Low
   if(hit)
   {
      PrintFormat("[CRT] Giá chạm biên đối diện %s -> ngừng arming, huỷ pending.",
                  DoubleToString(g_armOppBoundary, _Digits));
      g_armed = false;
      CancelEAPendings();
   }
}

//+------------------------------------------------------------------+
// Chạy mỗi nến Entry TF mới (sau engine.Update): nếu đang arm & có BOS/CHOCH
// thuận hướng (mới, trong range H4 hiện tại) -> vào lệnh.
//+------------------------------------------------------------------+
void ProcessEntryLogic()
{
   if(!g_hasData || !g_armed)
      return;
   if(CountEAPositions() >= Inp_MaxTrades)
      return;

   int      brkDir  = 0;
   datetime brkTime = 0;
   if(!GetLatestBreak(brkDir, brkTime))
      return;

   datetime rangeStart = iTime(_Symbol, Inp_HTF, 0); // mở cửa cây H4 đang hình thành
   if(brkDir == g_armDir && brkTime != g_lastActedBreakTime && brkTime >= rangeStart)
   {
      g_lastActedBreakTime = brkTime;
      ExecuteEntry(g_armDir);
   }
}

//+------------------------------------------------------------------+
// Lấy sự kiện BOS/CHOCH gần nhất trên nến ĐÃ ĐÓNG của engine entry.
// dir: +1 (lên) / -1 (xuống); trả false nếu không có.
//+------------------------------------------------------------------+
bool GetLatestBreak(int &dir, datetime &t)
{
   int n = ArraySize(g_entryEngine.MajorEvent);
   if(n < 3)
      return false;

   int limit = MathMin(n - 1, 600);
   for(int i = 1; i <= limit; i++)
   {
      int ev = g_entryEngine.MajorEvent[i];
      if(ev != 0)
      {
         dir = (ev > 0) ? 1 : -1; // ±1 BOS, ±2 CHOCH đều tính là break
         t   = g_entryEngine.time[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void ExecuteEntry(int dir)
{
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf   = Inp_SL_BufferPoints * _Point;

   if(dir > 0)
   {
      double entry = ask;
      double sl    = g_sweptLow - buf;
      double tp    = (Inp_TP_Target == CRT_TP_MIDDLE) ? HTF_Mid() : g_htfHigh;
      if(tp <= entry) tp = g_htfHigh;               // đảm bảo TP trên entry
      if(tp <= entry) { Print("[CRT] Bỏ qua BUY: TP không hợp lệ (giá đã vượt biên trên)."); return; }
      double lots  = CalcLots(entry - sl);
      if(lots <= 0) { Print("[CRT] Bỏ qua BUY: lots=0."); return; }
      if(g_trade.Buy(lots, _Symbol, entry, sl, tp, "CRT buy"))
         PrintFormat("[CRT] ✅ BUY %.2f lot @%s SL %s TP %s",
                     lots, DoubleToString(entry,_Digits), DoubleToString(sl,_Digits), DoubleToString(tp,_Digits));
      else
         PrintFormat("[CRT] ❌ BUY lỗi: %d %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
   else
   {
      double entry = bid;
      double sl    = g_sweptHigh + buf;
      double tp    = (Inp_TP_Target == CRT_TP_MIDDLE) ? HTF_Mid() : g_htfLow;
      if(tp >= entry) tp = g_htfLow;
      if(tp >= entry) { Print("[CRT] Bỏ qua SELL: TP không hợp lệ (giá đã vượt biên dưới)."); return; }
      double lots  = CalcLots(sl - entry);
      if(lots <= 0) { Print("[CRT] Bỏ qua SELL: lots=0."); return; }
      if(g_trade.Sell(lots, _Symbol, entry, sl, tp, "CRT sell"))
         PrintFormat("[CRT] ✅ SELL %.2f lot @%s SL %s TP %s",
                     lots, DoubleToString(entry,_Digits), DoubleToString(sl,_Digits), DoubleToString(tp,_Digits));
      else
         PrintFormat("[CRT] ❌ SELL lỗi: %d %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
// Lot theo risk %/tài khoản với khoảng SL cho trước (giá).
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   if(slDistancePrice <= 0)
      return 0;

   double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney= bal * Inp_RiskPercent / 100.0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0)
      return 0;

   double lossPerLot = slDistancePrice / tickSize * tickVal;
   if(lossPerLot <= 0)
      return 0;

   double lots = riskMoney / lossPerLot;

   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepL > 0) lots = MathFloor(lots / stepL) * stepL;
   lots = MathMax(minL, MathMin(maxL, lots));
   return lots;
}

//+------------------------------------------------------------------+
int CountEAPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber)
         cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
void CancelEAPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == Inp_MagicNumber)
         g_trade.OrderDelete(tk);
   }
}

//+------------------------------------------------------------------+
void CloseAllEAPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber)
         g_trade.PositionClose(tk);
   }
}

//+------------------------------------------------------------------+
// Chốt an toàn cấp tài khoản: equity <= balance_khởi_tạo * (1 - %).
//+------------------------------------------------------------------+
void CheckAccountStop()
{
   if(g_halted)
      return;

   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double limit = g_startBalance * (1.0 - Inp_AccountSL_Percent / 100.0);
   if(eq <= limit)
   {
      CloseAllEAPositions();
      CancelEAPendings();
      g_halted = true;
      g_armed  = false;
      PrintFormat("[CRT] 🛑 ACCOUNT SL: equity %.2f <= %.2f (-%.1f%%). Đóng tất cả & dừng vào lệnh.",
                  eq, limit, Inp_AccountSL_Percent);
   }
}

// Dashboard bằng OBJ_LABEL (mỗi dòng 1 màu). Đỏ = quét TRÊN, Xanh = quét DƯỚI.
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!Inp_ShowDashboard)
      return;

   color cNeutral = NeutralTextColor();

   if(!g_hasData)
   {
      SetDashLabel(0, "CRT · chờ dữ liệu HTF...", cNeutral);
      SetDashLabel(1, "", cNeutral);
      SetDashLabel(2, "", cNeutral);
      SetDashLabel(3, "", cNeutral);
      SetDashLabel(4, "", cNeutral);
      return;
   }

   // Dòng 0: tiêu đề
   SetDashLabel(0, StringFormat("CRT · HTF %s · LTF %s", TFToString(Inp_HTF), TFToString(Inp_LTF)), cNeutral);

   // Dòng 1: giá H4
   SetDashLabel(1, StringFormat("H4 High: %s   ·   H4 Middle: %s   ·   H4 Low: %s",
                     DoubleToString(g_htfHigh, _Digits),
                     DoubleToString(HTF_Mid(), _Digits),
                     DoubleToString(g_htfLow,  _Digits)), cNeutral);

   // Dòng 2: quét TRÊN (đỏ)
   SetDashLabel(2, "▲ Quét trên: " + SweepStatusText(true),  Inp_ColorSweepHigh);

   // Dòng 3: quét DƯỚI (xanh)
   SetDashLabel(3, "▼ Quét dưới: " + SweepStatusText(false), Inp_ColorSweepLow);

   // Dòng 4: trạng thái vào lệnh
   string entryTxt;
   color  entryClr = cNeutral;
   if(!Inp_EnableTrading)
      entryTxt = "Vào lệnh: TẮT";
   else if(g_halted)
   { entryTxt = "Vào lệnh: 🛑 HALT (account SL)"; entryClr = Inp_ColorSweepHigh; }
   else
   {
      string armTxt = "—";
      if(g_armed)
      {
         armTxt   = (g_armDir > 0) ? "chờ BUY" : "chờ SELL";
         entryClr = (g_armDir > 0) ? Inp_ColorSweepLow : Inp_ColorSweepHigh;
      }
      entryTxt = StringFormat("Vào lệnh: %s · Lệnh %d/%d · %s",
                     armTxt, CountEAPositions(), Inp_MaxTrades, TFToString(Inp_EntryTF));
   }
   SetDashLabel(4, entryTxt, entryClr);
}

//+------------------------------------------------------------------+
string SweepStatusText(bool isHigh)
{
   if(isHigh)
   {
      if(g_sweepHighActive)
         return StringFormat("theo dõi · Cao nhất %s", DoubleToString(g_sweepHighExtreme, _Digits));
      if(g_hasSweptHigh)
         return StringFormat("✔ Cao nhất %s @%s",
                             DoubleToString(g_sweptHigh, _Digits),
                             TimeToString(g_sweptHighTime, TIME_MINUTES));
      return "—";
   }
   else
   {
      if(g_sweepLowActive)
         return StringFormat("theo dõi · Thấp nhất %s", DoubleToString(g_sweepLowExtreme, _Digits));
      if(g_hasSweptLow)
         return StringFormat("✔ Thấp nhất %s @%s",
                             DoubleToString(g_sweptLow, _Digits),
                             TimeToString(g_sweptLowTime, TIME_MINUTES));
      return "—";
   }
}

//+------------------------------------------------------------------+
void SetDashLabel(int idx, string text, color clr)
{
   string name = g_prefix + "Dash" + (string)idx;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Inp_DashX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Inp_DashY + idx * (Inp_DashFontSize + 8));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Inp_DashFontSize);
   ObjectSetString(0,  name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
// Chọn màu chữ trung tính tương phản với nền chart (đen trên nền sáng, trắng trên nền tối).
//+------------------------------------------------------------------+
color NeutralTextColor()
{
   long bg = ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int r = (int)(bg & 0xFF);
   int g = (int)((bg >> 8) & 0xFF);
   int b = (int)((bg >> 16) & 0xFF);
   double lum = 0.299 * r + 0.587 * g + 0.114 * b;
   return lum > 128 ? clrBlack : clrWhite;
}

//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime t1, datetime t2, double price, color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void DrawLevelLabel(string name, datetime t, double price, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Inp_LabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
}
//+------------------------------------------------------------------+
