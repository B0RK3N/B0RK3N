@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0client\Connect.ps1"
if errorlevel 1 pause
