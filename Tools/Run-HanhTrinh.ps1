# Run-HanhTrinh.ps1 — chay loat backtest BOT_CRT de GHI HANH TRINH tung lenh.
#
# VI SAO CHIA DOAN 3 THANG:
#   Tai khoan Exness-MT5Trial7 bi rot ket noi deu dan 38-60 giay sau khi dang nhap
#   ("connection to Exness-MT5Trial7 lost"), roi tester bao "some error after pass
#   finished" va dong ngang. Do la gioi han cua server trial, khong phai loi bot:
#     · luot 3 thang  (~27 giay)  -> chay tron, co dong 'final balance'
#     · luot 6 thang  (~55 giay)  -> bi cat ngang
#   Nen chia moi lan chay <= 3 thang. Moi doan la mot lan dang nhap moi.
#
# HE QUA phai chap nhan: moi doan bat dau lai voi so du 10.000, va lenh dang mo tai
# ranh gioi doan bi cat. Voi muc tieu ghi HANH TRINH tung lenh (lot co dinh, phan tich
# theo tung lenh chu khong theo duong von) thi anh huong khong dang ke.
#
# Dung:
#   .\Run-HanhTrinh.ps1                     # chay het 6 cap khung
#   .\Run-HanhTrinh.ps1 -ChiCap h4m15       # chi mot cap
#   .\Run-HanhTrinh.ps1 -Tu 2025.01.01 -Den 2026.09.11

param(
    [string]$Tu       = "2023.01.01",
    [string]$Den      = "2026.09.11",
    [string]$ChiCap   = "",
    [int]   $SoThang  = 3,
    [string]$Account  = "account.crt.ini",
    [string]$Preset   = "C:\Users\Admin\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Profiles\Tester\CRT_MultiTF_EA.set",
    # Thu muc DUNG CHUNG, khong phai MQL5\Files cua terminal: trong tester, EA ghi file
    # bang co FILE_COMMON nen file ra o day. Khong co co do thi file roi vao hop cat
    # rieng cua agent va chay xong khong thay dau.
    [string]$FilesDir = "C:\Users\Admin\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
)

$ErrorActionPreference = "Stop"
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ToolsDir
$OutDir = Join-Path $ToolsDir "hanhtrinh"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# TP day ra 300 pip va TAT ca hai luat hoa von -> lenh chay het hanh trinh cua no,
# khong bi cat ngang. Moi muc TP <= 300 pip deu tinh nguoc lai duoc tu so lieu nay.
$baseSet = @(
    "Inp_Ghi_HanhTrinh=true",
    "Inp_BE_TaiBienDoiDien=false",
    "Inp_BE_TriggerPips=0",
    "Inp_TP21_Mode_LK=2", "Inp_TP21_Pips_LK=300",
    "Inp_TP21_Mode_SW=2", "Inp_TP21_Pips_SW=300",
    "Inp_TP22_Mode_LK=2", "Inp_TP22_Pips_LK=300",
    "Inp_TP22_Mode_SW=2", "Inp_TP22_Pips_SW=300"
)

# 16388 = PERIOD_H4 · 16385 = PERIOD_H1 · 15/5/1 = M15/M5/M1
$caps = @(
    @{ tag = "h4m15"; htf = 16388; ltf = 15; htfTen = "H4"; ltfTen = "M15"; period = "M15" },
    @{ tag = "h4m5";  htf = 16388; ltf = 5;  htfTen = "H4"; ltfTen = "M5";  period = "M5"  },
    @{ tag = "h4m1";  htf = 16388; ltf = 1;  htfTen = "H4"; ltfTen = "M1";  period = "M1"  },
    @{ tag = "h1m15"; htf = 16385; ltf = 15; htfTen = "H1"; ltfTen = "M15"; period = "M15" },
    @{ tag = "h1m5";  htf = 16385; ltf = 5;  htfTen = "H1"; ltfTen = "M5";  period = "M5"  },
    @{ tag = "h1m1";  htf = 16385; ltf = 1;  htfTen = "H1"; ltfTen = "M1";  period = "M1"  }
)
if ($ChiCap -ne "") { $caps = @($caps | Where-Object { $_.tag -eq $ChiCap }) }
if (-not $caps) { throw "Khong co cap khung nao khop -ChiCap '$ChiCap'" }

# Cac moc chia doan
$batDau = [datetime]::ParseExact($Tu,  "yyyy.MM.dd", $null)
$ketThuc = [datetime]::ParseExact($Den, "yyyy.MM.dd", $null)
$doan = @()
$t = $batDau
while ($t -lt $ketThuc) {
    $t2 = $t.AddMonths($SoThang)
    if ($t2 -gt $ketThuc) { $t2 = $ketThuc }
    $doan += @{ tu = $t.ToString("yyyy.MM.dd"); den = $t2.ToString("yyyy.MM.dd") }
    $t = $t2
}
Write-Host "[hanhtrinh] $($caps.Count) cap khung x $($doan.Count) doan = $($caps.Count * $doan.Count) luot chay" -ForegroundColor Cyan

foreach ($c in $caps) {
    $capDir = Join-Path $OutDir $c.tag
    if (-not (Test-Path $capDir)) { New-Item -ItemType Directory -Path $capDir | Out-Null }
    $csvNguon = Join-Path $FilesDir ("CRT_HT_XAUUSDm_{0}_{1}.csv" -f $c.htfTen, $c.ltfTen)
    $ok = 0; $hong = 0

    foreach ($d in $doan) {
        $tag = "ht_$($c.tag)_$($d.tu -replace '\.','')"
        $set = $baseSet + @("Inp_HTF=$($c.htf)", "Inp_LTF=$($c.ltf)")
        if (Test-Path $csvNguon) { Remove-Item $csvNguon -Force }

        $lan = 0
        while ($lan -lt 2) {
            $lan++
            try {
                & (Join-Path $ToolsDir "Run-Backtest.ps1") -Bot BOT_CRT -Account $Account `
                    -Preset $Preset -From $d.tu -To $d.den -Period $c.period `
                    -Model OHLC_M1 -Tag $tag -Set $set | Out-Null
            } catch {
                Write-Host "  [$tag] loi: $_" -ForegroundColor Red
            }
            $logFile = Join-Path $ToolsDir "logs\out_$tag.log"
            $xong = (Test-Path $logFile) -and ((Select-String -Path $logFile -Pattern "final balance" -SimpleMatch | Measure-Object).Count -gt 0)
            if ($xong) { break }
            Write-Host "  [$tag] bi cat ngang, thu lai lan $lan" -ForegroundColor Yellow
        }

        if (Test-Path $csvNguon) {
            $dich = Join-Path $capDir ("chunk_{0}.csv" -f ($d.tu -replace '\.',''))
            Move-Item $csvNguon $dich -Force
            $n = (Get-Content $dich | Measure-Object -Line).Lines - 1
            Write-Host ("  [{0}] {1} -> {2} lenh" -f $c.tag, $d.tu, $n)
            $ok++
        } else {
            Write-Host ("  [{0}] {1} -> KHONG co CSV" -f $c.tag, $d.tu) -ForegroundColor Yellow
            $hong++
        }
    }

    # Gop cac doan thanh 1 file cho ca cap khung (giu dung 1 dong header)
    $gop = Join-Path $OutDir ("{0}.csv" -f $c.tag)
    $files = Get-ChildItem $capDir -Filter "chunk_*.csv" | Sort-Object Name
    if ($files) {
        $header = (Get-Content $files[0].FullName -TotalCount 1)
        $rows = foreach ($f in $files) { Get-Content $f.FullName | Select-Object -Skip 1 }
        @($header) + $rows | Set-Content $gop -Encoding UTF8
        Write-Host ("[hanhtrinh] {0}: {1} doan ok, {2} doan hong, tong {3} lenh -> {4}" -f `
                    $c.tag, $ok, $hong, $rows.Count, $gop) -ForegroundColor Green
    }
}
Write-Host "[hanhtrinh] XONG" -ForegroundColor Cyan
