# FixMiCTS

## Download

- **[Download FixMiCTS.apk](https://github.com/Flexible78/FixMiCTS/releases/download/v1.3.1/FixMiCTS.apk)** — signed Android application.
- **[Download the public ZIP](https://github.com/Flexible78/FixMiCTS/releases/download/v1.3.1/FixMiCTS-1.3.1-public.zip)** — source, Windows helpers and APK.
- [Release details and SHA256 checksums](https://github.com/Flexible78/FixMiCTS/releases/tag/v1.3.1)
- [Инструкция на русском](README_RU.md)

The APK is under release **Assets**, not in the source-code file list. This is the FixMiCTS companion repair application; install the original MiCTS separately.

Minimal, unofficial Android workaround for two related OriginOS boot failures: Google VoiceInteractionService initialization (MiCTS / Circle to Search) and the Vivid N.G. accessibility service that drives its gesture engine. Companion to [MiCTS](https://github.com/parallelcc/MiCTS), not a replacement or fork of MiCTS. This project does not implement Circle to Search and does not claim invention of that feature or of its trigger.

**Experimental / prerelease.** On Vivo X100 Ultra V2366HA, Android 16, OriginOS 16, firmware PD2366H_A_16.2.19.0.W10: manual recovery from an empty VIS setting and automatic reboot recovery of both the Google voice service and Vivid N.G. were verified. Three cold power cycles, multi-day reliability and comparable day/night battery acceptance remain pending. Other models and firmware versions are not verified.

## How it works

A delivered BOOT_COMPLETED broadcast starts one short goAsync worker that performs two conservative Secure Settings operations:

- **MiCTS / Google VIS.** A public `Settings.Secure.putString` write for `voice_interaction_service`, only for Android user 0 and only while the exact Google assistant is selected and the service setting is empty or already Google. It refuses to replace another nonempty service or another assistant.
- **Vivid N.G.** (`com.ivianuu.oneplusgestures`) append-only write of `Settings.Secure.enabled_accessibility_services` (other services are never replaced) plus `accessibility_enabled=1`, which re-binds `VividAccessibilityService` exactly like manually enabling the "Enabled" toggle, without the "Vivid N.G. requests permission..." confirmation dialog. A best-effort `com.ivianuu.vivid.TURN_GESTURES_ON` broadcast is then sent. Skipped when Vivid is not installed.

A readable boot_count prevents duplicate automatic attempts. There is no recurring retry, scheduler, resident service, network permission, root or shell execution inside the app. FIX NOW is the manual fallback and repairs both. Merely opening the Activity does not repair settings.

WRITE_SECURE_SETTINGS must be granted once through ADB. This is a powerful permission: review the source and trust the APK before granting it. OriginOS Autostart must be enabled for **Fix MiCTS**. It is separate from the original MiCTS app's background controls.

```text
adb shell pm grant --user 0 dev.alextsyrkin.fixmicts android.permission.WRITE_SECURE_SETTINGS
```

## Installation on Windows 11

1. Download the signed APK and matching SHA256 from GitHub Releases; verify its checksum. No APK build is required to use a release.
2. Connect and authorize ADB. For wireless debugging use the phone's current connection port, not its pairing port.
3. Put FixMiCTS.apk and FixMiCTS.apk.sha256 beside INSTALL_TO_VIVO.cmd and run it. The helper is intentionally restricted to the verified Vivo model and user 0. If ADB installation is rejected, follow its phone-side Download-folder installation instructions. Do not uninstall blindly or disable installation security.
4. Enable OriginOS Autostart for Fix MiCTS. Check GRANTED, use FIX NOW, then test the actual MiCTS gesture and Vivid gestures.
5. Test boot recovery separately, without opening Fix MiCTS, pressing FIX NOW or changing assistant before testing. Reboots/power cycles are user-initiated, not part of installation.

Accepted write/readback does **not** prove that the Android service is connected. Test the feature and, if needed, use DIAGNOSE.cmd to inspect binding. FIX_FROM_PC.cmd is an explicit settings-writing fallback, not read-only diagnostics.

## Verified and unverified behavior

- A real signed 1.3.1 APK was built with JDK 21.0.8, Android Platform 35 and Build Tools 35.0.1; signature, alignment, version and DEX were checked. The same signing identity is retained across builds.
- Manual recovery from an actually empty VIS setting succeeded from ordinary app UID, followed by bound Google VIS and a user-visible MiCTS test.
- Automatic reboot recovery of both repairs was confirmed: Vivid was deliberately broken before reboot, the app's persisted status showed origin `boot receiver`, and afterwards the Vivid accessibility service was bound (`Bound services:{Vivid N.G.}`) with Google VIS `mBound=true`.
- A defect found during testing and fixed: targetSdk 32 hid the Vivid package from Android 11+ package visibility, so `<queries>` is now declared; without it the Vivid repair reported "not installed".
- An already-correct setting with a **broken** binding has NOT been shown to recover through ordinary app UID for the Google VIS key.
- Direct boot delivery before first unlock, every future boot, other profiles and permanent firmware repair are not guaranteed.
- No zero-drain claim. Battery collector execution was tested, but long-term battery benefit is not established.

## Build and signing

Run BUILD_APK.cmd on Windows. It validates a complete JDK 17 or 21 and downloads pinned Android tools using SHA256 checks. Internet access and applicable upstream SDK/JDK terms are required. Dependencies are not bundled in this repository. Gradle files are provided, but Gradle/Android Studio builds and Play publication were not verified; targetSdk 32 is retained for the tested personal sideload case.

On a new checkout the direct builder creates your own signing identity in _build. Keep its key and password private and backed up. A locally rebuilt APK signed by your own key cannot update the maintainer-signed release APK. Never commit _build, .sdk, keys, passwords or diagnostic reports. Loss of a signing key prevents compatible updates. Bit-for-bit build reproducibility is not claimed.

## Read-only battery diagnostics

BATTERY_AUDIT.cmd collects bounded, read-only device diagnostics into a new Windows TEMP folder, explicitly scoped to the verified Vivo/user 0. Select a transport with -Serial when both USB and Wi-Fi are connected. It does not reboot, install, reset statistics, force-stop, disable, uninstall or grant/revoke permissions. Android energy numbers are estimates; shared UID and OEM attribution limitations apply. Collect comparable 24-48h normal-use observations before considering changes.

Masking is best-effort, not guaranteed anonymization. Package inventories, OEM labels and logs can reveal private information: review locally and do not upload entire reports. No personal battery ranking or device logs are included here. This is not a debloat utility.

## Attribution and license

Created and maintained by Flexible78 with AI-assisted development and auditing. Published project code is provided under the MIT license; see LICENSE. No MiCTS implementation, MiCTS APK, Google APK, third-party automation APK, forum screenshots or third-party SDK binaries are included. MiCTS is a separately maintained GPL-3.0 project; its license remains its own. Vivid N.G. is a separate third-party application and is not redistributed. Using their names for interoperability does not imply endorsement by their authors, Google or Vivo.

Related community setup instructions: https://4pda.to/forum/index.php?showtopic=1092982&view=findpost&p=135605033 . This project addresses narrower observed boot failures rather than claiming a new way to enable Circle to Search.

For issue reports provide model, firmware, app version, permission status and reviewed minimal diagnostics. Never share keystores, passwords, accounts, device serials or full bugreports.
