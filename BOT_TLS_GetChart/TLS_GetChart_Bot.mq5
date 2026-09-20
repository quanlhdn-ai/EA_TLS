//+------------------------------------------------------------------+
//|                                          TLS_GetChart_Bot.mq5    |
//| Bot giao dịch dựng từ tin "Đặt LIMIT chờ trong vùng" của          |
//| BOT_ChartSnapshot (Combo_Structure_ChartSnapshot_Bot.mq5).        |
//|                                                                  |
//| Khác bot gốc ở chỗ: bot gốc chỉ BÁO, bot này VÀO LỆNH và lọc      |
//| thêm 2 tầng theo triết lý T-L-S:                                  |
//|   T (Trend)  — xu hướng Major của khung Trend (mặc định H1),      |
//|                đọc bằng CSMC_Engine y như BOT_TLS.                |
//|   L (Level)  — Zone Buy/Sell MỚI hình thành trên khung Zone       |
//|                (mặc định M1). Bot TỰ TÍNH Zone bằng CSMC_Engine,  |
//|                KHÔNG đọc tin Telegram của bot GetChart và không   |
//|                cần file TLS_SMC_Indicator.ex5 -> backtest được.   |
//|   S (Signal) — nến xác nhận tại từng mốc vào lệnh: không cần nến  |
//|                / Pinbar / Engulfing / Pinbar hoặc Engulfing.      |
//|                Cách đo nến lấy theo BOT_CRT (râu >= 1.5 x thân).  |
//|                                                                  |
//| Mỗi Zone = 1 setup = tối đa 2 lệnh, đặt tại 2 mốc tính theo %     |
//| độ rộng Zone (mặc định 0% = mép Zone và 50% = giữa Zone). Hai mốc |
//| xét tín hiệu ĐỘC LẬP nhau, mỗi mốc bắn tối đa 1 lần cho mỗi Zone. |
//| SL dùng chung, tính y hệt công thức in trong tin của bot GetChart.|
//|                                                                  |
//| Quản lý vốn, lá chắn tài khoản, Telegram, crash recovery, hàng đợi|
//| đóng lệnh retry: port từ BOT_TLS/TLS_SMC_CSV_Bot.mq5.             |
//+------------------------------------------------------------------+
//| CHANGELOG                                                         |
//| v1.0 (2026-09-06) — bản đầu tiên, dựng theo bản chốt thiết kế 8   |
//|                     phần ghi trong Nhatky_BOT_TLS_GetChart.txt.   |
//+------------------------------------------------------------------+
#property copyright "Jay Davis & anhtuan02t1"
#property version   "1.00"

// CÁCH CÀI ĐẶT TRÊN MÁY MỚI — chỉ cần copy ĐÚNG 1 THƯ MỤC:
//   1. Copy nguyên thư mục BOT_TLS_GetChart vào <MT5 data folder>\MQL5\Experts\
//      (mở data folder bằng menu File > Open Data Folder trong MT5).
//   2. Trong MetaEditor bấm Compile file TLS_GetChart_Bot.mq5 (hoặc F7).
//   3. Gắn EA lên chart XAUUSDm bất kỳ khung nào, nạp preset TLS_GetChart_Bot.set.
//   4. Bật WebRequest cho https://api.telegram.org trong Tools > Options > Expert Advisors.
// KHÔNG cần chép gì vào MQL5\Include: 2 file dùng chung nằm sẵn trong thư mục này và
// được include bằng DẤU NGOẶC KÉP (đường dẫn tương đối) — khác 3 bot còn lại trong repo
// vốn include bằng ngoặc nhọn và lấy từ MQL5\Include.
#include <Trade\Trade.mqh>
#include "CSMC_Engine.mqh"
#include "Telegram_Radar.mqh"

CTrade trade;
CTelegramRadar Radar;

// ==================================================================
// ENUM
// ==================================================================
// Khai báo TRƯỚC nhóm input vì MQL5 đòi kiểu enum phải có sẵn khi dùng làm input.
enum ENUM_SIGNAL_MODE {
    SIGNAL_KHONG_CAN_NEN         = 0,  // Không cần nến xác nhận
    SIGNAL_PINBAR                = 1,  // Chỉ Pinbar
    SIGNAL_ENGULFING             = 2,  // Chỉ Engulfing
    SIGNAL_PINBAR_HOAC_ENGULFING = 3   // Pinbar hoặc Engulfing
};

// Bot tự vẽ được Zone / BOS / CHOCH / Key Level / Protected-Active High-Low y như
// TLS_SMC_Indicator, không cần gắn thêm chỉ báo lên chart: CSMC_Engine đã có sẵn phần vẽ,
// chỉ cần bật cờ showGraphics và truyền màu vào Init().
// LƯU Ý: nếu khung Trend TRÙNG khung Zone (mặc định Trend = CURRENT, Zone = M1 trên chart
// M1 là trùng) thì chọn VE_CA_HAI sẽ vẽ đè 2 bộ đối tượng giống hệt nhau lên nhau — chỉ
// dùng VE_CA_HAI khi 2 khung thật sự khác nhau.
enum ENUM_DRAW_MODE {
    VE_KHONG      = 0,  // Không vẽ gì
    VE_KHUNG_ZONE = 1,  // Vẽ cấu trúc khung Zone
    VE_KHUNG_TREND= 2,  // Vẽ cấu trúc khung Trend
    VE_CA_HAI     = 3   // Vẽ cả hai khung
};

// ==================================================================
// INPUTS
// ==================================================================
input group "--- Dinh danh EA ---"
input long   Inp_BaseMagicNumber      = 2027000;  // Magic gốc (mốc 1 = +1, mốc 2 = +2)

input group "--- Telegram ---"
// Gắn cứng theo yêu cầu người dùng ngày 06/09/2026 để copy thư mục sang máy khác là chạy
// được ngay, không phải điền lại.
// LƯU Ý 1: token này ĐANG DÙNG CHUNG với BOT_TLS (xem exness_trieudo.set). Hai EA cùng
//   poll getUpdates trên một token sẽ ăn tranh update của nhau (getUpdates có offset, ai
//   đọc trước thì người kia mất tin) -> lệnh /status, /stop có thể rơi nhầm bot. Khi nào
//   có bot riêng từ BotFather thì đổi đúng 1 dòng dưới đây.
// LƯU Ý 2: chat_id lấy từ web.telegram.org/k/#-5442190551 — đây là group THƯỜNG. Nếu
//   group được nâng cấp lên supergroup thì ID đổi sang dạng -100xxxxxxxxxx và bot sẽ câm
//   lặng (đúng sự cố đã ghi trong Nhatky_BOT_ChartSnapshot).
input string Inp_BotToken             = "8365052004:AAEEqNwnzI_OIpjlzrXS_PjriACSdTZbnQs"; // Token bot Telegram
input string Inp_ChatID               = "-5442190551";   // Chat/Group ID nhận tin
input bool   Inp_SendScreenshot       = true;     // Gửi kèm ảnh chart khi báo tin

input group "--- T: Xu huong ---"
// Mặc định PERIOD_CURRENT = dùng luôn khung của chart đang gắn EA (yêu cầu 06/09/2026).
input ENUM_TIMEFRAMES Inp_Trend_Timeframe = PERIOD_CURRENT; // Khung xác định xu hướng
input bool   Inp_Enable_Trend_Filter  = true;     // Bật lọc xu hướng (tắt = vào cả 2 chiều)
input int    Inp_Trend_MajorSwing     = 9;        // Số nến Swing Major khung Trend

input group "--- L: Zone ---"
input ENUM_TIMEFRAMES Inp_Zone_Timeframe = PERIOD_M1;  // Khung sinh Zone vào lệnh
input int    Inp_Zone_MajorSwing      = 9;        // Số nến Swing Major khung Zone
input double Inp_Max_Zone_Width_Pips  = 300.0;    // Zone rộng hơn mức này (pips) thì bỏ qua
input double Inp_Min_Zone_Width_Pips  = 0.0;      // Zone hẹp hơn mức này (pips) thì bỏ (0 = tắt)

input group "--- Moc vao lenh ---"
// Vị trí tính theo % độ rộng Zone, đi từ mép Entry (mép gần giá) về phía mép SL:
// 0 = đúng mép Zone, 50 = giữa Zone, 100 = sát mép SL.
input bool   Inp_Use_Level1           = true;     // Bật lệnh 1
input double Inp_Level1_Pct           = 0.0;      // Vị trí lệnh 1 (% độ rộng Zone)
input double Inp_TP1_Pips             = 100.0;    // TP lệnh 1 (pips — 100 pips = 10 giá vàng)
input bool   Inp_Use_Level2           = true;     // Bật lệnh 2
input double Inp_Level2_Pct           = 50.0;     // Vị trí lệnh 2 (% độ rộng Zone)
input double Inp_TP2_Pips             = 100.0;    // TP lệnh 2 (pips)

input group "--- S: Nen xac nhan ---"
input ENUM_SIGNAL_MODE Inp_Signal_Mode = SIGNAL_KHONG_CAN_NEN; // Kiểu tín hiệu vào lệnh
input double Inp_MaxDistFromLevel_Pips = 0.0;     // Giá vào cách mốc tối đa (pips, 0 = không giới hạn)
// Engulfing chặt hay lỏng. false = chỉ cần nến sau trùm biên độ nến trước (bản gốc, chốt ở
// phần 4B.3). true = đòi thêm nến trước phải NGƯỢC chiều lệnh, tức đúng định nghĩa nến đảo
// chiều cổ điển. Để dạng input để chạy đối chứng được, không phải compile lại.
// Mặc định TRUE theo kết quả backtest 8 tháng XAUUSD (Zone M1, TP100): luật lỏng
// -10.5% / 421 lệnh, luật chặt -4.0% / 340 lệnh. Siết lại loại đúng 81 lệnh kém —
// bỏ đi mà kết quả tốt lên 6.5 điểm.
input bool   Inp_Engulf_PrevOpposite  = true;     // Engulfing: đòi nến trước ngược chiều lệnh

input group "--- SL ---"
// Công thức y hệt tin của bot GetChart: mép xa -> đệm theo thang 30-35-40-45-50 pips
// -> làm tròn số nguyên -> nới thêm Inp_SL_Extra_Pips.
input double Inp_SL_Extra_Pips        = 20.0;     // Nới thêm SL sau khi làm tròn (pips)
input bool   Inp_SL_RoundInteger      = true;     // Làm tròn SL về số nguyên trước khi nới

input group "--- Quan ly von ---"
input bool   UseRiskPerTrade          = true;     // true = lot theo % rủi ro, false = lot cố định
input double RiskPercent              = 0.5;      // % balance rủi ro cho MỖI lệnh
input double FixedLotSize             = 0.05;     // Lot cố định khi tắt UseRiskPerTrade
input int    Inp_Max_Risk_Trades      = 4;        // Số vị thế chưa hoà vốn tối đa (2 lệnh/setup)
input double Inp_Min_Entry_Dist_Pips  = 30.0;     // Cách lệnh của setup KHÁC tối thiểu (pips)
input int    Inp_Slippage_Points      = 30;       // Trượt giá tối đa cho phép (points)

input group "--- La chan tai khoan ---"
input bool   Inp_UseMarginLimit       = true;     // Bật trần margin khi tính lot
input double Inp_MaxMarginPercent     = 38.0;     // Trần margin (% balance)
input double Inp_DailyDrawdownLimit   = 3.0;      // Ngưỡng lỗ ngày (% balance đầu phiên), 0 = tắt
input double Inp_DailyProfitLimit     = 0.0;      // Ngưỡng lãi ngày (% balance đầu phiên), 0 = tắt
input double Inp_AutoPassTarget       = 0.0;      // Equity mục tiêu (USD) thì đóng hết, 0 = tắt
input string Inp_NewsTimes            = "15:30, 21:00"; // Giờ tin cần tránh (giờ server)
input int    Inp_NewsBufferMinutes    = 2;        // Số phút chặn trước/sau mỗi giờ tin
input double Inp_Pool_SL_Percent      = 0.0;      // Đóng cả tập lệnh cùng chiều khi lỗ % này (0 = tắt)

input group "--- FlexTP ---"
input bool   Inp_FlexTP_Enabled       = false;    // Bật chốt lãi linh hoạt cả tập lệnh
input double Inp_FlexTP_Percent       = 1.0;      // Ngưỡng lãi (% balance) để FlexTP đóng
input double Inp_FlexTP_Pips          = 0.0;      // Ngưỡng lãi (tổng pips) để FlexTP đóng (0 = tắt)

input group "--- Hien thi ---"
input ENUM_DRAW_MODE Inp_Draw_Mode    = VE_KHUNG_ZONE; // Vẽ cấu trúc SMC lên chart (thay cho chỉ báo)
input bool   Inp_Debug                = false;    // Ghi log chi tiết vào tab Experts

// ==================================================================
// HẰNG SỐ (tham số hình thức + hằng số công thức, không đưa vào Inputs)
// ==================================================================
// Thang đệm SL của bot GetChart. Nhatky_BOT_ChartSnapshot đã ghi: với Zone dưới 150 pips
// thì "1 phần" luôn <= 30 nên thang luôn trả về mốc đáy 30 — giữ nguyên cả thang để công
// thức khớp 100% với con số SL đã công bố trên kênh.
const double SL_LADDER[5] = {30, 35, 40, 45, 50};

// Tỷ lệ râu/thân tối thiểu của pinbar — để const đúng theo quy ước BOT_CRT.
const double WICK_BODY_RATIO = 1.5;

// Tham số cấu trúc của CSMC_Engine, giống BOT_TLS.
const int    MAX_ZONES = 1;
const int    MAX_BOS   = 5;
const int    MAX_MBOS  = 3;

// Bot chỉ dùng cấu trúc MAJOR (xác định xu hướng và sinh Zone đều theo Major) nên số nến
// Swing Minor không còn là tham số vận hành -> để const, gỡ khỏi bảng Inputs cho gọn.
// CSMC_Engine vẫn tính Minor bên trong vì đó là code có sẵn của thư viện dùng chung —
// KHÔNG sửa engine để cắt phần đó (sửa là phải mirror sang cả 4 bot).
const int    MINOR_SWING = 5;

// Màu vẽ 2 mốc vào lệnh + SL của setup đang chạy (chỉ để nhìn khi backtest).
const color  CLR_LEVEL_BUY  = clrDodgerBlue;
const color  CLR_LEVEL_SELL = clrOrangeRed;
const color  CLR_SL_LINE    = clrGray;

// Màu cho phần cấu trúc SMC do engine vẽ — lấy đúng bộ màu HTF của BOT_TLS để 2 bot nhìn
// giống nhau. Để const theo quy ước repo (bảng Inputs chỉ chứa tham số vận hành).
const color  CLR_BUY_ZONE  = C'235,250,240';
const color  CLR_SELL_ZONE = C'255,235,235';
const color  CLR_KEY_LEVEL = clrOrange;
const color  CLR_BOS_UP    = clrDodgerBlue;
const color  CLR_BOS_DN    = clrRed;

const string PFX = "[GCB]";   // tiền tố log theo quy ước [BOT][module]

// ==================================================================
// STRUCT
// ==================================================================
// Trạng thái 1 mốc vào lệnh trong 1 setup.
//   armed   = giá đã chạm mốc ít nhất 1 lần -> từ đây trở đi mọi nến xác nhận đều được
//             tính, không giới hạn số nến chờ (khác BOT_CRT chỉ xét đúng 1 cây kế tiếp).
//   done    = mốc đã bắn lệnh và lệnh đó đã thành vị thế -> không bắn lại cho Zone này.
//   ticket  = vé lệnh chờ đang treo (0 = không có). Lệnh chờ bị huỷ ngoài ý muốn (giờ tin,
//             /stop, xoá tay) sẽ được phát hiện qua vé này và mốc được mở lại.
struct SLevelState {
    bool   enabled;
    bool   armed;
    bool   done;
    double price;
    double tp_pips;
    ulong  ticket;
};

// 1 setup = 1 Zone. dir: 1 = Buy, -1 = Sell.
struct SSetup {
    bool   active;
    int    dir;
    int    group_id;
    double zone_entry;   // mép gần giá (gốc từ engine, chưa làm tròn)
    double zone_sl;      // mép xa
    double sl_price;     // SL đã đệm, dùng chung cho cả 2 lệnh
    datetime born;
    SLevelState lvl[2];
};

// Sổ theo dõi từng vị thế: phục vụ BE theo nhóm + báo RR khi đóng lệnh.
struct STradeRec {
    ulong  ticket;
    int    group_id;
    int    level;
    int    dir;
    double open_price;
    double init_sl;
    double risk_money;
    double realized_pnl;
    bool   be_done;
};

// Hàng đợi đóng lệnh retry (port từ BOT_TLS).
struct SCloseRetry {
    ulong  ticket;
    int    retries;
    ulong  next_ms;
    string source;
};

// ==================================================================
// BIẾN TOÀN CỤC
// ==================================================================
CSMC_Engine SMC_TREND;
CSMC_Engine SMC_ZONE;

SSetup    g_buy_setup;
SSetup    g_sell_setup;
int       g_group_seq = 0;

// Mốc so sánh để phát hiện Zone MỚI. seen = false ở lần đọc đầu tiên sau khi EA khởi động:
// lần đó chỉ ghi nhận Zone đang có làm mốc, KHÔNG vào lệnh (không biết Zone đó đã hình
// thành từ bao giờ) — y hệt cơ chế của CheckZoneFormed() trong bot GetChart.
bool      g_zone_seen        = false;
double    g_last_buy_entry   = 0, g_last_buy_sl  = 0;
double    g_last_sell_entry  = 0, g_last_sell_sl = 0;

STradeRec   g_trades[];
SCloseRetry g_retry_queue[];
int         g_retry_count = 0;

// Lá chắn tài khoản
bool      g_trading_stopped_today = false;
bool      g_account_passed        = false;
datetime  g_last_day_checked      = 0;
double    g_sod_balance           = 0;
string    g_shield_stop_reason    = "";

// Telegram + điều khiển
bool      g_cmd_paused        = false;
long      g_tg_last_update_id = 0;
ulong     g_tg_last_poll_ms   = 0;

// Dashboard
string    g_action_text = "Khởi tạo hệ thống...";
string    g_filter_text = "";

// Mốc bar đã xử lý của từng khung
datetime  g_last_trend_bar = 0;
datetime  g_last_zone_bar  = 0;

// Thị trường đóng cửa: sau khi sàn trả retcode 10018, ngưng gửi lệnh tới mốc thời gian này.
// Dùng TimeCurrent() (giờ server/giờ test) chứ KHÔNG dùng GetTickCount64() — trong Strategy
// Tester đồng hồ máy chạy nhanh gấp bội thời gian test nên cooldown theo ms sẽ vô nghĩa.
datetime  g_market_closed_until = 0;

// Lưới SL ảo: cooldown + nhịp ghi log cho từng vé, tránh mỗi tick lại gửi một lệnh đóng.
ulong     g_vsl_ticket[];
datetime  g_vsl_next_try[];
datetime  g_vsl_last_log[];

// ==================================================================
// HELPER CHUNG
// ==================================================================
// Quy ước pip giống hệt GetPipSize() của BOT_TLS và bot GetChart:
// vàng = 0.1, JPY = 0.01, 5/4 digit = 0.0001, 3/2 digit = 0.01, còn lại Point*10.
double GetPipSize(string sym) {
    string s = sym; StringToUpper(s);
    if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
    if(StringFind(s, "JPY") >= 0) return 0.01;
    long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS);
    if(digits == 5 || digits == 4) return 0.0001;
    if(digits == 3 || digits == 2) return 0.01;
    return SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0;
}

// Magic của bot này: base+1 (mốc 1) và base+2 (mốc 2). Mọi vòng lặp lệnh/vị thế đều lọc
// qua hàm này để không đụng lệnh tay hay lệnh của bot khác.
bool IsMyMagic(long magic) {
    return (magic >= Inp_BaseMagicNumber && magic <= Inp_BaseMagicNumber + 2);
}

long MagicOfLevel(int level) {
    return Inp_BaseMagicNumber + level + 1;   // level 0 -> +1, level 1 -> +2
}

// Nến mới của MỘT khung bất kỳ (không phụ thuộc khung của chart đang gắn EA).
bool IsNewBarTF(ENUM_TIMEFRAMES tf, datetime &last_bar) {
    datetime t = iTime(_Symbol, tf, 0);
    if(t == 0) return false;
    if(last_bar == 0) { last_bar = t; return true; }
    if(t != last_bar) { last_bar = t; return true; }
    return false;
}

string TFName(ENUM_TIMEFRAMES tf) {
    string s = EnumToString(tf);
    StringReplace(s, "PERIOD_", "");
    return s;
}

void DebugLog(string module, string msg) {
    if(Inp_Debug) Print(PFX, "[", module, "] ", msg);
}

// Bọc 2 hàm gửi tin của Telegram_Radar: trong Strategy Tester, WebRequest luôn bị chặn
// (TELEGRAM POST ERROR: Code -1 | Error: 4014) nên mỗi lần gửi vừa tốn thời gian vừa đổ
// rác vào log — với Zone khung M1 thì số tin rất nhiều, backtest sẽ chậm hẳn. Chạy thật
// thì 2 hàm này gọi thẳng Radar, không đổi hành vi.
void Notify(string msg) {
    if(MQLInfoInteger(MQL_TESTER)) return;
    Radar.SendMessage(msg);
}

void NotifyPhoto(string msg) {
    if(MQLInfoInteger(MQL_TESTER)) return;
    Radar.SendMessageWithPhoto(msg);
}

// ==================================================================
// CÔNG THỨC SL — sao y ComputeSLPadPips/ComputeAdjustedSL của bot GetChart
// ==================================================================
// Chia độ rộng Zone thành 5 phần, lấy 1 phần tra thang 30-35-40-45-50 pips (làm tròn LÊN
// mốc gần nhất) để ra khoảng đệm. "1 phần" CHỈ là chìa khoá tra bảng, KHÔNG cộng vào SL.
double ComputeSLPadPips(double entry, double stop) {
    double pip = GetPipSize(_Symbol);
    double widthPips = MathAbs(entry - stop) / pip;
    double share = widthPips / 5.0;
    double pad = SL_LADDER[4];
    for(int k = 0; k < 5; k++) {
        if(share <= SL_LADDER[k]) { pad = SL_LADDER[k]; break; }
    }
    return pad;
}

// SL cuối cùng, 4 bước (Buy đẩy xuống, Sell đẩy lên — luôn RA XA Zone):
//   1. Mép SL gốc của Zone.  2. Đẩy ra xa theo thang đệm.
//   3. Làm tròn số nguyên (nếu bật).  4. Nới thêm Inp_SL_Extra_Pips.
// Thứ tự "làm tròn TRƯỚC, nới thêm SAU" là cố ý (xem Nhatky_BOT_ChartSnapshot 04/09/2026):
// nhờ vậy phần nới thêm LUÔN đủ số pip, không bị phép làm tròn ăn bớt.
double ComputeAdjustedSL(bool isBuy, double entry, double stop) {
    double pip     = GetPipSize(_Symbol);
    double padPips = ComputeSLPadPips(entry, stop);
    double adjusted = isBuy ? (stop - padPips * pip) : (stop + padPips * pip);
    double rounded  = Inp_SL_RoundInteger ? MathRound(adjusted) : adjusted;
    double final_sl = isBuy ? (rounded - Inp_SL_Extra_Pips * pip)
                            : (rounded + Inp_SL_Extra_Pips * pip);
    return NormalizeDouble(final_sl, _Digits);
}

// ==================================================================
// HÀNG ĐỢI ĐÓNG LỆNH RETRY (port từ BOT_TLS)
// ==================================================================
bool IsRetryableRetcode(uint rc) {
    return (rc == TRADE_RETCODE_REQUOTE       ||
            rc == TRADE_RETCODE_PRICE_OFF     ||
            rc == TRADE_RETCODE_CONNECTION    ||
            rc == TRADE_RETCODE_TIMEOUT       ||
            rc == TRADE_RETCODE_PRICE_CHANGED ||
            rc == TRADE_RETCODE_MARKET_CLOSED);
}

void QueueCloseRetry(ulong ticket, string source) {
    for(int i = 0; i < g_retry_count; i++)
        if(g_retry_queue[i].ticket == ticket) return;
    ArrayResize(g_retry_queue, g_retry_count + 1);
    g_retry_queue[g_retry_count].ticket  = ticket;
    g_retry_queue[g_retry_count].retries = 0;
    g_retry_queue[g_retry_count].next_ms = GetTickCount64() + 300;
    g_retry_queue[g_retry_count].source  = source;
    g_retry_count++;
    Print(PFX, "[RETRY] Queue ticket=", ticket, " source=", source);
}

void ProcessCloseRetryQueue() {
    if(g_retry_count == 0) return;
    ulong now = GetTickCount64();
    for(int i = g_retry_count - 1; i >= 0; i--) {
        if(now < g_retry_queue[i].next_ms) continue;
        ulong ticket = g_retry_queue[i].ticket;
        if(!PositionSelectByTicket(ticket)) {
            ArrayRemove(g_retry_queue, i, 1); g_retry_count--;
            continue;
        }
        if(g_retry_queue[i].retries >= 5) {
            Print(PFX, "[RETRY] ticket=", ticket, " [", g_retry_queue[i].source, "] hết 5 lần retry, bỏ qua");
            ArrayRemove(g_retry_queue, i, 1); g_retry_count--;
            continue;
        }
        g_retry_queue[i].retries++;
        if(trade.PositionClose(ticket)) {
            Print(PFX, "[RETRY] ticket=", ticket, " đóng thành công lần ", g_retry_queue[i].retries);
            ArrayRemove(g_retry_queue, i, 1); g_retry_count--;
        } else {
            uint rc = trade.ResultRetcode();
            if(IsRetryableRetcode(rc)) g_retry_queue[i].next_ms = GetTickCount64() + 300;
            else {
                Print(PFX, "[RETRY] ticket=", ticket, " retcode=", rc, " không thể retry");
                ArrayRemove(g_retry_queue, i, 1); g_retry_count--;
            }
        }
    }
}

// ==================================================================
// CỨU TRẠNG THÁI SAU CRASH (GlobalVariables)
// ==================================================================
string GVKey(string k) { return "GCB_" + _Symbol + "_" + k; }

void SaveState() {
    GlobalVariableSet(GVKey("stopped_today"), g_trading_stopped_today ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("passed"),        g_account_passed        ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("sod_balance"),   g_sod_balance);
    GlobalVariableSet(GVKey("last_day"),      (double)g_last_day_checked);
    GlobalVariableSet(GVKey("cmd_paused"),    g_cmd_paused ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("tg_last_uid"),   (double)g_tg_last_update_id);
    GlobalVariableSet(GVKey("group_seq"),     (double)g_group_seq);
    // Mốc Zone: giữ lại để sau khi EA reload không coi Zone đang có là Zone mới.
    GlobalVariableSet(GVKey("zone_seen"),     g_zone_seen ? 1.0 : 0.0);
    GlobalVariableSet(GVKey("buy_entry"),     g_last_buy_entry);
    GlobalVariableSet(GVKey("buy_sl"),        g_last_buy_sl);
    GlobalVariableSet(GVKey("sell_entry"),    g_last_sell_entry);
    GlobalVariableSet(GVKey("sell_sl"),       g_last_sell_sl);
}

void LoadState() {
    if(!GlobalVariableCheck(GVKey("sod_balance"))) return;
    g_trading_stopped_today = GlobalVariableGet(GVKey("stopped_today")) > 0.5;
    g_account_passed        = GlobalVariableGet(GVKey("passed"))        > 0.5;
    g_sod_balance           = GlobalVariableGet(GVKey("sod_balance"));
    g_last_day_checked      = (datetime)GlobalVariableGet(GVKey("last_day"));
    g_cmd_paused            = GlobalVariableGet(GVKey("cmd_paused"))    > 0.5;
    g_tg_last_update_id     = (long)GlobalVariableGet(GVKey("tg_last_uid"));
    g_group_seq             = (int)GlobalVariableGet(GVKey("group_seq"));
    if(GlobalVariableCheck(GVKey("zone_seen"))) {
        g_zone_seen       = GlobalVariableGet(GVKey("zone_seen")) > 0.5;
        g_last_buy_entry  = GlobalVariableGet(GVKey("buy_entry"));
        g_last_buy_sl     = GlobalVariableGet(GVKey("buy_sl"));
        g_last_sell_entry = GlobalVariableGet(GVKey("sell_entry"));
        g_last_sell_sl    = GlobalVariableGet(GVKey("sell_sl"));
    }
    Print(PFX, "[STATE] Khôi phục: stopped=", g_trading_stopped_today,
          " paused=", g_cmd_paused, " sod_balance=", DoubleToString(g_sod_balance, 2));
}

// ==================================================================
// LÁ CHẮN TÀI KHOẢN (port từ BOT_TLS)
// ==================================================================
void CloseAll_PropFirm(string reason) {
    bool action_taken = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(!ticket || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(IsMyMagic(OrderGetInteger(ORDER_MAGIC))) { trade.OrderDelete(ticket); action_taken = true; }
    }
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        if(!trade.PositionClose(ticket)) {
            uint rc = trade.ResultRetcode();
            Print(PFX, "[SHIELD] Đóng lệnh lỗi ticket=", ticket, " retcode=", rc);
            if(IsRetryableRetcode(rc)) QueueCloseRetry(ticket, "SHIELD");
        }
        action_taken = true;
    }
    if(action_taken)
        Notify("🚨 <b>LÁ CHẮN KÍCH HOẠT</b>\n" + reason
            + "\nĐã huỷ sạch lệnh chờ và đóng toàn bộ vị thế của bot.");
}

bool IsInNewsWindow() {
    if(Inp_NewsTimes == "") return false;
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    int now_min = dt.hour * 60 + dt.min;
    string times[]; StringSplit(Inp_NewsTimes, ',', times);
    for(int i = 0; i < ArraySize(times); i++) {
        string t = times[i]; StringTrimLeft(t); StringTrimRight(t);
        if(t == "") continue;
        string parts[]; StringSplit(t, ':', parts);
        if(ArraySize(parts) == 2) {
            int news_min = (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
            if(now_min >= (news_min - Inp_NewsBufferMinutes) && now_min <= (news_min + Inp_NewsBufferMinutes))
                return true;
        }
    }
    return false;
}

void ManagePropFirmRules() {
    if(g_account_passed) return;
    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
    if(current_day != g_last_day_checked) {
        g_sod_balance           = AccountInfoDouble(ACCOUNT_BALANCE);
        g_trading_stopped_today = false;
        g_shield_stop_reason    = "";
        g_last_day_checked      = current_day;
    }
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(Inp_AutoPassTarget > 0 && equity >= Inp_AutoPassTarget) {
        CloseAll_PropFirm("🎉 ĐẠT MỤC TIÊU: " + DoubleToString(equity, 2) + "$");
        g_account_passed = true; g_trading_stopped_today = true;
        g_shield_stop_reason = "Đã đạt mục tiêu (" + DoubleToString(equity, 2) + "$)";
        return;
    }
    if(Inp_DailyDrawdownLimit > 0 && g_sod_balance > 0 && !g_trading_stopped_today) {
        double loss_limit = g_sod_balance - g_sod_balance * (Inp_DailyDrawdownLimit / 100.0);
        if(equity <= loss_limit) {
            CloseAll_PropFirm("🛑 CHẠM LỖ NGÀY " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%");
            g_trading_stopped_today = true;
            g_shield_stop_reason = "Chạm lỗ ngày " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%";
        }
    }
    if(Inp_DailyProfitLimit > 0 && g_sod_balance > 0 && !g_trading_stopped_today) {
        double pct = (equity - g_sod_balance) / g_sod_balance * 100.0;
        if(pct >= Inp_DailyProfitLimit) {
            CloseAll_PropFirm("🎯 ĐẠT LÃI NGÀY +" + DoubleToString(pct, 2) + "%");
            g_trading_stopped_today = true;
            g_shield_stop_reason = "Đạt lãi ngày +" + DoubleToString(pct, 2) + "%";
        }
    }
}

// ==================================================================
// TÍNH LOT (port từ BOT_TLS)
// ==================================================================
double CalculateLotSize(double sl_distance_points) {
    if(!UseRiskPerTrade || sl_distance_points <= 0) return FixedLotSize;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size == 0 || tick_value == 0) return FixedLotSize;
    if(RiskPercent <= 0) return FixedLotSize;
    double money_risk      = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    double value_per_point = tick_value / (tick_size / _Point);
    double risk_per_lot    = sl_distance_points * value_per_point;
    if(risk_per_lot == 0) return 0;
    double raw_lot = money_risk / risk_per_lot;
    if(Inp_UseMarginLimit) {
        double used_margin  = AccountInfoDouble(ACCOUNT_MARGIN);
        double max_margin   = AccountInfoDouble(ACCOUNT_BALANCE) * (Inp_MaxMarginPercent / 100.0);
        double room         = max_margin - used_margin;
        if(room <= 0) return 0;
        double margin_per_lot = 0;
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, ask, margin_per_lot))
            margin_per_lot = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * ask)
                           / AccountInfoInteger(ACCOUNT_LEVERAGE);
        if(margin_per_lot > 0) {
            double max_lot_by_margin = room / margin_per_lot;
            if(raw_lot > max_lot_by_margin) raw_lot = max_lot_by_margin;
        }
    }
    double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(step_lot <= 0) step_lot = 0.01;
    raw_lot = MathRound(raw_lot / step_lot) * step_lot;
    if(raw_lot < min_lot) return 0;
    return MathMin(raw_lot, max_lot);
}

// ==================================================================
// SỔ THEO DÕI LỆNH (phục vụ BE theo nhóm + báo RR khi đóng)
// ==================================================================
int FindTradeRec(ulong ticket) {
    for(int i = 0; i < ArraySize(g_trades); i++)
        if(g_trades[i].ticket == ticket) return i;
    return -1;
}

// Ghi sổ ngay lúc gửi lệnh (kể cả lệnh chờ chưa khớp) để biết lệnh này thuộc setup nào.
// open_price/init_sl để 0, sẽ được điền khi lệnh thành vị thế thật.
void AddTradeRec(ulong ticket, int group_id, int level, int dir) {
    if(ticket == 0 || FindTradeRec(ticket) >= 0) return;
    int n = ArraySize(g_trades);
    ArrayResize(g_trades, n + 1);
    g_trades[n].ticket       = ticket;
    g_trades[n].group_id     = group_id;
    g_trades[n].level        = level;
    g_trades[n].dir          = dir;
    g_trades[n].open_price   = 0;
    g_trades[n].init_sl      = 0;
    g_trades[n].risk_money   = 0;
    g_trades[n].realized_pnl = 0;
    g_trades[n].be_done      = false;
}

void RemoveTradeRec(int idx) {
    if(idx < 0 || idx >= ArraySize(g_trades)) return;
    for(int k = idx; k < ArraySize(g_trades) - 1; k++) g_trades[k] = g_trades[k + 1];
    ArrayResize(g_trades, ArraySize(g_trades) - 1);
}

bool OrderExistsByTicket(ulong ticket) {
    if(ticket == 0) return false;
    return OrderSelect(ticket);
}

bool PositionExistsByTicket(ulong ticket) {
    if(ticket == 0) return false;
    return PositionSelectByTicket(ticket);
}

// Điền thông tin thật cho các vị thế vừa khớp + dọn sổ những vé đã biến mất
// (lệnh chờ bị huỷ mà chưa từng thành vị thế). Cũng nhận lại vị thế mồ côi sau khi EA
// reload: các vị thế đó vào sổ với group_id = -1, nghĩa là không kéo BE theo nhóm được
// nữa (không biết chúng từng thuộc setup nào) nhưng vẫn được báo cáo khi đóng.
void SyncTradeRecords() {
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        int idx = FindTradeRec(ticket);
        if(idx < 0) {
            int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
            AddTradeRec(ticket, -1, -1, dir);
            idx = FindTradeRec(ticket);
            Print(PFX, "[SỔ] Nhận lại vị thế mồ côi ticket=", ticket, " (không rõ nhóm, BE theo nhóm sẽ bỏ qua)");
        }
        if(idx >= 0 && g_trades[idx].open_price == 0) {
            g_trades[idx].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            g_trades[idx].init_sl    = PositionGetDouble(POSITION_SL);
            double risk_dist = MathAbs(g_trades[idx].open_price - g_trades[idx].init_sl);
            double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double vol       = PositionGetDouble(POSITION_VOLUME);
            g_trades[idx].risk_money = (tick_size > 0)
                ? (risk_dist / tick_size * tick_val * vol) : 0;
        }
    }
    // Dọn: vé không còn là lệnh chờ, cũng không còn là vị thế -> bỏ khỏi sổ.
    // Trước khi bỏ, nếu vé đó TỪNG là vị thế thật (open_price != 0) thì tra lịch sử xem nó
    // đóng do chạm TP không. Đây là đường phát hiện TP CHÍNH của bot — không phụ thuộc
    // OnTradeTransaction (backtest 03/08 cho thấy nhánh OnTradeTransaction không chạy tới
    // nơi: lệnh #11 chạm TP mà lệnh #10 cùng setup vẫn giữ nguyên SL gốc, log không có
    // dòng modify nào).
    for(int i = ArraySize(g_trades) - 1; i >= 0; i--) {
        ulong t = g_trades[i].ticket;
        if(PositionExistsByTicket(t) || OrderExistsByTicket(t)) continue;
        bool was_position = (g_trades[i].open_price != 0);
        int  gid          = g_trades[i].group_id;
        RemoveTradeRec(i);
        if(was_position && ClosedByTakeProfit(t)) {
            Print(PFX, "[TP] Lệnh #", t, " của setup #", gid, " đã chạm TP");
            HandleGroupTP(gid, t);
        }
    }
}

// Kéo SL của các vị thế CÒN LẠI trong cùng nhóm về hoà vốn (giá mở của chính nó).
// Gọi khi một lệnh của nhóm đã chạm TP.
void ApplyBEForGroup(int group_id, ulong exclude_ticket) {
    if(group_id < 0) return;
    for(int i = 0; i < ArraySize(g_trades); i++) {
        if(g_trades[i].group_id != group_id) continue;
        ulong t = g_trades[i].ticket;
        if(t == exclude_ticket) continue;
        if(!PositionSelectByTicket(t)) continue;
        if(g_trades[i].be_done) continue;
        long   type = PositionGetInteger(POSITION_TYPE);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur_sl = PositionGetDouble(POSITION_SL);
        bool need = (type == POSITION_TYPE_BUY  && (cur_sl < open || cur_sl == 0))
                 || (type == POSITION_TYPE_SELL && (cur_sl > open || cur_sl == 0));
        if(!need) { g_trades[i].be_done = true; continue; }
        if(trade.PositionModify(t, NormalizeDouble(open, _Digits), PositionGetDouble(POSITION_TP))) {
            g_trades[i].be_done = true;
            Print(PFX, "[BE] Kéo SL lệnh #", t, " về hoà vốn ", DoubleToString(open, _Digits),
                  " (lệnh cùng setup đã chạm TP)");
            Notify("🛡️ <b>KÉO SL VỀ HOÀ VỐN</b>\n━━━━━━━━━━━━━━━\n"
                + "Lệnh cùng setup đã chạm TP, lệnh #" + (string)t + " được đưa về hoà vốn tại "
                + DoubleToString(open, _Digits));
        } else {
            Print(PFX, "[BE] LỖI kéo BE lệnh #", t, " retcode=", trade.ResultRetcode(),
                  " (", trade.ResultRetcodeDescription(), ")");
        }
    }
}

// Đánh dấu 2 mốc của setup đã dùng xong, để ProcessSetupBar không đặt lại lệnh chờ nữa.
void MarkSetupDoneByGroup(int group_id) {
    if(g_buy_setup.active && g_buy_setup.group_id == group_id)
        for(int i = 0; i < 2; i++) { g_buy_setup.lvl[i].done = true; g_buy_setup.lvl[i].ticket = 0; }
    if(g_sell_setup.active && g_sell_setup.group_id == group_id)
        for(int i = 0; i < 2; i++) { g_sell_setup.lvl[i].done = true; g_sell_setup.lvl[i].ticket = 0; }
}

// Một lệnh của setup đã chạm TP -> (1) huỷ lệnh chờ chưa khớp của chính setup đó,
// (2) khoá 2 mốc lại không cho vào thêm, (3) kéo SL các lệnh còn lại về hoà vốn.
// Viết idempotent (gọi lại nhiều lần không sao) vì được gọi từ 2 nơi: OnTradeTransaction
// và bộ dò theo lịch sử trong SyncTradeRecords.
void HandleGroupTP(int group_id, ulong closed_ticket) {
    if(group_id < 0) return;
    int cancelled = 0;
    for(int i = 0; i < ArraySize(g_trades); i++) {
        if(g_trades[i].group_id != group_id) continue;
        ulong t = g_trades[i].ticket;
        if(t == closed_ticket) continue;
        if(OrderExistsByTicket(t) && trade.OrderDelete(t)) cancelled++;
    }
    if(cancelled > 0)
        Print(PFX, "[TP] Đã huỷ ", cancelled, " lệnh chờ của setup #", group_id, " vì đã có lệnh chạm TP");
    MarkSetupDoneByGroup(group_id);
    ApplyBEForGroup(group_id, closed_ticket);
}

// Vị thế đã đóng: đọc lịch sử xem có phải đóng do chạm TP (hoặc đóng có lãi) không.
// Dùng để phát hiện TP mà KHÔNG phụ thuộc OnTradeTransaction.
bool ClosedByTakeProfit(ulong pos_id) {
    if(!HistorySelectByPosition(pos_id)) return false;
    double pnl = 0;
    bool   found = false, by_tp = false;
    int    total = HistoryDealsTotal();
    for(int i = 0; i < total; i++) {
        ulong d = HistoryDealGetTicket(i);
        if(d == 0) continue;
        if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        pnl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
             + HistoryDealGetDouble(d, DEAL_COMMISSION);
        if(HistoryDealGetInteger(d, DEAL_REASON) == DEAL_REASON_TP) by_tp = true;
        found = true;
    }
    return (found && (by_tp || pnl > 0));
}

// ==================================================================
// LƯỚI SL ẢO — chốt chặn khi SL trên sàn không nổ
// ==================================================================
// Bối cảnh: backtest 03/08/2026 cho thấy 2 lệnh SELL có SL 4044 mà giá đã lên 4047.6
// (cả Bid lẫn Ask đều vượt) vẫn treo hơn một tiếng, tới 22:01 mới đóng và bị trượt 107
// pips. Chưa xác định được vì sao MT5 không nổ SL trong khoảng đó, nên đặt lưới này vừa
// để BẢO VỆ vừa để ĐO: nó in ra đúng giá Bid/Ask và giá trị SL mà sàn đang báo tại thời
// điểm phát hiện, đủ để kết luận ở lần chạy tới.
// Khi SL sàn hoạt động bình thường thì hàm này không bao giờ ra tay.
int FindVSLIndex(ulong ticket) {
    for(int i = 0; i < ArraySize(g_vsl_ticket); i++)
        if(g_vsl_ticket[i] == ticket) return i;
    return -1;
}

int EnsureVSLSlot(ulong ticket) {
    int idx = FindVSLIndex(ticket);
    if(idx >= 0) return idx;
    int n = ArraySize(g_vsl_ticket);
    ArrayResize(g_vsl_ticket, n + 1);
    ArrayResize(g_vsl_next_try, n + 1);
    ArrayResize(g_vsl_last_log, n + 1);
    g_vsl_ticket[n]   = ticket;
    g_vsl_next_try[n] = 0;
    g_vsl_last_log[n] = 0;
    return n;
}

void CheckVirtualSL() {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(bid <= 0 || ask <= 0) return;
    datetime now = TimeCurrent();

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;

        double sl = PositionGetDouble(POSITION_SL);
        if(sl <= 0) continue;   // không đặt SL thì không có gì để canh

        long   type = PositionGetInteger(POSITION_TYPE);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        // Buy đóng bằng Bid, Sell đóng bằng Ask — đúng bên giá mà SL thật sẽ kích hoạt.
        bool breached = (type == POSITION_TYPE_BUY) ? (bid <= sl) : (ask >= sl);
        if(!breached) continue;

        int idx = EnsureVSLSlot(t);
        if(now < g_vsl_next_try[idx]) continue;
        g_vsl_next_try[idx] = now + 5;   // mặc định thử lại tối đa 5 giây/lần

        bool log_now = (g_vsl_last_log[idx] == 0 || now - g_vsl_last_log[idx] >= 60);
        if(log_now) {
            g_vsl_last_log[idx] = now;
            Print(PFX, "[SL-ẢO] #", t, " ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " open=", DoubleToString(open, _Digits),
                  " SL(sàn báo)=", DoubleToString(sl, _Digits),
                  " Bid=", DoubleToString(bid, _Digits),
                  " Ask=", DoubleToString(ask, _Digits),
                  " -> giá đã vượt SL mà lệnh còn mở, thử đóng bằng lệnh thị trường");
        }

        if(trade.PositionClose(t)) {
            Print(PFX, "[SL-ẢO] #", t, " ĐÃ ĐÓNG bằng lệnh thị trường (SL sàn không nổ)");
        } else {
            uint rc = trade.ResultRetcode();
            if(log_now)
                Print(PFX, "[SL-ẢO] #", t, " đóng THẤT BẠI retcode=", rc,
                      " (", trade.ResultRetcodeDescription(), ")");
            if(rc == TRADE_RETCODE_MARKET_CLOSED) {
                g_market_closed_until = now + 60;
                // Thị trường đóng thì 5 giây/lần là vô nghĩa và cực kỳ ồn: backtest 03/08
                // có tới hơn 3 tiếng đóng cửa liên tục, nhịp 5 giây đẻ ra ~4.500 lệnh đóng
                // hỏng. Giãn ra 5 phút — vẫn đủ nhanh để bắt lúc mở lại, mà không spam.
                g_vsl_next_try[idx] = now + 300;
            }
        }
    }

    // Dọn slot của những vé đã đóng
    for(int i = ArraySize(g_vsl_ticket) - 1; i >= 0; i--) {
        if(PositionSelectByTicket(g_vsl_ticket[i])) continue;
        for(int k = i; k < ArraySize(g_vsl_ticket) - 1; k++) {
            g_vsl_ticket[k]   = g_vsl_ticket[k + 1];
            g_vsl_next_try[k] = g_vsl_next_try[k + 1];
            g_vsl_last_log[k] = g_vsl_last_log[k + 1];
        }
        ArrayResize(g_vsl_ticket,   ArraySize(g_vsl_ticket) - 1);
        ArrayResize(g_vsl_next_try, ArraySize(g_vsl_next_try) - 1);
        ArrayResize(g_vsl_last_log, ArraySize(g_vsl_last_log) - 1);
    }
}

// ==================================================================
// NẾN XÁC NHẬN (S)
// ==================================================================
// Xét cây nến VỪA ĐÓNG (shift 1) của khung Zone, và cây liền trước (shift 2) cho engulfing.
//
// Điều kiện vị trí (chốt ở phần 4B): nến tín hiệu phải đóng ở PHÍA TRONG mốc — tức là từ
// mốc trở vào giữa Zone — và chưa đóng xuyên qua mép SL. Nhờ vậy giá vào lệnh không bao
// giờ xấu hơn giá mốc, mà vẫn nhận được tín hiệu xuất hiện muộn sau khi giá đã chạm mốc.
//
// Pinbar (chốt phần 4B.2): nến phải THUẬN chiều lệnh VÀ râu phía quét >= 1.5 x thân.
//   Cả 2 điều kiện đều bắt buộc — khác BOT_CRT (bên đó nến thuận chiều được miễn đo râu),
//   vì ở đây nến tín hiệu không còn bắt buộc phải chọc qua mốc nên nếu miễn đo râu thì một
//   cây nến giảm trơn cũng bị coi là tín hiệu bán.
//
// Engulfing (chốt phần 4B.3): nến 2 phải trùm CẢ High LẪN Low của nến 1 và đóng thuận
//   chiều lệnh. Không đòi nến 1 phải ngược chiều — điều kiện trùm toàn biên độ đã đủ chặt.
bool IsSignalCandle(int dir, double level, double zone_sl) {
    if(Inp_Signal_Mode == SIGNAL_KHONG_CAN_NEN) return false;

    double o1 = iOpen (_Symbol, Inp_Zone_Timeframe, 1);
    double h1 = iHigh (_Symbol, Inp_Zone_Timeframe, 1);
    double l1 = iLow  (_Symbol, Inp_Zone_Timeframe, 1);
    double c1 = iClose(_Symbol, Inp_Zone_Timeframe, 1);
    double o2 = iOpen (_Symbol, Inp_Zone_Timeframe, 2);
    double h2 = iHigh (_Symbol, Inp_Zone_Timeframe, 2);
    double l2 = iLow  (_Symbol, Inp_Zone_Timeframe, 2);
    double c2 = iClose(_Symbol, Inp_Zone_Timeframe, 2);
    if(o1 <= 0 || c1 <= 0 || h2 <= 0 || o2 <= 0 || c2 <= 0) return false;

    // Vị trí nến so với mốc và mép SL
    if(dir == 1) { if(!(c1 <= level && c1 > zone_sl)) return false; }
    else         { if(!(c1 >= level && c1 < zone_sl)) return false; }

    double body = MathAbs(c1 - o1);
    double wick = (dir == 1) ? (MathMin(o1, c1) - l1) : (h1 - MathMax(o1, c1));
    if(wick < 0) wick = 0;

    bool with_trade = (dir == 1) ? (c1 > o1) : (c1 < o1);
    bool pin = with_trade && wick > 0 && (wick >= body * WICK_BODY_RATIO);
    // Nến trước ngược chiều lệnh — chỉ bị đòi khi bật Inp_Engulf_PrevOpposite.
    bool prev_against = (dir == 1) ? (c2 < o2) : (c2 > o2);
    bool eng = with_trade && (h1 >= h2) && (l1 <= l2)
            && (!Inp_Engulf_PrevOpposite || prev_against);

    if(Inp_Signal_Mode == SIGNAL_PINBAR)    return pin;
    if(Inp_Signal_Mode == SIGNAL_ENGULFING) return eng;
    return (pin || eng);   // SIGNAL_PINBAR_HOAC_ENGULFING
}

// ==================================================================
// VẼ SETUP LÊN CHART (chỉ để nhìn khi backtest / theo dõi tay)
// ==================================================================
void DrawLine(string name, double price, color clr, ENUM_LINE_STYLE style, string text) {
    if(price <= 0) return;
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
    }
    ObjectSetDouble (0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetString (0, name, OBJPROP_TEXT,  text);
}

string SetupPrefix(int dir) { return (dir == 1) ? "GCB_BUY_" : "GCB_SELL_"; }

void DeleteSetupLines(int dir) {
    ObjectsDeleteAll(0, SetupPrefix(dir));
}

// ==================================================================
// SETUP: TẠO / HUỶ / ĐẶT LỆNH
// ==================================================================
void CancelPendingsOfSetup(SSetup &s) {
    for(int i = 0; i < 2; i++) {
        ulong t = s.lvl[i].ticket;
        if(t == 0) continue;
        if(OrderExistsByTicket(t)) trade.OrderDelete(t);
        s.lvl[i].ticket = 0;
    }
}

void KillSetup(SSetup &s, string reason) {
    if(!s.active) return;
    CancelPendingsOfSetup(s);
    DeleteSetupLines(s.dir);
    s.active = false;
    DebugLog("SETUP", (s.dir == 1 ? "BUY" : "SELL") + " kết thúc — " + reason);
}

void DrawSetupLines(SSetup &s) {
    string p = SetupPrefix(s.dir);
    color  c = (s.dir == 1) ? CLR_LEVEL_BUY : CLR_LEVEL_SELL;
    if(s.lvl[0].enabled) DrawLine(p + "L1", s.lvl[0].price, c, STYLE_SOLID,  "Mốc 1");
    if(s.lvl[1].enabled) DrawLine(p + "L2", s.lvl[1].price, c, STYLE_DASH,   "Mốc 2");
    DrawLine(p + "SL", s.sl_price, CLR_SL_LINE, STYLE_DOT, "SL");
}

// Đếm số vị thế đang chịu rủi ro (SL chưa về hoà vốn) + số lệnh chờ đang treo của bot.
int CountRiskTrades() {
    int cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long   type = PositionGetInteger(POSITION_TYPE);
        double op   = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl   = PositionGetDouble(POSITION_SL);
        if(type == POSITION_TYPE_BUY  && (sl < op || sl == 0)) cnt++;
        if(type == POSITION_TYPE_SELL && (sl > op || sl == 0)) cnt++;
    }
    for(int i = 0; i < OrdersTotal(); i++) {
        ulong t = OrderGetTicket(i);
        if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(IsMyMagic(OrderGetInteger(ORDER_MAGIC))) cnt++;
    }
    return cnt;
}

// Khoảng cách tối thiểu chỉ áp với lệnh của setup KHÁC. Hai mốc của cùng một Zone luôn
// được miễn — Zone hẹp (ví dụ 20 pips) thì mốc 50% chỉ cách mép 10 pips, nếu áp luật này
// cho cùng setup thì lệnh thứ 2 sẽ không bao giờ vào được.
bool IsTooCloseToOtherSetup(double entry_price, int dir, int group_id) {
    if(Inp_Min_Entry_Dist_Pips <= 0) return false;
    double min_dist = Inp_Min_Entry_Dist_Pips * GetPipSize(_Symbol);
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
        if(pdir != dir) continue;
        int idx = FindTradeRec(t);
        if(idx >= 0 && g_trades[idx].group_id == group_id) continue;   // cùng setup -> miễn
        if(MathAbs(entry_price - PositionGetDouble(POSITION_PRICE_OPEN)) < min_dist) return true;
    }
    for(int i = 0; i < OrdersTotal(); i++) {
        ulong t = OrderGetTicket(i);
        if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(OrderGetInteger(ORDER_MAGIC))) continue;
        long ot = OrderGetInteger(ORDER_TYPE);
        int odir = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP) ? 1 : -1;
        if(odir != dir) continue;
        int idx = FindTradeRec(t);
        if(idx >= 0 && g_trades[idx].group_id == group_id) continue;
        if(MathAbs(entry_price - OrderGetDouble(ORDER_PRICE_OPEN)) < min_dist) return true;
    }
    return false;
}

// Điều kiện chung chặn mọi lệnh mới.
bool TradingBlocked(string &why) {
    if(g_cmd_paused)                        { why = "Bot đang PAUSED (gửi /start để tiếp tục)"; return true; }
    if(g_trading_stopped_today || g_account_passed) { why = "[LÁ CHẮN] " + g_shield_stop_reason; return true; }
    if(IsInNewsWindow())                    { why = "Đang trong khung giờ tin"; return true; }
    // Sàn vừa trả "market closed" -> nghỉ một lát rồi hẵng thử lại. Không có chốt này thì
    // bot gửi lại lệnh mỗi nến và ăn nguyên chuỗi lỗi 10018 (backtest 03/08 dính 12 lần
    // trong 6 phút); trên VPS thật kiểu đó dễ bị sàn chặn.
    if(TimeCurrent() < g_market_closed_until) { why = "Thị trường đang đóng cửa"; return true; }
    return false;
}

// Đặt 1 lệnh cho 1 mốc. force_market = true khi vào theo nến xác nhận.
// Trả về true nếu đã gửi lệnh thành công (lệnh chờ hoặc lệnh thị trường).
bool PlaceEntry(SSetup &s, int idx, bool force_market) {
    string why = "";
    if(TradingBlocked(why)) { g_filter_text = "Chặn: " + why; return false; }

    if(CountRiskTrades() >= Inp_Max_Risk_Trades) {
        g_filter_text = "Chặn: đủ " + IntegerToString(Inp_Max_Risk_Trades) + " lệnh đang chịu rủi ro";
        return false;
    }

    double pip   = GetPipSize(_Symbol);
    double level = s.lvl[idx].price;
    double sl    = s.sl_price;
    double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

    // Giá dự kiến vào lệnh: lệnh chờ đặt đúng mốc; lệnh thị trường lấy giá hiện tại.
    bool   use_market = force_market;
    double entry      = level;
    if(s.dir == 1) {
        // Giá đã ở ngay/dưới mốc -> không đặt Buy Limit được nữa, vào Market (chốt phần 3.2).
        if(ask <= level + stops) { use_market = true; entry = ask; }
    } else {
        if(bid >= level - stops) { use_market = true; entry = bid; }
    }
    if(use_market) entry = (s.dir == 1) ? ask : bid;

    // Giá vào lệnh không được cách mốc quá xa (0 = không giới hạn)
    if(Inp_MaxDistFromLevel_Pips > 0 && MathAbs(entry - level) > Inp_MaxDistFromLevel_Pips * pip) {
        g_filter_text = "Chặn: giá vào cách mốc " + DoubleToString(MathAbs(entry - level) / pip, 0) + " pips";
        return false;
    }

    double risk_dist = MathAbs(entry - sl);
    if(risk_dist <= 0) { g_filter_text = "Chặn: khoảng SL = 0"; return false; }

    if(IsTooCloseToOtherSetup(entry, s.dir, s.group_id)) {
        g_filter_text = "Chặn: quá sát lệnh của setup khác (< "
                      + DoubleToString(Inp_Min_Entry_Dist_Pips, 0) + " pips)";
        DebugLog("LỆNH", "Mốc " + IntegerToString(idx + 1) + " — " + g_filter_text);
        return false;
    }

    double lot = CalculateLotSize(risk_dist / _Point);
    if(lot <= 0) { g_filter_text = "Chặn: lot = 0 (hết margin hoặc rủi ro quá nhỏ)"; return false; }

    double tp_pips = s.lvl[idx].tp_pips;
    double tp = 0;
    if(tp_pips > 0) tp = NormalizeDouble((s.dir == 1) ? (entry + tp_pips * pip) : (entry - tp_pips * pip), _Digits);

    // Lệnh chờ mà giá HIỆN TẠI đã vượt qua mức TP của chính nó thì đặt ra chỉ để bị huỷ
    // ngay ở tick sau (xem ProcessSetupTick) — bỏ luôn cho sạch, khoá mốc lại.
    // Không áp cho lệnh thị trường: TP của lệnh Market tính từ chính giá vào nên không
    // bao giờ rơi vào tình huống này.
    if(!use_market && tp > 0) {
        bool tp_passed = (s.dir == 1) ? (bid >= tp) : (ask <= tp);
        if(tp_passed) {
            s.lvl[idx].done = true;
            Print(PFX, "[LỆNH] Bỏ mốc ", idx + 1, ": giá hiện tại đã vượt mức TP dự kiến ",
                  DoubleToString(tp, _Digits), " nên lệnh chờ vô nghĩa");
            g_filter_text = "Bỏ mốc " + IntegerToString(idx + 1) + ": giá đã vượt TP dự kiến";
            return false;
        }
    }

    string cmt = "GCB-" + (s.dir == 1 ? "B" : "S") + IntegerToString(idx + 1) + "-" + IntegerToString(s.group_id);
    trade.SetExpertMagicNumber(MagicOfLevel(idx));

    bool ok = false;
    if(use_market) {
        ok = (s.dir == 1) ? trade.Buy(lot, _Symbol, 0, sl, tp, cmt)
                          : trade.Sell(lot, _Symbol, 0, sl, tp, cmt);
    } else {
        double price = NormalizeDouble(level, _Digits);
        ok = (s.dir == 1) ? trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
                          : trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
    }

    if(!ok && trade.ResultRetcode() != TRADE_RETCODE_DONE) {
        uint rc = trade.ResultRetcode();
        Print(PFX, "[LỆNH] Gửi lệnh THẤT BẠI mốc ", idx + 1, " retcode=", rc,
              " (", trade.ResultRetcodeDescription(), ")");
        g_filter_text = "Lỗi gửi lệnh: " + trade.ResultRetcodeDescription();
        if(rc == TRADE_RETCODE_MARKET_CLOSED) {
            g_market_closed_until = TimeCurrent() + 60;
            Print(PFX, "[LỆNH] Thị trường đóng cửa — ngưng gửi lệnh tới ",
                  TimeToString(g_market_closed_until, TIME_DATE | TIME_SECONDS));
        }
        return false;
    }

    // Lệnh thị trường: lấy giá KHỚP THẬT để log và tin Telegram không nói sai. Trước đây in
    // giá dự kiến trước khi gửi, lệch tới 6-7 pips so với giá khớp (backtest 03/08 05:51).
    if(use_market && trade.ResultPrice() > 0) entry = trade.ResultPrice();

    ulong ticket = trade.ResultOrder();
    AddTradeRec(ticket, s.group_id, idx, s.dir);
    if(use_market) { s.lvl[idx].done = true;  s.lvl[idx].ticket = 0; }
    else           { s.lvl[idx].done = false; s.lvl[idx].ticket = ticket; }

    double sl_pips = risk_dist / pip;
    string msg = "🛒 <b>" + (use_market ? "VÀO LỆNH THỊ TRƯỜNG" : "ĐẶT LỆNH CHỜ LIMIT") + " — "
               + (s.dir == 1 ? "MUA" : "BÁN") + "</b>\n━━━━━━━━━━━━━━━\n"
               + "📍 <b>Mốc " + IntegerToString(idx + 1) + ":</b> " + DoubleToString(level, _Digits)
               + "  (" + DoubleToString(idx == 0 ? Inp_Level1_Pct : Inp_Level2_Pct, 0) + "% Zone)\n"
               + "💵 <b>Giá vào:</b> " + DoubleToString(entry, _Digits) + " | <b>Lot:</b> " + DoubleToString(lot, 2) + "\n"
               + "🛡️ <b>SL:</b> " + DoubleToString(sl, _Digits) + " (" + DoubleToString(sl_pips, 0) + " pips)\n"
               + "🎯 <b>TP:</b> " + (tp > 0 ? DoubleToString(tp, _Digits) + " (" + DoubleToString(tp_pips, 0) + " pips)" : "Không đặt") + "\n"
               + "🧭 <b>Zone:</b> " + DoubleToString(s.zone_entry, _Digits) + " – " + DoubleToString(s.zone_sl, _Digits)
               + " | <b>Tín hiệu:</b> " + EnumToString(Inp_Signal_Mode);
    NotifyPhoto(msg);
    Print(PFX, "[LỆNH] ", (s.dir == 1 ? "BUY" : "SELL"), " mốc ", idx + 1,
          use_market ? " MARKET @" : " LIMIT @", DoubleToString(entry, _Digits),
          " SL=", DoubleToString(sl, _Digits), " lot=", DoubleToString(lot, 2));
    g_filter_text = "Đã vào lệnh mốc " + IntegerToString(idx + 1);
    return true;
}

// ==================================================================
// SETUP: TẠO MỚI KHI CÓ ZONE MỚI
// ==================================================================
void TryCreateSetup(SSetup &s, int dir, double zone_entry, double zone_sl) {
    // T — xu hướng. Trend = 0 (chưa xác định) cũng bị chặn, đúng tinh thần T-L-S.
    if(Inp_Enable_Trend_Filter && SMC_TREND.current_major_trend != dir) {
        g_filter_text = "Bỏ Zone " + (dir == 1 ? "Buy" : "Sell") + ": ngược xu hướng "
                      + TFName(Inp_Trend_Timeframe);
        DebugLog("SETUP", g_filter_text);
        return;
    }

    // Zone vừa sinh ra đã ở phía sau giá (giá nằm ngoài mép SL) thì bỏ luôn. Không có
    // chốt này thì với chế độ "không cần nến" bot sẽ vào Market ngay tại giá hiện tại rồi
    // mới bị ProcessSetupTick huỷ setup ở tick kế tiếp — tức là vào một lệnh mà Zone đã vỡ.
    double bid0 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask0 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if((dir == 1 && bid0 < zone_sl) || (dir == -1 && ask0 > zone_sl)) {
        g_filter_text = "Bỏ Zone " + (dir == 1 ? "Buy" : "Sell") + ": giá đã vượt mép SL của Zone";
        DebugLog("SETUP", g_filter_text);
        return;
    }

    double pip   = GetPipSize(_Symbol);
    double width = MathAbs(zone_entry - zone_sl) / pip;
    if(Inp_Max_Zone_Width_Pips > 0 && width > Inp_Max_Zone_Width_Pips) {
        g_filter_text = "Bỏ Zone: rộng " + DoubleToString(width, 0) + " pips (> "
                      + DoubleToString(Inp_Max_Zone_Width_Pips, 0) + ")";
        return;
    }
    if(Inp_Min_Zone_Width_Pips > 0 && width < Inp_Min_Zone_Width_Pips) {
        g_filter_text = "Bỏ Zone: hẹp " + DoubleToString(width, 0) + " pips (< "
                      + DoubleToString(Inp_Min_Zone_Width_Pips, 0) + ")";
        return;
    }

    g_group_seq++;
    s.active     = true;
    s.dir        = dir;
    s.group_id   = g_group_seq;
    s.zone_entry = zone_entry;
    s.zone_sl    = zone_sl;
    s.sl_price   = ComputeAdjustedSL(dir == 1, zone_entry, zone_sl);
    s.born       = TimeCurrent();

    // Mốc chạy từ mép Entry (gần giá) về phía mép SL: Buy đi xuống, Sell đi lên.
    double sign = (dir == 1) ? -1.0 : 1.0;
    double w    = MathAbs(zone_sl - zone_entry);
    double pct[2]; pct[0] = Inp_Level1_Pct; pct[1] = Inp_Level2_Pct;
    double tps[2]; tps[0] = Inp_TP1_Pips;   tps[1] = Inp_TP2_Pips;
    bool   ens[2]; ens[0] = Inp_Use_Level1; ens[1] = Inp_Use_Level2;
    for(int i = 0; i < 2; i++) {
        s.lvl[i].enabled = ens[i];
        s.lvl[i].price   = NormalizeDouble(zone_entry + sign * w * pct[i] / 100.0, _Digits);
        s.lvl[i].tp_pips = tps[i];
        s.lvl[i].armed   = false;
        s.lvl[i].done    = false;
        s.lvl[i].ticket  = 0;
    }

    DrawSetupLines(s);
    g_action_text = "Zone " + (dir == 1 ? "BUY" : "SELL") + " mới: "
                  + DoubleToString(zone_entry, _Digits) + " – " + DoubleToString(zone_sl, _Digits);
    Print(PFX, "[SETUP] ", g_action_text, " | SL=", DoubleToString(s.sl_price, _Digits),
          " | mốc1=", DoubleToString(s.lvl[0].price, _Digits),
          " | mốc2=", DoubleToString(s.lvl[1].price, _Digits));

    NotifyPhoto(
        (dir == 1 ? "🟩" : "🟥") + " <b>ZONE MỚI — " + (dir == 1 ? "MUA" : "BÁN") + " "
        + _Symbol + " " + TFName(Inp_Zone_Timeframe) + "</b>\n━━━━━━━━━━━━━━━\n"
        + "🧭 <b>Vùng:</b> " + DoubleToString(zone_entry, _Digits) + " – " + DoubleToString(zone_sl, _Digits)
        + " (" + DoubleToString(width, 0) + " pips)\n"
        + "📍 <b>Mốc 1:</b> " + (s.lvl[0].enabled ? DoubleToString(s.lvl[0].price, _Digits) : "tắt")
        + " | <b>Mốc 2:</b> " + (s.lvl[1].enabled ? DoubleToString(s.lvl[1].price, _Digits) : "tắt") + "\n"
        + "🛡️ <b>SL:</b> " + DoubleToString(s.sl_price, _Digits) + "\n"
        + "🕒 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));

    // Không cần nến xác nhận -> đặt sẵn lệnh chờ ngay tại 2 mốc.
    if(Inp_Signal_Mode == SIGNAL_KHONG_CAN_NEN) {
        for(int i = 0; i < 2; i++) {
            if(!s.lvl[i].enabled || s.lvl[i].done || s.lvl[i].ticket != 0) continue;
            PlaceEntry(s, i, false);
            // Mốc bật mà đặt lệnh không thành thì phải nói LÝ DO ra log. Không có dòng này
            // thì log chỉ hiện "Zone mới" rồi im, đọc lại không biết vì sao bot đứng ngoài
            // (đúng chỗ đã vấp khi soi backtest 03/08: setup 02:48 bị Inp_Min_Entry_Dist_Pips
            // chặn cả 2 mốc mà log không hé một chữ).
            if(!s.lvl[i].done && s.lvl[i].ticket == 0)
                Print(PFX, "[LỆNH] Không đặt được lệnh mốc ", i + 1, " — ", g_filter_text);
        }
    }
}

// ==================================================================
// SETUP: XỬ LÝ MỖI TICK (lên đạn mốc, Zone vỡ, trend đảo)
// ==================================================================
void ProcessSetupTick(SSetup &s) {
    if(!s.active) return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Zone vỡ theo giá: huỷ lệnh chờ và kết thúc setup ngay, không chờ nến đóng.
    if((s.dir == 1 && bid < s.zone_sl) || (s.dir == -1 && ask > s.zone_sl)) {
        KillSetup(s, "giá xuyên mép SL của Zone");
        g_filter_text = "Zone " + (s.dir == 1 ? "Buy" : "Sell") + " đã vỡ";
        return;
    }

    // Trend đảo: huỷ lệnh chờ, vị thế đã khớp giữ nguyên cho SL/TP tự chạy.
    if(Inp_Enable_Trend_Filter && SMC_TREND.current_major_trend != s.dir) {
        KillSetup(s, "xu hướng " + TFName(Inp_Trend_Timeframe) + " đảo chiều");
        g_filter_text = "Trend đảo — đã huỷ lệnh chờ";
        return;
    }

    // Giá chạy THẲNG tới TP mà lệnh chờ của mốc đó chưa kịp khớp -> setup coi như đã diễn
    // xong mà không có mình trong đó; giữ lệnh chờ lại chỉ tổ khớp muộn khi giá quay đầu.
    // Huỷ lệnh và khoá mốc luôn. Xét riêng từng mốc vì 2 mốc có 2 mức TP khác nhau.
    double pip_tick = GetPipSize(_Symbol);
    for(int i = 0; i < 2; i++) {
        if(!s.lvl[i].enabled || s.lvl[i].done || s.lvl[i].tp_pips <= 0) continue;
        double tp_price = (s.dir == 1) ? (s.lvl[i].price + s.lvl[i].tp_pips * pip_tick)
                                       : (s.lvl[i].price - s.lvl[i].tp_pips * pip_tick);
        bool tp_reached = (s.dir == 1) ? (bid >= tp_price) : (ask <= tp_price);
        if(!tp_reached) continue;
        if(s.lvl[i].ticket != 0 && OrderExistsByTicket(s.lvl[i].ticket)) {
            if(trade.OrderDelete(s.lvl[i].ticket))
                Print(PFX, "[TP] Huỷ lệnh chờ mốc ", i + 1, " (#", s.lvl[i].ticket,
                      "): giá đã chạy tới TP ", DoubleToString(tp_price, _Digits), " mà lệnh chưa khớp");
        } else {
            Print(PFX, "[TP] Khoá mốc ", i + 1, ": giá đã chạy tới TP ",
                  DoubleToString(tp_price, _Digits), " mà chưa vào được lệnh");
        }
        s.lvl[i].ticket = 0;
        s.lvl[i].done   = true;
        g_filter_text   = "Mốc " + IntegerToString(i + 1) + " bỏ: giá đã tới TP mà chưa khớp";
    }

    // Lên đạn: giá chạm mốc thì mốc đó armed vĩnh viễn cho tới khi Zone chết.
    for(int i = 0; i < 2; i++) {
        if(!s.lvl[i].enabled || s.lvl[i].done || s.lvl[i].armed) continue;
        bool touched = (s.dir == 1) ? (bid <= s.lvl[i].price) : (ask >= s.lvl[i].price);
        if(touched) {
            s.lvl[i].armed = true;
            Print(PFX, "[MỐC] ", (s.dir == 1 ? "BUY" : "SELL"), " mốc ", i + 1,
                  " đã chạm @", DoubleToString(s.lvl[i].price, _Digits), " — bắt đầu chờ tín hiệu nến");
        }
    }
}

// ==================================================================
// SETUP: XỬ LÝ MỖI NẾN KHUNG ZONE (xét nến xác nhận / đặt lại lệnh chờ)
// ==================================================================
void ProcessSetupBar(SSetup &s) {
    if(!s.active) return;

    for(int i = 0; i < 2; i++) {
        if(!s.lvl[i].enabled || s.lvl[i].done) continue;

        if(Inp_Signal_Mode == SIGNAL_KHONG_CAN_NEN) {
            // Lệnh chờ biến mất: đã khớp thành vị thế -> đánh dấu xong; bị huỷ ngoài ý muốn
            // (giờ tin, /stop, xoá tay) -> mở lại mốc để đặt lại khi hết điều kiện chặn.
            if(s.lvl[i].ticket != 0 && !OrderExistsByTicket(s.lvl[i].ticket)) {
                if(PositionExistsByTicket(s.lvl[i].ticket)) { s.lvl[i].done = true; }
                else Print(PFX, "[MỐC] Lệnh chờ mốc ", i + 1, " biến mất khi chưa khớp — sẽ đặt lại");
                s.lvl[i].ticket = 0;
            }
            if(!s.lvl[i].done && s.lvl[i].ticket == 0) PlaceEntry(s, i, false);
            continue;
        }

        // Có lọc nến: mốc phải được chạm trước, sau đó tín hiệu xuất hiện lúc nào vào lúc đó.
        if(!s.lvl[i].armed) continue;
        if(IsSignalCandle(s.dir, s.lvl[i].price, s.zone_sl)) {
            Print(PFX, "[TÍN HIỆU] ", (s.dir == 1 ? "BUY" : "SELL"), " mốc ", i + 1,
                  " có nến xác nhận (", EnumToString(Inp_Signal_Mode), ")");
            PlaceEntry(s, i, true);
        }
    }
}

// ==================================================================
// PHÁT HIỆN ZONE MỚI (L)
// ==================================================================
void ProcessZones() {
    double be = SMC_ZONE.current_buy_zone_entry,  bs = SMC_ZONE.current_buy_zone_sl;
    double se = SMC_ZONE.current_sell_zone_entry, ss = SMC_ZONE.current_sell_zone_sl;

    // Lần đọc đầu tiên sau khi EA khởi động: chỉ ghi mốc so sánh, KHÔNG vào lệnh —
    // không biết Zone đang có đã hình thành từ bao giờ (y hệt bot GetChart).
    if(!g_zone_seen) {
        g_zone_seen = true;
        g_last_buy_entry = be;  g_last_buy_sl  = bs;
        g_last_sell_entry = se; g_last_sell_sl = ss;
        Print(PFX, "[ZONE] Ghi mốc Zone hiện có, chờ Zone MỚI mới vào lệnh.");
        SaveState();
        return;
    }

    if(be != g_last_buy_entry || bs != g_last_buy_sl) {
        g_last_buy_entry = be; g_last_buy_sl = bs;
        if(g_buy_setup.active) KillSetup(g_buy_setup, "Zone Buy thay đổi");
        if(be > 0 && bs > 0 && be != EMPTY_VALUE && bs != EMPTY_VALUE)
            TryCreateSetup(g_buy_setup, 1, be, bs);
        SaveState();
    }
    if(se != g_last_sell_entry || ss != g_last_sell_sl) {
        g_last_sell_entry = se; g_last_sell_sl = ss;
        if(g_sell_setup.active) KillSetup(g_sell_setup, "Zone Sell thay đổi");
        if(se > 0 && ss > 0 && se != EMPTY_VALUE && ss != EMPTY_VALUE)
            TryCreateSetup(g_sell_setup, -1, se, ss);
        SaveState();
    }
}

// ==================================================================
// HUỶ LỆNH CHỜ QUANH GIỜ TIN
// ==================================================================
void CleanPendingOrdersForNews() {
    if(!IsInNewsWindow()) return;
    bool deleted = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong t = OrderGetTicket(i);
        if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(OrderGetInteger(ORDER_MAGIC))) continue;
        if(trade.OrderDelete(t)) deleted = true;
    }
    if(deleted) {
        for(int i = 0; i < 2; i++) { g_buy_setup.lvl[i].ticket = 0; g_sell_setup.lvl[i].ticket = 0; }
        Notify("⚠️ <b>GIỜ TIN</b>\nĐã huỷ lệnh chờ trong khung giờ tin ("
            + IntegerToString(Inp_NewsBufferMinutes) + " phút trước/sau). Sẽ đặt lại sau khi qua giờ tin.");
    }
}

// ==================================================================
// FLEX TP (port từ BOT_TLS)
// ==================================================================
void CheckFlexTP() {
    if(!Inp_FlexTP_Enabled) return;
    double pip = GetPipSize(_Symbol);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return;
    double buy_usd = 0, sell_usd = 0, buy_pips = 0, sell_pips = 0;
    int buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long   type = PositionGetInteger(POSITION_TYPE);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double usd  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)
                    + PositionGetDouble(POSITION_COMMISSION);
        double cur  = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double pips = (type == POSITION_TYPE_BUY) ? (cur - open) / pip : (open - cur) / pip;
        if(type == POSITION_TYPE_BUY) { buy_usd += usd; buy_pips += pips; buy_cnt++; }
        else                          { sell_usd += usd; sell_pips += pips; sell_cnt++; }
    }
    if(buy_cnt == 0 && sell_cnt == 0) return;
    double all_usd  = buy_usd + sell_usd;
    double all_pips = buy_pips + sell_pips;
    double pct_all  = all_usd  / balance * 100.0;
    double pct_buy  = buy_usd  / balance * 100.0;
    double pct_sell = sell_usd / balance * 100.0;
    bool close_all  = (Inp_FlexTP_Percent > 0 && pct_all  >= Inp_FlexTP_Percent)
                   || (Inp_FlexTP_Pips    > 0 && all_pips >= Inp_FlexTP_Pips);
    bool close_buy  = !close_all && buy_cnt > 0
                   && ((Inp_FlexTP_Percent > 0 && pct_buy  >= Inp_FlexTP_Percent)
                    || (Inp_FlexTP_Pips    > 0 && buy_pips >= Inp_FlexTP_Pips));
    bool close_sell = !close_all && sell_cnt > 0
                   && ((Inp_FlexTP_Percent > 0 && pct_sell  >= Inp_FlexTP_Percent)
                    || (Inp_FlexTP_Pips    > 0 && sell_pips >= Inp_FlexTP_Pips));
    if(!close_all && !close_buy && !close_sell) return;
    bool any = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        bool do_close = close_all || (close_buy && type == POSITION_TYPE_BUY)
                                  || (close_sell && type == POSITION_TYPE_SELL);
        if(!do_close) continue;
        if(trade.PositionClose(t)) any = true;
        else {
            uint rc = trade.ResultRetcode();
            if(IsRetryableRetcode(rc)) QueueCloseRetry(t, "FLEX_TP");
        }
    }
    if(any) {
        string dir = close_all ? "BUY+SELL" : (close_buy ? "BUY" : "SELL");
        double usd = close_all ? all_usd : (close_buy ? buy_usd : sell_usd);
        Notify("🏆 <b>FLEX TP</b>\n📊 " + dir + ": +" + DoubleToString(usd, 2) + "$\n"
            + "💳 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$");
    }
}

// ==================================================================
// POOL SL (port từ BOT_TLS)
// ==================================================================
void CheckPoolSL() {
    if(Inp_Pool_SL_Percent <= 0) return;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return;
    double limit_usd = balance * (Inp_Pool_SL_Percent / 100.0);
    double buy_pnl = 0, sell_pnl = 0;
    int buy_cnt = 0, sell_cnt = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)
                   + PositionGetDouble(POSITION_COMMISSION);
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { buy_pnl += pnl; buy_cnt++; }
        else                                                        { sell_pnl += pnl; sell_cnt++; }
    }
    bool close_buy  = (buy_cnt  > 0 && buy_pnl  <= -limit_usd);
    bool close_sell = (sell_cnt > 0 && sell_pnl <= -limit_usd);
    if(!close_buy && !close_sell) return;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        if((close_buy && type == POSITION_TYPE_BUY) || (close_sell && type == POSITION_TYPE_SELL)) {
            if(!trade.PositionClose(t)) {
                uint rc = trade.ResultRetcode();
                if(IsRetryableRetcode(rc)) QueueCloseRetry(t, "POOL_SL");
            }
        }
    }
    if(close_buy)  Notify("🛑 <b>POOL SL: ĐÓNG TẬP LỆNH BUY</b>\n💸 Lỗ "
                     + DoubleToString(buy_pnl, 2) + "$ (ngưỡng " + DoubleToString(Inp_Pool_SL_Percent, 1) + "%)");
    if(close_sell) Notify("🛑 <b>POOL SL: ĐÓNG TẬP LỆNH SELL</b>\n💸 Lỗ "
                     + DoubleToString(sell_pnl, 2) + "$ (ngưỡng " + DoubleToString(Inp_Pool_SL_Percent, 1) + "%)");
}

// ==================================================================
// SỰ KIỆN GIAO DỊCH: báo đóng lệnh + kéo BE cho lệnh còn lại cùng setup
// ==================================================================
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result) {
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    if(!HistoryDealSelect(trans.deal)) return;
    // Log thô để soi khi nhánh này không chạy tới nơi (bật Inp_Debug). Nghi ngờ chính:
    // deal do server sinh ra khi chạm SL/TP có thể không mang magic của EA.
    DebugLog("DEAL", StringFormat("deal=%I64u pos=%I64d magic=%I64d entry=%d reason=%d",
        trans.deal,
        HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID),
        HistoryDealGetInteger(trans.deal, DEAL_MAGIC),
        (int)HistoryDealGetInteger(trans.deal, DEAL_ENTRY),
        (int)HistoryDealGetInteger(trans.deal, DEAL_REASON)));
    if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
    if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
    if(!IsMyMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC))) return;

    ulong pos_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
    double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
               + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
               + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
    long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

    int idx = FindTradeRec(pos_id);
    double rr = 0;
    int    group_id = -1;
    int    level    = -1;
    if(idx >= 0) {
        g_trades[idx].realized_pnl += pnl;
        if(g_trades[idx].risk_money > 0) rr = g_trades[idx].realized_pnl / g_trades[idx].risk_money;
        group_id = g_trades[idx].group_id;
        level    = g_trades[idx].level;
    }

    string reason_str = "👤 Đóng tay / bị ép đóng";
    if(reason == DEAL_REASON_SL)     reason_str = "🔴 Chạm Stop Loss";
    if(reason == DEAL_REASON_TP)     reason_str = "✅ Chạm Take Profit";
    if(reason == DEAL_REASON_EXPERT) reason_str = "🤖 Bot tự đóng (FlexTP / PoolSL / Lá chắn)";

    Notify("🏁 <b>ĐÓNG LỆNH</b>\n━━━━━━━━━━━━━━━\n"
        + "📝 <b>Lý do:</b> " + reason_str + "\n"
        + (level >= 0 ? ("📍 <b>Mốc:</b> " + IntegerToString(level + 1) + "\n") : "")
        + "📊 <b>RR:</b> " + DoubleToString(rr, 2) + "R\n"
        + "💰 <b>PnL:</b> " + DoubleToString(pnl, 2) + "$\n"
        + "💳 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$");

    // Lệnh nào ăn TP trước -> huỷ lệnh chờ còn lại + kéo BE. Đây chỉ là đường phát hiện
    // NHANH; đường chính nằm trong SyncTradeRecords (dò theo lịch sử mỗi tick) nên dù
    // nhánh này không chạy tới nơi thì kết quả vẫn đúng, chỉ chậm hơn 1 tick.
    if(reason == DEAL_REASON_TP && group_id >= 0) HandleGroupTP(group_id, pos_id);

    if(idx >= 0 && !PositionSelectByTicket(pos_id)) RemoveTradeRec(idx);
}

// ==================================================================
// TELEGRAM: LỆNH ĐIỀU KHIỂN
// ==================================================================
void SendStatusMessage() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    int buy_cnt = 0, sell_cnt = 0, pend_cnt = 0;
    double buy_pnl = 0, sell_pnl = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)
                   + PositionGetDouble(POSITION_COMMISSION);
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { buy_cnt++; buy_pnl += pnl; }
        else { sell_cnt++; sell_pnl += pnl; }
    }
    for(int i = 0; i < OrdersTotal(); i++) {
        ulong t = OrderGetTicket(i);
        if(t && OrderGetString(ORDER_SYMBOL) == _Symbol && IsMyMagic(OrderGetInteger(ORDER_MAGIC))) pend_cnt++;
    }
    string bot_st = g_cmd_paused ? "⏸ TẠM DỪNG"
                  : (g_trading_stopped_today ? "🛑 ĐÃ DỪNG (lá chắn)" : "✅ ĐANG CHẠY");
    string trend_st = (SMC_TREND.current_major_trend == 1) ? "TĂNG"
                    : (SMC_TREND.current_major_trend == -1 ? "GIẢM" : "CHƯA RÕ");
    string buy_zone = g_buy_setup.active
        ? (DoubleToString(g_buy_setup.zone_entry, _Digits) + " – " + DoubleToString(g_buy_setup.zone_sl, _Digits))
        : "không có";
    string sell_zone = g_sell_setup.active
        ? (DoubleToString(g_sell_setup.zone_entry, _Digits) + " – " + DoubleToString(g_sell_setup.zone_sl, _Digits))
        : "không có";
    Notify("📊 <b>TRẠNG THÁI BOT — " + _Symbol + "</b>\n━━━━━━━━━━━━━━━\n"
        + "🤖 <b>Bot:</b> " + bot_st + "\n"
        + "📈 <b>Xu hướng " + TFName(Inp_Trend_Timeframe) + ":</b> " + trend_st + "\n"
        + "🟩 <b>Zone Buy:</b> " + buy_zone + "\n"
        + "🟥 <b>Zone Sell:</b> " + sell_zone + "\n"
        + "━━━━━━━━━━━━━━━\n"
        + "💰 <b>Balance:</b> " + DoubleToString(balance, 2) + "$\n"
        + "📈 <b>Equity:</b> "  + DoubleToString(equity, 2) + "$\n"
        + "📦 <b>Đang mở:</b> Buy " + IntegerToString(buy_cnt) + " (" + DoubleToString(buy_pnl, 2) + "$)"
        + " | Sell " + IntegerToString(sell_cnt) + " (" + DoubleToString(sell_pnl, 2) + "$)\n"
        + "⏳ <b>Lệnh chờ:</b> " + IntegerToString(pend_cnt) + "\n"
        + "🔎 " + (g_filter_text == "" ? "—" : g_filter_text));
}

void SendConfigMessage() {
    string risk_str = UseRiskPerTrade ? (DoubleToString(RiskPercent, 2) + "%/lệnh")
                                      : ("Lot cố định " + DoubleToString(FixedLotSize, 2));
    Notify("⚙️ <b>CẤU HÌNH BOT — " + _Symbol + "</b>\n━━━━━━━━━━━━━━━\n"
        + "🔢 <b>Magic:</b> " + IntegerToString(Inp_BaseMagicNumber + 1) + " / "
                              + IntegerToString(Inp_BaseMagicNumber + 2) + "\n"
        + "⏱ <b>T-L-S:</b> T=" + TFName(Inp_Trend_Timeframe)
             + " | Zone=" + TFName(Inp_Zone_Timeframe)
             + " | Nến=" + EnumToString(Inp_Signal_Mode) + "\n"
        + "🚦 <b>Lọc xu hướng:</b> " + (Inp_Enable_Trend_Filter ? "BẬT" : "TẮT") + "\n"
        + "━━━━━━━━━━━━━━━\n"
        + "📍 <b>Mốc 1:</b> " + (Inp_Use_Level1 ? (DoubleToString(Inp_Level1_Pct, 0) + "% Zone, TP "
                                 + DoubleToString(Inp_TP1_Pips, 0) + " pips") : "TẮT") + "\n"
        + "📍 <b>Mốc 2:</b> " + (Inp_Use_Level2 ? (DoubleToString(Inp_Level2_Pct, 0) + "% Zone, TP "
                                 + DoubleToString(Inp_TP2_Pips, 0) + " pips") : "TẮT") + "\n"
        + "🛡️ <b>SL:</b> thang 30-50 pips + nới " + DoubleToString(Inp_SL_Extra_Pips, 0) + " pips"
             + (Inp_SL_RoundInteger ? " (có làm tròn)" : "") + "\n"
        + "━━━━━━━━━━━━━━━\n"
        + "💵 <b>Rủi ro:</b> " + risk_str + "\n"
        + "📦 <b>Trần lệnh rủi ro:</b> " + IntegerToString(Inp_Max_Risk_Trades) + "\n"
        + "🛡 <b>Lỗ ngày:</b> " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%"
             + " | <b>Lãi ngày:</b> " + (Inp_DailyProfitLimit > 0 ? DoubleToString(Inp_DailyProfitLimit, 1) + "%" : "tắt") + "\n"
        + "🏆 <b>Mục tiêu equity:</b> " + (Inp_AutoPassTarget > 0 ? DoubleToString(Inp_AutoPassTarget, 0) + "$" : "tắt") + "\n"
        + "🌀 <b>Pool SL:</b> " + (Inp_Pool_SL_Percent > 0 ? DoubleToString(Inp_Pool_SL_Percent, 1) + "%" : "tắt")
        + " | <b>FlexTP:</b> " + (Inp_FlexTP_Enabled ? "bật" : "tắt") + "\n"
        + "📰 <b>Giờ tin:</b> " + (Inp_NewsTimes == "" ? "không đặt" : Inp_NewsTimes)
        + " (±" + IntegerToString(Inp_NewsBufferMinutes) + "p)");
}

void ProcessBotCommand(string cmd) {
    int at = StringFind(cmd, "@");
    if(at > 0) cmd = StringSubstr(cmd, 0, at);
    StringToLower(cmd);

    if(cmd == "/start") {
        g_cmd_paused = false;
        SaveState();
        Notify("✅ <b>BOT ĐÃ BẬT LẠI</b>\nSẵn sàng nhận Zone mới và vào lệnh.");
    }
    else if(cmd == "/stop" || cmd == "/pause") {
        g_cmd_paused = true;
        int cancelled = 0;
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong t = OrderGetTicket(i);
            if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsMyMagic(OrderGetInteger(ORDER_MAGIC))) continue;
            if(trade.OrderDelete(t)) cancelled++;
        }
        for(int i = 0; i < 2; i++) { g_buy_setup.lvl[i].ticket = 0; g_sell_setup.lvl[i].ticket = 0; }
        SaveState();
        Notify("⏸ <b>BOT TẠM DỪNG</b>\n🚫 Không vào lệnh mới\n🗑️ Đã huỷ <b>"
            + IntegerToString(cancelled) + "</b> lệnh chờ\n✅ Lệnh đang chạy vẫn được quản lý\n\n➡️ Gửi /start để tiếp tục");
    }
    else if(cmd == "/closeall") {
        int cp = 0, co = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong t = PositionGetTicket(i);
            if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if(!IsMyMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            if(trade.PositionClose(t)) cp++;
        }
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong t = OrderGetTicket(i);
            if(!t || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsMyMagic(OrderGetInteger(ORDER_MAGIC))) continue;
            if(trade.OrderDelete(t)) co++;
        }
        g_cmd_paused = true;
        SaveState();
        Notify("🔴 <b>ĐÃ ĐÓNG TẤT CẢ</b>\n✅ Đóng " + IntegerToString(cp) + " lệnh\n🗑️ Huỷ "
            + IntegerToString(co) + " lệnh chờ\n⏸ Bot đang TẠM DỪNG\n➡️ Gửi /start để tiếp tục");
    }
    else if(cmd == "/status")  SendStatusMessage();
    else if(cmd == "/config")  SendConfigMessage();
    else if(cmd == "/chart")   Radar.SendPhoto("📸 <b>Chart hiện tại — " + _Symbol + "</b>\n🕐 "
                                   + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
    else if(cmd == "/resetshield") {
        g_trading_stopped_today = false;
        g_account_passed        = false;
        g_shield_stop_reason    = "";
        g_sod_balance           = AccountInfoDouble(ACCOUNT_BALANCE);
        SaveState();
        Notify("🔓 <b>ĐÃ GỠ LÁ CHẮN</b>\nMốc lỗ/lãi ngày tính lại từ balance hiện tại: "
            + DoubleToString(g_sod_balance, 2) + "$");
    }
}

void CheckTelegramCommands() {
    if(MQLInfoInteger(MQL_TESTER)) return;
    if(Inp_BotToken == "" || Inp_BotToken == "YOUR_BOT_TOKEN_HERE" || Inp_ChatID == "") return;
    if(GetTickCount64() - g_tg_last_poll_ms < 3000) return;
    g_tg_last_poll_ms = GetTickCount64();

    string url = "https://api.telegram.org/bot" + Inp_BotToken
               + "/getUpdates?offset=" + (string)(g_tg_last_update_id + 1) + "&limit=10&timeout=0";
    char post[], result[];
    string headers;
    ResetLastError();
    if(WebRequest("GET", url, "", 5000, post, result, headers) != 200) return;

    string json = CharArrayToString(result);
    if(StringFind(json, "\"ok\":true") < 0) return;

    int pos = 0;
    while(true) {
        int uid_pos = StringFind(json, "\"update_id\":", pos);
        if(uid_pos < 0) break;
        int n = uid_pos + 12, n_end = n;
        while(n_end < StringLen(json) && StringGetCharacter(json, n_end) >= '0'
              && StringGetCharacter(json, n_end) <= '9') n_end++;
        long uid = (long)StringSubstr(json, n, n_end - n);
        if(uid > g_tg_last_update_id) g_tg_last_update_id = uid;

        int next_uid = StringFind(json, "\"update_id\":", n_end);
        int blk_end  = (next_uid > 0) ? next_uid : StringLen(json);
        string blk   = StringSubstr(json, uid_pos, blk_end - uid_pos);

        // Lấy "text" CUỐI CÙNG trong khối: nếu tin là reply thì "reply_to_message" lồng
        // vào trước và cũng có field "text" riêng của tin bị reply.
        string text = "";
        int search_from = 0, last_tp = -1;
        while(true) {
            int tp = StringFind(blk, "\"text\":\"", search_from);
            if(tp < 0) break;
            last_tp = tp; search_from = tp + 8;
        }
        if(last_tp >= 0) {
            int ts = last_tp + 8, te = StringFind(blk, "\"", ts);
            if(te > ts) text = StringSubstr(blk, ts, te - ts);
        }

        string chat_id_str = "";
        int cp = StringFind(blk, "\"chat\":{\"id\":");
        if(cp >= 0) {
            int cs = cp + 13, ce = cs;
            if(StringGetCharacter(blk, ce) == '-') ce++;
            while(ce < StringLen(blk) && StringGetCharacter(blk, ce) >= '0'
                  && StringGetCharacter(blk, ce) <= '9') ce++;
            chat_id_str = StringSubstr(blk, cs, ce - cs);
        }

        if(text != "" && chat_id_str == Inp_ChatID) ProcessBotCommand(text);
        pos = blk_end;
    }
}

// Bỏ qua toàn bộ update cũ còn tồn đọng khi EA vừa khởi động.
void SkipPendingTelegramUpdates() {
    if(MQLInfoInteger(MQL_TESTER)) return;
    if(Inp_BotToken == "" || Inp_BotToken == "YOUR_BOT_TOKEN_HERE" || Inp_ChatID == "") return;
    string url = "https://api.telegram.org/bot" + Inp_BotToken + "/getUpdates?offset=-1&limit=1";
    char post[], result[];
    string headers;
    ResetLastError();
    if(WebRequest("GET", url, "", 5000, post, result, headers) != 200) return;
    string json = CharArrayToString(result);
    int uid_pos = StringFind(json, "\"update_id\":");
    if(uid_pos < 0) return;
    int n = uid_pos + 12, n_end = n;
    while(n_end < StringLen(json) && StringGetCharacter(json, n_end) >= '0'
          && StringGetCharacter(json, n_end) <= '9') n_end++;
    long uid = (long)StringSubstr(json, n, n_end - n);
    if(uid > g_tg_last_update_id) g_tg_last_update_id = uid;
}

// ==================================================================
// DASHBOARD
// ==================================================================
void DashLabel(string name, int x, int y, color clr, int fsz, string text) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetString (0, name, OBJPROP_FONT,       "Arial");
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fsz);
    ObjectSetString (0, name, OBJPROP_TEXT,      text);
}

string LevelStateText(SSetup &s, int i) {
    if(!s.active)            return "—";
    if(!s.lvl[i].enabled)    return "tắt";
    if(s.lvl[i].done)        return "đã vào lệnh";
    if(s.lvl[i].ticket != 0) return "đang chờ khớp @" + DoubleToString(s.lvl[i].price, _Digits);
    if(s.lvl[i].armed)       return "chờ nến @" + DoubleToString(s.lvl[i].price, _Digits);
    return "chờ giá tới @" + DoubleToString(s.lvl[i].price, _Digits);
}

void UpdateDashboard() {
    color c_dark = clrBlack, c_gray = C'130,130,130', c_ok = C'0,140,0', c_bad = C'210,0,0';
    string trend_txt = (SMC_TREND.current_major_trend == 1) ? "TĂNG"
                     : (SMC_TREND.current_major_trend == -1 ? "GIẢM" : "CHƯA RÕ");
    color  trend_clr = (SMC_TREND.current_major_trend == 0) ? c_gray
                     : (SMC_TREND.current_major_trend == 1 ? c_ok : c_bad);
    int risk_cnt = CountRiskTrades();

    DashLabel("GCB_D_TITLE", 8, 22, c_dark, 8, "TLS GetChart Bot — " + _Symbol
        + "  (T=" + TFName(Inp_Trend_Timeframe) + " / Zone=" + TFName(Inp_Zone_Timeframe) + ")");
    DashLabel("GCB_D_TREND", 8, 40, trend_clr, 8, "Xu hướng: " + trend_txt
        + "   |   " + SMC_TREND.current_market_phase);
    DashLabel("GCB_D_ZONE",  8, 58, c_dark, 7, "Zone " + TFName(Inp_Zone_Timeframe) + ": "
        + (g_buy_setup.active  ? ("BUY " + DoubleToString(g_buy_setup.zone_entry, _Digits) + "–" + DoubleToString(g_buy_setup.zone_sl, _Digits)) : "BUY —")
        + "   " + (g_sell_setup.active ? ("SELL " + DoubleToString(g_sell_setup.zone_entry, _Digits) + "–" + DoubleToString(g_sell_setup.zone_sl, _Digits)) : "SELL —"));
    DashLabel("GCB_D_B1", 8, 78, c_dark, 7, "BUY  mốc1: " + LevelStateText(g_buy_setup, 0));
    DashLabel("GCB_D_B2", 8, 93, c_dark, 7, "BUY  mốc2: " + LevelStateText(g_buy_setup, 1));
    DashLabel("GCB_D_S1", 8, 111, c_dark, 7, "SELL mốc1: " + LevelStateText(g_sell_setup, 0));
    DashLabel("GCB_D_S2", 8, 126, c_dark, 7, "SELL mốc2: " + LevelStateText(g_sell_setup, 1));

    string shield_txt = g_cmd_paused ? "TẠM DỪNG"
                      : (g_trading_stopped_today ? "ĐÃ DỪNG: " + g_shield_stop_reason : "BÌNH THƯỜNG");
    color  shield_clr = (g_cmd_paused || g_trading_stopped_today) ? c_bad : c_ok;
    DashLabel("GCB_D_SHIELD", 8, 146, shield_clr, 7, "Lá chắn: " + shield_txt
        + "   |   Rủi ro: " + IntegerToString(risk_cnt) + "/" + IntegerToString(Inp_Max_Risk_Trades));
    DashLabel("GCB_D_FILTER", 8, 161, c_gray, 7, (g_filter_text == "") ? " " : g_filter_text);
}

void DeleteDashboard() {
    string names[] = {"GCB_D_TITLE","GCB_D_TREND","GCB_D_ZONE","GCB_D_B1","GCB_D_B2",
                      "GCB_D_S1","GCB_D_S2","GCB_D_SHIELD","GCB_D_FILTER"};
    for(int i = 0; i < ArraySize(names); i++) ObjectDelete(0, names[i]);
}

// ==================================================================
// VÒNG ĐỜI EA
// ==================================================================
int OnInit() {
    trade.SetDeviationInPoints(Inp_Slippage_Points);
    Radar.Init(Inp_BotToken, Inp_ChatID, Inp_SendScreenshot);

    // showMinor = false ở cả 2 engine: bot chỉ dùng cấu trúc Major nên không vẽ gì của Minor
    // (engine vẫn tính Minor bên trong, đó là code sẵn có của thư viện dùng chung).
    bool draw_trend = (Inp_Draw_Mode == VE_KHUNG_TREND || Inp_Draw_Mode == VE_CA_HAI);
    bool draw_zone  = (Inp_Draw_Mode == VE_KHUNG_ZONE  || Inp_Draw_Mode == VE_CA_HAI);

    SMC_TREND.Init(_Symbol, Inp_Trend_Timeframe, "GCB_TREND_", true, false, draw_trend,
        CLR_BUY_ZONE, CLR_SELL_ZONE, CLR_KEY_LEVEL, CLR_BOS_UP, CLR_BOS_DN, clrNONE, clrNONE,
        Inp_Trend_MajorSwing, MINOR_SWING, MAX_ZONES, MAX_BOS, MAX_MBOS);
    SMC_ZONE.Init(_Symbol, Inp_Zone_Timeframe, "GCB_ZONE_", false, false, draw_zone,
        CLR_BUY_ZONE, CLR_SELL_ZONE, CLR_KEY_LEVEL, CLR_BOS_UP, CLR_BOS_DN, clrNONE, clrNONE,
        Inp_Zone_MajorSwing, MINOR_SWING, MAX_ZONES, MAX_BOS, MAX_MBOS);

    g_buy_setup.active  = false; g_buy_setup.dir  = 1;
    g_sell_setup.active = false; g_sell_setup.dir = -1;

    LoadState();
    if(g_sod_balance <= 0) {
        g_sod_balance      = AccountInfoDouble(ACCOUNT_BALANCE);
        g_last_day_checked = iTime(_Symbol, PERIOD_D1, 0);
    }
    SyncTradeRecords();
    SkipPendingTelegramUpdates();

    // Nạp dữ liệu ngay lần đầu để dashboard có số liệu, và ghi mốc Zone hiện có.
    SMC_TREND.Update();
    SMC_ZONE.Update();
    ProcessZones();
    g_last_trend_bar = iTime(_Symbol, Inp_Trend_Timeframe, 0);
    g_last_zone_bar  = iTime(_Symbol, Inp_Zone_Timeframe, 0);

    EventSetMillisecondTimer(100);

    Notify("🟢 <b>TLS GETCHART BOT v1.0 KHỞI ĐỘNG</b>\n━━━━━━━━━━━━━━━\n"
        + "💰 <b>Balance:</b> " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n"
        + "⚙️ <b>T-L-S:</b> " + _Symbol + " | T=" + TFName(Inp_Trend_Timeframe)
        + " | Zone=" + TFName(Inp_Zone_Timeframe) + " | Nến=" + EnumToString(Inp_Signal_Mode) + "\n"
        + "🛡️ <b>Lỗ ngày:</b> " + DoubleToString(Inp_DailyDrawdownLimit, 1) + "%"
        + " | <b>Rủi ro:</b> " + (UseRiskPerTrade ? DoubleToString(RiskPercent, 2) + "%/lệnh"
                                                  : DoubleToString(FixedLotSize, 2) + " lot"));
    Print(PFX, " Đã nạp bot. Magic ", Inp_BaseMagicNumber + 1, "/", Inp_BaseMagicNumber + 2);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    EventKillTimer();
    SaveState();
    DeleteDashboard();
    DeleteSetupLines(1);
    DeleteSetupLines(-1);
    ObjectsDeleteAll(0, "GCB_TREND_");
    ObjectsDeleteAll(0, "GCB_ZONE_");
}

void OnTimer() {
    ProcessCloseRetryQueue();
    CheckTelegramCommands();
}

void OnTick() {
    ManagePropFirmRules();
    CleanPendingOrdersForNews();
    CheckFlexTP();
    CheckPoolSL();
    SyncTradeRecords();
    CheckVirtualSL();   // chốt chặn khi SL trên sàn không nổ

    ProcessSetupTick(g_buy_setup);
    ProcessSetupTick(g_sell_setup);

    if(IsNewBarTF(Inp_Trend_Timeframe, g_last_trend_bar)) SMC_TREND.Update();

    if(IsNewBarTF(Inp_Zone_Timeframe, g_last_zone_bar)) {
        SMC_ZONE.Update();
        ProcessZones();                 // phát hiện Zone mới -> tạo setup
        ProcessSetupBar(g_buy_setup);   // xét nến xác nhận / đặt lại lệnh chờ
        ProcessSetupBar(g_sell_setup);
    }

    UpdateDashboard();
}

// Đường Tracking (Protected / Active High-Low) của engine là tia kéo tới mép phải chart,
// nên phải vẽ lại mỗi khi người dùng cuộn/phóng to chart — y như BOT_TLS làm với SMC_HTF.
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id != CHARTEVENT_CHART_CHANGE) return;
    if(Inp_Draw_Mode == VE_KHUNG_ZONE  || Inp_Draw_Mode == VE_CA_HAI)  SMC_ZONE.HandleChartEvent();
    if(Inp_Draw_Mode == VE_KHUNG_TREND || Inp_Draw_Mode == VE_CA_HAI)  SMC_TREND.HandleChartEvent();
}
//+------------------------------------------------------------------+
