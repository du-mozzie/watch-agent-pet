<#
  oppo-watch-agent-pet / android/sensor-probe build script
  Gradle-less build: aapt2 + javac + jar + d8 + zipalign + apksigner (SDK build-tools only)
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 [-SdkPath <sdk>] [-JavaHome <jdk>]
  Output: build\sensor-probe-debug.apk
  Notes:
   - build runs inside an ASCII staging dir under %TEMP% (non-ASCII path safety)
   - ASCII-only script on purpose (PowerShell 5.1 encoding safety)
   - native tools are invoked with LITERAL string args only; array splatting to
     native exes is avoided (PS 5.1 mangles splatted args)
   - $ErrorActionPreference is Continue on purpose: javac warnings on stderr
     would otherwise become terminating errors; exit codes are checked explicitly
#>
param(
    [string]$SdkPath = "",
    [string]$JavaHome = ""
)
$ErrorActionPreference = "Continue"
$proj = $PSScriptRoot
Write-Output "[i] project: $proj"
Write-Output "[i] params: SdkPath=$SdkPath JavaHome=$JavaHome"

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
        (Join-Path $proj "..\..\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        "$env:LOCALAPPDATA\Android\Sdk"
    ) | Where-Object { $_ }
    foreach ($c in $cands) { if (Test-Path "$c\platforms") { $SdkPath = $c; break } }
}
if (-not $SdkPath -or -not (Test-Path "$SdkPath\platforms")) {
    Write-Output "[X] Android SDK not found. Install per AGENT.md section 2 or pass -SdkPath."
    exit 1
}
$jarPath = "$SdkPath\platforms\android-30\android.jar"
if (-not (Test-Path $jarPath)) {
    Write-Output "[X] missing platforms;android-30 ($jarPath)"
    exit 1
}
$btDir = Get-ChildItem "$SdkPath\build-tools" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $btDir) {
    Write-Output "[X] missing build-tools under $SdkPath"
    exit 1
}
$bt = $btDir.FullName
Write-Output "[i] SDK: $SdkPath"
Write-Output "[i] build-tools: $bt"

# ---------- 1 locate JDK (javac / jar / keytool) ----------
$javac = $null
if ($JavaHome -and (Test-Path "$JavaHome\bin\javac.exe")) { $javac = "$JavaHome\bin\javac.exe" }
if (-not $javac) { $c = Get-Command javac -ErrorAction SilentlyContinue; if ($c) { $javac = $c.Source } }
if (-not $javac -and $env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\javac.exe")) { $javac = "$env:JAVA_HOME\bin\javac.exe" }
if (-not $javac) {
    Write-Output "[X] javac not found (need JDK 8+). Pass -JavaHome <jdk-dir>."
    exit 1
}
$jdkBin = Split-Path $javac -Parent
$jarTool = Join-Path $jdkBin "jar.exe"
$keytool = Join-Path $jdkBin "keytool.exe"
$env:Path = "$jdkBin;$env:Path"   # make sure d8.bat / apksigner.bat can find java
# d8.bat / apksigner.bat resolve java via JAVA_HOME (not PATH) -> point it at the same JDK
$jdkHome = Split-Path $jdkBin -Parent
$env:JAVA_HOME = $jdkHome
Write-Output "[i] javac: $javac"

# ---------- 2 stage into ASCII temp dir ----------
$stage = Join-Path $env:TEMP "owap-sp-build"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path "$stage\classes", "$stage\src" -Force | Out-Null
Copy-Item "$proj\src\*" "$stage\src\" -Recurse
Copy-Item "$proj\AndroidManifest.xml" $stage
Copy-Item $jarPath "$stage\android.jar"
# persist debug keystore under project build/ (gitignored via *.keystore)
$ksPersist = "$proj\build\debug.keystore"
if (Test-Path $ksPersist) { Copy-Item $ksPersist "$stage\debug.keystore" }

# ---------- 3 aapt2 link (manifest -> unsigned apk) ----------
& "$bt\aapt2.exe" link -I "$stage\android.jar" --manifest "$stage\AndroidManifest.xml" --min-sdk-version 27 --target-sdk-version 30 -o "$stage\app.unsigned.apk" 2> "$stage\aapt2-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\aapt2-err.txt"; throw "aapt2 link failed" }
Write-Output "[1/7] aapt2 link OK"

# ---------- 4 javac per file (literal args; splatting is avoided) ----------
$srcs = Get-ChildItem "$stage\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if (-not $srcs) { throw "no .java sources found under $stage\src" }
foreach ($f in $srcs) {
    & $javac -source 1.8 -target 1.8 -encoding UTF-8 -bootclasspath "$stage\android.jar" -d "$stage\classes" "$f" 2> "$stage\javac-err.txt"
    if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\javac-err.txt"; throw "javac failed on $f" }
}
Write-Output "[2/7] javac OK ($($srcs.Count) source files)"

# ---------- 5 package classes into a jar (single input for d8) ----------
& $jarTool cf "$stage\classes.jar" -C "$stage\classes" . 2> "$stage\jar-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\jar-err.txt"; throw "jar packaging failed" }
Write-Output "[3/7] jar OK"

# ---------- 6 d8 (dex, min-api 27) ----------
& "$bt\d8.bat" --min-api 27 --lib "$stage\android.jar" --output "$stage\classes" "$stage\classes.jar" 2> "$stage\d8-err.txt"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$stage\classes\classes.dex")) { Read-NativeErr "$stage\d8-err.txt"; throw "d8 failed" }
Write-Output "[4/7] d8 OK"

# ---------- 7 inject classes.dex into apk ----------
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$apkStream = [System.IO.Compression.ZipFile]::Open("$stage\app.unsigned.apk", [System.IO.Compression.ZipArchiveMode]::Update)
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apkStream, "$stage\classes\classes.dex", "classes.dex", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
$apkStream.Dispose()
Write-Output "[5/7] classes.dex injected"

# ---------- 8 zipalign ----------
& "$bt\zipalign.exe" -f 4 "$stage\app.unsigned.apk" "$stage\app.aligned.apk" 2> "$stage\zipalign-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\zipalign-err.txt"; throw "zipalign failed" }
Write-Output "[6/7] zipalign OK"

# ---------- 9 sign with debug keystore ----------
if (-not (Test-Path "$stage\debug.keystore")) {
    & $keytool -genkeypair -keystore "$stage\debug.keystore" -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" 2> "$stage\keytool-err.txt"
    if (-not (Test-Path "$stage\debug.keystore")) { Read-NativeErr "$stage\keytool-err.txt"; throw "keytool keystore generation failed" }
}
& "$bt\apksigner.bat" sign --ks "$stage\debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$stage\sensor-probe-debug.apk" "$stage\app.aligned.apk" 2> "$stage\apksigner-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\apksigner-err.txt"; throw "apksigner sign failed" }

# ---------- 10 verify and copy back ----------
& "$bt\apksigner.bat" verify --print-certs "$stage\sensor-probe-debug.apk" 2> "$stage\verify-err.txt"
if ($LASTEXITCODE -ne 0) { Read-NativeErr "$stage\verify-err.txt"; throw "apksigner verify failed" }
Write-Output "[7/7] apksigner verify OK"

New-Item -ItemType Directory -Path "$proj\build" -Force | Out-Null
Copy-Item "$stage\sensor-probe-debug.apk" "$proj\build\sensor-probe-debug.apk" -Force
Copy-Item "$stage\debug.keystore" $ksPersist -Force
$out = "$proj\build\sensor-probe-debug.apk"
Write-Output ""
Write-Output ("[OK] output: {0} ({1:N0} bytes)" -f $out, (Get-Item $out).Length)
Write-Output "     32-bit note: pure Java, no native .so -> armeabi-v7a-only safe; min-api 27 / target 30"
Write-Output "     on-device check: run tools\device-test.ps1 (see AGENT.md section 6)"
