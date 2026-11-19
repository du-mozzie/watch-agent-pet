<#
  oppo-watch-agent-pet / on-device test session script
  Covers: P1 physical keys (getevent) + private sensor data validation (Sensor Probe APK)
  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File device-test.ps1
  Before: watch on dock + USB debugging on + authorized (docs/tutorials/01-getting-started.md)
          APK built by android\sensor-probe\build.ps1
  Output: results\device-test-<timestamp>\ (getevent log + logcat + sensor registrations + summary)
  Device actions: install probe app + log capture only; otherwise read-only.
  ASCII-only on purpose (PS 5.1 encoding safety); console re-encoded to UTF-8 for adb output.
#>
param(
    [string]$AdbPath = "",
    [int]$GeteventSeconds = 25,
    [int]$LogcatSeconds = 20
)
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$repo = Split-Path $ScriptDir -Parent
$pkg = "com.owapet.sensorprobe"

function Section { param($T) Write-Output ""; Write-Output ("=" * 60); Write-Output "  $T"; Write-Output ("=" * 60) }
function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $o = & $AdbPath @AdbArgs 2>&1
    return (($o | Out-String) -replace "`r", "").Trim()
}

# ---------- 0 locate adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "platform-tools\adb.exe"),
        (Join-Path (Split-Path $repo -Parent) "tools\platform-tools\adb.exe")
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $AdbPath = $c; break } }
}
if (-not $AdbPath) { $cmd = Get-Command adb -ErrorAction SilentlyContinue; if ($cmd) { $AdbPath = $cmd.Source } }
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
    Write-Output "[X] adb.exe not found. Unzip platform-tools into tools\platform-tools or pass -AdbPath."
    exit 1
}
Write-Output "[i] adb: $AdbPath"

# ---------- 1 wait for device ----------
Section "1. Waiting for device (max 30s)"
$deadline = (Get-Date).AddSeconds(30)
$devLine = ""
while ((Get-Date) -lt $deadline) {
    $devLine = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\S+\s+device$" } | Select-Object -First 1
    if ($devLine) { break }
    Start-Sleep -Seconds 2
}
if (-not $devLine) {
    Write-Output "[X] no device in 30s. Check: dock->PC usb, debugging on, tap 'always allow' on watch."
    exit 1
}
Write-Output "[OK] $devLine"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $repo "results\device-test-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Output "[i] results dir: $outDir"

# ---------- 2 P1: physical key capture ----------
Section "2. P1 physical keys (getevent, $GeteventSeconds s)"
Write-Output "  When the timer starts, do each of these on the watch:"
Write-Output "    a) rotate the crown 5-10 detents both ways"
Write-Output "    b) short-press the side function key once"
Write-Output "    c) short-press the crown once"
Write-Output "    d) raise/lower the wrist once"
Read-Host  "  Press ENTER here to start the capture"
Write-Output "  >>> GO (keep going until it says done)"
$ev = Invoke-Adb shell "timeout $GeteventSeconds getevent -l"
$evFile = Join-Path $outDir "getevent.txt"
$ev | Out-File -LiteralPath $evFile -Encoding utf8
$evLines = @($ev -split "`n")
$keyLines = @($evLines | Where-Object { $_ -match "KEY_" })
$relLines = @($evLines | Where-Object { $_ -match "EV_REL" })
$keyNames = @($keyLines | ForEach-Object { if ($_ -match "(KEY_[A-Z0-9_]+)") { $Matches[1] } } | Sort-Object -Unique)
Write-Output ("  captured {0} lines ({1} KEY_ lines, {2} EV_REL lines)" -f $evLines.Count, $keyLines.Count, $relLines.Count)
if ($keyNames.Count -gt 0) { Write-Output ("  unique keys: {0}" -f ($keyNames -join ", ")) }
if ($relLines.Count -gt 0) { Write-Output "  NOTE: EV_REL lines present -> crown rotation may report as relative axis, not keys" }

# ---------- 3 install probe APK ----------
Section "3. Install Sensor Probe APK"
$apk = Join-Path $repo "android\sensor-probe\build\sensor-probe-debug.apk"
if (-not (Test-Path $apk)) {
    Write-Output "[X] APK not found: $apk"
    Write-Output "    Build it first: powershell -File android\sensor-probe\build.ps1"
    exit 1
}
$inst = Invoke-Adb install -r $apk
Write-Output "  $inst"

# ---------- 4 grant BODY_SENSORS ----------
Section "4. Grant BODY_SENSORS"
$g = Invoke-Adb shell pm grant $pkg android.permission.BODY_SENSORS
if ([string]::IsNullOrWhiteSpace($g)) {
    Write-Output "  [OK] granted via pm grant"
} else {
    Write-Output "  [!] pm grant said: $g"
    Write-Output "      fallback: grant it on the watch when the app asks (then rerun this script)"
}

# ---------- 5 launch + logcat capture ----------
Section "5. Launch probe + capture logcat ($LogcatSeconds s)"
Invoke-Adb logcat -c | Out-Null
$st = Invoke-Adb shell am start -n "$pkg/.MainActivity"
Write-Output "  $st"
Write-Output "  >>> keep the app in foreground; keep a finger on the back sensor so"
Write-Output "      the PPG/heart-rate sensors see live tissue during the capture"
$lc = Invoke-Adb shell "timeout $LogcatSeconds logcat -s PROBE STATS -v time"
$lcFile = Join-Path $outDir "logcat-probe.txt"
$lc | Out-File -LiteralPath $lcFile -Encoding utf8
$lcLines = @($lc -split "`n" | Where-Object { $_.Trim() })
$first = @($lcLines | Where-Object { $_ -match "PROBE" })
$stats = @($lcLines | Where-Object { $_ -match "STATS" })
Write-Output ("  captured {0} PROBE lines, {1} STATS lines -> {2}" -f $first.Count, $stats.Count, $lcFile)

# ---------- 6 sensor service registrations ----------
Section "6. Sensor service registrations (our package)"
$dump = Invoke-Adb shell dumpsys sensorservice
$dumpFile = Join-Path $outDir "sensorservice-dump.txt"
$dump | Out-File -LiteralPath $dumpFile -Encoding utf8
$ours = @(($dump -split "`n") | Where-Object { $_ -match "owapet" })
if ($ours.Count -gt 0) {
    Write-Output ("  found {0} registration lines mentioning our package:" -f $ours.Count)
    $ours | Select-Object -First 25 | ForEach-Object { Write-Output "    $_" }
} else {
    Write-Output "  no registrations mentioning owapet (app may have been killed or sensors rejected)"
}

# ---------- 7 summary ----------
Section "7. Summary"
$sum = @()
$sum += "# device-test summary $stamp"
$sum += ""
$sum += "device: $(($devLine -split "`t" | Select-Object -First 1))"
$sum += ""
$sum += "## P1 keys"
if ($keyNames.Count -gt 0) { $sum += "unique keys: $($keyNames -join ', ')" } else { $sum += "no KEY_ events captured" }
$sum += "KEY lines: $($keyLines.Count); EV_REL lines: $($relLines.Count)"
$sum += ""
$sum += "## Sensor probe"
$sum += "PROBE lines: $($first.Count); STATS lines: $($stats.Count)"
$sum += "registered-sensor lines mentioning owapet in dumpsys: $($ours.Count)"
$sum += ""
$sum += "## Key log lines (first 60)"
$sum += $lcLines | Select-Object -First 60
$sumPath = Join-Path $outDir "summary.md"
$sum | Out-File -LiteralPath $sumPath -Encoding utf8
Write-Output "  summary -> $sumPath"
Write-Output ""
Write-Output "DONE. Hand the results folder to the agent for interpretation:"
Write-Output "  $outDir"
