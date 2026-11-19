<#
  watch-agent-pet / packages/device-access/oppo-watch-4-pro/collector 一键构建脚本（中文提示版）
  无 Gradle 构建：aapt2 + javac + jar + d8 + zipalign + apksigner（仅需 SDK build-tools）
  用法：powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 [-SdkPath <sdk>] [-JavaHome <jdk>]
  产出：build\sensor-probe-debug.apk
  说明：
   - 构建在 %TEMP% 的 ASCII 暂存目录内进行（规避开中文路径与原生工具的兼容问题）
   - 本脚本为带 BOM 的 UTF-8（含中文提示）；PS 5.1 下必须保留 BOM，见 AGENT.md §10 坑 1
   - 原生工具只用字面量字符串参数调用；不向原生 exe 展开数组 splat
     （PS 5.1 会把 splat 参数切碎）
   - 故意用 $ErrorActionPreference=Continue：否则 javac 警告会变成终止错误；
     退出码均显式检查
#>
param(
    [string]$SdkPath = "",
    [string]$JavaHome = ""
)
$ErrorActionPreference = "Continue"
$proj = $PSScriptRoot
Write-Output "[i] 项目目录: $proj"
Write-Output "[i] 参数: SdkPath=$SdkPath JavaHome=$JavaHome"

function Read-NativeErr {
    param([string]$File)
    if (Test-Path $File) {
        $t = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::GetEncoding(936))
        if ($t.Trim()) { Write-Output $t }
    }
}

# ---------- 0 locate Android SDK ----------
if (-not $SdkPath) {
    $cands = @(
        (Join-Path $proj "..\..\..\..\android-sdk"),
        (Join-Path $proj "..\..\..\..\..\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        "$env:LOCALAPPDATA\Android\Sdk"
    ) | Where-Object { $_ }
    foreach ($c in $cands) { if (Test-Path "$c\platforms") { $SdkPath = $c; break } }
}
if (-not $SdkPath -or -not (Test-Path "$SdkPath\platforms")) {
    Write-Output "[X] 找不到 Android SDK（需要含 platforms 目录）。按 AGENT.md §2 安装，或用 -SdkPath 指定路径。"
    exit 1
}
$jarPath = "$SdkPath\platforms\android-30\android.jar"
if (-not (Test-Path $jarPath)) {
    Write-Output "[X] 缺 platforms;android-30：$jarPath"
    exit 1
}
$btDir = Get-ChildItem "$SdkPath\build-tools" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $btDir) {
    Write-Output "[X] 缺 build-tools：$SdkPath\build-tools"
    exit 1
}
$bt = $btDir.FullName
Write-Output "[i] SDK: $SdkPath"
Write-Output "[i] build-tools: $bt"

# ---------- 1 定位 JDK（javac / jar / keytool）----------
$javac = $null
if ($JavaHome -and (Test-Path "$JavaHome\bin\javac.exe")) { $javac = "$JavaHome\bin\javac.exe" }
if (-not $javac) { $c = Get-Command javac -ErrorAction SilentlyContinue; if ($c) { $javac = $c.Source } }
if (-not $javac -and $env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\javac.exe")) { $javac = "$env:JAVA_HOME\bin\javac.exe" }
if (-not $javac) {
    Write-Output "[X] 找不到 javac（需 JDK 8+）。可用 -JavaHome 指定 JDK 目录。"
    exit 1
}
$jdkBin = Split-Path $javac -Parent
$jarTool = Join-Path $jdkBin "jar.exe"
$keytool = Join-Path $jdkBin "keytool.exe"
$env:Path = "$jdkBin;$env:Path"   # 确保 d8.bat / apksigner.bat 能找到 java
# d8.bat / apksigner.bat 经 JAVA_HOME（而非 PATH）找 java → 指向同一 JDK
$jdkHome = Split-Path $jdkBin -Parent
$env:JAVA_HOME = $jdkHome
Write-Output "[i] javac: $javac"

# ---------- 2 暂存到 ASCII 临时目录 ----------
$stage = Join-Path $env:TEMP ("watch-agent-pet-build-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path "$stage\classes", "$stage\src" -Force | Out-Null
Copy-Item "$proj\src\*" "$stage\src\" -Recurse
Copy-Item "$proj\AndroidManifest.xml" $stage
Copy-Item $jarPath "$stage\android.jar"
# 持久化 debug keystore 到项目 build/（.gitignore 已忽略 *.keystore）
$ksPersist = "$proj\build\debug.keystore"
if (Test-Path $ksPersist) { Copy-Item $ksPersist "$stage\debug.keystore" }

# ---------- 3 aapt2 link (manifest -> unsigned apk) ----------
& "$bt\aapt2.exe" link -I "$stage\android.jar" --manifest "$stage\AndroidManifest.xml" --min-sdk-version 27 --target-sdk-version 30 -o "$stage\app.unsigned.apk" 2> "$stage\aapt2-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\aapt2-err.txt"; throw "aapt2 link failed" }
Write-Output "[1/7] aapt2 link 完成"

# ---------- 4 逐文件 javac（只用字面量参数，不用 splat）----------
$srcs = Get-ChildItem "$stage\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if (-not $srcs) { throw "在 $stage\src 下找不到 .java 源文件" }
foreach ($f in $srcs) {
    & $javac -source 1.8 -target 1.8 -encoding UTF-8 -bootclasspath "$stage\android.jar" -d "$stage\classes" "$f" 2> "$stage\javac-err.txt"
    if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\javac-err.txt"; throw "javac 编译失败：$f" }
}
Write-Output "[2/7] javac 编译完成（$($srcs.Count) 个源文件）"

# ---------- 5 打包 class 为 jar（作为 d8 的单输入）----------
& $jarTool cf "$stage\classes.jar" -C "$stage\classes" . 2> "$stage\jar-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\jar-err.txt"; throw "jar 打包失败" }
Write-Output "[3/7] jar 打包完成"

# ---------- 6 d8（转 dex，min-api 27）----------
& "$bt\d8.bat" --min-api 27 --lib "$stage\android.jar" --output "$stage\classes" "$stage\classes.jar" 2> "$stage\d8-err.txt"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$stage\classes\classes.dex")) { Read-NativeErr "$stage\d8-err.txt"; throw "d8 失败" }
Write-Output "[4/7] d8 转 dex 完成"

# ---------- 7 注入 classes.dex 到 apk ----------
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$apkStream = [System.IO.Compression.ZipFile]::Open("$stage\app.unsigned.apk", [System.IO.Compression.ZipArchiveMode]::Update)
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apkStream, "$stage\classes\classes.dex", "classes.dex", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
$apkStream.Dispose()
Write-Output "[5/7] classes.dex 已注入"

# ---------- 8 zipalign 对齐 ----------
& "$bt\zipalign.exe" -f 4 "$stage\app.unsigned.apk" "$stage\app.aligned.apk" 2> "$stage\zipalign-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\zipalign-err.txt"; throw "zipalign 失败" }
Write-Output "[6/7] zipalign 对齐完成"

# ---------- 9 用 debug keystore 签名 ----------
if (-not (Test-Path "$stage\debug.keystore")) {
    & $keytool -genkeypair -keystore "$stage\debug.keystore" -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" 2> "$stage\keytool-err.txt"
    if (-not (Test-Path "$stage\debug.keystore")) { Read-NativeErr "$stage\keytool-err.txt"; throw "keytool 生成 keystore 失败" }
}
& "$bt\apksigner.bat" sign --ks "$stage\debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$stage\sensor-probe-debug.apk" "$stage\app.aligned.apk" 2> "$stage\apksigner-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\apksigner-err.txt"; throw "apksigner 签名失败" }

# ---------- 10 校验并拷回 ----------
& "$bt\apksigner.bat" verify --print-certs "$stage\sensor-probe-debug.apk" 2> "$stage\verify-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\verify-err.txt"; throw "apksigner 校验失败" }
Write-Output "[7/7] apksigner 校验通过"

New-Item -ItemType Directory -Path "$proj\build" -Force | Out-Null
Copy-Item "$stage\sensor-probe-debug.apk" "$proj\build\sensor-probe-debug.apk" -Force
Copy-Item "$stage\debug.keystore" $ksPersist -Force
$out = "$proj\build\sensor-probe-debug.apk"
Write-Output ""
Write-Output ("[OK] 产物: {0}（{1:N0} 字节）" -f $out, (Get-Item $out).Length)
Write-Output "     32 位说明: 纯 Java 无 native so，天然满足 armeabi-v7a-only；min-api 27 / target 30"
Write-Output "     真机验证: 运行 packages\device-access\oppo-watch-4-pro\tools\device-test.ps1（见 AGENT.md §6）"
