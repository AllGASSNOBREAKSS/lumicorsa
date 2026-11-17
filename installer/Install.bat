@echo off
rem Double-click installer: runs the readable PowerShell script next to it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install-Photolap.ps1" %*
pause
