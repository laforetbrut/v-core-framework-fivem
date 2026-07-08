# Changelog

All notable changes to FiveM Vanilla Dev Server are documented here.

---

## [1.0.0] - 2026-07-08

### Added (English first)

- **Vanilla server base** — FXServer artifacts plus the official cfx default resources (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames) under `resources/[cfx-default]`.
- **Clean configuration** — `server.cfg` with endpoints on 30120, OneSync enabled, system chat, and a `[local]` folder reserved for our own scripts. No framework, no database dependency.
- **v-core framework** — `resources/[local]/v-core`, our custom roleplay core: shared config, `exports['v-core']:GetCore()` on client and server, in-memory player model with money accounts, player load/drop lifecycle, and a `/vmoney` demo command. Database persistence plugs in later.
- **Launchers** — `start.bat` and `start.ps1` to boot the server.
- **On-demand database** — local MariaDB (not a Windows service, never 24/7) with `start-db.bat` / `stop-db.bat` toggles; data in `database/data/` (gitignored), database `projet_r` ready.
- **Project docs** — `README.md`, `RULES.md`, `.gitignore` tailored to a vanilla FiveM workflow.

### Ajouts (French mirror)

- **Base serveur vanilla** — binaires FXServer et ressources cfx officielles par défaut (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames) sous `resources/[cfx-default]`.
- **Configuration propre** — `server.cfg` avec endpoints sur 30120, OneSync activé, chat système, et un dossier `[local]` réservé à nos propres scripts. Aucun framework, aucune dépendance base de données.
- **Framework v-core** — `resources/[local]/v-core`, notre core roleplay maison : config partagée, `exports['v-core']:GetCore()` côté client et serveur, modèle joueur en mémoire avec comptes d'argent, cycle de vie chargement/déconnexion, et une commande de démo `/vmoney`. La persistance en base se branchera plus tard.
- **Lanceurs** — `start.bat` et `start.ps1` pour démarrer le serveur.
- **Base de données à la demande** — MariaDB locale (pas un service Windows, jamais 24/7) avec les scripts `start-db.bat` / `stop-db.bat` ; données dans `database/data/` (gitignoré), base `projet_r` prête.
- **Documentation projet** — `README.md`, `RULES.md`, `.gitignore` adaptés à un workflow FiveM vanilla.

---
