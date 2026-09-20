<#
.SYNOPSIS
    Phan tich dac diem luc vao lenh (xu huong D1/H4/H1, zone khung lon, khoang trong toi can,
    toc do cham 1R) va mo phong cac kich ban TP / loc lenh theo muc tieu lai deu hang thang.

.DESCRIPTION
    Can hai file trong logs\:
      out_<Tag>.log  — log cua luot do (Run-Backtest.ps1)
      <Tag>.csv      — file dac diem BOT_TLS xuat trong Strategy Tester (Common\Files\study_*.csv),
                       copy vao logs\ va doi ten theo Tag.
    Tu dong tach tung lenh (trades_<Tag>.csv) neu chua co, roi ghi logs\features_<Tag>.txt.

    Nen chay luot do voi TP rat dai va KHONG hoa von (vd ma tran TP 10R) de biet lenh thang
    thuc su chay xa bao nhieu. Mo phong TP ngan hon la chinh xac theo tung lenh; to hop
    TP + hoa von thi KHONG mo phong duoc — phai chay that.

.EXAMPLE
    .\Analyze-Features.ps1 -Tag feat_TP10_43m
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Tag,
    [double]$Lot          = 0.05,
    [double]$ContractSize = 100,
    [double]$Pip          = 0.1,
    [double]$Deposit      = 10000,
    # USD tru moi lenh cho swap + hoa hong (log khong ghi). Uoc tu (net tach duoc - lai rong tester) / so lenh
    # cua Analyze-Trades; BOT_TLS vang lot 0.05 tren IC: ~1.4.
    [double]$CostPerTrade = 0
)

$ErrorActionPreference = "Stop"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::InvariantCulture
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir   = Join-Path $ToolsDir "logs"
$Lib      = Join-Path $ToolsDir "lib"

function Find-Gawk {
    $c = Get-Command gawk -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\Git\usr\bin\gawk.exe",
                     "${env:ProgramFiles(x86)}\Git\usr\bin\gawk.exe",
                     "$env:LOCALAPPDATA\Programs\Git\usr\bin\gawk.exe")) {
        if (Test-Path $p) { return $p }
    }
    throw "Khong tim thay gawk. Cai Git for Windows hoac them gawk vao PATH."
}
$gawk = Find-Gawk

$log  = Join-Path $LogDir "out_$Tag.log"
$feat = Join-Path $LogDir "$Tag.csv"
$trd  = Join-Path $LogDir "trades_$Tag.csv"
$rep  = Join-Path $LogDir "features_$Tag.txt"
if (-not (Test-Path $feat)) { throw "Thieu file dac diem $feat (copy tu Common\Files\study_*.csv)." }
if (-not (Test-Path $trd)) {
    if (-not (Test-Path $log)) { throw "Thieu ca $trd lan $log." }
    $rows = & $gawk -f (Join-Path $Lib "extract_trades.awk") $log
    [IO.File]::WriteAllLines($trd, [string[]]$rows)
}
$out = & $gawk -v LOT=$Lot -v CS=$ContractSize -v PIP=$Pip -v DEP=$Deposit -v COST=$CostPerTrade -f (Join-Path $Lib "analyze_features.awk") $trd $feat
[IO.File]::WriteAllLines($rep, [string[]]$out)
$out
