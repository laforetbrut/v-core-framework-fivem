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
- **i18n (fr/en)** — locale engine in v-core (`@v-core/locale/shared.lua`, `L()`/`LP()`), per-account language in DB + statebag; modules ship `fr` + `en`, NUI text driven by locale.
- **v-spawn module** — first-run flow: language selection → character creation (name, dob, sex) → full appearance editor (heritage, face, hair, eyebrows/beard, eye color, clothing) with live preview + orbit camera; persists identity + appearance then spawns.
- **v-notify** — themed NUI toasts (success / error / warning / info) with icons, progress bar and slide animations; `Core.Notify` now routes through it (native fallback).
- **v-banking (Fleeca)** — ATM interaction (no command), deposit / withdraw / transfer with recipient validation (online + offline), transaction history, Fleeca-green themed UI; new `bank_transactions` table.
- **v-loadscreen** — custom Projet R loading screen shown while players connect: dark/orange branded design, real progress bar wired to FiveM load events, and rotating bilingual tips.
- **HUD customization+** — players can now drag to reposition each element (vitals, money, compass), pick any custom accent colour, toggle a compass, and control the minimap (show/hide, vehicle-only); all persisted per player.
- **Fixes & polish** — fixed a v-hud NUI-focus softlock (`RegisterNUICallback` casing), a character-creation race condition, and a logs param-marshalling bug; v-hud is now fully fr/en localized; added `dependency` declarations to modules.
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
- **i18n (fr/en)** — moteur de langue dans v-core (`@v-core/locale/shared.lua`, `L()`/`LP()`), langue par compte en base + statebag ; chaque module fournit `fr` + `en`, textes NUI pilotés par la locale.
- **Module v-spawn** — flux de première connexion : sélection de langue → création de personnage (nom, date de naissance, sexe) → éditeur d'apparence complet (hérédité, visage, cheveux, sourcils/barbe, yeux, vêtements) avec aperçu live + caméra orbitale ; persiste identité + apparence puis fait apparaître.
- **v-notify** — toasts NUI stylés (succès / erreur / alerte / info) avec icônes, barre de progression et animations ; `Core.Notify` passe désormais par lui (fallback natif).
- **v-banking (Fleeca)** — interaction ATM (sans commande), dépôt / retrait / virement avec validation du destinataire (en ligne + hors ligne), historique des transactions, UI thème Fleeca-vert ; nouvelle table `bank_transactions`.
- **v-loadscreen** — écran de chargement custom affiché à la connexion : design sombre/orangé « Projet R », barre de progression réelle branchée sur les events de chargement FiveM, et astuces bilingues défilantes.
- **Personnalisation HUD+** — les joueurs peuvent désormais déplacer chaque élément (vitals, argent, boussole), choisir une couleur d'accent personnalisée, activer une boussole, et contrôler la minimap (afficher/masquer, véhicule uniquement) ; le tout persisté par joueur.
- **Correctifs & finitions** — softlock souris du HUD corrigé (casse de `RegisterNUICallback`), race condition à la création de personnage, bug de marshalling des params de logs ; v-hud entièrement traduit fr/en ; déclarations `dependency` ajoutées aux modules.
- **Guide d'architecture** — `ARCHITECTURE.md` documente l'API de v-core et la roadmap des modules.
- **Lanceurs** — `start.bat` et `start.ps1` pour démarrer le serveur.
- **Base de données à la demande** — MariaDB locale (pas un service Windows, jamais 24/7) avec les scripts `start-db.bat` / `stop-db.bat` ; données dans `database/data/` (gitignoré), base `projet_r` prête.
- **Documentation projet** — `README.md`, `RULES.md`, `.gitignore` adaptés à un workflow FiveM vanilla.

---
