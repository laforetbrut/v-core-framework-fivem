# Start the local MariaDB instance for Projet R (on-demand, not a service).
# Author: vyrriox
$ErrorActionPreference = 'Stop'
$bin  = 'C:\Program Files\MariaDB 12.3\bin'
$data = Join-Path $PSScriptRoot 'data'

if (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '[DB] Deja en ligne sur localhost:3306.' -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path (Join-Path $data 'mysql'))) {
    Write-Host "[DB] ERREUR: dossier de donnees introuvable ($data)." -ForegroundColor Red
    exit 1
}

Write-Host '[DB] Demarrage de MariaDB (Projet R)...' -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $bin 'mariadbd.exe') `
    -ArgumentList "--datadir=`"$data`"", '--port=3306' -WindowStyle Hidden

for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host '[DB] En ligne sur localhost:3306  (user: root  /  pass: root).' -ForegroundColor Green
        exit 0
    }
}
Write-Host '[DB] ERREUR: la base ne repond pas apres 10s.' -ForegroundColor Red
exit 1
