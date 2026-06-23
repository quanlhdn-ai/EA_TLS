//+------------------------------------------------------------------+
//|                                            Telegram_ChartBot.mqh |
//|                     Chỉ dùng để gửi tin nhắn & ảnh chụp chart    |
//|                     (không liên quan tới module giao dịch)      |
//+------------------------------------------------------------------+
class CTelegramChartBot
{
private:
    string m_token;
    string m_chat_id;

    // Group/chat bị Telegram tự nâng cấp thành supergroup -> chat_id cũ bị đổi vĩnh viễn,
    // API trả lỗi 400 kèm "migrate_to_chat_id" báo ID mới. In cảnh báo dễ hiểu thay vì để
    // lỗi JSON khó đọc, tránh phải dò log thủ công như group AnhTuan_GuiChartMT5_Bot từng gặp.
    void CheckMigratedChat(string response) {
       int p = StringFind(response, "\"migrate_to_chat_id\":");
       if(p < 0) return;
       int s = p + 21, e = s;
       if(StringGetCharacter(response, e) == '-') e++;
       while(e < StringLen(response) && StringGetCharacter(response, e) >= '0' && StringGetCharacter(response, e) <= '9') e++;
       string new_id = StringSubstr(response, s, e - s);
       Print("[CẢNH BÁO] Group/chat đã được Telegram nâng cấp thành supergroup — chat_id cũ '", m_chat_id,
             "' không còn dùng được nữa. Hãy đổi input Inp_ChatID thành chat_id mới: ", new_id);
    }

    // Mã hóa URL chuẩn (Băm chuỗi sang UTF-8)
    string UrlEncode(string str) {
       string res = "";
       uchar bytes[];
       int len = StringToCharArray(str, bytes, 0, WHOLE_ARRAY, CP_UTF8);

       for(int i = 0; i < len - 1; i++) {
          uchar b = bytes[i];
          if((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')) {
             res += CharToString((ushort)b);
          } else {
             res += StringFormat("%%%02X", b);
          }
       }
       return res;
    }

public:
    void Init(string token, string chat_id) {
        m_token   = token;
        m_chat_id = chat_id;
    }

    bool IsConfigured() {
        return (m_token != "" && m_token != "YOUR_BOT_TOKEN_HERE" && m_chat_id != "");
    }

    // Gửi tin nhắn văn bản (POST — không bị giới hạn độ dài như URL GET)
    // reply_markup_json: chuỗi JSON tùy chọn (ví dụ custom keyboard) — để trống nếu không cần.
    void SendMessage(string message, string reply_markup_json = "") {
       if(!IsConfigured()) return;

       string url  = "https://api.telegram.org/bot" + m_token + "/sendMessage";
       string body = "chat_id=" + m_chat_id + "&parse_mode=HTML&text=" + UrlEncode(message);
       if(reply_markup_json != "") body += "&reply_markup=" + UrlEncode(reply_markup_json);

       char data[], result[];
       string headers;
       int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
       ArrayResize(data, len - 1);

       string req_headers = "Content-Type: application/x-www-form-urlencoded\r\n";

       ResetLastError();
       int res = WebRequest("POST", url, req_headers, 5000, data, result, headers);

       if(res != 200) {
           Print("TELEGRAM SENDMESSAGE ERROR: Code ", res, " | Error: ", GetLastError());
           if(ArraySize(result) > 0) {
               string resp = CharArrayToString(result);
               Print("Telegram Response: ", resp);
               CheckMigratedChat(resp);
           }
       }
    }

    // Chart vừa đổi symbol/period hoặc vừa gắn lại indicator có thể tạm thời
    // chưa "rep" kịp, ChartScreenShot trả lỗi 4102 (ERR_CHART_NO_REPLY) — thử lại.
    bool ChartScreenShotRetry(long chart_id, string filename, int width, int height, int max_tries = 6, int delay_ms = 400) {
       for(int i = 0; i < max_tries; i++) {
          ResetLastError();
          if(ChartScreenShot(chart_id, filename, width, height, ALIGN_RIGHT)) return true;
          int err = GetLastError();
          if(err != 4102) { Print("CHART SCREENSHOT ERROR: ", err); return false; }
          Sleep(delay_ms);
       }
       Print("CHART SCREENSHOT vẫn lỗi 4102 sau ", max_tries, " lần thử.");
       return false;
    }

    // Chụp ảnh 1 chart cụ thể (theo chart_id) rồi gửi lên Telegram
    bool SendPhoto(long chart_id, string caption, int width, int height) {
       if(!IsConfigured()) return false;

       string filename = "TLS_ChartSnapshot_" + IntegerToString(MathRand()) + ".png";
       if(!ChartScreenShotRetry(chart_id, filename, width, height)) {
           SendMessage(caption);
           return false;
       }
       Sleep(200);

       int handle = FileOpen(filename, FILE_READ | FILE_BIN);
       if(handle == INVALID_HANDLE) {
           SendMessage(caption); // Không chụp được ảnh → lùi về gửi Text
           return false;
       }

       ulong fileSize = FileSize(handle);
       uchar photoData[];
       ArrayResize(photoData, (int)fileSize);
       FileReadArray(handle, photoData);
       FileClose(handle);
       FileDelete(filename);

       string boundary = "----WebKitFormBoundary" + IntegerToString(MathRand());
       string rn = "\r\n";

       string header = "--" + boundary + rn + "Content-Disposition: form-data; name=\"chat_id\"" + rn + rn + m_chat_id + rn;
       header += "--" + boundary + rn + "Content-Disposition: form-data; name=\"parse_mode\"" + rn + rn + "HTML" + rn;
       header += "--" + boundary + rn + "Content-Disposition: form-data; name=\"caption\"" + rn + rn + caption + rn;
       header += "--" + boundary + rn + "Content-Disposition: form-data; name=\"photo\"; filename=\"chart.png\"" + rn + "Content-Type: image/png" + rn + rn;

       string footer = rn + "--" + boundary + "--" + rn;

       uchar headerBytes[], footerBytes[], finalData[];
       StringToCharArray(header, headerBytes, 0, WHOLE_ARRAY, CP_UTF8);
       StringToCharArray(footer, footerBytes, 0, WHOLE_ARRAY, CP_UTF8);

       int hL = ArraySize(headerBytes) - 1;
       int fL = ArraySize(footerBytes) - 1;

       ArrayResize(finalData, hL + ArraySize(photoData) + fL);
       ArrayCopy(finalData, headerBytes, 0, 0, hL);
       ArrayCopy(finalData, photoData, hL, 0, ArraySize(photoData));
       ArrayCopy(finalData, footerBytes, hL + ArraySize(photoData), 0, fL);

       string url = "https://api.telegram.org/bot" + m_token + "/sendPhoto";
       string req_headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
       char result[]; string resHeaders;

       ResetLastError();
       int res = WebRequest("POST", url, req_headers, 10000, finalData, result, resHeaders);

       if(res != 200) {
           Print("TELEGRAM PHOTO ERROR: Code ", res, " | Error: ", GetLastError());
           if(ArraySize(result) > 0) {
               string resp = CharArrayToString(result);
               Print("Telegram Response: ", resp);
               CheckMigratedChat(resp);
           }
           SendMessage(caption);
       }
       return (res == 200);
    }
};
//+------------------------------------------------------------------+
