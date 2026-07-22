# v-core - a roleplay framework built for FiveM Enhanced

[![License: MIT](https://img.shields.io/badge/License-MIT-e8a33d.svg)](LICENSE)
[![FiveM Enhanced](https://img.shields.io/badge/FiveM-Enhanced-e8a33d.svg)](https://forum.cfx.re/)
[![Lua 5.4](https://img.shields.io/badge/Lua-5.4-000080.svg)](https://www.lua.org/)
[![Modules](https://img.shields.io/badge/modules-35-e8a33d.svg)](ARCHITECTURE.md)
[![Docs EN + FR](https://img.shields.io/badge/docs-EN%20%2B%20FR-e8a33d.svg)](DEVELOPERS.md)

**v-core** is a complete, self-contained roleplay framework for **FiveM Enhanced** - the GTA V
Enhanced next-gen edition. 35 modules, one shared design system, one database, no external
framework dependency. It is not an ESX or QBCore add-on pack, it *is* the framework.

**Why a new framework rather than a port?** ESX and QBCore were written for the **Legacy** branch,
and the differences are not cosmetic: the Enhanced binary is `cfx-server.exe` and rejects Legacy
stream assets outright; `sv_enforceGameBuild` takes Legacy build numbers that lock Enhanced clients
out entirely; and CEF 140 dropped `nui://` as a secure context and renders `backdrop-filter` as an
opaque black box, which breaks most existing NUI. Every one of those is designed around here rather
than patched over.

Built and tested on `cfx-server.exe`, OneSync, MariaDB via `oxmysql`.

```bash
git clone https://github.com/laforetbrut/v-core-framework-fivem.git
```

Then follow [Installation](#installation) - five steps, no build toolchain.

> **Status:** in active development on `main`.
>
> | Document | What it is |
> |---|---|
> | **[API.md](API.md)** | Every export, callback and event - the reference |
> | **[DEVELOPERS.md](DEVELOPERS.md)** | Write a script for v-core: the `V` helper, conventions, gotchas |
> | **[ARCHITECTURE.md](ARCHITECTURE.md)** | What each module does today, and the roadmap |
> | **[CHANGELOG.md](CHANGELOG.md)** | What shipped |
> | **[CONTRIBUTING.md](CONTRIBUTING.md)** | How to contribute, and what gets sent back |

## Why it exists

Most FiveM frameworks are a core plus fifty third-party scripts that each bring their own UI, their own
config format and their own idea of who is allowed to do what. v-core is the opposite bet: **one
codebase, one look, one permission model**, and **everything an operator needs to tune is editable
in-game** - never by editing Lua on a live server.

## Features

- **FiveM Enhanced native** - runs on `cfx-server.exe`, `gamename: gta5enhanced`. No `sv_enforceGameBuild`
  (those are Legacy build numbers and lock Enhanced clients out). CEF 140-safe NUI (`https://cfx-nui-…`).
- **`v-core`** - DB-persistent players, server/client callback system, permission tiers, structured audit
  log, multi-character selection. Every module goes through it.
- **`v-ui` design system, fully themeable** - one canonical stylesheet every NUI page shares, driven by
  `v-ui/config.lua`: **6 colour presets**, an accent override the whole highlight family is derived
  from, corner roundness, density, animation speed (0 disables motion), panel opacity and font scale.
  Changing any of it in **Admin -> Settings -> Interface** restyles **every module at once** - no
  module hardcodes a colour.
- **Configurable loading screen** - `v-loadscreen/html/config.js`: **7 layouts** (centre, left, right,
  split, bottom, top, card), the same 6 palettes, video/image/gradient/solid backgrounds, every effect
  toggleable, and all copy + tips in one place.
- **In-game content editor** - **21 domains** the admin panel creates, edits and deletes without a
  restart: map blips, store locations, shops, jobs & grades, gangs & ranks, items, craft recipes,
  clothing stores & wearable slots, garages, rental points, fuel stations, mechanic shops, dealerships,
  the vehicle catalogue, licence types, **gang territories**, **the penal code**, **substances**,
  **radio channels**, **faction treasuries** and **per-module themes**. All backed by `v-world`,
  all applied **live**.
- **Module registry & settings** - every module declares its tunables to `v-core`; the admin panel's
  **Settings** tab renders whatever it is handed, so it never needs changing. A third-party script
  adds `v_module 'yes'` to its manifest and appears there too - see [DEVELOPERS.md](DEVELOPERS.md).
- **NPC police off by default** - no ambient cruisers, no wanted stars, no dispatch helicopter, because
  none of it is played by anyone. Every piece is its own switch in the admin panel.
- **No player chat commands** - the interaction surface is the target eye, keybinds and NUI, by design.
- **Bilingual out of the box** - every player-facing string exists in English and French; players pick
  their language on first join.
- **Server-authoritative by default** - proximity, funds, ownership and permissions are re-derived
  server-side on every action. Client-side gates are treated as UX, not security.
- **On-demand local MariaDB** - never runs as a Windows service, never starts with Windows.

### Gameplay modules

- **`v-inventory`** - grid inventory (weight, use/drop/give), **302-item catalogue**, functional weapons
  (ammo, serial, **durability/jamming**, **attachments**), backpacks & armor, a hidden pocket, vehicle
  trunks & shared/gang stashes, and player **frisk/steal + hands-up**.
- **`v-world`** - the admin-editable world content layer (blips, store locations, jobs, items, recipes).
- **`v-admin`** - in-game panel (F10): dashboard, players, scripts, world, logs, **Editor**, and tools
  (noclip, god, invisible, player blips, spectate, open a player's inventory).
- **`v-appearance` / `v-spawn`** - appearance engine with stable clothing identity, multi-character
  selection, barber / plastic surgeon / tattoo parlour.
- **`v-crafting`** - **105 recipes** across 6 stations (workbench, reloading, kitchen, electronics,
  **recycling/refining**, hidden **drug lab**), server-authoritative, recipes editable in-game.
- **`v-gathering`** - resource nodes (mining, salvage, textile, hidden cannabis grows) feeding the crafting tier.
- **`v-shops`** - stores with **buy & sell**, vending machines, a scrap dealer, and an illegal
  **dealer / launderer** (dirty money). Store positions editable in-game.
- **`v-target`** - universal interaction eye (hold Left-Alt): entity/zone options **filtered by permission & job**.
- **`v-jobs`** - jobs, grades, on-duty salaries; the source of truth for every job gate.
- **`v-vehicles` / `v-garages`** - owned-vehicle persistence (mods, fuel, damage), server-minted
  plates, a key system, a **3D showroom preview**, and 9 garages incl. an impound lot and job motor
  pools - all editable in-game.
- **`v-fuel`** - four fuel types (regular / premium / diesel / electric), load-based consumption,
  18 stations incl. EV charging points with connector levels and a charge curve, jerry cans;
  stations and prices editable in-game.
- **`v-mechanic`** - 20-part wear model (12 for an EV) driven by distance, abuse and crashes, a real
  odometer, 27 craftable parts, roadside repair kits and job-locked shops - all editable in-game.
- **`v-vehicleshop`** - 6 dealerships, a 56-vehicle catalogue with a 3D showroom preview, test drives,
  licence-gated purchases and sell-back; dealers and catalogue editable in-game.
- **`v-licenses`** - 12 licences & permits (ID, driving, HGV, boat, pilot, weapon…) with suspension,
  revocation, expiry and demerit points; the single source of truth for character capabilities.
- **`v-cityhall`** - the city hall job desk: apply for any position an admin has left open, or resign.
  Whitelisted jobs (police, EMS, …) never show up here - they are handed out by their own chain of command.
- **`v-rentals`** - short-term hire at four counters: a deposit and a fee up front, a temporary
  `RENT###` plate and a timer. Return it in time and the deposit comes back. A rental never creates an
  ownership row, which is the single rule that separates a hire from a free car.
- **`v-factions`** - one engine for legal factions and illegal ones: they differ by which table holds
  their definition, `jobs` or `gangs`, and by nothing else. Membership, ranks, and a **treasury that is a
  real account with its own audit trail** rather than a number in a config. Salaries can be paid out of it.
- **`v-bossmenu`** (F6) - the panel a faction leader needs: members, ranks, hiring, dismissal, treasury
  and payroll. **Gated on rank, not on admin permission** - staff are not bosses.
- **`v-gangs`** - territory with capture and influence. Influence belongs to whoever holds the turf and a
  rival *wears it down* rather than taking it, so a contested turf is a fight instead of a race. Unheld
  influence decays: a turf has to be held, not taken once.
- **`v-police`** - cuffs, escort, search, seizure, charges, fines, jail and an MDT (record, warrants,
  licences, vehicles). **Police is a job, not a permission.** The penal code is data - 21 charges with
  fine, jail time and licence points, all editable in-game.
- **`v-banking`** (Fleeca ATM) · **`v-status`** (hunger/thirst/stress/bleed) · **`v-hud`** (vitals, money,
  compass, square minimap and a vehicle cluster with fuel, engine and odometer) · **`v-notify`**
  · **`v-clothing`** (16 wearable slots, 10 stores, slots & stores editable in-game) · **`v-loadscreen`**.
- **`v-radio`** (F3) - the handheld: monitor several channels at once, talk on one, presets on a
  keypad. It decides no permission - it asks `v-voice`, which asks the job and gang gates.
- **`v-3dsound`** - a positional sound primitive other modules call: a name, a place and a range
  go on the wire, never audio, and only listeners in range are told.
- **`v-anticheat`** - server-side checks on movement, health, explosions, client entity creation,
  money and weapon damage. **Logs by default rather than kicking**, because an anticheat that
  kicks legitimate players is worse than none.
- **`v-voice`** - proximity voice in three steps, radio channels gated on job or gang rank, and a
  separate channel for phone calls. Bleeding narrows your range, cuffs kill the radio, and leaving
  a job leaves its channel.
- **`v-drugs`** - plantations a player places and can lose, and street dealing that pushes back:
  demand decays per district as you sell into it, and heat drives both refusals and the chance of
  a bust. Sales pay dirty money, which has to go through the launderer.
- **Economy loops** - legal: gather → craft → sell. Illegal: grow → process → deal → launder.

## Installation

1. **Artifacts** - the server binaries live in `artifacts/` (not tracked by git). Download
   **`cfx-server_win_x64.zip`** (Windows) or **`cfx-server_linux_x64.tar.xz`** (Linux) from the cfx.re
   artifacts and extract it into `artifacts/`. It must contain **`cfx-server.exe`** - `server.zip` /
   `FXServer.exe` is the **Legacy** branch and will reject Enhanced clients with `bad_request`.
2. **License key** - get a free key at [keymaster.fivem.net](https://keymaster.fivem.net/) and set
   `sv_licenseKey` in `server.cfg`.
3. **Database** - point `mysql_connection_string` in `server.cfg` at your MySQL/MariaDB, then import `database/schema.sql`.
4. **Run** - `./start.ps1`.
5. **Connect** - in FiveM press `F8` and type `connect localhost:30120`.

## The core: v-core

`resources/[local]/v-core` is the framework. Other resources use it via exports:

```lua
local Core = exports['v-core']:GetCore()
```

To add a feature resource:

1. Create `resources/[local]/<your-resource>/` with an `fxmanifest.lua`.
2. Grab the core with `exports['v-core']:GetCore()` and build on `Core.GetPlayer`, `Core.Notify`, etc.
3. Add `ensure <your-resource>` in `server.cfg` **after** `v-core`.
4. Ship a permission-gated management UI in `v-admin` for anything an operator will want to tune -
   see the `v-world` pattern in [ARCHITECTURE.md](ARCHITECTURE.md) §7.
5. In the server console: `refresh` then `ensure <your-resource>`.

## Database (on-demand)

Any MySQL or MariaDB instance works - the framework only talks to it through `oxmysql`, so how you run
it is your call (a service, Docker, or an on-demand local install).

Set the connection in `server.cfg`:

```cfg
set mysql_connection_string "mysql://user:password@localhost:3306/your_database?charset=utf8mb4"
```

Then import **`database/schema.sql`** (24 tables). Migrations run automatically at boot.

## Dependencies

- [FiveM / cfx.re](https://fivem.net/) · [FiveM natives](https://docs.fivem.net/natives/) ·
  [Server manual](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) ·
  [MariaDB](https://mariadb.org/) · [oxmysql](https://github.com/overextended/oxmysql) ·
  [screenshot-basic](https://github.com/citizenfx/screenshot-basic) - clothing catalogue thumbnails

## Credits

Author: vyrriox

---

# v-core - un framework roleplay pour FiveM Enhanced (Version Française)

**v-core** est un framework roleplay complet et autonome pour **FiveM Enhanced** (l'édition next-gen de
GTA V). 35 modules, un seul design system, une seule base de données, aucune dépendance à un framework
externe - ce n'est pas un pack d'add-ons pour ESX ou QBCore, c'est *le* framework.

Développé et testé sur le binaire serveur Enhanced (`cfx-server.exe`), OneSync, MariaDB via `oxmysql`.

> **État :** en développement actif sur `main`.
>
> | Document | Contenu |
> |---|---|
> | **[API.md](API.md)** | Tous les exports, callbacks et événements - la référence |
> | **[DEVELOPERS.md](DEVELOPERS.md)** | Écrire un script pour v-core : le helper `V`, conventions, pièges |
> | **[ARCHITECTURE.md](ARCHITECTURE.md)** | Ce que fait chaque module, et la roadmap |
> | **[CHANGELOG.md](CHANGELOG.md)** | Ce qui est livré |
> | **[CONTRIBUTING.md](CONTRIBUTING.md)** | Comment contribuer |

## Pourquoi

La plupart des frameworks FiveM, c'est un core plus cinquante scripts tiers qui apportent chacun leur UI,
leur format de config et leur propre idée de qui a le droit de faire quoi. v-core fait le pari inverse :
**une seule base de code, un seul look, un seul modèle de permissions**, et **tout ce qu'un opérateur doit
régler est modifiable en jeu** - jamais en éditant du Lua sur un serveur en production.

## Caractéristiques

- **Natif FiveM Enhanced** - tourne sur `cfx-server.exe`, `gamename: gta5enhanced`. Pas de
  `sv_enforceGameBuild` (ce sont des numéros de build Legacy, qui bloquent les clients Enhanced).
  NUI compatible CEF 140 (`https://cfx-nui-…`).
- **`v-core`** - joueurs persistés en BDD, système de callbacks serveur/client, paliers de permission,
  log d'audit structuré, sélection multi-personnages. Tous les modules passent par lui.
- **Design system `v-ui`, entièrement thémable** - une feuille de style canonique partagée par toutes
  les pages NUI, pilotée par `v-ui/config.lua` : **6 presets de couleurs**, un accent d'où toute la
  famille de surbrillance est dérivée, arrondi des angles, densité, vitesse d'animation (0 = aucune),
  opacité des panneaux, échelle de police. Changer l'un d'eux dans **Admin -> Réglages -> Interface**
  restyle **tous les modules d'un coup** - aucun module ne code une couleur en dur.
- **Écran de chargement configurable** - `v-loadscreen/html/config.js` : **7 dispositions** (centre,
  gauche, droite, split, bas, haut, carte), les 6 mêmes palettes, fonds vidéo/image/dégradé/uni, chaque
  effet activable, et tous les textes + astuces au même endroit.
- **Éditeur de contenu en jeu** - **21 domaines** que le menu admin crée, modifie et supprime sans
  redémarrage : blips, boutiques, métiers & grades, gangs & rangs, items, recettes de craft, boutiques de
  vêtements & emplacements, garages, points de location, stations-service, ateliers, concessions,
  catalogue véhicules, types de licence, **territoires de gang**, **code pénal**, **substances**,
  **canaux radio**, **trésoreries de faction** et **thèmes par module**. Adossé à `v-world`,
  appliqué à chaud.
- **Registre de modules & réglages** - chaque module déclare ses réglages à `v-core` ; l'onglet
  **Réglages** du menu admin affiche ce qu'on lui donne, il n'a donc jamais à changer. Un script tiers
  ajoute `v_module 'yes'` à son manifest et y apparaît aussi - voir [DEVELOPERS.md](DEVELOPERS.md).
- **Aucune commande chat joueur** - la surface d'interaction, c'est l'œil de ciblage, les touches et la NUI.
- **Bilingue nativement** - chaque texte joueur existe en anglais et en français ; le joueur choisit sa
  langue à la première connexion.
- **Autoritaire serveur par défaut** - proximité, fonds, propriété et permissions sont revérifiés côté
  serveur à chaque action. Les contrôles côté client sont de l'UX, pas de la sécurité.
- **MariaDB locale à la demande** - jamais en service Windows, ne démarre jamais avec Windows.

### Modules de gameplay

- **`v-inventory`** - inventaire grille (poids, utiliser/jeter/donner), **catalogue de 302 items**, armes
  fonctionnelles (munitions, série, **durabilité/enrayage**, **accessoires**), sacs & armure, poche cachée,
  coffres de véhicule & stashes partagés/gang, et **fouille/vol de joueur + mains en l'air**.
- **`v-world`** - la couche de contenu modifiable par les admins (blips, boutiques, métiers, items, recettes).
- **`v-admin`** - panneau en jeu (F10) : tableau de bord, joueurs, scripts, monde, logs, **Éditeur**, et
  outils (noclip, mode dieu, invisible, blips joueurs, observation, ouvrir l'inventaire d'un joueur).
- **`v-appearance` / `v-spawn`** - moteur d'apparence à identité vêtement stable, sélection
  multi-personnages, coiffeur / chirurgien / salon de tatouage.
- **`v-crafting`** - **105 recettes** sur 6 stations (établi, rechargement, cuisine, électronique,
  **recyclage/raffinage**, **labo de drogue** caché), autoritaire serveur, recettes éditables en jeu.
- **`v-gathering`** - points de ressources (minage, casse, textile, cultures de cannabis cachées).
- **`v-shops`** - boutiques avec **achat & vente**, distributeurs, revendeur de ferraille, et
  **dealer / blanchisseur** illégal (argent sale). Positions modifiables en jeu.
- **`v-target`** - œil d'interaction universel (maintiens Alt gauche) : options **filtrées par permission & métier**.
- **`v-jobs`** - métiers, grades, salaires en service ; la référence pour tous les gates métier.
- **`v-vehicles` / `v-garages`** - persistance des véhicules possédés (mods, carburant, dégâts),
  plaques générées par le serveur, système de clés, et 9 garages dont une fourrière et les garages
  de métier, et un **aperçu 3D showroom** - le tout modifiable en jeu.
- **`v-fuel`** - quatre carburants (91 / 98 / gazole / électrique), consommation selon la charge
  moteur, 18 stations dont des bornes de recharge à plusieurs niveaux avec courbe de charge,
  jerricans ; stations et prix modifiables en jeu.
- **`v-mechanic`** - usure sur 20 pièces (12 en électrique) selon la distance, la conduite et les
  accidents, vrai compteur kilométrique, 27 pièces fabricables, kits de réparation et ateliers
  verrouillés par métier - le tout modifiable en jeu.
- **`v-vehicleshop`** - 6 concessions, catalogue de 56 véhicules avec aperçu 3D showroom, essais
  routiers, achats conditionnés au permis et revente ; concessions et catalogue modifiables en jeu.
- **`v-licenses`** - 12 licences & permis (identité, conduite, poids lourd, bateau, pilote, port
  d'arme…) avec suspension, retrait, expiration et points ; la référence unique des droits du perso.
- **`v-cityhall`** - le guichet emploi de la mairie : postuler à un poste laissé ouvert par un admin,
  ou démissionner. Les métiers sur whitelist (police, EMS, …) n'y apparaissent jamais.
- **`v-rentals`** - location courte durée à quatre comptoirs : caution et frais prélevés d'avance, plaque
  temporaire `RENT###` et minuteur. Rendu à temps, la caution revient. Une location ne crée jamais de ligne
  de propriété : c'est la seule règle qui sépare une location d'une voiture gratuite.
- **`v-factions`** - un seul moteur pour les factions légales et illégales : elles diffèrent par la table
  qui porte leur définition, `jobs` ou `gangs`, et par rien d'autre. Adhésion, rangs, et une **trésorerie
  qui est un vrai compte avec sa piste d'audit** plutôt qu'un nombre dans un fichier. Les salaires peuvent
  en sortir.
- **`v-bossmenu`** (F6) - le panneau dont un patron a besoin : membres, rangs, recrutement, renvoi,
  trésorerie et paie. **Verrouillé sur le rang, pas sur la permission admin** - le staff n'est pas patron.
- **`v-gangs`** - territoires avec capture et influence. L'influence appartient à celui qui tient le
  territoire et un rival l'*use* au lieu de la prendre : un territoire contesté est un combat, pas une
  course. L'influence non défendue décroît, un territoire doit être tenu et pas seulement pris.
- **`v-police`** - menottes, escorte, fouille, saisie, inculpation, amendes, prison et un MDT (casier,
  mandats, permis, véhicules). **La police est un métier, pas une permission.** Le code pénal est une
  donnée : 21 infractions avec amende, prison et points de permis, modifiables en jeu.
- **`v-banking`** (DAB Fleeca) · **`v-status`** (faim/soif/stress/saignement) · **`v-hud`** (vitales,
  argent, boussole, minimap carrée et un bloc véhicule avec carburant, moteur et compteur) · **`v-notify`**
  · **`v-clothing`** (16 emplacements portables, 10 boutiques, emplacements & boutiques modifiables en jeu) · **`v-loadscreen`**.
- **`v-radio`** (F3) - l'appareil : suivre plusieurs canaux à la fois, émettre sur un seul,
  présélections sur un pavé. Il ne décide d'aucune permission - il demande à `v-voice`.
- **`v-3dsound`** - un primitif de son positionnel que les autres modules appellent : un nom, un
  lieu et une portée passent sur le fil, jamais de l'audio, et seuls les auditeurs à portée sont prévenus.
- **`v-anticheat`** - contrôles serveur sur les déplacements, la santé, les explosions, la création
  d'entités par le client, l'argent et les dégâts d'arme. **Journalise par défaut au lieu
  d'expulser**, parce qu'un anticheat qui expulse des joueurs légitimes est pire que rien.
- **`v-voice`** - voix de proximité en trois paliers, canaux radio verrouillés sur le métier ou le
  rang de gang, et un canal séparé pour les appels. Un saignement réduit la portée, les menottes
  coupent la radio, et quitter un métier quitte son canal.
- **`v-drugs`** - des plantations que le joueur pose et peut perdre, et un deal de rue qui résiste :
  la demande décroît par quartier à mesure qu'on y vend, et la chaleur pilote les refus comme le
  risque d'interpellation. Les ventes paient en argent sale, qui doit passer par le blanchisseur.
- **Boucles économiques** - légale : récolter → fabriquer → vendre. Illégale : cultiver → traiter → dealer → blanchir.

## Installation

1. **Artifacts** - les binaires serveur vont dans `artifacts/` (non suivi par git). Télécharge
   **`cfx-server_win_x64.zip`** (Windows) ou **`cfx-server_linux_x64.tar.xz`** (Linux) depuis les artifacts
   cfx.re et extrais-les dans `artifacts/`. L'archive doit contenir **`cfx-server.exe`** - `server.zip` /
   `FXServer.exe` est la branche **Legacy** et refusera les clients Enhanced avec `bad_request`.
2. **Clé de licence** - récupère une clé gratuite sur [keymaster.fivem.net](https://keymaster.fivem.net/)
   et renseigne `sv_licenseKey` dans `server.cfg`.
3. **Base de données** - fais pointer `mysql_connection_string` dans `server.cfg` vers ton MySQL/MariaDB, puis importe `database/schema.sql`.
4. **Lancement** - `./start.ps1`.
5. **Connexion** - dans FiveM, appuie sur `F8` et tape `connect localhost:30120`.

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
   régler - voir le pattern `v-world` dans [ARCHITECTURE.md](ARCHITECTURE.md) §7.
5. Dans la console serveur : `refresh` puis `ensure <ta-ressource>`.

## Base de données (à la demande)

N'importe quelle instance MySQL ou MariaDB convient - le framework ne lui parle qu'à travers `oxmysql`,
donc la façon de la lancer t'appartient (service, Docker, ou installation locale à la demande).

Configure la connexion dans `server.cfg` :

```cfg
set mysql_connection_string "mysql://user:password@localhost:3306/ta_base?charset=utf8mb4"
```

Puis importe **`database/schema.sql`** (24 tables). Les migrations s'appliquent automatiquement au démarrage.

## Dépendances

- [FiveM / cfx.re](https://fivem.net/) · [Natives FiveM](https://docs.fivem.net/natives/) ·
  [Manuel serveur](https://docs.fivem.net/docs/server-manual/setting-up-a-server/) ·
  [MariaDB](https://mariadb.org/) · [oxmysql](https://github.com/overextended/oxmysql) ·
  [screenshot-basic](https://github.com/citizenfx/screenshot-basic) - miniatures du catalogue de vêtements

## Credits

Author: vyrriox
