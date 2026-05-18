Runtime folder note

Source checkout:
- runtime\scrcpy is not committed.
- tools\build-release.ps1 downloads the pinned official scrcpy Windows x64 release automatically.

Release ZIP:
- runtime\scrcpy must contain the full official scrcpy Windows x64 package.
- Required files include scrcpy.exe, adb.exe, AdbWinApi.dll, AdbWinUsbApi.dll, scrcpy-server, SDL DLLs, and FFmpeg DLLs.
- The app treats missing runtime files as an incomplete release package and does not install dependencies online.
