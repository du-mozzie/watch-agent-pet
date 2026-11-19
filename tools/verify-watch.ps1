<#
  oppo-watch-agent-pet baseline probe (read-only)
  Usage : powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-watch.ps1 [-AdbPath <adb.exe>] [-WaitSeconds <n>]
  What  : device connection check, system baseline (model/Android/ABI/screen/battery),
          full sensor list + keyword hits (SpO2/ECG/wrist-temp -> sideload readability verdict)
  Output: watch-report-<timestamp>.md + sensorservice-dump.txt in script dir
  Note  : ASCII-only on purpose - PS 5.1 mis-parses BOM-less UTF-8 scripts with Chinese
          text as GBK and breaks the parser (see AGENT.md section 10, pitfall 1).
#>

param(
    [string]$AdbPath = "",
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# ---------- 0 locate adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "platform-tools\adb.exe")
    )
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath $c) { $AdbPath = $c; break }
    }
}
if (-not $AdbPath) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $AdbPath = $cmd.Source }
}
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
    Write-Host "[X] adb.exe not found. Unzip platform-tools into tools\platform-tools or pass -AdbPath." -ForegroundColor Red
    exit 1
}
Write-Host "[i] using adb: $AdbPath" -ForegroundColor Cyan

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $o = & $AdbPath @AdbArgs 2>&1
    return (($o | Out-String) -replace "`r", "").Trim()
}
function Say { param($Msg, $Color = "Gray") Write-Host $Msg -ForegroundColor $Color }
function Section {
    param($T)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor DarkGray
    Write-Host "  $T" -ForegroundColor White
    Write-Host ("=" * 64) -ForegroundColor DarkGray
}

$Report = [System.Text.StringBuilder]::new()
function Add-Report {
    param($Line)
    [void]$Report.AppendLine($Line)
    Write-Host $Line
}

# ---------- 1 connection check ----------
Section "1. Device connection"
$verLine = (Invoke-Adb version) -split "`n" | Select-Object -First 1
Add-Report "adb version: $verLine"

function Get-DeviceLines {
    $raw = Invoke-Adb devices
    return ($raw -split "`n" | Where-Object { $_ -match "^\S+\s+(device|unauthorized|offline|recovery|sideload)$" })
}

$devLines = Get-DeviceLines
if (-not $devLines) {
    Say ""
    Say "[!] No device yet - waiting up to $WaitSeconds s..." "Yellow"
    Say "    Meanwhile: watch on dock + dock USB to PC, USB debugging on, tap 'always allow' on the watch."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        Write-Host "." -NoNewline
        $devLines = Get-DeviceLines
        if ($devLines) { break }
    }
    Write-Host ""
    if (-not $devLines) {
        Say "[X] Timed out, still no device. Checklist:" "Red"
        Say "    1) dock USB cable plugged into this PC (try a rear port)"
        Say "    2) cable must carry data (many cables are charge-only)"
        Say "    3) USB debugging enabled in Developer options on the watch"
        Say "    4) 'Allow USB debugging?' popup on the watch not yet confirmed"
        Say "    5) unknown device in Device Manager (install USB driver)"
        Say ""
        Say "    Fix then rerun, or extend the wait: .\verify-watch.ps1 -WaitSeconds 120" "Red"
        exit 1
    }
    Say "[OK] device attached." "Green"
}

$devState = ($devLines -join "`n")
Add-Report "adb devices:"
Add-Report $devState

if ($devState -match "unauthorized") {
    Say ""
    Say "[!] State is unauthorized: an 'Allow USB debugging?' popup is showing on the watch - tick 'always allow' and confirm." "Yellow"
    Say "    No popup? re-seat the watch on the dock; still none: Developer options -> revoke USB debugging authorizations, retry." "Yellow"
    exit 1
}
if ($devState -match "offline") {
    Say "[!] State is offline: run 'adb kill-server', re-seat the dock, rerun this script." "Yellow"
    exit 1
}
Add-Report "-> device authorized, connection OK"

# ---------- 2 system baseline ----------
Section "2. Device baseline"
$propList = @(
    @("model",       "ro.product.model"),
    @("device",      "ro.product.device"),
    @("brand",       "ro.product.brand"),
    @("manufacturer", "ro.product.manufacturer"),
    @("android",     "ro.build.version.release"),
    @("sdk(api)",    "ro.build.version.sdk"),
    @("cpu abi",     "ro.product.cpu.abi"),
    @("abi list",    "ro.product.cpu.abilist"),
    @("fingerprint", "ro.build.fingerprint")
)
foreach ($p in $propList) {
    $v = Invoke-Adb shell getprop $p[1]
    if ([string]::IsNullOrWhiteSpace($v)) { $v = "(empty)" }
    Add-Report ("{0,-14}: {1}" -f $p[0], $v)
}

$wmSize = (Invoke-Adb shell wm size) -replace "`n", " ; "
$wmDen  = (Invoke-Adb shell wm density) -replace "`n", " ; "
Add-Report "screen size   : $wmSize"
Add-Report "screen density: $wmDen"

$mem = Invoke-Adb shell cat /proc/meminfo
$memLine = ($mem -split "`n" | Where-Object { $_ -match "MemTotal" } | Select-Object -First 1)
Add-Report "memory        : $($memLine.Trim())"

$bat = Invoke-Adb shell dumpsys battery
$batLines = ($bat -split "`n" | Where-Object { $_ -match "^  (level|status|health|temperature|voltage):" })
foreach ($b in $batLines) { Add-Report ("battery       : " + $b.Trim()) }

# ---------- 3 sensors (the key part) ----------
Section "3. Sensor list - decides SpO2/ECG/wrist-temp sideload readability"
$sensorRaw = Invoke-Adb shell dumpsys sensorservice
$sensorFile = Join-Path $ScriptDir "sensorservice-dump.txt"
$sensorRaw | Out-File -LiteralPath $sensorFile -Encoding utf8
Add-Report "raw dump saved: $sensorFile"

$sensorLines = $sensorRaw -split "`n"
# lines inside "Sensor List" carrying a type
$typeLines = $sensorLines | Where-Object { $_ -match "type" -and $_ -match "\|" }

Add-Report ""
Add-Report ("sensor entries: " + $typeLines.Count)
$shown = 0
foreach ($l in $typeLines) {
    if ($shown -ge 45) { Add-Report "  ... (rest in dump file)"; break }
    Add-Report ("  " + $l.Trim())
    $shown++
}

# keyword hits
Add-Report ""
Add-Report "keyword hits (capability boundary):"
$kwSets = @(
    @("heart rate",     @("heart", "type_heart_rate", "hr_rate")),
    @("SpO2",          @("ppg_spo", "spo2", "blood", "oxygen", "oximeter", "pulse_ox")),
    @("ECG",           @("ecg", "electrocardio")),
    @("wrist temp",    @("wrist", "skin_temp", "temperature"))
)
foreach ($ks in $kwSets) {
    $label = $ks[0]
    $hits = @()
    foreach ($k in $ks[1]) {
        $hits += ($sensorLines | Where-Object { $_.ToLower().Contains($k) })
    }
    $hits = $hits | Select-Object -Unique
    if ($hits.Count -gt 0) {
        Add-Report ("  [HIT] {0} ({1} lines)" -f $label, $hits.Count)
        foreach ($h in ($hits | Select-Object -First 3)) {
            Add-Report ("         " + $h.Trim())
        }
    } else {
        Add-Report ("  [MISS] {0}" -f $label)
    }
}

# ---------- 4 sideload environment ----------
Section "4. Sideload environment"
$third = Invoke-Adb shell pm list packages -3
$thirdLines = ($third -split "`n" | Where-Object { $_ -match "package:" })
Add-Report ("installed 3rd-party packages: " + $thirdLines.Count)
foreach ($t in ($thirdLines | Select-Object -First 12)) { Add-Report ("  " + $t.Trim()) }

$inst = Invoke-Adb shell pm list packages com.oppo.watch
Add-Report "system watch packages (sample):"
foreach ($t in (($inst -split "`n" | Where-Object { $_ -match "package:" } | Select-Object -First 6))) { Add-Report ("  " + $t.Trim()) }

# ---------- 5 foreground window ----------
Section "5. Foreground window"
$win = Invoke-Adb shell dumpsys window
$focus = ($win -split "`n" | Where-Object { $_ -match "mCurrentFocus|mFocusedApp" } | Select-Object -First 4)
foreach ($f in $focus) { Add-Report ("  " + $f.Trim()) }

# ---------- 6 report ----------
Section "6. Done"
$reportPath = Join-Path $ScriptDir ("watch-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
$header = "# OPPO Watch probe report`n`ntime: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "`n`n"
$header + $Report.ToString() | Out-File -LiteralPath $reportPath -Encoding utf8
Write-Host ""
Write-Host "report saved: $reportPath" -ForegroundColor Green
Write-Host "Open the report for the sensor list and keyword hits; interpret against docs/tutorials/02-sensor-probe.md" -ForegroundColor Green
