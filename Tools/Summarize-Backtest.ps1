<#
.SYNOPSIS
    Doc cac file log do Run-Backtest.ps1 sinh ra va in bang tom tat.

.DESCRIPTION
    Bang gom: lai %, sut von, so lenh, ty le thang, profit factor, diem
    (lai-thang chia sut-von), so dong luat phat sinh lenh, va so loi van hanh.
    Cot INPUT lap lai cac input quan trong DOC TU LOG chu khong tu file .ini —
    day la cach duy nhat de biet cau hinh co that su duoc ap dung hay khong.

.EXAMPLE
    .\Summarize-Backtest.ps1
    .\Summarize-Backtest.ps1 -Tag june_now -Detail
#>
[CmdletBinding()]
param(
    [string]$Tag = "*",
    [switch]$Detail
)

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir   = Join-Path $ToolsDir "logs"
$files    = Get-ChildItem $LogDir -Filter "out_$Tag.log" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $files) { Write-Host "Khong thay log nao khop 'out_$Tag.log' trong $LogDir"; return }

function Get-Match([string[]]$text, [string]$pattern, [int]$group = 1) {
    foreach ($line in $text) {
        $m = [regex]::Match($line, $pattern)
        if ($m.Success) { return $m.Groups[$group].Value }
    }
    return ""
}

$rows = @()
foreach ($f in $files) {
    $t   = Get-Content $f.FullName
    $tag = $f.BaseName -replace '^out_', ''

    $cut  = $false
    if (($t | Select-String "final balance" | Measure-Object).Count -eq 0) { $cut = $true }

    $lai  = Get-Match $t 'Lai rong=[-0-9.]+ \(([-0-9.]+)%\)'
    $pf   = Get-Match $t 'Profit factor=([0-9.]+)'
    $n    = Get-Match $t 'So lenh=([0-9]+)'
    $wr   = Get-Match $t 'Ty le thang=([0-9.]+)%'
    $dd   = Get-Match $t 'equity tuong doi=([0-9.]+)%'
    $sc   = Get-Match $t 'DIEM \(lai-thang/sut-von\)=([-0-9.]+)'
    $ru   = Get-Match $t 'phat sinh lenh: ([0-9]+ / [0-9]+)'
    $bal  = Get-Match $t 'final balance ([0-9.]+)'
    $err  = ($t | Select-String -Pattern 'FAILED|failed |LOI:' | Measure-Object).Count

    $rows += [pscustomobject]@{
        TAG      = if ($cut) { "$tag (CAT NGANG)" } else { $tag }
        'LAI%'   = $lai
        'SUTVON' = $dd
        'LENH'   = $n
        'THANG%' = $wr
        'PF'     = $pf
        'DIEM'   = $sc
        'RULE'   = $ru
        'LOI'    = $err
        'BALANCE'= $bal
    }
}
$rows | Format-Table -AutoSize

if ($Detail) {
    foreach ($f in $files) {
        $t = Get-Content $f.FullName
        Write-Host ""
        Write-Host "===== $($f.BaseName) =====" -ForegroundColor Cyan

        Write-Host "-- input thuc te doc tu log (doi chung, dung tin file .ini) --" -ForegroundColor DarkGray
        $t | Select-String -Pattern 'Inp_(Matrix_File|No_SL|FlexTP_Enabled|Entry_Mode|DailyDrawdownLimit|Gate_MaxOrders)=|FixedLotSize=|UseRiskPerTrade=|RiskPercent=' |
             ForEach-Object { ($_ -replace '^.*\t', '').Trim() } | Select-Object -Unique | ForEach-Object { "   $_" }

        Write-Host "-- loi van hanh --" -ForegroundColor DarkGray
        $errs = $t | Select-String -Pattern 'FAILED|failed |LOI:' | ForEach-Object {
            ($_ -replace '^.*\t','') -replace '[0-9]{4}\.[0-9]{2}\.[0-9]{2} [0-9:]+','' -replace '#[0-9]+','#N' -replace '[0-9]+\.[0-9]+','N' -replace 'ticket=[0-9]+','ticket=N'
        }
        if ($errs) { $errs | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 |
                     ForEach-Object { "   {0,6} x {1}" -f $_.Count, $_.Name.Trim() } }
        else { "   khong co" }

        Write-Host "-- ba bang OnTester --" -ForegroundColor DarkGray
        $t | Select-String -Pattern '\[TESTER\]' | ForEach-Object { "   " + (($_ -replace '^.*\t','') -replace '^[0-9. :]*\s*','') }
    }
}
