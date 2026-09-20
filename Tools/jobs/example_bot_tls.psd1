# File job mau cho Run-Batch.ps1. Chi chua gia tri (chuoi, so, mang, bang bam) — khong duoc
# co lenh PowerShell vi Import-PowerShellDataFile tu choi.
#
# Moi luot se goi Run-Backtest.ps1 voi: Defaults ghep voi muc cua luot (luot ghi de).
# Set cua Defaults va Set cua luot duoc GHEP theo ten input.
@{
    Name     = "vi_du_bot_tls"

    Defaults = @{
        Bot    = "BOT_TLS"
        Preset = "demo_M5_nogate_TP4_BE15.set"
        Period = "M5"
        Set    = @("Inp_No_SL=false", "Inp_FlexTP_Enabled=false")
    }

    Jobs = @(
        # Luot don le tren khoang LIEN TUC dai — con so dung de ket luan (bay so 8).
        @{ Tag = "vd_goc_43m";  From = "2023.02.01"; To = "2026.09.12" }

        # Kiem ngoai mau tren nam CHUA TUNG dung de chon tham so.
        @{ Tag = "vd_goc_2022"; From = "2022.02.01"; To = "2023.02.01" }

        # Toi uu hoa song song mot tham so. Voi -FillMissing, to hop MT5 bo sot se duoc chay bu.
        @{ Tag = "opt_minsl_43m"; From = "2023.02.01"; To = "2026.09.12"; Range = @("Inp_Min_SL_Pips=0:30:150") }

        # Doi ma tran CSV va ghi de them input rieng cho luot nay.
        @{ Tag = "vd_tp10_2022"; From = "2022.02.01"; To = "2023.02.01"; Matrix = "M_S_TP10.csv"; Set = @("Inp_DailyDrawdownLimit=6") }
    )
}
