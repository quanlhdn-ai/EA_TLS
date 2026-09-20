# analyze_features.awk — dac diem LUC VAO LENH cua lenh thang lon / thua, va mo phong kich ban.
#
# Cach goi:  gawk -v LOT=0.05 -v CS=100 -v PIP=0.1 -v DEP=10000 -f analyze_features.awk trades.csv features.csv
#   trades.csv   : tu extract_trades.awk (chi dung de lay GIO DONG theo so vi the)
#   features.csv : study_*.csv do BOT_TLS xuat trong Strategy Tester (OnTester -> StudyReport)
#
# Nen chay luot do voi TP RAT DAI va KHONG hoa von (vd TP 10R) de do duoc lenh chay xa bao nhieu.
# Mo phong TP ngan hon la CHINH XAC theo tung lenh: lai noi cao nhat ghi den luc dong la lai noi
# TRUOC khi cham SL, nen MFE >= T nghia la TP T da khop truoc. Chi mo phong duoc T <= TP cua luot do.
# KHONG mo phong duoc to hop TP + hoa von (khong biet cham hoa von truoc hay sau khi cham TP).
#
# Ma khung trong file: chart = khung vao lenh, htf = HTF_Timeframe, trend = Trend_Timeframe, h4, d1.
function pct(x, n) { return (n > 0) ? 100.0 * x / n : 0 }
function outR(k, T) { return (mfe[k] >= T) ? T : act[k] }
function al(k, f) { return (tr[k, f] == dir[k]) ? 1 : 0 }
function co(k, f) { return (tr[k, f] == -dir[k]) ? 1 : 0 }
function alName(k, f) { return al(k, f) ? "thuan " : (co(k, f) ? "nghich" : "chua ro") }
function add(g, k,   j) {
  if (!(g in gn)) order[++ng] = g
  gn[g]++
  if (mfe[k] >= 1) g1[g]++
  if (mfe[k] >= 2) g2[g]++
  if (mfe[k] >= 4) g4[g]++
  for (j = 1; j <= NT; j++) gu[g, j] += outR(k, TPS[j]) * rusd[k] - COST
}
function flush(title,  i, g, j) {
  printf "\n=== %s ===\n", title
  printf "  %-40s %6s %6s %6s %6s |", "nhom", "lenh", ">=1R", ">=2R", ">=4R"
  for (j = 1; j <= NT; j++) printf "  TP%-4s", TPS[j]
  printf "   <- ky vong USD/lenh neu dat TP do\n"
  for (i = 1; i <= ng; i++) { g = order[i]
    printf "  %-40s %6d %5.1f%% %5.1f%% %5.1f%% |", g, gn[g], pct(g1[g], gn[g]), pct(g2[g], gn[g]), pct(g4[g], gn[g])
    for (j = 1; j <= NT; j++) printf " %+6.1f", gu[g, j] / gn[g]
    printf "\n" }
  delete gn; delete g1; delete g2; delete g4; delete gu; delete order; ng = 0
}
# Quyet dinh TP cho tung kich ban (0 = khong vao lenh). Them kich ban: them nhanh o day + ten o BEGIN.
# Khoang trong toi zone doi dien cua khung f, tinh theo R cua lenh (-1 = khong co zone doi dien).
function roomR(k, f,   rp) { rp = risk[k] / PIP; return (room[k, f] > 0 && rp > 0) ? room[k, f] / rp : -1 }
function decideTP(id, k,   sc, d1ok) {
  sc = al(k, 3) + al(k, 4) + al(k, 5)
  d1ok = (roomR(k, 5) < 0 || roomR(k, 5) >= 2)
  if (id == 11) return al(k,5) ? 4 : 0
  if (id == 12) return al(k,5) ? 2 : 0
  if (id == 13) return al(k,5) ? 1.5 : 0
  if (id == 14) return al(k,5) ? 4 : 1.5
  if (id == 15) return al(k,5) ? 4 : (co(k,5) ? 1 : 0)
  if (id == 16) return (al(k,5) && d1ok) ? 4 : 0
  if (id == 17) return (al(k,5) && d1ok) ? 2 : 0
  if (id == 18) return (al(k,5) && d1ok) ? 1.5 : 0
  if (id == 1)  return 4
  if (id == 2)  return 1.5
  if (id == 3)  return 1
  if (id == 4)  return (al(k,5) && al(k,4)) ? 4 : 0
  if (id == 5)  return (al(k,5) && al(k,4)) ? 2 : 0
  if (id == 6)  return (al(k,5) && al(k,4)) ? 4 : 1.5
  if (id == 7)  return (al(k,5) && al(k,4)) ? 4 : ((co(k,5) && co(k,4)) ? 0 : 1.5)
  if (id == 8)  return (sc >= 2) ? 2 : 0
  if (id == 9)  return (sc == 3) ? 4 : 0
  if (id == 10) return (sc == 3) ? 2 : 0
  return 0
}
BEGIN {
  FS = ","; if (LOT == "") LOT = 0.05; if (CS == "") CS = 100; if (PIP == "") PIP = 0.1; if (DEP == "") DEP = 10000
  NT = split("1,1.5,2,3,4,6,10", TPS, ",")
  split("chart,htf,trend,h4,d1", SUF, ",")
  if (COST == "") COST = 0   # USD tru moi lenh (swap + hoa hong). BOT_TLS vang lot 0.05: ~1.4
  NS = 18
  SN[11] = "chi thuan D1, TP 4R"
  SN[12] = "chi thuan D1, TP 2R"
  SN[13] = "chi thuan D1, TP 1.5R"
  SN[14] = "thuan D1 TP 4R, nghich D1 TP 1.5R"
  SN[15] = "thuan D1 TP 4R, nghich D1 TP 1R"
  SN[16] = "thuan D1 + can D1 >=2R/khong co, TP 4R"
  SN[17] = "thuan D1 + can D1 >=2R/khong co, TP 2R"
  SN[18] = "thuan D1 + can D1 >=2R/khong co, TP 1.5R"
  SN[1] = "tat ca lenh, TP 4R"
  SN[2] = "tat ca lenh, TP 1.5R (luot song)"
  SN[3] = "tat ca lenh, TP 1R (luot song)"
  SN[4] = "chi thuan D1+H4, TP 4R"
  SN[5] = "chi thuan D1+H4, TP 2R"
  SN[6] = "thuan D1+H4 TP 4R, con lai TP 1.5R"
  SN[7] = "thuan D1+H4 TP 4R, nghich ca 2 bo, con lai 1.5R"
  SN[8] = ">=2/3 khung H1,H4,D1 thuan, TP 2R"
  SN[9] = "ca H1,H4,D1 thuan, TP 4R"
  SN[10] = "ca H1,H4,D1 thuan, TP 2R"
}
# MT5 FileWrite va .NET WriteAllLines ghi xuong dong CRLF: bo '\r' truoc, neu khong ten cot cuoi
# thanh "room_d1\r" va doc ra 0 ma khong bao loi.
{ sub(/\r$/, "") }
FNR == 1 { if (NR != FNR) for (i = 1; i <= NF; i++) H[$i] = i; next }
/^#/ { next }
NR == FNR { closeT[$1] = $8; next }
{
  k++
  pid[k] = $H["pos_id"]; dir[k] = $H["dir"] + 0; ot[k] = $H["open_time"]
  risk[k] = $H["risk_price"] + 0; mfe[k] = $H["mfe_R"] + 0; act[k] = $H["act_R"] + 0
  rusd[k] = risk[k] * LOT * CS; t1r[k] = $H["t1r_min"] + 0
  for (f = 1; f <= 5; f++) { tr[k, f] = $H["tr_" SUF[f]] + 0; inz[k, f] = $H["inz_" SUF[f]] + 0; room[k, f] = $H["room_" SUF[f]] + 0 }
  ct[k] = (pid[k] in closeT) ? closeT[pid[k]] : ot[k]
}
END {
  n = k; if (n == 0) { print "Khong co du lieu dac diem."; exit }
  for (k = 1; k <= n; k++) { if (pid[k] in closeT) joined++; rsum += rusd[k] }
  printf "Lenh co dac diem=%d | ghep duoc gio dong=%d | 1R trung binh=%.0f USD (lot %s) | phi tru moi lenh=%s USD\n", n, joined, rsum / n, LOT, COST
  for (k = 1; k <= n; k++) add("tat ca", k)
  flush("TONG QUAT — kha nang cham tung moc R, ky vong USD/lenh theo TP")

  for (k = 1; k <= n; k++) add("D1 " alName(k,5) " | H4 " alName(k,4), k)
  flush("THUAN / NGHICH XU HUONG D1 x H4 (theo huong vao lenh)")

  for (k = 1; k <= n; k++) add("so khung thuan trong H1,H4,D1 = " (al(k,3)+al(k,4)+al(k,5)), k)
  flush("MUC DO HOP LUU XU HUONG")

  for (k = 1; k <= n; k++) {
    z = 0
    if (inz[k,3]) { add("gia trong zone cung chieu H1", k); z = 1 }
    if (inz[k,4]) { add("gia trong zone cung chieu H4", k); z = 1 }
    if (inz[k,5]) { add("gia trong zone cung chieu D1", k); z = 1 }
    if (!z) add("khong nam trong zone H1/H4/D1", k)
  }
  flush("HOP LUU ZONE KHUNG LON (1 lenh co the thuoc nhieu nhom)")

  for (f = 4; f <= 5; f++) {
    for (k = 1; k <= n; k++) {
      rp = risk[k] / PIP; rr = (room[k, f] > 0 && rp > 0) ? room[k, f] / rp : -1
      g = (rr < 0) ? "khong co zone doi dien" : (rr < 1 ? "cach can < 1R" : (rr < 2 ? "cach can 1-2R" : (rr < 4 ? "cach can 2-4R" : "cach can >= 4R")))
      add(g, k)
    }
    flush("KHOANG TRONG TOI ZONE DOI DIEN " (f == 4 ? "H4" : "D1") " (tinh theo R cua lenh)")
  }

  for (k = 1; k <= n; k++) {
    t = t1r[k]; g = (t < 0) ? "khong bao gio cham 1R" : (t < 15 ? "cham 1R trong < 15 phut" : (t < 60 ? "cham 1R trong 15-60 phut" : (t < 240 ? "cham 1R trong 1-4 gio" : "cham 1R sau >= 4 gio")))
    add(g, k)
  }
  flush("TOC DO CHAM 1R")

  for (k = 1; k <= n; k++) key[k] = ct[k] sprintf("%07d", k)
  m = asort(key, ks)
  for (j = 1; j <= m; j++) idx[j] = substr(ks[j], length(ks[j]) - 6) + 0
  for (k = 1; k <= n; k++) { allm[substr(ct[k], 1, 7)] = 1; ally[substr(ct[k], 1, 4)] = 1 }
  nm = asorti(allm, mk); nyr = asorti(ally, yk)

  printf "\n=== KICH BAN (thu tu theo gio dong; muc tieu: lai DEU theo thang) ===\n"
  printf "  %-46s %6s %6s %9s %5s | %-15s %6s %6s %8s %7s %6s\n", "kich ban", "lenh", "thang", "net USD", "PF", "thang duong", "am l.t", "thua lt", "te nhat", "sut von", "nam am"
  for (s = 1; s <= NS; s++) {
    delete mu; delete yu; taken = 0; wn = 0; gw = 0; gl = 0; net = 0; cur = 0; mls = 0; bal = DEP; peak = DEP; mdd = 0
    for (j = 1; j <= m; j++) {
      k = idx[j]; T = decideTP(s, k); if (T == 0) continue
      o = outR(k, T); u = o * rusd[k] - COST; taken++; net += u
      if (u > 0) { wn++; gw += u; cur = 0 } else { gl -= u; cur++; if (cur > mls) mls = cur }
      mu[substr(ct[k], 1, 7)] += u; yu[substr(ct[k], 1, 4)] += u
      bal += u; if (bal > peak) peak = bal; else { dd = (peak - bal) / peak; if (dd > mdd) mdd = dd }
    }
    mp = 0; mneg = 0; mlm = 0; worst = 1e18
    for (i = 1; i <= nm; i++) { v = mu[mk[i]] + 0
      if (v > 0) { mp++; mneg = 0 } else if (v < 0) { mneg++; if (mneg > mlm) mlm = mneg } else mneg = 0
      if (v < worst) worst = v }
    yneg = 0; for (i = 1; i <= nyr; i++) { if (yu[yk[i]] + 0 < 0) yneg++; syu[s, i] = yu[yk[i]] + 0 }
    printf "  %2d %-43s %6d %5.1f%% %+9.0f %5.2f | %3d/%-3d (%3.0f%%) %6d %6d %+8.0f %6.1f%% %3d/%-2d\n", s, SN[s], taken, pct(wn, taken), net, (gl > 0 ? gw / gl : 0), mp, nm, pct(mp, nm), mlm, mls, worst, 100 * mdd, yneg, nyr
  }
  printf "  (thang duong/tong so thang cua du lieu; am l.t = thang am lien tiep; thua lt = lenh thua lien tiep; nam am = so nam lich am)\n"

  # Tong nhieu nam de bi MOT nam lon che: loc thuan D1 tren BOT_TLS dan +45.8k / 43 thang nhung
  # 2023 va 2026 lai NGUOC chieu. Chi tin kich ban dung dau o moi nam.
  printf "\n=== KICH BAN x NAM (net USD) ===\n  %-46s", "kich ban"
  for (i = 1; i <= nyr; i++) printf " %9s", yk[i]
  printf "\n"
  for (s = 1; s <= NS; s++) {
    printf "  %2d %-43s", s, SN[s]
    for (i = 1; i <= nyr; i++) printf " %+9.0f", syu[s, i]
    printf "\n"
  }
  printf "  CANH BAO: mo phong TP tren luot TP 10R khong hoa von — khong tinh duoc to hop TP + hoa von, va\n"
  printf "  bot that co cac lenh khac chiem cho/von. Kich ban duoc chon PHAI chay lai that bang ma tran.\n"
}
