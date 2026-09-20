<#
.SYNOPSIS
    Tach tung lenh tu log backtest va in bao cao phan tich sau.

.DESCRIPTION
    Doc logs\out_<Tag>.log do Run-Backtest.ps1 sinh ra, tai dung tung lenh bang GIA KHOP THAT,
    ghi logs\trades_<Tag>.csv va logs\report_<Tag>.txt.

    Bao cao: tong ket (lai/lo TB theo USD va pip) · theo do rong SL · theo ngay · chuoi thua va
    thoi gian nam duoi dinh · so lenh mo cung luc va tong rui ro · chieu x nam · theo thang
    (ty le thang duong, thang am lien tiep) · do tap trung loi nhuan.

    Luu y quan trong:
      - USD tinh tu gia x lot x ContractSize, TRUOC swap va hoa hong (log khong ghi hai khoan nay).
        Dong '#' trong CSV cho biet lai rong cua tester de doi chieu.
      - Moi vi the mot dong; gia dong = binh quan theo khoi luong moi lan dong (SL/TP, EA chot mot
        phan, FlexTP, Pool SL). Vi the con mo luc het ky test khong co trong CSV (dong '#': chua_dong).
      - Kiem nhanh: chenh lech net tach duoc - lai_rong_tester phai on dinh giua cac cau hinh cung so
        lenh (~ swap + hoa hong). Trung tung do la giua hai cau hinh khac nhau = dang bo sot lenh dong.
      - Can gawk: co san trong Git for Windows (usr\bin\gawk.exe).

.EXAMPLE
    .\Analyze-Trades.ps1 -Tag b3_S_TP4_BE15
    .\Analyze-Trades.ps1 -Tag "oos2022_*"
    .\Analyze-Trades.ps1 -Tag eurusd_test -ContractSize 100000 -Pip 0.0001
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Tag,
    [double]$Deposit      = 10000,
    [double]$ContractSize = 100,
    [double]$Pip          = 0.1
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

$logs = Get-ChildItem $LogDir -Filter "out_$Tag.log" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $logs) { throw "Khong thay log nao khop 'out_$Tag.log' trong $LogDir" }

foreach ($log in $logs) {
    $t   = $log.BaseName -replace '^out_', ''
    $csv = Join-Path $LogDir "trades_$t.csv"
    $rep = Join-Path $LogDir "report_$t.txt"

    $rows = & $gawk -f (Join-Path $Lib "extract_trades.awk") $log.FullName
    [IO.File]::WriteAllLines($csv, [string[]]$rows)
    $stat = ($rows | Where-Object { $_ -like '#*' } | Select-Object -Last 1)

    $report = & $gawk -v DEP=$Deposit -v CS=$ContractSize -v PIP=$Pip -f (Join-Path $Lib "analyze_trades.awk") $csv
    $header = @("================ $t ================", "doi chieu: $stat")
    [IO.File]::WriteAllLines($rep, [string[]]($header + $report))
    $header + $report
    ""
}
