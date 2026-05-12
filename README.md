# WiFi Phone Control

A Windows desktop project for Android **Wi-Fi pairing + control** with `adb` and `scrcpy`.

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
- `adb` and `scrcpy` (from winget package `Genymobile.scrcpy`)
- Optional: `ps2exe` module (for building EXE)

## Dependencies

Install `scrcpy` (includes `adb`):

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
2. Prepare dependencies (choose one):
   - **Option A (recommended for non-technical users):** provide full scrcpy runtime in `runtime\scrcpy\`.
   - **Option B:** install with winget:
     ```powershell
     winget install Genymobile.scrcpy
     ```
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
- Keep `dist\core`, `dist\config`, `dist\profiles`, and optional `dist\runtime` together with the exe.

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
