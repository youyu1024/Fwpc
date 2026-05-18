# Release Acceptance (Windows x64)

## Acceptance Environment

Run acceptance on a fresh machine or clean VM with:

- Windows 10 x64 or Windows 11 x64
- No preinstalled `adb`
- No preinstalled `scrcpy`
- No dependency on `winget` or online dependency install after the ZIP is extracted

The Android device still needs wireless debugging enabled, local network connectivity, and any required Windows firewall/security approvals.

## Artifact Check

Before publishing, verify the artifact:

- [ ] Release artifact name is exactly `WiFiPhoneControl-vX.Y.Z-win-x64.zip`.
- [ ] ZIP contains `WiFiPhoneControl.exe`.
- [ ] ZIP contains `QUICKSTART.txt` and `LICENSE`.
- [ ] ZIP contains `core/`, `config/`, and `profiles/`.
- [ ] ZIP contains `runtime/scrcpy/scrcpy.exe`.
- [ ] ZIP contains `runtime/scrcpy/adb.exe`.
- [ ] ZIP contains `runtime/scrcpy/AdbWinApi.dll`.
- [ ] ZIP contains `runtime/scrcpy/AdbWinUsbApi.dll`.
- [ ] ZIP contains `runtime/scrcpy/scrcpy-server`.
- [ ] ZIP contains SDL and FFmpeg DLLs from the official scrcpy Windows x64 release.

## Manual Acceptance

The following items are the minimum go/no-go criteria:

- [ ] Extracting `WiFiPhoneControl-vX.Y.Z-win-x64.zip` produces a self-contained app folder.
- [ ] Double-clicking `WiFiPhoneControl.exe` starts the application successfully.
- [ ] Pairing workflow can be entered and accepts pairing endpoint/code input.
- [ ] Pair & Connect can use the bundled `runtime/scrcpy/adb.exe`.
- [ ] Start Control can launch the bundled `runtime/scrcpy/scrcpy.exe` when device connectivity prerequisites are met.
- [ ] Acceptance is completed without installing `adb`, `scrcpy`, Android platform-tools, or `winget` packages.

If any item above is not checked, do not publish the release ZIP.

## Release Note Requirements

Each release note must explicitly include:

1. System requirements: Windows 10/11 x64
2. Bundled dependency versions:
   - scrcpy 4.0
   - adb/platform-tools 37.0.0
3. Verification statement:
   - Confirmed in a fresh/offline Windows acceptance environment
4. Tester and date
