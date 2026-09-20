# Ham dung chung cho cac script trong Tools. Dot-source: . "$PSScriptRoot\BacktestLib.ps1"

# Doc chi so cua mot luot chay tu file log do Run-Backtest.ps1 sinh ra.
# Tra ve $null neu log khong ton tai. Done = $false neu thieu dong 'final balance'
# (luot bi cat ngang, khong duoc dung so lieu).
function Get-RunMetrics([string]$LogPath) {
    if (-not (Test-Path $LogPath)) { return $null }
    $t = Get-Content $LogPath
    function _m([string]$pat) {
        foreach ($line in $t) { $x = [regex]::Match($line, $pat); if ($x.Success) { return $x.Groups[1].Value } }
        return ""
    }
    $num = { param($s) if ($s -eq "") { [double]::NaN } else { [double]$s } }
    [pscustomobject]@{
        Done    = (($t | Select-String "final balance" | Measure-Object).Count -gt 0)
        NetPct  = & $num (_m 'Lai rong=[-0-9.]+ \(([-0-9.]+)%\)')
        DDBal   = & $num (_m 'Sut von: balance=([0-9.]+)%')
        DDEq    = & $num (_m 'equity tuong doi=([0-9.]+)%')
        Trades  = & $num (_m 'So lenh=([0-9]+)')
        WinPct  = & $num (_m 'Ty le thang=([0-9.]+)%')
        PF      = & $num (_m 'Profit factor=([0-9.]+)')
        Balance = & $num (_m 'final balance ([0-9.]+)')
        Errors  = ($t | Select-String -Pattern 'FAILED|failed |LOI:' | Measure-Object).Count
    }
}
