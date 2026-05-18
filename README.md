# WiFi Phone Control

A Windows desktop project for Android **Wi-Fi pairing + control** with `adb` and `scrcpy`.

## Highlights

- Modern desktop GUI (WinForms)
- Chinese / English UI switch
- Dark / light theme switch
- Pairing workflow (`adb pair` + auto endpoint detect)
- Auto reconnect monitor
- Multi-profile device endpoint management
- Release ZIP supports **download + extract + run** on fresh Windows PCs

## Tech Stack

- PowerShell 5.1+
- Windows Forms (.NET Framework)
- `adb` + `scrcpy` runtime bundled in release ZIP
- `ps2exe` (used during build)

## Commands

### 1) Development build (`dist`)

```powershell
.\build-release.cmd
```

What it does:

- Builds `dist\WiFiPhoneControl.exe`
- Copies `core\`, `config\`, `profiles\`, `runtime\` into `dist\`
- Produces ZIP in `dist\WiFiPhoneControl-vX.Y.Z-win-x64.zip`
- Fails fast if runtime is incomplete

### 2) Release packaging (`release`) - recommended for publishing

```powershell
.\package-release.cmd
```

What it does:

- Reads version from `config\release.json`
- Auto-provisions `runtime\scrcpy\` from official scrcpy GitHub release when missing
- Builds app and validates runtime/dependency completeness
- Produces publish artifact in `release\WiFiPhoneControl-vX.Y.Z-win-x64.zip`

## Fresh PC usage (release user)

1. Download `WiFiPhoneControl-vX.Y.Z-win-x64.zip` from release assets.
2. Extract ZIP to any local folder.
3. Double-click `WiFiPhoneControl.exe`.
4. Pair device and start control.

No `winget`, `adb`, or `scrcpy` preinstallation is required for release users.

## Runtime requirements for release artifact

Release ZIP must include these files:

- `runtime\scrcpy\scrcpy.exe`
- `runtime\scrcpy\adb.exe`
- `runtime\scrcpy\AdbWinApi.dll`
- `runtime\scrcpy\AdbWinUsbApi.dll`
- `runtime\scrcpy\SDL2.dll`

These are validated by `tools\build-release.ps1` before release packaging succeeds.

## Release gate

Before publishing `WiFiPhoneControl-vX.Y.Z-win-x64.zip`, follow:

- `docs\release-acceptance.md` artifact checklist
- Fresh/offline acceptance checklist

If any gate item fails, do not publish the ZIP.

## Project Structure

```text
app/        GUI entry script
core/       reusable modules (common/pairing/control/monitor)
config/     settings + release metadata
profiles/   devices.json
state/      endpoint/ip runtime state
logs/       daily logs
tools/      build and packaging scripts
```

## License

MIT License. See [LICENSE](LICENSE).
