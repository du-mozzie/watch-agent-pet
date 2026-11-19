<#
  oppo-watch-agent-pet / 真机测试会话脚本（中文提示版）
  覆盖：P1 物理按键（getevent）+ 私有传感器出数验证（Sensor Probe APK）
  用法：powershell -NoProfile -ExecutionPolicy Bypass -File device-test.ps1
  前置：手表放底座 + USB 调试已授权（docs/tutorials/01-getting-started.md）；
        APK 已由 watch\\sensor-probe\build.ps1 构建
  产出：results\device-test-<时间戳>\（getevent 日志 + logcat + 传感器注册行 + 汇总）
  设备动作：仅安装被测 App + 采集日志，其余只读。
  编码：本脚本为带 BOM 的 UTF-8（含中文提示）；PS 5.1 下必须保留 BOM，见 AGENT.md §10 坑 1。
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

# ---------- 0 定位 adb ----------
if (-not $AdbPath) {
    $cands = @(
        (Join-Path $ScriptDir "platform-tools\adb.exe"),
        (Join-Path (Split-Path $repo -Parent) "tools\platform-tools\adb.exe")
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $AdbPath = $c; break } }
}
if (-not $AdbPath) { $cmd = Get-Command adb -ErrorAction SilentlyContinue; if ($cmd) { $AdbPath = $cmd.Source } }
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
    Write-Output "[X] 找不到 adb.exe。请把 platform-tools 解压到 tools\platform-tools，或用 -AdbPath 指定路径。"
    exit 1
}
Write-Output "[i] adb: $AdbPath"

# ---------- 1 等待设备 ----------
Section "1. 等待设备接入（最多 30 秒）"
$deadline = (Get-Date).AddSeconds(30)
$devLine = ""
while ((Get-Date) -lt $deadline) {
    $devLine = (Invoke-Adb devices) -split "`n" | Where-Object { $_ -match "^\S+\s+device$" } | Select-Object -First 1
    if ($devLine) { break }
    Start-Sleep -Seconds 2
}
if (-not $devLine) {
    Write-Output "[X] 30 秒内没有设备。请检查：手表在底座、底座 USB 连电脑、USB 调试已开、表上已点「一律允许」。"
    exit 1
}
Write-Output "[OK] $devLine"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $repo "results\device-test-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Output "[i] 结果目录: $outDir"

# ---------- 2 P1：物理按键采集 ----------
Section "2. P1 物理按键采集（getevent，$GeteventSeconds 秒）"
Write-Output "  计时开始后，请在手表上依次完成以下动作："
Write-Output "    a) 旋转表冠 5~10 格（两个方向都转）"
Write-Output "    b) 短按一次侧边功能键"
Write-Output "    c) 短按一次表冠"
Write-Output "    d) 抬腕/放腕一次"
Read-Host  "  在这里按回车键开始采集"
Write-Output "  >>> 开始！请持续操作，直到提示完成"
$ev = & $AdbPath shell "timeout $GeteventSeconds getevent -l" 2>&1
$ev = (($ev | Out-String) -replace "`r", "")
$evFile = Join-Path $outDir "getevent.txt"
$ev | Out-File -LiteralPath $evFile -Encoding utf8
$evLines = @($ev -split "`n")
$keyLines = @($evLines | Where-Object { $_ -match "KEY_" })
$relLines = @($evLines | Where-Object { $_ -match "EV_REL" })
$keyNames = @($keyLines | ForEach-Object { if ($_ -match "(KEY_[A-Z0-9_]+)") { $Matches[1] } } | Sort-Object -Unique)
Write-Output ("  采集完成：{0} 行（其中 KEY_ 事件 {1} 行、EV_REL 相对轴事件 {2} 行）" -f $evLines.Count, $keyLines.Count, $relLines.Count)
if ($keyNames.Count -gt 0) { Write-Output ("  捕获到的按键: {0}" -f ($keyNames -join ", ")) }
if ($relLines.Count -gt 0) { Write-Output "  注意：出现 EV_REL 行 → 表冠旋转可能走相对轴上报，不是按键" }

# ---------- 3 安装探针 APK（install 必须用字面量参数直接调用，见 AGENT.md §10 坑 2）----------
Section "3. 安装传感器探针 APK"
$apk = Join-Path $repo "watch\\sensor-probe\build\sensor-probe-debug.apk"
if (-not (Test-Path $apk)) {
    Write-Output "[X] 找不到 APK: $apk"
    Write-Output "    请先构建：powershell -File watch\\sensor-probe\build.ps1"
    exit 1
}
$inst = & $AdbPath install -r $apk 2>&1
$inst = (($inst | Out-String) -replace "`r", "").Trim()
Write-Output "  $inst"
if ($LASTEXITCODE -ne 0 -or $inst -notmatch "Success") {
    Write-Output "[X] 安装失败（exit=$LASTEXITCODE）。请把上面的报错交给 Agent 分析。"
    exit 1
}
# 安装后确认包确实在
$pkgCheck = (& $AdbPath shell pm list packages $pkg 2>&1 | Out-String)
if ($pkgCheck -notmatch "package:$pkg") {
    Write-Output "[X] 包 $pkg 安装后未出现在包列表，安装异常。"
    exit 1
}
Write-Output "  [OK] 已安装: $pkg"

# ---------- 4 授权 BODY_SENSORS（字面量参数直接调用）----------
Section "4. 授予 BODY_SENSORS 权限"
$g = & $AdbPath shell pm grant $pkg android.permission.BODY_SENSORS 2>&1
$g = (($g | Out-String) -replace "`r", "").Trim()
if ([string]::IsNullOrWhiteSpace($g)) {
    Write-Output "  [OK] 已通过 pm grant 授权"
} else {
    Write-Output "  [!] pm grant 返回: $g"
    Write-Output "      备选：让 App 在表上弹授权窗时手动点允许（然后重跑本脚本）"
}

# ---------- 5 拉起 App + 采集 logcat（字面量参数直接调用）----------
Section "5. 拉起探针 App 并采集 logcat（$LogcatSeconds 秒）"
& $AdbPath logcat -c 2>&1 | Out-Null
$st = & $AdbPath shell am start -n "$pkg/.MainActivity" 2>&1
$st = (($st | Out-String) -replace "`r", "").Trim()
Write-Output "  $st"
Start-Sleep -Seconds 2
$pid = (& $AdbPath shell pidof $pkg 2>&1 | Out-String).Trim()
if ($pid) { Write-Output "  [OK] App 进程在线: pid $pid" } else { Write-Output "  [!] App 进程未找到（可能被杀，检查表上是否有异常）" }
Write-Output "  >>> 采集期间请保持 App 在前台"
$serial = Invoke-Adb devices
if ($serial -match "\d+\.\d+\.\d+\.\d+:5555") {
    Write-Output "  检测到 Wi-Fi 模式（表已离座）：请把手指贴住表背传感器；"
    Write-Output "      测 ECG 数值：表背贴住手掌 + 另一手指按在表冠上"
} else {
    Write-Output "  停靠模式（表背贴着充电器）：数值会是零/噪声——没关系，"
    Write-Output "      本次回答的是「HAL 是否向第三方 App 喂回调」（数回调次数）。"
    Write-Output "      之后想拿真实数值：先跑 adb-wifi.ps1，拔线离座，手持/佩戴再测。"
}
$lc = & $AdbPath shell "timeout $LogcatSeconds logcat -s PROBE STATS -v time" 2>&1
$lc = (($lc | Out-String) -replace "`r", "")
$lcFile = Join-Path $outDir "logcat-probe.txt"
$lc | Out-File -LiteralPath $lcFile -Encoding utf8
$lcLines = @($lc -split "`n" | Where-Object { $_.Trim() })
$first = @($lcLines | Where-Object { $_ -match "PROBE" })
$stats = @($lcLines | Where-Object { $_ -match "STATS" })
Write-Output ("  采集完成：PROBE 行 {0} 条、STATS 行 {1} 条 → {2}" -f $first.Count, $stats.Count, $lcFile)

# ---------- 6 传感器服务注册行 ----------
Section "6. 传感器服务注册情况（我们的包名）"
$dump = & $AdbPath shell dumpsys sensorservice 2>&1
$dump = (($dump | Out-String) -replace "`r", "")
$dumpFile = Join-Path $outDir "sensorservice-dump.txt"
$dump | Out-File -LiteralPath $dumpFile -Encoding utf8
$ours = @(($dump -split "`n") | Where-Object { $_ -match "owapet" })
if ($ours.Count -gt 0) {
    Write-Output ("  找到 {0} 行包含我们包名的注册记录：" -f $ours.Count)
    $ours | Select-Object -First 25 | ForEach-Object { Write-Output "    $_" }
} else {
    Write-Output "  没有包含 owapet 的注册行（App 可能被杀或传感器注册被拒）"
}

# ---------- 7 汇总 ----------
Section "7. 汇总"
$sum = @()
$sum += "# device-test 汇总 $stamp"
$sum += ""
$sum += "device: $(($devLine -split "`t" | Select-Object -First 1))"
$sum += ""
$sum += "## P1 按键"
if ($keyNames.Count -gt 0) { $sum += "unique keys: $($keyNames -join ', ')" } else { $sum += "no KEY_ events captured" }
$sum += "KEY lines: $($keyLines.Count); EV_REL lines: $($relLines.Count)"
$sum += ""
$sum += "## 传感器探针"
$sum += "PROBE lines: $($first.Count); STATS lines: $($stats.Count)"
$sum += "registered-sensor lines mentioning owapet in dumpsys: $($ours.Count)"
$sum += ""
$sum += "## Key log lines (first 60)"
$sum += $lcLines | Select-Object -First 60
$sumPath = Join-Path $outDir "summary.md"
$sum | Out-File -LiteralPath $sumPath -Encoding utf8
Write-Output "  汇总已保存 → $sumPath"
Write-Output ""
Write-Output "完成！请把结果目录交给 Agent 判读："
Write-Output "  $outDir"
