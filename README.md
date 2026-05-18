# WiFi Phone Control

Windows desktop app for Android Wi-Fi pairing, reconnect monitoring, and scrcpy control.

## Release Usage

For normal users, use the release ZIP:

1. Download `WiFiPhoneControl-v1.0.0-win-x64.zip`.
2. Extract the ZIP to any local folder, for example `C:\WiFiPhoneControl`.
3. Double-click `WiFiPhoneControl.exe`.
4. On the Android device, enable Developer options -> Wireless debugging -> Pair device with pairing code.
5. Enter the pair endpoint and pair code in the app, then click **Pair & Connect**.
6. Click **Start Control (scrcpy)**.

The release ZIP bundles the official scrcpy Windows x64 runtime, including `scrcpy.exe`, `adb.exe`, required DLLs, and `scrcpy-server`. Release users do not need `winget`, a separate Android platform-tools install, or a separate scrcpy install.

## System Requirements

- Windows 10/11 x64
- Android device with wireless debugging enabled
- Host PC and Android device on a reachable network

Windows security prompts, firewall prompts, and Android wireless debugging authorization prompts are still controlled by the local environment.

## Bundled Runtime

The release build pins:

- scrcpy: `4.0`
- adb/platform-tools: `37.0.0` as bundled by scrcpy 4.0
- Windows x64 asset: `scrcpy-win64-v4.0.zip`
- SHA256: `75dbeb5b00e6f64292f26f70900ae55ca397786bdfb0b9bbeb481a0549047457`

The app only uses `runtime\scrcpy` from the extracted release package. If the runtime folder or required files are missing, the app reports an incomplete release package and does not install dependencies online.

## Build Release

Build from source on Windows:

```powershell
.\build-release.cmd
```

The build script:

- Downloads the pinned official scrcpy Windows x64 ZIP if it is not already cached.
- Verifies the SHA256 hash before using it.
- Builds `dist\WiFiPhoneControl.exe` with `ps2exe`.
- Creates `release\WiFiPhoneControl-v1.0.0-win-x64.zip`.
- Validates that the release ZIP contains the app, config, profiles, docs, and complete `runtime\scrcpy`.

Build dependency:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
```

If `ps2exe` is missing, the build script attempts to install it for the current user.

## Project Structure

```text
app/        GUI entry script
core/       reusable modules
config/     default settings
profiles/   default device profiles
runtime/    runtime notes; release builds populate runtime/scrcpy
tools/      build scripts
docs/       release acceptance checklist
```

## Release Gate

Before publishing any `WiFiPhoneControl-vX.Y.Z-win-x64.zip`, complete the checklist in `docs/release-acceptance.md`.

Release notes must include:

- System requirements: Windows 10/11 x64
- Bundled dependency versions: scrcpy 4.0 and adb 37.0.0
- Verification statement for a fresh/offline Windows acceptance environment

## License

MIT License. See [LICENSE](LICENSE).
