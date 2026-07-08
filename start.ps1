# ─────────────────────────────────────────────────────────────
#  QBCore development server launcher (PowerShell)
#  Author: vyrriox
# ─────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$fx = Join-Path $PSScriptRoot 'artifacts\FXServer.exe'
if (-not (Test-Path $fx)) {
    Write-Host '[ERROR] artifacts\FXServer.exe not found. Download the artifacts first.' -ForegroundColor Red
    exit 1
}

Write-Host 'Starting QBCore server on port 30120...' -ForegroundColor Green
& $fx +exec server.cfg
