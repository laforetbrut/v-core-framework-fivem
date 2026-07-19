# FiveM Vanilla Dev Server

A clean FiveM (GTA V) server on a **vanilla base** — only the official cfx default resources — ready for building custom scripts from scratch.

## Features

- FXServer (cfx.re) recommended build.
- Vanilla cfx default resources only (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames).
- OneSync enabled.
- Custom roleplay core `v-core` — DB-persistent players, API + callbacks (see [ARCHITECTURE.md](ARCHITECTURE.md)).
- `v-ui` "EMBER" design system (modern dark glass, dominant orange) + `v-hud` money HUD + `v-notify` toasts.
- On-demand local MariaDB (never runs 24/7).
- One-click launch via `start.bat`.

### Gameplay modules

- **`v-inventory`** — grid inventory (weight, use/drop/give), functional weapons (ammo, serial, **durability/jamming**, **attachments**), backpacks & armor, a hidden pocket, vehicle trunks & shared/gang stashes, and player **frisk/steal + hands-up**.
- **`v-appearance` / `v-spawn`** — appearance engine (stable clothing identity), multi-character selection, barber / surgeon / tattoos.
- **`v-crafting`** — workbench crafting: 6 stations (workbench, reloading, kitchen, electronics, **recycling/refining**, hidden **drug lab**), server-authoritative.
- **`v-gathering`** — resource nodes (mining, salvage, textile, hidden cannabis grows) that supply raw materials.
- **`v-shops`** — stores with **buy & sell**, vending machines, a scrap dealer, and an illegal **dealer / launderer** (dirty money).
- **`v-target`** — universal interaction eye (hold Left-Alt): entity/zone options **filtered by permission & job**.
- **`v-jobs`** — jobs, grades, on-duty salaries; the source of truth for every job gate.
- **Economy loop** — gather → craft → sell; and the illegal loop grow → process → deal → launder.
- **`v-banking`** (Fleeca ATM), **`v-status`** (hunger/thirst/stress), **`v-admin`** (in-game panel + noclip / player blips).

## Installation

1. **Artifacts** — the FXServer binaries live in `artifacts/` (not tracked by git). If missing, download `server.zip` for `build_server_windows` from the cfx.re artifacts and extract it into `artifacts/`.
2. **License key** — get a free key at [keymaster.fivem.net](https://keymaster.fivem.net/) and set `sv_licenseKey` in `server.cfg`.
3. **Run** — double-click `start.bat` (or run `./start.ps1`).
4. **Connect** — in FiveM press `F8` and type `connect localhost:30120`.

## The core: v-core

`resources/[local]/v-core` is our custom roleplay framework. Other resources use it via exports:

```lua
local Core = exports['v-core']:GetCore()
```

To add a feature resource:

1. Create `resources/[local]/<your-resource>/` with an `fxmanifest.lua`.
2. Grab the core with `exports['v-core']:GetCore()` and build on `Core.GetPlayer`, `Core.Notify`, etc.
3. Add `ensure <your-resource>` in `server.cfg` **after** `v-core`.
4. In the server console: `refresh` then `ensure <your-resource>`.

## Database (on-demand)

A local MariaDB instance is available but **does not run 24/7** — it is not a Windows service and never starts with Windows. Turn it on/off with the scripts:

- **`start-db.bat`** — starts MariaDB in the background on `localhost:3306` (user `root`, password `root`, database `projet_r`).
- **`stop-db.bat`** — stops it cleanly.

Data lives in `database/data/` (gitignored). Only start it when a resource actually needs it.

## Dependencies

- [FiveM / FXServer](https://fivem.net/) · [FiveM Natives](https://docs.fivem.net/natives/) · [Server commands](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) · [MariaDB](https://mariadb.org/) · [screenshot-basic](https://github.com/citizenfx/screenshot-basic) — clothing catalogue thumbnails (admin `/scanclothes`)

## Credits

Author: vyrriox

---

# FiveM Vanilla Dev Server (Version Française)

Serveur FiveM (GTA V) sur une **base vanilla** — uniquement les ressources officielles cfx par défaut — prêt à développer nos propres scripts de zéro.

## Caractéristiques

- Binaires FXServer (cfx.re) build recommandé.
- Uniquement les ressources cfx par défaut (mapmanager, spawnmanager, sessionmanager, basic-gamemode, hardcap, baseevents, rconlog, playernames).
- OneSync activé.
- Core roleplay maison `v-core` — joueurs persistés en BDD, API + callbacks (voir [ARCHITECTURE.md](ARCHITECTURE.md)).
- Design system `v-ui` « EMBER » (verre sombre moderne, orange dominant) + HUD d'argent `v-hud` + toasts `v-notify`.
- MariaDB locale à la demande (ne tourne jamais 24/7).
- Lancement en un clic via `start.bat`.

### Modules de gameplay

- **`v-inventory`** — inventaire grille (poids, utiliser/jeter/donner), armes fonctionnelles (munitions, série, **durabilité/enrayage**, **pièces jointes**), sacs & armure, poche cachée, coffres de véhicule & stashes partagés/gang, et **fouille/vol de joueur + mains en l'air**.
- **`v-appearance` / `v-spawn`** — moteur d'apparence (identité vêtement stable), sélection multi-personnages, coiffeur / chirurgien / tatouages.
- **`v-crafting`** — artisanat à l'établi : 6 stations (établi, rechargement, cuisine, électronique, **recyclage/raffinage**, **labo de drogue** caché), autoritaire serveur.
- **`v-gathering`** — points de ressources (minage, casse, textile, cultures de cannabis cachées) qui fournissent les matières premières.
- **`v-shops`** — boutiques avec **achat & vente**, distributeurs, revendeur de ferraille, et **dealer / blanchisseur** illégal (argent sale).
- **`v-target`** — œil d'interaction universel (maintiens Alt gauche) : options entité/zone **filtrées par permission & métier**.
- **`v-jobs`** — métiers, grades, salaires en service ; la référence pour tous les gates métier.
- **Boucle économique** — récolter → fabriquer → vendre ; et la boucle illégale cultiver → traiter → dealer → blanchir.
- **`v-banking`** (DAB Fleeca), **`v-status`** (faim/soif/stress), **`v-admin`** (panneau in-game + noclip / blips joueurs).

## Installation

1. **Artifacts** — les binaires FXServer sont dans `artifacts/` (non suivi par git). S'ils manquent, télécharge `server.zip` (`build_server_windows`) depuis les artifacts cfx.re et extrais-le dans `artifacts/`.
2. **Clé de licence** — récupère une clé gratuite sur [keymaster.fivem.net](https://keymaster.fivem.net/) et renseigne `sv_licenseKey` dans `server.cfg`.
3. **Lancement** — double-clique sur `start.bat` (ou lance `./start.ps1`).
4. **Connexion** — dans FiveM, appuie sur `F8` et tape `connect localhost:30120`.

## Le core : v-core

`resources/[local]/v-core` est notre framework roleplay maison. Les autres ressources l'utilisent via les exports :

```lua
local Core = exports['v-core']:GetCore()
```

Pour ajouter une ressource :

1. Crée `resources/[local]/<ta-ressource>/` avec un `fxmanifest.lua`.
2. Récupère le core avec `exports['v-core']:GetCore()` et bâtis sur `Core.GetPlayer`, `Core.Notify`, etc.
3. Ajoute `ensure <ta-ressource>` dans `server.cfg` **après** `v-core`.
4. Dans la console serveur : `refresh` puis `ensure <ta-ressource>`.

## Base de données (à la demande)

Une instance MariaDB locale est disponible mais **ne tourne pas 24/7** — ce n'est pas un service Windows et elle ne démarre jamais avec Windows. Tu l'allumes/l'éteins avec les scripts :

- **`start-db.bat`** — démarre MariaDB en arrière-plan sur `localhost:3306` (user `root`, mot de passe `root`, base `projet_r`).
- **`stop-db.bat`** — l'arrête proprement.

Les données sont dans `database/data/` (gitignoré). Ne l'allume que quand une ressource en a réellement besoin.

## Dépendances

- [FiveM / FXServer](https://fivem.net/) · [FiveM Natives](https://docs.fivem.net/natives/) · [Commandes serveur](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) · [MariaDB](https://mariadb.org/) · [screenshot-basic](https://github.com/citizenfx/screenshot-basic) — miniatures du catalogue de vêtements (admin `/scanclothes`)

## Credits

Author: vyrriox
