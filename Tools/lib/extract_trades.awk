# extract_trades.awk — tai dung TUNG LENH tu log agent cua MT5 Strategy Tester.
#
# Dung cho moi EA vao lenh thi truong co SL/TP va dong lenh bang SL/TP.
#   - dong yeu cau  "market buy|sell LOT SYMBOL sl: S tp: T"             -> SL/TP BAN DAU
#   - dong khop     "deal #D dir LOT SYMBOL at P done (based on order #O)" ngay sau
#                                                                          -> lenh vao, O = so vi the
#   - dong kich hoat "(stop loss|take profit) triggered #O ... [#C ...]" -> lenh #C se dong vi the O
#   - dong khop cua lenh #C                                               -> gia KHOP THAT va gio dong
#   - dong EA tu dong "market sell LOT SYMBOL, close #P (...)" + dong khop -> dong MOT PHAN / toan bo
#
# Moi vi the ra MOT dong: lot = lot luc vao, close = gia dong BINH QUAN theo khoi luong cua moi lan
# dong (chot mot phan + phan con lai dinh SL/TP). Nhu vay (close - open) x lot x CS = lai that.
# Truoc ban nay phan dong mot phan bi bo qua: luot chot 50% @2R ra so lieu Y HET luot khong chot.
# reason: SL / TP (phan cuoi dong bang SL/TP) hoac EA (EA tu dong het); partial = so lan dong mot phan.
#
# Vi sao lay gia khop that: lenh dinh SL qua dem / cuoi tuan bi truot gia. Lay gia SL yeu cau
# thi tong lai lech ~12% so voi tester (do duoc tren BOT_TLS, 3.722 lenh).
# Dong "CTrade::OrderSend: market ..." va "failed market ..." KHONG khop vi regex neo ngay sau gio.
# Lenh dong vi ly do khac (EA tu dong, het ky test) KHONG duoc ghi — xem dong thong ke cuoi.
#
# Dau ra (stdout): CSV; dong cuoi bat dau bang '#' la thong ke doi chieu.
function emit(p, ctime, reason, slc) {
  printf "%s,%s,%s,%s,%s,%s,%s,%s,%.5f,%s,%s,%d\n", p, ot[p], od[p], ol[p], op[p], osl[p], otp[p], ctime, wsum[p] / lsum[p], reason, slc, npart[p]
  n_out++; if (npart[p]) n_partpos++
  delete ot[p]
}
BEGIN { OFS = ","; print "pos,open_time,dir,lot,open,sl0,tp0,close_time,close,reason,sl_at_close,partial" }
{
  n = split($0, f, "\t"); msg = f[n]
  if (match(msg, /^([0-9.]+ [0-9:]+)   market (buy|sell) ([0-9.]+) [A-Za-z0-9._#+-]+ sl: ([0-9.]+) tp: ([0-9.]+)/, m)) {
    pend = 1; psl = m[4]; ptp = m[5]; next
  }
  if (match(msg, /^([0-9.]+ [0-9:]+)   market (buy|sell) ([0-9.]+) [A-Za-z0-9._#+-]+, close #([0-9]+) /, m)) {
    pclose = m[4]; next
  }
  if (match(msg, /^([0-9.]+ [0-9:]+)   (stop loss|take profit) triggered #([0-9]+) (buy|sell) [0-9.]+ [A-Za-z0-9._#+-]+ [0-9.]+ sl: ([0-9.]+) tp: [0-9.]+ \[#([0-9]+) (buy|sell) [0-9.]+ [A-Za-z0-9._#+-]+ at ([0-9.]+)\]/, m)) {
    if (!(m[3] in ot)) { unmatched++; next }
    c = m[6]; cpos[c] = m[3]; creason[c] = (m[2] == "stop loss" ? "SL" : "TP"); csl[c] = m[5]; next
  }
  if (match(msg, /^([0-9.]+ [0-9:]+)   deal #[0-9]+ (buy|sell) ([0-9.]+) [A-Za-z0-9._#+-]+ at ([0-9.]+) done \(based on order #([0-9]+)\)/, m)) {
    o = m[5]
    if (pend) { ot[o] = m[1]; od[o] = m[2]; ol[o] = m[3]; op[o] = m[4]; osl[o] = psl; otp[o] = ptp; rl[o] = m[3]
                wsum[o] = 0; lsum[o] = 0; npart[o] = 0; pend = 0; n_in++ }
    else if (o in cpos) {
      p = cpos[o]; delete cpos[o]
      if (p in ot) { wsum[p] += m[4] * m[3]; lsum[p] += m[3]; emit(p, m[1], creason[o], csl[o]) }
    }
    else if (pclose != "" && (pclose in ot)) {
      p = pclose; wsum[p] += m[4] * m[3]; lsum[p] += m[3]; rl[p] -= m[3]
      if (rl[p] < 1e-6) emit(p, m[1], "EA", "") ; else { npart[p]++; n_part++ }
    }
    pclose = ""
    next
  }
  if (match(msg, /Lai rong=([-0-9.]+)/, m)) net = m[1]
}
END {
  for (p in ot) still++
  printf "#lenh_vao=%d lenh_da_dong=%d (co_chot_mot_phan=%d, lan_chot_mot_phan=%d) chua_dong=%d kich_hoat_khong_khop=%d lai_rong_tester=%s\n", \
         n_in, n_out, n_partpos, n_part, still, unmatched + 0, net
}
