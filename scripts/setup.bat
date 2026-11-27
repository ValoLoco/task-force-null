@echo off
REM Task Force Null Windows setup launcher (cmd.exe / double-click).
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1" %*