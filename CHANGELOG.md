# Changelog

All notable changes to FiveM Vanilla Dev Server are documented here.

---

## [1.0.0] - 2026-07-08

### Added (English first)

- **Vanilla server base** — FXServer artifacts plus the official cfx default resources (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames) under `resources/[cfx-default]`.
- **Clean configuration** — `server.cfg` with endpoints on 30120, OneSync enabled, system chat, and a `[local]` folder reserved for our own scripts. No framework, no database dependency.
- **v-core framework** — `resources/[local]/v-core`: `exports['v-core']:GetCore()` API on client and server, a client↔server callback system, **database-persistent player object** (money/job/gang/metadata) loaded from and saved to MariaDB via oxmysql, autosave + save-on-drop lifecycle, and namespaced events (`onPlayerLoaded`, `onMoneyChange`, …) so modules stay decoupled.
- **Database layer** — `oxmysql` wired to `projet_r`; schema in `database/schema.sql` (users, characters, items, vehicles, jobs, gangs, shops, server_config) with seed data.
- **v-ui design system** — `resources/[local]/v-ui/theme.css`: dark/warm-orange, condensed-industrial visual identity (tokens + components) shared across all NUIs.
- **Permissions & logs (v-core)** — permission tiers (`user < mod < admin < superadmin`) for in-game management, and a `Core.Log` system writing to console + the `logs` table.
- **v-status module** — hunger, thirst, stress, bleeding (injury from damage) and illness, with time drain, health effects, screen feedback and metadata persistence; exports for food/drink/treatment items.
- **v-hud (customizable)** — vitals rings (health, armor, hunger, thirst, stress, stamina, oxygen) + money, plus a player settings panel (toggle elements, accent, opacity, scale, dynamic hide) persisted via KVP. No player command — opened by keybind.
- **Architecture guide** — `ARCHITECTURE.md` documents the v-core API and the module roadmap.
- **Launchers** — `start.bat` and `start.ps1` to boot the server.
- **On-demand database** — local MariaDB (not a Windows service, never 24/7) with `start-db.bat` / `stop-db.bat` toggles; data in `database/data/` (gitignored), database `projet_r` ready.
- **Project docs** — `README.md`, `RULES.md`, `.gitignore` tailored to a vanilla FiveM workflow.

### Ajouts (French mirror)

- **Base serveur vanilla** — binaires FXServer et ressources cfx officielles par défaut (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames) sous `resources/[cfx-default]`.
- **Configuration propre** — `server.cfg` avec endpoints sur 30120, OneSync activé, chat système, et un dossier `[local]` réservé à nos propres scripts. Aucun framework, aucune dépendance base de données.
- **Framework v-core** — `resources/[local]/v-core` : API `exports['v-core']:GetCore()` côté client et serveur, système de callbacks client↔serveur, **objet joueur persistant en base** (argent/job/gang/metadata) chargé et sauvegardé sur MariaDB via oxmysql, cycle autosave + sauvegarde à la déconnexion, et events nommés (`onPlayerLoaded`, `onMoneyChange`, …) pour garder les modules découplés.
- **Couche base de données** — `oxmysql` relié à `projet_r` ; schéma dans `database/schema.sql` (users, characters, items, vehicles, jobs, gangs, shops, server_config) avec données de départ.
- **Design system v-ui** — `resources/[local]/v-ui/theme.css` : identité visuelle sombre/orangée, condensée-industrielle (tokens + composants) partagée par toutes les interfaces NUI.
- **Permissions & logs (v-core)** — niveaux de permission (`user < mod < admin < superadmin`) pour la gestion in-game, et un système `Core.Log` écrivant dans la console + la table `logs`.
- **Module v-status** — faim, soif, stress, saignements (blessure sur dégâts) et maladie, avec drain temporel, effets sur la vie, retours écran et persistance en metadata ; exports pour les items nourriture/boisson/soin.
- **v-hud (personnalisable)** — jauges de vitals (vie, armure, faim, soif, stress, stamina, oxygène) + argent, avec un panneau de réglages joueur (activer les éléments, accent, opacité, taille, masquage dynamique) persisté via KVP. Aucune commande joueur — ouvert par raccourci clavier.
- **Guide d'architecture** — `ARCHITECTURE.md` documente l'API de v-core et la roadmap des modules.
- **Lanceurs** — `start.bat` et `start.ps1` pour démarrer le serveur.
- **Base de données à la demande** — MariaDB locale (pas un service Windows, jamais 24/7) avec les scripts `start-db.bat` / `stop-db.bat` ; données dans `database/data/` (gitignoré), base `projet_r` prête.
- **Documentation projet** — `README.md`, `RULES.md`, `.gitignore` adaptés à un workflow FiveM vanilla.

---
