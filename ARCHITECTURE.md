# v-core — Architecture & Module Guide

How the framework is wired, what each module actually does today, and what is left to build.

Last surveyed: **2026-07-10** (every module read end-to-end; see `## Per-module status`).

---

## 0. Build progress — inventory & appearance

Quick tracker for the two big in-flight workstreams. `✅ done · 🔨 in progress · ⬜ not started`.

### Appearance suite (rebuild — full plan in `memory/appearance-suite-plan.md`)

| Phase | What it delivers | State |
|-------|------------------|-------|
| **1 — engine + stable identity** | `v-appearance` module = single ped writer; clothing stored as stable **(collection, local index, texture)** refs (survives addon/build changes); v1→v2 migration on load; v-spawn + v-clothing delegate rendering; `appearance` added to autosave. | ✅ **done** |
| **2 — creator / barber / surgery / tattoos** | Re-openable editor (barber, surgeon, tattoo studio); fix the dead controls (blush overlay missing, makeup/lipstick opacity 0, unclamped ranges); tattoo apply + `character_tattoos` persistence. | ⬜ |
| **3 — catalogue + scanner rebuild** | `clothing_catalogue` table; per-gender scan; CEF colour extraction; real `.webp` storage (not loose `.txt`); replace-clothing detection; incremental/resumable scan. | ⬜ |
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
| 2 | Weapons & attachments (serial/ammo metadata exists; attachments/on-back/draw anims don't) | ⬜ |
| 3 | Shared stashes **with permissions** | ⬜ |
| 4 | Advanced shops with a **basket** (drag-to-buy + inventory view now shipped in v-shops) | 🔨 partial |
| 5 | Advanced crafting (recipes, benches) | ⬜ |
| 6 | Inventory customization (colours, transparency, centered mode) | ⬜ |
| 7 | Backpacks + armor DLC | ⬜ |
| 8 | Place items in the world as entities + **player search / steal** (the `GetSearchable` export is ready for it) | ⬜ |
| 9 | Bonus: vending machines, garbage job, skill tree | ⬜ |

Also outstanding on inventory (from the audit, not yet fixed): item degradation over time, weapon serial/ammo persistence, in-world drops as real entities (currently markers), and moving the direct-SQL `stashes`/`items` access behind `v-core`.

### Recently fixed bugs (this session)

- **No mouse in any menu** — `SetNuiFocus` is resource-scoped; `v-core` had no `ui_page`, so the shared focus helper was a silent no-op. Each owning resource now takes focus itself.
- **Spawn fell into the void / showed a default ped** — screen held black from the first frame; ped kept frozen while collision streams + ground is found; unfrozen only after the switch-in.
- **Inventory drag broken + imageless items** — see the two ✅ rows above.

---

## 1. Layers

```
v-ui        → shared design system (theme.css). No logic, no Lua.
v-core      → the framework: database, API, callbacks, permissions, i18n, logs,
              persistent player object.
v-<module>  → feature resources (hud, banking, inventory, …).
              They consume v-core's API and events.
```

Load order (`server.cfg`): `oxmysql → screenshot-basic → v-loadscreen → v-ui → v-notify → v-core → v-spawn → v-status → v-hud → v-banking → v-inventory → v-shops → v-clothing → v-admin`.

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

Schema lives in **`database/schema.sql`** (10 tables). MariaDB, accessed through `oxmysql`.

| Table | Owner | Purpose | State |
|-------|-------|---------|-------|
| `users` | v-core | account per license: name, language, permission, last_seen | ✅ used |
| `characters` | v-core | identity, cash/bank, job, gang, position, metadata, inventory, appearance | ✅ used (`slot` column unused — multi-character not implemented) |
| `items` | v-core (schema) | item definitions (name, label, weight, stackable, usable, category, metadata) | ✅ used, but seeded by **v-inventory** and **v-clothing** directly |
| `logs` | v-core | structured audit log | ✅ used (read directly by v-admin) |
| `bank_transactions` | v-banking | deposit / withdraw / transfer_in / transfer_out audit | ✅ used (direct SQL) |
| `stashes` | v-inventory | persistent containers (stashes, gang boxes, ground drops) | ✅ used (created + queried directly) |
| `shops` | v-shops | shop catalogue + prices | ⚠️ read at boot only; `coords` column **dead** (locations hardcoded) |
| `character_vehicles` | — | vehicle ownership | ⬜ **empty — v-vehicles not built** |
| `jobs` | — | jobs & grades | ⬜ **empty — v-jobs not built** |
| `gangs` | — | gangs & grades | ⬜ **empty — v-gangs not built** |
| `server_config` | — | live server settings | ⬜ **empty — never read or written by anything** |

---

## 4. Per-module status

Legend: ✅ shipped · ⚠️ shipped with a known hole · ⬜ not built.

### `v-ui` ✅ — shared design system
**Done.** `theme.css` only: the full "Field Case" token set (warm-charcoal surfaces, orange-only
accent, muted status + rarity scales, chamfer geometry, `--z-*` scale, motion tokens) plus the
primitives `.v-chamfer` / `.v-tab` / `.v-brk` / `.v-slot` / `.v-gauge` / `.v-btn` / `.v-chip` /
`.v-stencil` / `.v-input`, a global `:focus-visible` ring and a `prefers-reduced-motion` block.
CEF-103 safe. No SQL, no Lua, no exports.

**Remaining.**
- No shared JS runtime — every module re-implements the `--i` stagger, gauge fill and `.is-over`
  toggling in its own `app.js`. That is the copy-paste drift the single-source rule exists to stop.
- `--v-rar-legendary` is byte-identical to `--v-accent`, so a legendary item is indistinguishable
  from ordinary accented chrome.
- No `dependencies{}` block: if `v-ui` fails to start, every NUI page renders unstyled **silently**.
- No cache-busting on the stylesheet URL.
- `v-loadscreen` cannot link it (loads pre-mount) and mirrors the tokens locally — they will drift.

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
line icons, chamfered Field Case cards, XSS-safe escaping, click-to-dismiss, countdown bar,
`aria-live` region.

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
**Done.** 40 slots / 30 kg, 5-slot hotbar (keys 1-5), **TAB** to open. 170-item catalogue with local
images, seeded on boot with `ON DUPLICATE KEY UPDATE`. Drag & drop (move / swap / merge / shift-split),
right-click actions (use / give / split / rename / drop), search, tooltip with rarity / serial / ammo /
durability. **Cash as an item** — a virtual wallet tile mirroring the account, which stays the single
source of truth (no dupe path). Vehicle trunk + glovebox, persistent stashes, ground drops.
**Equipment panel** — clothing as body slots, drag to equip, right-click to unequip (driven by
v-clothing's `GetWorn` / `Unequip`). Server-authoritative: every action re-renders from the returned
state. Field Case NUI.

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

**Remaining.**
- **No server-side proximity check** on `getShop` / `buy`. A client can buy any shop's catalogue from
  anywhere on the map.
- **`shops.job` is loaded but never enforced** — a job-locked store (a police armory) is buyable by
  anyone. Combined with the point above, this is the module's most serious hole.
- `RemoveMoney`'s return value is **ignored** after `AddItem` has already granted the items. Safe only
  because nothing yields between them today — a latent free-item dupe.
- Purchase amount is unbounded server-side (the 1-99 clamp lives only in the client stepper).
- `ItemDefs[data.item].label` is indexed unguarded on the success path — an orphaned shop row throws
  *after* the money is taken and the item granted.
- Locations hardcoded in `config.lua`; the `shops.coords` column built to hold them is **dead**.
- Data is loaded **once at boot** — any DB price edit needs a full `restart v-shops`.
- Direct SQL against `items` and `shops`.
- No in-game management UI (`config.lua` literally says *"editable in-game later"*).
- The NUI silently ignores `{error='funds'|'space'}`.

### `v-clothing` ✅ — clothing store
**Done.** Proximity store (5 branded locations, streamed shopkeepers), live on-ped preview with a
drag-orbit camera, per-drawable texture picker, buy-as-item, equip by using the item (swaps the worn
piece back to inventory), unequip from the wardrobe tab or via the `Unequip` export. **Admin
thumbnail scanner**: studio teleport, bare-vs-dressed pixel diff so only the garment survives on a
transparent background, crop + downscale in the NUI, one-shot-token HTTP upload (works around the
net-event size kick), lazy batched loading. 1848 thumbnails already generated. Arms are free.

Exports: `Unequip(src, catKey)` / `GetWorn(src)`.

**Remaining.**
- **Gender blindness.** Thumbnails are captured on the *admin's* ped and stored as one set, but
  freemode drawable indices differ between `mp_m` and `mp_f`. A female player browses images shot on a
  male ped, and a purchased item maps to a different garment on another model.
- **Item loss bug:** `equip()` and `doUnequip()` ignore `AddItem`'s return value — with a full
  inventory, the swapped-out garment is silently destroyed.
- The buy payload's `drawable` / `texture` are **client-trusted and unvalidated** (the server cannot
  call the ped natives), so arbitrary or dev components are purchasable.
- Buying with a full inventory fails **silently** — no notification and no locale key for it.
- No accessories yet: bag, watch, ring, necklace, vest, armor.
- Flat per-category pricing; no per-drawable price, rarity or stock.
- Direct SQL: `INSERT IGNORE INTO items` on boot.
- Thumbnails are 1848 loose base64 `.txt` files + an `index.json` under the resource.
- `screenshot-basic` and `oxmysql` are not declared in `dependencies{}`.

### `v-admin` ✅ — management panel (F10)
**Done.** Permission-gated NUI. **Dashboard** (uptime, players, resources, characters). **Players**
(searchable roster; goto / bring / heal / freeze / kick with reason / give money / give item /
set permission — superadmin only). **Scripts** (state of every module, restart / stop / start,
protected resources shielded). **World** (weather + time synced via `GlobalState` including late
joiners, vehicle spawner, server announcements). **Logs** (last 60 rows, category filter,
parameterized query). Every action validated server-side and audit-logged.

**Remaining.**
- **It does not yet manage content.** `RULES.md` §3.6.2 says every content system must be
  create/modify/delete-able in-game from here. There is **no UI for jobs, grades, prices, shops,
  items, vehicles, or any module's config**. This is the single biggest gap between the stated
  architecture and the code.
- Missing admin staples: **ban, warn, mute, spectate, noclip, revive-other, teleport-to-waypoint,
  vehicle repair/delete, inventory viewing**.
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

## 5. Not built yet

| Module | Priority | Responsibility |
|--------|----------|----------------|
| `v-vehicles` | 🔨 **next** | Garages, ownership (`character_vehicles` table already in the schema), keys, LSC |
| `v-phone` | high | iFruit phone NUI — a primary interaction surface (the server has no chat) |
| `v-radial` | high | Radial menu (context actions) — the other main interaction surface |
| `v-jobs` | high | Jobs, grades, duty, salaries (`jobs` table exists) + in-game manager |
| `v-pausemenu` | medium | Custom pause menu (hosts settings, incl. HUD) |
| `v-crafting` | medium | Recipes → items, benches |
| `v-anticheat` | medium | Server-side sanity checks; explosion / health / money guards, logged |
| `v-weather` | low | Weather/time sync + in-game control (currently lives inside v-admin) |
| `v-gangs` | low | Gangs & mafias, territories (`gangs` table exists) |
| `v-police` | low | Police + investigation (evidence, MDT, cuffs, jail) |
| `v-drugs` | low | GTA-lore drug system (grow / process / deal) |

---

## 6. Cross-cutting debt

Ordered by how much damage it can do.

1. **Economy holes.** The offline-transfer dupe in `v-banking`; the ignored `RemoveMoney` result in
   `v-shops`; the uncapped `AddMoney` in `v-core` and `v-admin`. Fix these before the server opens.
2. **Missing server-side authorization.** `v-shops` and `v-banking` never check that the player is
   actually near the shop/ATM, and `shops.job` is loaded but never enforced. `v-status:server:onRespawn`
   is an unvalidated self-cleanse.
3. **Client-trusted writes.** `v-core:createCharacter` and `saveAppearance` take unbounded, unvalidated
   client tables straight into the DB. `v-clothing` writes client-supplied drawable ids into item
   metadata.
4. **Five modules bypass the DB layer.** `v-inventory` (`stashes`, `items`), `v-banking`
   (`bank_transactions`, `characters`), `v-shops` (`shops`, `items`), `v-clothing` (`items`),
   `v-admin` (`characters`, `logs`). `v-core` should grow `GetShops` / `GetStash` / `SaveStash` /
   `InsertTransaction` / `GetLogs` / `CountCharacters` and the modules should stop pulling in `oxmysql`.
5. **Nothing is manageable in-game.** Every module's tunables (shop prices and locations, clothing
   prices, status drain rates, HUD thresholds, notification behaviour, the protected-resource list)
   live in `config.lua` with no permission-gated UI, which is exactly what `RULES.md` §3.6.2 forbids.
   `v-admin` is the intended home for all of it.
6. **`server_config` table is dead** — built for live settings, never read or written.
7. **i18n leaks.** Hardcoded French in `v-banking`'s transfer notification and the whole
   `v-loadscreen` status line; hardcoded English `aria-label`s in `v-hud`; DB-sourced content strings
   (item labels, shop names) have no translation path at all.
8. **`RegisterKeyMapping` requires a backing `RegisterCommand`**, so `vinv`, `vhotbar1..5`,
   `vhud_settings`, `vadmin_panel` and `vclothing_scan` are technically typeable in chat. Server-side
   gating makes the admin ones inert for players. This is an accepted platform constraint, not a
   violation — but `giveitem` (v-inventory) and `scanclothes` / `status` / `givemoney` / `setperm`
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
4. NUI: `<link href="https://cfx-nui-v-ui/theme.css">` and compose the Field Case primitives
   (`RULES.md` §3.5). **The resource that owns the page calls `SetNuiFocus` itself.**
5. Every player-facing string goes through `L('key')` with fr **and** en entries.
6. Ship a permission-gated management UI in `v-admin` for anything an operator will want to tune.
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
