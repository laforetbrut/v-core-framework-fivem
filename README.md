# v-core — a FiveM Enhanced roleplay framework

**v-core** is a complete, self-contained roleplay framework for **FiveM Enhanced** (the GTA V Enhanced
next-gen edition). 22 modules, one shared design system, one database, no external framework
dependency — it is not an ESX or QBCore add-on pack, it *is* the framework.

Built and tested on the Enhanced server binary (`cfx-server.exe`), OneSync, MariaDB via `oxmysql`.

> **Status:** in active development on `main`. See [CHANGELOG.md](CHANGELOG.md) for what shipped and
> [ARCHITECTURE.md](ARCHITECTURE.md) for what each module actually does today and what is left.

## Why it exists

Most FiveM frameworks are a core plus fifty third-party scripts that each bring their own UI, their own
config format and their own idea of who is allowed to do what. v-core is the opposite bet: **one
codebase, one look, one permission model**, and **everything an operator needs to tune is editable
in-game** — never by editing Lua on a live server.

## Features

- **FiveM Enhanced native** — runs on `cfx-server.exe`, `gamename: gta5enhanced`. No `sv_enforceGameBuild`
  (those are Legacy build numbers and lock Enhanced clients out). CEF 140-safe NUI (`https://cfx-nui-…`).
- **`v-core`** — DB-persistent players, server/client callback system, permission tiers, structured audit
  log, multi-character selection. Every module goes through it.
- **`v-ui` "EMBER" design system** — one canonical `theme.css` (dark glass, dominant orange) that all 13
  NUI pages share, so nothing looks bolted on.
- **In-game content editor** — the admin panel creates, edits and deletes **map blips, store locations,
  jobs & grades, items and craft recipes**, backed by `v-world`. Changes apply **live**, no restart.
- **No player chat commands** — the interaction surface is the target eye, keybinds and NUI, by design.
- **Bilingual out of the box** — every player-facing string exists in English and French; players pick
  their language on first join.
- **Server-authoritative by default** — proximity, funds, ownership and permissions are re-derived
  server-side on every action. Client-side gates are treated as UX, not security.
- **On-demand local MariaDB** — never runs as a Windows service, never starts with Windows.

### Gameplay modules

- **`v-inventory`** — grid inventory (weight, use/drop/give), **302-item catalogue**, functional weapons
  (ammo, serial, **durability/jamming**, **attachments**), backpacks & armor, a hidden pocket, vehicle
  trunks & shared/gang stashes, and player **frisk/steal + hands-up**.
- **`v-world`** — the admin-editable world content layer (blips, store locations, jobs, items, recipes).
- **`v-admin`** — in-game panel (F10): dashboard, players, scripts, world, logs, **Editor**, and tools
  (noclip, god, invisible, player blips, spectate, open a player's inventory).
- **`v-appearance` / `v-spawn`** — appearance engine with stable clothing identity, multi-character
  selection, barber / plastic surgeon / tattoo parlour.
- **`v-crafting`** — **105 recipes** across 6 stations (workbench, reloading, kitchen, electronics,
  **recycling/refining**, hidden **drug lab**), server-authoritative, recipes editable in-game.
- **`v-gathering`** — resource nodes (mining, salvage, textile, hidden cannabis grows) feeding the crafting tier.
- **`v-shops`** — stores with **buy & sell**, vending machines, a scrap dealer, and an illegal
  **dealer / launderer** (dirty money). Store positions editable in-game.
- **`v-target`** — universal interaction eye (hold Left-Alt): entity/zone options **filtered by permission & job**.
- **`v-jobs`** — jobs, grades, on-duty salaries; the source of truth for every job gate.
- **`v-vehicles` / `v-garages`** — owned-vehicle persistence (mods, fuel, damage), server-minted
  plates, a key system, a **3D showroom preview**, and 9 garages incl. an impound lot and job motor
  pools — all editable in-game.
- **`v-fuel`** — four fuel types (regular / premium / diesel / electric), load-based consumption,
  18 stations incl. EV charging points, jerry cans; stations and prices editable in-game.
- **`v-cityhall`** — the city hall job desk: apply for any position an admin has left open, or resign.
  Whitelisted jobs (police, EMS, …) never show up here — they are handed out by their own chain of command.
- **`v-banking`** (Fleeca ATM) · **`v-status`** (hunger/thirst/stress/bleed) · **`v-hud`** · **`v-notify`**
  · **`v-clothing`** (16 wearable slots, 10 stores, slots & stores editable in-game) · **`v-loadscreen`**.
- **Economy loops** — legal: gather → craft → sell. Illegal: grow → process → deal → launder.

## Installation

1. **Artifacts** — the server binaries live in `artifacts/` (not tracked by git). Download
   **`cfx-server_win_x64.zip`** (Windows) or **`cfx-server_linux_x64.tar.xz`** (Linux) from the cfx.re
   artifacts and extract it into `artifacts/`. It must contain **`cfx-server.exe`** — `server.zip` /
   `FXServer.exe` is the **Legacy** branch and will reject Enhanced clients with `bad_request`.
2. **License key** — get a free key at [keymaster.fivem.net](https://keymaster.fivem.net/) and set
   `sv_licenseKey` in `server.cfg`.
3. **Database** — run `start-db.bat`, then import `database/schema.sql`.
4. **Run** — `./start.ps1`.
5. **Connect** — in FiveM press `F8` and type `connect localhost:30120`.

## The core: v-core

`resources/[local]/v-core` is the framework. Other resources use it via exports:

```lua
local Core = exports['v-core']:GetCore()
```

To add a feature resource:

1. Create `resources/[local]/<your-resource>/` with an `fxmanifest.lua`.
2. Grab the core with `exports['v-core']:GetCore()` and build on `Core.GetPlayer`, `Core.Notify`, etc.
3. Add `ensure <your-resource>` in `server.cfg` **after** `v-core`.
4. Ship a permission-gated management UI in `v-admin` for anything an operator will want to tune —
   see the `v-world` pattern in [ARCHITECTURE.md](ARCHITECTURE.md) §7.
5. In the server console: `refresh` then `ensure <your-resource>`.

## Database (on-demand)

A local MariaDB instance is available but **does not run 24/7** — it is not a Windows service and never
starts with Windows.

- **`start-db.bat`** — starts MariaDB on `localhost:3306` (user `root`, password `root`, database `projet_r`).
- **`stop-db.bat`** — stops it cleanly.

Schema: `database/schema.sql` (19 tables). Data lives in `database/data/` (gitignored).

## Dependencies

- [FiveM / cfx.re](https://fivem.net/) · [FiveM natives](https://docs.fivem.net/natives/) ·
  [Server manual](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) ·
  [MariaDB](https://mariadb.org/) · [oxmysql](https://github.com/overextended/oxmysql) ·
  [screenshot-basic](https://github.com/citizenfx/screenshot-basic) — clothing catalogue thumbnails

## Credits

Author: vyrriox

---

# v-core — un framework roleplay pour FiveM Enhanced (Version Française)

**v-core** est un framework roleplay complet et autonome pour **FiveM Enhanced** (l'édition next-gen de
GTA V). 22 modules, un seul design system, une seule base de données, aucune dépendance à un framework
externe — ce n'est pas un pack d'add-ons pour ESX ou QBCore, c'est *le* framework.

Développé et testé sur le binaire serveur Enhanced (`cfx-server.exe`), OneSync, MariaDB via `oxmysql`.

> **État :** en développement actif sur `main`. Voir [CHANGELOG.md](CHANGELOG.md) pour ce qui est livré
> et [ARCHITECTURE.md](ARCHITECTURE.md) pour ce que fait réellement chaque module et ce qu'il reste.

## Pourquoi

La plupart des frameworks FiveM, c'est un core plus cinquante scripts tiers qui apportent chacun leur UI,
leur format de config et leur propre idée de qui a le droit de faire quoi. v-core fait le pari inverse :
**une seule base de code, un seul look, un seul modèle de permissions**, et **tout ce qu'un opérateur doit
régler est modifiable en jeu** — jamais en éditant du Lua sur un serveur en production.

## Caractéristiques

- **Natif FiveM Enhanced** — tourne sur `cfx-server.exe`, `gamename: gta5enhanced`. Pas de
  `sv_enforceGameBuild` (ce sont des numéros de build Legacy, qui bloquent les clients Enhanced).
  NUI compatible CEF 140 (`https://cfx-nui-…`).
- **`v-core`** — joueurs persistés en BDD, système de callbacks serveur/client, paliers de permission,
  log d'audit structuré, sélection multi-personnages. Tous les modules passent par lui.
- **Design system `v-ui` « EMBER »** — un `theme.css` canonique (verre sombre, orange dominant) partagé
  par les 13 pages NUI, pour que rien n'ait l'air rapporté.
- **Éditeur de contenu en jeu** — le menu admin crée, modifie et supprime **blips, positions de boutique,
  métiers & grades, items, recettes de craft, boutiques de vêtements et emplacements portables**, adossé à `v-world`. Application **à chaud**, sans restart.
- **Aucune commande chat joueur** — la surface d'interaction, c'est l'œil de ciblage, les touches et la NUI.
- **Bilingue nativement** — chaque texte joueur existe en anglais et en français ; le joueur choisit sa
  langue à la première connexion.
- **Autoritaire serveur par défaut** — proximité, fonds, propriété et permissions sont revérifiés côté
  serveur à chaque action. Les contrôles côté client sont de l'UX, pas de la sécurité.
- **MariaDB locale à la demande** — jamais en service Windows, ne démarre jamais avec Windows.

### Modules de gameplay

- **`v-inventory`** — inventaire grille (poids, utiliser/jeter/donner), **catalogue de 302 items**, armes
  fonctionnelles (munitions, série, **durabilité/enrayage**, **accessoires**), sacs & armure, poche cachée,
  coffres de véhicule & stashes partagés/gang, et **fouille/vol de joueur + mains en l'air**.
- **`v-world`** — la couche de contenu modifiable par les admins (blips, boutiques, métiers, items, recettes).
- **`v-admin`** — panneau en jeu (F10) : tableau de bord, joueurs, scripts, monde, logs, **Éditeur**, et
  outils (noclip, mode dieu, invisible, blips joueurs, observation, ouvrir l'inventaire d'un joueur).
- **`v-appearance` / `v-spawn`** — moteur d'apparence à identité vêtement stable, sélection
  multi-personnages, coiffeur / chirurgien / salon de tatouage.
- **`v-crafting`** — **105 recettes** sur 6 stations (établi, rechargement, cuisine, électronique,
  **recyclage/raffinage**, **labo de drogue** caché), autoritaire serveur, recettes éditables en jeu.
- **`v-gathering`** — points de ressources (minage, casse, textile, cultures de cannabis cachées).
- **`v-shops`** — boutiques avec **achat & vente**, distributeurs, revendeur de ferraille, et
  **dealer / blanchisseur** illégal (argent sale). Positions modifiables en jeu.
- **`v-target`** — œil d'interaction universel (maintiens Alt gauche) : options **filtrées par permission & métier**.
- **`v-jobs`** — métiers, grades, salaires en service ; la référence pour tous les gates métier.
- **`v-vehicles` / `v-garages`** — persistance des véhicules possédés (mods, carburant, dégâts),
  plaques générées par le serveur, système de clés, et 9 garages dont une fourrière et les garages
  de métier, et un **aperçu 3D showroom** — le tout modifiable en jeu.
- **`v-fuel`** — quatre carburants (91 / 98 / gazole / électrique), consommation selon la charge
  moteur, 18 stations dont des points de recharge, jerricans ; stations et prix modifiables en jeu.
- **`v-cityhall`** — le guichet emploi de la mairie : postuler à un poste laissé ouvert par un admin,
  ou démissionner. Les métiers sur whitelist (police, EMS, …) n'y apparaissent jamais.
- **`v-banking`** (DAB Fleeca) · **`v-status`** (faim/soif/stress/saignement) · **`v-hud`** · **`v-notify`**
  · **`v-clothing`** (16 emplacements portables, 10 boutiques, emplacements & boutiques modifiables en jeu) · **`v-loadscreen`**.
- **Boucles économiques** — légale : récolter → fabriquer → vendre. Illégale : cultiver → traiter → dealer → blanchir.

## Installation

1. **Artifacts** — les binaires serveur vont dans `artifacts/` (non suivi par git). Télécharge
   **`cfx-server_win_x64.zip`** (Windows) ou **`cfx-server_linux_x64.tar.xz`** (Linux) depuis les artifacts
   cfx.re et extrais-les dans `artifacts/`. L'archive doit contenir **`cfx-server.exe`** — `server.zip` /
   `FXServer.exe` est la branche **Legacy** et refusera les clients Enhanced avec `bad_request`.
2. **Clé de licence** — récupère une clé gratuite sur [keymaster.fivem.net](https://keymaster.fivem.net/)
   et renseigne `sv_licenseKey` dans `server.cfg`.
3. **Base de données** — lance `start-db.bat`, puis importe `database/schema.sql`.
4. **Lancement** — `./start.ps1`.
5. **Connexion** — dans FiveM, appuie sur `F8` et tape `connect localhost:30120`.

## Le core : v-core

`resources/[local]/v-core` est le framework. Les autres ressources l'utilisent via les exports :

```lua
local Core = exports['v-core']:GetCore()
```

Pour ajouter une ressource :

1. Crée `resources/[local]/<ta-ressource>/` avec un `fxmanifest.lua`.
2. Récupère le core avec `exports['v-core']:GetCore()` et bâtis sur `Core.GetPlayer`, `Core.Notify`, etc.
3. Ajoute `ensure <ta-ressource>` dans `server.cfg` **après** `v-core`.
4. Livre une UI de gestion protégée par permission dans `v-admin` pour tout ce qu'un opérateur voudra
   régler — voir le pattern `v-world` dans [ARCHITECTURE.md](ARCHITECTURE.md) §7.
5. Dans la console serveur : `refresh` puis `ensure <ta-ressource>`.

## Base de données (à la demande)

Une instance MariaDB locale est disponible mais **ne tourne pas 24/7** — ce n'est pas un service Windows
et elle ne démarre jamais avec Windows.

- **`start-db.bat`** — démarre MariaDB sur `localhost:3306` (user `root`, mot de passe `root`, base `projet_r`).
- **`stop-db.bat`** — l'arrête proprement.

Schéma : `database/schema.sql` (19 tables). Les données sont dans `database/data/` (gitignoré).

## Dépendances

- [FiveM / cfx.re](https://fivem.net/) · [Natives FiveM](https://docs.fivem.net/natives/) ·
  [Manuel serveur](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) ·
  [MariaDB](https://mariadb.org/) · [oxmysql](https://github.com/overextended/oxmysql) ·
  [screenshot-basic](https://github.com/citizenfx/screenshot-basic) — miniatures du catalogue de vêtements

## Credits

Author: vyrriox
