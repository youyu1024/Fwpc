# Release acceptance

Record the release ZIP, tester, date, Windows version, and test results. Record the Android model and version for device tests. Use the same build for desktop and phone verification.

## Package and Windows

- [ ] Verify the ZIP contains the launcher, core modules, default settings, profiles, quick-start guide and standalone scrcpy runtime.
- [ ] Extract to a fresh folder and start the launcher from a different working directory on Windows 10 or 11 x64. The bundled ADB and scrcpy run without separate installs.
- [ ] Start a copy with a required runtime file missing. The Control center explains how to recover.
- [ ] Check the Control center, six-digit wizard, settings and diagnostics in Simplified Chinese and English. Check keyboard actions, light and dark themes, and 100%, 125% and 150% display scaling.
- [ ] Run tests\connection.tests.ps1 with Windows PowerShell. Record device-selection, pairing, reconnect, timeout, cancellation and USB results.

## Android devices

- [ ] Pair with a fresh six-digit code and control the intended phone. Check that an incorrect or expired code prompts for a new one.
- [ ] Connect two phones and an emulator. USB requires selection when several USB phones are available. Wi-Fi discovery and reconnect retain the chosen target.
- [ ] Test a network without discovery where the phone's current connection address is reachable. Manual address entry resumes the connection after successful pairing.
- [ ] Check guest network isolation, a changed wireless port, a Wi-Fi interruption, and revoked authorization. Confirm the app displays the action appropriate to each state.
- [ ] Turn off Wi-Fi and start a USB session. Check initial USB authorization, data-cable detection, unplug and reconnect, and failure when a charging-only cable is used.
- [ ] Verify video, keyboard and mouse control, display options, phone shortcuts and screenshot capture on an authorized device.

Publish the package after completing the required checks. Label builds with pending physical-device results as preview builds and record the unverified cases.
