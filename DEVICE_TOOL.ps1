param(
    [ValidateSet('Install','Fix','Diagnose')][string]$Mode = 'Diagnose',
    [string]$Serial = $env:ANDROID_SERIAL
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Package = 'dev.alextsyrkin.fixmicts'
$Component = 'com.google.android.googlequicksearchbox/com.google.android.voiceinteraction.GsaVoiceInteractionService'
$localAdb = Join-Path $Root 'adb.exe'
if (Test-Path -LiteralPath $localAdb) { $Adb = $localAdb }
else {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if (!$command) { throw 'adb.exe not found. Install Android Platform Tools and add to PATH, or put adb.exe and its DLLs beside this script.' }
    $Adb = $command.Source
}
function Invoke-Adb([string[]]$Arguments) {
    & $Adb @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ') (exit $LASTEXITCODE)" }
}
try {
    $listing = @(Invoke-Adb @('devices','-l'))
    $listing | ForEach-Object { Write-Host $_ }
    $online = @($listing | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' } | ForEach-Object { ($_ -split '\s+')[0] })
    if (!$Serial) {
        if ($online.Count -ne 1) { throw 'Need exactly one online phone, or specify -Serial / ANDROID_SERIAL. For Wi-Fi use adb connect CURRENT_IP:PORT; do not use the pairing port.' }
        $Serial = $online[0]
    }
    if ($online -notcontains $Serial) { throw 'Selected phone is not online. Unlock it and reconnect ADB.' }
    $model = (Invoke-Adb @('-s',$Serial,'shell','getprop','ro.product.model') | Out-String).Trim()
    $user = (Invoke-Adb @('-s',$Serial,'shell','am','get-current-user') | Out-String).Trim()
    Write-Host "Device: $model; current Android user: $user"
    if ($model -ne 'V2366HA' -or $user -ne '0') { throw 'This personal installer targets the tested Vivo V2366HA, primary user 0 only. No changes made.' }
    if ($Mode -eq 'Install') {
        $apk = Join-Path $Root 'FixMiCTS.apk'
        if (!(Test-Path -LiteralPath $apk)) { throw 'FixMiCTS.apk missing. Run BUILD_APK.cmd first.' }
        $actualHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
        $hashFile = Join-Path $Root 'FixMiCTS.apk.sha256'
        if (!(Test-Path -LiteralPath $hashFile)) { throw 'APK SHA256 file missing; rebuild or restore the complete delivery.' }
        $expectedHash = ([IO.File]::ReadAllText($hashFile).Trim() -split '\s+')[0]
        if ($actualHash -ine $expectedHash) { throw 'APK checksum mismatch. Do not install; rebuild or restore the delivery.' }
        $identicalInstalled = $false
        $pathResult = @(Invoke-Adb @('-s',$Serial,'shell','pm','path','--user','0',$Package))
        if ($pathResult.Count -eq 1 -and $pathResult[0] -match '^package:(.+/base\.apk)\s*$') {
            $remote = $Matches[1]
            $temporaryApk = Join-Path ([IO.Path]::GetTempPath()) ('FixMiCTS-installed-' + [Guid]::NewGuid().ToString('N') + '.apk')
            try {
                & $Adb -s $Serial pull $remote $temporaryApk
                if ($LASTEXITCODE -eq 0) { $identicalInstalled = (Get-FileHash -LiteralPath $temporaryApk -Algorithm SHA256).Hash -eq $actualHash }
            } finally {
                if (Test-Path -LiteralPath $temporaryApk) { Remove-Item -LiteralPath $temporaryApk -Force }
            }
        }
        if (!$identicalInstalled) {
            Write-Host 'Unlock the phone, keep its screen on, and confirm the installation request.'
            & $Adb -s $Serial install --user 0 -r $apk
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Installation failed. No uninstall, signature replacement or security-policy change will be attempted.'
                Invoke-Adb @('-s',$Serial,'push',$apk,'/sdcard/Download/FixMiCTS.apk')
                throw 'Open Files > Download > FixMiCTS.apk on the phone and confirm the update. Then rerun INSTALL_TO_VIVO.cmd: it recognizes an identical installed APK and only grants/checks permission and opens the app. If signature conflict is reported, retain the original signing key; do not uninstall blindly.'
            }
        } else { Write-Host 'Exact APK already installed (SHA256 matched); skipping installation.' }
        Invoke-Adb @('-s',$Serial,'shell','pm','grant','--user','0',$Package,'android.permission.WRITE_SECURE_SETTINGS')
        Write-Host '=== Permission readback; confirm GRANTED in the app for user 0 ==='
        Invoke-Adb @('-s',$Serial,'shell','dumpsys','package',$Package) | Select-String 'WRITE_SECURE_SETTINGS|User 0:|versionCode=|versionName='
        Invoke-Adb @('-s',$Serial,'shell','am','start','--user','0','-W','-n',($Package+'/.MainActivity'))
        Write-Host 'INSTALL/GRANT commands completed. Verify UI shows GRANTED, press FIX NOW, then test actual MiCTS. Installation alone does not prove recovery or boot execution.'
    } elseif ($Mode -eq 'Fix') {
        $assistant = (Invoke-Adb @('-s',$Serial,'shell','settings','get','--user','0','secure','assistant') | Out-String).Trim()
        $vis = (Invoke-Adb @('-s',$Serial,'shell','settings','get','--user','0','secure','voice_interaction_service') | Out-String).Trim()
        if ($assistant -ne $Component -or ($vis -and $vis -ne 'null' -and $vis -ne $Component)) { throw 'Not changed: assistant is not Google or another voice service is selected.' }
        Invoke-Adb @('-s',$Serial,'shell','settings','put','--user','0','secure','voice_interaction_service',$Component)
        Write-Host 'PC fallback write completed as ADB shell; this is NOT proof of app-UID or automatic recovery.'
        Start-Sleep -Seconds 3
    }
    Write-Host '=== VoiceInteraction binding (read only) ==='
    Invoke-Adb @('-s',$Serial,'shell','dumpsys','voiceinteraction') | Select-String 'mUser=|mComponent=|mBound=|No active implementation'
    if ($Mode -eq 'Diagnose') {
        Write-Host '=== App-only logs; launching the app is NOT required ==='
        Invoke-Adb @('-s',$Serial,'logcat','-d','-s','FixMiCTS:I','*:S') | Select-Object -Last 80
        Write-Host 'Version 1.2 uses a short direct BOOT_COMPLETED worker, NOT JobScheduler. Look for origin=boot receiver, worker duration, and a real MiCTS test. Do not force-run a job as automatic acceptance.'
    }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
