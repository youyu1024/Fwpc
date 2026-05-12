@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\wifi-phone-control-gui.ps1"
if errorlevel 1 (
  echo GUI start failed. Please check errors above.
  pause
)
