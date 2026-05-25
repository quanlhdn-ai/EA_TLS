//+------------------------------------------------------------------+
//|                                               Telegram_Radar.mqh |
//|                                      Focus: Bulletproof API GET  |
//|                                      Status: Final Stable V5     |
//+------------------------------------------------------------------+
class CTelegramRadar
{
private:
    string m_token;
    string m_chat_id;
    bool   m_send_photo;

    // Hàm mã hóa URL chuẩn (Băm chuỗi sang UTF-8)
    string UrlEncode(string str) {
       string res = "";
       uchar bytes[];
       int len = StringToCharArray(str, bytes, 0, WHOLE_ARRAY, CP_UTF8);
       
       for(int i=0; i<len-1; i++) {
          uchar b = bytes[i];
          if( (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') ) {
             res += CharToString((ushort)b);
          } else {
             res += StringFormat("%%%02X", b);
          }
       }
       return res;
    }

public:
    // Khởi tạo Radar
    void Init(string token, string chat_id, bool send_photo) {
        m_token = token;
        m_chat_id = chat_id;
        m_send_photo = send_photo;
    }

    // Hàm gửi tin nhắn văn bản (DÙNG PHƯƠNG THỨC 'GET' BẤT BẠI)
    void SendMessage(string message) {
       if(m_token == "" || m_token == "YOUR_BOT_TOKEN_HERE" || m_chat_id == "") return;
       
       // Đẩy thẳng mọi tham số vào thanh URL (Giống hệt gõ link trên trình duyệt Web)
       string url = "https://api.telegram.org/bot" + m_token + 
                    "/sendMessage?chat_id=" + m_chat_id + 
                    "&text=" + UrlEncode(message) + 
                    "&parse_mode=HTML";
       
       char data[], result[]; 
       string headers;
       
       ResetLastError();
       // Gọi lệnh GET, mảng data[] để trống. An toàn tuyệt đối!
       int res = WebRequest("GET", url, "", 5000, data, result, headers);
       
       if(res != 200) {
           Print("TELEGRAM GET ERROR: Code ", res, " | Error: ", GetLastError());
           if(ArraySize(result) > 0) Print("Telegram Response: ", CharArrayToString(result));
       }
    }

    // Hàm gửi tin nhắn kèm ảnh (GIỮ NGUYÊN HÀM CHUẨN CỦA ANH)
    bool SendMessageWithPhoto(string caption) {
       if(!m_send_photo) { 
           SendMessage(caption); 
           return true; 
       }
       
       if(m_token == "" || m_token == "YOUR_BOT_TOKEN_HERE" || m_chat_id == "") return false;
       
       string filename = "TLS_Shot_" + IntegerToString(MathRand()) + ".png";
       ChartScreenShot(0, filename, 1280, 720, ALIGN_RIGHT); 
       Sleep(200);
       
       int handle = FileOpen(filename, FILE_READ|FILE_BIN);
       if(handle == INVALID_HANDLE) {
           SendMessage(caption); // Nếu không chụp được ảnh, lùi về gửi Text
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
           SendMessage(caption); // Nếu ảnh gửi xịt, lùi về gửi Text
       }
       return (res == 200);
    }
};
//+------------------------------------------------------------------+