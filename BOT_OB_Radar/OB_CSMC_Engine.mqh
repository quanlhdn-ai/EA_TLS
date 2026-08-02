//+------------------------------------------------------------------+
//|                                                    OB_Engine.mqh |
//|                                      Focus: Ultimate OB Tracker  |
//+------------------------------------------------------------------+
#include "CSMC_Engine.mqh"

struct ActiveOB {
    string name;
    datetime time;
    double top;
    double bottom;
    bool isBull;
};

class COB_Engine
{
private:
    string   m_prefix;
    bool     m_showGraphics;
    color    c_BuyOB;
    color    c_SellOB;
    bool     m_enableOB;
    ActiveOB m_liveOBs[];
    int      m_prev_calculated;

public:
    void Init(string prefix, bool showGraphics, bool enableOB = true, color buyOB = C'255,250,205', color sellOB = C'255,250,205')
    {
        m_prefix = prefix; m_showGraphics = showGraphics; m_enableOB = enableOB; c_BuyOB = buyOB; c_SellOB = sellOB;
        m_prev_calculated = 0; ArrayResize(m_liveOBs, 0);
    }

    void ResetState() {
        if(m_showGraphics) { for(int i=0; i<ArraySize(m_liveOBs); i++) { ObjectDelete(0, m_liveOBs[i].name); ObjectDelete(0, m_liveOBs[i].name+"_LBL"); } }
        ArrayResize(m_liveOBs, 0); m_prev_calculated = 0;
    }

    int GetLiveOBCount() { return ArraySize(m_liveOBs); }
    
    // 👇 THÊM 2 HÀM NÀY VÀO 👇
    int GetBuyOBCount() {
        int count = 0;
        for(int i=0; i<ArraySize(m_liveOBs); i++) if(m_liveOBs[i].isBull) count++;
        return count;
    }
    int GetSellOBCount() {
        int count = 0;
        for(int i=0; i<ArraySize(m_liveOBs); i++) if(!m_liveOBs[i].isBull) count++;
        return count;
    }
    // 👆 ================== 👆
    
    // Hàm này mở cửa cho BOT lấy thông tin OB để vào lệnh
    bool GetLiveOBInfoEx(int index, double &top, double &bot, bool &isBull, datetime &time) {
        if(index < 0 || index >= ArraySize(m_liveOBs)) return false;
        top = m_liveOBs[index].top; bot = m_liveOBs[index].bottom; isBull = m_liveOBs[index].isBull; time = m_liveOBs[index].time; return true;
    }

    // Đôi mắt của OB_Engine: Chỉ cần truyền CSMC_Engine vào đây là nó tự hiểu mọi thứ!
    void Update(CSMC_Engine &smc, string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!m_enableOB) return;
        int current_bars = iBars(symbol, tf);
        if(current_bars < 100) return;
        int rates_total = ArraySize(smc.close);
        if(rates_total < 100) return;

        int bos_limit = 0;
        if(m_prev_calculated == 0) { bos_limit = rates_total - 10; ResetState(); } 
        else {
            int shift = current_bars - m_prev_calculated;
            bos_limit = shift + 1;
            if(bos_limit > rates_total - 10) bos_limit = rates_total - 10;
        }
        m_prev_calculated = current_bars;

        for(int i = bos_limit; i >= 0; i--) {
            // ==============================================================
            // 1. THANH TRỪNG OB CŨ (Chỉ giữ lại sóng gần nhất theo ảnh vẽ)
            // ==============================================================
            int evt = smc.MajorEvent[i];
            if(evt == 2 || evt == -2) { // Nếu có CHOCH
                datetime broken_time = smc.BrokenTime[i];
                if(broken_time > 0) PurgeOBsBeforeTime(broken_time);
            }

            // ==============================================================
            // 2. QUÉT VÀ VẼ TẤT CẢ OB LIÊN TỤC (BẤT CHẤP XU HƯỚNG)
            // ==============================================================
            int k = i + 1;
            if(k + 1 < rates_total && k - 1 > 0) { // <--- Ép k-1 phải lớn hơn 0 (tức là nến 1 đã đóng)
                CheckAndDrawSingleOB(k, true, smc, i);  
                CheckAndDrawSingleOB(k, false, smc, i); 
            }

            // ==============================================================
            // 3. XÓA OB KHI BỊ CHẠM (MITIGATION)
            // ==============================================================
            for(int obj = ArraySize(m_liveOBs) - 1; obj >= 0; obj--) {
                if(m_liveOBs[obj].isBull) {
                    if(smc.low[i] <= m_liveOBs[obj].top) { RemoveOB(obj); }
                } else {
                    if(smc.high[i] >= m_liveOBs[obj].bottom) { RemoveOB(obj); }
                }
            }
        }
    }

private:
    void PurgeOBsBeforeTime(datetime threshold_time) {
        for(int obj = ArraySize(m_liveOBs) - 1; obj >= 0; obj--) {
            if(m_liveOBs[obj].time < threshold_time) { RemoveOB(obj); }
        }
    }

    void RemoveOB(int idx) {
        if(m_showGraphics) { ObjectDelete(0, m_liveOBs[idx].name); ObjectDelete(0, m_liveOBs[idx].name+"_LBL"); }
        ArrayRemove(m_liveOBs, idx, 1);
    }

    void CheckAndDrawSingleOB(int idx, bool isBull, CSMC_Engine &smc, int current_i) {
        if (isBull) {
            if (smc.close[idx+1] < smc.open[idx+1] && smc.low[idx] < smc.low[idx+1] && smc.high[idx+1] < smc.low[idx-1]) {
                double ob_top = smc.high[idx+1]; double ob_bot = smc.low[idx];   
                string name = m_prefix + "OB_BULL_" + IntegerToString((long)smc.time[idx+1]);
                for(int k=0; k<ArraySize(m_liveOBs); k++) if(m_liveOBs[k].name == name) return; 
                bool mitigated = false; for (int m = idx - 1; m >= current_i; m--) { if (smc.low[m] <= ob_top) { mitigated = true; break; } }
                if (!mitigated) {
                    DrawOBBox(name, smc.time[idx+1], ob_top, ob_bot, true, " Buy OB", c_BuyOB);
                    int sz = ArraySize(m_liveOBs); ArrayResize(m_liveOBs, sz + 1);
                    m_liveOBs[sz].name = name; m_liveOBs[sz].time = smc.time[idx+1]; m_liveOBs[sz].top = ob_top; m_liveOBs[sz].bottom = ob_bot; m_liveOBs[sz].isBull = true;
                }
            }
        } else {
            if (smc.close[idx+1] > smc.open[idx+1] && smc.high[idx] > smc.high[idx+1] && smc.low[idx+1] > smc.high[idx-1]) {
                double ob_top = smc.high[idx]; double ob_bot = smc.low[idx+1]; 
                string name = m_prefix + "OB_BEAR_" + IntegerToString((long)smc.time[idx+1]);
                for(int k=0; k<ArraySize(m_liveOBs); k++) if(m_liveOBs[k].name == name) return;
                bool mitigated = false; for (int m = idx - 1; m >= current_i; m--) { if (smc.high[m] >= ob_bot) { mitigated = true; break; } }
                if (!mitigated) {
                    DrawOBBox(name, smc.time[idx+1], ob_top, ob_bot, false, " Sell OB", c_SellOB);
                    int sz = ArraySize(m_liveOBs); ArrayResize(m_liveOBs, sz + 1);
                    m_liveOBs[sz].name = name; m_liveOBs[sz].time = smc.time[idx+1]; m_liveOBs[sz].top = ob_top; m_liveOBs[sz].bottom = ob_bot; m_liveOBs[sz].isBull = false;
                }
            }
        }
    }

    void DrawOBBox(string name, datetime t1, double top, double bot, bool isBull, string lbl_text, color obColor) {
        if(!m_showGraphics) return;
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, TimeCurrent() + PeriodSeconds()*1000, bot);
        ObjectSetInteger(0, name, OBJPROP_COLOR, obColor); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        string lbl = name + "_LBL"; ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, isBull ? bot : top);
        ObjectSetString(0, lbl, OBJPROP_TEXT, lbl_text); ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrGray); ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isBull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    }
};
//+------------------------------------------------------------------+