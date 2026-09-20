<#
.SYNOPSIS
    Chay Strategy Tester cua MT5 khong can mo giao dien, cho cac bot trong EA_TLS.

.DESCRIPTION
    Doc thong tin tai khoan tu account.local.ini (KHONG nam trong git), dung .set
    lam bo input goc, ghi file .ini dung chuan MT5, chay terminal64.exe /config:,
    roi cat dung phan log cua luot vua chay ra file rieng.

.EXAMPLE
    .\Run-Backtest.ps1 -Bot BOT_TLS -Preset exness_359.set -From 2026.06.18 -To 2026.09.09 -Tag june_now

.EXAMPLE
    .\Run-Backtest.ps1 -Bot BOT_TLS -Preset ftmo.set -Period M5 -Matrix M_I_NOGATE_R3.csv `
                       -Set @("Inp_No_SL=false","FixedLotSize=0.02") -Tag ftmo_thantrong
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Bot,
    [Parameter(Mandatory=$true)][string]$Preset,
    [Parameter(Mandatory=$true)][string]$Tag,
    [string]$From    = "2026.01.01",
    [string]$To      = "2026.02.01",
    [string]$Period  = "",
    [string]$Symbol  = "",
    [int]   $Deposit = 0,
    [string]$Matrix  = "",
    [ValidateSet("EveryTick","OHLC_M1","OpenPrices")][string]$Model = "EveryTick",
    [string[]]$Set   = @(),
    # Toi uu hoa song song: "Ten=batdau:buoc:ketthuc". Co it nhat mot muc thi
    # MT5 chay che do optimization, chia cac luot ra moi nhan CPU cung luc.
    [string[]]$Range = @(),
    [string]$Account = ""
)

$ErrorActionPreference = "Stop"
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir  = Split-Path -Parent $ToolsDir
$BotDir   = Join-Path $RepoDir $Bot
$LogDir   = Join-Path $ToolsDir "logs"

if (-not (Test-Path $BotDir)) { throw "Khong thay thu muc bot: $BotDir" }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# ------------------------------------------------------------------ tai khoan
if ($Account -eq "") { $Account = Join-Path $ToolsDir "account.local.ini" }
if (-not (Test-Path $Account)) {
    throw "Chua co $Account. Copy account.local.ini.example thanh account.local.ini roi dien thong tin. File nay KHONG duoc dua vao git."
}
$acc = @{}
Get-Content $Account | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith(";") -or $line.StartsWith("#") -or $line.StartsWith("[")) { return }
    if ($line -match '^([^=]+)=(.*)$') { $acc[$matches[1].Trim()] = $matches[2].Trim() }
}
foreach ($k in @("Terminal","Login","Password","Server")) {
    if (-not $acc.ContainsKey($k) -or $acc[$k] -eq "") { throw "Thieu khoa '$k' trong $Account" }
}
$TERM = $acc["Terminal"]
if (-not (Test-Path $TERM)) { throw "Khong thay terminal64.exe tai: $TERM" }
if ($Symbol  -eq "") { $Symbol  = if ($acc.ContainsKey("Symbol"))  { $acc["Symbol"] }  else { "XAUUSD" } }
if ($Period  -eq "") { $Period  = if ($acc.ContainsKey("Period"))  { $acc["Period"] }  else { "M1" } }
if ($Deposit -eq 0 ) { $Deposit = if ($acc.ContainsKey("Deposit")) { [int]$acc["Deposit"] } else { 10000 } }
$Leverage = if ($acc.ContainsKey("Leverage")) { $acc["Leverage"] } else { "1:100" }
$Currency = if ($acc.ContainsKey("Currency")) { $acc["Currency"] } else { "USD" }

# ---------------------------------------------------- thu muc du lieu terminal
# origin.txt trong moi thu muc GUID ghi ro no thuoc ban cai nao. Moi may mot khac,
# khong duoc dung lai GUID cua may cu.
$DataFolder = ""
if ($acc.ContainsKey("DataFolder") -and $acc["DataFolder"] -ne "") {
    $DataFolder = $acc["DataFolder"]
} else {
    $termRoot = Split-Path -Parent $TERM
    Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $o = Join-Path $_.FullName "origin.txt"
        if (Test-Path $o) {
            $origin = (Get-Content $o -Raw) -replace "[\0\r\n﻿]", ""
            if ($origin.Trim() -eq $termRoot) { $DataFolder = $_.FullName }
        }
    }
}
if ($DataFolder -eq "") { throw "Khong do duoc thu muc du lieu cua terminal. Dien DataFolder vao $Account." }
$Guid    = Split-Path -Leaf $DataFolder
$TestLog = "$env:APPDATA\MetaQuotes\Tester\$Guid\Agent-127.0.0.1-3000\logs"

# ------------------------------------------------ input hop le tu ma nguon .mq5
# Loc theo danh sach 'input' co that trong .mq5: cac thiet lap my thuat da doi
# sang 'const' van con trong .set cu, liet ke chung se lam MT5 bao loi.
$src = Get-ChildItem $BotDir -Filter *.mq5 | Where-Object { $_.Name -notlike "*Indicator*" } | Select-Object -First 1
if (-not $src) { throw "Khong thay file .mq5 trong $BotDir" }
$valid = @{}
Select-String -Path $src.FullName -Pattern '^\s*input\s+\S+\s+(\w+)' | ForEach-Object {
    $valid[$_.Matches[0].Groups[1].Value] = $true
}
if ($valid.Count -eq 0) { throw "Khong doc duoc input nao tu $($src.Name)" }

# --------------------------------------------------------- doc .set (UTF-16LE)
$PresetPath = if (Test-Path $Preset) { $Preset } else { Join-Path $BotDir $Preset }
if (-not (Test-Path $PresetPath)) { throw "Khong thay preset: $PresetPath" }
$inputs = [ordered]@{}
$skipped = @()
Get-Content $PresetPath -Encoding Unicode | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith(";")) { return }
    if ($line -match '^([^=]+)=([^|]*)') {
        $name = $matches[1].Trim(); $val = $matches[2].Trim()
        if ($valid.ContainsKey($name)) { $inputs[$name] = $val } else { $skipped += $name }
    }
}
if ($inputs.Count -eq 0) { throw "Doc duoc 0 input tu $PresetPath (file .set phai la UTF-16LE)" }

if ($Matrix -ne "") { $inputs["Inp_Matrix_File"] = $Matrix }
foreach ($o in $Set) {
    if ($o -match '^([^=]+)=(.*)$') {
        $n = $matches[1].Trim()
        if (-not $valid.ContainsKey($n)) { throw "Input '$n' khong ton tai trong $($src.Name)" }
        $inputs[$n] = $matches[2].Trim()
    } else { throw "Tham so -Set sai dinh dang, phai la 'Ten=GiaTri': $o" }
}
$optimize = $false
foreach ($r in $Range) {
    if ($r -notmatch '^([^=]+)=(-?[0-9.]+):([0-9.]+):(-?[0-9.]+)$') { throw "Tham so -Range sai dinh dang, phai la 'Ten=batdau:buoc:ketthuc': $r" }
    $n = $matches[1].Trim()
    if (-not $valid.ContainsKey($n)) { throw "Input '$n' khong ton tai trong $($src.Name)" }
    $inputs[$n] = "$($matches[2])||$($matches[2])||$($matches[3])||$($matches[4])||Y"
    $optimize = $true
}
$ReportName = "eatls_opt_$Tag"

$modelId = switch ($Model) { "EveryTick" {0} "OHLC_M1" {1} "OpenPrices" {2} }

# ----------------------------------------------------------------- ghi file ini
# BAT BUOC ASCII khong BOM. PowerShell 5.1 'Set-Content -Encoding utf8' ghi CO BOM,
# MT5 se bo qua muc [Tester] va mo giao dien thay vi chay tester.
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("[Common]")
$lines.Add("Login=$($acc['Login'])")
$lines.Add("Password=$($acc['Password'])")
$lines.Add("Server=$($acc['Server'])")
$lines.Add("")
$lines.Add("[Tester]")
$lines.Add("Expert=$($src.BaseName).ex5")
$lines.Add("Symbol=$Symbol")
$lines.Add("Period=$Period")
$lines.Add("Model=$modelId")
$lines.Add("FromDate=$From")
$lines.Add("ToDate=$To")
$lines.Add("Deposit=$Deposit")
$lines.Add("Currency=$Currency")
$lines.Add("Leverage=$Leverage")
if ($optimize) {
    $lines.Add("Optimization=1")            # 1 = quet het moi to hop (slow complete)
    $lines.Add("OptimizationCriterion=6")   # 6 = gia tri OnTester()
    $lines.Add("Report=$ReportName")
    $lines.Add("ReplaceReport=1")
} else {
    $lines.Add("Optimization=0")
}
$lines.Add("Visual=0")
$lines.Add("ShutdownTerminal=1")
$lines.Add("")
$lines.Add("[TesterInputs]")
foreach ($k in $inputs.Keys) { $lines.Add("$k=$($inputs[$k])") }

$ini = Join-Path $env:TEMP "eatls_run_$Tag.ini"
[System.IO.File]::WriteAllText($ini, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

# --------------------------------------------------------------------- chay
# Terminal dang mo thi /config KHONG kich hoat tester ma chi bat lai cua so cu,
# co lan no con tu gan EA len chart tai khoan that. Phai dong truoc.
# CHI tat DUNG ban MT5 sap dung. Truoc day dong nay la `Get-Process terminal64 |
# Stop-Process -Force` -> giet MOI ban MT5 dang mo, ke ca lot backtest cua topic khac
# dang chay o ban cai khac. Loc theo duong dan tien trinh de hai ben doc lap nhau.
Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
    $exe = $null
    try { $exe = $_.Path } catch { }
    if ($exe -eq $TERM) {
        Write-Host "[tat] $exe (PID $($_.Id))" -ForegroundColor DarkGray
        Stop-Process -Id $_.Id -Force
    } elseif ($exe) {
        Write-Host "[giu nguyen] $exe (PID $($_.Id)) - ban cai khac, khong dung toi" -ForegroundColor DarkGray
    }
}
Start-Sleep -Seconds 2

# Nho so dong log truoc khi chay de cat dung phan cua luot nay (log la file theo
# ngay, gom nhieu luot noi duoi nhau).
$before = 0; $beforeFile = ""
$cur = Get-ChildItem $TestLog -Filter *.log -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($cur) { $beforeFile = $cur.FullName; $before = (Get-Content $cur.FullName -Encoding Unicode).Count }

Write-Host "[$Tag] $Symbol $Period $From..$To | $($src.BaseName) | $($inputs.Count) input | dang chay..."
$sw = [Diagnostics.Stopwatch]::StartNew()
& $TERM /config:$ini | Out-Null
$sw.Stop()
Remove-Item $ini -Force -ErrorAction SilentlyContinue

$after = Get-ChildItem $TestLog -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$all   = Get-Content $after.FullName -Encoding Unicode
$slice = if ($after.FullName -eq $beforeFile) { $all | Select-Object -Skip $before } else { $all }
$dst   = Join-Path $LogDir "out_$Tag.log"
$slice | Set-Content $dst -Encoding UTF8

$done = ($slice | Select-String "final balance" | Measure-Object).Count
$mm = [int]$sw.Elapsed.TotalMinutes; $ss = [int]($sw.Elapsed.Seconds)
if ($done -eq 0 -and -not $optimize) {
    Write-Warning "[$Tag] KHONG thay dong 'final balance' -> luot chay bi cat ngang, phai chay lai."
}
Write-Host "[$Tag] xong sau $mm phut $ss giay -> $dst"

# ------------------------------------------ doc bao cao toi uu hoa (SpreadsheetML)
# MT5 luu bao cao optimization vao thu muc du lieu terminal duoi dang XML Excel 2003.
# Chuyen thanh CSV: moi dong mot to hop tham so, cot = chi so + gia tri input.
if ($optimize) {
    $xmlPath = Join-Path $DataFolder "$ReportName.xml"
    if (-not (Test-Path $xmlPath)) {
        Write-Warning "[$Tag] KHONG thay bao cao toi uu hoa $xmlPath"
    } else {
        [xml]$x = Get-Content $xmlPath -Raw
        $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
        $ns.AddNamespace("ss", "urn:schemas-microsoft-com:office:spreadsheet")
        $rowsXml = $x.SelectNodes("//ss:Worksheet[1]/ss:Table/ss:Row", $ns)
        $csv = foreach ($row in $rowsXml) {
            ($row.SelectNodes("ss:Cell/ss:Data", $ns) | ForEach-Object { $_.InnerText }) -join ","
        }
        $csvPath = Join-Path $LogDir "opt_$Tag.csv"
        $csv | Set-Content $csvPath -Encoding UTF8
        Write-Host "[$Tag] $($csv.Count - 1) to hop -> $csvPath"
    }
}

if ($skipped.Count -gt 0) {
    Write-Host "[$Tag] bo qua $($skipped.Count) khoa trong .set khong con la input: $($skipped -join ', ')" -ForegroundColor DarkGray
}
