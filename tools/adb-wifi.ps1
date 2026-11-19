<#
  oppo-watch-agent-pet / enable adb over Wi-Fi (tcpip 5555)
  Why   : the dock covers the watch back (PPG/ECG/wrist-temp sensors), so docked
          tests cannot see living tissue. With adb over Wi-Fi the watch can be
          taken OFF the dock - held in hand or worn - for meaningful sensor values.
  Prereq: watch on dock + USB debugging authorized;
          watch connected to the same Wi-Fi/LAN as this PC
          (Settings -> Network & connections -> WLAN on the watch).
  Usage : powershell -NoProfile -ExecutionPolicy Bypass -File adb-wifi.ps1
  After : unplug the dock USB; adb keeps working over Wi-Fi.
          Revert anytime: plug USB again, or run 'adb usb'.
  Output: connected <ip>:5555; then run device-test.ps1 with the watch in hand/on wrist.
  ASCII-only on purpose (PS 5.1 encoding safety, see AGENT.md section 10).
#>
param([string]$AdbPath = "")
$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# ---------- 0 locate adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "platform-tools\adb.exe")
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $AdbPath = $c; break } }
}
if (-not $AdbPath) { $cmd = Get-Command adb -ErrorAction SilentlyContinue; if ($cmd) { $AdbPath = $cmd.Source } }
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
    Write-Output "[X] adb.exe not found. Unzip platform-tools into tools\platform-tools or pass -AdbPath."
    exit 1
}
Write-Output "[i] using adb: $AdbPath"

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $o = & $AdbPath @AdbArgs 2>&1
    return (($o | Out-String) -replace "`r", "").Trim()
}

# ---------- 1 device over USB ----------
$dev = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\S+\s+device$" } | Select-Object -First 1
if (-not $dev) {
    Write-Output "[X] no device over USB right now."
    Write-Output "    Put the watch ON THE DOCK first (USB debugging authorized), then rerun this script."
    exit 1
}
Write-Output "[OK] device over USB: $dev"

# ---------- 2 watch Wi-Fi IP ----------
$ipOut = Invoke-Adb shell "ip -f inet addr show wlan0"
$ip = ""
if ($ipOut -match "inet (\d+\.\d+\.\d+\.\d+)") { $ip = $Matches[1] }
if (-not $ip) {
    $routeOut = Invoke-Adb shell "ip route"
    if ($routeOut -match "src (\d+\.\d+\.\d+\.\d+)") { $ip = $Matches[1] }
}
if (-not $ip) {
    Write-Output "[X] watch has no Wi-Fi IP (wlan0 down / not connected)."
    Write-Output "    On the watch: Settings -> Network & connections -> WLAN -> join the same LAN as this PC."
    Write-Output "    (Captive-portal networks are NOT supported per OPPO docs - use a normal home/office Wi-Fi.)"
    exit 1
}
Write-Output "[i] watch Wi-Fi IP: $ip"

# ---------- 3 switch adb to tcpip ----------
$r = Invoke-Adb tcpip 5555
Write-Output "[i] adb tcpip 5555: $r"
Start-Sleep -Seconds 3

# ---------- 4 connect over Wi-Fi ----------
Write-Output ""
Write-Output "NEXT STEPS (you do these):"
Write-Output "  1) UNPLUG the dock USB cable from the PC"
Write-Output "  2) Take the watch off the dock - hold it in your hand or wear it"
Write-Output "  3) Come back here and press ENTER to connect over Wi-Fi"
Read-Host "  Press ENTER after unplugging"

$c = Invoke-Adb connect "$ip`:5555"
Write-Output "[i] adb connect: $c"

$dev2 = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+:5555\s+device$" } | Select-Object -First 1
if ($dev2) {
    Write-Output ""
    Write-Output "[OK] adb over Wi-Fi active: $dev2"
    Write-Output "     Watch is now OFF the dock and testable in hand / on wrist."
    Write-Output "     Run:  .\device-test.ps1   (finger on the back; for ECG: back against palm + finger on crown)"
    Write-Output "     Revert later: plug USB again or run 'adb usb'."
} else {
    Write-Output ""
    Write-Output "[!] $ip`:5555 not listed as device. Checklist:"
    Write-Output "    - dock USB fully unplugged? (USB and tcpip fight over the same device)"
    Write-Output "    - watch still on and screen unlocked?"
    Write-Output "    - PC and watch on the same subnet? firewall blocking 5555?"
    Write-Output "    Retry: $AdbPath connect ${ip}:5555"
}
