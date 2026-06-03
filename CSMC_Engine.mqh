//+------------------------------------------------------------------+
//|                                                  CSMC_Engine.mqh |
//|                                     Focus: CHOCH Priority Sync   |
//|                                     Status: Radar Sync Update    |
//|                                     Version: 6.0 (Radar + mZone) |
//+------------------------------------------------------------------+
struct TSwing { double price; datetime time; bool isActive; int idx; };
struct TZone  { string name; double entryPrice; double stopPrice; };

class CSMC_Engine
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   string            m_prefix;
   bool              m_isHTF;
   bool              m_showMinor;
   bool              m_showGraphics;
   bool              m_showZone;

   color             c_BuyZone, c_SellZone, c_KeyLevel, c_BOSUp, c_BOSDn, c_mBOSUp, c_mBOSDn;

   double            HAOpen[], HAHigh[], HALow[], HAClose[], HAColor[];
   double            majorSwingHigh[], majorSwingLow[];
   double            minorSwingHigh[], minorSwingLow[];

   TSwing            ActiveHigh, ActiveLow, ActiveMinorHigh, ActiveMinorLow;

   string            BOSUpQueue[], BOSDnQueue[];
   TZone             BuyZonesQueue[], SellZonesQueue[];

   string            MinorBOSUpQueue[], MinorBOSDnQueue[];
   TZone             MinorBuyZonesQueue[], MinorSellZonesQueue[];

   int               m_prev_calculated;

   datetime          last_processed_high_time, last_processed_low_time;
   int               last_break_dir;
   int               last_break_type;
   datetime          latest_break_up_time;   int latest_break_up_idx;   double latest_break_up_level;
   datetime          latest_break_down_time; int latest_break_down_idx; double latest_break_down_level;

   datetime          last_processed_minor_high_time, last_processed_minor_low_time;
   int               last_minor_break_dir;
   datetime          latest_minor_break_up_time;   int latest_minor_break_up_idx;
   datetime          latest_minor_break_down_time; int latest_minor_break_down_idx;

   int               major_trend, minor_trend;
   double            maj_prot_high, maj_prot_low, min_prot_high, min_prot_low;
   datetime          maj_prot_high_time, maj_prot_low_time, min_prot_high_time, min_prot_low_time;
   int               maj_prot_high_idx, maj_prot_low_idx, min_prot_high_idx, min_prot_low_idx;

   double            maj_extreme_high, maj_extreme_low, min_extreme_high, min_extreme_low;
   datetime          maj_extreme_high_time, maj_extreme_low_time, min_extreme_high_time, min_extreme_low_time;
   int               maj_extreme_high_idx, maj_extreme_low_idx, min_extreme_high_idx, min_extreme_low_idx;

   double            last_maj_high, last_maj_low, last_min_high, last_min_low;
   datetime          last_maj_high_time, last_maj_low_time, last_min_high_time, last_min_low_time;
   int               last_maj_high_idx, last_maj_low_idx, last_min_high_idx, last_min_low_idx;

   double            g_high_lvl, g_low_lvl;
   datetime          g_high_time, g_low_time;
   string            g_high_text, g_low_text;

   int               PeriodsInMajorSwing;
   int               PeriodsInMinorSwing;
   int               MaxZones;
   int               MaxBOSLines;
   int               MaxMinorBOSLines;

   // === [RADAR SYSTEM - V6.0] ===
   // Major Confirmed Extreme (Weak High/Low)
   double            maj_confirmed_extreme_high, maj_confirmed_extreme_low;
   datetime          maj_confirmed_extreme_high_time, maj_confirmed_extreme_low_time;
   // Major Radar Pending
   bool              pending_prot_high_update, pending_prot_low_update;
   datetime          processed_prot_weak_high_time, processed_prot_weak_low_time;
   datetime          prot_anchor_time;
   int               prot_breakout_idx;
   // Major Sweep Flags
   bool              is_maj_prot_high_sweep, is_maj_prot_low_sweep;
   // Minor Confirmed Extreme
   double            min_confirmed_extreme_high, min_confirmed_extreme_low;
   datetime          min_confirmed_extreme_high_time, min_confirmed_extreme_low_time;
   // Minor Radar Pending
   bool              min_pending_prot_high_update, min_pending_prot_low_update;
   datetime          min_processed_prot_weak_high_time, min_processed_prot_weak_low_time;
   datetime          min_prot_anchor_time;
   int               min_prot_breakout_idx;
   // Minor Sweep Flags
   bool              is_min_prot_high_sweep, is_min_prot_low_sweep;
   // === [KẾT THÚC RADAR SYSTEM] ===

   // Lưu trữ riêng đường CHOCH (tách khỏi BOS queue để tránh bị evict bởi MaxBOSLines)
   string            current_choch_up_name, current_choch_dn_name;
   string            current_minor_choch_up_name, current_minor_choch_dn_name;

public:
   double            open[], high[], low[], close[];
   datetime          time[];
   datetime          BrokenTime[];

   int               MajorEvent[];
   int               OriginIdx[];

   int      current_major_trend;
   int      current_minor_trend;

   double   current_buy_zone_entry, current_buy_zone_sl;
   double   current_sell_zone_entry, current_sell_zone_sl;
   double   current_minor_buy_zone_entry, current_minor_buy_zone_sl;
   double   current_minor_sell_zone_entry, current_minor_sell_zone_sl;

   string   current_market_phase;
   string   current_minor_phase;

   double   current_maj_prot_high, current_maj_prot_low;
   double   current_min_prot_high, current_min_prot_low;

   double   current_maj_extreme_high, current_maj_extreme_low;
   double   current_maj_active_high, current_maj_active_low;

   // [V6.0] Confirmed Extreme (Weak High / Weak Low) - dùng cho TP target nâng cao
   double   current_maj_confirmed_extreme_high, current_maj_confirmed_extreme_low;
   // Mức BOS/ChoCh vừa break — dùng cho entry LIMIT_AT_BOS
   double   current_bos_up_level;   // Swing high vừa bị phá lên (BOS Up / ChoCh Up)
   double   current_bos_dn_level;   // Swing low vừa bị phá xuống (BOS Down / ChoCh Down)

   void Init(string sym, ENUM_TIMEFRAMES tf, string prefix, bool isHTF, bool showMinor, bool showGraphics,
             color bZone, color sZone, color kLevel, color bUp, color bDn, color mbUp, color mbDn,
             int maj_swing, int min_swing, int max_zones, int max_bos, int max_mbos, bool showZone = true)
   {
      m_symbol = sym; m_tf = tf; m_prefix = prefix; m_isHTF = isHTF; m_showMinor = showMinor; m_showGraphics = showGraphics;
      c_BuyZone = bZone; c_SellZone = sZone; c_KeyLevel = kLevel;
      c_BOSUp = bUp; c_BOSDn = bDn; c_mBOSUp = mbUp; c_mBOSDn = mbDn;
      PeriodsInMajorSwing = maj_swing; PeriodsInMinorSwing = min_swing;
      MaxZones = max_zones; MaxBOSLines = max_bos; MaxMinorBOSLines = max_mbos;
      m_prev_calculated = 0;
      m_showZone = showZone;
   }

   void ResetState()
   {
      if (m_showGraphics) ObjectsDeleteAll(0, m_prefix);

      ActiveHigh.isActive = false; ActiveLow.isActive = false;
      ActiveMinorHigh.isActive = false; ActiveMinorLow.isActive = false;
      ActiveHigh.idx = -1; ActiveLow.idx = -1; ActiveMinorHigh.idx = -1; ActiveMinorLow.idx = -1;

      major_trend = 0; minor_trend = 0;
      maj_prot_high = EMPTY_VALUE; maj_prot_low = EMPTY_VALUE;
      maj_extreme_high = EMPTY_VALUE; maj_extreme_low = EMPTY_VALUE;
      last_maj_high = EMPTY_VALUE; last_maj_low = EMPTY_VALUE;
      min_prot_high = EMPTY_VALUE; min_prot_low = EMPTY_VALUE;
      min_extreme_high = EMPTY_VALUE; min_extreme_low = EMPTY_VALUE;
      last_min_high = EMPTY_VALUE; last_min_low = EMPTY_VALUE;

      maj_prot_high_idx = -1; maj_prot_low_idx = -1; maj_extreme_high_idx = -1; maj_extreme_low_idx = -1; last_maj_high_idx = -1; last_maj_low_idx = -1;
      min_prot_high_idx = -1; min_prot_low_idx = -1; min_extreme_high_idx = -1; min_extreme_low_idx = -1; last_min_high_idx = -1; last_min_low_idx = -1;

      last_processed_high_time = 0; last_processed_low_time = 0;
      last_break_dir = 0; last_break_type = 0;
      latest_break_up_time = 0; latest_break_up_idx = -1; latest_break_up_level = EMPTY_VALUE;
      latest_break_down_time = 0; latest_break_down_idx = -1; latest_break_down_level = EMPTY_VALUE;

      last_processed_minor_high_time = 0; last_processed_minor_low_time = 0;
      last_minor_break_dir = 0; latest_minor_break_up_time = 0; latest_minor_break_down_time = 0;
      latest_minor_break_up_idx = -1; latest_minor_break_down_idx = -1;

      g_high_lvl = EMPTY_VALUE; g_low_lvl = EMPTY_VALUE;

      ArrayResize(BOSUpQueue, 0); ArrayResize(BOSDnQueue, 0);
      ArrayResize(BuyZonesQueue, 0); ArrayResize(SellZonesQueue, 0);
      ArrayResize(MinorBOSUpQueue, 0); ArrayResize(MinorBOSDnQueue, 0);
      ArrayResize(MinorBuyZonesQueue, 0); ArrayResize(MinorSellZonesQueue, 0);

      current_market_phase = "Analyzing..."; current_minor_phase = "Analyzing...";

      // [RADAR SYSTEM RESET - V6.0]
      maj_confirmed_extreme_high = EMPTY_VALUE; maj_confirmed_extreme_low = EMPTY_VALUE;
      maj_confirmed_extreme_high_time = 0; maj_confirmed_extreme_low_time = 0;
      pending_prot_high_update = false; pending_prot_low_update = false;
      processed_prot_weak_high_time = 0; processed_prot_weak_low_time = 0;
      prot_anchor_time = 0; prot_breakout_idx = -1;
      is_maj_prot_high_sweep = false; is_maj_prot_low_sweep = false;

      min_confirmed_extreme_high = EMPTY_VALUE; min_confirmed_extreme_low = EMPTY_VALUE;
      min_confirmed_extreme_high_time = 0; min_confirmed_extreme_low_time = 0;
      min_pending_prot_high_update = false; min_pending_prot_low_update = false;
      min_processed_prot_weak_high_time = 0; min_processed_prot_weak_low_time = 0;
      min_prot_anchor_time = 0; min_prot_breakout_idx = -1;
      is_min_prot_high_sweep = false; is_min_prot_low_sweep = false;
      current_choch_up_name = ""; current_choch_dn_name = "";
      current_minor_choch_up_name = ""; current_minor_choch_dn_name = "";
      current_bos_up_level = 0; current_bos_dn_level = 0;
   }

   void Update()
   {
      int current_bars = iBars(m_symbol, m_tf);
      if(current_bars < 100) return;

      MqlRates rates[]; ArraySetAsSeries(rates, true);
      int rates_total = CopyRates(m_symbol, m_tf, 0, 5000, rates);
      if(rates_total < 100) return;

      ArrayResize(open, rates_total);  ArraySetAsSeries(open, true);
      ArrayResize(high, rates_total);  ArraySetAsSeries(high, true);
      ArrayResize(low, rates_total);   ArraySetAsSeries(low, true);
      ArrayResize(close, rates_total); ArraySetAsSeries(close, true);
      ArrayResize(time, rates_total);  ArraySetAsSeries(time, true);
      ArrayResize(HAOpen, rates_total);  ArraySetAsSeries(HAOpen, true);
      ArrayResize(HAHigh, rates_total);  ArraySetAsSeries(HAHigh, true);
      ArrayResize(HALow, rates_total);   ArraySetAsSeries(HALow, true);
      ArrayResize(HAClose, rates_total); ArraySetAsSeries(HAClose, true);
      ArrayResize(HAColor, rates_total); ArraySetAsSeries(HAColor, true);
      ArrayResize(majorSwingHigh, rates_total); ArraySetAsSeries(majorSwingHigh, true);
      ArrayResize(majorSwingLow, rates_total);  ArraySetAsSeries(majorSwingLow, true);
      ArrayResize(minorSwingHigh, rates_total); ArraySetAsSeries(minorSwingHigh, true);
      ArrayResize(minorSwingLow, rates_total);  ArraySetAsSeries(minorSwingLow, true);

      ArrayResize(MajorEvent, rates_total); ArraySetAsSeries(MajorEvent, true);
      ArrayResize(OriginIdx, rates_total);  ArraySetAsSeries(OriginIdx, true);
      ArrayResize(BrokenTime, rates_total); ArraySetAsSeries(BrokenTime, true);

      for(int i = 0; i < rates_total; i++) { open[i] = rates[i].open; high[i] = rates[i].high; low[i] = rates[i].low; close[i] = rates[i].close; time[i] = rates[i].time; }

      int lookBack_max = MathMax(PeriodsInMajorSwing, PeriodsInMinorSwing) * 2;
      int data_limit = 0;
      int bos_limit = 0;

      if (m_prev_calculated == 0) {
         data_limit = rates_total - lookBack_max - 1;
         if (data_limit < 0) return;
         bos_limit = data_limit;
         ResetState();
         ArrayInitialize(majorSwingHigh, EMPTY_VALUE); ArrayInitialize(majorSwingLow, EMPTY_VALUE);
         ArrayInitialize(minorSwingHigh, EMPTY_VALUE); ArrayInitialize(minorSwingLow, EMPTY_VALUE);
      } else {
         int shift = current_bars - m_prev_calculated;
         if(shift > 0) {
            if(ActiveHigh.idx >= 0) ActiveHigh.idx += shift; if(ActiveLow.idx >= 0) ActiveLow.idx += shift;
            if(ActiveMinorHigh.idx >= 0) ActiveMinorHigh.idx += shift; if(ActiveMinorLow.idx >= 0) ActiveMinorLow.idx += shift;
            if(maj_prot_high_idx >= 0) maj_prot_high_idx += shift; if(maj_prot_low_idx >= 0) maj_prot_low_idx += shift;
            if(maj_extreme_high_idx >= 0) maj_extreme_high_idx += shift; if(maj_extreme_low_idx >= 0) maj_extreme_low_idx += shift;
            if(last_maj_high_idx >= 0) last_maj_high_idx += shift; if(last_maj_low_idx >= 0) last_maj_low_idx += shift;
            if(latest_break_up_idx >= 0) latest_break_up_idx += shift; if(latest_break_down_idx >= 0) latest_break_down_idx += shift;
            if(min_prot_high_idx >= 0) min_prot_high_idx += shift; if(min_prot_low_idx >= 0) min_prot_low_idx += shift;
            if(min_extreme_high_idx >= 0) min_extreme_high_idx += shift; if(min_extreme_low_idx >= 0) min_extreme_low_idx += shift;
            if(last_min_high_idx >= 0) last_min_high_idx += shift; if(last_min_low_idx >= 0) last_min_low_idx += shift;
            if(prot_breakout_idx >= 0) prot_breakout_idx += shift;
            if(min_prot_breakout_idx >= 0) min_prot_breakout_idx += shift;

            data_limit = rates_total - lookBack_max - 1;
         } else {
            data_limit = lookBack_max;
         }
         bos_limit = shift + 1;
         if (bos_limit > rates_total - lookBack_max - 1) bos_limit = rates_total - lookBack_max - 1;
      }
      m_prev_calculated = current_bars;

      for(int i = data_limit + lookBack_max; i >= 0; i--) {
         HAClose[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
         if(i >= rates_total - 1) HAOpen[i] = (open[i] + close[i]) / 2.0; else HAOpen[i] = (HAOpen[i+1] + HAClose[i+1]) / 2.0;
         HAHigh[i] = MathMax(high[i], MathMax(HAOpen[i], HAClose[i])); HALow[i] = MathMin(low[i], MathMin(HAOpen[i], HAClose[i]));
         HAColor[i] = (HAClose[i] >= HAOpen[i]) ? 0 : 1;
      }

      for(int i = 0; i <= data_limit; i++) {
         majorSwingHigh[i + PeriodsInMajorSwing] = EMPTY_VALUE; majorSwingLow[i + PeriodsInMajorSwing] = EMPTY_VALUE;
         minorSwingHigh[i + PeriodsInMinorSwing] = EMPTY_VALUE; minorSwingLow[i + PeriodsInMinorSwing] = EMPTY_VALUE;
         if (i > 0) {
            if(ArrayMaximum(high, i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing) majorSwingHigh[i + PeriodsInMajorSwing] = high[i + PeriodsInMajorSwing];
            if(ArrayMinimum(low,  i, PeriodsInMajorSwing * 2 + 1) == i + PeriodsInMajorSwing) majorSwingLow[i + PeriodsInMajorSwing]  = low[i + PeriodsInMajorSwing];
            if(ArrayMaximum(high, i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing) minorSwingHigh[i + PeriodsInMinorSwing] = high[i + PeriodsInMinorSwing];
            if(ArrayMinimum(low,  i, PeriodsInMinorSwing * 2 + 1) == i + PeriodsInMinorSwing) minorSwingLow[i + PeriodsInMinorSwing]  = low[i + PeriodsInMinorSwing];
         }
      }

      for(int i = bos_limit; i >= 0; i--)
      {
         MajorEvent[i] = 0;
         BrokenTime[i] = 0;
         OriginIdx[i]  = -1;

         // --- Validate Active Swings ---
         if(ActiveHigh.isActive)      { if(ActiveHigh.idx >= 0      && ActiveHigh.idx < rates_total      && majorSwingHigh[ActiveHigh.idx] == EMPTY_VALUE)      ActiveHigh.isActive = false; }
         if(ActiveLow.isActive)       { if(ActiveLow.idx >= 0       && ActiveLow.idx < rates_total       && majorSwingLow[ActiveLow.idx] == EMPTY_VALUE)         ActiveLow.isActive = false; }
         if(ActiveMinorHigh.isActive) { if(ActiveMinorHigh.idx >= 0 && ActiveMinorHigh.idx < rates_total && minorSwingHigh[ActiveMinorHigh.idx] == EMPTY_VALUE)  ActiveMinorHigh.isActive = false; }
         if(ActiveMinorLow.isActive)  { if(ActiveMinorLow.idx >= 0  && ActiveMinorLow.idx < rates_total  && minorSwingLow[ActiveMinorLow.idx] == EMPTY_VALUE)    ActiveMinorLow.isActive = false; }

         // --- Invalidate Prot Levels (sweep-sticky: skip nếu đã được đánh dấu là sweep) ---
         if(maj_prot_high != EMPTY_VALUE && !is_maj_prot_high_sweep) { if(maj_prot_high_idx >= 0 && maj_prot_high_idx < rates_total && majorSwingHigh[maj_prot_high_idx] == EMPTY_VALUE) { maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1; } }
         if(maj_prot_low  != EMPTY_VALUE && !is_maj_prot_low_sweep)  { if(maj_prot_low_idx >= 0  && maj_prot_low_idx < rates_total  && majorSwingLow[maj_prot_low_idx] == EMPTY_VALUE)    { maj_prot_low = EMPTY_VALUE;  maj_prot_low_idx = -1;  } }
         if(min_prot_high != EMPTY_VALUE && !is_min_prot_high_sweep) { if(min_prot_high_idx >= 0 && min_prot_high_idx < rates_total && minorSwingHigh[min_prot_high_idx] == EMPTY_VALUE) { min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1; } }
         if(min_prot_low  != EMPTY_VALUE && !is_min_prot_low_sweep)  { if(min_prot_low_idx >= 0  && min_prot_low_idx < rates_total  && minorSwingLow[min_prot_low_idx] == EMPTY_VALUE)    { min_prot_low = EMPTY_VALUE;  min_prot_low_idx = -1;  } }

         // --- Major Swing Tracking + Confirmed Extreme Detection ---
         int swingMajor_idx = i + PeriodsInMajorSwing;
         if (swingMajor_idx < rates_total) {
            if(majorSwingHigh[swingMajor_idx] != EMPTY_VALUE) {
               ActiveHigh.price = majorSwingHigh[swingMajor_idx]; ActiveHigh.time = time[swingMajor_idx]; ActiveHigh.isActive = true; ActiveHigh.idx = swingMajor_idx;
               last_maj_high = ActiveHigh.price; last_maj_high_time = ActiveHigh.time; last_maj_high_idx = swingMajor_idx;
               // Xác nhận Confirmed Extreme khi swing high == đỉnh extreme hiện tại
               if (major_trend == 1 && majorSwingHigh[swingMajor_idx] == maj_extreme_high) {
                  maj_confirmed_extreme_high = majorSwingHigh[swingMajor_idx];
                  maj_confirmed_extreme_high_time = time[swingMajor_idx];
               }
               if (time[swingMajor_idx] > last_processed_high_time) {
                  last_processed_high_time = time[swingMajor_idx];
                  if (last_break_dir == -1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_down_time) {
                     int b_idx = latest_break_down_idx;
                     if (b_idx != -1) {
                        string zone_name = m_prefix + "ZONE_SELL_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, swingMajor_idx, b_idx, true, latest_break_down_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
            }
            if(majorSwingLow[swingMajor_idx] != EMPTY_VALUE) {
               ActiveLow.price = majorSwingLow[swingMajor_idx]; ActiveLow.time = time[swingMajor_idx]; ActiveLow.isActive = true; ActiveLow.idx = swingMajor_idx;
               last_maj_low = ActiveLow.price; last_maj_low_time = ActiveLow.time; last_maj_low_idx = swingMajor_idx;
               // Xác nhận Confirmed Extreme khi swing low == đáy extreme hiện tại
               if (major_trend == -1 && majorSwingLow[swingMajor_idx] == maj_extreme_low) {
                  maj_confirmed_extreme_low = majorSwingLow[swingMajor_idx];
                  maj_confirmed_extreme_low_time = time[swingMajor_idx];
               }
               if (time[swingMajor_idx] > last_processed_low_time) {
                  last_processed_low_time = time[swingMajor_idx];
                  if (last_break_dir == 1 && last_break_type == 1 && time[swingMajor_idx] <= latest_break_up_time) {
                     int b_idx = latest_break_up_idx;
                     if (b_idx != -1) {
                        string zone_name = m_prefix + "ZONE_BUY_BOS_" + IntegerToString((long)time[swingMajor_idx]);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, swingMajor_idx, b_idx, false, latest_break_up_level, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
            }
         }

         // --- Minor Swing Tracking + Confirmed Extreme Detection ---
         int swingMinor_idx = i + PeriodsInMinorSwing;
         if (swingMinor_idx < rates_total) {
            if(minorSwingHigh[swingMinor_idx] != EMPTY_VALUE) {
               ActiveMinorHigh.price = minorSwingHigh[swingMinor_idx]; ActiveMinorHigh.time = time[swingMinor_idx]; ActiveMinorHigh.isActive = true; ActiveMinorHigh.idx = swingMinor_idx;
               last_min_high = ActiveMinorHigh.price; last_min_high_time = ActiveMinorHigh.time; last_min_high_idx = swingMinor_idx;
               if (minor_trend == 1 && minorSwingHigh[swingMinor_idx] == min_extreme_high) {
                  min_confirmed_extreme_high = minorSwingHigh[swingMinor_idx];
                  min_confirmed_extreme_high_time = time[swingMinor_idx];
               }
            }
            if(minorSwingLow[swingMinor_idx] != EMPTY_VALUE) {
               ActiveMinorLow.price = minorSwingLow[swingMinor_idx]; ActiveMinorLow.time = time[swingMinor_idx]; ActiveMinorLow.isActive = true; ActiveMinorLow.idx = swingMinor_idx;
               last_min_low = ActiveMinorLow.price; last_min_low_time = ActiveMinorLow.time; last_min_low_idx = swingMinor_idx;
               if (minor_trend == -1 && minorSwingLow[swingMinor_idx] == min_extreme_low) {
                  min_confirmed_extreme_low = minorSwingLow[swingMinor_idx];
                  min_confirmed_extreme_low_time = time[swingMinor_idx];
               }
            }
         }

         // --- Extreme Tracking (chỉ theo dõi đỉnh/đáy, KHÔNG cập nhật prot level trực tiếp) ---
         if (major_trend == 1) {
            if (maj_extreme_high == EMPTY_VALUE || high[i] > maj_extreme_high) { maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i; }
         } else if (major_trend == -1) {
            if (maj_extreme_low == EMPTY_VALUE || low[i] < maj_extreme_low)   { maj_extreme_low = low[i];   maj_extreme_low_time = time[i];  maj_extreme_low_idx = i;  }
         }
         if (minor_trend == 1) {
            if (min_extreme_high == EMPTY_VALUE || high[i] > min_extreme_high) { min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i; }
         } else if (minor_trend == -1) {
            if (min_extreme_low == EMPTY_VALUE || low[i] < min_extreme_low)   { min_extreme_low = low[i];   min_extreme_low_time = time[i];  min_extreme_low_idx = i;  }
         }

         if(i > 0)
         {
            // --- Zone Queue Cleanup ---
            for(int j = ArraySize(BuyZonesQueue)  - 1; j >= 0; j--) { if(HAClose[i] < BuyZonesQueue[j].stopPrice)  { if(m_showGraphics) ObjectDelete(0, BuyZonesQueue[j].name);  for(int k = j; k < ArraySize(BuyZonesQueue)  - 1; k++) BuyZonesQueue[k]  = BuyZonesQueue[k+1];  ArrayResize(BuyZonesQueue,  ArraySize(BuyZonesQueue)  - 1); } }
            for(int j = ArraySize(SellZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] > SellZonesQueue[j].stopPrice) { if(m_showGraphics) ObjectDelete(0, SellZonesQueue[j].name); for(int k = j; k < ArraySize(SellZonesQueue) - 1; k++) SellZonesQueue[k] = SellZonesQueue[k+1]; ArrayResize(SellZonesQueue, ArraySize(SellZonesQueue) - 1); } }
            for(int j = ArraySize(MinorBuyZonesQueue)  - 1; j >= 0; j--) { if(HAClose[i] < MinorBuyZonesQueue[j].stopPrice)  { if(m_showGraphics) ObjectDelete(0, MinorBuyZonesQueue[j].name);  for(int k = j; k < ArraySize(MinorBuyZonesQueue)  - 1; k++) MinorBuyZonesQueue[k]  = MinorBuyZonesQueue[k+1];  ArrayResize(MinorBuyZonesQueue,  ArraySize(MinorBuyZonesQueue)  - 1); } }
            for(int j = ArraySize(MinorSellZonesQueue) - 1; j >= 0; j--) { if(HAClose[i] > MinorSellZonesQueue[j].stopPrice) { if(m_showGraphics) ObjectDelete(0, MinorSellZonesQueue[j].name); for(int k = j; k < ArraySize(MinorSellZonesQueue) - 1; k++) MinorSellZonesQueue[k] = MinorSellZonesQueue[k+1]; ArrayResize(MinorSellZonesQueue, ArraySize(MinorSellZonesQueue) - 1); } }

            // =========================================================================
            // KHỞI TẠO XU HƯỚNG MỒI (DEADLOCK PREVENTION) - có fallback an toàn
            // =========================================================================
            if (major_trend == 0) {
               if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) {
                  major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i;
                  maj_prot_low = (last_maj_low != EMPTY_VALUE) ? last_maj_low : low[i];
                  maj_prot_low_time = (last_maj_low_time != 0) ? last_maj_low_time : time[i];
                  maj_prot_low_idx  = (last_maj_low_idx != -1) ? last_maj_low_idx  : i;
                  is_maj_prot_low_sweep = false;
               } else if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) {
                  major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i;
                  maj_prot_high = (last_maj_high != EMPTY_VALUE) ? last_maj_high : high[i];
                  maj_prot_high_time = (last_maj_high_time != 0) ? last_maj_high_time : time[i];
                  maj_prot_high_idx  = (last_maj_high_idx != -1) ? last_maj_high_idx  : i;
                  is_maj_prot_high_sweep = false;
               }
            }
            if (minor_trend == 0) {
               if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) {
                  minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i;
                  min_prot_low = (last_min_low != EMPTY_VALUE) ? last_min_low : low[i];
                  min_prot_low_time = (last_min_low_time != 0) ? last_min_low_time : time[i];
                  min_prot_low_idx  = (last_min_low_idx != -1) ? last_min_low_idx  : i;
                  is_min_prot_low_sweep = false;
               } else if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) {
                  minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i;
                  min_prot_high = (last_min_high != EMPTY_VALUE) ? last_min_high : high[i];
                  min_prot_high_time = (last_min_high_time != 0) ? last_min_high_time : time[i];
                  min_prot_high_idx  = (last_min_high_idx != -1) ? last_min_high_idx  : i;
                  is_min_prot_high_sweep = false;
               }
            }

            // =========================================================================
            // MAJOR RADAR: KÍCH HOẠT KHI GIÁ PHÁ VỠ CONFIRMED EXTREME (WEAK HIGH/LOW)
            // Immediate set Protected Level = last_maj_low/high + D5 scan
            // Radar streaming tiếp tục tìm D4 mới hơn (gần BOS hơn, chưa confirm lúc trigger)
            // =========================================================================
            // Major Uptrend: HA phá Weak High → Immediate set Protected Low = last_maj_low + D5 scan
            if (major_trend == 1 && maj_confirmed_extreme_high != EMPTY_VALUE &&
                HAClose[i] > maj_confirmed_extreme_high &&
                processed_prot_weak_high_time != maj_confirmed_extreme_high_time) {
               processed_prot_weak_high_time = maj_confirmed_extreme_high_time;
               if (last_maj_low != EMPTY_VALUE) {
                  double imm_d4 = last_maj_low; datetime imm_d4_t = last_maj_low_time; int imm_d4_idx = last_maj_low_idx;
                  double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                  for (int k = MathMin(last_maj_low_idx, ArraySize(low) - 1); k >= i; k--) {
                     if (low[k] < imm_d5) { imm_d5 = low[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                  }
                  if (imm_d5 < imm_d4) { maj_prot_low = imm_d5; maj_prot_low_time = imm_d5_t; maj_prot_low_idx = imm_d5_idx; is_maj_prot_low_sweep = true; }
                  else                  { maj_prot_low = imm_d4; maj_prot_low_time = imm_d4_t; maj_prot_low_idx = imm_d4_idx; is_maj_prot_low_sweep = false; }
                  pending_prot_low_update = true;
                  prot_anchor_time = last_maj_low_time;
                  prot_breakout_idx = i;
               }
            }
            // Major Downtrend: HA phá Weak Low → Immediate set Protected High = last_maj_high + D5 scan
            if (major_trend == -1 && maj_confirmed_extreme_low != EMPTY_VALUE &&
                HAClose[i] < maj_confirmed_extreme_low &&
                processed_prot_weak_low_time != maj_confirmed_extreme_low_time) {
               processed_prot_weak_low_time = maj_confirmed_extreme_low_time;
               if (last_maj_high != EMPTY_VALUE) {
                  double imm_d4 = last_maj_high; datetime imm_d4_t = last_maj_high_time; int imm_d4_idx = last_maj_high_idx;
                  double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                  for (int k = MathMin(last_maj_high_idx, ArraySize(high) - 1); k >= i; k--) {
                     if (high[k] > imm_d5) { imm_d5 = high[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                  }
                  if (imm_d5 > imm_d4) { maj_prot_high = imm_d5; maj_prot_high_time = imm_d5_t; maj_prot_high_idx = imm_d5_idx; is_maj_prot_high_sweep = true; }
                  else                  { maj_prot_high = imm_d4; maj_prot_high_time = imm_d4_t; maj_prot_high_idx = imm_d4_idx; is_maj_prot_high_sweep = false; }
                  pending_prot_high_update = true;
                  prot_anchor_time = last_maj_high_time;
                  prot_breakout_idx = i;
               }
            }

            // =========================================================================
            // MAJOR RADAR: THỰC THI D4/D5 (TÌM SWING + KIỂM TRA SWEEP)
            // =========================================================================
            if (major_trend == 1 && pending_prot_low_update && prot_breakout_idx != -1) {
               int anchor_idx = -1;
               for(int k = i; k < rates_total; k++) { if (time[k] == prot_anchor_time) { anchor_idx = k; break; } }
               if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx) {
                  double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
                  for(int k = prot_breakout_idx; k <= anchor_idx; k++) {
                     if (majorSwingLow[k] != EMPTY_VALUE) { d4_val = majorSwingLow[k]; d4_time = time[k]; d4_idx = k; break; }
                  }
                  if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = prot_breakout_idx; k <= d4_idx; k++) {
                        if (d5_val == EMPTY_VALUE || low[k] < d5_val) { d5_val = low[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val < d4_val) { maj_prot_low = d5_val; maj_prot_low_time = d5_time; maj_prot_low_idx = d5_idx; is_maj_prot_low_sweep = true; }
                     else                                            { maj_prot_low = d4_val; maj_prot_low_time = d4_time; maj_prot_low_idx = d4_idx; is_maj_prot_low_sweep = false; }
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) pending_prot_low_update = false;
                  } else {
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) pending_prot_low_update = false;
                  }
               } else { pending_prot_low_update = false; }
            }

            if (major_trend == -1 && pending_prot_high_update && prot_breakout_idx != -1) {
               int anchor_idx = -1;
               for(int k = i; k < rates_total; k++) { if (time[k] == prot_anchor_time) { anchor_idx = k; break; } }
               if (anchor_idx != -1 && prot_breakout_idx <= anchor_idx) {
                  double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
                  for(int k = prot_breakout_idx; k <= anchor_idx; k++) {
                     if (majorSwingHigh[k] != EMPTY_VALUE) { d4_val = majorSwingHigh[k]; d4_time = time[k]; d4_idx = k; break; }
                  }
                  if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = prot_breakout_idx; k <= d4_idx; k++) {
                        if (d5_val == EMPTY_VALUE || high[k] > d5_val) { d5_val = high[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val > d4_val) { maj_prot_high = d5_val; maj_prot_high_time = d5_time; maj_prot_high_idx = d5_idx; is_maj_prot_high_sweep = true; }
                     else                                            { maj_prot_high = d4_val; maj_prot_high_time = d4_time; maj_prot_high_idx = d4_idx; is_maj_prot_high_sweep = false; }
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) pending_prot_high_update = false;
                  } else {
                     if (prot_breakout_idx - i >= PeriodsInMajorSwing) pending_prot_high_update = false;
                  }
               } else { pending_prot_high_update = false; }
            }

            // =========================================================================
            // MINOR RADAR: KÍCH HOẠT KHI GIÁ PHÁ VỠ CONFIRMED EXTREME (WEAK HIGH/LOW)
            // Immediate set Protected Level = last_min_low/high + D5 scan
            // Radar streaming tiếp tục tìm D4 mới hơn (gần BOS hơn, chưa confirm lúc trigger)
            // =========================================================================
            // Minor Uptrend: HA phá Weak High → Immediate set Protected Low = last_min_low + D5 scan
            if (minor_trend == 1 && min_confirmed_extreme_high != EMPTY_VALUE &&
                HAClose[i] > min_confirmed_extreme_high &&
                min_processed_prot_weak_high_time != min_confirmed_extreme_high_time) {
               min_processed_prot_weak_high_time = min_confirmed_extreme_high_time;
               if (last_min_low != EMPTY_VALUE) {
                  double imm_d4 = last_min_low; datetime imm_d4_t = last_min_low_time; int imm_d4_idx = last_min_low_idx;
                  double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                  for (int k = last_min_low_idx; k >= i; k--) {
                     if (low[k] < imm_d5) { imm_d5 = low[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                  }
                  if (imm_d5 < imm_d4) { min_prot_low = imm_d5; min_prot_low_time = imm_d5_t; min_prot_low_idx = imm_d5_idx; is_min_prot_low_sweep = true; }
                  else                  { min_prot_low = imm_d4; min_prot_low_time = imm_d4_t; min_prot_low_idx = imm_d4_idx; is_min_prot_low_sweep = false; }
                  min_pending_prot_low_update = true;
                  min_prot_anchor_time = last_min_low_time;
                  min_prot_breakout_idx = i;
               }
            }
            // Minor Downtrend: HA phá Weak Low → Immediate set Protected High = last_min_high + D5 scan
            if (minor_trend == -1 && min_confirmed_extreme_low != EMPTY_VALUE &&
                HAClose[i] < min_confirmed_extreme_low &&
                min_processed_prot_weak_low_time != min_confirmed_extreme_low_time) {
               min_processed_prot_weak_low_time = min_confirmed_extreme_low_time;
               if (last_min_high != EMPTY_VALUE) {
                  double imm_d4 = last_min_high; datetime imm_d4_t = last_min_high_time; int imm_d4_idx = last_min_high_idx;
                  double imm_d5 = imm_d4; datetime imm_d5_t = imm_d4_t; int imm_d5_idx = imm_d4_idx;
                  for (int k = last_min_high_idx; k >= i; k--) {
                     if (high[k] > imm_d5) { imm_d5 = high[k]; imm_d5_t = time[k]; imm_d5_idx = k; }
                  }
                  if (imm_d5 > imm_d4) { min_prot_high = imm_d5; min_prot_high_time = imm_d5_t; min_prot_high_idx = imm_d5_idx; is_min_prot_high_sweep = true; }
                  else                  { min_prot_high = imm_d4; min_prot_high_time = imm_d4_t; min_prot_high_idx = imm_d4_idx; is_min_prot_high_sweep = false; }
                  min_pending_prot_high_update = true;
                  min_prot_anchor_time = last_min_high_time;
                  min_prot_breakout_idx = i;
               }
            }

            // =========================================================================
            // MINOR RADAR: THỰC THI D4/D5
            // =========================================================================
            if (minor_trend == 1 && min_pending_prot_low_update && min_prot_breakout_idx != -1) {
               int anchor_idx = -1;
               for(int k = i; k < rates_total; k++) { if (time[k] == min_prot_anchor_time) { anchor_idx = k; break; } }
               if (anchor_idx != -1 && min_prot_breakout_idx <= anchor_idx) {
                  double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
                  for(int k = min_prot_breakout_idx; k <= anchor_idx; k++) {
                     if (minorSwingLow[k] != EMPTY_VALUE) { d4_val = minorSwingLow[k]; d4_time = time[k]; d4_idx = k; break; }
                  }
                  if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = min_prot_breakout_idx; k <= d4_idx; k++) {
                        if (d5_val == EMPTY_VALUE || low[k] < d5_val) { d5_val = low[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val < d4_val) { min_prot_low = d5_val; min_prot_low_time = d5_time; min_prot_low_idx = d5_idx; is_min_prot_low_sweep = true; }
                     else                                            { min_prot_low = d4_val; min_prot_low_time = d4_time; min_prot_low_idx = d4_idx; is_min_prot_low_sweep = false; }
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) min_pending_prot_low_update = false;
                  } else {
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) min_pending_prot_low_update = false;
                  }
               } else { min_pending_prot_low_update = false; }
            }

            if (minor_trend == -1 && min_pending_prot_high_update && min_prot_breakout_idx != -1) {
               int anchor_idx = -1;
               for(int k = i; k < rates_total; k++) { if (time[k] == min_prot_anchor_time) { anchor_idx = k; break; } }
               if (anchor_idx != -1 && min_prot_breakout_idx <= anchor_idx) {
                  double d4_val = EMPTY_VALUE; datetime d4_time = 0; int d4_idx = -1;
                  for(int k = min_prot_breakout_idx; k <= anchor_idx; k++) {
                     if (minorSwingHigh[k] != EMPTY_VALUE) { d4_val = minorSwingHigh[k]; d4_time = time[k]; d4_idx = k; break; }
                  }
                  if (d4_val != EMPTY_VALUE) {
                     double d5_val = EMPTY_VALUE; datetime d5_time = 0; int d5_idx = -1;
                     for(int k = min_prot_breakout_idx; k <= d4_idx; k++) {
                        if (d5_val == EMPTY_VALUE || high[k] > d5_val) { d5_val = high[k]; d5_time = time[k]; d5_idx = k; }
                     }
                     if (d5_val != EMPTY_VALUE && d5_val > d4_val) { min_prot_high = d5_val; min_prot_high_time = d5_time; min_prot_high_idx = d5_idx; is_min_prot_high_sweep = true; }
                     else                                            { min_prot_high = d4_val; min_prot_high_time = d4_time; min_prot_high_idx = d4_idx; is_min_prot_high_sweep = false; }
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) min_pending_prot_high_update = false;
                  } else {
                     if (min_prot_breakout_idx - i >= PeriodsInMinorSwing) min_pending_prot_high_update = false;
                  }
               } else { min_pending_prot_high_update = false; }
            }

            bool is_major_choch_up = false; bool is_major_choch_dn = false;
            bool is_minor_choch_up = false; bool is_minor_choch_dn = false;

            // =========================================================================
            // 1. MAJOR CHOCH DOWN
            // =========================================================================
            if (major_trend == 1 && maj_prot_low != EMPTY_VALUE && HAClose[i] < maj_prot_low) {
               current_market_phase = "Impulse Down - ChoCh Down";
               string choch_name = m_prefix + "CHOCH_DN_" + IntegerToString((long)maj_prot_low_time);
               if(ObjectFind(0, choch_name) < 0) {
                  CreateBOSLine(choch_name, maj_prot_low_time, maj_prot_low, time[i], c_BOSDn, m_isHTF ? "HCHOCH" : "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                  if(m_showGraphics && current_choch_up_name != "") { ObjectDelete(0, current_choch_up_name); ObjectDelete(0, current_choch_up_name + "_lbl"); current_choch_up_name = ""; }
                  current_choch_dn_name = choch_name;
                  current_bos_dn_level = maj_prot_low;
                  ClearZoneQueue(BuyZonesQueue);

                  double actual_extreme_high = maj_extreme_high; datetime actual_extreme_time = maj_extreme_high_time; int actual_extreme_idx = maj_extreme_high_idx;
                  int prot_idx = maj_prot_low_idx;
                  if (prot_idx != -1 && prot_idx >= i) {
                     int count = prot_idx - i + 1; int highest_idx = ArrayMaximum(high, i, count);
                     if (highest_idx != -1) { actual_extreme_high = high[highest_idx]; actual_extreme_time = time[highest_idx]; actual_extreme_idx = highest_idx; }
                  }

                  if(m_showGraphics) { ObjectDelete(0, m_prefix + "KEY_LEVEL"); ObjectDelete(0, m_prefix + "KEY_LEVEL_lbl"); }
                  CreateRayLine(m_prefix + "KEY_LEVEL", actual_extreme_time, actual_extreme_high, c_KeyLevel, (m_isHTF?"HTF ":"LTF ") + "Major Key Level Down", true);

                  MajorEvent[i] = -2;
                  BrokenTime[i] = maj_prot_low_time;
                  OriginIdx[i]  = actual_extreme_idx;

                  last_break_dir = -1; last_break_type = 2;
                  latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = maj_prot_low;

                  int zone_anchor_idx = actual_extreme_idx;
                  if (actual_extreme_idx != -1) {
                     for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                        if (k < rates_total && majorSwingHigh[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                     }
                  }
                  if(zone_anchor_idx != -1) {
                     string zone_name = m_prefix + "ZONE_SELL_CHOCH_" + IntegerToString((long)time[i]);
                     double zEntry, zStop;
                     CreateZoneHelper(zone_name, zone_anchor_idx, i, true, maj_prot_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                     PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                  }

                  if (ActiveLow.time == maj_prot_low_time) ActiveLow.isActive = false;
                  ClearQueue(BOSUpQueue);
                  major_trend = -1; maj_extreme_low = low[i]; maj_extreme_low_time = time[i]; maj_extreme_low_idx = i;

                  // Reset confirmed extreme + kích hoạt Radar cho downtrend mới
                  maj_confirmed_extreme_high = EMPTY_VALUE;
                  maj_prot_high = actual_extreme_high; maj_prot_high_time = actual_extreme_time; maj_prot_high_idx = actual_extreme_idx;
                  maj_prot_low = EMPTY_VALUE; maj_prot_low_idx = -1;
                  is_maj_prot_high_sweep = true;
                  pending_prot_high_update = true;
                  prot_anchor_time = actual_extreme_time;
                  prot_breakout_idx = i;
                  pending_prot_low_update = false;
               }
               is_major_choch_dn = true;
            }
            // =========================================================================
            // 2. MAJOR CHOCH UP
            // =========================================================================
            else if (major_trend == -1 && maj_prot_high != EMPTY_VALUE && HAClose[i] > maj_prot_high) {
               current_market_phase = "Impulse Up - ChoCh Up";
               string choch_name = m_prefix + "CHOCH_UP_" + IntegerToString((long)maj_prot_high_time);
               if(ObjectFind(0, choch_name) < 0) {
                  CreateBOSLine(choch_name, maj_prot_high_time, maj_prot_high, time[i], c_BOSUp, m_isHTF ? "HCHOCH" : "CHOCH", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                  if(m_showGraphics && current_choch_dn_name != "") { ObjectDelete(0, current_choch_dn_name); ObjectDelete(0, current_choch_dn_name + "_lbl"); current_choch_dn_name = ""; }
                  current_choch_up_name = choch_name;
                  current_bos_up_level = maj_prot_high;
                  ClearZoneQueue(SellZonesQueue);

                  double actual_extreme_low = maj_extreme_low; datetime actual_extreme_time = maj_extreme_low_time; int actual_extreme_idx = maj_extreme_low_idx;
                  int prot_idx = maj_prot_high_idx;
                  if (prot_idx != -1 && prot_idx >= i) {
                     int count = prot_idx - i + 1; int lowest_idx = ArrayMinimum(low, i, count);
                     if (lowest_idx != -1) { actual_extreme_low = low[lowest_idx]; actual_extreme_time = time[lowest_idx]; actual_extreme_idx = lowest_idx; }
                  }

                  if(m_showGraphics) { ObjectDelete(0, m_prefix + "KEY_LEVEL"); ObjectDelete(0, m_prefix + "KEY_LEVEL_lbl"); }
                  CreateRayLine(m_prefix + "KEY_LEVEL", actual_extreme_time, actual_extreme_low, c_KeyLevel, (m_isHTF?"HTF ":"LTF ") + "Major Key Level Up", false);

                  MajorEvent[i] = 2;
                  BrokenTime[i] = maj_prot_high_time;
                  OriginIdx[i]  = actual_extreme_idx;

                  last_break_dir = 1; last_break_type = 2;
                  latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = maj_prot_high;

                  int zone_anchor_idx = actual_extreme_idx;
                  if (actual_extreme_idx != -1) {
                     for (int k = i + PeriodsInMajorSwing; k <= actual_extreme_idx; k++) {
                        if (k < rates_total && majorSwingLow[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                     }
                  }
                  if(zone_anchor_idx != -1) {
                     string zone_name = m_prefix + "ZONE_BUY_CHOCH_" + IntegerToString((long)time[i]);
                     double zEntry, zStop;
                     CreateZoneHelper(zone_name, zone_anchor_idx, i, false, maj_prot_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                     PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                  }

                  if (ActiveHigh.time == maj_prot_high_time) ActiveHigh.isActive = false;
                  ClearQueue(BOSDnQueue);
                  major_trend = 1; maj_extreme_high = high[i]; maj_extreme_high_time = time[i]; maj_extreme_high_idx = i;

                  // Reset confirmed extreme + kích hoạt Radar cho uptrend mới
                  maj_confirmed_extreme_low = EMPTY_VALUE;
                  maj_prot_low = actual_extreme_low; maj_prot_low_time = actual_extreme_time; maj_prot_low_idx = actual_extreme_idx;
                  maj_prot_high = EMPTY_VALUE; maj_prot_high_idx = -1;
                  is_maj_prot_low_sweep = true;
                  pending_prot_low_update = true;
                  prot_anchor_time = actual_extreme_time;
                  prot_breakout_idx = i;
                  pending_prot_high_update = false;
               }
               is_major_choch_up = true;
            }

            // =========================================================================
            // 3. MAJOR BOS UP
            // =========================================================================
            if (ActiveHigh.isActive && HAClose[i] > ActiveHigh.price) {
               if (!is_major_choch_up) {
                  current_market_phase = (major_trend == 1) ? "Impulse Up - BoS Up" : "Impulse Down - BoS Up";
                  string bos_name = m_prefix + "BOS_UP_" + IntegerToString((long)ActiveHigh.time);
                  if(ObjectFind(0, bos_name) < 0) {
                     CreateBOSLine(bos_name, ActiveHigh.time, ActiveHigh.price, time[i], c_BOSUp, m_isHTF ? "HBOS" : "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                     PushBOS(BOSUpQueue, bos_name, MaxBOSLines);

                     MajorEvent[i] = 1;
                     OriginIdx[i]  = last_maj_low_idx;

                     last_break_dir = 1; last_break_type = 1;
                     latest_break_up_time = time[i]; latest_break_up_idx = i; latest_break_up_level = ActiveHigh.price;
                     current_bos_up_level = ActiveHigh.price;
                     int origin_idx = last_maj_low_idx;
                     if (origin_idx != -1) {
                        string zone_name = m_prefix + "ZONE_BUY_BOS_" + IntegerToString((long)last_maj_low_time);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, origin_idx, i, false, ActiveHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(BuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
               ActiveHigh.isActive = false;
            }

            // =========================================================================
            // 4. MAJOR BOS DOWN
            // =========================================================================
            if (ActiveLow.isActive && HAClose[i] < ActiveLow.price) {
               if (!is_major_choch_dn) {
                  current_market_phase = (major_trend == -1) ? "Impulse Down - BoS Down" : "Impulse Up - BoS Down";
                  string bos_name = m_prefix + "BOS_DN_" + IntegerToString((long)ActiveLow.time);
                  if(ObjectFind(0, bos_name) < 0) {
                     CreateBOSLine(bos_name, ActiveLow.time, ActiveLow.price, time[i], c_BOSDn, m_isHTF ? "HBOS" : "BOS", STYLE_SOLID, 2, ANCHOR_LOWER, 6);
                     PushBOS(BOSDnQueue, bos_name, MaxBOSLines);

                     MajorEvent[i] = -1;
                     OriginIdx[i]  = last_maj_high_idx;

                     last_break_dir = -1; last_break_type = 1;
                     latest_break_down_time = time[i]; latest_break_down_idx = i; latest_break_down_level = ActiveLow.price;
                     current_bos_dn_level = ActiveLow.price;
                     int origin_idx = last_maj_high_idx;
                     if (origin_idx != -1) {
                        string zone_name = m_prefix + "ZONE_SELL_BOS_" + IntegerToString((long)last_maj_high_time);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, origin_idx, i, true, ActiveLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop);
                        PushZone(SellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
               ActiveLow.isActive = false;
            }

            // =========================================================================
            // 5. MINOR CHOCH DOWN
            // =========================================================================
            if (minor_trend == 1 && min_prot_low != EMPTY_VALUE && HAClose[i] < min_prot_low) {
               if (!is_major_choch_dn) {
                  current_minor_phase = "Impulse Down - ChoCh Down";
                  string choch_name = m_prefix + "MINOR_CHOCH_DN_" + IntegerToString((long)min_prot_low_time);
                  if(ObjectFind(0, choch_name) < 0) {
                     if(m_showMinor) {
                        CreateBOSLine(choch_name, min_prot_low_time, min_prot_low, time[i], c_mBOSDn, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                        if(current_minor_choch_up_name != "") { ObjectDelete(0, current_minor_choch_up_name); ObjectDelete(0, current_minor_choch_up_name + "_lbl"); current_minor_choch_up_name = ""; }
                        current_minor_choch_dn_name = choch_name;
                     }

                     // Tính actual extreme (đỉnh thực tế giữa i và prot_low_idx)
                     double actual_extreme_high = min_extreme_high; datetime actual_extreme_time = min_extreme_high_time; int actual_extreme_idx = min_extreme_high_idx;
                     int prot_idx = min_prot_low_idx;
                     if (prot_idx != -1 && prot_idx >= i) {
                        int count = prot_idx - i + 1; int highest_idx = ArrayMaximum(high, i, count);
                        if (highest_idx != -1) { actual_extreme_high = high[highest_idx]; actual_extreme_time = time[highest_idx]; actual_extreme_idx = highest_idx; }
                     }

                     // Tạo mZone Sell từ Minor CHOCH Down
                     int zone_anchor_idx = actual_extreme_idx;
                     if (actual_extreme_idx != -1) {
                        for (int k = i + PeriodsInMinorSwing; k <= actual_extreme_idx; k++) {
                           if (k < rates_total && minorSwingHigh[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                        }
                     }
                     if (zone_anchor_idx != -1) {
                        string zone_name = m_prefix + "ZONE_MINOR_SELL_CHOCH_" + IntegerToString((long)time[i]);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, zone_anchor_idx, i, true, min_prot_low, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, m_showMinor);
                        PushZone(MinorSellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }

                     if (ActiveMinorLow.time == min_prot_low_time) ActiveMinorLow.isActive = false;
                     ClearQueue(MinorBOSUpQueue); ClearZoneQueue(MinorBuyZonesQueue);
                     minor_trend = -1; min_extreme_low = low[i]; min_extreme_low_time = time[i]; min_extreme_low_idx = i;

                     min_confirmed_extreme_high = EMPTY_VALUE;
                     min_prot_high = actual_extreme_high; min_prot_high_time = actual_extreme_time; min_prot_high_idx = actual_extreme_idx;
                     min_prot_low = EMPTY_VALUE; min_prot_low_idx = -1;
                     is_min_prot_high_sweep = true;
                     min_pending_prot_high_update = true;
                     min_prot_anchor_time = actual_extreme_time;
                     min_prot_breakout_idx = i;
                     min_pending_prot_low_update = false;
                  }
               }
               is_minor_choch_dn = true;
            }
            // =========================================================================
            // 6. MINOR CHOCH UP
            // =========================================================================
            else if (minor_trend == -1 && min_prot_high != EMPTY_VALUE && HAClose[i] > min_prot_high) {
               if (!is_major_choch_up) {
                  current_minor_phase = "Impulse Up - ChoCh Up";
                  string choch_name = m_prefix + "MINOR_CHOCH_UP_" + IntegerToString((long)min_prot_high_time);
                  if(ObjectFind(0, choch_name) < 0) {
                     if(m_showMinor) {
                        CreateBOSLine(choch_name, min_prot_high_time, min_prot_high, time[i], c_mBOSUp, "mCHOCH", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                        if(current_minor_choch_dn_name != "") { ObjectDelete(0, current_minor_choch_dn_name); ObjectDelete(0, current_minor_choch_dn_name + "_lbl"); current_minor_choch_dn_name = ""; }
                        current_minor_choch_up_name = choch_name;
                     }

                     // Tính actual extreme (đáy thực tế giữa i và prot_high_idx)
                     double actual_extreme_low = min_extreme_low; datetime actual_extreme_time = min_extreme_low_time; int actual_extreme_idx = min_extreme_low_idx;
                     int prot_idx = min_prot_high_idx;
                     if (prot_idx != -1 && prot_idx >= i) {
                        int count = prot_idx - i + 1; int lowest_idx = ArrayMinimum(low, i, count);
                        if (lowest_idx != -1) { actual_extreme_low = low[lowest_idx]; actual_extreme_time = time[lowest_idx]; actual_extreme_idx = lowest_idx; }
                     }

                     // Tạo mZone Buy từ Minor CHOCH Up
                     int zone_anchor_idx = actual_extreme_idx;
                     if (actual_extreme_idx != -1) {
                        for (int k = i + PeriodsInMinorSwing; k <= actual_extreme_idx; k++) {
                           if (k < rates_total && minorSwingLow[k] != EMPTY_VALUE) { zone_anchor_idx = k; break; }
                        }
                     }
                     if (zone_anchor_idx != -1) {
                        string zone_name = m_prefix + "ZONE_MINOR_BUY_CHOCH_" + IntegerToString((long)time[i]);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, zone_anchor_idx, i, false, min_prot_high, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, m_showMinor);
                        PushZone(MinorBuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }

                     if (ActiveMinorHigh.time == min_prot_high_time) ActiveMinorHigh.isActive = false;
                     ClearQueue(MinorBOSDnQueue); ClearZoneQueue(MinorSellZonesQueue);
                     minor_trend = 1; min_extreme_high = high[i]; min_extreme_high_time = time[i]; min_extreme_high_idx = i;

                     min_confirmed_extreme_low = EMPTY_VALUE;
                     min_prot_low = actual_extreme_low; min_prot_low_time = actual_extreme_time; min_prot_low_idx = actual_extreme_idx;
                     min_prot_high = EMPTY_VALUE; min_prot_high_idx = -1;
                     is_min_prot_low_sweep = true;
                     min_pending_prot_low_update = true;
                     min_prot_anchor_time = actual_extreme_time;
                     min_prot_breakout_idx = i;
                     min_pending_prot_high_update = false;
                  }
               }
               is_minor_choch_up = true;
            }

            // =========================================================================
            // 7. MINOR BOS UP
            // =========================================================================
            if (ActiveMinorHigh.isActive && HAClose[i] > ActiveMinorHigh.price) {
               if (!is_minor_choch_up && !is_major_choch_up) {
                  current_minor_phase = (minor_trend == 1) ? "Impulse Up - BoS Up" : "Impulse Down - BoS Up";
                  string bos_name = m_prefix + "MINOR_BOS_UP_" + IntegerToString((long)ActiveMinorHigh.time);
                  if(ObjectFind(0, bos_name) < 0) {
                     if(m_showMinor) {
                        CreateBOSLine(bos_name, ActiveMinorHigh.time, ActiveMinorHigh.price, time[i], c_mBOSUp, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                        PushBOS(MinorBOSUpQueue, bos_name, MaxMinorBOSLines);
                     }
                     // Tạo mZone Buy từ Minor BOS Up
                     int origin_idx = last_min_low_idx;
                     if (origin_idx != -1) {
                        string zone_name = m_prefix + "ZONE_MINOR_BUY_BOS_" + IntegerToString((long)last_min_low_time);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, origin_idx, i, false, ActiveMinorHigh.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, m_showMinor);
                        PushZone(MinorBuyZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
               ActiveMinorHigh.isActive = false;
            }

            // =========================================================================
            // 8. MINOR BOS DOWN
            // =========================================================================
            if (ActiveMinorLow.isActive && HAClose[i] < ActiveMinorLow.price) {
               if (!is_minor_choch_dn && !is_major_choch_dn) {
                  current_minor_phase = (minor_trend == -1) ? "Impulse Down - BoS Down" : "Impulse Up - BoS Down";
                  string bos_name = m_prefix + "MINOR_BOS_DN_" + IntegerToString((long)ActiveMinorLow.time);
                  if(ObjectFind(0, bos_name) < 0) {
                     if(m_showMinor) {
                        CreateBOSLine(bos_name, ActiveMinorLow.time, ActiveMinorLow.price, time[i], c_mBOSDn, "mBOS", STYLE_DOT, 1, ANCHOR_UPPER, 6);
                        PushBOS(MinorBOSDnQueue, bos_name, MaxMinorBOSLines);
                     }
                     // Tạo mZone Sell từ Minor BOS Down
                     int origin_idx = last_min_high_idx;
                     if (origin_idx != -1) {
                        string zone_name = m_prefix + "ZONE_MINOR_SELL_BOS_" + IntegerToString((long)last_min_high_time);
                        double zEntry, zStop;
                        CreateZoneHelper(zone_name, origin_idx, i, true, ActiveMinorLow.price, time, high, low, HAHigh, HALow, HAColor, rates_total, zEntry, zStop, m_showMinor);
                        PushZone(MinorSellZonesQueue, zone_name, zEntry, zStop, MaxZones);
                     }
                  }
               }
               ActiveMinorLow.isActive = false;
            }
         }

         if (i == 0) {
            if (major_trend == -1 && maj_prot_high != EMPTY_VALUE) { g_high_lvl = maj_prot_high; g_high_time = maj_prot_high_time; g_high_text = (m_isHTF?"HTF ":"LTF ") + "Protected High"; }
            else if (ActiveHigh.isActive) { g_high_lvl = ActiveHigh.price; g_high_time = ActiveHigh.time; g_high_text = (m_isHTF?"HTF ":"LTF ") + "Active High"; }
            else { g_high_lvl = EMPTY_VALUE; }

            if (major_trend == 1 && maj_prot_low != EMPTY_VALUE) { g_low_lvl = maj_prot_low; g_low_time = maj_prot_low_time; g_low_text = (m_isHTF?"HTF ":"LTF ") + "Protected Low"; }
            else if (ActiveLow.isActive) { g_low_lvl = ActiveLow.price; g_low_time = ActiveLow.time; g_low_text = (m_isHTF?"HTF ":"LTF ") + "Active Low"; }
            else { g_low_lvl = EMPTY_VALUE; }

            CreateTrackingRayWithLabel(m_prefix + "TRACK_HIGH", g_high_time, g_high_lvl, c_KeyLevel, g_high_text, false, time[0]);
            CreateTrackingRayWithLabel(m_prefix + "TRACK_LOW",  g_low_time,  g_low_lvl,  c_KeyLevel, g_low_text,  true,  time[0]);
         }
      }

      current_major_trend = major_trend;
      current_minor_trend = minor_trend;
      current_maj_prot_high = maj_prot_high; current_maj_prot_low  = maj_prot_low;
      current_min_prot_high = min_prot_high; current_min_prot_low  = min_prot_low;
      current_maj_extreme_high = maj_extreme_high; current_maj_extreme_low = maj_extreme_low;
      current_maj_active_high = ActiveHigh.isActive ? ActiveHigh.price : 0;
      current_maj_active_low  = ActiveLow.isActive  ? ActiveLow.price  : 0;
      current_maj_confirmed_extreme_high = maj_confirmed_extreme_high;
      current_maj_confirmed_extreme_low  = maj_confirmed_extreme_low;

      if(ArraySize(BuyZonesQueue) > 0)       { current_buy_zone_entry        = BuyZonesQueue[0].entryPrice;       current_buy_zone_sl        = BuyZonesQueue[0].stopPrice;       } else { current_buy_zone_entry        = 0; current_buy_zone_sl        = 0; }
      if(ArraySize(SellZonesQueue) > 0)      { current_sell_zone_entry       = SellZonesQueue[0].entryPrice;      current_sell_zone_sl       = SellZonesQueue[0].stopPrice;      } else { current_sell_zone_entry       = 0; current_sell_zone_sl       = 0; }
      if(ArraySize(MinorBuyZonesQueue) > 0)  { current_minor_buy_zone_entry  = MinorBuyZonesQueue[0].entryPrice;  current_minor_buy_zone_sl  = MinorBuyZonesQueue[0].stopPrice;  } else { current_minor_buy_zone_entry  = 0; current_minor_buy_zone_sl  = 0; }
      if(ArraySize(MinorSellZonesQueue) > 0) { current_minor_sell_zone_entry = MinorSellZonesQueue[0].entryPrice; current_minor_sell_zone_sl = MinorSellZonesQueue[0].stopPrice; } else { current_minor_sell_zone_entry = 0; current_minor_sell_zone_sl = 0; }
   }

   void HandleChartEvent() {
      if(!m_showGraphics) return;
      datetime t[]; if (CopyTime(_Symbol, _Period, 0, 1, t) > 0) {
         CreateTrackingRayWithLabel(m_prefix + "TRACK_HIGH", g_high_time, g_high_lvl, c_KeyLevel, g_high_text, false, t[0]);
         CreateTrackingRayWithLabel(m_prefix + "TRACK_LOW",  g_low_time,  g_low_lvl,  c_KeyLevel, g_low_text,  true,  t[0]);
         ChartRedraw();
      }
   }

private:
   datetime GetRightEdgeTime(datetime current_time) {
      int width = (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS);
      int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
      int future_offset = width - first - 2; if (future_offset < 1) future_offset = 1;
      return current_time + future_offset * PeriodSeconds();
   }

   void CreateTrackingRayWithLabel(string name, datetime t1, double p1, color clr, string text, bool isDown, datetime current_time) {
      if(!m_showGraphics) return;
      if (p1 == EMPTY_VALUE || t1 == 0) { ObjectDelete(0, name + "_ray"); ObjectDelete(0, name + "_lbl"); return; }
      string ray_name = name + "_ray";
      if(ObjectFind(0, ray_name) < 0) {
         ObjectCreate(0, ray_name, OBJ_TREND, 0, t1, p1, current_time + PeriodSeconds() * 10, p1);
         ObjectSetInteger(0, ray_name, OBJPROP_COLOR, clr); ObjectSetInteger(0, ray_name, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, ray_name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, ray_name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0, ray_name, OBJPROP_BACK, false);
      } else {
         ObjectSetInteger(0, ray_name, OBJPROP_TIME, 0, t1); ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 0, p1);
         ObjectSetInteger(0, ray_name, OBJPROP_TIME, 1, current_time + PeriodSeconds() * 10); ObjectSetDouble(0, ray_name, OBJPROP_PRICE, 1, p1);
      }
      string lbl_name = name + "_lbl"; datetime label_time = GetRightEdgeTime(current_time);
      if(ObjectFind(0, lbl_name) < 0) {
         ObjectCreate(0, lbl_name, OBJ_TEXT, 0, label_time, p1); ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lbl_name, OBJPROP_BACK, false); ObjectSetInteger(0, lbl_name, OBJPROP_SELECTABLE, false);
      } else {
         ObjectSetInteger(0, lbl_name, OBJPROP_TIME, 0, label_time); ObjectSetDouble(0, lbl_name, OBJPROP_PRICE, 0, p1);
      }
      ObjectSetString(0, lbl_name, OBJPROP_TEXT, text + "  ");
      ObjectSetInteger(0, lbl_name, OBJPROP_ANCHOR, isDown ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
   }

   void CreateBOSLine(string name, datetime t1, double p1, datetime t2, color clr, string text, ENUM_LINE_STYLE style, int width, ENUM_ANCHOR_POINT anchor, int fontSize) {
      if(!m_showGraphics) return;
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p1);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, style);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, width); ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); ObjectSetInteger(0, name, OBJPROP_BACK, false);
         datetime t_mid = t1 + (t2 - t1) / 2; string lbl = name + "_lbl";
         ObjectCreate(0, lbl, OBJ_TEXT, 0, t_mid, p1); ObjectSetString(0, lbl, OBJPROP_TEXT, text);
         ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr); ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, anchor);
         ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, fontSize); ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
      }
   }

   void CreateRayLine(string name, datetime t1, double p1, color clr, string text, bool isDown) {
      if(!m_showGraphics) return;
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t1 + PeriodSeconds()*100, p1);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2); ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0, name, OBJPROP_BACK, false);
         string lbl = name + "_lbl";
         ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, p1); ObjectSetString(0, lbl, OBJPROP_TEXT, " " + text);
         ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr); ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isDown ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
      } else {
         ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1); ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
         ObjectSetInteger(0, name+"_lbl", OBJPROP_TIME, 0, t1); ObjectSetDouble(0, name+"_lbl", OBJPROP_PRICE, 0, p1);
         ObjectSetString(0, name+"_lbl", OBJPROP_TEXT, " " + text);
      }
   }

   void PushBOS(string &queue[], string name, int max_count) {
      for(int i=0; i<ArraySize(queue); i++) if(queue[i] == name) return;
      int size = ArraySize(queue); ArrayResize(queue, size + 1); queue[size] = name;
      if(ArraySize(queue) > max_count) {
         if(m_showGraphics) { ObjectDelete(0, queue[0]); ObjectDelete(0, queue[0] + "_lbl"); }
         for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1];
         ArrayResize(queue, ArraySize(queue) - 1);
      }
   }

   void ClearQueue(string &queue[]) {
      for(int i=0; i<ArraySize(queue); i++) { if(m_showGraphics) { ObjectDelete(0, queue[i]); ObjectDelete(0, queue[i] + "_lbl"); } }
      ArrayResize(queue, 0);
   }

   void PushZone(TZone &queue[], string name, double entry, double stop, int max_count) {
      for(int i=0; i<ArraySize(queue); i++) { if(queue[i].name == name) { queue[i].entryPrice = entry; queue[i].stopPrice = stop; return; } }
      int size = ArraySize(queue); ArrayResize(queue, size + 1);
      queue[size].name = name; queue[size].entryPrice = entry; queue[size].stopPrice = stop;
      if(ArraySize(queue) > max_count) {
         if(m_showGraphics) ObjectDelete(0, queue[0].name);
         for(int i = 0; i < ArraySize(queue) - 1; i++) queue[i] = queue[i+1];
         ArrayResize(queue, ArraySize(queue) - 1);
      }
   }

   void ClearZoneQueue(TZone &queue[]) {
      for(int i=0; i<ArraySize(queue); i++) { if(m_showGraphics) ObjectDelete(0, queue[i].name); }
      ArrayResize(queue, 0);
   }

   // drawZone = false: chỉ tính toán entry/stop, không vẽ đồ họa (dùng cho mZone khi m_showMinor = false)
   void CreateZoneHelper(string name, int swing_idx, int bos_idx, bool isSellZone, double broken_level,
                         const datetime &t[], const double &h[], const double &l[],
                         const double &ha_h[], const double &ha_l[], const double &ha_color[],
                         int total, double &out_entry, double &out_stop, bool drawZone = true) {
      int ext_idx = swing_idx;
      if (bos_idx >= 0 && swing_idx >= bos_idx) {
         int count = swing_idx - bos_idx + 1;
         if(isSellZone) ext_idx = ArrayMaximum(h, bos_idx, count);
         else           ext_idx = ArrayMinimum(l, bos_idx, count);
      }

      double actual_broken_level = broken_level;
      if ((actual_broken_level <= 0 || actual_broken_level == EMPTY_VALUE) && bos_idx >= 0 && swing_idx > bos_idx) {
         int check_count = swing_idx - bos_idx;
         if (isSellZone) { int brk_idx = ArrayMinimum(l, bos_idx + 1, check_count); if (brk_idx != -1) actual_broken_level = l[brk_idx]; }
         else            { int brk_idx = ArrayMaximum(h, bos_idx + 1, check_count); if (brk_idx != -1) actual_broken_level = h[brk_idx]; }
      }

      int targetColor = isSellZone ? 0 : 1;
      int k = ext_idx;
      double zHigh = ha_h[ext_idx];
      double zLow  = ha_l[ext_idx];
      while(k < total && ha_color[k] != targetColor && k <= ext_idx + 10) { k++; }
      if(k <= ext_idx + 10 && k < total) {
         if(isSellZone) {
            zLow = ha_l[k];
            while(k < total && ha_color[k] == targetColor) { zLow = MathMin(zLow, ha_l[k]); k++; }
            zHigh = MathMax(zHigh, ha_h[ext_idx]);
         } else {
            zHigh = ha_h[k];
            while(k < total && ha_color[k] == targetColor) { zHigh = MathMax(zHigh, ha_h[k]); k++; }
            zLow = MathMin(zLow, ha_l[ext_idx]);
         }
      }

      if (actual_broken_level > 0 && actual_broken_level != EMPTY_VALUE) {
         if (isSellZone  && zLow  <= actual_broken_level + _Point) { zHigh = ha_h[ext_idx]; zLow = ha_l[ext_idx]; }
         else if (!isSellZone && zHigh >= actual_broken_level - _Point) { zHigh = ha_h[ext_idx]; zLow = ha_l[ext_idx]; }
      }

      out_stop  = isSellZone ? zHigh : zLow;
      out_entry = isSellZone ? zLow  : zHigh;

      if(!drawZone || !m_showGraphics || !m_showZone) return;

      datetime tStart = t[ext_idx];
      datetime tEnd   = t[0] + PeriodSeconds() * 1000;

      if(ObjectFind(0, name) >= 0) {
         double old_zHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         double old_zLow  = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
         if (MathAbs(old_zHigh - zHigh) < _Point && MathAbs(old_zLow - zLow) < _Point) return;
         ObjectDelete(0, name);
      }

      ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, zHigh, tEnd, zLow);
      ObjectSetInteger(0, name, OBJPROP_COLOR, isSellZone ? c_SellZone : c_BuyZone);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, m_isHTF);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
};
//+------------------------------------------------------------------+