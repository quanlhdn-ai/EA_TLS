# Phantich-HanhTrinh.awk — tu file hanh trinh cua BOT_CRT, tinh nguoc ra ket qua cua
# MOI to hop (muc TP x moc BE) ma khong phai chay lai backtest lan nao.
#
# Dung:  awk -F, -f Phantich-HanhTrinh.awk hanhtrinh/h4m15.csv
#
# CACH TINH cho 1 lenh, voi muc TP = X pip va moc BE = T pip:
#   · Chua tung cham T           -> BE chua kich -> ket qua nhu khong co BE
#   · Cham T, roi cham X TRUOC khi quay ve entry -> thang, +X pip
#   · Cham T, quay ve entry truoc khi cham X     -> hoa von, 0 pip
#   · Khong cham X va khong quay ve entry        -> thua, -R pip (neu ket cuc la SL)
#
# GIOI HAN cua so lieu, phai nho khi doc ket qua:
#   · Chi xet duoc cac muc TP nam trong danh sach moc da ghi (10..300 pip).
#   · Thoi diem ghi theo PHUT. Cham TP va quay ve entry trong cung mot phut thi khong
#     phan biet duoc thu tu -> quy uoc tinh THANG (lac quan). Anh huong nho.
#   · Luot ghi hanh trinh dat TP 300 pip, nen khong biet gi ve doan xa hon 300 pip.

BEGIN {
    n_moc = 9
    split("10 20 30 50 80 100 150 200 300", moc, " ")
    # Cot dau tien cua nhom moc thu i: cham=12+(i-1)*3, phut=+1, phut_ve_entry=+2
}

NR == 1 { next }
NF < 40 { next }

{
    R = $7 + 0
    if (R <= 0) next
    ketcuc = $39
    t[++N] = 1
    Rpip[N] = R
    kc[N] = ketcuc
    for (i = 1; i <= n_moc; i++) {
        c = 12 + (i - 1) * 3
        cham[N, i] = ($c == "1") ? 1 : 0
        phut[N, i] = $(c + 1) + 0
        ve = $(c + 2)
        # "-" = cham moc nhung khong quay ve entry · rong = chua cham moc
        veco[N, i]  = (ve != "" && ve != "-") ? 1 : 0
        vephut[N, i] = (veco[N, i]) ? ve + 0 : -1
    }
}

function ketqua(k, itp, ibe,   reached, vp) {
    reached = cham[k, itp]
    if (ibe > 0 && ibe <= itp && cham[k, ibe]) {
        if (veco[k, ibe]) {
            vp = vephut[k, ibe]
            # Cham TP truoc hay quay ve entry truoc?
            if (reached && phut[k, itp] <= vp) return moc[itp]
            return 0
        }
        # BE da kich hoat ma khong ghi nhan lan quay ve entry nao:
        #   · cham TP  -> thang (lan quay ve, neu co, xay ra sau do)
        #   · ket cuc SL -> gia BAT BUOC da di qua entry moi xuong toi SL duoc, chi la
        #     bo ghi lay mau theo tick nen lo mat khoanh khac do -> voi BE thi la HOA VON,
        #     TUYET DOI khong phai thua. (Do duoc: chi 1/52 lenh roi vao ca nay.)
        if (reached) return moc[itp]
        return 0
    }
    if (reached) return moc[itp]
    return (kc[k] == "SL") ? -Rpip[k] : 0
}

END {
    if (N == 0) { print "Khong doc duoc lenh nao"; exit }

    # Che do xuat CSV de so sanh nhieu cap khung: awk -v csv=1 -v ten=h4m15 ...
    if (csv == 1) {
        for (i = 1; i <= n_moc; i++) {
            for (b = 0; b <= n_moc; b++) {
                if (b > i) continue
                tong = 0; thang = 0; hoa = 0; thua = 0
                for (k = 1; k <= N; k++) {
                    r = ketqua(k, i, b)
                    tong += r
                    if (r > 0) thang++; else if (r == 0) hoa++; else thua++
                }
                printf "%s,%d,%d,%.0f,%.3f,%d,%d,%d,%d\n",
                       ten, moc[i], (b == 0 ? 0 : moc[b]), tong, tong / N, thang, hoa, thua, N
            }
        }
        exit
    }
    printf "So lenh: %d\n\n", N
    printf "TONG PIP (va so lenh thang) theo tung to hop — dong = muc TP, cot = moc BE\n"
    printf "%-8s", "TP\\BE"
    printf "%12s", "tat"
    for (b = 1; b <= n_moc; b++) if (moc[b] <= 100) printf "%12s", moc[b] "p"
    printf "\n"

    for (i = 1; i <= n_moc; i++) {
        printf "%-8s", moc[i] "p"
        for (b = 0; b <= n_moc; b++) {
            if (b > 0 && moc[b] > 100) continue
            if (b > 0 && b > i) { printf "%12s", "-"; continue }
            tong = 0; thang = 0; hoa = 0
            for (k = 1; k <= N; k++) {
                r = ketqua(k, i, b)
                tong += r
                if (r > 0) thang++
                else if (r == 0) hoa++
            }
            printf "%12s", sprintf("%.0f/%d", tong, thang)
        }
        printf "\n"
    }

    printf "\nTB PIP MOI LENH theo tung to hop\n"
    printf "%-8s", "TP\\BE"
    printf "%12s", "tat"
    for (b = 1; b <= n_moc; b++) if (moc[b] <= 100) printf "%12s", moc[b] "p"
    printf "\n"
    for (i = 1; i <= n_moc; i++) {
        printf "%-8s", moc[i] "p"
        for (b = 0; b <= n_moc; b++) {
            if (b > 0 && moc[b] > 100) continue
            if (b > 0 && b > i) { printf "%12s", "-"; continue }
            tong = 0
            for (k = 1; k <= N; k++) tong += ketqua(k, i, b)
            printf "%12.2f", tong / N
        }
        printf "\n"
    }
}
