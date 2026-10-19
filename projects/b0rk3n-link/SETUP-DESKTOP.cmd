@echo off
setlocal
echo Run this file ON YOUR DESKTOP PC from an Administrator terminal.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server\Setup.ps1" -EnableRemoteDesktop -RegisterAutoStart
pause
