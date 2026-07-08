# FiveM Vanilla Dev Server

A clean FiveM (GTA V) server on a **vanilla base** — only the official cfx default resources — ready for building custom scripts from scratch.

## Features

- FXServer (cfx.re) recommended build.
- Vanilla cfx default resources only (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames).
- OneSync enabled.
- No framework, no database lock-in — build your own systems.
- Starter resource `resources/[local]/hello-world` to copy from.
- One-click launch via `start.bat`.

## Installation

1. **Artifacts** — the FXServer binaries live in `artifacts/` (not tracked by git). If missing, download `server.zip` for `build_server_windows` from the cfx.re artifacts and extract it into `artifacts/`.
2. **License key** — get a free key at [keymaster.fivem.net](https://keymaster.fivem.net/) and set `sv_licenseKey` in `server.cfg`.
3. **Run** — double-click `start.bat` (or run `./start.ps1`).
4. **Connect** — in FiveM press `F8` and type `connect localhost:30120`.

## Developing a script

1. Copy `resources/[local]/hello-world` to `resources/[local]/<your-resource>`.
2. Edit `fxmanifest.lua`, `client.lua`, `server.lua`.
3. Add `ensure <your-resource>` in `server.cfg`.
4. In the server console: `refresh` then `ensure <your-resource>` (or `restart <your-resource>`).

## Dependencies

- [FiveM / FXServer](https://fivem.net/) · [FiveM Natives](https://docs.fivem.net/natives/) · [Server commands](https://docs.fivem.net/docs/server-manual/setting-up-a-server/)

## Credits

Author: vyrriox

---

# FiveM Vanilla Dev Server (Version Française)

Serveur FiveM (GTA V) sur une **base vanilla** — uniquement les ressources officielles cfx par défaut — prêt à développer nos propres scripts de zéro.

## Caractéristiques

- Binaires FXServer (cfx.re) build recommandé.
- Uniquement les ressources cfx par défaut (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames).
- OneSync activé.
- Aucun framework, aucune base imposée — on construit nos propres systèmes.
- Ressource de démarrage `resources/[local]/hello-world` à copier.
- Lancement en un clic via `start.bat`.

## Installation

1. **Artifacts** — les binaires FXServer sont dans `artifacts/` (non suivi par git). S'ils manquent, télécharge `server.zip` (`build_server_windows`) depuis les artifacts cfx.re et extrais-le dans `artifacts/`.
2. **Clé de licence** — récupère une clé gratuite sur [keymaster.fivem.net](https://keymaster.fivem.net/) et renseigne `sv_licenseKey` dans `server.cfg`.
3. **Lancement** — double-clique sur `start.bat` (ou lance `./start.ps1`).
4. **Connexion** — dans FiveM, appuie sur `F8` et tape `connect localhost:30120`.

## Développer un script

1. Copie `resources/[local]/hello-world` vers `resources/[local]/<ta-ressource>`.
2. Modifie `fxmanifest.lua`, `client.lua`, `server.lua`.
3. Ajoute `ensure <ta-ressource>` dans `server.cfg`.
4. Dans la console serveur : `refresh` puis `ensure <ta-ressource>` (ou `restart <ta-ressource>`).

## Dépendances

- [FiveM / FXServer](https://fivem.net/) · [FiveM Natives](https://docs.fivem.net/natives/) · [Commandes serveur](https://docs.fivem.net/docs/server-manual/setting-up-a-server/)

## Credits

Author: vyrriox
