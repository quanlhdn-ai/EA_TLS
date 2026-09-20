<#
.SYNOPSIS
    Chay mot loat backtest tu file cau hinh .psd1, co chot chan cho cac bay da gap.

.DESCRIPTION
    Doc danh sach luot chay tu file .psd1 va goi Run-Backtest.ps1 lan luot tung luot.

    Chot chan tu dong:
      1. KHONG khoi dong neu ban MT5 dich dang chay (Run-Backtest se tat no -> giet bot demo
         dang giao dich). Bo qua bang -AllowStopLive.
      2. Tat che do ngu khi cam sac trong luc chay, va KHOI PHUC dung gia tri cu khi xong
         (ke ca khi loat bi loi giua chung).
      3. Sau moi luot toi uu hoa (-Range), so to hop trong bao cao voi luoi mong doi; MT5 hay
         bo sot to hop. Voi -FillMissing, tu chay bu tung to hop thieu bang luot don le.
      4. Luot loi khong lam dung ca loat; moi luot duoc ghi trang thai vao file tom tat.

    Dinh dang file .psd1 (xem jobs\example_bot_tls.psd1):
        @{
          Name     = "ten_loat"
          Defaults = @{ Bot = "BOT_TLS"; Preset = "demo.set"; Period = "M5"; Set = @("Inp_No_SL=false") }
          Jobs     = @(
            @{ Tag = "tp4_43m"; From = "2023.02.01"; To = "2026.09.12"; Matrix = "M_S_TP4.csv" }
            @{ Tag = "minsl_43m"; From = "2023.02.01"; To = "2026.09.12"; Range = @("Inp_Min_SL_Pips=0:30:150") }
          )
        }
    Set cua Defaults duoc GHEP voi Set cua tung luot (luot ghi de khi trung ten input).

.EXAMPLE
    .\Run-Batch.ps1 -JobFile .\jobs\example_bot_tls.psd1 -FillMissing

.EXAMPLE
    # Kiem tra file job va xem to hop nao bi thieu ma KHONG chay MT5
    .\Run-Batch.ps1 -JobFile .\jobs\example_bot_tls.psd1 -FillMissing -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobFile,
    [switch]$FillMissing,
    [switch]$AllowStopLive,
    [switch]$NoKeepAwake,
    # Chi in ke hoach va doi chieu to hop voi CSV toi uu hoa da co; khong chay MT5, khong doi che do ngu.
    [switch]$DryRun,
    [string]$Account = ""
)

$ErrorActionPreference = "Stop"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::InvariantCulture
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir   = Join-Path $ToolsDir "logs"
$Runner   = Join-Path $ToolsDir "Run-Backtest.ps1"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$cfg = Import-PowerShellDataFile -Path $JobFile
if (-not $cfg.Jobs) { throw "File $JobFile khong co muc Jobs." }
$batchName = if ($cfg.Name) { $cfg.Name } else { [IO.Path]::GetFileNameWithoutExtension($JobFile) }
$defaults  = if ($cfg.Defaults) { $cfg.Defaults } else { @{} }
$summary   = Join-Path $LogDir "batch_$($batchName)_summary.txt"

# ---------------------------------------------------------------- chot chan 1: MT5 dang chay
if ($Account -eq "") { $Account = Join-Path $ToolsDir "account.local.ini" }
$termPath = ""
if (Test-Path $Account) {
    Get-Content $Account | ForEach-Object { if ($_ -match '^\s*Terminal\s*=\s*(.+)$') { $termPath = $matches[1].Trim() } }
}
if ($termPath -ne "" -and -not $AllowStopLive) {
    $live = Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $termPath }
    if ($live) {
        $msg = ("Ban MT5 dich dang chay (PID {0}: {1}). Run-Backtest se TAT no, neu dang co bot demo/that " +
                "tren do se bi dung. Tat MT5 truoc, hoac chay lai voi -AllowStopLive neu chac chan.") -f $live[0].Id, $live[0].MainWindowTitle
        if ($DryRun) { Write-Warning $msg } else { throw $msg }
    }
}

# ----------------------------------------------------------------------- tien ich
function Merge-SetList([string[]]$base, [string[]]$over) {
    $h = [ordered]@{}
    foreach ($s in @($base) + @($over)) { if ($s -match '^([^=]+)=(.*)$') { $h[$matches[1].Trim()] = $matches[2].Trim() } }
    return @($h.Keys | ForEach-Object { "$_=$($h[$_])" })
}
function Expand-Range([string]$spec) {
    if ($spec -notmatch '^([^=]+)=(-?[0-9.]+):([0-9.]+):(-?[0-9.]+)$') { throw "Range sai dinh dang: $spec" }
    $name = $matches[1].Trim(); $a = [double]$matches[2]; $st = [double]$matches[3]; $b = [double]$matches[4]
    $vals = @(); $v = $a
    while ($v -le $b + 1e-9) { $vals += [math]::Round($v, 8); $v += $st }
    return [pscustomobject]@{ Name = $name; Values = $vals }
}
function Get-Combos($ranges) {
    $combos = @(@{})
    foreach ($r in $ranges) {
        $next = @()
        foreach ($c in $combos) { foreach ($v in $r.Values) { $n = @{} + $c; $n[$r.Name] = $v; $next += $n } }
        $combos = $next
    }
    return $combos
}
function Get-PowerAc([string]$setting) {
    $g = (powercfg /getactivescheme) -replace '.*GUID: ([0-9a-f\-]+).*', '$1'
    $l = (powercfg /query $g SUB_SLEEP $setting) | Select-String 'Current AC Power Setting Index'
    if ($l) { return [Convert]::ToInt32($l.ToString().Split(':')[1].Trim(), 16) } else { return $null }
}
function Invoke-Run([hashtable]$job, [string[]]$setList, [string[]]$rangeList, [string]$tag) {
    $args2 = @{}
    foreach ($k in @('Bot','Preset','Period','Symbol','Deposit','Matrix','Model','From','To')) {
        if ($job.ContainsKey($k) -and $job[$k]) { $args2[$k] = $job[$k] }
        elseif ($defaults.ContainsKey($k) -and $defaults[$k]) { $args2[$k] = $defaults[$k] }
    }
    $args2['Tag'] = $tag
    if ($setList.Count -gt 0)   { $args2['Set']   = $setList }
    if ($rangeList.Count -gt 0) { $args2['Range'] = $rangeList }
    if ($Account -ne "")        { $args2['Account'] = $Account }
    if ($DryRun) {
        $desc = ($args2.GetEnumerator() | Sort-Object Name | ForEach-Object {
            if ($_.Value -is [array]) { "-$($_.Name) @(" + (($_.Value | ForEach-Object { "'$_'" }) -join ',') + ")" } else { "-$($_.Name) $($_.Value)" }
        }) -join ' '
        Write-Host "[DRY] Run-Backtest.ps1 $desc"
        return [pscustomobject]@{ Ok = $true; Error = ""; Minutes = 0 }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Runner @args2 | Out-Host; $ok = $true; $err = "" } catch { $ok = $false; $err = $_.Exception.Message }
    $sw.Stop()
    return [pscustomobject]@{ Ok = $ok; Error = $err; Minutes = [math]::Round($sw.Elapsed.TotalMinutes, 1) }
}

# ------------------------------------------------------------- chot chan 2: che do ngu
$oldStandby = $null; $oldHibern = $null
if (-not $NoKeepAwake -and -not $DryRun) {
    $oldStandby = Get-PowerAc 'STANDBYIDLE'
    $oldHibern  = Get-PowerAc 'HIBERNATEIDLE'
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Loat: $batchName | bat dau $(Get-Date -Format 'yyyy-MM-dd HH:mm') | file: $JobFile")
try {
    foreach ($job in $cfg.Jobs) {
        $tag       = $job.Tag
        $fillLines = New-Object System.Collections.Generic.List[string]
        $setList  = Merge-SetList $defaults.Set $job.Set
        $rangeRaw = @($job.Range | Where-Object { $_ })
        $res      = Invoke-Run $job $setList $rangeRaw $tag
        $status   = if ($res.Ok) { "OK" } else { "LOI: $($res.Error)" }

        if ($res.Ok -and $rangeRaw.Count -eq 0 -and -not $DryRun) {
            $log = Join-Path $LogDir "out_$tag.log"
            if (-not (Test-Path $log) -or -not (Select-String -Path $log -Pattern 'final balance' -Quiet)) { $status = "CAT NGANG (khong co final balance)" }
        }

        # ------------------------------------------ chot chan 3: to hop toi uu hoa bi sot
        if ($res.Ok -and $rangeRaw.Count -gt 0) {
            $ranges   = @($rangeRaw | ForEach-Object { Expand-Range $_ })
            $expected = Get-Combos $ranges
            $csv      = Join-Path $LogDir "opt_$tag.csv"
            $present  = if (Test-Path $csv) { @(Import-Csv $csv) } else { @() }
            $missing  = @()
            foreach ($c in $expected) {
                $found = $false
                foreach ($row in $present) {
                    $all = $true
                    foreach ($r in $ranges) {
                        $cell = $row.($r.Name)
                        if ($null -eq $cell -or [math]::Abs([double]$cell - [double]$c[$r.Name]) -gt 1e-6) { $all = $false; break }
                    }
                    if ($all) { $found = $true; break }
                }
                if (-not $found) { $missing += ,$c }
            }
            $status = "OK toi uu hoa: $($present.Count)/$($expected.Count) to hop"
            if ($missing.Count -gt 0) {
                $status += " | THIEU: " + (($missing | ForEach-Object { $m = $_; (($m.Keys | Sort-Object | ForEach-Object { "$_=$($m[$_])" }) -join ",") }) -join " ; ")
                if ($FillMissing) {
                    foreach ($m in $missing) {
                        $pairs   = @($m.Keys | Sort-Object | ForEach-Object { "$_=$($m[$_])" })
                        $fillTag = "$($tag)_bu_" + (($pairs -join "_") -replace '[^A-Za-z0-9_.-]', '')
                        $fr      = Invoke-Run $job (Merge-SetList $setList $pairs) @() $fillTag
                        $flog    = Join-Path $LogDir "out_$fillTag.log"
                        $fok     = $fr.Ok -and ($DryRun -or ((Test-Path $flog) -and (Select-String -Path $flog -Pattern 'final balance' -Quiet)))
                        $fillLines.Add("    bu $fillTag : " + $(if ($fok) { "OK" } else { "LOI/CAT NGANG $($fr.Error)" }) + " ($($fr.Minutes) phut)")
                    }
                }
            }
        }
        $lines.Add("  $tag : $status ($($res.Minutes) phut)")
        foreach ($fl in $fillLines) { $lines.Add($fl) }
        [IO.File]::WriteAllLines($summary, [string[]]$lines)
    }
}
finally {
    if (-not $NoKeepAwake -and -not $DryRun) {
        if ($null -ne $oldStandby) { powercfg /change standby-timeout-ac ([int]($oldStandby / 60)) | Out-Null }
        if ($null -ne $oldHibern)  { powercfg /change hibernate-timeout-ac ([int]($oldHibern / 60)) | Out-Null }
    }
    $lines.Add("Ket thuc $(Get-Date -Format 'yyyy-MM-dd HH:mm')" + $(if ($DryRun) { " | CHAY THU, khong chay MT5" } elseif (-not $NoKeepAwake) { " | da khoi phuc che do ngu" } else { "" }))
    [IO.File]::WriteAllLines($summary, [string[]]$lines)
    Get-Content $summary
}
