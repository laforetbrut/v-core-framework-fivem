# v-core — Architecture & Module Guide

How the framework is wired, what each module actually does today, and what is left to build.

Last surveyed: **2026-07-22** (every module read end-to-end; see `## Per-module status`).

Platform: **FiveM Enhanced** — the server runs on `artifacts/cfx-server.exe` (the Enhanced binary;
`FXServer.exe` is the Legacy branch and rejects Enhanced clients with `bad_request`). `info.json`
must report `gamename: gta5enhanced`. **Never set `sv_enforceGameBuild`** — those are Legacy build
numbers and enforcing one locks Enhanced clients out. CEF is Chromium 140, so `nui://` is no longer a
secure context: always reference NUI assets as `https://cfx-nui-<resource>/…`.

---

## 0. Build progress — in-game content editor, inventory & appearance

### In-game content editor — `v-world` + the v-admin **Editor** tab

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
live — **no `restart` needed**. Config tables are now *seed data only*: they are pushed to the DB with
`INSERT IGNORE` on first boot, so the DB is the single source of truth and admin edits are never
overwritten on restart.

Guard rails: item internal `name` is immutable after creation (renaming would orphan every stack);
deleting an item is refused if a recipe references it, and `money` can never be deleted.

**Visibility gating:** a blip row carries `job` + `grade` + `perm`. The filtering runs **server-side, per
player** (`blipsFor(src)`) — a restricted location is never sent to a client that isn't allowed to see
it, so it can't be read out of client memory. The set is re-pushed on `v-jobs:server:changed` and
`v-core:server:permissionChanged`. A job row carries `whitelisted`: whitelisted jobs are hidden from the
city hall and handed out by their own chain of command.

**Clothing slots are data now.** `clothing_categories` holds the wearable slots themselves — key, label,
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

### Appearance suite (rebuild — full plan in `memory/appearance-suite-plan.md`)

| Phase | What it delivers | State |
|-------|------------------|-------|
| **1 — engine + stable identity** | `v-appearance` module = single ped writer; clothing stored as stable **(collection, local index, texture)** refs (survives addon/build changes); v1→v2 migration on load; v-spawn + v-clothing delegate rendering; `appearance` added to autosave. | ✅ **done** |
| **2 — barber / surgery / tattoos** | Shared re-openable editor with three station types (barber, plastic surgeon, tattoo parlour) + peds/blips. Barber = hair style/colour/highlight + all head overlays with **proper opacity + colour** (blush/makeup/lipstick were dead; now correct); surgeon = 20 face features + head-blend mixes; tattoos = 869-overlay catalogue by zone, apply/remove, **stored in `appearance.tattoos`** and re-applied by the engine after the head-blend. | ✅ **done** |
| **3 — catalogue + scanner rebuild** | **Foundation ✅**: `clothing_catalogue` + `clothing_scan_state` tables, `VCore.DB` catalogue/scan functions, and a verified CEF **colour-extraction** module (CIELAB ΔE nearest-named-colour, saturation-weighted). **Remaining**: the actual scan capture pipeline — per-gender enumeration via the collection natives, wiring the colour extractor + perceptual hash into the NUI, `.webp` storage (not loose `.txt`), replace-clothing detection, incremental/resumable scan. Needs an in-game scan (screenshot-basic) to verify. | 🔨 |
| **4 — shops + inventory integration** | Per-shop catalogues, dynamic stock, filters (colour/name/sub-type), in-game shop creation, restrictions (job/ace/id), item-metadata → ref migration. | ⬜ |
| **5 — outfits + job outfits + height** | Wardrobe & job outfits (temporary override layer); character height (opt-in, off by default, experimental — no true GTA V native). | ⬜ |

**Not achievable as the vendor markets it** (verified against the FiveM natives, see the plan): the 46 000 pre-tagged catalogue and "AI labelling"/sub-types are a shipped hand-authored dataset, not runtime-derivable; character height is visual-only and glitchy (no `SET_PED_SCALE` on GTA V). We reach parity by curation + our colour extractor, and ship height opt-in/experimental.

### Inventory (Quasar-parity roadmap the owner asked for)

| # | Feature | State |
|---|---------|-------|
| — | Core grid, weight/slots, use/give/drop, stashes, trunk, cash-as-item, equipment panel | ✅ done |
| — | **Pointer-based drag & drop** (HTML5 DnD is unreliable in CEF) | ✅ done |
| — | **Fallback icons** for imageless items (clothing garment / generic box) | ✅ done |
| — | **Hidden pocket** (1 kg concealed compartment, invisible to a police search) | ✅ done |
| 1 | Unified player top-nav menu | ⬜ |
| 2 | Weapons **functional** (equip/holster via Use, ammo boxes top up the drawn weapon, serial minted on first draw, ammo persists to metadata) ✅ · **attachments** ✅ (5 attachment items — suppressor / flashlight / scope / grip / extended-mag — `Use` fits them to the drawn weapon via a server component map, stored on the weapon item's metadata and re-applied on every draw; craftable at the reloading bench) · on-back / draw anims ⬜ | 🔨 |
| 3 | **Shared/gang stashes with permissions** — persistent containers gated by job / gang / permission tier, opened via `exports['v-inventory']:OpenSharedStash(src, id)` or a net event; access checked server-side on every open (`Config.SharedStashes`) | ✅ framework (needs placement/interaction points) |
| 4 | Advanced shops with a **basket** (drag-to-buy + inventory view now shipped in v-shops) | 🔨 partial |
| 5 | Advanced crafting (recipes, benches) ✅ — **`v-crafting`** module: 4 stations (workbench / reloading / kitchen / electronics), 25 recipes, server-authoritative proximity + input check + space-check with refund, EMBER NUI (material chips have/need + progress bar), optional job/perm gates | ✅ |
| 6 | Inventory customization (colours, transparency, centered mode) | ⬜ |
| 7 | **Backpacks** (carrying one adds +12 slots / +20 kg) ✅ · **body armor** items apply armour on use ✅ · armor DLC ⬜ | 🔨 |
| 8 | **Player search / steal** ✅ (frisk a nearby hands-up / downed player — server-validated proximity + gate, cross-player container, take **or** plant, hidden pocket never exposed) + **hands-up surrender**. In-world *placed* items (beyond ground drops) ⬜ | 🔨 |
| 9 | Bonus: vending machines, garbage job, skill tree | ⬜ |

**Optimization:** the item catalogue (`defs`, ~170 rows) is now sent to the NUI **once** on open and cached; move/use/drop responses omit it — every action payload dropped from ~full-catalogue to just the changed state.

Also outstanding on inventory (from the audit, not yet fixed): moving the direct-SQL `stashes`/`items` access behind `v-core`. **Done since the audit:** weapon serial/ammo persistence ✅, in-world drops are now **real props** that are garbage-collected when emptied ✅ (also fixed the unbounded `Stashes` leak), **weapon attachments** ✅, and **weapon durability/wear** ✅ (server-derived from reported ammo; a Cleaning Kit repairs it). Food/perishable time-decay still open.

### Other recent additions

- **Multi-character selection** — slots per tier (user 1 / mod 2 / admin 6), Play / New / Delete (admin-gated). `v-core` GetCharactersByLicense / DeleteCharacter / selectCharacter / deleteCharacter callbacks; `characters.slot` now written on create.

### Recently fixed bugs (this session)

- **Inventory/shop drag stacking & slot placement** — oxmysql TINYINT→boolean broke `stackable==1`; empty-table metadata (`{}` truthy in Lua) blocked merges; drops ignored the target slot. Fixed with flag coercion, a `noMeta` helper, and a preferred-slot arg on `AddItem`/`addToContainer`.

- **No mouse in any menu** — `SetNuiFocus` is resource-scoped; `v-core` had no `ui_page`, so the shared focus helper was a silent no-op. Each owning resource now takes focus itself.
- **Spawn fell into the void / showed a default ped** — screen held black from the first frame; ped kept frozen while collision streams + ground is found; unfrozen only after the switch-in.
- **Inventory drag broken + imageless items** — see the two ✅ rows above.

---

## 0b. The module registry — settings & third-party integration

Two problems, one answer. *"Everything must be configurable from the admin panel"* and
*"someone else's script should plug in without editing the framework"* are the same problem
once you notice that both are about a module **describing itself**.

`v-core/server/modules.lua` holds a registry. A module declares its **tunables**; v-core
stores the values (`module_settings`), serves them to the admin panel, and pushes changes
back. **`v-admin` knows nothing about any module's settings** — it renders whatever it is
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
before it registers anything — an operator can see it is installed. All 25 of our own
modules carry the flag. Full guide: **[INTEGRATION.md](INTEGRATION.md)**.

**Settings vs. content.** A *tunable* (a rate, a threshold, a price multiplier) is a
setting. A *list* (shops, items, recipes, garages) is a **v-world domain** with an Editor
subtab — §7. Using a setting for a list, or a domain for a single number, is the mistake
this split exists to prevent.

**21 of 25 modules declare their settings** — every one that has a meaningful tunable.
The four that do not (`v-ui`, `v-loadscreen`, `v-world`, `v-admin`) are infrastructure with
nothing an operator would sensibly change at runtime; `v-core` itself is listed so an
operator sees it running.

A caveat worth stating: a declared setting is only real if something **reads** it. The
first sweep declared five multipliers (`v-shops` buy/sell, `v-crafting` duration,
`v-gathering` yield, `v-clothing` price) and a salary multiplier that nothing consumed —
they have since been wired into their actual code paths. A setting that does nothing is
worse than no setting: it lies to the operator.

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

**Rule that is currently violated:** modules are supposed to never touch SQL — only `v-core` may.
Five modules query the DB directly today. See `## 6. Cross-cutting debt`.

---

## 2. The v-core API

### Get the core
```lua
local Core = exports['v-core']:GetCore()   -- server or client
```

### Server — player object
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

### Server — callbacks, permissions, logs
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

### Client — data, callbacks, events
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

### Client — NUI focus bookkeeping (v-core/client/focus.lua)
```lua
exports['v-core']:MenuOpened()      -- ref-counts, sets LocalPlayer.state.nuiOpen
exports['v-core']:MenuClosed()
exports['v-core']:IsAnyMenuOpen()
```

> **`SetNuiFocus` is resource-scoped.** The native resolves against the *calling* resource's own
> NUI frame and returns early when that resource has no `ui_page`. `v-core` has none, so it can
> never take focus on another module's behalf. **The resource that owns the page must call
> `SetNuiFocus` itself**, right next to its `MenuOpened()` / `MenuClosed()` report. This caused a
> total loss of mouse input in every menu on 2026-07-10 — see `ERROR_LOG.md`.

---

## 3. Database

Schema lives in **`database/schema.sql`** (25 tables; `world_blips` gains `job`/`grade`/`perm` and `jobs` gains `whitelisted` via idempotent `ALTER`s at boot). MariaDB, accessed through `oxmysql`.
`craft_recipes` is created idempotently at boot by `v-world`'s `ensureTables()`.

| Table | Owner | Purpose | State |
|-------|-------|---------|-------|
| `users` | v-core | account per license: name, language, permission, last_seen | ✅ used |
| `characters` | v-core | identity, cash/bank, job, gang, position, metadata, inventory, appearance | ✅ used (`slot` column unused — multi-character not implemented) |
| `items` | v-core (schema) | item definitions (name, label, weight, stackable, usable, category, metadata) | ✅ **source of truth** — seeded `INSERT IGNORE` by v-inventory/v-clothing, edited live from v-admin → v-world |
| `logs` | v-core | structured audit log | ✅ used (read directly by v-admin) |
| `bank_transactions` | v-banking | deposit / withdraw / transfer_in / transfer_out audit | ✅ used (direct SQL) |
| `stashes` | v-inventory | persistent containers (stashes, gang boxes, ground drops) | ✅ used (created + queried directly) |
| `shops` | v-shops | shop catalogue + prices | ⚠️ read at boot only; store **positions** now live in `world_shops` |
| `world_blips` | v-world | admin-created map blips | ✅ used (Editor → Blips) |
| `world_shops` | v-world | store positions: coords, heading, ped model, blip | ✅ used (Editor → Stores, consumed by v-shops) |
| `craft_recipes` | v-world | recipes: station, output, count, time, ingredients JSON | ✅ used (Editor → Craft, consumed by v-crafting) |
| `character_vehicles` | — | vehicle ownership | ⬜ **empty — v-vehicles not built** |
| `jobs` | v-world | jobs & grades | ✅ used (Editor → Jobs, consumed by v-jobs) |
| `gangs` | — | gangs & grades | ⬜ **empty — v-gangs not built** |
| `server_config` | — | live server settings | ⬜ **empty — never read or written by anything** |

**Planned by the roadmap (§5), not created yet:**
`vehicle_rentals` (active hires), `faction_treasury` + `faction_transactions`, `gang_territories`,
`drug_plants` / `drug_labs`. `gangs` already exists and is still empty; **`character_vehicles` and `world_garages` are now live**.

---

## 4. Per-module status

Legend: ✅ shipped · ⚠️ shipped with a known hole · ⬜ not built.

### `v-ui` ✅ — shared design system
**Done.** `theme.css` only: the full "EMBER" token set (warm-graphite surfaces, **dominant**
brand orange with gradient/glow variants, muted status + rarity scales, 8–22px rounded geometry,
soft layered shadows, `--z-*` scale, fluid/spring motion tokens) plus the primitives `.v-chamfer`
(rounded glass panel + orange top light-streak) / `.v-tab` / `.v-brk` / `.v-slot` / `.v-gauge` /
`.v-progress` / `.v-glass` / `.v-btn` / `.v-chip` / `.v-stencil` / `.v-input`, a global
`:focus-visible` ring and a `prefers-reduced-motion` block. CEF-safe: **no `backdrop-filter`**
(FiveM's CEF renders it as an opaque black box) — depth comes from layered gradients and shadows.
No SQL, no Lua, no exports.

**Remaining.**
- No shared JS runtime — every module re-implements the `--i` stagger, gauge fill and `.is-over`
  toggling in its own `app.js`. That is the copy-paste drift the single-source rule exists to stop.
- `--v-rar-legendary` is byte-identical to `--v-accent`, so a legendary item is indistinguishable
  from ordinary accented chrome.
- No `dependencies{}` block: if `v-ui` fails to start, every NUI page renders unstyled **silently**.
- No cache-busting on the stylesheet URL.
- `v-loadscreen` cannot link it (loads pre-mount) and mirrors the EMBER tokens locally — they will drift.

### `v-core` ✅ — framework
**Done.** Player lifecycle (`playerReady` → `EnsureUser` → load-or-create character → `playerLoaded`,
autosave + save on drop/stop). Self-persisting player object with guarded `AddMoney`/`RemoveMoney`.
`VCore.DB` layer over `users` / `characters` / `logs` / `items`. Bidirectional callback bus with
request-id correlation. Permission tiers with DB + `Config.Admins` bootstrap. i18n engine
(`L` / `LP`, fr default via `vcore_lang`, per-player `state.lang`). Structured logging to console +
`logs`. Private routing-bucket isolation for character creation, concurrency-guarded. NUI-focus
bookkeeping. Two permission-gated console commands (`givemoney`, `setperm`).

**Remaining.**
- **Multi-character is not implemented** — `GetCharacterByLicense` is `ORDER BY slot ASC LIMIT 1`
  with the comment "multi-character selection comes later". No character delete / rename / slot UI.
- `createCharacter` and `v-core:server:saveAppearance` write **client-supplied data straight to the
  DB** with no length, format or size validation, and no rate limit. DB-bloat vector.
- `GenerateCitizenId` has no collision retry; a duplicate id makes the INSERT fail inside a `pcall`
  and the player is silently stuck on the creation screen (no error string exists for it).
- `SetGang` fires no `v-core:server:onGangChange` — asymmetric with `SetJob`.
- `Config.Accounts` and `Config.DefaultSpawn` are dead keys. `Config.Debug` ships as `true`.
- `Core.Log` webhook sink is a stub (`"plugs in here later"`) — console + DB only.
- No cap on `AddMoney`; any resource holding the player object can mint unbounded money.
- Dead code: `CreateDefaultCharacter`, `GetItems`, `GetPlayerByCitizenId` are never called in-core.

### `v-notify` ✅ — toasts
**Done.** Client `exports['v-notify']:show(data)` + `v-notify:show` net event. Four muted types with
line icons, rounded EMBER glass cards with a type-keyed accent bar, XSS-safe escaping,
click-to-dismiss, glowing countdown bar, `aria-live` region.

**Remaining.**
- **No server-side export.** Every server caller hardcodes the literal string
  `TriggerClientEvent('v-notify:show', src, data)` — renaming the event silently breaks all of them.
- No stack cap and no max-duration clamp → an unbounded toast stack + leaked timers.
- No de-duplication, no positioning options, no sound, no "clear all".

### `v-loadscreen` ✅ — boot screen
**Done.** Native loadscreen, ken-burns video + poster, blueprint grid + grain + vignette, stencil
title, 16-notch progress gauge with a monotonic clamp, rotating tips, staggered entrance.

**Remaining.**
- **Status strings are French-only** (`Initialisation…`, `Chargement de la carte…`) and tips crudely
  alternate FR/EN every 5s. It cannot use the locale system (it loads before `v-core`).
- The progress bar **fabricates advancement**: an idle-creep interval pushes it to 92% even when no
  real load event fires.
- Server name, kicker, signature, tips and asset paths are hardcoded in HTML/JS.
- Mirrors `theme.css` tokens locally — will drift.

### `v-spawn` ✅ — onboarding
**Done.** Language pick → identity form → full appearance editor (6 tabs, orbit camera, colour
swatch grids, garment thumbnail strips wired to v-clothing's scan) → first-spawn location cards
(LSIA / Bolingbroke / Sandy Shores) → GTA-style `SwitchOutPlayer`/`SwitchInPlayer` swoop with
ground-Z snap. Returning characters restore their saved look and swoop to their last position.

**Remaining.**
- **No re-entry path** — there is no export or event to reopen the creator for a barber or a
  plastic surgeon, even though `v-core` already ships `SaveAppearance` for exactly that.
- `Config.Max` is **dead and drifted**: nothing reads it, and its ranges disagree with the real
  ranges hardcoded in `app.js` (`tops` 300 vs 350).
- **Blush does nothing** — the control exists in the UI, but `ped.lua` has no blush overlay.
  **Makeup and lipstick are invisible** — their default opacity is `0.0` and no opacity slider exists.
- Drawable ranges are model-independent and unclamped against `GetNumberOfPedDrawableVariations`, so
  out-of-range / invisible garments are selectable.
- Creation failure gives **no feedback** — the player is soft-locked on the appearance screen.
- DOB is unvalidated (any string into a `DATE` column; future dates accepted).
- Eye-colour palette exposes 24 of ~32 swatches.
- The chosen spawn point is only teleported client-side; it reaches the DB on the next autosave, so
  an immediate disconnect loses it.
- No randomize / reset button.

### `v-status` ⚠️ — survival
**Done.** Server-authoritative hunger / thirst / stress / bleed (0-4) / sick (0-3). Drain tick,
starvation damage, bleed damage + screen flash + ragdoll, illness damage, stress timecycle + cam
shake. Client injury detection. Persistence through `v-core` metadata (respects the no-SQL rule).
Server mutator exports: `Get` / `Set` / `Add` / `SetBleed` / `SetSick` / `Heal`.

**Remaining — and one of these is a real bug.**
- **Status damage can never kill.** The client forces `SetEntityHealth(ped, math.max(101, target))`,
  so starvation, bleeding and illness all floor at 101 HP. Level-4 bleed (12 HP/tick, designed to
  down a player) can never down anyone. The server also passes a *different* floor (`110`).
- **`Set`/`Add` mis-clamp `bleed` and `sick`** to 0-100 instead of 0-4 / 0-3, so an item or EMS
  caller silently corrupts the state and drives a `nil` damage-table lookup.
- **`Get` returns the live table by reference** — any consumer can write `Get(src).hunger = 999`,
  bypassing clamping, persistence and sync.
- **Exploit:** `v-status:server:onRespawn` is a plain net event with no death validation. A client
  can spam it to cure its own bleeding and refill hunger/thirst to 50 at will.
- Injury detection is client-side (HP drop > 8) — a modded client is immune; it also false-positives
  on falls and teleports.
- **Stress has no source and no decay**, and **illness has no source** — nothing in the codebase ever
  raises them, so both systems are dead until an external caller drives them.
- `Heal` clears bleed + sick only, not hunger/thirst/stress, despite being labelled "full cleanse".
- The stress thread calls `ClearTimecycleModifier()` every second, **stomping any timecycle set by
  another resource** (drunk, nightvision, weather fx).
- No HUD of its own (by design — `v-hud` renders it), no locales, no in-game tuning UI.

### `v-hud` ✅ — overlay
**Done.** Money readouts, seven always-visible vitals rings, hunger/thirst alerts at 25% with
hysteresis, scrolling compass, **custom square minimap** (streamed mask, GTA:O health/armour bars
removed via the scaleform, NUI frame slaved to the native map's true screen rect), drag-to-move and
resize, F7 settings panel (element toggles, accent, opacity, scale, layout mode), whole-HUD auto-hide
on pause / fade / player switch / open menu, KVP persistence, fr+en.

**Remaining.**
- Settings live in **client-side KVP**, so they are per-machine, not per-character, and not
  server-authoritative.
- **No exports and no inbound events** — another resource (a cutscene, a phone) cannot cleanly hide
  or drive the HUD.
- Everything is hardcoded: poll interval, alert thresholds, oxygen multiplier, danger thresholds,
  the six accent presets, compass constants. No config, no admin surface.
- `v-notify` is used but not declared in `dependencies{}`; if absent, the 25% alert silently vanishes.
- The accent picker offers green/blue/red/amber/purple, which contradicts the one-accent rule in
  `RULES.md` §3.5. **Open question for the owner:** restrict it to orange variants, or keep it as a
  player preference outside the design system?
- Several `aria-label`s and the panel's `HUD` tab label are hardcoded English.
- Dual source of truth for minimap size (Lua `map.scale` vs JS `settings.minimapSize`).

### `v-banking` ⚠️ — Fleeca ATM
**Done.** ATM proximity (4 prop models) → E → NUI with balances + last 20 transactions. Deposit,
withdraw, transfer by citizenid (self-transfer blocked, recipient existence checked, online credited
in-memory / offline credited by SQL). Every mutation server-authoritative; both legs audited into
`bank_transactions`. Full fr+en.

**Remaining.**
- **DUPE VECTOR.** An offline recipient is credited with an *immediate persistent* SQL
  `UPDATE ... bank = bank + ?`, while the sender's deduction is only an *in-memory* `RemoveMoney`
  that persists on the next autosave. A crash in that window creates money. Online→online is
  symmetric and safe; only the offline path is exposed.
- **No server-side ATM proximity check** — deposit / withdraw / transfer are net callbacks a modded
  client can call from anywhere. No rate limiting either (each offline transfer is 4 queries).
- Direct SQL against `bank_transactions` **and against `characters`, a table it does not own**.
- **No export** — salaries, fines and shops cannot record a bank transaction, so their money movements
  never appear in the history.
- The recipient notification is a **hardcoded French string** that bypasses i18n entirely.
- Transfers use the raw internal citizenid — no name lookup, no account number, no contacts.
- No fees, limits, savings, business accounts, cards or statements. No blips, no bank interior teller.
- History is capped at 20 rows, no pagination, and re-queried on every mutation.

### `v-inventory` ✅ — grid inventory
**Done.** 40 slots / 30 kg, 5-slot hotbar (keys 1-5), **TAB** to open. **300-item catalogue**
(`data/items.lua`; the first 170 ship local PNGs, the rest use `image=nil` and fall back to the NUI
glyph), seeded on boot with **`INSERT IGNORE`** — the `items` table is the source of truth and is
edited live from v-admin → v-world, so re-applying the Lua values every boot would wipe admin edits.
`loadItemDefs()` re-reads the definitions and re-binds the type-driven use handlers whenever
`v-world:server:changed('items')` fires. Drag & drop (move / swap / merge / shift-split),
right-click actions (use / give / split / rename / drop), search, tooltip with rarity / serial / ammo /
durability. **Cash as an item** — a virtual wallet tile mirroring the account, which stays the single
source of truth (no dupe path). Vehicle trunk + glovebox, persistent stashes, ground drops.
**Equipment panel** — clothing as body slots, drag to equip, right-click to unequip (driven by
v-clothing's `GetWorn` / `Unequip`). Server-authoritative: every action re-renders from the returned
state. EMBER NUI.

Exports: `AddItem` / `RemoveItem` / `GetItemCount` / `RegisterUsableItem`.
Callbacks: `getState` / `move` / `use` / `drop` / `give` / `rename` / `unequipCloth`.

**Remaining — this is the biggest backlog in the project.** The owner has asked for the full
Quasar-inventory feature set:
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

### `v-shops` ⚠️ — stores
**Done.** Clerk peds + blips at fixed 24/7 locations, streamed in/out. Buy UI with quantity stepper
and cash/bank toggle. Purchase re-derives the price server-side, checks funds, reserves inventory
space via `AddItem`, then charges and logs. fr+en.

**Fixed (hardening pass).** `getShop` / `buy` now run through `canUseShop`: the server checks the player
is **physically at a store** mapping to that shop id (coords from the shared `Config.Locations`) and, for
job-locked stores, that the player **holds the job** — closing the buy-from-anywhere and unenforced-`job`
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
- Item **prices** are still loaded once at boot — a DB price edit needs a `restart v-shops`.
- Direct SQL against `items` and `shops`.
- No in-game management UI (`config.lua` literally says *"editable in-game later"*).
- The NUI silently ignores `{error='funds'|'space'}`.

### `v-crafting` ✅ — workbench crafting
**Done.** New module. Four **stations** (`workbench`, `ammo`, `cooking`, `electronics`) with map blips
and ground markers at fixed benches; **25 recipes** defined in `config.lua` (inputs → output, produced
count, progress time, optional `gate` = job/grade/permission). Opening a station and crafting are both
**server-authoritative**: `getStation` / `craft` re-check the player's real distance to a bench server-side
(`atBench`, uses `GetPlayerPed`+`GetEntityCoords`), verify every input for `qty × amount`, consume them,
then `AddItem` the output — **refunding the inputs if the output doesn't fit**. Per-player cooldown +
in-flight lock guard against spam/double-submit. EMBER NUI: recipe rows show each material as a
`have/need` chip (red when short), a quantity stepper capped to the craftable amount, and a progress bar;
the panel refreshes owned counts live after each craft. fr+en. Reuses `v-inventory`
`GetItemCount`/`RemoveItem`/`AddItem` exports — no new DB tables.

**In-game editable.** Recipes now live in `craft_recipes` and are managed from v-admin → Editor → Craft
(station, output item, produced count, duration, enabled, and a dynamic list of ingredient/qty rows).
`Config.Recipes` is seed data only; `rebuildRecipes()` re-derives the runtime list on
`v-world:server:changed('recipes')`, and `loadItemDefs()` refreshes labels on `…('items')`.

**Remaining.**
- The **stations** (bench coords, blips, markers) are still boot-static in `config.lua` — only the
  recipes are editable in-game.
- The craft progress time is client-side (feel only); the server enforces order + cooldown but not the
  full duration, so a crafted item can arrive up to `time` early if the client is patched. Low impact
  (inputs are still consumed atomically); move the timer server-side if it ever matters.
- No skill/XP progression on crafts (roadmap #9).

### `v-gathering` ✅ — resource nodes
**Done.** New module. Supplies the raw materials `v-crafting` consumes, closing the economy loop.
Three resource types (`mining`, `salvage`, `textile`) with map blips + ground markers at fixed **nodes**
(real GTA V spots: Davis Quarry, scrap/junk yards, Grapeseed cotton fields). Interact key starts a world
scenario for the resource's `time`; the harvest **cancels if the player walks off the node**. On completion
the server (`v-gathering:harvest`) **re-checks proximity** (`GetPlayerPed`+`GetEntityCoords`), enforces a
per-player cooldown, rolls a **weighted yield** (+ an optional rare bonus), and grants it via
`exports['v-inventory']:AddItem` with a space-check. No NUI — blips, marker and `v-notify` toasts only.
fr+en. No new DB tables.

**Remaining.**
- No tool requirement / tool durability on gathering yet (roadmap: pickaxe/axe, tool wear).
- No gathering XP / yield scaling.
- `gunpowder` has no gather source (only craftable/buyable) — add a chemical node or keep it shop-only.
- Node coords are boot-static in `config.lua`.

### `v-clothing` ✅ — clothing store
**Done.** Proximity store (**10 branded locations**, streamed shopkeepers), live on-ped preview with a
drag-orbit camera, per-drawable texture picker, buy-as-item, equip by using the item (swaps the worn
piece back to inventory), unequip from the wardrobe tab or via the `Unequip` export. **Admin
thumbnail scanner**: studio teleport, bare-vs-dressed pixel diff so only the garment survives on a
transparent background, crop + downscale in the NUI, one-shot-token HTTP upload (works around the
net-event size kick), lazy batched loading. 1848 thumbnails already generated. Arms are free.

**16 wearable slots** (was 8): masks, hats, glasses, **earrings**, undershirts, tops, arms,
**gloves**, **body armor**, **decals**, **necklaces**, **bags**, **watches**, **bracelets**, pants,
shoes — i.e. every component (1,3,4,5,6,7,8,9,10,11) and every prop (0,1,2,6,7) the appearance engine
already supported. `arms` and `gloves` deliberately share component 3: GTA renders one drawable per
component, so equipping gloves **evicts** bare arms (`sameSlot()` returns the displaced garment to the
inventory first, and aborts the swap if it can't fit). That is the honest model — the ped cannot wear
both, and pretending otherwise would leave a garment "worn" in the data but invisible.

**Everything is admin-editable.** Store locations live in `world_clothing` (position, heading, clerk
ped, blip, **job lock**, enabled) and the slots themselves in `clothing_categories`; both are seeded
from `config.lua` with `INSERT IGNORE` on first boot and then read from the DB. `rebuildCategories()`
re-reads the slots on `v-world:server:changed('clothcats')`, (re-)creates each slot's item definition,
binds its use handler once and pushes the list to every client; store edits re-push the locations and
the client tears down and rebuilds blips and peds — **no restart**.

**Buying is now server-authoritative.** `atStore(src)` re-derives the player's distance from the
server-owned ped and enforces the store's job lock, closing the buy-from-anywhere hole.

Exports: `Unequip(src, catKey)` / `GetWorn(src)` / `GetCategories()`.

**Remaining.**
- **Gender blindness.** Thumbnails are captured on the *admin's* ped and stored as one set, but
  freemode drawable indices differ between `mp_m` and `mp_f`. A female player browses images shot on a
  male ped, and a purchased item maps to a different garment on another model.
- The buy payload's `drawable` / `texture` are **client-trusted and unvalidated** (the server cannot
  call the ped natives), so arbitrary or dev components are purchasable.
- Buying with a full inventory fails **silently** — no notification and no locale key for it.
- Flat per-category pricing (editable in-game); no per-drawable price, rarity or stock.
- Direct SQL: `INSERT IGNORE INTO items` on boot.
- Thumbnails are 1848 loose base64 `.txt` files + an `index.json` under the resource.
- `screenshot-basic` and `oxmysql` are not declared in `dependencies{}`.

### `v-vehicles` ✅ — owned-vehicle persistence & keys
**Done.** New module, roadmap §5.1 step 1. Owns `character_vehicles` and is the **only** legitimate
path an owned vehicle takes into the world. Plates are **minted server-side** (`VR` + 5 digits, retried
against the unique index, fails loudly rather than handing out a duplicate). Condition — mod slots,
colours, neon, extras, livery, plate style, fuel, engine and body health — is captured from the client
that can actually see the entity and written back on store, on despawn, on disconnect and on a
`Config.SaveInterval` safety tick; every field is **coerced and clamped** server-side, so a patched
client can lie about its own fuel but cannot corrupt the row or reach another plate. `SpawnOwned()`
creates the entity **server-side** (OneSync) after checking ownership or keys, so a client cannot
conjure an owned car by asking. **Keys** are session-scoped (`Config.Keys.persist = false`) — a
courtesy, not an ownership record, which stays `character_vehicles.citizenid`; sharing them re-derives
both players' positions from the server-owned peds. The client-side engine cut is deliberately a
**soft** gate: the authoritative answer already came from `v-vehicles:hasKeys`.

**Showroom preview instance.** `client/preview.lua` creates the vehicle as a **local, non-networked**
entity at a point under the map and moves only the camera there — the player's ped never leaves, other
players see nothing, and the car cannot be entered or crashed into. That is what makes it an instance
rather than a spawned car. It is dressed with the **stored props from the row**, so the preview is the
car as it really is, and the camera distance is derived from the model's own dimensions so a bike and
a bus both frame sensibly. Shared surface — `v-garages` uses it today, the dealership next.

Exports: `GetOwned` / `GetOwnedByCid` / `GetVehicle` / `IsOwner` / `HasKeys` / `GiveKeys` /
`RemoveKeys` / `SpawnOwned` / `DespawnOwned` / `CreateOwned` / `IsLive` / `SetState` / `SetGarage`;
client-side `GetProps` / `ApplyProps` / `GetFuel` / `SetFuel` / `OpenPreview` / `ClosePreview` /
`RotatePreview` / `ZoomPreview` / `IsPreviewOpen`.

**Remaining.** No lockpick/hotwire path yet (the config reserves `hotwireTime` for it), no fuel
stations, no vehicle-damage → repair economy, and a vehicle whose entity vanishes is moved to
`impound` by the cleanup tick, which is a blunt rule that will want nuance once players test it.

### `v-licenses` ✅ — licences & permits
**Done.** New module, roadmap §5.3. The single answer to *"is this character allowed to do this"*.
The framework now has **three distinct permission concepts and they are not interchangeable**:
`v-core` permission is **staff**, a `v-jobs` job is **employment**, and a licence is **the law**.
Anything gating a real-world capability asks here.

One table (`character_licenses`: citizenid, type, status, points, issued, expires, issuer) and one
export — `Has(src, type)`. 12 types seeded (ID card, driving, motorcycle, HGV, taxi, boat, pilot,
weapon, hunting, fishing, medical, liquor), all **editable from the admin panel** (`license_types`):
key, issuer, price, validity in days, whether it needs a test.

Four states — valid / suspended / revoked / expired — plus a **demerit-points** system that suspends
automatically at the limit. Expiry is applied **lazily on read**, so a licence that lapsed while the
player was offline never reads as valid again.

**Who may issue** is the interesting rule: a *place* issuer (`cityhall`, `school`) serves anyone
standing there, but anything else is a **job** — an on-duty member of that job is the authority. That
is what makes a weapon permit a police decision rather than a shop transaction. Issuing to another
player re-derives both peds' positions server-side. A licence requiring a **test** can be renewed at
the city hall but never issued from nothing there; it is earned at the driving school.

The wallet lives in the **city hall panel** (new Licences tab) — the paperwork counter belongs at the
city hall, not in a module with its own UI.

Exports: `Has` / `HasByCid` / `Get` / `GetTypes` / `Grant` / `Revoke` / `Suspend` / `Reinstate` /
`AddPoints` / `LicenseForClass`.

**Remaining.** No actual driving *test* flow (the school grants it; the practical is a roleplay
gap), no physical ID-card item to show someone, and points are never added automatically because
`v-police` doesn't exist yet to add them.

### `v-vehicleshop` ✅ — dealerships
**Done.** New module, roadmap §5.1 step 3. Six dealerships (Premium Deluxe, Luxury Autos, bike, boat,
air, truck) each selling a **subset of categories**, and a **56-vehicle catalogue** with a deliberate
price ladder from a $9.5k Panto to a $1.65M Buzzard — including the four GTA electrics, so `v-fuel`'s
charging has customers.

Both the dealerships and the catalogue are `v-world` domains: model, label, category, price, **stock**
(-1 = unlimited), **required licence**, **job restriction** and enabled, all editable in the admin panel.

**The purchase is the sensitive part** and is ordered accordingly: the vehicle row is minted *first*,
then the charge; a failed charge deletes the row rather than gifting a car, and a failed mint has
charged nobody. One purchase in flight per player, so a double click cannot mint two cars. The
**licence gate is re-asked server-side**, never trusted from the browse payload.

**Test drive** is a *local, non-networked* vehicle on a timer that returns you exactly where you
started — it can never become an owned car. **Sell-back** pays a fraction of catalogue price scaled by
the car's actual condition, and refuses a vehicle that is still out of the garage.

The panel reuses `v-vehicles`' **showroom instance**: selecting a row stands the car up, drag to orbit.
A car you *cannot* buy still shows, dimmed, with the reason — the missing licence is the information.

**Automatic vehicle scan.** An admin runs a scan from the Editor → Vehicle catalogue; the
**client** enumerates every model it can actually spawn (base game *and* any addon pack
installed), reads its real class, display name, top speed and seat count, and suggests a
price from the model's own performance figures. The server keeps only what is missing from
the catalogue, re-validates every field, and holds the result until the admin reviews and
imports it — category and price editable per row. Adding a car pack is a two-click job
instead of hand-writing a config table, and **nothing reaches the catalogue because a
client said so**.

**Remaining.** No financing/instalments, no dealer-owned stock economy (stock is a number,
not a supply chain), and no player-run dealership.

### `v-mechanic` ✅ — per-part wear, odometer, diagnostics, repairs
**Done.** New module. Replaces "engine health" with a **20-part condition model** (12 for an EV):
engine, transmission, clutch, turbo, injectors, plugs, filters, fuel pump, radiator, exhaust, brakes,
suspension, steering, axle, tyres, battery, alternator, bodywork, glass — and for an electric car a
**traction battery, motor, inverter, BMS, charge port and coolant** instead of the parts it doesn't have.

**Wear has causes, not a timer.** Distance drives the baseline (per 100 km, scaled by each part's own
rate); **abuse** multiplies it — sustained redline hits the drivetrain, hard braking hits the brakes,
off-road hits the suspension; **collisions** damage the systems that took the hit, scaled by the body-health
delta; and **neglect** past the service interval accelerates everything. A gentle driver genuinely gets
more life out of a part, which is the only thing that makes parts interesting.

**You feel it before you read it.** Condition is applied through `SetVehicleEnginePowerMultiplier`,
`SetVehicleBrakeForceMultiplier` and `SetVehicleGripMultiplier`, ramping from `DegradeBelow` down to each
system's floor. A dead radiator bleeds engine health; a dead alternator kills the lights and stalls you.

**A real odometer** (`character_vehicles.mileage`, with `last_service`), incremented from actual distance
travelled and immune to teleports — a garage spawn is not mileage.

**Repair economy.** Every part is an **inventory item** (27 new ones, all craftable at the workbench or
the electronics bench), so a mechanic can stock or craft their own. A **shop** replaces a part outright
(part consumed + labour paid); a **repair kit** patches one back to 55 % in the field and refuses a part
below 15 % — a way home, not a free garage. A **full service** resets the interval and the consumables.
Shops are `world_mechshops` rows (position, blip, **job lock**, labour multiplier), editable in the admin
panel; a shop staffed by its own job is cheaper than the same shop used self-service.

Server-authoritative: the client observes the driving (it is the only side that can) but reports
**deltas only**, capped at 25 points per message, and the server never adds condition from a client
message. Every repair is priced, charged and consumed server-side.

Exports: `GetParts(plate)` / `GetShops()`; client `GetLocalParts` / `GetMileage` / `ScanNearby`.

**Remaining.** No tuning/cosmetic side (that is LSC's other half), no towing, no mechanic call-out job
flow, and `v-hud` shows neither the odometer nor a warning light yet.

### `v-fuel` ✅ — fuel types, consumption, stations
**Done.** New module. Owns everything fuel; `v-vehicles` keeps only the stored number.
**Four fuel types** — regular (91), premium (98), diesel and electric — each with its own price per
litre/kWh and an efficiency `rate`. What a vehicle accepts is derived from a **model override list**
first (the GTA EVs, the trucks) then its **class**; premium is accepted wherever regular is (same pump
family, better octane), everything else is a **wrong-fuel** mistake that is charged, announced and
**damages the engine** rather than silently ruining the car.

**Consumption** is load-based: an idle floor plus a term driven by real speed against the model's
estimated top speed, scaled by a per-class multiplier and the fuel's efficiency. A supercar at full
throttle drains far faster than a compact idling. Tank size is per class (16 L for a bike, 300 L for a
plane), which is what makes the litre maths and the price honest.

**18 stations** seeded from real GTA V pumps, including **3 electric charging points** (own blip, own
flow rate). Points live in `world_stations` — position, **which fuels are sold**, and a **price
multiplier** so a desert pump can cost more than a city one — all editable from the admin panel.

Server-authoritative: the price is re-derived from the server's own station and type tables, the
litres are **clamped to what the tank could physically hold**, and both the player *and the vehicle*
must be at the pump (the entity is re-read from its net id and measured). A patched client can ask for
9999 L; it gets billed for a tankful. The jerry can is an inventory item, and a failed grant refunds
the charge. fr+en.

**Electric is modelled as charging, not filling.** Three things make it behave like an EV: a **charge
curve** that tapers hard past 80 % (which is why "charge to 80" is a habit); **connector levels** — an
11 kW AC post, a 50 kW DC charger and a 150 kW ultra-fast unit, each with its own speed *and* its own
price per kWh, so the fast one is a real trade-off; and **battery health**, owned by `v-mechanic`'s
`battery_pack`, which derates usable capacity — an aged EV genuinely has less range. **Regenerative
braking** puts a little charge back when you slow down. The UI meters in kWh, not litres.

**Remaining.** No fuel theft/siphoning, no station ownership or revenue for a player-run business, and
`v-hud` does not show a fuel gauge yet.

### `v-garages` ✅ — store, retrieve, impound
**Done.** New module, roadmap §5.1 step 2. Garage points live in `world_garages` (editable from the
admin panel): id, label, **type** (`public` / `job` / `gang` / `impound`), the interaction point, a
**separate spawn point + heading** so a garage can sit indoors and deliver on the street, blip, a
**job/gang lock** reusing the clothing-store gate, a release fee and enabled. 9 real GTA V parking
structures ship as seed data, including the impound lot and the LSPD/EMS motor pools.

Server-authoritative throughout: `canUse()` re-derives the player's distance and job, `take` re-reads
the row's real `state`/`garage` instead of trusting the list the NUI was shown, and `store` re-reads
**the vehicle entity itself** from its net id, checks the plate on it and measures *its* distance —
parking a car you are not near is not possible. The impound fee is refunded if the spawn then fails.
Deleting a garage that still has cars parked in it is refused. EMBER NUI with per-vehicle
fuel/engine/body bars. fr+en.

**Remaining.** No per-garage capacity, and no shared/gang garage listing (it lists *your* cars only).
✅ The panel now shows a **live 3D preview**: selecting a row stands the car up in the v-vehicles
showroom instance, dragging the empty half of the screen orbits it and the wheel zooms.

### `v-world` ✅ — admin-editable world content

**Done.** The data layer behind the v-admin **Editor** tab. Owns five domains — `blips`, `shops`,
`jobs`, `items`, `recipes` — and is the only writer for `world_blips`, `world_shops`, `craft_recipes`,
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

### `v-cityhall` ✅ — city hall job desk

**Done.** New module. Three real civic buildings (LS City Hall, Sandy Shores, Paleto Bay) with a blip, a
clerk ped on a clipboard scenario, a ground marker + E prompt and a **v-target** zone. The NUI lists the
**open positions** — every job in the `jobs` table that is **not** `whitelisted` and not in
`Config.NeverPublic` — with its entry grade, starting pay and rank count, plus the player's current
contract and a **Resign** button.

Server-authoritative: `atCityHall(src)` re-derives the player's real distance from the server-owned ped,
and `take` **re-computes the open set server-side** rather than trusting the list the NUI was shown, so a
patched client cannot hand itself a police badge. The optional `Config.HireFee` is refunded if `SetJob`
then fails. Hires at grade 0 only. Both actions are audit-logged. fr+en.

**Remaining.** No application/interview flow (it's instant hire), no per-job player cap, no ID card or
civic paperwork — the desk only does jobs today.

### `v-admin` ✅ — management panel (F10)
**Performance.** The panel grew to 8 rail tabs, 13 editor domains and a settings registry,
and four things scaled badly: every keystroke in a search box rebuilt the whole list
synchronously; rows were appended one at a time (one reflow each); saving one setting
refetched the entire registry; and the editor truncated at 300 rows **silently**, which
reads as "that is everything". All four are fixed — searches are debounced (140 ms), lists
paint through a `DocumentFragment`, a saved setting is patched in place (one round trip
instead of two), and the list pages at 200 with an explicit **"show more (N)"**. The editor
subtabs are grouped **World / Economy / People** rather than 13 buttons in one wrapping row.

**Done.** Permission-gated NUI. **Dashboard** (uptime, players, resources, characters). **Players**
(searchable roster; goto / bring / heal / freeze / kick with reason / give money / give item /
set permission — superadmin only). **Scripts** (state of every module, restart / stop / start,
protected resources shielded). **World** (weather + time synced via `GlobalState` including late
joiners, vehicle spawner, server announcements). **Logs** (last 60 rows, category filter,
parameterized query). Every action validated server-side and audit-logged.

**Editor tab ✅** — the content-management surface `RULES.md` §3.6.2 requires. A rail tab with five
subtabs (**Blips / Stores / Jobs / Items / Craft**), a live search box, a list of existing rows and a
per-domain form: create, edit, delete, plus **"use my position"** for anything with coords. It is a thin
client over `v-world:list` / `v-world:save` / `v-world:delete` — the admin panel holds no content logic
of its own. Item forms lock the internal `name` when editing; recipe forms build ingredient rows
dynamically. Every write is permission-gated and audit-logged server-side.

**Tools tab ✅** — noclip (**F9**), god mode, invisible, player blips (ESP), spectate, self heal / revive /
armor, copy coordinates, open any player's inventory, and the **clothing thumbnail scan** (mode + category
picker). Admin tools are revoked automatically when a player is demoted. The scan used to be a double-press
F9 keybind plus a `/scanclothes` chat command; both are gone — that freed F9 for noclip and put every admin
action behind one permission gate.

**Remaining.**
- Editor coverage is not complete: **vehicles, gangs, gathering nodes, craft stations, shop price /
  sell lists** are still `config.lua`-only.
- Missing admin staples: **ban, warn, mute, teleport-to-waypoint, vehicle repair/delete**.
- `Actions.money` is **uncapped and unrated** — a compromised admin account can inflate the economy.
- The dashboard's `SELECT COUNT(*) FROM characters` has no `pcall`; a DB error leaves the NUI fetch
  hanging forever.
- Freeze state is tracked only in a client-side JS `Set`, so the label desyncs after a reopen.
- No confirmation on destructive actions; an admin can freeze or kick themselves.
- Spawned vehicles are never cleaned up.
- The `mod` tier is unused — the whole panel requires `admin`.
- Logs have no pagination and no free-text / time-range search.
- Direct SQL against `characters` and `logs`.

---

## 5. Not built yet — the roadmap

Everything below follows the two rules the rest of the framework already follows: **server-authoritative**
(never trust a client for money, ownership, position or permission) and **manageable in-game** (a
`v-world` domain + a v-admin Editor subtab, never a `config.lua` an operator has to edit on a live
server — `RULES.md` §3.6.2). Ordered by build order, not by wish.

### 5.1 Vehicles — the next big block

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 1 | ✅ **`v-vehicles`** — persistence & keys (**shipped**) | `v-core` | The foundation everything else in this block sits on. Owns `character_vehicles`: plate (unique), model, owner citizenid, **stored properties** (colours, mods, extras, livery, plate style), fuel, engine/body health, mileage, and a **state** (`garaged` / `out` / `impounded`). Persists a spawned vehicle's condition back to the row on despawn, on save-tick and on disconnect, so a car keeps its damage and mods. **Key system**: who may start/lock a given plate, giveable and revocable, checked server-side on engine start and lock toggle — a client-side lock check is not a lock. Plates are minted server-side and unique. |
| 2 | ✅ **`v-garages`** — storage & retrieval (**shipped**) | `v-vehicles` | Garage points (public, **job-owned**, gang-owned, house), each a `v-world` domain row: position, spawn point + heading, blip, type, and a **job/gang lock** reusing the same gate as the clothing stores. Store / retrieve / list, an **impound** that only releases against a fee, and per-garage capacity. Retrieval re-applies the stored properties from the DB — the garage is the only legitimate way an owned car enters the world. |
| 3 | ✅ **`v-vehicleshop`** — dealerships (**shipped**) | `v-vehicles`, `v-banking` | Concessions at the real GTA V dealerships (Premium Deluxe, Luxury Autos, bike/boat/plane sellers). A **catalogue editable from the admin panel** (model, category, price, stock, **licence required**, job/gang restriction, enabled) — the vehicle catalogue is a `v-world` domain like items and recipes, not a Lua table. Test drive on a timer that returns you where you started, purchase charges **server-side** and mints the `character_vehicles` row + plate atomically, then the car appears in the buyer's garage. Sell-back at a configurable rate. |
| 4 | 🔨 **`v-rentals`** — short-term hire (**next**) | `v-vehicles`, `v-garages` | Rental points (airport, train stations, PD/EMS motor pool). A **deposit** is taken, the vehicle is spawned with a temporary plate and a **timer**; returning it to any rental point refunds the deposit minus the fee, and an expired or destroyed rental keeps the deposit. Rentals never create a `character_vehicles` row — that is what separates a rental from a purchase and stops it becoming a free-car exploit. |

**Cross-cutting for the whole block:** ✅ **fuel is done** (`v-fuel` — one consumption model, four
fuel types, admin-editable stations),
a `v-vehicles` export surface (`GetOwned`, `HasKeys`, `GiveKeys`, `SpawnOwned`, `StoreOwned`) so
`v-police` can impound and `v-jobs` can hand out job vehicles without touching the DB, and **one
spawn path** — nothing else in the framework is allowed to `CreateVehicle` an owned car.

### 5.2 Organisations — factions, gangs, and running them

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 5 | **`v-factions`** — the shared org layer | `v-jobs`, `v-world` | One engine for **legal factions** (PD, EMS, mechanics, taxi, news) and **illegal ones** (gangs, mafias) — they differ by data, not by code. Owns membership, ranks (reusing `jobs.grades`), a **faction treasury** (a real account with its own transaction log, not a number in a config), owned garages/stashes/vehicles, and a territory concept for the illegal side. `gangs` already exists in the schema and is still empty. |
| 6 | **`v-bossmenu`** — the boss/patron panel | `v-factions`, `v-banking` | The management UI a faction leader actually needs, gated on **rank**, not on admin permission: **hire / fire / promote / demote** members, see who is on duty, **deposit & withdraw from the treasury** with a full audit trail, **pay salaries**, manage the faction's **garage and stash access per rank**, and set the recruitment state. Every action is server-verified against the caller's rank and logged — a boss menu that trusts the client is a money printer. |
| 7 | **`v-gangs`** — the illegal org flavour | `v-factions` | What `v-factions` doesn't share: **territories** (capture, influence decay, contested state), turf-gated drug sales, gang stashes and gang wars. Reuses the faction engine for membership and the treasury. |
| 8 | **`v-police`** | `v-factions`, `v-vehicles` | Cuffs, escort, search (reusing `v-inventory`'s `GetSearchable`, which already never exposes the hidden pocket), **evidence**, an MDT (records, warrants, BOLOs), fines, jail, and **impound** through `v-garages`. |

### 5.3 Papers — licences & permits

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 9 | ✅ **`v-licenses`** (**shipped**) | `v-core`, `v-factions` | The single source of truth for *"is this character allowed to do this"*. One table (`character_licenses`: citizenid, type, status, issued/expiry, issuer, points), one export (`Has(src, type)`), and a **licence type list editable from the admin panel** so a server can invent its own. Ships: **ID card**, **driving licence** (car / bike / truck / taxi), **boat**, **pilot**, **weapon permit**, **hunting**, **fishing**, and the job-side ones (medical, bar). Includes **suspension and revocation** (a licence taken by the PD, with points and expiry), and issuance flows: the **city hall** (`v-cityhall`, already built) for the paperwork, a **driving school** for the practical, the **PD** for weapon permits. Consumed everywhere: the dealership refuses a sale without the right licence, the weapon shop without a permit, and the PD can run a plate against the driver's status. |

### 5.4 The illegal economy, finished

The legal loop (gather → craft → sell) and a first illegal loop (grow → process → deal → launder) already
ship. What's missing is the depth and the **risk** side that makes them a game rather than a spreadsheet.

| # | Module | Depends on | Responsibility |
|---|--------|-----------|----------------|
| 10 | **`v-drugs`** — the full chain | `v-gangs`, `v-police`, `v-licenses` | Turn the current recipes into a real system: **plantations** with growth stages, watering and theft by other players; **labs** with quality tiers, failure chance and a **fire/explosion risk** if you rush; **NPC dealing** priced by district, demand decay and heat; **player-to-player** dealing; **addiction & effects** on the buyer (tied to `v-status`); and **police pressure** — a bust chance that scales with heat, dirty money that must go through `v-banking`'s laundering, and evidence that lands in `v-police`. |
| 11 | **Heists & robberies** | `v-police`, `v-inventory` | Stores, ATMs, jewellery, the Fleeca/Pacific jobs. Server-authoritative timers and loot tables, a **minimum police count** before a job can start, and dirty money as the payout so it feeds the laundering loop. |
| 12 | **`v-anticheat`** | `v-core` | The counterweight to all of the above: server-side sanity checks on money deltas, health, explosions, spawned entities and impossible movement, every trip logged to the existing audit log. |

### 5.5 Interaction surfaces & the rest

| Module | Priority | Responsibility |
|--------|----------|----------------|
| `v-phone` | high | iFruit phone NUI — a primary interaction surface (the server has no chat). Carries messages, calls, the faction/gang comms, dealer contacts and the licence wallet. |
| `v-radial` | high | Radial menu (context actions) — the other main interaction surface. |
| `v-houses` | medium | Property ownership, interiors, house garages and stashes. |
| `v-pausemenu` | medium | Custom pause menu (hosts settings, incl. HUD). |
| `v-weather` | low | Weather/time sync + in-game control (currently lives inside v-admin). |

### 5.6 Build order and why

1. **`v-vehicles` first.** Garages, dealerships, rentals, police impound and job vehicles all read the
   same ownership + key layer. Building any of them before it means building it twice.
2. **`v-licenses` early** — it is small, and the dealership, the weapon shop and the PD all need it.
   Adding it after those exist means retrofitting gates into three modules.
3. **`v-factions` before `v-gangs`, `v-police` and `v-bossmenu`.** They are the same engine with
   different data; writing the police module standalone would fork the membership/treasury code.
4. **`v-drugs` last of the economy work** — it depends on gangs (turf), police (pressure) and the
   laundering path, and it is the module most likely to need balancing once players are on the server.
5. **`v-anticheat` before the server opens**, not after. It is listed last because it guards
   everything above, not because it matters least.

**Every module in this roadmap ships with:** a `v-world` domain + a v-admin Editor subtab for its
content, fr **and** en locales, server-side re-derivation of every gate, and an entry in this file,
`CHANGELOG.md` and the module's own README (`RULES.md` §3.7).

---

## 6. Cross-cutting debt

Ordered by how much damage it can do.

1. **Economy holes.** The offline-transfer dupe in `v-banking`; the uncapped `AddMoney` in `v-core` and
   `v-admin`. Fix these before the server opens. ✅ **`v-shops`' ignored `RemoveMoney` is fixed** — the
   charge is checked and the item refunded on failure.
2. **Missing server-side authorization.** `v-banking` never checks that the player is actually near the
   ATM. `v-status:server:onRespawn` is an unvalidated self-cleanse. ✅ **`v-inventory` openStash is now
   server-authoritative** (vehicle trunks resolve by net id with a distance check + server-read plate;
   drops must be real; move/drop/give amounts are floored). ✅ **`v-shops` is now server-authoritative**
   too — `getShop`/`buy` verify the player is at a store mapping to that shop id and enforce `shops.job`.
3. **Client-trusted writes.** `v-core:createCharacter` and `saveAppearance` take unbounded, unvalidated
   client tables straight into the DB. `v-clothing` writes client-supplied drawable ids into item
   metadata.
4. **Five modules bypass the DB layer.** `v-inventory` (`stashes`, `items`), `v-banking`
   (`bank_transactions`, `characters`), `v-shops` (`shops`, `items`), `v-clothing` (`items`),
   `v-admin` (`characters`, `logs`). `v-core` should grow `GetShops` / `GetStash` / `SaveStash` /
   `InsertTransaction` / `GetLogs` / `CountCharacters` and the modules should stop pulling in `oxmysql`.
5. **Content management — mostly closed.** ✅ Blips, store positions, jobs & grades, **items** and
   **craft recipes** are now created / renamed / deleted in-game from v-admin → Editor, backed by
   `v-world`, with live reload. Still `config.lua`-only and therefore still in breach of
   `RULES.md` §3.6.2: vehicles, gangs, gathering nodes, craft **stations**, shop price & sell lists,
   clothing prices, status drain rates, HUD thresholds, notification behaviour, the protected-resource
   list.
6. **`server_config` table is dead** — built for live settings, never read or written.
7. **i18n leaks.** Hardcoded French in `v-banking`'s transfer notification and the whole
   `v-loadscreen` status line; hardcoded English `aria-label`s in `v-hud`; DB-sourced content strings
   (item labels, shop names) have no translation path at all.
8. **`RegisterKeyMapping` requires a backing `RegisterCommand`**, so `vinv`, `vhotbar1..5`,
   `vhud_settings` and `vadmin_panel` are technically typeable in chat. Server-side
   gating makes the admin ones inert for players. This is an accepted platform constraint, not a
   violation — but `giveitem` (v-inventory) and `status` / `givemoney` / `setperm`
   are genuine console commands that should migrate into `v-admin`.
9. **Dead config keys** in almost every module (`Config.Debug` in six of them, `Config.Accounts`,
   `Config.DefaultSpawn`, `Config.Max`).
10. **No per-module `README.md` / `CHANGELOG.md`**, which `RULES.md` §5 requires.

---

## 7. Writing a module (the pattern)

1. `resources/[local]/v-<name>/` with `fxmanifest.lua`.
2. Server: `local Core = exports['v-core']:GetCore()`, register callbacks, use `Core.GetPlayer`.
   **Never query SQL directly** — add the query to `v-core/server/database.lua`.
3. Client: `local Core = exports['v-core']:GetCore()`, listen to `v-core:client:*`, drive NUI.
4. NUI: `<link href="https://cfx-nui-v-ui/theme.css">` and compose the EMBER primitives
   (`RULES.md` §3.5). **The resource that owns the page calls `SetNuiFocus` itself.**
5. Every player-facing string goes through `L('key')` with fr **and** en entries.
6. Ship a permission-gated management UI in `v-admin` for anything an operator will want to tune.
   The cheap way: add a **domain to `v-world`** (table + loader + `list`/`save`/`delete` branch +
   `SeedX` export), a subtab + form to the v-admin Editor, and an
   `AddEventHandler('v-world:server:changed', …)` in your module that rebuilds its runtime tables.
   Seed your `config.lua` defaults with `INSERT IGNORE` — **never** `ON DUPLICATE KEY UPDATE`, which
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
                                                     --   (main inventory only — NEVER the hidden pocket)
exports['v-inventory']:GetLimits()                   -- { maxSlots, maxWeight, hotbar }
-- open a container client-side:
TriggerServerEvent('v-inventory:server:openStash', id, label, kind)

-- v-world (server) — admin-editable content, DB is the source of truth
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

-- v-notify (client only — no server export yet)
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
