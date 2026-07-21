@echo off
REM ─────────────────────────────────────────────────────────────
REM  QBCore development server launcher
REM  Author: vyrriox
REM ─────────────────────────────────────────────────────────────
title QBCore Dev Server
cd /d "%~dp0"

REM  Prefer the FiveM Enhanced binary (cfx-server.exe); fall back to Legacy (FXServer.exe).
set "SRV=artifacts\cfx-server.exe"
if not exist "%SRV%" set "SRV=artifacts\FXServer.exe"
if not exist "%SRV%" (
    echo [ERROR] No server binary found in artifacts\ (cfx-server.exe or FXServer.exe). Download the artifacts first.
    pause
    exit /b 1
)

echo Starting server on port 30120 using %SRV% ...
"%SRV%" +exec server.cfg
echo.
echo Server stopped.
pause
