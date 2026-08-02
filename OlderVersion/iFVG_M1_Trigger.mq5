//+------------------------------------------------------------------+
//|                                              iFVG_M1_Trigger.mq5 |
//|                     Focus: MTF Zone + Exact Historical Inversion |
//|                                                    Version: 4.00 |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "4.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input group "--- HTF Settings ---"
input ENUM_TIMEFRAMES HTF_Period = PERIOD_M15; 

input group "--- FVG/iFVG Settings ---"
input color FVG_Color_Pending = C'220,220,220'; 
input color iFVG_Buy_Color    = clrAqua;        
input color iFVG_Sell_Color   = clrMagenta;     

int htf_handle;

struct TActiveZone {
    bool     isActive;
    int      type;          
    double   entry;
    double   sl;
    datetime createTime;    
    bool     isTouched;
    datetime touchTime;     
    datetime extremeTime;   
    double   extremePrice;  
};
TActiveZone currentZone;

struct T_iFVG {
    string   name;
    double   gapHigh;
    double   gapLow;
    datetime startTime;
    bool     isInsideZone;
    bool     isInverted;       
    double   distanceToZone;
};
T_iFVG activeFVGs[];
int outside_iFVG_Count = 0;

int OnInit() {
    htf_handle = iCustom(_Symbol, HTF_Period, "Combo_MajorSwing_HA_BOS_Zone_V80");
    if(htf_handle == INVALID_HANDLE) return(INIT_FAILED);
    currentZone.isActive = false;
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "IND_M1_FVG_");
    ObjectsDeleteAll(0, "EXTREME_MARKER");
    IndicatorRelease(htf_handle);
}

void ResetFVGData() {
    ArrayResize(activeFVGs, 0);
    outside_iFVG_Count = 0;
    ObjectsDeleteAll(0, "IND_M1_FVG_");
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
    if(rates_total < 100) return(0);

    ArraySetAsSeries(time, true); ArraySetAsSeries(high, true); 
    ArraySetAsSeries(low, true); ArraySetAsSeries(close, true);

    double buyEntry[1], buySL[1], sellSL[1], sellEntry[1];
    
    if(CopyBuffer(htf_handle, 18, 0, 1, buyEntry) > 0 && CopyBuffer(htf_handle, 19, 0, 1, buySL) > 0 &&
       CopyBuffer(htf_handle, 20, 0, 1, sellSL) > 0 && CopyBuffer(htf_handle, 21, 0, 1, sellEntry) > 0) 
    {
        bool hasBuyZone = (buyEntry[0] != EMPTY_VALUE && buyEntry[0] > 0);
        bool hasSellZone = (sellEntry[0] != EMPTY_VALUE && sellEntry[0] > 0);

        if(!hasBuyZone && !hasSellZone) {
            if(currentZone.isActive) {
                currentZone.isActive = false;
                ObjectDelete(0, "EXTREME_MARKER");
                ResetFVGData(); 
            }
        } 
        else {
            int newType = hasBuyZone ? 1 : -1;
            double newEntry = hasBuyZone ? buyEntry[0] : sellEntry[0];
            double newSL = hasBuyZone ? buySL[0] : sellSL[0];

            if(!currentZone.isActive || currentZone.type != newType || MathAbs(currentZone.entry - newEntry) > _Point) {
                currentZone.isActive = true; 
                currentZone.type = newType;
                currentZone.entry = newEntry; 
                currentZone.sl = newSL;
                currentZone.createTime = time[0]; 
                currentZone.isTouched = false;
                ObjectDelete(0, "EXTREME_MARKER");
                ResetFVGData();
            }
        }
    }

    if(currentZone.isActive && !currentZone.isTouched) {
        if((currentZone.type == 1 && low[0] <= currentZone.entry) || (currentZone.type == -1 && high[0] >= currentZone.entry)) {
            currentZone.isTouched = true;
            currentZone.touchTime = time[0];
            
            int barsToSearch = iBarShift(_Symbol, _Period, currentZone.createTime) + 1;
            if(barsToSearch < 10) barsToSearch = 100; 
            
            int extremeIdx = (currentZone.type == 1) ? ArrayMaximum(high, 0, barsToSearch) : ArrayMinimum(low, 0, barsToSearch);
            if(extremeIdx != -1) {
                currentZone.extremeTime = time[extremeIdx];
                currentZone.extremePrice = (currentZone.type == 1) ? high[extremeIdx] : low[extremeIdx];
                
                ObjectCreate(0, "EXTREME_MARKER", OBJ_ARROW, 0, currentZone.extremeTime, currentZone.extremePrice);
                ObjectSetInteger(0, "EXTREME_MARKER", OBJPROP_ARROWCODE, (currentZone.type == 1) ? 226 : 225);
                ObjectSetInteger(0, "EXTREME_MARKER", OBJPROP_COLOR, clrMagenta);
                ObjectSetInteger(0, "EXTREME_MARKER", OBJPROP_WIDTH, 2);
            }
        }
    }

    if(currentZone.isActive && currentZone.isTouched) {
        int shiftExtreme = iBarShift(_Symbol, _Period, currentZone.extremeTime);
        
        // --- BƯỚC 1: Sửa j >= 3 để FVG luôn là nến đã ĐÓNG CỬA hoàn toàn ---
        if(shiftExtreme >= 3) {
            for(int j = shiftExtreme; j >= 3; j--) {
                double gHigh = EMPTY_VALUE, gLow = EMPTY_VALUE;
                bool isFVG = false;

                if(currentZone.type == 1 && low[j] > high[j-2]) { 
                    gHigh = low[j]; gLow = high[j-2]; isFVG = true; 
                } 
                else if(currentZone.type == -1 && high[j] < low[j-2]) { 
                    gLow = high[j]; gHigh = low[j-2]; isFVG = true; 
                }

                if(isFVG) {
                    datetime fvgTime = time[j-1]; 
                    string fvgName = "IND_M1_FVG_" + IntegerToString(fvgTime);
                    
                    bool isInside = false;
                    if(currentZone.type == 1 && gHigh <= currentZone.entry && gLow >= currentZone.sl) isInside = true;
                    if(currentZone.type == -1 && gLow >= currentZone.entry && gHigh <= currentZone.sl) isInside = true;

                    double distance = MathAbs((gHigh + gLow)/2.0 - currentZone.entry);

                    bool exists = false;
                    for(int k = 0; k < ArraySize(activeFVGs); k++) { if(activeFVGs[k].name == fvgName) { exists = true; break; } }

                    if(!exists) {
                        bool canAdd = true;

                        if(!isInside) {
                            if(outside_iFVG_Count > 0) canAdd = false; 
                            else {
                                for(int k = ArraySize(activeFVGs)-1; k >= 0; k--) {
                                    if(!activeFVGs[k].isInsideZone && !activeFVGs[k].isInverted) {
                                        if(distance < activeFVGs[k].distanceToZone) {
                                            ObjectDelete(0, activeFVGs[k].name); 
                                            ArrayRemove(activeFVGs, k, 1);       
                                        } else {
                                            canAdd = false; 
                                        }
                                    }
                                }
                            }
                        }

                        if(canAdd) {
                            // --- FIX LỊCH SỬ: Quét tìm chính xác nến ĐÃ phá vỡ Box này trong quá khứ ---
                            bool historicallyInverted = false;
                            datetime exactLockTime = 0;
                            
                            for(int scan = j - 3; scan >= 1; scan--) {
                                if(currentZone.type == 1 && close[scan] > gHigh) {
                                    historicallyInverted = true; exactLockTime = time[scan]; break;
                                }
                                if(currentZone.type == -1 && close[scan] < gLow) {
                                    historicallyInverted = true; exactLockTime = time[scan]; break;
                                }
                            }

                            int size = ArraySize(activeFVGs); ArrayResize(activeFVGs, size + 1);
                            activeFVGs[size].name = fvgName; activeFVGs[size].gapHigh = gHigh;
                            activeFVGs[size].gapLow = gLow; activeFVGs[size].startTime = fvgTime;
                            activeFVGs[size].isInsideZone = isInside; 
                            activeFVGs[size].isInverted = historicallyInverted;
                            activeFVGs[size].distanceToZone = distance;

                            // Vẽ cạnh phải chính xác theo lịch sử
                            ObjectCreate(0, fvgName, OBJ_RECTANGLE, 0, fvgTime, gHigh, 
                                         historicallyInverted ? exactLockTime + PeriodSeconds() : time[0] + PeriodSeconds(), gLow);
                            ObjectSetInteger(0, fvgName, OBJPROP_COLOR, historicallyInverted ? ((currentZone.type == 1) ? iFVG_Buy_Color : iFVG_Sell_Color) : FVG_Color_Pending);
                            ObjectSetInteger(0, fvgName, OBJPROP_FILL, true);
                            ObjectSetInteger(0, fvgName, OBJPROP_BACK, false); 
                            
                            if(historicallyInverted && !isInside) outside_iFVG_Count++;
                        }
                    }
                }
            }
        }

        // --- BƯỚC 2: TRACKING THỜI GIAN THỰC (Cho những FVG chưa bị phá) ---
        for(int k = 0; k < ArraySize(activeFVGs); k++) {
            if(!activeFVGs[k].isInverted) {
                bool triggerInversion = false;
                datetime lockTime = 0;
                
                if(currentZone.type == 1 && close[1] > activeFVGs[k].gapHigh) { triggerInversion = true; lockTime = time[1]; }
                if(currentZone.type == -1 && close[1] < activeFVGs[k].gapLow) { triggerInversion = true; lockTime = time[1]; }

                if(triggerInversion) {
                    activeFVGs[k].isInverted = true; 
                    ObjectSetInteger(0, activeFVGs[k].name, OBJPROP_COLOR, (currentZone.type == 1) ? iFVG_Buy_Color : iFVG_Sell_Color);
                    // Cắt gọt chính xác tại nến đóng
                    ObjectSetInteger(0, activeFVGs[k].name, OBJPROP_TIME, 1, lockTime + PeriodSeconds());
                    if(!activeFVGs[k].isInsideZone) outside_iFVG_Count++; 
                } else {
                    // Update nhích theo từng nến hiện tại
                    ObjectSetInteger(0, activeFVGs[k].name, OBJPROP_TIME, 1, time[0] + PeriodSeconds());
                }
            }
        }
    }

    return(rates_total);
}
//+------------------------------------------------------------------+