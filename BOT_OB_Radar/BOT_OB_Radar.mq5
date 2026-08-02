//+------------------------------------------------------------------+
//|                                            BOT_OB_Radar.mq5      |
//|                      (đổi tên từ Test_OB_Bot_V2.mq5, 08/2026)     |
//|                                Focus: Modular MTF SMC + OB Radar |
//|                    Chỉ phát hiện Order Block + báo Telegram —    |
//|                              KHÔNG đặt lệnh (không có logic trade)|
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "2.10"
#property strict

#include <CSMC_Engine.mqh>
#include <OB_CSMC_Engine.mqh>
#include <Telegram_Radar.mqh> 

// ==============================================================================
// CẤU HÌNH INPUTS
// ==============================================================================
input group "--- Telegram Notifications ---"
input string   InpTelegramToken  = "8365052004:AAEEqNwnzI_OIpjlzrXS_PjriACSdTZbnQs"; 
input string   InpTelegramChatID = "-5161191555";   
input bool     InpSendPhoto      = true;                  

input group "--- Display Toggles (Hiển thị) ---"
input bool     InpEnableOB       = true;  // Bật/Tắt quét & vẽ Order Block
input bool     InpShowZone       = true;  // Bật/Tắt vẽ hộp ZONE (Supply/Demand)
input bool     InpShowMinor      = true;  // Bật/Tắt vẽ Sóng Phụ (mBOS, mCHOCH, Swing)

// Khai báo các thực thể cho 5 khung thời gian
CSMC_Engine SMC_M1,  SMC_M5,  SMC_M15,  SMC_H1,  SMC_H4;
COB_Engine  OB_M1,   OB_M5,   OB_M15,   OB_H1,   OB_H4;

CTelegramRadar Telegram;

// Biến quản lý trạng thái chống Spam
datetime last_ob_time_m1  = 0;
datetime last_ob_time_m5  = 0;
datetime last_ob_time_m15 = 0;
datetime last_ob_time_h1  = 0;
datetime last_ob_time_h4  = 0;
bool     is_initialized   = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Telegram.Init(InpTelegramToken, InpTelegramChatID, InpSendPhoto);

    // Truyền công tắc InpShowMinor và InpShowZone vào 5 bộ não
    SMC_M1.Init(_Symbol,  PERIOD_M1,  "M1_",  false, InpShowMinor, (_Period == PERIOD_M1),  C'190,235,210', C'255,200,200', clrOrange, clrDodgerBlue, clrRed, C'120,220,220', C'255,180,180', 9, 5, 1, 5, 3, InpShowZone);
    SMC_M5.Init(_Symbol,  PERIOD_M5,  "M5_",  false, InpShowMinor, (_Period == PERIOD_M5),  C'190,235,210', C'255,200,200', clrOrange, clrDodgerBlue, clrRed, C'120,220,220', C'255,180,180', 9, 5, 1, 5, 3, InpShowZone);
    SMC_M15.Init(_Symbol, PERIOD_M15, "M15_", false, InpShowMinor, (_Period == PERIOD_M15), C'190,235,210', C'255,200,200', clrOrange, clrDodgerBlue, clrRed, C'120,220,220', C'255,180,180', 9, 5, 1, 5, 3, InpShowZone);
    SMC_H1.Init(_Symbol,  PERIOD_H1,  "H1_",  true,  InpShowMinor, (_Period == PERIOD_H1),  C'190,235,210', C'255,200,200', clrOrange, clrDodgerBlue, clrRed, C'120,220,220', C'255,180,180', 9, 5, 1, 5, 3, InpShowZone);
    SMC_H4.Init(_Symbol,  PERIOD_H4,  "H4_",  true,  InpShowMinor, (_Period == PERIOD_H4),  C'190,235,210', C'255,200,200', clrOrange, clrDodgerBlue, clrRed, C'120,220,220', C'255,180,180', 9, 5, 1, 5, 3, InpShowZone);

    // Khởi tạo OB_Engine
    OB_M1.Init("M1_",  (_Period == PERIOD_M1),  InpEnableOB);
    OB_M5.Init("M5_",  (_Period == PERIOD_M5),  InpEnableOB);
    OB_M15.Init("M15_", (_Period == PERIOD_M15), InpEnableOB);
    OB_H1.Init("H1_",  (_Period == PERIOD_H1),  InpEnableOB);
    OB_H4.Init("H4_",  (_Period == PERIOD_H4),  InpEnableOB);

    is_initialized = false;
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "M1_"); ObjectsDeleteAll(0, "M5_");
    ObjectsDeleteAll(0, "M15_"); ObjectsDeleteAll(0, "H1_"); ObjectsDeleteAll(0, "H4_");
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    SMC_M1.Update();  OB_M1.Update(SMC_M1, _Symbol, PERIOD_M1);
    SMC_M5.Update();  OB_M5.Update(SMC_M5, _Symbol, PERIOD_M5);
    SMC_M15.Update(); OB_M15.Update(SMC_M15, _Symbol, PERIOD_M15);
    SMC_H1.Update();  OB_H1.Update(SMC_H1, _Symbol, PERIOD_H1);
    SMC_H4.Update();  OB_H4.Update(SMC_H4, _Symbol, PERIOD_H4);

    if (!is_initialized) {
        if (SMC_H4.current_major_trend != 0) { 
            SyncHistoryTimes();
            is_initialized = true;
            Telegram.SendMessage("✅ <b>RADAR SMC MODULAR V2 ĐÃ SẴN SÀNG!</b>\nDữ liệu đa khung đã đồng bộ. Đang trực chiến...");
        }
        return;
    }

    CheckAndNotifyOB("M1",  SMC_M1, OB_M1,  last_ob_time_m1);
    CheckAndNotifyOB("M5",  SMC_M5, OB_M5,  last_ob_time_m5);
    CheckAndNotifyOB("M15", SMC_M15, OB_M15, last_ob_time_m15);
    CheckAndNotifyOB("H1",  SMC_H1, OB_H1,  last_ob_time_h1);
    CheckAndNotifyOB("H4",  SMC_H4, OB_H4,  last_ob_time_h4);

    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Các hàm hỗ trợ                                                   |
//+------------------------------------------------------------------+
void CheckAndNotifyOB(string tf_name, CSMC_Engine &smc, COB_Engine &ob, datetime &last_time)
{
    int count = ob.GetLiveOBCount();
    if (count <= 0) return;

    double top, bot; bool isBull; datetime time;
    if (ob.GetLiveOBInfoEx(count - 1, top, bot, isBull, time)) {
        if (time > last_time) {
            string msg = "🚨 <b>PHÁT HIỆN ORDER BLOCK MỚI!</b>\n\n";
            msg += "🪙 <b>Cặp:</b> " + _Symbol + " | ⏱ <b>TF:</b> " + tf_name + "\n";
            string trend_str = (smc.current_major_trend == 1) ? "TĂNG 🟢" : (smc.current_major_trend == -1 ? "GIẢM 🔴" : "SIDEWAY ⚪️");
            msg += "📊 <b>Xu hướng chính:</b> " + trend_str + "\n";
            msg += "🎯 <b>Loại:</b> " + (isBull ? "BUY OB 🟢" : "SELL OB 🔴") + "\n";
            msg += "🏷 <b>Vùng:</b> " + DoubleToString(bot, _Digits) + " - " + DoubleToString(top, _Digits) + "\n";
            
            Telegram.SendMessageWithPhoto(msg);
            last_time = time; 
        }
    }
}

void SyncHistoryTimes() {
    double t, b; bool bul; int c;
    c = OB_M1.GetLiveOBCount();  if(c>0) OB_M1.GetLiveOBInfoEx(c-1, t, b, bul, last_ob_time_m1);
    c = OB_M5.GetLiveOBCount();  if(c>0) OB_M5.GetLiveOBInfoEx(c-1, t, b, bul, last_ob_time_m5);
    c = OB_M15.GetLiveOBCount(); if(c>0) OB_M15.GetLiveOBInfoEx(c-1, t, b, bul, last_ob_time_m15);
    c = OB_H1.GetLiveOBCount();  if(c>0) OB_H1.GetLiveOBInfoEx(c-1, t, b, bul, last_ob_time_h1);
    c = OB_H4.GetLiveOBCount();  if(c>0) OB_H4.GetLiveOBInfoEx(c-1, t, b, bul, last_ob_time_h4);
}

// ==============================================================================
// CẬP NHẬT DASHBOARD (BẢN TỐI GIẢN & CHỐNG LỖI FONT)
// ==============================================================================
void UpdateDashboard() {
    string d = "===========================\n";
    d += "    RADAR ORDER BLOCK V2.0\n";
    d += "===========================\n\n";
    
    d += FormatTFLine("M1",  SMC_M1,  OB_M1);
    d += FormatTFLine("M5",  SMC_M5,  OB_M5);
    d += FormatTFLine("M15", SMC_M15, OB_M15);
    d += FormatTFLine("H1",  SMC_H1,  OB_H1);
    d += FormatTFLine("H4",  SMC_H4,  OB_H4);
    
    Comment(d);
}

string FormatTFLine(string name, CSMC_Engine &smc, COB_Engine &ob) {
    // 1. Lọc hành động phá vỡ (Phase)
    string phase = smc.current_market_phase;
    string action = "Wait...";
    if(StringFind(phase, "BoS Up") >= 0)         action = "BoS Up";
    else if(StringFind(phase, "BoS Down") >= 0)  action = "BoS Dn";
    else if(StringFind(phase, "ChoCh Up") >= 0)  action = "ChoCh Up";
    else if(StringFind(phase, "ChoCh Down") >= 0)action = "ChoCh Dn";

    // 2. Lấy xu hướng Sóng Chính (Major)
    string maj = (smc.current_major_trend == 1) ? "Up" : (smc.current_major_trend == -1 ? "Dn" : "--");

    // 3. Ghép chuỗi trung tâm: "Up-BoS Up"
    string short_phase = maj + "-" + action;
    
    // Tự động chèn dấu cách để căn lề cột giữa cho thẳng tắp
    while(StringLen(short_phase) < 12) short_phase += " ";

    // 4. Lọc Order Block
    int b_ob = ob.GetBuyOBCount();
    int s_ob = ob.GetSellOBCount();
    string ob_status = "";
    
    if (b_ob == 0 && s_ob == 0) {
        ob_status = "---";
    } else {
        if (b_ob > 0) ob_status += IntegerToString(b_ob) + " Buy   ";
        if (s_ob > 0) ob_status += IntegerToString(s_ob) + " Sell";
    }

// 5. CĂN LỀ HOÀN HẢO BẰNG CÁCH ĐỆM SỐ 0 (Trị dứt điểm lỗi lệch pixel của MT5)
    string tf_name = name;
    if (name == "M1")      tf_name = "M1  ";
    else if (name == "M5") tf_name = "M5  ";
    else if (name == "H1") tf_name = "H1  ";
    else if (name == "H4") tf_name = "H4  ";
    else if (name == "M15") tf_name = "M15";
    // M15 tự động giữ nguyên vì đã có sẵn 3 ký tự (M-1-5)

    // Trả về dòng hoàn chỉnh
    return tf_name + " | " + short_phase + " | " + ob_status + "\n";
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if (id == CHARTEVENT_CHART_CHANGE) {
        if(_Period == PERIOD_M1) SMC_M1.HandleChartEvent();
        if(_Period == PERIOD_M5) SMC_M5.HandleChartEvent();
        if(_Period == PERIOD_M15) SMC_M15.HandleChartEvent();
        if(_Period == PERIOD_H1) SMC_H1.HandleChartEvent();
        if(_Period == PERIOD_H4) SMC_H4.HandleChartEvent();
    }
}
//+------------------------------------------------------------------+