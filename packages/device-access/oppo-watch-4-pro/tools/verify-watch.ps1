<#
  watch-agent-pet 基线探针（中文提示版，纯只读）
  用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-watch.ps1 [-AdbPath <adb.exe>] [-WaitSeconds <秒>]
  作用：确认手表连接状态，抓取型号/系统/ABI/屏幕/电池等基线，
        并列出全部传感器 + 关键词命中（判断血氧/ECG/腕温能否侧载直读）
  产出：同目录下 watch-report-<时间戳>.md + sensorservice-dump.txt
  编码：本脚本为带 BOM 的 UTF-8（含中文提示）；PS 5.1 下必须保留 BOM，见 AGENT.md §10 坑 1。
#>

param(
    [string]$AdbPath = "",
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# ---------- 0 定位 adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "..\..\..\..\tools\platform-tools\adb.exe")
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
    Write-Host "[X] 找不到 adb.exe。请把 platform-tools 解压到 tools\platform-tools，或用 -AdbPath 指定路径。" -ForegroundColor Red
    exit 1
}
Write-Host "[i] 使用 adb: $AdbPath" -ForegroundColor Cyan

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

# ---------- 1 连接检查 ----------
Section "1. 检查设备连接"
$verLine = (Invoke-Adb version) -split "`n" | Select-Object -First 1
Add-Report "adb 版本: $verLine"

function Get-DeviceLines {
    $raw = Invoke-Adb devices
    return ($raw -split "`n" | Where-Object { $_ -match "^\S+\s+(device|unauthorized|offline|recovery|sideload)$" })
}

$devLines = Get-DeviceLines
if (-not $devLines) {
    Say ""
    Say "[!] 还没检测到设备，开始等待（最多 $WaitSeconds 秒）……" "Yellow"
    Say "    等待期间请完成：手表放底座并连电脑、开启 USB 调试、表上点「一律允许」。"
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        Write-Host "." -NoNewline
        $devLines = Get-DeviceLines
        if ($devLines) { break }
    }
    Write-Host ""
    if (-not $devLines) {
        Say "[X] 等待超时，仍无设备。逐条排查：" "Red"
        Say "    1) 底座 USB 线是否插在这台电脑上（换一个 USB 口，优先主机后置口）"
        Say "    2) 数据线是否支持数据传输（有些线只能充电）"
        Say "    3) 手表是否已开「开发者选项」里的「USB 调试」"
        Say "    4) 手表屏幕是否弹出「允许 USB 调试」而没点"
        Say "    5) 电脑设备管理器里是否出现未识别设备（若是，需要装 USB 驱动）"
        Say ""
        Say "    排查后可重跑本脚本，或延长等待：.\verify-watch.ps1 -WaitSeconds 120" "Red"
        exit 1
    }
    Say "[OK] 设备已接入。" "Green"
}

$devState = ($devLines -join "`n")
Add-Report "adb devices:"
Add-Report $devState

if ($devState -match "unauthorized") {
    Say ""
    Say "[!] 状态是 unauthorized：手表屏幕上有「允许 USB 调试吗」弹窗，勾选「一律允许」再点确定。" "Yellow"
    Say "    没有弹窗就把手表从底座上取下重新放一次；仍没有：开发者选项 → 撤销 USB 调试授权，再重试。" "Yellow"
    exit 1
}
if ($devState -match "offline") {
    Say "[!] 状态是 offline：先运行 adb kill-server，重新插拔底座，再跑本脚本。" "Yellow"
    exit 1
}
Add-Report "-> 设备已授权连接 OK"

# ---------- 2 设备基线 ----------
Section "2. 设备基线信息"
$propList = @(
    @("型号",         "ro.product.model"),
    @("设备代号",     "ro.product.device"),
    @("品牌",         "ro.product.brand"),
    @("制造商",       "ro.product.manufacturer"),
    @("Android版本",  "ro.build.version.release"),
    @("SDK(API)",    "ro.build.version.sdk"),
    @("CPU ABI",     "ro.product.cpu.abi"),
    @("ABI 列表",    "ro.product.cpu.abilist"),
    @("系统构建",     "ro.build.fingerprint")
)
foreach ($p in $propList) {
    $v = Invoke-Adb shell getprop $p[1]
    if ([string]::IsNullOrWhiteSpace($v)) { $v = "(空)" }
    Add-Report ("{0,-12}: {1}" -f $p[0], $v)
}

$wmSize = (Invoke-Adb shell wm size) -replace "`n", " ; "
$wmDen  = (Invoke-Adb shell wm density) -replace "`n", " ; "
Add-Report "屏幕尺寸    : $wmSize"
Add-Report "屏幕密度    : $wmDen"

$mem = Invoke-Adb shell cat /proc/meminfo
$memLine = ($mem -split "`n" | Where-Object { $_ -match "MemTotal" } | Select-Object -First 1)
Add-Report "内存        : $($memLine.Trim())"

$bat = Invoke-Adb shell dumpsys battery
$batLines = ($bat -split "`n" | Where-Object { $_ -match "^  (level|status|health|temperature|voltage):" })
foreach ($b in $batLines) { Add-Report ("电池        : " + $b.Trim()) }

# ---------- 3 传感器（关键） ----------
Section "3. 传感器清单 —— 决定血氧/ECG/腕温能否侧载直读"
$sensorRaw = Invoke-Adb shell dumpsys sensorservice
$sensorFile = Join-Path $ScriptDir "sensorservice-dump.txt"
$sensorRaw | Out-File -LiteralPath $sensorFile -Encoding utf8
Add-Report "原始 dump 已保存: $sensorFile"

$sensorLines = $sensorRaw -split "`n"
# 抓 "Sensor List" 段里带 type 的行
$typeLines = $sensorLines | Where-Object { $_ -match "type" -and $_ -match "\|" }

Add-Report ""
Add-Report ("传感器条目数: " + $typeLines.Count)
$shown = 0
foreach ($l in $typeLines) {
    if ($shown -ge 45) { Add-Report "  ... (其余见 dump 文件)"; break }
    Add-Report ("  " + $l.Trim())
    $shown++
}

# 关键词命中
Add-Report ""
Add-Report "关键词命中（判断能力边界）："
$kwSets = @(
    @("心率 HEART RATE",  @("heart", "type_heart_rate", "hr_rate")),
    @("血氧 SpO2",        @("ppg_spo", "spo2", "blood", "oxygen", "oximeter", "pulse_ox")),
    @("心电 ECG",         @("ecg", "electrocardio")),
    @("腕温 WRIST TEMP",  @("wrist", "skin_temp", "temperature"))
)
foreach ($ks in $kwSets) {
    $label = $ks[0]
    $hits = @()
    foreach ($k in $ks[1]) {
        $hits += ($sensorLines | Where-Object { $_.ToLower().Contains($k) })
    }
    $hits = $hits | Select-Object -Unique
    if ($hits.Count -gt 0) {
        Add-Report ("  [命中] {0}（{1} 行）" -f $label, $hits.Count)
        foreach ($h in ($hits | Select-Object -First 3)) {
            Add-Report ("         " + $h.Trim())
        }
    } else {
        Add-Report ("  [未命中] {0}" -f $label)
    }
}

# ---------- 4 已装第三方应用 ----------
Section "4. 侧载环境检查"
$third = Invoke-Adb shell pm list packages -3
$thirdLines = ($third -split "`n" | Where-Object { $_ -match "package:" })
Add-Report ("已安装第三方应用数量: " + $thirdLines.Count)
foreach ($t in ($thirdLines | Select-Object -First 12)) { Add-Report ("  " + $t.Trim()) }

$inst = Invoke-Adb shell pm list packages com.oppo.watch
Add-Report "系统手表组件抽样:"
foreach ($t in (($inst -split "`n" | Where-Object { $_ -match "package:" } | Select-Object -First 6))) { Add-Report ("  " + $t.Trim()) }

# ---------- 5 当前前台窗口 ----------
Section "5. 当前前台窗口"
$win = Invoke-Adb shell dumpsys window
$focus = ($win -split "`n" | Where-Object { $_ -match "mCurrentFocus|mFocusedApp" } | Select-Object -First 4)
foreach ($f in $focus) { Add-Report ("  " + $f.Trim()) }

# ---------- 6 输出报告 ----------
Section "6. 完成"
$reportPath = Join-Path $ScriptDir ("watch-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
$header = "# OPPO Watch 探针报告`n`n时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "`n`n"
$header + $Report.ToString() | Out-File -LiteralPath $reportPath -Encoding utf8
Write-Host ""
Write-Host "报告已保存: $reportPath" -ForegroundColor Green
Write-Host "请打开报告查看传感器清单与关键词命中情况，对照 packages/device-access/oppo-watch-4-pro/docs/tutorials/02-sensor-probe.md 判读。" -ForegroundColor Green
