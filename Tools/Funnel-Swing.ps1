<#
.SYNOPSIS
    Do tham so tuan tu tung input mot, TU CHON gia tri giua cac giai doan.

.DESCRIPTION
    Voi moi input trong -Stages (theo thu tu): chay het -Grid, cham diem, chot gia
    tri tot nhat, roi sang input ke tiep voi gia tri do da co dinh. Khong can nguoi
    ngoi canh giua cac giai doan.

    Diem moi luot  = Lai% / max(SutVonEquity%, 1). Luot < -MinTrades lenh, bi cat
                     ngang, hoac lai am thi bi loai khoi viec chon.
    Diem ben vung  = diem THAP NHAT trong {ben trai, chinh no, ben phai} tren luoi.
                     Chon theo diem nay de uu tien VUNG PHANG, tranh dinh nhon canh
                     vuc — mot gia tri tot ma hang xom te thi kho tin.

    Chay lai duoc: luot nao da co log hoan chinh thi bo qua, nen bi ngat giua chung
    chi can goi lai dung lenh cu.

    Ket qua: logs\<Prefix>_summary.csv (moi luot mot dong) va
             logs\<Prefix>_result.txt  (bo tham so da chot).

.EXAMPLE
    .\Funnel-Swing.ps1 -Prefix nosl_off -Bot BOT_TLS -Preset exness_359.set `
        -From 2024.10.01 -To 2025.10.01 -Model OHLC_M1 `
        -Base @("Trend_Timeframe=15","HTF_Timeframe=5","Inp_No_SL=false") `
        -Stages @("Trend_PeriodsInMajorSwing","HTF_PeriodsInMajorSwing","PeriodsInMajorSwing") `
        -Start  @{Trend_PeriodsInMajorSwing=3; HTF_PeriodsInMajorSwing=5; PeriodsInMajorSwing=9} `
        -Grid   @(3,5,7,10,13,16,20)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Prefix,
    [Parameter(Mandatory=$true)][string]$Bot,
    [Parameter(Mandatory=$true)][string]$Preset,
    [Parameter(Mandatory=$true)][string[]]$Stages,
    [Parameter(Mandatory=$true)][hashtable]$Start,
    [Parameter(Mandatory=$true)][int[]]$Grid,
    [string]$From   = "2024.10.01",
    [string]$To     = "2025.10.01",
    [string]$Period = "",
    [string]$Matrix = "",
    [ValidateSet("EveryTick","OHLC_M1","OpenPrices")][string]$Model = "OHLC_M1",
    [string[]]$Base = @(),
    [int]$MinTrades = 100
)

$ErrorActionPreference = "Stop"
# CSV phai dung dau cham thap phan. May dat locale vi-VN thi -f se in "43,75"
# va pha vo cot CSV, nen ep InvariantCulture cho toan script.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::InvariantCulture
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ToolsDir "BacktestLib.ps1")
$LogDir  = Join-Path $ToolsDir "logs"
$Summary = Join-Path $LogDir "$($Prefix)_summary.csv"
$Result  = Join-Path $LogDir "$($Prefix)_result.txt"
# Viet lai tu dau moi lan goi: so lieu deu doc lai tu log nen khong mat gi,
# va tranh dong trung lap khi chay lai sau khi bi ngat.
"Stage,Input,Value,Tag,NetPct,DDBal,DDEq,Trades,WinPct,PF,Balance,Errors,Score,Robust,Chosen" | Set-Content $Summary -Encoding UTF8
Remove-Item $Result -ErrorAction SilentlyContinue

$cur = @{}; foreach ($k in $Start.Keys) { $cur[$k] = $Start[$k] }

for ($si = 0; $si -lt $Stages.Count; $si++) {
    $inp = $Stages[$si]
    $rows = @()
    foreach ($v in $Grid) {
        $tag = "{0}_s{1}_{2}" -f $Prefix, ($si + 1), $v
        $log = Join-Path $LogDir "out_$tag.log"
        $m = Get-RunMetrics $log
        if (-not $m -or -not $m.Done) {
            $set = @($Base)
            foreach ($k in $cur.Keys) { if ($k -ne $inp) { $set += "$k=$($cur[$k])" } }
            $set += "$inp=$v"
            $rb = @{ Bot=$Bot; Preset=$Preset; Tag=$tag; From=$From; To=$To; Model=$Model; Set=$set }
            if ($Period -ne "") { $rb.Period = $Period }
            if ($Matrix -ne "") { $rb.Matrix = $Matrix }
            & (Join-Path $ToolsDir "Run-Backtest.ps1") @rb | Out-Null
            $m = Get-RunMetrics $log
        }
        $ok = $m -and $m.Done -and $m.Trades -ge $MinTrades -and $m.NetPct -gt 0
        $score = if ($ok) { $m.NetPct / [math]::Max($m.DDEq, 1.0) } else { -999.0 }
        $rows += [pscustomobject]@{ V=$v; Tag=$tag; M=$m; Score=$score }
    }

    # Diem ben vung: lay diem thap nhat trong cua so 3 o lien ke tren luoi.
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $w = @($rows[$i].Score)
        if ($i -gt 0)                { $w += $rows[$i - 1].Score }
        if ($i -lt $rows.Count - 1)  { $w += $rows[$i + 1].Score }
        $rows[$i] | Add-Member -NotePropertyName Robust -NotePropertyValue (($w | Measure-Object -Minimum).Minimum)
    }
    $best = $rows | Sort-Object Robust -Descending | Select-Object -First 1
    if ($best.Robust -le -999) {
        # Khong gia tri nao dat chuan: giu nguyen gia tri hien tai, ghi ro ly do.
        Add-Content $Result ("[{0}] KHONG gia tri nao dat chuan (lai>0, >= {1} lenh). Giu {0}={2}" -f $inp, $MinTrades, $cur[$inp])
    } else {
        $cur[$inp] = $best.V
    }

    foreach ($r in $rows) {
        $m = $r.M
        $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12:N3},{13:N3},{14}" -f `
            ($si + 1), $inp, $r.V, $r.Tag, $m.NetPct, $m.DDBal, $m.DDEq, $m.Trades, $m.WinPct, $m.PF, `
            $m.Balance, $m.Errors, $r.Score, $r.Robust, ($(if ($r.V -eq $cur[$inp] -and $best.Robust -gt -999) {"X"} else {""}))
        Add-Content $Summary $line -Encoding UTF8
    }
    Write-Host ("[{0}] giai doan {1}: chot {2} = {3}" -f $Prefix, ($si + 1), $inp, $cur[$inp])
}

$final = ($Stages | ForEach-Object { "$_=$($cur[$_])" }) -join "; "
Add-Content $Result "BO THAM SO CHOT: $final"
Write-Host "[$Prefix] XONG. $final"
