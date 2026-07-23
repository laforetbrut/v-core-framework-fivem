# v-core - Architecture & Module Guide

How the framework is wired, what each module actually does today, and what is left to build.

Last surveyed: **2026-07-22** (every module read end-to-end; see `## Per-module status`).

Platform: **FiveM Enhanced** - the server runs on `artifacts/cfx-server.exe` (the Enhanced binary;
`FXServer.exe` is the Legacy branch and rejects Enhanced clients with `bad_request`). `info.json`
must report `gamename: gta5enhanced`. **Never set `sv_enforceGameBuild`** - those are Legacy build
numbers and enforcing one locks Enhanced clients out. CEF is Chromium 140, so `nui://` is no longer a
secure context: always reference NUI assets as `https://cfx-nui-<resource>/…`.

---

## 0. Build progress - in-game content editor, inventory & appearance

### In-game content editor - `v-world` + the v-admin **Editor** tab

`RULES.md` §3.6.2 requires every content system to be create/modify/delete-able in-game. `v-world` is
the module that owns that data; `v-admin`'s Editor tab is its UI. Five domains are live:

| Domain | Table | Consumed by | State |
|--------|-------|-------------|-------|
| **Blips** | `world_blips` | `v-world/client` renders them directly | ✅ |
| **Stores** | `world_shops` | `v-shops` (peds, blips, v-target zones, `canUseShop`) | ✅ |
| **Jobs** | `jobs` | `v-jobs` (`JobDefs`, grades, pay) | ✅ |
| **Items** | `items` | `v-inventory` (`ItemDefs` + type-driven use handlers) | ✅ |
| **Craft** | `craft_recipes` | `v-crafting` (`Recipes`) | ✅ |
| **Clothing stores** | `world_clothing` | `v-clothing` (blips, clerk peds, `atStore`) | ✅ |
| **Clothing slots** | `clothing_categories` | `v-clothing` (`Categories`, item defs, use handlers) | ✅ |
| **Garages** | `world_garages` | `v-garages` (blips, markers, store/retrieve) | ✅ |
| **Fuel stations** | `world_stations` | `v-fuel` (blips, pumps, prices) | ✅ |
| **Mechanic shops** | `world_mechshops` | `v-mechanic` (blips, diagnostics, repairs) | ✅ |
| **Dealerships** | `world_dealers` | `v-vehicleshop` (blips, which categories a dealer sells) | ✅ |
| **Vehicle catalogue** | `vehicle_catalogue` | `v-vehicleshop` (model, price, stock, licence, job) | ✅ |
| **Licences** | `license_types` | `v-licenses` (key, issuer, price, validity, test) | ✅ |

Wiring: every editor write goes through the `v-world:save` / `v-world:delete` callbacks (permission-gated
+ audit-logged), which reload the domain and fire the **server-to-server** event
`v-world:server:changed(domain)`. Each consuming module listens for it and rebuilds its runtime tables
live - **no `restart` needed**. Config tables are now *seed data only*: they are pushed to the DB with
`INSERT IGNORE` on first boot, so the DB is the single source of truth and admin edits are never
overwritten on restart.

Guard rails: item internal `name` is immutable after creation (renaming would orphan every stack);
deleting an item is refused if a recipe references it, and `money` can never be deleted.

**Visibility gating:** a blip row carries `job` + `grade` + `perm`. The filtering runs **server-side, per
player** (`blipsFor(src)`) - a restricted location is never sent to a client that isn't allowed to see
it, so it can't be read out of client memory. The set is re-pushed on `v-jobs:server:changed` and
`v-core:server:permissionChanged`. A job row carries `whitelisted`: whitelisted jobs are hidden from the
city hall and handed out by their own chain of command.

**Clothing slots are data now.** `clothing_categories` holds the wearable slots themselves - key, label,
`kind` (comp/prop), the GTA component/prop id, the inventory item the slot mints, price, thumbnail
framing and sort order. An admin can add a whole new wearable category from the panel: v-clothing
rebuilds its runtime list, inserts the item definition, binds the use handler and pushes the new set to
every client, live. The slot **key** is immutable once created (it is stamped into every garment's
metadata). A category's `slot` is validated against the real component/prop range, so an id that would
render nothing is refused.

**Remaining for the editor:** vehicles, gangs, gathering nodes, crafting *stations* (only recipes are
editable, the benches are still `config.lua`), shop price lists / sell lists, and a live map-picker
instead of "use my position".

The two other in-flight workstreams. `✅ done · 🔨 in progress · ⬜ not started`.

### Appearance suite (rebuild - full plan in `memory/appearance-suite-plan.md`)

| Phase | What it delivers | State |
|-------|------------------|-------|
| **1 - engine + stable identity** | `v-appearance` module = single ped writer; clothing stored as stable **(collection, local index, texture)** refs (survives addon/build changes); v1→v2 migration on load; v-spawn + v-clothing delegate rendering; `appearance` added to autosave. | ✅ **done** |
| **2 - barber / surgery / tattoos** | Shared re-openable editor with three station types (barber, plastic surgeon, tattoo parlour) + peds/blips. Barber = hair style/colour/highlight + all head overlays with **proper opacity + colour** (blush/makeup/lipstick were dead; now correct); surgeon = 20 face features + head-blend mixes; tattoos = 869-overlay catalogue by zone, apply/remove, **stored in `appearance.tattoos`** and re-applied by the engine after the head-blend. | ✅ **done** |
| **3 - catalogue + scanner rebuild** | **Foundation ✅**: `clothing_catalogue` + `clothing_scan_state` tables, `VCore.DB` catalogue/scan functions, and a verified CEF **colour-extraction** module (CIELAB ΔE nearest-named-colour, saturation-weighted). **Remaining**: the actual scan capture pipeline - per-gender enumeration via the collection natives, wiring the colour extractor + perceptual hash into the NUI, `.webp` storage (not loose `.txt`), replace-clothing detection, incremental/resumable scan. Needs an in-game scan (screenshot-basic) to verify. | 🔨 |
| **4 - shops + inventory integration** | Per-shop catalogues, dynamic stock, filters (colour/name/sub-type), in-game shop creation, restrictions (job/ace/id), item-metadata → ref migration. | ⬜ |
| **5 - outfits + job outfits + height** | Wardrobe & job outfits (temporary override layer); character height (opt-in, off by default, experimental - no true GTA V native). | ⬜ |

**Not achievable as the vendor markets it** (verified against the FiveM natives, see the plan): the 46 000 pre-tagged catalogue and "AI labelling"/sub-types are a shipped hand-authored dataset, not runtime-derivable; character height is visual-only and glitchy (no `SET_PED_SCALE` on GTA V). We reach parity by curation + our colour extractor, and ship height opt-in/experimental.

### Inventory (feature-parity roadmap the owner asked for)

| # | Feature | State |
|---|---------|-------|
| - | Core grid, weight/slots, use/give/drop, stashes, trunk, cash-as-item, equipment panel | ✅ done |
| - | **Pointer-based drag & drop** (HTML5 DnD is unreliable in CEF) | ✅ done |
| - | **Fallback icons** for imageless items (clothing garment / generic box) | ✅ done |
| - | **Hidden pocket** (1 kg concealed compartment, invisible to a police search) | ✅ done |
| 1 | Unified player top-nav menu | ⬜ |
| 2 | Weapons **functional** (equip/holster via Use, ammo boxes top up the drawn weapon, serial minted on first draw, ammo persists to metadata) ✅ · **attachments** ✅ (5 attachment items - suppressor / flashlight / scope / grip / extended-mag - `Use` fits them to the drawn weapon via a server component map, stored on the weapon item's metadata and re-applied on every draw; craftable at the reloading bench) · on-back / draw anims ⬜ | 🔨 |
| 3 | **Shared/gang stashes with permissions** - persistent containers gated by job / gang / permission tier, opened via `exports['v-inventory']:OpenSharedStash(src, id)` or a net event; access checked server-side on every open (`Config.SharedStashes`) | ✅ framework (needs placement/interaction points) |
| 4 | Advanced shops with a **basket** (drag-to-buy + inventory view now shipped in v-shops) | 🔨 partial |
| 5 | Advanced crafting (recipes, benches) ✅ - **`v-crafting`** module: 4 stations (workbench / reloading / kitchen / electronics), 25 recipes, server-authoritative proximity + input check + space-check with refund, EMBER NUI (material chips have/need + progress bar), optional job/perm gates | ✅ |
| 6 | Inventory customization (colours, transparency, centered mode) | ⬜ |
| 7 | **Backpacks** (carrying one adds +12 slots / +20 kg) ✅ · **body armor** items apply armour on use ✅ · armor DLC ⬜ | 🔨 |
| 8 | **Player search / steal** ✅ (frisk a nearby hands-up / downed player - server-validated proximity + gate, cross-player container, take **or** plant, hidden pocket never exposed) + **hands-up surrender**. In-world *placed* items (beyond ground drops) ⬜ | 🔨 |
| 9 | Bonus: vending machines, garbage job, skill tree | ⬜ |

**Optimization:** the item catalogue (`defs`, ~170 rows) is now sent to the NUI **once** on open and cached; move/use/drop responses omit it - every action payload dropped from ~full-catalogue to just the changed state.

Also outstanding on inventory (from the audit, not yet fixed): moving the direct-SQL `stashes`/`items` access behind `v-core`. **Done since the audit:** weapon serial/ammo persistence ✅, in-world drops are now **real props** that are garbage-collected when emptied ✅ (also fixed the unbounded `Stashes` leak), **weapon attachments** ✅, and **weapon durability/wear** ✅ (server-derived from reported ammo; a Cleaning Kit repairs it). Food/perishable time-decay still open.

### Other recent additions

- **Multi-character selection** - slots per tier (user 1 / mod 2 / admin 6), Play / New / Delete (admin-gated). `v-core` GetCharactersByLicense / DeleteCharacter / selectCharacter / deleteCharacter callbacks; `characters.slot` now written on create.

### Recently fixed bugs (this session)

- **Inventory/shop drag stacking & slot placement** - oxmysql TINYINT→boolean broke `stackable==1`; empty-table metadata (`{}` truthy in Lua) blocked merges; drops ignored the target slot. Fixed with flag coercion, a `noMeta` helper, and a preferred-slot arg on `AddItem`/`addToContainer`.

- **No mouse in any menu** - `SetNuiFocus` is resource-scoped; `v-core` had no `ui_page`, so the shared focus helper was a silent no-op. Each owning resource now takes focus itself.
- **Spawn fell into the void / showed a default ped** - screen held black from the first frame; ped kept frozen while collision streams + ground is found; unfrozen only after the switch-in.
- **Inventory drag broken + imageless items** - see the two ✅ rows above.

---

## 0b. The module registry - settings & third-party integration

Two problems, one answer. *"Everything must be configurable from the admin panel"* and
*"someone else's script should plug in without editing the framework"* are the same problem
once you notice that both are about a module **describing itself**.

`v-core/server/modules.lua` holds a registry. A module declares its **tunables**; v-core
stores the values (`module_settings`), serves them to the admin panel, and pushes changes
back. **`v-admin` knows nothing about any module's settings** - it renders whatever it is
handed, which is exactly what makes a third-party resource a first-class citizen.

```lua
exports['v-core']:RegisterModule('my-script', {
    label = 'My Script', category = 'gameplay',
    settings = {
        { key = 'payout', label = 'Payout', type = 'number', default = 250, min = 0, max = 10000 },
    },
})
local payout = exports['v-core']:GetSetting('my-script', 'payout')
AddEventHandler('v-core:server:settingChanged', function(mod, key, value) ... end)
```

Types: `number` (min/max/step), `bool`, `string` (maxLength), `select` (options), `color`.
Every submitted value is **coerced and clamped server-side**; one that cannot be coerced is
rejected rather than stored as something else. Changes fire `v-core:server:settingChanged`
and are mirrored to every client (`Core.GetSetting` client-side), so nothing polls.

**Auto-detection.** A resource with `v_module 'yes'` in its `fxmanifest.lua` is listed even
before it registers anything - an operator can see it is installed. All 25 of our own
modules carry the flag. Full guide: **[DEVELOPERS.md](DEVELOPERS.md)**.

**Settings vs. content.** A *tunable* (a rate, a threshold, a price multiplier) is a
setting. A *list* (shops, items, recipes, garages) is a **v-world domain** with an Editor
subtab - §7. Using a setting for a list, or a domain for a single number, is the mistake
this split exists to prevent.

**32 of 34 modules declare their settings** - every one that has a meaningful tunable.
The two that do not (`v-loadscreen`, `v-admin`) are infrastructure with
nothing an operator would sensibly change at runtime; `v-core` itself is listed so an
operator sees it running.

A caveat worth stating: a declared setting is only real if something **reads** it. The
first sweep declared five multipliers (`v-shops` buy/sell, `v-crafting` duration,
`v-gathering` yield, `v-clothing` price) and a salary multiplier that nothing consumed -
they have since been wired into their actual code paths. A setting that does nothing is
worse than no setting: it lies to the operator.

---

## 0c. Seeding - how a default reaches the database

Every module ships defaults in `config.lua` and pushes them into its `v-world` table once.
The first real boot showed the original rule - *"seed only if the table is empty"* - was
wrong in a way that is invisible until it bites: this database already held 3 jobs from an
older schema, so `mechanic` and `taxi` were **never inserted**, the mechanic shops gated on
`job = 'mechanic'` could match nobody, and the city hall could not offer either job.

There are two kinds of table and they need different rules:

| Table shape | Rule | Why |
|---|---|---|
| **Natural key** (`jobs.name`, `license_types.key`, `vehicle_catalogue.model`, garages/stations/mechshops/dealers `id`, `clothing_categories.key`) | Re-seed when the **config's entry count changes** (`world_seeded.count`); every insert is `INSERT IGNORE` | Existing rows are untouched, genuinely new defaults get added, and a default an admin deleted stays deleted until the config itself changes |
| **AUTO_INCREMENT id** (`world_shops`, `world_clothing`, `craft_recipes`) | Seed **only when the table is empty** | There is no key to dedupe on, so a re-run would duplicate every row - which is exactly what happened on the boot that proved this |

**Column migrations backfill.** An `ALTER TABLE ... ADD COLUMN` leaves existing rows at the
column default, which is not always the right answer. `jobs.whitelisted` defaulted to `0`,
so police and EMS - rows that pre-dated the column - would have been handed out at the city
hall to anyone. The migration now backfills non-civilian jobs in the same step.

---

## 1. Layers

```
v-ui        → shared design system (theme.css). No logic, no Lua.
v-core      → the framework: database, API, callbacks, permissions, i18n, logs,
              persistent player object.
v-<module>  → feature resources (hud, banking, inventory, …).
              They consume v-core's API and events.
```

Load order (`server.cfg`): `oxmysql → screenshot-basic → v-loadscreen → v-ui → v-notify → v-core → v-jobs → v-spawn → v-status → v-hud → v-banking → v-target → v-inventory → v-shops → v-crafting → v-gathering → v-clothing → v-admin`.

**Rule that is currently violated:** modules are supposed to never touch SQL - only `v-core` may.
Five modules query the DB directly today. See `## 6. Cross-cutting debt`.

---

## 2. The v-core API

### Get the core
```lua
local Core = exports['v-core']:GetCore()   -- server or client
```

### Server - player object
```lua
local player = Core.GetPlayer(source)         -- object for a connected source
Core.GetPlayerByCitizenId('V4KD9P2A')
Core.GetPlayers()                             -- array of all loaded players

player.citizenid, player.name, player.charinfo
player.money.cash / player.money.bank
player.job  = { name, grade }
player.gang = { name, grade }

player.AddMoney(account, amount, reason)      -- true/false, syncs client + fires event
player.RemoveMoney(account, amount, reason)   -- true/false (checks funds)
player.SetJob(name, grade)                    -- syncs client + fires v-core:server:onJobChange
player.SetGang(name, grade)                   -- NOTE: fires no server event (asymmetric, see gaps)
player.SetMetadata(key, value) / player.GetMetadata(key)
player.GetInventory() / player.SetInventory(inv)
player.UpdatePosition(coords)
player.Save()                                 -- also autosaved + on drop + on resource stop
player.ExportData()                           -- table sent to the client
```

### Server - callbacks, permissions, logs
```lua
Core.RegisterCallback('v-banking:getAccounts', function(source, resolve)
    local p = Core.GetPlayer(source)
    resolve({ cash = p.money.cash, bank = p.money.bank })
end)

Core.HasPermission(source, 'admin')          -- user < mod < admin < superadmin
Core.SetPermission(source, 'mod')            -- persisted to users.permission
Core.Log('economy', 'message', { any = 'data' }, citizenid)   -- console + logs table
Core.Notify(source, 'message', 'success')    -- routed to v-notify
```

### Client - data, callbacks, events
```lua
local data = exports['v-core']:GetPlayerData()

Core.TriggerCallback('v-banking:getAccounts', function(accounts) end)

AddEventHandler('v-core:client:onPlayerLoaded', function(data) end)
AddEventHandler('v-core:client:onMoneyChange',  function(money, account, reason) end)
AddEventHandler('v-core:client:onJobChange',    function(job) end)
AddEventHandler('v-core:client:onGangChange',   function(gang) end)
```

### Server events other modules can listen to
```lua
AddEventHandler('v-core:server:onPlayerLoaded', function(source, player) end)
AddEventHandler('v-core:server:onMoneyChange',  function(source, account, amount, reason) end)
AddEventHandler('v-core:server:onJobChange',    function(source, job) end)
```

### Client - NUI focus bookkeeping (v-core/client/focus.lua)
```lua
exports['v-core']:MenuOpened()      -- ref-counts, sets LocalPlayer.state.nuiOpen
exports['v-core']:MenuClosed()
exports['v-core']:IsAnyMenuOpen()
```

> **`SetNuiFocus` is resource-scoped.** The native resolves against the *calling* resource's own
> NUI frame and returns early when that resource has no `ui_page`. `v-core` has none, so it can
> never take focus on another module's behalf. **The resource that owns the page must call
> `SetNuiFocus` itself**, right next to its `MenuOpened()` / `MenuClosed()` report. This caused a
> total loss of mouse input in every menu on 2026-07-10 - see `ERROR_LOG.md`.

---

## 3. Database

Schema lives in **`database/schema.sql`** (25 tables; `world_blips` gains `job`/`grade`/`perm` and `jobs` gains `whitelisted` via idempotent `ALTER`s at boot). MariaDB, accessed through `oxmysql`.
`craft_recipes` is created idempotently at boot by `v-world`'s `ensureTables()`.

| Table | Owner | Purpose | State |
|-------|-------|---------|-------|
| `users` | v-core | account per license: name, language, permission, last_seen | ✅ used |
| `characters` | v-core | identity, cash/bank, job, gang, position, metadata, inventory, appearance | ✅ used (`slot` column unused - multi-character not implemented) |
| `items` | v-core (schema) | item definitions (name, label, weight, stackable, usable, category, metadata) | ✅ **source of truth** - seeded `INSERT IGNORE` by v-inventory/v-clothing, edited live from v-admin → v-world |
| `logs` | v-core | structured audit log | ✅ used (read directly by v-admin) |
| `bank_transactions` | v-banking | deposit / withdraw / transfer_in / transfer_out audit | ✅ used (direct SQL) |
| `stashes` | v-inventory | persistent containers (stashes, gang boxes, ground drops) | ✅ used (created + queried directly) |
| `shops` | v-shops | shop catalogue + prices | ⚠️ read at boot only; store **positions** now live in `world_shops` |
| `world_blips` | v-world | admin-created map blips | ✅ used (Editor → Blips) |
| `world_shops` | v-world | store positions: coords, heading, ped model, blip | ✅ used (Editor → Stores, consumed by v-shops) |
| `craft_recipes` | v-world | recipes: station, output, count, time, ingredients JSON | ✅ used (Editor → Craft, consumed by v-crafting) |
| `character_vehicles` | - | vehicle ownership | ⬜ **empty - v-vehicles not built** |
| `jobs` | v-world | jobs & grades | ✅ used (Editor → Jobs, consumed by v-jobs) |
| `gangs` | - | gangs & grades | ⬜ **empty - v-gangs not built** |
| `server_config` | - | live server settings | ⬜ **empty - never read or written by anything** |

**Planned by the roadmap (§5), not created yet:**
`vehicle_rentals` (active hires), `faction_treasury` + `faction_transactions`, `gang_territories`,
`drug_plants` / `drug_labs`. `gangs` already exists and is still empty; **`character_vehicles` and `world_garages` are now live**.

---

## 4. Per-module status

Legend: ✅ shipped · ⚠️ shipped with a known hole · ⬜ not built.

### `v-ui` ✅ - shared design system, themeable at runtime
**Done.** `config.lua` owns the whole look: **6 presets**, an accent from which the entire
highlight family is derived (hover, glow, selection, gradients), corner roundness, density,
animation speed, panel opacity, backdrop darkness, font scale, rarity colours and three
feature switches (corner brackets, panel top light, film grain). Every one is an admin
setting, applied live.

The delivery mechanism is the interesting part: a NUI page can only be messaged by the
resource that owns it, so v-ui cannot push variables into v-inventory's page. Instead the
server resolves the theme into **`theme-vars.css`** (`SaveResourceFile`), which every page
links after `theme.css`; `theme.js` re-links it with a new cache-buster when the version
changes. One channel that reaches all 16 pages, and it survives a page reload for free.

`theme.css` no longer contains a single hardcoded colour - its 19 literal brand-orange
values were routed through `--v-accent-glow` / `--v-accent`, which is what makes a preset
switch actually reach every shadow and filter.

**One global theme, with a per-module override.** A server owner who wants the inventory
more transparent, or the admin panel in a different colour, does not have to fork anything:
`ui_overrides` holds one row per module and **every column is nullable - NULL means
inherit**, so a row carries only what genuinely differs. The generated stylesheet is
therefore

```css
:root { /* the global theme */ }
:root[data-vmod="v-inventory"] { /* only what this module overrides */ }
```

and `theme.js` stamps the owning resource onto `<html>` (a NUI page is served from the
resource that owns it, so `location.hostname` *is* the module name). A page picks up its own
block and inherits the rest. Managed in one place: **Admin → Editor → Look → Module themes**,
where the module list comes from the live registry - so a third-party script that declared
itself is themeable with no change to v-ui.

An accent override with no preset derives its own gradient partner; otherwise a green accent
would still end in the global orange.

**Boot notes.** v-ui is ensured *before* v-core (every NUI needs the stylesheet first), so
the core is resolved lazily rather than at file scope, and a fallback `theme-vars.css` is
committed so the resource loads before its first generation.

### `v-ui` (original notes) - shared design system
**Done.** `theme.css` only: the full "EMBER" token set (warm-graphite surfaces, **dominant**
brand orange with gradient/glow variants, muted status + rarity scales, 8–22px rounded geometry,
soft layered shadows, `--z-*` scale, fluid/spring motion tokens) plus the primitives `.v-chamfer`
(rounded glass panel + orange top light-streak) / `.v-tab` / `.v-brk` / `.v-slot` / `.v-gauge` /
`.v-progress` / `.v-glass` / `.v-btn` / `.v-chip` / `.v-stencil` / `.v-input`, a global
`:focus-visible` ring and a `prefers-reduced-motion` block. CEF-safe: **no `backdrop-filter`**
(FiveM's CEF renders it as an opaque black box) - depth comes from layered gradients and shadows.
No SQL, no Lua, no exports.

**Remaining.**
- No shared JS runtime - every module re-implements the `--i` stagger, gauge fill and `.is-over`
  toggling in its own `app.js`. That is the copy-paste drift the single-source rule exists to stop.
- `--v-rar-legendary` is byte-identical to `--v-accent`, so a legendary item is indistinguishable
  from ordinary accented chrome.
- No `dependencies{}` block: if `v-ui` fails to start, every NUI page renders unstyled **silently**.
- No cache-busting on the stylesheet URL.
- `v-loadscreen` cannot link it (loads pre-mount) and mirrors the EMBER tokens locally - they will drift.

### `v-core` ✅ - framework
**Done.** Player lifecycle (`playerReady` → `EnsureUser` → load-or-create character → `playerLoaded`,
autosave + save on drop/stop). Self-persisting player object with guarded `AddMoney`/`RemoveMoney`.
`VCore.DB` layer over `users` / `characters` / `logs` / `items`. Bidirectional callback bus with
request-id correlation. Permission tiers with DB + `Config.Admins` bootstrap. i18n engine
(`L` / `LP`, fr default via `vcore_lang`, per-player `state.lang`). Structured logging to console +
`logs`. Private routing-bucket isolation for character creation, concurrency-guarded. NUI-focus
bookkeeping. Two permission-gated console commands (`givemoney`, `setperm`).

**Remaining.**
- **Multi-character is not implemented** - `GetCharacterByLicense` is `ORDER BY slot ASC LIMIT 1`
  with the comment "multi-character selection comes later". No character delete / rename / slot UI.
- `createCharacter` and `v-core:server:saveAppearance` write **client-supplied data straight to the
  DB** with no length, format or size validation, and no rate limit. DB-bloat vector.
- `GenerateCitizenId` has no collision retry; a duplicate id makes the INSERT fail inside a `pcall`
  and the player is silently stuck on the creation screen (no error string exists for it).
- `SetGang` fires no `v-core:server:onGangChange` - asymmetric with `SetJob`.
- `Config.Accounts` and `Config.DefaultSpawn` are dead keys. `Config.Debug` ships as `true`.
- `Core.Log` webhook sink is a stub (`"plugs in here later"`) - console + DB only.
- No cap on `AddMoney`; any resource holding the player object can mint unbounded money.
- Dead code: `CreateDefaultCharacter`, `GetItems`, `GetPlayerByCitizenId` are never called in-core.

### `v-notify` ✅ - toasts
**Done.** Client `exports['v-notify']:show(data)` + `v-notify:show` net event. Four muted types with
line icons, rounded EMBER glass cards with a type-keyed accent bar, XSS-safe escaping,
click-to-dismiss, glowing countdown bar, `aria-live` region.

**Remaining.**
- **No server-side export.** Every server caller hardcodes the literal string
  `TriggerClientEvent('v-notify:show', src, data)` - renaming the event silently breaks all of them.
- No stack cap and no max-duration clamp → an unbounded toast stack + leaked timers.
- No de-duplication, no positioning options, no sound, no "clear all".

### `v-loadscreen` ✅ - boot screen
**Done.** Native loadscreen, ken-burns video + poster, blueprint grid + grain + vignette, stencil
title, 16-notch progress gauge with a monotonic clamp, rotating tips, staggered entrance.

**Remaining.**
- **Status strings are French-only** (`Initialisation…`, `Chargement de la carte…`) and tips crudely
  alternate FR/EN every 5s. It cannot use the locale system (it loads before `v-core`).
- The progress bar **fabricates advancement**: an idle-creep interval pushes it to 92% even when no
  real load event fires.
- Server name, kicker, signature, tips and asset paths are hardcoded in HTML/JS.
- Mirrors `theme.css` tokens locally - will drift.

### `v-spawn` ✅ - onboarding
**Done.** Language pick → identity form → full appearance editor (6 tabs, orbit camera, colour
swatch grids, garment thumbnail strips wired to v-clothing's scan) → first-spawn location cards
(LSIA / Bolingbroke / Sandy Shores) → GTA-style `SwitchOutPlayer`/`SwitchInPlayer` swoop with
ground-Z snap. Returning characters restore their saved look and swoop to their last position.

**Remaining.**
- **No re-entry path** - there is no export or event to reopen the creator for a barber or a
  plastic surgeon, even though `v-core` already ships `SaveAppearance` for exactly that.
- `Config.Max` is **dead and drifted**: nothing reads it, and its ranges disagree with the real
  ranges hardcoded in `app.js` (`tops` 300 vs 350).
- **Blush does nothing** - the control exists in the UI, but `ped.lua` has no blush overlay.
  **Makeup and lipstick are invisible** - their default opacity is `0.0` and no opacity slider exists.
- Drawable ranges are model-independent and unclamped against `GetNumberOfPedDrawableVariations`, so
  out-of-range / invisible garments are selectable.
- Creation failure gives **no feedback** - the player is soft-locked on the appearance screen.
- DOB is unvalidated (any string into a `DATE` column; future dates accepted).
- Eye-colour palette exposes 24 of ~32 swatches.
- The chosen spawn point is only teleported client-side; it reaches the DB on the next autosave, so
  an immediate disconnect loses it.
- No randomize / reset button.

### `v-status` ⚠️ - survival
**Done.** Server-authoritative hunger / thirst / stress / bleed (0-4) / sick (0-3). Drain tick,
starvation damage, bleed damage + screen flash + ragdoll, illness damage, stress timecycle + cam
shake. Client injury detection. Persistence through `v-core` metadata (respects the no-SQL rule).
Server mutator exports: `Get` / `Set` / `Add` / `SetBleed` / `SetSick` / `Heal`.

**Remaining - and one of these is a real bug.**
- **Status damage can never kill.** The client forces `SetEntityHealth(ped, math.max(101, target))`,
  so starvation, bleeding and illness all floor at 101 HP. Level-4 bleed (12 HP/tick, designed to
  down a player) can never down anyone. The server also passes a *different* floor (`110`).
- **`Set`/`Add` mis-clamp `bleed` and `sick`** to 0-100 instead of 0-4 / 0-3, so an item or EMS
  caller silently corrupts the state and drives a `nil` damage-table lookup.
- **`Get` returns the live table by reference** - any consumer can write `Get(src).hunger = 999`,
  bypassing clamping, persistence and sync.
- **Exploit:** `v-status:server:onRespawn` is a plain net event with no death validation. A client
  can spam it to cure its own bleeding and refill hunger/thirst to 50 at will.
- Injury detection is client-side (HP drop > 8) - a modded client is immune; it also false-positives
  on falls and teleports.
- **Stress has no source and no decay**, and **illness has no source** - nothing in the codebase ever
  raises them, so both systems are dead until an external caller drives them.
- `Heal` clears bleed + sick only, not hunger/thirst/stress, despite being labelled "full cleanse".
- The stress thread calls `ClearTimecycleModifier()` every second, **stomping any timecycle set by
  another resource** (drunk, nightvision, weather fx).
- No HUD of its own (by design - `v-hud` renders it), no locales, no in-game tuning UI.

### `v-hud` ✅ - overlay
**Done.** Money readouts, seven always-visible vitals rings, hunger/thirst alerts at 25% with
hysteresis, scrolling compass, **custom square minimap** (streamed mask, GTA:O health/armour bars
removed via the scaleform, NUI frame slaved to the native map's true screen rect), drag-to-move and
resize, F7 settings panel (element toggles, accent, opacity, scale, layout mode), whole-HUD auto-hide
on pause / fade / player switch / open menu, KVP persistence, fr+en.

**Remaining.**
- Settings live in **client-side KVP**, so they are per-machine, not per-character, and not
  server-authoritative.
- **No exports and no inbound events** - another resource (a cutscene, a phone) cannot cleanly hide
  or drive the HUD.
- Everything is hardcoded: poll interval, alert thresholds, oxygen multiplier, danger thresholds,
  the six accent presets, compass constants. No config, no admin surface.
- `v-notify` is used but not declared in `dependencies{}`; if absent, the 25% alert silently vanishes.
- The accent picker offers green/blue/red/amber/purple, which contradicts the one-accent rule in
  `RULES.md` §3.5. **Open question for the owner:** restrict it to orange variants, or keep it as a
  player preference outside the design system?
- Several `aria-label`s and the panel's `HUD` tab label are hardcoded English.
- Dual source of truth for minimap size (Lua `map.scale` vs JS `settings.minimapSize`).

### `v-banking` ⚠️ - Fleeca ATM
**Done.** ATM proximity (4 prop models) → E → NUI with balances + last 20 transactions. Deposit,
withdraw, transfer by citizenid (self-transfer blocked, recipient existence checked, online credited
in-memory / offline credited by SQL). Every mutation server-authoritative; both legs audited into
`bank_transactions`. Full fr+en.

**Remaining.**
- **DUPE VECTOR.** An offline recipient is credited with an *immediate persistent* SQL
  `UPDATE ... bank = bank + ?`, while the sender's deduction is only an *in-memory* `RemoveMoney`
  that persists on the next autosave. A crash in that window creates money. Online→online is
  symmetric and safe; only the offline path is exposed.
- **No server-side ATM proximity check** - deposit / withdraw / transfer are net callbacks a modded
  client can call from anywhere. No rate limiting either (each offline transfer is 4 queries).
- Direct SQL against `bank_transactions` **and against `characters`, a table it does not own**.
- **No export** - salaries, fines and shops cannot record a bank transaction, so their money movements
  never appear in the history.
- The recipient notification is a **hardcoded French string** that bypasses i18n entirely.
- Transfers use the raw internal citizenid - no name lookup, no account number, no contacts.
- No fees, limits, savings, business accounts, cards or statements. No blips, no bank interior teller.
- History is capped at 20 rows, no pagination, and re-queried on every mutation.

### `v-inventory` ✅ - grid inventory
**Done.** 40 slots / 30 kg, 5-slot hotbar (keys 1-5), **TAB** to open. **300-item catalogue**
(`data/items.lua`; the first 170 ship local PNGs, the rest use `image=nil` and fall back to the NUI
glyph), seeded on boot with **`INSERT IGNORE`** - the `items` table is the source of truth and is
edited live from v-admin → v-world, so re-applying the Lua values every boot would wipe admin edits.
`loadItemDefs()` re-reads the definitions and re-binds the type-driven use handlers whenever
`v-world:server:changed('items')` fires. Drag & drop (move / swap / merge / shift-split),
right-click actions (use / give / split / rename / drop), search, tooltip with rarity / serial / ammo /
durability. **Cash as an item** - a virtual wallet tile mirroring the account, which stays the single
source of truth (no dupe path). Vehicle trunk + glovebox, persistent stashes, ground drops.
**Equipment panel** - clothing as body slots, drag to equip, right-click to unequip (driven by
v-clothing's `GetWorn` / `Unequip`). Server-authoritative: every action re-renders from the returned
state. EMBER NUI.

Exports: `AddItem` / `RemoveItem` / `GetItemCount` / `RegisterUsableItem`.
Callbacks: `getState` / `move` / `use` / `drop` / `give` / `rename` / `unequipCloth`.

**Remaining - this is the biggest backlog in the project.** The owner has asked for the full
premium-inventory feature set:
1. Unified player top-nav menu.
2. **Weapons & attachments** (serial/ammo metadata exists; attachments, weapon-on-back, draw anims do not).
3. Shared stashes **with permissions** (stashes exist; access control does not).
4. Advanced shops with a **basket**.
5. Advanced **crafting** (recipes, benches).
6. Inventory **customization** (colours, transparency, centered mode).
7. **Backpacks** + armor DLC.
8. **Place items in the world** as real entities + **player search / steal**.
9. Bonus: vending machines, garbage job, skill tree.

Also missing: item degradation over time, and `v-clothing` accessories (bag / watch / ring / necklace /
vest / armor) need new component & prop ids plus a **live ped preview** in the equipment panel.

Known holes today:
- Direct SQL: it `CREATE TABLE`s and queries `stashes` itself and reads `items` itself.
- `giveitem` is a server chat command.

### `v-shops` ⚠️ - stores
**Done.** Clerk peds + blips at fixed 24/7 locations, streamed in/out. Buy UI with quantity stepper
and cash/bank toggle. Purchase re-derives the price server-side, checks funds, reserves inventory
space via `AddItem`, then charges and logs. fr+en.

**Fixed (hardening pass).** `getShop` / `buy` now run through `canUseShop`: the server checks the player
is **physically at a store** mapping to that shop id (coords from the shared `Config.Locations`) and, for
job-locked stores, that the player **holds the job** - closing the buy-from-anywhere and unenforced-`job`
holes. Purchase amount is **clamped server-side**, `ItemDefs[data.item]` is **guarded** before the label
index, and `RemoveMoney` is now **checked with the item refunded on failure** (latent dupe closed).

**Selling.** The NUI has a **Buy / Sell toggle**; Sell mode lists owned items the store buys (price + owned
count + Sell button). `v-shops:sell` runs the same `canUseShop` gate, reads the price from `Config.SellLists`,
verifies the owned amount, `RemoveItem`s then `AddMoney`. A sell-only **Scrap Dealer** shop is auto-seeded at
boot (`Config.SeedShops`) so no manual SQL is needed. Closes the gather→craft→**sell** loop.

**In-game editable.** Store **positions** (coords, heading, clerk ped, blip, shop id, enabled) now live in
`world_shops` and are managed from v-admin → Editor → Stores. `config.lua` locations are seed data only
(pushed once with `INSERT IGNORE`). The server rebuilds `Locations` and **pushes them to every client**
on `v-world:server:changed('shops')`; the client tears down and rebuilds blips, peds and v-target zones
with no `restart`.

**Remaining.**
- Sell prices are static in `Config.SellLists` (no dynamic/market pricing, no in-game editor yet).
- Item **prices** are still loaded once at boot - a DB price edit needs a `restart v-shops`.
- Direct SQL against `items` and `shops`.
- No in-game management UI (`config.lua` literally says *"editable in-game later"*).
- The NUI silently ignores `{error='funds'|'space'}`.

### `v-crafting` ✅ - workbench crafting
**Done.** New module. Four **stations** (`workbench`, `ammo`, `cooking`, `electronics`) with map blips
and ground markers at fixed benches; **25 recipes** defined in `config.lua` (inputs → output, produced
count, progress time, optional `gate` = job/grade/permission). Opening a station and crafting are both
**server-authoritative**: `getStation` / `craft` re-check the player's real distance to a bench server-side
(`atBench`, uses `GetPlayerPed`+`GetEntityCoords`), verify every input for `qty × amount`, consume them,
then `AddItem` the output - **refunding the inputs if the output doesn't fit**. Per-player cooldown +
in-flight lock guard against spam/double-submit. EMBER NUI: recipe rows show each material as a
`have/need` chip (red when short), a quantity stepper capped to the craftable amount, and a progress bar;
the panel refreshes owned counts live after each craft. fr+en. Reuses `v-inventory`
`GetItemCount`/`RemoveItem`/`AddItem` exports - no new DB tables.

**In-game editable.** Recipes now live in `craft_recipes` and are managed from v-admin → Editor → Craft
(station, output item, produced count, duration, enabled, and a dynamic list of ingredient/qty rows).
`Config.Recipes` is seed data only; `rebuildRecipes()` re-derives the runtime list on
`v-world:server:changed('recipes')`, and `loadItemDefs()` refreshes labels on `…('items')`.

**Remaining.**
- The **stations** (bench coords, blips, markers) are still boot-static in `config.lua` - only the
  recipes are editable in-game.
- The craft progress time is client-side (feel only); the server enforces order + cooldown but not the
  full duration, so a crafted item can arrive up to `time` early if the client is patched. Low impact
  (inputs are still consumed atomically); move the timer server-side if it ever matters.
- No skill/XP progression on crafts (roadmap #9).

### `v-gathering` ✅ - resource nodes
**Done.** New module. Supplies the raw materials `v-crafting` consumes, closing the economy loop.
Three resource types (`mining`, `salvage`, `textile`) with map blips + ground markers at fixed **nodes**
(real GTA V spots: Davis Quarry, scrap/junk yards, Grapeseed cotton fields). Interact key starts a world
scenario for the resource's `time`; the harvest **cancels if the player walks off the node**. On completion
the server (`v-gathering:harvest`) **re-checks proximity** (`GetPlayerPed`+`GetEntityCoords`), enforces a
per-player cooldown, rolls a **weighted yield** (+ an optional rare bonus), and grants it via
`exports['v-inventory']:AddItem` with a space-check. No NUI - blips, marker and `v-notify` toasts only.
fr+en. No new DB tables.

**Remaining.**
- No tool requirement / tool durability on gathering yet (roadmap: pickaxe/axe, tool wear).
- No gathering XP / yield scaling.
- `gunpowder` has no gather source (only craftable/buyable) - add a chemical node or keep it shop-only.
- Node coords are boot-static in `config.lua`.

### `v-clothing` ✅ - clothing store
**Done.** Proximity store (**10 branded locations**, streamed shopkeepers), live on-ped preview with a
drag-orbit camera, per-drawable texture picker, buy-as-item, equip by using the item (swaps the worn
piece back to inventory), unequip from the wardrobe tab or via the `Unequip` export. **Admin
thumbnail scanner**: studio teleport, bare-vs-dressed pixel diff so only the garment survives on a
transparent background, crop + downscale in the NUI, one-shot-token HTTP upload (works around the
net-event size kick), lazy batched loading. 1848 thumbnails already generated. Arms are free.

**16 wearable slots** (was 8): masks, hats, glasses, **earrings**, undershirts, tops, arms,
**gloves**, **body armor**, **decals**, **necklaces**, **bags**, **watches**, **bracelets**, pants,
shoes - i.e. every component (1,3,4,5,6,7,8,9,10,11) and every prop (0,1,2,6,7) the appearance engine
already supported. `arms` and `gloves` deliberately share component 3: GTA renders one drawable per
component, so equipping gloves **evicts** bare arms (`sameSlot()` returns the displaced garment to the
inventory first, and aborts the swap if it can't fit). That is the honest model - the ped cannot wear
both, and pretending otherwise would leave a garment "worn" in the data but invisible.

**Everything is admin-editable.** Store locations live in `world_clothing` (position, heading, clerk
ped, blip, **job lock**, enabled) and the slots themselves in `clothing_categories`; both are seeded
from `config.lua` with `INSERT IGNORE` on first boot and then read from the DB. `rebuildCategories()`
re-reads the slots on `v-world:server:changed('clothcats')`, (re-)creates each slot's item definition,
binds its use handler once and pushes the list to every client; store edits re-push the locations and
the client tears down and rebuilds blips and peds - **no restart**.

**Buying is now server-authoritative.** `atStore(src)` re-derives the player's distance from the
server-owned ped and enforces the store's job lock, closing the buy-from-anywhere hole.

Exports: `Unequip(src, catKey)` / `GetWorn(src)` / `GetCategories()`.

**Remaining.**
- **Gender blindness.** Thumbnails are captured on the *admin's* ped and stored as one set, but
  freemode drawable indices differ between `mp_m` and `mp_f`. A female player browses images shot on a
  male ped, and a purchased item maps to a different garment on another model.
- The buy payload's `drawable` / `texture` are **client-trusted and unvalidated** (the server cannot
  call the ped natives), so arbitrary or dev components are purchasable.
- Buying with a full inventory fails **silently** - no notification and no locale key for it.
- Flat per-category pricing (editable in-game); no per-drawable price, rarity or stock.
- Direct SQL: `INSERT IGNORE INTO items` on boot.
- Thumbnails are 1848 loose base64 `.txt` files + an `index.json` under the resource.
- `screenshot-basic` and `oxmysql` are not declared in `dependencies{}`.

### `v-vehicles` ✅ - owned-vehicle persistence & keys
**Done.** New module, roadmap §5.1 step 1. Owns `character_vehicles` and is the **only** legitimate
path an owned vehicle takes into the world. Plates are **minted server-side** (`VR` + 5 digits, retried
against the unique index, fails loudly rather than handing out a duplicate). Condition - mod slots,
colours, neon, extras, livery, plate style, fuel, engine and body health - is captured from the client
that can actually see the entity and written back on store, on despawn, on disconnect and on a
`Config.SaveInterval` safety tick; every field is **coerced and clamped** server-side, so a patched
client can lie about its own fuel but cannot corrupt the row or reach another plate. `SpawnOwned()`
creates the entity **server-side** (OneSync) after checking ownership or keys, so a client cannot
conjure an owned car by asking. **Keys** are session-scoped (`Config.Keys.persist = false`) - a
courtesy, not an ownership record, which stays `character_vehicles.citizenid`; sharing them re-derives
both players' positions from the server-owned peds. The client-side engine cut is deliberately a
**soft** gate: the authoritative answer already came from `v-vehicles:hasKeys`.

**Showroom preview instance.** `client/preview.lua` creates the vehicle as a **local, non-networked**
entity at a point under the map and moves only the camera there - the player's ped never leaves, other
players see nothing, and the car cannot be entered or crashed into. That is what makes it an instance
rather than a spawned car. It is dressed with the **stored props from the row**, so the preview is the
car as it really is, and the camera distance is derived from the model's own dimensions so a bike and
a bus both frame sensibly. Shared surface - `v-garages` uses it today, the dealership next.

Exports: `GetOwned` / `GetOwnedByCid` / `GetVehicle` / `IsOwner` / `HasKeys` / `GiveKeys` /
`RemoveKeys` / `SpawnOwned` / `DespawnOwned` / `CreateOwned` / `IsLive` / `SetState` / `SetGarage`;
client-side `GetProps` / `ApplyProps` / `GetFuel` / `SetFuel` / `OpenPreview` / `ClosePreview` /
`RotatePreview` / `ZoomPreview` / `IsPreviewOpen`.

**Remaining.** No lockpick/hotwire path yet (the config reserves `hotwireTime` for it), no fuel
stations, no vehicle-damage → repair economy, and a vehicle whose entity vanishes is moved to
`impound` by the cleanup tick, which is a blunt rule that will want nuance once players test it.

### `v-licenses` ✅ - licences & permits
**Done.** New module, roadmap §5.3. The single answer to *"is this character allowed to do this"*.
The framework now has **three distinct permission concepts and they are not interchangeable**:
`v-core` permission is **staff**, a `v-jobs` job is **employment**, and a licence is **the law**.
Anything gating a real-world capability asks here.

One table (`character_licenses`: citizenid, type, status, points, issued, expires, issuer) and one
export - `Has(src, type)`. 12 types seeded (ID card, driving, motorcycle, HGV, taxi, boat, pilot,
weapon, hunting, fishing, medical, liquor), all **editable from the admin panel** (`license_types`):
key, issuer, price, validity in days, whether it needs a test.

Four states - valid / suspended / revoked / expired - plus a **demerit-points** system that suspends
automatically at the limit. Expiry is applied **lazily on read**, so a licence that lapsed while the
player was offline never reads as valid again.

**Who may issue** is the interesting rule: a *place* issuer (`cityhall`, `school`) serves anyone
standing there, but anything else is a **job** - an on-duty member of that job is the authority. That
is what makes a weapon permit a police decision rather than a shop transaction. Issuing to another
player re-derives both peds' positions server-side. A licence requiring a **test** can be renewed at
the city hall but never issued from nothing there; it is earned at the driving school.

The wallet lives in the **city hall panel** (new Licences tab) - the paperwork counter belongs at the
city hall, not in a module with its own UI.

Exports: `Has` / `HasByCid` / `Get` / `GetTypes` / `Grant` / `Revoke` / `Suspend` / `Reinstate` /
`AddPoints` / `LicenseForClass`.

**Remaining.** No actual driving *test* flow (the school grants it; the practical is a roleplay
gap), no physical ID-card item to show someone, and points are never added automatically because
`v-police` doesn't exist yet to add them.

### `v-vehicleshop` ✅ - dealerships
**Done.** New module, roadmap §5.1 step 3. Six dealerships (Premium Deluxe, Luxury Autos, bike, boat,
air, truck) each selling a **subset of categories**, and a **56-vehicle catalogue** with a deliberate
price ladder from a $9.5k Panto to a $1.65M Buzzard - including the four GTA electrics, so `v-fuel`'s
charging has customers.

Both the dealerships and the catalogue are `v-world` domains: model, label, category, price, **stock**
(-1 = unlimited), **required licence**, **job restriction** and enabled, all editable in the admin panel.

**The purchase is the sensitive part** and is ordered accordingly: the vehicle row is minted *first*,
then the charge; a failed charge deletes the row rather than gifting a car, and a failed mint has
charged nobody. One purchase in flight per player, so a double click cannot mint two cars. The
**licence gate is re-asked server-side**, never trusted from the browse payload.

**Test drive** is a *local, non-networked* vehicle on a timer that returns you exactly where you
started - it can never become an owned car. **Sell-back** pays a fraction of catalogue price scaled by
the car's actual condition, and refuses a vehicle that is still out of the garage.

The panel reuses `v-vehicles`' **showroom instance**: selecting a row stands the car up, drag to orbit.
A car you *cannot* buy still shows, dimmed, with the reason - the missing licence is the information.

**Automatic vehicle scan.** An admin runs a scan from the Editor → Vehicle catalogue; the
**client** enumerates every model it can actually spawn (base game *and* any addon pack
installed), reads its real class, display name, top speed and seat count, and suggests a
price from the model's own performance figures. The server keeps only what is missing from
the catalogue, re-validates every field, and holds the result until the admin reviews and
imports it - category and price editable per row. Adding a car pack is a two-click job
instead of hand-writing a config table, and **nothing reaches the catalogue because a
client said so**.

**Remaining.** No financing/instalments, no dealer-owned stock economy (stock is a number,
not a supply chain), and no player-run dealership.

### `v-mechanic` ✅ - per-part wear, odometer, diagnostics, repairs
**Done.** New module. Replaces "engine health" with a **20-part condition model** (12 for an EV):
engine, transmission, clutch, turbo, injectors, plugs, filters, fuel pump, radiator, exhaust, brakes,
suspension, steering, axle, tyres, battery, alternator, bodywork, glass - and for an electric car a
**traction battery, motor, inverter, BMS, charge port and coolant** instead of the parts it doesn't have.

**Wear has causes, not a timer.** Distance drives the baseline (per 100 km, scaled by each part's own
rate); **abuse** multiplies it - sustained redline hits the drivetrain, hard braking hits the brakes,
off-road hits the suspension; **collisions** damage the systems that took the hit, scaled by the body-health
delta; and **neglect** past the service interval accelerates everything. A gentle driver genuinely gets
more life out of a part, which is the only thing that makes parts interesting.

**You feel it before you read it.** Condition is applied through `SetVehicleEnginePowerMultiplier`,
`SetVehicleBrakeForceMultiplier` and `SetVehicleGripMultiplier`, ramping from `DegradeBelow` down to each
system's floor. A dead radiator bleeds engine health; a dead alternator kills the lights and stalls you.

**A real odometer** (`character_vehicles.mileage`, with `last_service`), incremented from actual distance
travelled and immune to teleports - a garage spawn is not mileage.

**Repair economy.** Every part is an **inventory item** (27 new ones, all craftable at the workbench or
the electronics bench), so a mechanic can stock or craft their own. A **shop** replaces a part outright
(part consumed + labour paid); a **repair kit** patches one back to 55 % in the field and refuses a part
below 15 % - a way home, not a free garage. A **full service** resets the interval and the consumables.
Shops are `world_mechshops` rows (position, blip, **job lock**, labour multiplier), editable in the admin
panel; a shop staffed by its own job is cheaper than the same shop used self-service.

Server-authoritative: the client observes the driving (it is the only side that can) but reports
**deltas only**, capped at 25 points per message, and the server never adds condition from a client
message. Every repair is priced, charged and consumed server-side.

Exports: `GetParts(plate)` / `GetShops()`; client `GetLocalParts` / `GetMileage` / `ScanNearby`.

**Remaining.** No tuning/cosmetic side (that is LSC's other half), no towing, no mechanic call-out job
flow, and `v-hud` shows neither the odometer nor a warning light yet.

### `v-fuel` ✅ - fuel types, consumption, stations
**Done.** New module. Owns everything fuel; `v-vehicles` keeps only the stored number.
**Four fuel types** - regular (91), premium (98), diesel and electric - each with its own price per
litre/kWh and an efficiency `rate`. What a vehicle accepts is derived from a **model override list**
first (the GTA EVs, the trucks) then its **class**; premium is accepted wherever regular is (same pump
family, better octane), everything else is a **wrong-fuel** mistake that is charged, announced and
**damages the engine** rather than silently ruining the car.

**Consumption** is load-based: an idle floor plus a term driven by real speed against the model's
estimated top speed, scaled by a per-class multiplier and the fuel's efficiency. A supercar at full
throttle drains far faster than a compact idling. Tank size is per class (16 L for a bike, 300 L for a
plane), which is what makes the litre maths and the price honest.

**18 stations** seeded from real GTA V pumps, including **3 electric charging points** (own blip, own
flow rate). Points live in `world_stations` - position, **which fuels are sold**, and a **price
multiplier** so a desert pump can cost more than a city one - all editable from the admin panel.

Server-authoritative: the price is re-derived from the server's own station and type tables, the
litres are **clamped to what the tank could physically hold**, and both the player *and the vehicle*
must be at the pump (the entity is re-read from its net id and measured). A patched client can ask for
9999 L; it gets billed for a tankful. The jerry can is an inventory item, and a failed grant refunds
the charge. fr+en.

**Electric is modelled as charging, not filling.** Three things make it behave like an EV: a **charge
curve** that tapers hard past 80 % (which is why "charge to 80" is a habit); **connector levels** - an
11 kW AC post, a 50 kW DC charger and a 150 kW ultra-fast unit, each with its own speed *and* its own
price per kWh, so the fast one is a real trade-off; and **battery health**, owned by `v-mechanic`'s
`battery_pack`, which derates usable capacity - an aged EV genuinely has less range. **Regenerative
braking** puts a little charge back when you slow down. The UI meters in kWh, not litres.

**Remaining.** No fuel theft/siphoning, no station ownership or revenue for a player-run business, and
`v-hud` does not show a fuel gauge yet.

### `v-garages` ✅ - store, retrieve, impound
**Done.** New module, roadmap §5.1 step 2. Garage points live in `world_garages` (editable from the
admin panel): id, label, **type** (`public` / `job` / `gang` / `impound`), the interaction point, a
**separate spawn point + heading** so a garage can sit indoors and deliver on the street, blip, a
**job/gang lock** reusing the clothing-store gate, a release fee and enabled. 9 real GTA V parking
structures ship as seed data, including the impound lot and the LSPD/EMS motor pools.

Server-authoritative throughout: `canUse()` re-derives the player's distance and job, `take` re-reads
the row's real `state`/`garage` instead of trusting the list the NUI was shown, and `store` re-reads
**the vehicle entity itself** from its net id, checks the plate on it and measures *its* distance -
parking a car you are not near is not possible. The impound fee is refunded if the spawn then fails.
Deleting a garage that still has cars parked in it is refused. EMBER NUI with per-vehicle
fuel/engine/body bars. fr+en.

**Remaining.** No per-garage capacity, and no shared/gang garage listing (it lists *your* cars only).
✅ The panel now shows a **live 3D preview**: selecting a row stands the car up in the v-vehicles
showroom instance, dragging the empty half of the screen orbits it and the wheel zooms.

### `v-core` - world policy

**World policy lives in the core** (`v-core/client/world.lua`). GTA's built-in police are
the single biggest thing standing between a server and immersive roleplay: an NPC cruiser
that spawns out of nowhere, a wanted star that paints the minimap red, a dispatch
helicopter overhead - none of it is played by anyone, and all of it overrides whatever the
actual police module was doing. **So it ships off**, and an operator turns back on only the
pieces they want.

`SetPoliceIgnorePlayer` alone is not enough - dispatch keeps running and keeps drawing
blips - so the twelve police dispatch services are disabled too, while the two emergency
ones (fire, ambulance) are a **separate** setting: a server can have NPC ambulances and no
NPC police at all. The wanted **ceiling** is what stops a star appearing; clearing one
after the fact still flashes the minimap, which is the immersion break being removed.

Ambient traffic is the same idea: random cops, GTA's scripted street events, trains, boats
and garbage trucks are each their own switch. Eight settings, applied live on every client.

A module can suspend the policy for a scripted chase or a heist through
`SetWorldPolicy` / `ClearWorldPolicy`; an override wins over the setting until cleared, and
`GetWorldPolicy` reports the two separately so a forgotten override is visible rather than
silently overruling the admin panel.

### `v-target` - the interaction eye, and the player's main menu

**The eye is the surface every other module writes into.** A player holds one key, looks at
something and picks an action; the alternative is one keybind per module and a printed
cheat sheet nobody reads. When the ray finds nothing targetable it offers the player their
own actions instead of an empty list, which is what makes it a menu rather than a context
menu.

**The ray is asynchronous and comes from the screen centre.** Both were wrong before and
both were felt rather than seen:

- The old probe was `StartExpensiveSynchronousShapeTestLosProbe` - the name is the warning.
  It blocks the game thread until the physics query answers, sixty times a second.
- The old ray was cast from the free mouse cursor, whose position was posted back from the
  page at most every 50 ms. The outline therefore lagged the visible cursor by up to three
  frames. That lag **was** the "not fluid" feeling.
- Casting from the cursor also meant moving the mouse onto the option list made the ray
  miss, so the options vanished before they could be clicked. Three stacked workarounds - a
  sticky target lock, a panel-hover freeze and a do-not-re-acquire rule - existed only to
  hide that. A centre ray cannot miss because you moved the mouse, so all three are gone.

The shape-test mask went from `-1` ("everything", which includes water and foliage) to world
plus vehicles, peds and objects: a bush in front of a car used to swallow the ray.

**Rows know which part of the thing you are pointing at.** The closest vehicle or ped bone
to the impact point is resolved every rebuild, so the boot offers storage, the bonnet offers
the engine, and a door offers that door and the seat behind it.

**Two kinds of refusal, and they are not the same.** A row gated by job, gang or permission
is not drawn at all - advertising the police menu to a civilian tells them what the police
can do. A row refused for a reason the player can act on (missing tool, too far, already
unlocked) is drawn inert with the reason underneath, because the alternative is a player
guessing why the action they expected is absent.

Movement stays live while the eye is open; only look and attack are suppressed. Walking up
to a car while deciding what to do with it is the normal case, not an edge case.

Seven settings, all read by the client. Options gate on items by reading a
`{ name = count }` map that `v-inventory` publishes on the player's own statebag: a callback
would answer a frame after the list was drawn, and a row that appears late reads as flicker.

### `v-3dsound` ✅ - the positional sound primitive

A primitive, not a feature. `v-music`, `v-radio`, `v-housing`, `v-police` and `v-drugs` all
want the same thing, and building it once is the whole point.

**The wire carries a name, a position and a range - never audio.** The bank is on every
client already, so the server broadcasts the *intent* and each client plays it locally,
attenuated by its own distance.

**Two banks.** Native GTA sounds cost nothing: no download, no streaming, already on every
client, and the engine does the 3D mix itself. A custom file is a download every player
pays for, so it goes through a small NUI page and only when nothing in the game sounds
right. No custom files ship; the mechanism and the instructions do.

**The rule the module exists to enforce:** anything a player can cause goes through
`PlayFromPlayer`, which takes the position **from the ped**, not from a payload. A sound a
client triggers and broadcasts itself is a griefing tool. Four entry points:
`Play` (a world position), `PlayFromPlayer` (the one gameplay modules should use),
`PlayOnEntity` (follows a moving car) and `PlayFor` (one person, not positional).

**Only listeners in range get the message.** Sending to everyone and letting each client
decide would put every sound on every wire, which is exactly what a proximity system exists
to avoid. A per-source per-minute budget catches the realistic failure - a looping script,
not a cheater.

Custom-file falloff is **linear with a flat head**: full volume up close, silent at the
edge. A squared curve sounds more natural but makes anything past half the range
effectively inaudible, which is not what a caller asking for a 60 m alarm wants.

Wired on arrival so it is not dead code: the cuff click in `v-police`, planting and
harvesting in `v-drugs`, and a private confirmation in `v-banking`. Five settings.

### `v-anticheat` ✅ - sanity checks on what a client must not decide

Six detectors, all server-side: **impossible movement** (metres per second between two
samples), **impossible health** (above the engine maximum, or armour over 100),
**explosions** (a blocked-type list plus a per-minute budget), **client entity creation**
(every legitimate spawn in this framework already goes through the server, so a client
creating entities at speed is already unusual), **money** (a change larger than any
legitimate payout, or one with no reason attached - which means it did not come from a
module here), and **weapon damage from further away than any weapon reaches**.

**The default action is `log`, and that is the most important line in the module.** An
anticheat that kicks legitimate players is worse than none: it costs a server its
population and the operator their trust in the tool. Everything ships noisy-but-harmless so
an operator can watch their own logs for a week before arming anything. Fourteen settings,
including the action and a staff tier that is never flagged - noclip and teleports are a
moderator's job, and flagging them is pure noise.

**`Expect` is the integration that makes it usable.** Six modules legitimately teleport a
player. A teleport detector that does not know about them flags the framework itself, so a
module declares its intent - `exports['v-anticheat']:Expect(src, 'teleport', 15)` - and the
window is deliberately short, because a grace window is a hole and a wide one is a wide
hole. `v-police` declares jail; `v-spawn` is covered by the load grace; `v-admin` and the
clothing scanner are staff-exempt.

**Everything lands in the existing audit log** through `Core.Log`, so there is no second
place to look and the admin panel's Logs tab already shows it.

**Found while wiring it:** the vehicle **test drive was entirely client-side, cooldown
included** - which means it was not a cooldown. It is a server callback now that re-derives
the dealer's proximity, checks the model is actually in the catalogue, enforces the wait,
and tells the anticheat to expect the two teleports and the local vehicle that follow.

### `v-core` - the integration layer
**`MenuOpened(name, keepInput)` now asserts the input policy.** `SetNuiFocus` is scoped to
the calling resource, but `SetNuiFocusKeepInput` sets a single **process-wide** flag that
`SetNuiFocus(false, false)` does not clear. One resource turning it on therefore leaked
game input into every page opened afterwards, for the rest of the session - and the
symptom is unmistakable once seen: typing "fume" into a phone message presses F, and the
player climbs into a nearby car mid-sentence. Only the interaction eye wants it on;
everything else wants it off, and off has to be *asserted* rather than assumed, because
the flag arrives in whatever state the last menu left it. `MenuOpened` is the one call
every page already makes, so the assertion lives there where it cannot be forgotten.


Three things turn a large framework into an extensible one, and none of them are exports.

**Services** answer "who provides banking?" rather than "what is the banking resource
called". Twenty-three ship. A server that replaces a module keeps every consumer working,
because no consumer ever named the resource. Two providers for one service is a
configuration mistake the core says out loud rather than resolving silently - picking one
would mean half the server talking to a module the operator thinks is off.

**Hooks** are a synchronous interception point another resource can veto or rewrite, and
they are the one thing FiveM events cannot do: event arguments are serialised across
resources, so a handler that mutates a table changes nothing. Hooks go through **exports**,
which do return values. `false` vetoes, a table replaces the payload, and a handler that
errors is **skipped rather than allowed to abort the chain** - one broken third-party
script must not be able to stop money from moving. Lower priority runs first, so a
validator rejects before a mutator bothers. Three ship on the money and job paths; the
value is in what a server adds.

**Discovery** is the registry: every module, service, hook, event and command in one call,
or `vdev` in the console. The question every integrator starts with is "what already exists
here", and the honest answer to that is not a documentation file that drifts.

Around them: `V.Enabled` / `V.SetEnabled` (a real resource stop, not a flag every module
has to remember to honour), `V.Require(resource, version)` which refuses **loudly and once**
rather than failing somewhere unrelated an hour later, `V.Command` which gates and registers
in one call, and the small things every script otherwise rewrites - intervals, timeouts and
statebag helpers.

### `v-housing` - property, tenancy and motels

**A motel is not a second module.** It is a row with `tenancy = rent`, a smaller stash and
no garage - the entire difference, and all three are columns. Writing it as its own system
would have meant two copies of doors, buckets, keys and storage.

**Entering is a teleport into a routing bucket**, derived from the property id. Without
buckets, two players in "the same" apartment stand in the same room; with them, one
base-game interior serves every property that uses it and nothing has to be streamed.

**Everything inside is reused, not reimplemented.** Storage is a `v-inventory` stash keyed
by property. Keys follow the `v-vehicles` model - giveable to somebody standing in front of
you, revocable, checked server-side, because a key list on the client is not a lock. The
stash is opened **through v-housing** rather than letting the client name a stash id, since
a client that could would open anybody's.

**A failed rent locks the door; it never deletes the property.** Deleting somebody's stash
because they were poor for a day is how a server loses a player, and a locked property can
be paid off with everything exactly where they left it. Arrears are derived from
`paid_until` rather than ticked, so a restart loses nothing and a tenant offline for a week
owes exactly a week.

Deleting a property somebody lives in is refused outright - the row is what their storage
hangs off. Eleven settings, and **Editor - Properties** for the rest.

### `v-phone` - iFruit, and what a shell has to refuse to do

**The phone is a shell.** Messages and contacts are the only things it owns; every other app
is a thin view over the module that already holds the data, and the client asks that module
directly rather than going through v-phone. Proxying a balance through the phone would put a
second copy of the bank's rules in the phone, and a second copy is a second answer.

Building it turned up two places where being a shell means shipping **less**, not faking more:

- **The jobs app is read only.** `v-cityhall:take` is gated on standing at a desk, and it
  should stay that way - browsing vacancies from a sofa is fine, being hired from one is not.
  The vacancy list comes from a new `v-cityhall:OpenPositions()` export rather than a second
  copy of "what counts as open".
- **The camera ships disabled with no upload target.** Where a photo goes is an operator
  decision; a default would be one made for them.

**A number is a column on the character**, minted server-side in a configurable format and
retried on collision, because two characters made in the same second would otherwise share an
inbox. Numbers address contacts, calls and messages - never the citizen id, which is a
database key a player should not be trading.

**Server-authoritative in exactly two places.** A message is stored and relayed by the server,
because a client that could write another player's history could forge it; every query is
scoped to the requester's citizen id in SQL, so a client cannot ask for a conversation it is
not in. A call is routed by the server, so ringing somebody does not depend on the caller
knowing where they are. **The phone does no audio at all** - a connected call hands both ends
to `v-voice`, which owns the Mumble channel, and the hang-up releases it even if the UI never
saw the start, because a call that ends without releasing the channel leaves a player audible
to strangers across the map.

**Gestures, and where a drag starts deciding what it means.** The phone is driven by a
mouse, so a swipe is a click-drag - but the rule is the real one: the **bottom edge** is
the home gesture (and, held for a moment first, the app switcher), the **top edge** is the
notification shade on the left and the control centre on the right, a drag in from the
**left edge** inside an app goes back, and sideways on the home screen turns the page. None
of those need a button, which is why iOS uses them.

**The side buttons work, and they control real things.** Power locks and wakes. Volume
moves the volume of whatever `v-music` says this player may control, and says "nothing
playing" when there is nothing - rather than moving a number attached to silence. The
Action button opens an app the player chose in Settings, and says so when they have not
chosen one.

**An app is in one of three states, and the third is what makes a store mean anything.**
`required` cannot be removed - a phone with no Phone app is a brick, and one with no store
cannot get anything back. `stock` is there unless the player removed it. **`optional` is
absent until it is downloaded**, which is where the social apps live: a network you joined
is worth more than one you woke up already signed into. The two lists behind it start from
opposite defaults, so they are stored separately - a stock app is recorded when it LEAVES,
an optional one when it ARRIVES. That is also why an app an operator adds next month
appears by itself while a new optional one waits to be found.

The store front is a store front: a featured card holding something you do **not** have
yet (a shop window showing what you already own is a shelf), rows grouped by category in a
fixed order so it does not reshuffle when you install something, a search field, and a
product page per app with its icon, category, developer, status and description.

**FruitStore separates two decisions that look like one.** The **operator** decides what is
available (Editor - Phone apps, plus the job and gang gates); the **player** decides what
to keep. What is stored is what they *removed*, not what they installed, so an app an
operator adds next month is simply there rather than needing every existing character to
go and find it. A handful of apps are `required` and refuse to be removed, because a phone
with no Phone app is a brick.

**The card is v-banking's, not the phone's.** It is minted once per character, retried on
collision, and a transfer accepts it as a destination - for exactly the reason phone
numbers exist: a citizen id is a database key, and asking players to trade one so they can
be paid is asking them to hand over an internal identifier.

**The card is ordered, not issued.** It used to be minted the first time somebody opened
their wallet, which meant every character silently had one they never asked for. It is now
a counter errand at the bank, charged a configurable fee, refunded if the mint fails - and
the wallet says where to get one rather than drawing an empty rectangle.

**A wallpaper can be a link, and the hosts are the operator's decision.** A linked image is
a URL a client fetches, so it goes through an allow-list exactly as music does, and it
ships narrow. Rejected rather than silently rewritten: quietly turning somebody's link into
one that works is worse than telling them it is not permitted.

**The camera is as real as the operator made it.** It uses `screenshot-basic`, which
already ships, and uploads to the destination the `cameraUpload` setting names. With no
destination configured there is nowhere for a photo to go, and the app says so - a data URI
in a metadata column would be megabytes per shot.

**Folders, arrangement and the shape of the device.** Hold a tile to arrange, drop one onto
another to make a folder; the layout is a list of items rather than a list of apps, and
anything installed but missing from a saved layout is appended, so an app added next month
appears at the end rather than vanishing. Size and side are per character, because a small
screen and a left-handed player are not the same person's problem.

**Battery and signal are both decided on the server, from where the player actually is.**
A client that reported its own signal would report five bars from inside a tunnel, and one
that reported its own charge would never go flat.

The battery takes eight real hours to empty, configurable, and drains roughly three times
faster with the screen on. **It only drains while the player is connected** - a phone
genuinely goes flat in a drawer, but so does the ability to charge it, and coming back from
a week away to a dead phone with nothing you could have done about it is a punishment for
logging off rather than a simulation. The level is carried with the character, so a phone
that was flat when you left is flat when you return. Charging happens at a **charger**
(a `world_chargers` row), **in any vehicle**, or **inside a property you hold a key to**;
the last two follow the player rather than a coordinate, which is why they are code and not
rows. A **power bank** is one charge and then it is spent.

**Dead zones are a ceiling, not a penalty.** `bars = 0` is no service at all; zones overlap
deliberately and the worst one wins, so a tunnel inside a weak-signal desert is still a
tunnel. Without a signal nothing leaves the phone: messages refuse, calls refuse, and a call
to somebody standing in a dead zone refuses as well - checked on the server, so standing in
the tunnel actually means something. Eight seed zones at places a story would put you:
Chiliad, Raton Canyon, Fort Zancudo, Humane Labs, the Los Santos tunnels, and three more.

Both are `v-world` domains, edited from **Editor - Phone chargers** and **Editor - Dead
zones** like every other content list. **Thirty domains.**

**Apps are a registry, not a list.** `RegisterApp(id, { label, icon, page, slot, dock })` and a third
party ships its own app without touching v-phone. What the operator controls is separate and
lives in `world_apps`: enabled, ordered, and gated by job or gang, edited from **Editor - Phone
apps** like every other content list. Three gates decide whether an icon appears, and they are
not interchangeable - the operator's switch, the owning module actually running, and the
job/gang on the row. An app whose owner is stopped is hidden, because an app that opens onto
nothing is worse than an app that is not there.

**The shell is iOS 27, and the glass is composed rather than sampled.** Lock screen with a
notification stack, a Dynamic Island that expands into a live activity for a call, a paging
home grid with a dock, iOS inset-grouped lists, large titles that collapse on scroll,
sheets, banners and a control centre. `backdrop-filter` is not available - FiveM's CEF
renders it as an opaque black box - so every glass surface is built from a translucent
tint, a bright half-pixel rim, a specular sheen along the top edge and an inner shadow.
Against the gradient wallpapers that reads as glass and costs nothing to draw. An app opens
by scaling out of the icon that launched it, which is most of what separates "an iPhone"
from "a list on a dark background".

**What iOS 27 changed, and what that meant here.** Apple's own summary of the update is
that it rebuilt the foundations of the material rather than its shape, and three of those
changes are visible enough to be worth copying: the glass **diffuses what is behind it
more aggressively** so text stays legible, it gained a **darkened edge** outside the bright
rim, and its **specular highlights got brighter**. There is also a **uniform toolbar** when
content scrolls under a floating bar, instead of a hairline.

The headline user-facing change is a **transparency slider**, from ultra clear to fully
tinted, and that is the part worth being careful about: it would have been easy to ship as
a fade on one overlay. It is a stored per-character preference instead, exposed as a single
CSS custom property, and **every alpha in the material is a `calc()` off it** - tint,
sheen and rim all move together. Moving the slider restyles the phone rather than dimming
a layer.

**Fourteen apps, and every one of them is a view of something real.** Maps turns v-world's
public location lists into a waypoint, which is the one thing a phone map is for. Music
lists what v-music says this player may control and sends it the same actions its own UI
does. Property exists because **a failed rent locks a door rather than deleting a
property**, so being able to pay it off from anywhere is what makes that rule survivable.
The MDT is police-only by default, and the app gate only decides whether the icon is drawn
- `isCop` is re-checked on every call. The calculator is the one app that owns itself, and
it earns its place: splitting a payment three ways is something players do constantly and
currently do in their heads.

Nothing here was invented to fill the grid. A weather app was considered and dropped
because no module answers for weather, and an app with nothing behind it is worse than an
empty space where one could go.

**The pass that made it read as iOS, and what it actually consisted of.** App icons were
the single biggest tell: a stroke outline on a flat tint reads as a web dashboard, so
every built-in app now has a vivid gradient squircle with a **filled white glyph**, drawn
from one table in the SDK that third-party apps inherit just by naming an icon. The
palette is the system's, exactly: grouped background, system blue, green, red, orange,
indigo - and Settings carries the per-row coloured icon tiles the real app is recognised
by. The keypad is the real keypad (light grey circles, letters under the digits, green
call), the calculator is the real calculator (black, orange operators, grey functions),
received bubbles are the exact grey against system-blue sent, and banners, lock-screen
notifications and the calendar widget sit on **light material** rather than dark glass -
with the weather widget on Weather blue. Motion: icons **jiggle** while being arranged,
drilling into a thread **pushes in from the right**, and a **spotlight** above the dock
finds an app by name, because a sixth page of icons is where apps go to be forgotten.

**The control centre contains only real controls.** A tile that toggles nothing is
decoration, and decoration shaped like a switch is a lie about what the phone can do.

**A third-party app is one HTML file and eight lines of Lua.** `sdk.js` exports `PhoneUI`,
the component kit - and it is the *same object the built-in apps draw themselves with*, so
an app somebody else ships cannot drift out of looking native - plus `Phone`, the bridge:
title, toast, notify, badge, storage, contacts, message, call, and calls into the app's own
server code. `Phone.request('save', x)` becomes `V.Callback('<appId>:save')`, with the id
supplied by the phone rather than the message, so an app cannot reach
`v-banking:withdraw` - not because the phone refuses, but because the name cannot be
formed. Per-app, per-character storage means most apps need no table and no server file at
all. `v-phone/apps/example` ships as the worked example.

Ten settings. The conversation list is three plain queries rather than one with window
functions: MariaDB only grew those in 10.2, and working on the operator's database matters
more than a clever statement.

### `v-social` - the shared layer, and why the social apps waited for it

The social apps were refused twice, and the reason was always the same: they need data
**shared between players** - handles, posts, likes, matches - and the phone is a shell
that owns nothing shared. This module is that missing owner. The apps went from
impossible to thin views the day it existed.

**The brands are Rockstar's own.** Bleeter and Snapmatic ship in the game; inventing a
parallel Twitter would break the world every other module is set in. Hush is the dating
service the same universe already jokes about.

**Bleeter and Snapmatic are one feed.** One table with a `kind` column; one app shows
`text`, the other shows `photo`, and both share the same card, the same likes and the
same account. Two modules would have been two copies of everything.

**Three identity rules, and they are the architecture:**

- **The author is always the server's idea of who called**, never a payload field. A
  client that could name the author of a post could bleet as the mayor.
- **Handles address people; citizen ids never leave the server.** Every answer resolves
  ids to handles before it resolves at all. A Hush candidate travels as an opaque ref the
  client hands straight back.
- **A match is the only place identity crosses**, because both sides asked: each gets the
  other's first name and number - through v-phone, which owns numbers - and each receives
  a message from the other, so the conversation already exists when they open it.

A like is a toggle keyed on (post, citizen), so double-clicking can never count twice. A
Hush pass is recorded like a like, or the same face would come back on every open; the
daily ceiling counts likes only, because saying no is free. Image links go through the
same host allow-list as wallpapers, for the same reason. Six settings.

### `v-music` ✅ - boomboxes, jukeboxes and the car stereo

Same rule as `v-3dsound`: the server sends a URL, a start timestamp and a position, and
every client plays it locally at the volume its own distance earns. **Nothing streams
through the server.**

**Sync is by timestamp, not by streaming.** A source carries when it started; a client
arriving late computes its own offset and seeks there, so it joins mid-track instead of
restarting it for everybody. Pausing stores the elapsed time and resuming shifts the start
time back by it - without that, a pause would restart the track for every listener.

**The difference from `v-3dsound`:** a one-shot fires and forgets, but music is continuous,
so the volume has to track the listener as they walk. A 250 ms loop does it - well below
what an ear reads as a step, and well above what a per-frame loop would cost for something
that changes only as fast as a person moves.

**Three kinds, one key.** In a vehicle it is the stereo, standing at a jukebox it is the
jukebox, otherwise it is your boombox: two keys would be one for a player to forget. A
boombox is an item you drop and becomes a **local, non-networked prop** for the same reason
the drug plants are - it is server state, and a networked entity would let any client
delete somebody else's. The car stereo is **keys, not proximity**: a passenger should not
be able to hijack it. Jukeboxes are a `v-world` domain seeded at four real Los Santos
venues, with an optional job lock so a bar's playlist belongs to the staff.

**The honest constraint, made a setting:** arbitrary URL playback is a moderation problem,
not a technical one. The allow-list ships narrow, blank means deliberately open, and every
play is logged with who asked for it. A server that lets anyone stream anything to everyone
in earshot will spend its first week moderating audio.

Ten settings, and the audio pool sits **outside** the panel in the NUI so closing the
interface does not stop the music.

### `v-radio` ✅ - the handheld, and `v-voice` goes multi-channel

`v-voice` owns the channels: who may join, who may transmit, and the Mumble plumbing.
`v-radio` is deliberately the other half - **the object in your hand** - and it never
decides a permission. It asks `v-voice`, which asks `v-factions` and `v-police`. A device
that decides its own channel list is a device that can be edited.

**The multi-channel change landed where it belonged, inside `v-voice`.** One joined channel
became a **set of listens plus a single transmit target**, which is how a real handheld
works and what an officer monitoring dispatch and a tac channel needs.
`MumbleAddVoiceChannelListen` already accepts several; the authority check simply runs per
channel. Two details make it behave:

- **The first channel joined becomes the transmit target**, so a player who only ever uses
  one never has to learn that the distinction exists.
- **The server sends the whole set on every change and the client reconciles**, adding what
  is new and dropping what is gone. Sending deltas would let the two disagree about what is
  being monitored, and only one of them would be right.

**A ceiling on how many channels one radio monitors** (a setting, four by default). Without
it, "listen to everything" is strictly better than choosing, and the device stops being a
decision.

**The device:** the channel list filtered to what you may actually use, a keypad of presets
saved in KVP (a preset is a personal convenience, not world state, and should not cost a
round trip), and a transmit selector that only offers channels you already monitor - which
is exactly what the server enforces. Leaving a job leaves its channels, and an admin
re-gating a channel takes the device off it, because it follows `v-voice`'s push rather
than polling.

**A setting worth naming:** *show which job or gang a channel belongs to*. Turning it off
hides the padlock, so a player has to know a channel exists to go looking for it.

### `v-voice` ✅ - proximity, radio channels and phone audio

FiveM already ships a Mumble voice server, so this module implements no audio. It decides
**who hears whom, and how loudly** - the framing that keeps it small.

**Three proximity steps** (whisper / normal / shout) on a key. Both Mumble distances are
set, not one: input is how far your voice carries, output is how far you hear, and setting
only one produces the classic "I can hear them but they cannot hear me". The ranges are
**settings, resolved server-side** - a client that sets its own range has a megaphone.

**Radio channels are the part that must be authoritative.** A client that picks its own
channel can listen to the police, so joining is a callback, and permission to transmit is
re-asked on **every keypress** rather than cached - it is the only moment that can know the
player still holds the radio, is still in the job, and is not cuffed. The gate reuses the
existing job and gang concepts plus a minimum grade; there is no third permission list.
Channels live in `world_radio` and are edited in **Admin → Editor → Radio channels**.

**Consequences wired through the rest of the framework:**
- `v-status`: bleeding past a threshold multiplies the range down, because a wounded player
  should not be shouting across a street. The HUD says so, since a player who does not know
  they are quiet reports it as the voice system being broken.
- `v-police`: a cuffed player cannot key the radio.
- `v-inventory`: transmitting needs a radio item, so being disarmed of it is a real event.
- Leaving a job or a gang leaves its channel through `onJobChange`, with no bookkeeping.
- An admin editing a channel takes anyone no longer eligible off it immediately, rather
  than the edit doing nothing until they relog.
- `v-hud` renders a small indicator: proximity step, talking, radio, muted, and the channel.

**The phone gets its own Mumble channel** (`PhoneCallStart` / `PhoneCallEnd`), so a call
carries across the map and is inaudible to somebody standing next to you. `v-phone` will
call those two exports and nothing else.

**Staff mute** is keyed on the citizen id rather than the session, so it survives a relog,
and it needs no access to the voice server.

Nine settings. `server.cfg` gained the three convars without which the built-in voice is
not positional at all - which would have defeated the whole proximity model.

### `v-drugs` ✅ - plantations, street dealing, demand and heat

The illegal loop already shipped as a **static** chain: fixed gather nodes, a craft bench
and a buyer who always paid the same. This module adds the two parts that make it a game.

**Plantations a player places and can lose.** Using a seed starts a placement prompt; the
plant is a row, and its position is taken from the *player*, never from the payload - a
client that picks its own coordinates can plant through a wall or across the map. Growth is
derived from timestamps rather than ticked, so a restart mid-grow loses nothing and a crop
keeps growing while nobody is online. Skipping the watering **wilts** rather than kills: a
bad grower is punished, not wiped. Anyone can harvest anyone's plant for a configurable
share, and **the owner is told** - anonymous theft would be free theft.

The props are **local and non-networked**. A plant is server state; spawning it as a
networked entity would let any client delete somebody else's crop.

**Street dealing that pushes back.** Using a sellable drug offers it to whoever is standing
next to you - no menu, because the point is standing somewhere you should not be. Price is
`base × refinement × district demand × turf bonus`, and **demand decays per district as you
sell into it**, recovering slowly. The same corner stops paying, so dealers have to move.
That is the whole design.

**Heat is the pressure side.** It rises with every sale, decays when you stop, makes peds
refuse above a threshold, and drives a bust chance that scales from a floor to a ceiling.
Getting caught is what a long session on one corner earns you, not bad luck on the first
sale. A bust puts a temporary blip on **police** maps only, through `v-police:IsCop`.

Sales pay **dirty money** by default, so the payout has to go through the launderer that
already shipped in `v-shops` - which is what connects dealing to the banking side instead
of paying into a clean balance.

Substances are one `world_drugs` row each, carrying both the growing side and the street
side, because an operator thinks in substances rather than subsystems. Edited in
**Admin → Editor → Substances**; fifteen settings.

### `v-police` ✅ - cuffs, escort, search, charges, jail, MDT

**Police is a job, not a permission.** Staff are not police, and an admin who wants to
arrest somebody should be given the job. Every callback checks the job (and duty, by
default), never a permission tier.

**The penal code is data.** Every server rewrites its charge sheet first, so charges live
in `world_charges` - code, label, category, fine, jail minutes, licence points and which
licence those points hit - and are edited in **Admin → Editor → Penal code**. Twenty-one
charges ship as a starting point.

**The client sends codes; the server derives the sentence.** The NUI shows a running total
as a preview only. A client that could name its own fine could also name a negative one.

**Only a cuffed detainee can be escorted**, otherwise "escort" is a way to move any player
anywhere against their will. **Seized goods leave the world** rather than moving to the
officer - evidence that lands in a policeman's pocket is indistinguishable from theft.
Search reads `v-inventory`'s own `GetSearchable`, which already never exposes the hidden
pocket; re-deriving that rule here would fork it.

**Jail is a row with an absolute release time, not a timer.** A timer dies with a restart
and a relog would be an escape. The sentence is re-read on spawn, and the client can only
release itself when the row agrees.

**A fine that cannot be paid is a debt, not a failed arrest** - the sentence stands and the
record is marked unpaid. Fines can optionally be paid into the department's `v-factions`
treasury, which closes the loop between policing and the faction economy. Licence points
reach `v-licenses` through the charge row rather than a hardcoded list here, and impound
goes through `v-vehicles`/`v-garages` so the owner can buy the car back at the lot.

The **MDT** looks a citizen up by name or id and shows their record, active warrants,
licences (with points) and registered vehicles; warrants can be issued and cleared. Nine
settings, including whether charging clears outstanding warrants.

### `v-gangs` ✅ - territory, capture and influence

Membership, ranks and the treasury are **not** here - they are `v-factions`'. This module
adds only what the illegal side does not share with a legal faction: **territory**.

**The `gangs` table shipped in the schema and nothing ever filled it**, so `v-factions` and
the boss menu had no illegal organisation to work with. It is seeded now with the canonical
Los Santos gangs (Ballas, Vagos, Families, Marabunta Grande, The Lost MC), each with four
ranks, and `v-world` gained a full `gangs` domain mirroring `jobs` - **Editor → Gangs**.

**A turf is a circle, not a polygon.** The capture rule only ever asks *who is standing
inside*, and a radius answers that with one distance check per player instead of a
point-in-polygon test every tick.

**Influence belongs to whoever holds the turf; a rival wears it down rather than taking
it.** The turf only changes hands once influence reaches the floor. That is what makes a
contested turf a fight instead of a race to a number - and standing your ground as the
owner slows the bleed rather than stopping it, so being outnumbered still costs you.
Unattended influence decays, so a turf has to be *held*, not just taken once. A group
multiplier is capped, because a mob should not capture instantly.

Ten settings drive all of it, and the whole pass is admin-tunable at runtime: the interval
is re-read every pass rather than cached, so a change takes effect without a restart.

**Blips are per-gang coloured** - a radius blip for the territory and an icon on top
carrying the name, the holder and the current influence.

Exports the rest of the roadmap needs: `TurfAt(coords)`, `GetOwner(id)`, and `InOwnTurf(src)` -
the one call a turf-gated drug sale or a gang stash will want. `SetOwner` hands a turf
over without a capture, and is logged like any other ownership change; it is what
**Editor → Territories** uses.

### `v-bossmenu` ✅ - the panel a faction leader actually needs

Opens on **F6**, and only for somebody who is a boss of a job or a gang. Three panes over
one server payload: **members** (rank, online, on duty, promote, dismiss), **hire**, and
**treasury** (deposit, withdraw, movement history, pay salaries by hand).

**Gated on rank, not on admin permission.** The menu asks `v-factions` who the caller is a
boss of and re-derives it on every action. An admin is not a boss - giving staff this panel
is how a framework ends up with two different ways to move the same money.

**Hiring is done to somebody standing in front of you.** The candidate list is built
server-side from a radius, and the hire call re-derives that list rather than trusting the
citizen id in the payload - otherwise the menu would be a way to recruit anyone on the
server from anywhere on the map.

**The panel owns no data and re-reads instead of guessing.** Membership and the treasury
both live in `v-factions`; every action posts and the whole state is re-read from the
answer, so the UI can never drift from what the server actually did. The rank dropdown only
offers grades at or below the caller's own - the server enforces it, and offering more
would just be a button that always fails.

**Deposit takes the money first, then credits the treasury**, refunding on failure. The
other order mints money whenever the treasury write fails. Manual salary payment withdraws
**once per member** so a treasury that runs dry pays the first few rather than failing the
whole run and paying nobody.

Eight settings, each action independently switchable: hire, dismiss, rank changes, treasury
movement, manual salaries, hiring radius, salary multiplier, and whether gangs get a menu.

### `v-factions` ✅ - membership, ranks and treasuries

One engine for legal factions (PD, EMS, mechanics) and illegal ones (gangs, mafias). They
differ by **which table their definition lives in** - `jobs` or `gangs`, both already
editable from the admin panel - and by nothing else. That is what stops `v-police` and
`v-gangs` from each growing their own copy of membership and treasury code.

**Boss without a data migration.** The schema has always documented an `isboss` grade flag
and no seed ever set one. Rather than migrating every organisation, the highest grade is
the boss by default and an explicit `isboss` overrides it - so an operator who starts
flagging grades gets exact control, and everyone else keeps a working chain of command.

**The treasury is a real account, not a number in a config**: `faction_accounts` plus
`faction_transactions`, because a balance nobody can explain is indistinguishable from a
duplication bug. Every movement is signed, reasoned and attributed. The admin panel gets
**Editor → Treasuries**, where the balance is shown but never typed: the only way it moves
is an adjustment that lands in the log with a reason beside it.

**Rank is not permission.** Every mutating export takes the acting source and re-derives
that player's rank *in that faction* - an admin is not a boss, and the two are different
powers. A boss cannot promote anyone above themselves, which is how a faction gets taken
over from the inside.

**Salaries can come out of the treasury** (`TrySalary`, off by default). It returns three
distinct answers on purpose: `nil` = this server does not use treasury pay, `true` = the
treasury covered it, `false` = it could not. Only the last withholds the wage - collapsing
`nil` and `true` would silently double every salary the moment the feature was switched on.

### `v-vehicles` - driver controls, locks and lockpicking

**Indicators and hazards** have no native, so the blink is ours: one timer for every
vehicle rather than one per light. **Headlights and high beams are deliberately not
rebound** - GTA already cycles them on `H`, and taking a control the player already knows
is worse than leaving it. What did change is that `v-inventory`'s search now ignores `H`
while you are in a vehicle: frisking somebody from the driver's seat was never a thing, and
the key belongs to the lights.

**The engine is a server answer.** With `lockEngine` on, no keys means no engine, and that
is not a decision a client makes about a car it does not own. **Getting out leaves it
running**: GTA cuts the engine on exit, and a driver who left it idling expects to find it
idling, so the script puts it back.

**Seats cycle to the next free one** rather than opening a menu - the choice is almost
always "somewhere else in this car".

**The lock lives on the server**, keyed by plate and mirrored to clients, because whichever
client happens to own the entity is not the right authority. A key reaches six metres:
unlocking a car across a car park is how a key becomes a wand.

**Lockpicking is the illegal counterpart**, and everything that decides anything is
server-side - including the wait, so a client that skips its own animation gains nothing. A
failure can snap the pick, and **a failure is what draws attention**: a clean job should be
quiet, or there is no reason to be good at it. The alert reaches police only, through
`v-police:IsCop`. Eight settings cover the whole of it.

### `v-rentals` ✅ - short-term vehicle hire

Rental counters at four real GTA V locations (LSIA, Vespucci, Sandy Shores airfield, Paleto
Bay), each a `world_rentals` row: position, spawn point + heading, a **category list**, an
optional job lock, blip and enabled flag. Editable from **Admin → Editor → Rental points**.

**Rentability rides on the vehicle catalogue, not a second list.** `vehicle_catalogue` gained
two nullable columns - `rent_deposit` and `rent_fee`. NULL means *not for hire*; a value makes
the model rentable wherever a point's category list allows it. An operator edits one vehicle
list, in **Editor → Vehicles**, and blank never collapses to 0 (a free hire with no deposit is
a very different thing from no hire).

**What stops it being a free car:** a rental never creates a `character_vehicles` row. It gets
a temporary `RENT###` plate - deliberately recognisable, so police can tell a hire car from an
owned one - keys through `v-vehicles` (whose key system is not ownership-gated), and a row in
`vehicle_rentals` with an `expires_at`. The deposit comes back only by returning the car to a
rental point in time.

**Expiry runs on its own clock, not a per-rental timer**: a timer dies with a restart, a row
does not. On boot, any hire still marked `active` is closed as forfeited - otherwise a
restart mid-hire would leave a row that blocks that player from ever renting again.

Server re-derives everything: proximity (of the *vehicle*, not just the player, on return),
the price from the catalogue, the driving-licence gate, and the one-hire-at-a-time rule.
Eight settings: range, hire length, warning threshold, refund-on-time, licence requirement,
deposit and fee multipliers, blips.

### `v-world` ✅ - admin-editable world content

**Done.** The data layer behind the v-admin **Editor** tab. Owns five domains - `blips`, `shops`,
`jobs`, `items`, `recipes` - and is the only writer for `world_blips`, `world_shops`, `craft_recipes`,
`jobs` and `items`. `ensureTables()` creates its own tables at boot, then each domain is loaded into
memory. Three permission-gated + audit-logged callbacks:

```lua
Core.TriggerCallback('v-world:list',   cb, domain)          -- rows for the editor
Core.TriggerCallback('v-world:save',   cb, domain, row)     -- insert or update, validated
Core.TriggerCallback('v-world:delete', cb, domain, id)      -- protected deletes
```

After a write it reloads the domain, pushes blips to clients, and fires the server-to-server event
**`v-world:server:changed(domain)`** that `v-shops`, `v-jobs`, `v-inventory` and `v-crafting` listen to
so they rebuild live. Consumers seed their `config.lua` defaults through
`SeedShopLocations` / `SeedJobs` / `SeedRecipes` (all `INSERT IGNORE`) on first boot, then read the DB.

Exports: `IsReady` / `GetBlips` / `GetShopLocations` / `GetJobs` / `GetItems` / `GetRecipes` /
`SeedShopLocations` / `SeedJobs` / `SeedRecipes`.
Client: renders `world_blips` and re-renders on `v-world:client:blips`.
Validation lives server-side: names are slugged (`[^%w_]` stripped, 50 chars), labels capped, numbers
clamped, item `name` immutable after create, an item referenced by a recipe cannot be deleted, and
`money` is undeletable.

**Remaining.** Vehicles / gangs / gathering nodes / craft stations / price lists domains; a map-picker
UI instead of "use my position"; per-domain import & export.

### `v-cityhall` ✅ - city hall job desk

**Done.** New module. Three real civic buildings (LS City Hall, Sandy Shores, Paleto Bay) with a blip, a
clerk ped on a clipboard scenario, a ground marker + E prompt and a **v-target** zone. The NUI lists the
**open positions** - every job in the `jobs` table that is **not** `whitelisted` and not in
`Config.NeverPublic` - with its entry grade, starting pay and rank count, plus the player's current
contract and a **Resign** button.

Server-authoritative: `atCityHall(src)` re-derives the player's real distance from the server-owned ped,
and `take` **re-computes the open set server-side** rather than trusting the list the NUI was shown, so a
patched client cannot hand itself a police badge. The optional `Config.HireFee` is refunded if `SetJob`
then fails. Hires at grade 0 only. Both actions are audit-logged. fr+en.

**Remaining.** No application/interview flow (it's instant hire), no per-job player cap, no ID card or
civic paperwork - the desk only does jobs today.

### `v-admin` ✅ - management panel (F10)
**Performance.** The panel grew to 8 rail tabs, 13 editor domains and a settings registry,
and four things scaled badly: every keystroke in a search box rebuilt the whole list
synchronously; rows were appended one at a time (one reflow each); saving one setting
refetched the entire registry; and the editor truncated at 300 rows **silently**, which
reads as "that is everything". All four are fixed - searches are debounced (140 ms), lists
paint through a `DocumentFragment`, a saved setting is patched in place (one round trip
instead of two), and the list pages at 200 with an explicit **"show more (N)"**. The editor
subtabs are grouped **World / Economy / People** rather than 13 buttons in one wrapping row.

**Done.** Permission-gated NUI. **Dashboard** (uptime, players, resources, characters). **Players**
(searchable roster; goto / bring / heal / freeze / kick with reason / give money / give item /
set permission - superadmin only). **Scripts** (state of every module, restart / stop / start,
protected resources shielded). **World** (weather + time synced via `GlobalState` including late
joiners, vehicle spawner, server announcements). **Logs** (last 60 rows, category filter,
parameterized query). Every action validated server-side and audit-logged.

**Editor tab ✅** - the content-management surface `RULES.md` §3.6.2 requires. A rail tab with five
subtabs (**Blips / Stores / Jobs / Items / Craft**), a live search box, a list of existing rows and a
per-domain form: create, edit, delete, plus **"use my position"** for anything with coords. It is a thin
client over `v-world:list` / `v-world:save` / `v-world:delete` - the admin panel holds no content logic
of its own. Item forms lock the internal `name` when editing; recipe forms build ingredient rows
dynamically. Every write is permission-gated and audit-logged server-side.

**Tools tab ✅** - noclip (**F9**), god mode, invisible, player blips (ESP), spectate, self heal / revive /
armor, copy coordinates, open any player's inventory, and the **clothing thumbnail scan** (mode + category
picker). Admin tools are revoked automatically when a player is demoted. The scan used to be a double-press
F9 keybind plus a `/scanclothes` chat command; both are gone - that freed F9 for noclip and put every admin
action behind one permission gate.

**Remaining.**
- Editor coverage is not complete: **vehicles, gangs, gathering nodes, craft stations, shop price /
  sell lists** are still `config.lua`-only.
- Missing admin staples: **ban, warn, mute, teleport-to-waypoint, vehicle repair/delete**.
- `Actions.money` is **uncapped and unrated** - a compromised admin account can inflate the economy.
- The dashboard's `SELECT COUNT(*) FROM characters` has no `pcall`; a DB error leaves the NUI fetch
  hanging forever.
- Freeze state is tracked only in a client-side JS `Set`, so the label desyncs after a reopen.
- No confirmation on destructive actions; an admin can freeze or kick themselves.
- Spawned vehicles are never cleaned up.
- The `mod` tier is unused - the whole panel requires `admin`.
- Logs have no pagination and no free-text / time-range search.
- Direct SQL against `characters` and `logs`.

---

## 5. Not built yet - the roadmap

Everything below follows the two rules the rest of the framework already follows: **server-authoritative**
(never trust a client for money, ownership, position or permission) and **manageable in-game** (a
`v-world` domain + a v-admin Editor subtab, never a `config.lua` an operator has to edit on a live
server - `RULES.md` §3.6.2). Ordered by build order, not by wish.

### 5.1 Vehicles - the next big block

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 1 | ✅ **`v-vehicles`** - persistence & keys (**shipped**) | `v-core` | The foundation everything else in this block sits on. Owns `character_vehicles`: plate (unique), model, owner citizenid, **stored properties** (colours, mods, extras, livery, plate style), fuel, engine/body health, mileage, and a **state** (`garaged` / `out` / `impounded`). Persists a spawned vehicle's condition back to the row on despawn, on save-tick and on disconnect, so a car keeps its damage and mods. **Key system**: who may start/lock a given plate, giveable and revocable, checked server-side on engine start and lock toggle - a client-side lock check is not a lock. Plates are minted server-side and unique. |
| 2 | ✅ **`v-garages`** - storage & retrieval (**shipped**) | `v-vehicles` | Garage points (public, **job-owned**, gang-owned, house), each a `v-world` domain row: position, spawn point + heading, blip, type, and a **job/gang lock** reusing the same gate as the clothing stores. Store / retrieve / list, an **impound** that only releases against a fee, and per-garage capacity. Retrieval re-applies the stored properties from the DB - the garage is the only legitimate way an owned car enters the world. |
| 3 | ✅ **`v-vehicleshop`** - dealerships (**shipped**) | `v-vehicles`, `v-banking` | Concessions at the real GTA V dealerships (Premium Deluxe, Luxury Autos, bike/boat/plane sellers). A **catalogue editable from the admin panel** (model, category, price, stock, **licence required**, job/gang restriction, enabled) - the vehicle catalogue is a `v-world` domain like items and recipes, not a Lua table. Test drive on a timer that returns you where you started, purchase charges **server-side** and mints the `character_vehicles` row + plate atomically, then the car appears in the buyer's garage. Sell-back at a configurable rate. |
| 4 | ✅ **`v-rentals`** - short-term hire (**shipped**) | `v-vehicles`, `v-garages` | Rental points (airport, train stations, PD/EMS motor pool). A **deposit** is taken, the vehicle is spawned with a temporary plate and a **timer**; returning it to any rental point refunds the deposit minus the fee, and an expired or destroyed rental keeps the deposit. Rentals never create a `character_vehicles` row - that is what separates a rental from a purchase and stops it becoming a free-car exploit. |

**Cross-cutting for the whole block:** ✅ **fuel is done** (`v-fuel` - one consumption model, four
fuel types, admin-editable stations),
a `v-vehicles` export surface (`GetOwned`, `HasKeys`, `GiveKeys`, `SpawnOwned`, `StoreOwned`) so
`v-police` can impound and `v-jobs` can hand out job vehicles without touching the DB, and **one
spawn path** - nothing else in the framework is allowed to `CreateVehicle` an owned car.

### 5.2 Organisations - factions, gangs, and running them

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 5 | ✅ **`v-factions`** - the shared org layer (**shipped**) | `v-jobs`, `v-world` | One engine for **legal factions** (PD, EMS, mechanics, taxi, news) and **illegal ones** (gangs, mafias) - they differ by data, not by code. Owns membership, ranks (reusing `jobs.grades`), a **faction treasury** (a real account with its own transaction log, not a number in a config), owned garages/stashes/vehicles, and a territory concept for the illegal side. `gangs` already exists in the schema and is still empty. |
| 6 | ✅ **`v-bossmenu`** - the boss/patron panel (**shipped**) | `v-factions`, `v-banking` | The management UI a faction leader actually needs, gated on **rank**, not on admin permission: **hire / fire / promote / demote** members, see who is on duty, **deposit & withdraw from the treasury** with a full audit trail, **pay salaries**, manage the faction's **garage and stash access per rank**, and set the recruitment state. Every action is server-verified against the caller's rank and logged - a boss menu that trusts the client is a money printer. |
| 7 | ✅ **`v-gangs`** - the illegal org flavour (**shipped**) | `v-factions` | What `v-factions` doesn't share: **territories** (capture, influence decay, contested state), turf-gated drug sales, gang stashes and gang wars. Reuses the faction engine for membership and the treasury. |
| 8 | ✅ **`v-police`** (**shipped**) | `v-factions`, `v-vehicles` | Cuffs, escort, search (reusing `v-inventory`'s `GetSearchable`, which already never exposes the hidden pocket), **evidence**, an MDT (records, warrants, BOLOs), fines, jail, and **impound** through `v-garages`. |

### 5.3 Papers - licences & permits

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 9 | ✅ **`v-licenses`** (**shipped**) | `v-core`, `v-factions` | The single source of truth for *"is this character allowed to do this"*. One table (`character_licenses`: citizenid, type, status, issued/expiry, issuer, points), one export (`Has(src, type)`), and a **licence type list editable from the admin panel** so a server can invent its own. Ships: **ID card**, **driving licence** (car / bike / truck / taxi), **boat**, **pilot**, **weapon permit**, **hunting**, **fishing**, and the job-side ones (medical, bar). Includes **suspension and revocation** (a licence taken by the PD, with points and expiry), and issuance flows: the **city hall** (`v-cityhall`, already built) for the paperwork, a **driving school** for the practical, the **PD** for weapon permits. Consumed everywhere: the dealership refuses a sale without the right licence, the weapon shop without a permit, and the PD can run a plate against the driver's status. |

### 5.4 The illegal economy, finished

The legal loop (gather → craft → sell) and a first illegal loop (grow → process → deal → launder) already
ship. What's missing is the depth and the **risk** side that makes them a game rather than a spreadsheet.

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 10 | ✅ **`v-drugs`** - the full chain (**shipped**) | `v-gangs`, `v-police`, `v-licenses` | Turn the current recipes into a real system: **plantations** with growth stages, watering and theft by other players; **labs** with quality tiers, failure chance and a **fire/explosion risk** if you rush; **NPC dealing** priced by district, demand decay and heat; **player-to-player** dealing; **addiction & effects** on the buyer (tied to `v-status`); and **police pressure** - a bust chance that scales with heat, dirty money that must go through `v-banking`'s laundering, and evidence that lands in `v-police`. |
| 11 | **Heists & robberies** | `v-police`, `v-inventory` | Stores, ATMs, jewellery, the Fleeca/Pacific jobs. Server-authoritative timers and loot tables, a **minimum police count** before a job can start, and dirty money as the payout so it feeds the laundering loop. |
| 12 | ✅ **`v-anticheat`** (**shipped**) | `v-core` | The counterweight to all of the above: server-side sanity checks on money deltas, health, explosions, spawned entities and impossible movement, every trip logged to the existing audit log. |

### 5.5 Interaction surfaces & the rest

| Module | Priority | Responsibility |
|--------|----------|----------------|
| `v-phone` | high | **iFruit** - the phone. The primary interaction surface, and a shell over modules that already own the data. |
| `v-radial` | high | Radial menu (context actions) - the other main interaction surface. |
| `v-forgery` | medium | Fake papers and fake plates. The illegal counterpart of `v-licenses` and the plate registry. |
| `v-chat` | medium | Local, OOC and emote text. **Not** a command surface: the no-player-commands rule stands. |
| `v-pausemenu` | medium | Custom pause menu (hosts settings, incl. HUD). |
| `v-weather` | low | Weather/time sync + in-game control (currently lives inside v-admin). |

#### `v-phone` - iFruit, the primary interaction surface

The framework has **no player chat commands** by design, which makes the phone the surface
most of the game is actually played through. It is also the module most likely to go wrong
in one specific way, so the rule comes first.

**The phone is a shell, not a feature.** Every app is a thin view over a module that
already owns its data. A bank app calls `v-banking`; it does not keep a balance. A garage
app calls `v-garages`; it does not know what a vehicle state is. The moment an app holds
its own copy of anything, there are two sources of truth and one of them is wrong.

**Look:** iPhone-inspired - a lock screen, a home grid, app switching, notification
banners, a status bar - branded **iFruit**, GTA's own phone brand. The chrome is the
phone's; the **accent, panel and radius come from `v-ui`**, so a server that themes the
framework purple gets a purple phone rather than an orange rectangle in a purple world.

**Identity:** a phone number is a column on the character, unique and minted server-side in
a configurable format. Numbers are how contacts, calls and messages address each other -
never the citizen id, which is a database key a player should not be trading.

**Apps, and what each one is a view of:**

| App | Owned by | Notes |
|---|---|---|
| Phone | `v-voice` | Calls are `PhoneCallStart` / `PhoneCallEnd`. The phone does **no audio**. |
| Messages | `v-phone` | The one thing it does own. Persisted server-side; a client is never sent a conversation it is not in. |
| Contacts | `v-phone` | Per character, name plus number. |
| Bank | `v-banking` | Balance, transfers, history - the existing callbacks. |
| Garage | `v-garages` / `v-vehicles` | Where a car is, not how to spawn one. |
| Wallet | `v-licenses` | ID, driving, weapon permits - read only. |
| Jobs | `v-cityhall` / `v-jobs` | Open positions, resign. |
| Faction | `v-factions` / `v-bossmenu` | Members and treasury, gated on the same rank. |
| Contacts (illegal) | `v-drugs` / `v-gangs` | Unlocked by knowing somebody, not by an app store. |
| Camera | `v-phone` | Screenshot to a gallery; **an upload target is an operator decision**, so it is a setting with no default. |
| Settings | `v-phone` | Wallpaper, ringtone, do-not-disturb. |

**Third parties get an app registry**, the same bet the module registry made:
`RegisterApp(name, { label, icon, page })` and a script ships its own app without touching
v-phone. An app that is not installed is not on the home screen, and installation is an
admin domain like every other content list.

**Server-authoritative in the two places it matters:** a message is stored and relayed by
the server (a client that could write another player's history could forge it), and a call
is routed by the server, so ringing somebody does not depend on the caller knowing where
they are.

**Admin surface:** which apps exist and which are enabled, the number format, message
retention, whether the camera can upload and where, and per-app job or gang gating - a
`v-world` domain, edited like everything else.

**The trap:** a phone is where a framework accidentally grows a second economy. Every
transfer, every purchase and every job action goes through the module that owns it, so the
audit log stays in one place and the anticheat keeps seeing the same events it already
watches.

#### `v-forgery` - fake papers, fake plates

The illegal counterpart of the two registries this framework already treats as truth:
`v-licenses` decides what you are allowed to do, and `character_vehicles.plate` decides
what a car is. Forgery is the module that makes both **lie convincingly**, and the reason
it is worth building is that it gives the police something to *find out*.

**A forgery is a real record with a `forged` flag**, not a fake object in an inventory. A
counterfeit ID that is only an item is a piece of paper nobody can check; a counterfeit
that lives in `character_licenses` with `forged = 1` is one that passes an ordinary lookup
and fails a careful one. That difference is the whole game:

- **Casual checks pass.** A shop, a dealership, a traffic stop that just asks "does this
  person hold a driving licence" gets a yes.
- **A deliberate check can fail.** `v-police`'s MDT compares against the issuing authority
  and rolls against the forgery's **quality**; a cheap job shows up, a good one holds.
- **Quality is what you pay for**, and it is what a forger's skill buys.

**Fake plates** work the same way. A plate is swapped on the *vehicle*, not on the
ownership row, so:
- the car still belongs to whoever owns it (a fake plate is not a transfer of title);
- `v-police` running the plate sees the **plate's** registration, which is somebody else's
  car or nobody's at all;
- **`v-vehicles` must be the one place that knows**, because it already owns the plate,
  the persistence and the spawn path. A second module writing plates is how a framework
  ends up with two vehicles claiming the same registration.

**Where forgery happens** is a `v-world` domain: a back-room location, a required item, a
job or gang gate. Not a menu anyone can open anywhere - a forger is a person you have to
find.

**Integration that has to be right:**
- `v-licenses` gains a `forged` column and a `VerifyDeep(cid, type)` export. Nothing else
  changes: `Has()` keeps answering the casual question, which is exactly why the fake works.
- `v-police` gets the deliberate check, and a successful detection is evidence - a charge
  code already exists for it in the penal code.
- `v-anticheat` needs telling: a plate change is a legitimate action here, so it declares
  itself through `Expect` like every other module that does something flaggable.
- `v-drugs`' heat model is the right shape to reuse for forger reputation, if a server
  wants a bad forger to attract attention.

**The trap:** a forged licence that is indistinguishable from a real one forever is not a
feature, it is a bug in the police module's favour. Every forgery carries a quality and a
detection roll, so the answer to "will this hold" is *probably*, never *always*.

#### `v-chat` - local, OOC and emotes, without becoming a command surface

The framework's rule is **no player commands**, and that rule stands: chat must not become
a way to `/givemoney` or `/tp`. What it *is* for:

- **Local text** with a range, so a deaf or mute player is not locked out of roleplay - the
  single strongest reason to build this at all.
- **`/me` and `/do`** emotes, the two conventions every roleplay server actually uses.
- **OOC**, range-limited or global depending on a setting, clearly marked as out of
  character.
- **A report channel** that reaches staff, which today has no surface at all.

Everything else stays where it is: gameplay actions go through the radial menu, the phone
and keybinds. Admin commands remain admin commands.

**Server-side and rate-limited.** Message text is sanitised server-side (a chat that renders
client HTML is an XSS hole in a NUI), range is re-derived from the sender's position, and a
flood limit is a setting rather than a constant. Every message is logged through
`Core.Log`, because a chat with no audit trail is a chat a staff member cannot moderate.

### 5.6 Build order and why

1. **`v-vehicles` first.** Garages, dealerships, rentals, police impound and job vehicles all read the
   same ownership + key layer. Building any of them before it means building it twice.
2. **`v-licenses` early** - it is small, and the dealership, the weapon shop and the PD all need it.
   Adding it after those exist means retrofitting gates into three modules.
3. **`v-factions` before `v-gangs`, `v-police` and `v-bossmenu`.** They are the same engine with
   different data; writing the police module standalone would fork the membership/treasury code.
4. **`v-drugs` last of the economy work** - it depends on gangs (turf), police (pressure) and the
   laundering path, and it is the module most likely to need balancing once players are on the server.
5. ✅ **`v-anticheat` before the server opens**, not after - **done**. It is listed last because
   it guards everything above, not because it matters least.
6. ✅ **`v-3dsound` before `v-music` and `v-radio`** - **done**, and both now ship. It is a
   primitive that five modules want; building any of them first would have meant building it
   five times.
7. Done - **`v-motel` with `v-housing`, not after it**: it landed as a tenancy column exactly
   as planned rather than a second module.
8. Done - **`v-housing` after `v-police`, not before.** Property, storage and the house garage only wire
   existing modules to a new key, so they are cheap; **robbery** is the part that gives houses a
   reason to exist on the illegal side, and it needs the police module that now ships. Building
   housing first would mean shipping it twice.
9. Done - **`v-phone` after the modules it is a view of.** Every app turned out to be a shell
   over a module that already owned its data, exactly as planned; messages and contacts are the
   only things it owns outright. Two apps had to be cut back rather than faked: the jobs app is
   read only because `v-cityhall:take` is gated on standing at a desk, and the camera ships
   disabled because an upload target is an operator decision, not a default.
10. **`v-forgery` after `v-police`, which now ships.** A forged document is only interesting
    if somebody can catch it; building the fake before the check means shipping a document
    that always works, which is a bug rather than a feature.
11. **`v-chat` whenever, but not as a shortcut.** It is small, and the temptation the moment it
   exists is to hang gameplay commands off it. The no-player-commands rule is what keeps the
   phone and the radial menu worth building.

**Every module in this roadmap ships with:** a `v-world` domain + a v-admin Editor subtab for its
content, fr **and** en locales, server-side re-derivation of every gate, and an entry in this file,
`CHANGELOG.md` and the module's own README (`RULES.md` §3.7).

---

## 6. Cross-cutting debt

Ordered by how much damage it can do.

1. **Economy holes.** The offline-transfer dupe in `v-banking`; the uncapped `AddMoney` in `v-core` and
   `v-admin`. Fix these before the server opens. ✅ **`v-shops`' ignored `RemoveMoney` is fixed** - the
   charge is checked and the item refunded on failure.
2. **Missing server-side authorization.** `v-banking` never checks that the player is actually near the
   ATM. `v-status:server:onRespawn` is an unvalidated self-cleanse. ✅ **`v-inventory` openStash is now
   server-authoritative** (vehicle trunks resolve by net id with a distance check + server-read plate;
   drops must be real; move/drop/give amounts are floored). ✅ **`v-shops` is now server-authoritative**
   too - `getShop`/`buy` verify the player is at a store mapping to that shop id and enforce `shops.job`.
3. **Client-trusted writes.** `v-core:createCharacter` and `saveAppearance` take unbounded, unvalidated
   client tables straight into the DB. `v-clothing` writes client-supplied drawable ids into item
   metadata.
4. **Five modules bypass the DB layer.** `v-inventory` (`stashes`, `items`), `v-banking`
   (`bank_transactions`, `characters`), `v-shops` (`shops`, `items`), `v-clothing` (`items`),
   `v-admin` (`characters`, `logs`). `v-core` should grow `GetShops` / `GetStash` / `SaveStash` /
   `InsertTransaction` / `GetLogs` / `CountCharacters` and the modules should stop pulling in `oxmysql`.
5. **Content management - mostly closed.** ✅ Blips, store positions, jobs & grades, **items** and
   **craft recipes** are now created / renamed / deleted in-game from v-admin → Editor, backed by
   `v-world`, with live reload. Still `config.lua`-only and therefore still in breach of
   `RULES.md` §3.6.2: vehicles, gangs, gathering nodes, craft **stations**, shop price & sell lists,
   clothing prices, status drain rates, HUD thresholds, notification behaviour, the protected-resource
   list.
6. **`server_config` table is dead** - built for live settings, never read or written.
7. **i18n leaks.** Hardcoded French in `v-banking`'s transfer notification and the whole
   `v-loadscreen` status line; hardcoded English `aria-label`s in `v-hud`; DB-sourced content strings
   (item labels, shop names) have no translation path at all.
8. **`RegisterKeyMapping` requires a backing `RegisterCommand`**, so `vinv`, `vhotbar1..5`,
   `vhud_settings` and `vadmin_panel` are technically typeable in chat. Server-side
   gating makes the admin ones inert for players. This is an accepted platform constraint, not a
   violation - but `giveitem` (v-inventory) and `status` / `givemoney` / `setperm`
   are genuine console commands that should migrate into `v-admin`.
9. **Dead config keys** in almost every module (`Config.Debug` in six of them, `Config.Accounts`,
   `Config.DefaultSpawn`, `Config.Max`).
10. **No per-module `README.md` / `CHANGELOG.md`**, which `RULES.md` §5 requires.

---

## 7. Writing a module (the pattern)

1. `resources/[local]/v-<name>/` with `fxmanifest.lua`.
2. Server: `local Core = exports['v-core']:GetCore()`, register callbacks, use `Core.GetPlayer`.
   **Never query SQL directly** - add the query to `v-core/server/database.lua`.
3. Client: `local Core = exports['v-core']:GetCore()`, listen to `v-core:client:*`, drive NUI.
4. NUI: `<link href="https://cfx-nui-v-ui/theme.css">` and compose the EMBER primitives
   (`RULES.md` §3.5). **The resource that owns the page calls `SetNuiFocus` itself.**
5. Every player-facing string goes through `L('key')` with fr **and** en entries.
6. Ship a permission-gated management UI in `v-admin` for anything an operator will want to tune.
   The cheap way: add a **domain to `v-world`** (table + loader + `list`/`save`/`delete` branch +
   `SeedX` export), a subtab + form to the v-admin Editor, and an
   `AddEventHandler('v-world:server:changed', …)` in your module that rebuilds its runtime tables.
   Seed your `config.lua` defaults with `INSERT IGNORE` - **never** `ON DUPLICATE KEY UPDATE`, which
   silently wipes every admin edit on restart.
7. `ensure v-<name>` in `server.cfg` after `v-core`.
8. Update this file, `CHANGELOG.md` and the roadmap in the same commit (`RULES.md` §3.7).

---

## 8. Module APIs at a glance

```lua
-- v-status (server)
exports['v-status']:Get(source)               -- { hunger, thirst, stress, bleed, sick }  (live ref!)
exports['v-status']:Add(source, 'hunger', 25)
exports['v-status']:SetBleed(source, 0)
exports['v-status']:SetSick(source, 0)
exports['v-status']:Heal(source)              -- clears bleed + sick only

-- v-inventory (server)
exports['v-inventory']:AddItem(src, 'water', 2)      -- true/false (weight & slots checked)
exports['v-inventory']:RemoveItem(src, 'water', 1)
exports['v-inventory']:GetItemCount(src, 'water')
exports['v-inventory']:RegisterUsableItem('water', function(src, item) end)
exports['v-inventory']:GetItems(src)                 -- main inventory array
exports['v-inventory']:GetSearchable(src)            -- what a police frisk/steal may see
                                                     --   (main inventory only - NEVER the hidden pocket)
exports['v-inventory']:GetLimits()                   -- { maxSlots, maxWeight, hotbar }
-- open a container client-side:
TriggerServerEvent('v-inventory:server:openStash', id, label, kind)

-- v-world (server) - admin-editable content, DB is the source of truth
exports['v-world']:IsReady()                         -- tables created + loaded
exports['v-world']:GetShopLocations()                -- rows of world_shops
exports['v-world']:GetJobs() / GetItems() / GetRecipes() / GetBlips()
exports['v-world']:SeedShopLocations(Config.Locations)  -- INSERT IGNORE, first boot only
exports['v-world']:SeedJobs(Config.Jobs)
exports['v-world']:SeedRecipes(Config.Recipes)
-- rebuild your runtime tables when an admin edits something:
AddEventHandler('v-world:server:changed', function(domain) --[[ 'blips'|'shops'|'jobs'|'items'|'recipes' ]] end)

-- v-clothing (server)
exports['v-clothing']:GetWorn(src)            -- cat -> { item, drawable, texture }
exports['v-clothing']:Unequip(src, 'tops')    -- true/false

-- v-notify (client only - no server export yet)
exports['v-notify']:show({ type = 'success', title = '…', message = '…', duration = 4000 })
TriggerClientEvent('v-notify:show', src, { … })   -- server side, event string hardcoded
```

## 9. i18n

Every resource does `shared_script '@v-core/locale/shared.lua'`, defines `Locales = { en = {…}, fr = {…} }`
and calls `L('key', …)`. The player's language lives in `LocalPlayer.state.lang` (client) and
`Player(src).state.lang` (server); use `LP(src, 'key')` server-side. NUI text is driven by sending
`Locales[lang]` to the page. Default via `set vcore_lang "fr"`; each player picks their language in
`v-spawn`.

**Principles:** no player chat commands (phone / radial / pause UI / keybinds only); every content
system manageable in-game via permissions; everything routes through `v-core` so modules stay
decoupled. See `RULES.md` §3.5–3.7.
