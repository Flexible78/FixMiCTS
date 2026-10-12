param(
    [string]$Serial = $env:ANDROID_SERIAL,
    [string]$OutputDirectory,
    [ValidateRange(5,120)][int]$CommandTimeoutSeconds = 30
)
# Read-only phone diagnostics. No installs, settings writes, resets or app launches.
$ErrorActionPreference = 'Stop'
$Utf8 = [System.Text.UTF8Encoding]::new($false)
$Packages = @('com.parallelc.micts','com.google.android.googlequicksearchbox','com.google.android.tts','dev.alextsyrkin.fixmicts','com.google.android.gms')
$LocalAdb = Join-Path $PSScriptRoot 'adb.exe'
if (Test-Path -LiteralPath $LocalAdb) { $Adb = $LocalAdb }
else {
    $AdbCommand = Get-Command adb.exe -ErrorAction Stop
    $Adb = $AdbCommand.Source
}
function Invoke-BoundedAdb([string[]]$AdbArguments) {
    # No shell command construction: launch adb directly. Arguments are fixed
    # diagnostic tokens or a validated transport serial, never user shell text.
    foreach ($Argument in $AdbArguments) {
        if ($Argument -notmatch '^[A-Za-z0-9_./:@*?=%+-]+$') { throw 'Unsafe diagnostic argument.' }
    }
    $Info = [System.Diagnostics.ProcessStartInfo]::new()
    $Info.FileName = $Adb
    $Info.Arguments = $AdbArguments -join ' '
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Info.StandardOutputEncoding = $Utf8
    $Info.StandardErrorEncoding = $Utf8
    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $Info
    try {
        if (!$Process.Start()) { throw 'Cannot start adb.' }
        $Stdout = $Process.StandardOutput.ReadToEndAsync()
        $Stderr = $Process.StandardError.ReadToEndAsync()
        if (!$Process.WaitForExit($CommandTimeoutSeconds * 1000)) {
            # Stop only this host-side diagnostic client, never the ADB server
            # or a phone process. Never retry indefinitely.
            $Process.Kill()
            $Process.WaitForExit()
            return [pscustomobject]@{ Code = 124; Text = 'TIMEOUT: host diagnostic client stopped; remote dump may finish independently.' }
        }
        return [pscustomobject]@{ Code = $Process.ExitCode; Text = ($Stdout.GetAwaiter().GetResult() + "`n" + $Stderr.GetAwaiter().GetResult()).Trim() }
    } finally { $Process.Dispose() }
}
function Protect-Text([string]$Text) {
    if ($Serial) { $Text = $Text.Replace($Serial, '<device>') }
    $Text = [regex]::Replace($Text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '<email>')
    $Text = [regex]::Replace($Text, '(?i)https?://\S+', '<url>')
    $Text = [regex]::Replace($Text, '\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b', '<ip>')
    $Text = [regex]::Replace($Text, '(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b', '<mac>')
    $Text = [regex]::Replace($Text, '\b\d{14,16}\b', '<long-number>')
    $Text = [regex]::Replace($Text, '(?im)^.*\b(?:imei|imsi|iccid|subscriberId|serialNumber|access_token|refresh_token|authorization|accountName|ssid|bssid|wifiNetworkKey|networkId)\b.*$', '<sensitive line omitted>')
    return $Text
}
function Save-Text([string]$Name, [string]$Text) {
    [System.IO.File]::WriteAllText((Join-Path $OutputDirectory $Name), (Protect-Text $Text), $Utf8)
}
function Save-Diagnostic([string]$Name, [string[]]$ShellArguments) {
    $Started = [DateTimeOffset]::Now
    $Result = Invoke-BoundedAdb (@('-s',$Serial,'shell') + $ShellArguments)
    $Status = 'OK'
    if ($Result.Code -ne 0 -or $Result.Text -match '(?im)SecurityException|Permission Denial|Unknown (command|option)|not found|not supported|Error:') { $Status = 'GAP' }
    Save-Text $Name ("Captured: $($Started.ToString('o'))`nRead-only: adb shell $($ShellArguments -join ' ')`nExit: $($Result.Code); status: $Status`n`n" + $Result.Text)
    $script:Index.Add([pscustomobject]@{ File = $Name; Status = $Status; Exit = $Result.Code; Time = $Started.ToString('o') })
    Write-Host "$Status $Name"
    return $Result
}
try {
    $Listing = Invoke-BoundedAdb @('devices','-l')
    if ($Listing.Code -ne 0) { throw 'ADB device enumeration failed.' }
    $Online = @($Listing.Text -split '\r?\n' | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' } | ForEach-Object { ($_ -split '\s+')[0] })
    if (!$Serial) {
        if ($Online.Count -ne 1) { throw 'Need exactly one online phone. Unlock/reconnect it; for Wi-Fi use its CURRENT connection IP:port, not the pairing port. No phone changes made.' }
        $Serial = $Online[0]
    }
    if ($Online -notcontains $Serial) { throw 'Selected phone is not online. No phone changes made.' }
    $Model = Invoke-BoundedAdb @('-s',$Serial,'shell','getprop','ro.product.model')
    $User = Invoke-BoundedAdb @('-s',$Serial,'shell','am','get-current-user')
    if ($Model.Code -ne 0 -or $User.Code -ne 0 -or $Model.Text.Trim() -ne 'V2366HA' -or $User.Text.Trim() -ne '0') { throw 'Expected Vivo V2366HA and active user 0. No phone changes made.' }
    if (!$OutputDirectory) {
        $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('FixMiCTS-Battery-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory already exists. Choose a new directory; existing reports are never overwritten.' }
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $script:Index = [System.Collections.Generic.List[object]]::new()
    Write-Host "Temporary local reports: $OutputDirectory"
    Write-Host 'Best-effort redaction only. Package inventory and wake/job names may still be private. Review before sharing; remove reports manually when no longer needed.'
    $null = Save-Diagnostic '01-phone-time.txt' @('date','+%Y-%m-%dT%H:%M:%S%z')
    $null = Save-Diagnostic '02-uptime.txt' @('cat','/proc/uptime')
    $null = Save-Diagnostic '03-battery-start.txt' @('dumpsys','battery')
    $null = Save-Diagnostic '04-thermal.txt' @('dumpsys','thermalservice')
    $Help = Save-Diagnostic '05-batterystats-help.txt' @('dumpsys','batterystats','-h')
    if ($Help.Code -eq 0 -and $Help.Text.Contains('--usage')) {
        # Supported Android 16 aggregate energy report, without event history.
        # Do not use --checkin: device help says it can clear old saved stats.
        $null = Save-Diagnostic '06-batterystats.txt' @('dumpsys','batterystats','--usage')
    } else {
        Save-Text '06-batterystats.txt' 'GAP: aggregate --usage not advertised. Full history intentionally not collected. Use phone Battery usage screenshots without personal notifications; no statistics reset.'
        $script:Index.Add([pscustomobject]@{ File = '06-batterystats.txt'; Status = 'GAP'; Exit = -1; Time = [DateTimeOffset]::Now.ToString('o') })
    }
    if ($Help.Code -eq 0 -and $Help.Text.Contains('--cpu')) {
        $null = Save-Diagnostic '06b-battery-cpu.txt' @('dumpsys','batterystats','--cpu')
    }
    if ($Help.Code -eq 0 -and $Help.Text.Contains('--charged')) {
        # Obtain the observation window without persisting history, job names
        # or other arbitrary lines from the full aggregate dump.
        $WindowTime = [DateTimeOffset]::Now
        $WindowDump = Invoke-BoundedAdb @('-s',$Serial,'shell','dumpsys','batterystats','--charged')
        $WindowLines = @($WindowDump.Text -split '\r?\n' | Where-Object {
            $_ -match '(?i)^\s*(Statistics since|Start clock time:|Time on battery:|Time on battery screen off:|Time on battery screen doze:|Total run time:|Screen on:|Screen doze:|Discharge:|Estimated battery capacity:|Last learned battery capacity:|Min learned battery capacity:|Max learned battery capacity:|System starts:|Capacity:)'
        })
        $WindowStatus = 'OK'
        if ($WindowDump.Code -ne 0 -or !($WindowLines -match 'Start clock time:') -or !($WindowLines -match 'Time on battery:')) { $WindowStatus = 'GAP' }
        Save-Text '06c-statistics-window.txt' ("Captured: $($WindowTime.ToString('o'))`nRead-only: dumpsys batterystats --charged; only allowlisted aggregate headers retained.`nExit: $($WindowDump.Code); status: $WindowStatus`nSequential snapshot: do not assume identical epochs across a charging reset.`n`n" + ($WindowLines -join "`n"))
        $script:Index.Add([pscustomobject]@{ File = '06c-statistics-window.txt'; Status = $WindowStatus; Exit = $WindowDump.Code; Time = $WindowTime.ToString('o') })
        Write-Host "$WindowStatus 06c-statistics-window.txt"
        $WindowDump = $null
    }
    $null = Save-Diagnostic '07-packages-user0-uid.txt' @('cmd','package','list','packages','-U','--user','0')
    $null = Save-Diagnostic '08-doze-whitelist.txt' @('dumpsys','deviceidle','whitelist')
    $null = Save-Diagnostic '09-doze-state.txt' @('dumpsys','deviceidle')
    $null = Save-Diagnostic '10-cpu-snapshot.txt' @('dumpsys','cpuinfo')
    $null = Save-Diagnostic '11-network-summary.txt' @('dumpsys','netstats','--summary')
    foreach ($Package in $Packages) {
        $null = Save-Diagnostic ($Package + '-appops.txt') @('cmd','appops','get','--user','0',$Package)
        $null = Save-Diagnostic ($Package + '-background-appop.txt') @('cmd','appops','get','--user','0',$Package,'RUN_IN_BACKGROUND')
        $null = Save-Diagnostic ($Package + '-any-background-appop.txt') @('cmd','appops','get','--user','0',$Package,'RUN_ANY_IN_BACKGROUND')
        $null = Save-Diagnostic ($Package + '-inactive.txt') @('am','get-inactive','--user','0',$Package)
        $null = Save-Diagnostic ($Package + '-standby.txt') @('am','get-standby-bucket','--user','0',$Package)
    }
    $null = Save-Diagnostic '12-assistant.txt' @('settings','get','--user','0','secure','assistant')
    $null = Save-Diagnostic '13-voice-service-setting.txt' @('settings','get','--user','0','secure','voice_interaction_service')
    # Avoid a full VoiceInteraction dump (session data). Only binding lines.
    $Binding = Invoke-BoundedAdb @('-s',$Serial,'shell','dumpsys','voiceinteraction')
    $BindingLines = @($Binding.Text -split '\r?\n' | Where-Object { $_ -match 'mUser=|mComponent=|mBound=|No active implementation' })
    $BindingStatus = 'OK'
    if ($Binding.Code -ne 0 -or $BindingLines.Count -eq 0) { $BindingStatus = 'GAP' }
    Save-Text '14-voice-binding.txt' ("Exit: $($Binding.Code); status: $BindingStatus`n" + ($BindingLines -join "`n"))
    $script:Index.Add([pscustomobject]@{ File = '14-voice-binding.txt'; Status = $BindingStatus; Exit = $Binding.Code; Time = [DateTimeOffset]::Now.ToString('o') })
    Write-Host "$BindingStatus 14-voice-binding.txt"
    $null = Save-Diagnostic '15-battery-end.txt' @('dumpsys','battery')
    Save-Text 'INDEX.csv' (($script:Index | ConvertTo-Csv -NoTypeInformation) -join "`r`n")
    $Notes = @'
READ ONLY: no reboot, install, grant/revoke, settings/appops writes, process killing, battery reset, bugreport or logcat. No phone-side files created. ADB itself and dump commands have brief diagnostic overhead; Wi-Fi ADB can affect standby. Disconnect using the phone UI for normal-use measurements, then reconnect for the next snapshot.

These are sequential snapshots, not atomic measurements. CPU snapshot/RAM/process presence does not establish battery drain. Android per-UID mAh is generally a modeled estimate, not an independent meter. Shared UID, system attribution and OEM omissions limit package ranking. Confirm the statistics start/end window, charging history, screen time, radio/network and user activity before interpreting results. Charging may change the statistics window; never reset history for this audit.

Aggregate batterystats --usage provides available per-UID energy estimates; --cpu provides battery CPU attribution if supported. These are not a complete wakelock/job/alarm audit. Full event history is intentionally not persisted. If data is missing, record a gap instead of inferring zero consumption. This collector does not prove OriginOS Autostart or all proprietary background controls. On the phone search Settings for Battery usage, Background power consumption and Autostart (localized menu names vary); record the interval and exact selected options for MiCTS, Google, Google TTS and Fix MiCTS. Do not change them yet.

For a useful baseline, capture now and after 24-48h typical use, including one unplugged night. Record charge %, times, screen-on time, signal conditions, charging, unusual use and whether Wi-Fi ADB was active. Do not compare UID totals across a reset/new statistics epoch without accounting for it. No automatic cleanup/retention daemon is installed. Reports live in Windows TEMP by default and are not intended for permanent storage.

Privacy: no device serial is intentionally saved; email/URL/IP/MAC/long-number and selected sensitive lines are masked. This is best-effort, NOT guaranteed anonymization. Package names reveal installed apps, and OEM wake/job labels may contain personal text. Review locally; share only necessary excerpts. Do not publish the whole folder or include it in the project ZIP. Remove this exact report folder manually after analysis, retaining only a reviewed aggregate audit table if desired.

No optimization is authorized by this collection. Preserve Fix MiCTS WRITE_SECURE_SETTINGS and Autostart. A USER Doze exemption does not prove it was an experiment. AppOps default allow does not prove a previous override. Do not set inactive=true as an alleged rollback of inactive=false. Every actual change needs a captured original state, explicit consent, one-change functional/battery comparison and exact rollback.
'@
    Save-Text 'READ_ME_FIRST.txt' $Notes
    $Gaps = @($script:Index | Where-Object Status -eq 'GAP').Count
    Write-Host "Collection finished; diagnostic gaps: $Gaps. No battery-drain or MiCTS functionality verdict is inferred."
    Write-Host "Reports: $OutputDirectory"
    if ($Gaps -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Host ('FAILED: ' + (Protect-Text $_.Exception.Message)) -ForegroundColor Red
    exit 1
}
