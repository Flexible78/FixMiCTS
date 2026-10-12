$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OriginalRoot = $PSScriptRoot
$Root = $OriginalRoot
# Legacy aapt.exe cannot reliably consume non-ASCII archive paths on Windows.
# Give native tools an ASCII junction path; .NET still publishes into the real root.
# No source, dependency, or signing key is moved or replaced.
if ($Root -match '[^\x00-\x7F]') {
    $asciiTemp = [IO.Path]::GetTempPath()
    if ($asciiTemp -match '[^\x00-\x7F]') {
        if (-not ('FixMiCTS.ShortPath' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace FixMiCTS {
    public static class ShortPath {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint GetShortPathName(string path, StringBuilder result, uint size);
    }
}
'@
        }
        $buffer = [Text.StringBuilder]::new(32768)
        $length = [FixMiCTS.ShortPath]::GetShortPathName($asciiTemp,$buffer,32768)
        if ($length -eq 0 -or $length -ge 32768 -or $buffer.ToString() -match '[^\x00-\x7F]') {
            throw 'Native Android tools need an ASCII staging path. Set TEMP/TMP to a writable ASCII folder, or unpack the project into C:\FixMiCTS, then rerun. No administrator rights or security changes are needed.'
        }
        $asciiTemp = $buffer.ToString()
    }
    $aliasParent = Join-Path $asciiTemp ('FixMiCTS-ascii-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $aliasParent -Force | Out-Null
    $Root = Join-Path $aliasParent 'project'
    New-Item -ItemType Junction -Path $Root -Target $OriginalRoot | Out-Null
    Write-Host "Native-tool ASCII alias: $Root"
}
$Sdk = Join-Path $Root '.sdk'
$Build = Join-Path $Root '_build'
$Cache = Join-Path $Sdk 'cache'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Download-Verified([string]$Url,[string]$Name,[string]$Hash) {
    $dest = Join-Path $Cache $Name
    if ((Test-Path -LiteralPath $dest) -and (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ieq $Hash) { return $dest }
    $part = $dest + '.part'
    Write-Host "Downloading pinned dependency: $Name"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $part -TimeoutSec 240 -MaximumRedirection 10
            if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ine $Hash) { throw "SHA256 mismatch for $Name" }
            Move-Item -LiteralPath $part -Destination $dest -Force
            return $dest
        } catch {
            if ($attempt -eq 3) { throw "Download failed: $Name. Check Internet/proxy, then rerun BUILD_APK.cmd. $($_.Exception.Message)" }
            Start-Sleep -Seconds 2
        }
    }
}
function Unpack-Verified([string]$Zip,[string]$Folder,[string[]]$Required) {
    $hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
    $marker = Join-Path $Folder '.archive-sha256'
    $complete = (Test-Path -LiteralPath $marker) -and ([IO.File]::ReadAllText($marker) -eq $hash)
    foreach ($relative in $Required) { if (!(Test-Path -LiteralPath (Join-Path $Folder $relative))) { $complete = $false } }
    if (!$complete) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        Expand-Archive -LiteralPath $Zip -DestinationPath $Folder -Force
        foreach ($relative in $Required) { if (!(Test-Path -LiteralPath (Join-Path $Folder $relative))) { throw "Incomplete archive: $relative" } }
        [IO.File]::WriteAllText($marker,$hash)
    }
}
function Test-Jdk([string]$Candidate) {
    if (!$Candidate -or !(Test-Path -LiteralPath $Candidate)) { return $null }
    foreach ($name in @('java','javac','jar','keytool')) {
        if (!(Test-Path -LiteralPath (Join-Path $Candidate "bin\$name.exe"))) { Write-Host "Rejected JDK: $Candidate (missing $name.exe)"; return $null }
    }
    $version = (& (Join-Path $Candidate 'bin\javac.exe') -version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^javac (17|21)(\.|\s|$)') { Write-Host "Rejected JDK: $Candidate ($version; use LTS 17 or 21)"; return $null }
    Write-Host "Accepted JDK: $Candidate ($version)"
    return $Candidate
}
function Invoke-Checked([string]$Tool,[string[]]$ToolArgs) {
    & $Tool @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "Tool failed (exit $LASTEXITCODE): $Tool" }
}
try {
    New-Item -ItemType Directory -Path $Sdk,$Build,$Cache -Force | Out-Null
    Write-Host '1/6: Finding a COMPLETE JDK 17 or 21...'
    $candidates = @($env:JAVA_HOME,(Join-Path $Sdk 'jdk17\jdk-17.0.16+8'),'C:\Program Files\Android\Android Studio\jbr')
    foreach ($base in @('C:\Program Files\Java','C:\Program Files\Eclipse Adoptium')) {
        if (Test-Path -LiteralPath $base) { $candidates += @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name | ForEach-Object FullName) }
    }
    foreach ($command in @(Get-Command javac.exe -All -ErrorAction SilentlyContinue)) {
        $candidates += Split-Path (Split-Path $command.Source -Parent) -Parent
        $item = Get-Item -LiteralPath $command.Source
        if ($item.Target) { foreach ($target in $item.Target) { $candidates += Split-Path (Split-Path $target -Parent) -Parent } }
    }
    $selected = $null
    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) { $selected = Test-Jdk $candidate; if ($selected) { break } }
    if (!$selected) {
        $jdkZip = Download-Verified 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.16%2B8/OpenJDK17U-jdk_x64_windows_hotspot_17.0.16_8.zip' 'jdk17.0.16_8.zip' '8c7cfff78a55c56ebaf470ed6a89c6466b47d8274bdabdda997d7507c20325c5'
        $jdkFolder = Join-Path $Sdk 'jdk17'
        Unpack-Verified $jdkZip $jdkFolder @('jdk-17.0.16+8\bin\java.exe','jdk-17.0.16+8\bin\javac.exe','jdk-17.0.16+8\bin\jar.exe','jdk-17.0.16+8\bin\keytool.exe')
        $selected = Test-Jdk (Join-Path $jdkFolder 'jdk-17.0.16+8')
        if (!$selected) { throw 'Pinned JDK failed validation.' }
    }
    $env:JAVA_HOME = $selected
    $env:PATH = (Join-Path $selected 'bin') + ';' + $env:PATH
    $javac = Join-Path $selected 'bin\javac.exe'
    $jar = Join-Path $selected 'bin\jar.exe'
    $keytool = Join-Path $selected 'bin\keytool.exe'
    Write-Host '2/6: Verifying pinned Android SDK/build tools (SHA256)...'
    $platformZip = Download-Verified 'https://dl.google.com/android/repository/platform-35_r02.zip' 'platform-35_r02.zip' '0988cacad01b38a18a47bac14a0695f246bc76c1b06c0eeb8eb0dc825ab0c8e0'
    $toolsZip = Download-Verified 'https://dl.google.com/android/repository/build-tools_r35.0.1_windows.zip' 'build-tools_r35.0.1_windows.zip' '79748cb4ab64b61fa678af21639985c7e394d874a4e31f082f4026d5c57e01a3'
    $platformFolder = Join-Path $Sdk 'platform-35'
    $toolsFolder = Join-Path $Sdk 'build-tools-35.0.1'
    Unpack-Verified $platformZip $platformFolder @('android-35\android.jar')
    Unpack-Verified $toolsZip $toolsFolder @('android-15\aapt.exe','android-15\d8.bat','android-15\lib\d8.jar','android-15\zipalign.exe','android-15\apksigner.bat','android-15\lib\apksigner.jar')
    $androidJar = Join-Path $platformFolder 'android-35\android.jar'
    $tools = Join-Path $toolsFolder 'android-15'
    $aapt = Join-Path $tools 'aapt.exe'
    $d8 = Join-Path $tools 'd8.bat'
    $zipalign = Join-Path $tools 'zipalign.exe'
    $signer = Join-Path $tools 'apksigner.bat'
    Write-Host '3/6: Compiling Java against Android API...'
    $run = Join-Path $Build ('run-' + [Guid]::NewGuid().ToString('N'))
    $classes = Join-Path $run 'classes'
    $dex = Join-Path $run 'dex'
    New-Item -ItemType Directory -Path $classes,$dex -Force | Out-Null
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'app\src\main\java') -Recurse -File -Filter '*.java' | ForEach-Object FullName)
    if (!$sourceFiles.Count) { throw 'No Java source files found.' }
    # javac needs the JDK LambdaMetafactory signature; D8 desugars Java 8 lambdas
    # for Android afterwards. android.jar alone is not a complete javac bootclasspath.
    Invoke-Checked $javac (@('-source','8','-target','8','-Xlint:-options','-encoding','UTF-8','-classpath',$androidJar,'-d',$classes) + $sourceFiles)
    Write-Host '4/6: Packaging manifest/resources and DEX...'
    $unsigned = Join-Path $run 'unsigned.apk'
    $aligned = Join-Path $run 'aligned.apk'
    Invoke-Checked $aapt @('package','-f','-M',(Join-Path $Root 'app\src\main\AndroidManifest.xml'),'-S',(Join-Path $Root 'app\src\main\res'),'-I',$androidJar,'-F',$unsigned)
    $classFiles = @(Get-ChildItem -LiteralPath $classes -Recurse -File -Filter '*.class' | ForEach-Object FullName)
    Invoke-Checked $d8 (@('--lib',$androidJar,'--min-api','26','--output',$dex) + $classFiles)
    Invoke-Checked $jar @('uf',$unsigned,'-C',$dex,'classes.dex')
    Invoke-Checked $zipalign @('-f','4',$unsigned,$aligned)
    Write-Host '5/6: Reusing permanent personal signing identity...'
    $key = Join-Path $Build 'fixmicts-local.jks'
    $passFile = Join-Path $Build 'signing.pw'
    if ((Test-Path -LiteralPath $key) -xor (Test-Path -LiteralPath $passFile)) { throw 'Incomplete signing identity. Restore BOTH _build\fixmicts-local.jks and _build\signing.pw; never replace an existing key.' }
    if (!(Test-Path -LiteralPath $key)) {
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $secret = [Convert]::ToBase64String($bytes)
        [IO.File]::WriteAllText($passFile,$secret)
        $env:FIXMICTS_STOREPASS = $secret
        Invoke-Checked $keytool @('-genkeypair','-keystore',$key,'-alias','fixmicts','-keyalg','RSA','-keysize','3072','-validity','36500','-storepass:env','FIXMICTS_STOREPASS','-keypass:env','FIXMICTS_STOREPASS','-dname','CN=Fix MiCTS Personal Build','-noprompt')
    }
    $env:FIXMICTS_STOREPASS = [IO.File]::ReadAllText($passFile)
    Write-Host '6/6: Signing, verifying certificate, alignment and APK content...'
    $candidateApk = Join-Path $run 'FixMiCTS.apk'
    Invoke-Checked $signer @('sign','--ks',$key,'--ks-key-alias','fixmicts','--ks-pass','env:FIXMICTS_STOREPASS','--key-pass','env:FIXMICTS_STOREPASS','--out',$candidateApk,$aligned)
    Invoke-Checked $signer @('verify','--verbose','--print-certs',$candidateApk)
    Invoke-Checked $zipalign @('-c','4',$candidateApk)
    Invoke-Checked $aapt @('dump','badging',$candidateApk)
    $apk = Join-Path $OriginalRoot 'FixMiCTS.apk'
    Copy-Item -LiteralPath $candidateApk -Destination $apk -Force
    $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $OriginalRoot 'FixMiCTS.apk.sha256'),"$apkHash  FixMiCTS.apk`r`n")
    Write-Host "APK READY: $apk"
    Write-Host "SHA256: $apkHash"
    Write-Host 'Keep _build\fixmicts-local.jks AND _build\signing.pw privately for future updates.'
} catch {
    Write-Host "BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally { $env:FIXMICTS_STOREPASS = $null }
