# WiFi Phone Control

A Windows desktop project for Android **Wi-Fi pairing + control** with built-in `adb` and `scrcpy` runtime in release package.

## Highlights

- Modern desktop GUI (WinForms)
- Chinese / English UI switch
- Dark / light theme switch
- Pairing workflow (`adb pair` + auto endpoint detect)
- Auto reconnect monitor (for sleep/off-screen reconnect attempts)
- Multi-profile device endpoint management
- Optional EXE packaging for release

## Tech Stack

- PowerShell 5.1+
- Windows Forms (.NET Framework)
- `adb` and `scrcpy` (release zip already bundles official runtime files)
- Optional: `ps2exe` module (for building EXE)

## Dependencies

Release package users do not need to install `scrcpy` or `adb` separately.

If you are developing from source and want local fallback tooling, you can still install via winget:

```powershell
winget install Genymobile.scrcpy
```

Optional build dependency:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
```

Portable dependency mode (recommended for open-source distribution):

- Do **not** bundle only two exe files.
- Bundle the **full scrcpy Windows package** (all files), for example:
  - `runtime\scrcpy\scrcpy.exe`
  - `runtime\scrcpy\adb.exe`
  - `runtime\scrcpy\AdbWinApi.dll`
  - `runtime\scrcpy\AdbWinUsbApi.dll`
  - `runtime\scrcpy\SDL2.dll`
  - plus other files from the official release archive
- App will prefer bundled binaries first.
- If runtime is missing, app tries winget install fallback.

## Fresh PC install & run (from GitHub)

1. Download this repository (ZIP) and extract it, e.g. `C:\WiFiPhoneControl`.
2. Prepare runtime files:
   - Put the **full official scrcpy Windows release package** under `runtime\scrcpy\` before building release.
3. Build EXE:
   ```powershell
   .\build-release.cmd
   ```
4. Run:
   - Double-click `dist\WiFiPhoneControl.exe`
5. First use:
   - Pair in app, then connect, then start control.

Notes:
- On some clean Windows systems, install Microsoft Visual C++ Redistributable (x64) if scrcpy cannot start.
- Release ZIP (`dist\WiFiPhoneControl-v1.0.0-win-x64.zip`) already includes `WiFiPhoneControl.exe`, `core/`, `config/`, `profiles/`, and `runtime\scrcpy\`; extract and run directly (no winget required).

## Quick Start

1. Build EXE once
   - Run `build-release.cmd`
2. Start app (no CMD window)
   - Double-click `dist\WiFiPhoneControl.exe`
3. First pairing
   - On device: Developer options -> Wireless debugging -> Pair device with pairing code
   - Fill **Pair Endpoint** and **Pair Code**
   - Click **Pair & Connect**
4. Start control
   - Click **Start Control (scrcpy)**
   - Keep auto monitor enabled

## Project Structure

```text
app/        GUI entry script
core/       reusable modules (common/pairing/control/monitor)
config/     settings.json
profiles/   devices.json
state/      endpoint/ip runtime state
logs/       daily logs
tools/      build scripts
```

## Build Release EXE

```powershell
.\build-release.cmd
```

Output:

```text
dist\WiFiPhoneControl.exe
```

## License

MIT License. See [LICENSE](LICENSE).


## Release Package Validation

`tools/build-release.ps1` now validates the generated ZIP and requires:

- `runtime/scrcpy/scrcpy.exe`
- `runtime/scrcpy/adb.exe`
- `runtime/scrcpy/AdbWinApi.dll`
- `runtime/scrcpy/AdbWinUsbApi.dll`

If any required runtime file is missing, build will fail before release.

## Release Process Gate

Before publishing `WiFiPhoneControl-vX.Y.Z-win-x64.zip`, you must pass:

1. **Artifact check** and
2. **Manual acceptance sign-off**

Follow the checklist in `docs/release-acceptance.md`. If checklist items are incomplete, the release ZIP must not be published.

### Required release note content

Every release note must include:

- System requirements: Windows 10/11 x64
- Bundled dependency versions (at least `scrcpy` and `adb`)
- Acceptance verification statement (fresh/offline environment)
