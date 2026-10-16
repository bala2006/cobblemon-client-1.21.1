@echo off
setlocal
title Cobblemon client installer
cd /d "%~dp0"

where powershell >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Windows PowerShell was not found on PATH.
  echo         This script needs the PowerShell that ships with Windows.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo [ERROR] installer exited with code %RC%
pause
exit /b %RC%
