# ─────────────────────────────────────────────────────────────
#  Projet R — FiveM Enhanced server launcher (PowerShell)
#  Start the database first (start-db.bat), then run this.
#  Author: vyrriox
# ─────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# Prefer the FiveM Enhanced binary (cfx-server.exe); fall back to Legacy (FXServer.exe).
$fx = Join-Path $PSScriptRoot 'artifacts\cfx-server.exe'
if (-not (Test-Path $fx)) { $fx = Join-Path $PSScriptRoot 'artifacts\FXServer.exe' }
if (-not (Test-Path $fx)) {
    Write-Host '[ERROR] No server binary in artifacts\ (cfx-server.exe or FXServer.exe). Download the artifacts first.' -ForegroundColor Red
    exit 1
}

Write-Host "Starting server on port 30120 using $fx ..." -ForegroundColor Green
& $fx +exec server.cfg
