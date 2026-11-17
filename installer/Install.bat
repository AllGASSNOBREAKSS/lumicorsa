@echo off
rem Double-click installer: runs the readable PowerShell script (copies the CSP app into AC, nothing else).
set "PS1=%~dp0Install-Photolap.ps1"
if not exist "%PS1%" set "PS1=%~dp0installer\Install-Photolap.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
pause
