<#
  oppo-watch-agent-pet / 开启 Wi-Fi adb（中文提示版）
  目的：底座会盖住表背（PPG/ECG/腕温传感器），停靠时测不到活体数据。
        开启 Wi-Fi adb 后可拔掉底座，手持/佩戴手表测试，拿到真实数值。
  前置：手表在底座 + USB 调试已授权；手表已连上与电脑同一 Wi-Fi/LAN
        （表上：设置 → 网络与连接 → WLAN）。
  用法：powershell -NoProfile -ExecutionPolicy Bypass -File adb-wifi.ps1
  之后：拔掉底座 USB 线，adb 仍可经 Wi-Fi 工作；随时可恢复：重新插 USB 或运行 adb usb。
  编码：本脚本为带 BOM 的 UTF-8（含中文提示）；PS 5.1 下必须保留 BOM，见 AGENT.md §10 坑 1。
#>
param([string]$AdbPath = "")
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# ---------- 0 定位 adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "platform-tools\adb.exe")
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $AdbPath = $c; break } }
}
if (-not $AdbPath) { $cmd = Get-Command adb -ErrorAction SilentlyContinue; if ($cmd) { $AdbPath = $cmd.Source } }
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
    Write-Output "[X] 找不到 adb.exe。请把 platform-tools 解压到 tools\platform-tools，或用 -AdbPath 指定路径。"
    exit 1
}
Write-Output "[i] adb: $AdbPath"

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $o = & $AdbPath @AdbArgs 2>&1
    return (($o | Out-String) -replace "`r", "").Trim()
}

# ---------- 1 检查 USB 设备 ----------
$dev = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\S+\s+device$" } | Select-Object -First 1
if (-not $dev) {
    Write-Output "[X] 当前没有 USB 设备。"
    Write-Output "    请先把手表放到底座上（USB 调试已授权），再重跑本脚本。"
    exit 1
}
Write-Output "[OK] USB 设备在线: $dev"

# ---------- 2 读取手表 Wi-Fi IP ----------
$ipOut = Invoke-Adb shell "ip -f inet addr show wlan0"
$ip = ""
if ($ipOut -match "inet (\d+\.\d+\.\d+\.\d+)") { $ip = $Matches[1] }
if (-not $ip) {
    $routeOut = Invoke-Adb shell "ip route"
    if ($routeOut -match "src (\d+\.\d+\.\d+\.\d+)") { $ip = $Matches[1] }
}
if (-not $ip) {
    Write-Output "[X] 手表没有 Wi-Fi IP（wlan0 未连接）。"
    Write-Output "    表上操作：设置 → 网络与连接 → WLAN → 加入与电脑同一局域网。"
    Write-Output "    （官方注明不支持 Portal 认证网络——请用普通家庭/办公 Wi-Fi）"
    exit 1
}
Write-Output "[i] 手表 Wi-Fi IP: $ip"

# ---------- 3 切换 adb 到 tcpip ----------
$r = Invoke-Adb tcpip 5555
Write-Output "[i] adb tcpip 5555: $r"
Start-Sleep -Seconds 3

# ---------- 4 经 Wi-Fi 连接 ----------
Write-Output ""
Write-Output "接下来请你操作："
Write-Output "  1) 把底座的 USB 线从电脑上拔掉"
Write-Output "  2) 把手表从底座上取下来——拿在手里或戴到手腕上"
Write-Output "  3) 回到这里按回车键，进行 Wi-Fi 连接"
Read-Host "  拔线后按回车"

$c = Invoke-Adb connect "$ip`:5555"
Write-Output "[i] adb connect: $c"

$dev2 = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+:5555\s+device$" } | Select-Object -First 1
if ($dev2) {
    Write-Output ""
    Write-Output "[OK] Wi-Fi adb 已生效: $dev2"
    Write-Output "     手表已离座，可以手持/佩戴测试了。"
    Write-Output "     接着运行: .\device-test.ps1（手指贴表背；测 ECG：表背贴掌 + 指按表冠）"
    Write-Output "     想恢复 USB：重新插线，或运行 adb usb。"
} else {
    Write-Output ""
    Write-Output "[!] $ip`:5555 未出现在设备列表。请检查："
    Write-Output "    - 底座 USB 线已彻底拔掉？（USB 与 tcpip 会争抢同一设备）"
    Write-Output "    - 手表还亮着、屏幕没锁？"
    Write-Output "    - 电脑与手表在同一子网？防火墙拦了 5555 端口？"
    Write-Output "    重试: $AdbPath connect ${ip}:5555"
}
