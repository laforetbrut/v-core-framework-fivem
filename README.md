# QBCore Dev Server

A local FiveM (GTA V) development server running the **QBCore** framework, set up for building and testing custom scripts.

## Features

- FXServer (cfx.re) recommended build, game build 3095 (The Chop Shop).
- Full QBCore framework with jobs, systems, maps, HUD, phone, inventory and more.
- `oxmysql` + MariaDB database layer.
- `pma-voice` proximity voice.
- Ready-to-copy example resource in `resources/[local]/dev-starter`.
- One-click launch via `start.bat`.

## Installation

1. **Artifacts** — the FXServer binaries live in `artifacts/` (not tracked by git). If missing, download `server.zip` for `build_server_windows` from the cfx.re artifacts and extract it into `artifacts/`.
2. **Database** — install MariaDB, keep the service on `localhost:3306`, create a database named `qbcore` and import the QBCore SQL.
3. **License key** — get a free key at [keymaster.fivem.net](https://keymaster.fivem.net/) and set `sv_licenseKey` in `server.cfg`.
4. **Database string** — confirm `set mysql_connection_string` in `server.cfg` matches your MariaDB credentials.
5. **Run** — double-click `start.bat` (or run `./start.ps1`).
6. **Connect** — in FiveM press `F8` and type `connect localhost:30120`.

## Dependencies

- [FiveM / FXServer](https://fivem.net/) · [QBCore](https://docs.qbcore.org) · [oxmysql](https://github.com/overextended/oxmysql) · [MariaDB](https://mariadb.org/)

## Credits

Author: vyrriox

---

# QBCore Dev Server (Version Française)

Serveur FiveM (GTA V) local basé sur le framework **QBCore**, configuré pour développer et tester des scripts personnalisés.

## Caractéristiques

- Binaires FXServer (cfx.re) build recommandé, game build 3095 (The Chop Shop).
- Framework QBCore complet : métiers, systèmes, maps, HUD, téléphone, inventaire, etc.
- Couche base de données `oxmysql` + MariaDB.
- Voix de proximité `pma-voice`.
- Ressource d'exemple prête à copier : `resources/[local]/dev-starter`.
- Lancement en un clic via `start.bat`.

## Installation

1. **Artifacts** — les binaires FXServer sont dans `artifacts/` (non suivi par git). S'ils manquent, télécharge `server.zip` (`build_server_windows`) depuis les artifacts cfx.re et extrais-le dans `artifacts/`.
2. **Base de données** — installe MariaDB, garde le service sur `localhost:3306`, crée une base `qbcore` et importe le SQL QBCore.
3. **Clé de licence** — récupère une clé gratuite sur [keymaster.fivem.net](https://keymaster.fivem.net/) et renseigne `sv_licenseKey` dans `server.cfg`.
4. **Chaîne de connexion** — vérifie que `set mysql_connection_string` dans `server.cfg` correspond à tes identifiants MariaDB.
5. **Lancement** — double-clique sur `start.bat` (ou lance `./start.ps1`).
6. **Connexion** — dans FiveM, appuie sur `F8` et tape `connect localhost:30120`.

## Dépendances

- [FiveM / FXServer](https://fivem.net/) · [QBCore](https://docs.qbcore.org) · [oxmysql](https://github.com/overextended/oxmysql) · [MariaDB](https://mariadb.org/)

## Credits

Author: vyrriox
