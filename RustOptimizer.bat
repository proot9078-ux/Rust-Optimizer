@echo off
setlocal EnableExtensions
title PURPLE RUSH - RUST + FORTNITE PERFORMANCE ENGINE
cd /d "%~dp0"
rem ============================================================
rem  PURPLE RUSH - RUST PERFORMANCE ENGINE
rem  Open source: MIT. Source: src\parts\*.ps1
rem  Right-click -> Run as administrator (recommended).
rem  First launch creates a desktop shortcut with the app icon.
rem ============================================================

if /i "%~1"=="elevated" goto run
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)

:run
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\RustOptimizer.ps1"
exit /b