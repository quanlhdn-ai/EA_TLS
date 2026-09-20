# analyze_trades.awk — phan tich sau file CSV tu extract_trades.awk.
#
# Tham so (-v):  DEP = von dau (mac dinh 10000)
#                CS  = kich thuoc hop dong / 1 lot (mac dinh 100 = vang)
#                PIP = gia tri 1 pip theo gia (mac dinh 0.1 = vang)
#
# USD = (gia dong - gia vao) x chieu x lot x CS  -> TRUOC swap va hoa hong (log khong ghi).
# Voi lot co dinh, so sanh giua cac nhom trong cung mot cau hinh van dung.
function ts(s,  t) { t = s; gsub(/[.:]/, " ", t); return mktime(t) }
BEGIN { FS = ","; if (DEP == "") DEP = 10000; if (CS == "") CS = 100; if (PIP == "") PIP = 0.1 }
{ sub(/\r$/, "") }   # CSV ghi bang .NET WriteAllLines co xuong dong CRLF
/^#/    { next }
NR == 1 { next }
{
  i++; ot[i] = $2; dir[i] = ($3 == "buy") ? 1 : -1; lot[i] = $4; op[i] = $5; sl[i] = $6; ct[i] = $8; cp[i] = $9
  usd[i]  = (cp[i] - op[i]) * dir[i] * lot[i] * CS
  pip[i]  = (cp[i] - op[i]) * dir[i] / PIP
  rp[i]   = op[i] - sl[i]; if (rp[i] < 0) rp[i] = -rp[i]
  rusd[i] = rp[i] * lot[i] * CS
}
END {
  n = i; if (n == 0) { print "Khong co lenh nao."; exit }
  LOT = lot[1]
  for (k = 1; k <= n; k++) { net += usd[k]; if (usd[k] > 0) { w++; gw += usd[k]; wp += pip[k] } else { gl -= usd[k]; lp += pip[k] } }
  printf "1. TONG KET  lenh=%d | thang=%.1f%% | net=%.0f USD | PF=%.2f | TB lenh thang=+%.0f USD (+%.0f pip) | TB lenh thua=%.0f USD (%.0f pip)\n", \
         n, 100*w/n, net, (gl > 0 ? gw/gl : 0), (w ? gw/w : 0), (w ? wp/w : 0), (n-w ? -gl/(n-w) : 0), (n-w ? lp/(n-w) : 0)

  for (k = 1; k <= n; k++) r[k] = rp[k]; asort(r)
  printf "2. SL BAN DAU trung vi=%.2f gia (%.0f pip, %.0f USD) | p90=%.2f (%.0f USD) | lon nhat=%.2f (%.0f USD)\n", \
         r[int(n*.5)+0 ? int(n*.5) : 1], r[int(n*.5) ? int(n*.5) : 1]/PIP, r[int(n*.5) ? int(n*.5) : 1]*LOT*CS, r[int(n*.9) ? int(n*.9) : 1], r[int(n*.9) ? int(n*.9) : 1]*LOT*CS, r[n], r[n]*LOT*CS
  nb = split("0,60,90,150,250,1e9", bp, ",")
  for (k = 1; k <= n; k++) { s = rp[k] / PIP; for (j = 1; j < nb; j++) if (s >= bp[j] && s < bp[j+1]) { bn[j]++; bu[j] += usd[k]; if (usd[k] > 0) bw[j]++; break } }
  for (j = 1; j < nb; j++) if (bn[j]) printf "   SL %4s-%-5s pip: lenh=%5d | thang=%4.1f%% | net=%+9.0f USD | TB/lenh=%+7.1f USD\n", bp[j], (bp[j+1] == 1e9 ? "+" : bp[j+1]), bn[j], 100*bw[j]/bn[j], bu[j], bu[j]/bn[j]

  for (k = 1; k <= n; k++) du[substr(ct[k], 1, 10)] += usd[k]
  for (d in du) { nd++; dv[nd] = du[d]; if (du[d] > 0) dpos++ }
  asort(dv)
  printf "3. THEO NGAY %d ngay co dong lenh | ngay duong=%.1f%% | TB=%+.0f | p10=%+.0f p25=%+.0f trung vi=%+.0f p75=%+.0f p90=%+.0f | tot nhat=%+.0f | te nhat=%+.0f USD\n", \
         nd, 100*dpos/nd, net/nd, dv[int(nd*.1) ? int(nd*.1) : 1], dv[int(nd*.25) ? int(nd*.25) : 1], dv[int(nd*.5) ? int(nd*.5) : 1], dv[int(nd*.75) ? int(nd*.75) : 1], dv[int(nd*.9) ? int(nd*.9) : 1], dv[nd], dv[1]

  for (k = 1; k <= n; k++) key[k] = ct[k] sprintf("%06d", k)
  m = asort(key, ks)
  bal = DEP; peak = DEP; cur = 0
  for (j = 1; j <= m; j++) {
    k = substr(ks[j], 20) + 0
    if (usd[k] <= 0) { cur++; if (cur > mls) mls = cur } else cur = 0
    bal += usd[k]
    if (bal > peak) { if (uw != "") { dur = (ts(ct[k]) - ts(uw)) / 86400; if (dur > muw) muw = dur }; peak = bal; uw = "" }
    else { if (uw == "") uw = ct[k]; dd = (peak - bal) / peak; if (dd > mdd) { mdd = dd; mdd_t = ct[k] } }
  }
  if (uw != "") { dur = (ts(ct[ks[m] ? substr(ks[m], 20) + 0 : 1]) - ts(uw)) / 86400; if (dur > muw) muw = dur }
  nds = asorti(du, ds); cur = 0
  for (j = 1; j <= nds; j++) { if (du[ds[j]] <= 0) { cur++; if (cur > mld) mld = cur } else cur = 0 }
  printf "4. CHUOI     thua lien tiep dai nhat=%d lenh | ngay am lien tiep=%d | sut von balance lon nhat=%.1f%% (%s) | nam duoi dinh lau nhat=%.0f ngay\n", \
         mls, mld, 100*mdd, substr(mdd_t, 1, 10), muw

  for (k = 1; k <= n; k++) { e[++ne] = ot[k] "|1|" k; e[++ne] = ct[k] "|0|" k }
  asort(e); cnt = 0; rk = 0
  for (j = 1; j <= ne; j++) { split(e[j], pp, "|"); k = pp[3] + 0
    if (pp[2] == "1") { cnt++; rk += rusd[k]; if (cnt > mc) mc = cnt; if (rk > mr) { mr = rk; mr_t = pp[1] }; cs_sum += cnt; co++ }
    else { cnt--; rk -= rusd[k] } }
  printf "5. PHOI NHIEM lenh mo cung luc toi da=%d, TB luc vao lenh=%.1f | tong rui ro SL cung luc toi da=%.0f USD (%s)\n", mc, cs_sum/co, mr, substr(mr_t, 1, 10)

  for (k = 1; k <= n; k++) { y = substr(ot[k], 1, 4) (dir[k] > 0 ? " BUY " : " SELL"); yn[y]++; yu[y] += usd[k]; if (usd[k] > 0) yw[y]++ }
  ny = asorti(yn, yk); printf "6. CHIEU x NAM\n"
  for (j = 1; j <= ny; j++) printf "   %s: %5d lenh | thang %4.1f%% | %+9.0f USD\n", yk[j], yn[yk[j]], 100*yw[yk[j]]/yn[yk[j]], yu[yk[j]]

  for (k = 1; k <= n; k++) mu[substr(ct[k], 1, 7)] += usd[k]
  nm = asorti(mu, mk); mb = -1e18; mw = 1e18; cur = 0
  for (j = 1; j <= nm; j++) {
    if (mu[mk[j]] > 0) { mpos++; cur = 0 } else { cur++; if (cur > mlm) mlm = cur }
    if (mu[mk[j]] > mb) { mb = mu[mk[j]]; mbk = mk[j] }
    if (mu[mk[j]] < mw) { mw = mu[mk[j]]; mwk = mk[j] }
  }
  printf "7. THEO THANG %d thang | thang duong=%d (%.0f%%) | thang am lien tiep=%d | tot nhat %s %+.0f | te nhat %s %+.0f USD\n", nm, mpos, 100*mpos/nm, mlm, mbk, mb, mwk, mw

  for (k = 1; k <= n; k++) uc[k] = usd[k]; asort(uc); top = 0; kt = int(n * 0.05); if (kt < 1) kt = 1
  for (j = n; j > n - kt; j--) top += uc[j]
  printf "8. TAP TRUNG %d lenh lai lon nhat (5%%) = %+.0f USD = %.0f%% loi nhuan rong\n", kt, top, (net != 0 ? 100*top/net : 0)
}
