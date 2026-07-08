@echo off
REM ─────────────────────────────────────────────────────────────
REM  QBCore development server launcher
REM  Author: vyrriox
REM ─────────────────────────────────────────────────────────────
title QBCore Dev Server
cd /d "%~dp0"

if not exist "artifacts\FXServer.exe" (
    echo [ERROR] artifacts\FXServer.exe not found. Run the artifacts download first.
    pause
    exit /b 1
)

echo Starting QBCore server on port 30120...
"artifacts\FXServer.exe" +exec server.cfg
echo.
echo Server stopped.
pause
