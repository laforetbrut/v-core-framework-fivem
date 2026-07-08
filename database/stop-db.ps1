# Stop the local MariaDB instance for Projet R.
# Author: vyrriox
$bin = 'C:\Program Files\MariaDB 12.3\bin'

if (-not (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue)) {
    Write-Host '[DB] Deja arretee.' -ForegroundColor Yellow
    exit 0
}

Write-Host '[DB] Arret de MariaDB...' -ForegroundColor Cyan
& (Join-Path $bin 'mariadb-admin.exe') -u root -proot --port=3306 shutdown 2>$null

for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue)) {
        Write-Host '[DB] Arretee.' -ForegroundColor Green
        exit 0
    }
}

Write-Host '[DB] Arret propre echoue, forcage du processus...' -ForegroundColor Yellow
Get-Process mariadbd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host '[DB] Arretee (forcee).' -ForegroundColor Green
