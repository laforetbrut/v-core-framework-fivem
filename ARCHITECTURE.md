# v-core — Architecture & Module Guide

How the framework is wired and how every module talks to every other module.

## Layers

```
v-ui      → shared design system (theme.css). No logic.
v-core    → the framework: database, API, callbacks, persistent player object.
v-<module>→ feature resources (hud, banking, inventory, …). They NEVER touch SQL directly;
            they consume v-core's API and events.
```

Load order (in `server.cfg`): `oxmysql → v-ui → v-core → v-<modules>`.

## The v-core API

### Get the core
```lua
-- server or client
local Core = exports['v-core']:GetCore()
```

### Server — player object
```lua
local player = Core.GetPlayer(source)         -- object for a connected source
Core.GetPlayerByCitizenId('V4KD9P2A')         -- object by citizen id
Core.GetPlayers()                             -- array of all loaded players

player.citizenid, player.name, player.charinfo
player.money.cash / player.money.bank
player.job  = { name, grade }
player.gang = { name, grade }

player.AddMoney(account, amount, reason)      -- true/false, syncs client + fires event
player.RemoveMoney(account, amount, reason)   -- true/false (checks funds)
player.SetJob(name, grade)                    -- syncs client + fires event
player.SetGang(name, grade)
player.SetMetadata(key, value) / player.GetMetadata(key)
player.Save()                                 -- persist to DB (also autosaved + on drop)
```

### Server — callbacks (client asks, server answers)
```lua
Core.RegisterCallback('v-banking:getAccounts', function(source, resolve)
    local p = Core.GetPlayer(source)
    resolve({ cash = p.money.cash, bank = p.money.bank })
end)
```

### Client — data, callbacks, events
```lua
local data = exports['v-core']:GetPlayerData()   -- { citizenid, name, money, job, gang, ... }

Core.TriggerCallback('v-banking:getAccounts', function(accounts)
    -- do something with accounts
end)

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

## Writing a module (the pattern)

1. `resources/[local]/v-<name>/` with `fxmanifest.lua`.
2. Server: `local Core = exports['v-core']:GetCore()`, register callbacks, use `Core.GetPlayer`.
3. Client: `local Core = exports['v-core']:GetCore()`, listen to `v-core:client:*` events, drive NUI.
4. NUI: `<link href="https://cfx-nui-v-ui/theme.css">` for the shared look.
5. `ensure v-<name>` in `server.cfg` after `v-core`.

## Module roadmap

| Module | Status | Responsibility |
|--------|--------|----------------|
| `v-ui` | ✅ done | Shared design system (dark/orange theme tokens) |
| `v-core` | ✅ done | DB, API, callbacks, persistent player, money/job/gang, **permissions**, **logs**, **i18n (fr/en)** |
| `v-spawn` | ✅ done | Language selection → character creation → appearance editor (heritage/face/hair/details/clothing) |
| `v-status` | ✅ done | Hunger, thirst, stress, bleeding (injury), illness |
| `v-hud` | ✅ done | Fully customizable HUD: money + vitals rings + player settings panel |
| `v-banking` | 🔨 next | Fleeca/Maze Bank logic behind the phone bank app + ATMs |
| `v-inventory` | ⬜ | Item grid + pose menu, weight, use/drop/give, trunk/glovebox, gang stash |
| `v-phone` | ⬜ | iFruit phone NUI: apps (bank, contacts, messages, …) — a primary interaction surface |
| `v-radial` | ⬜ | Radial menu (context actions) — the other main interaction surface |
| `v-drugs` | ⬜ | GTA-lore drug system (grow/process/deal) |
| `v-police` | ⬜ | Police + investigation (evidence, MDT, cuffs, jail) |
| `v-inventory` | ⬜ | Item grid, weight, use/drop/give, registry from `items` table |
| `v-shops` | ⬜ | 24/7, Ammu-Nation, LSC… buy from `shops` table |
| `v-vehicles` | ⬜ | Garages, ownership (`character_vehicles`), keys, LSC |
| `v-jobs` | ⬜ | Jobs, grades, duty, salaries (`jobs` table) + in-game manager |
| `v-gangs` | ⬜ | Gangs & mafias, territories (`gangs` table) |
| `v-crafting` | ⬜ | Recipes → items, benches |
| `v-weather` | ⬜ | Weather/time sync + in-game control |
| `v-anticheat` | ⬜ | Server-side sanity checks, explosion/health/money guards, logged |
| `v-pausemenu` | ⬜ | Custom pause menu (hosts settings, incl. HUD) |
| `v-admin` | ⬜ | In-game panel: manage items, prices, shops, vehicles, jobs, players |

**Principles:** no player chat commands (phone/radial/pause UI only); every content system is manageable **in-game via permissions**; everything routes through `v-core` so modules stay decoupled. See `RULES.md` §3.5–3.6.

## Permissions, logs & status (v-core / v-status)
```lua
-- server
Core.HasPermission(source, 'admin')          -- user < mod < admin < superadmin
Core.SetPermission(source, 'mod')
Core.Log('economy', 'message', { any = 'data' }, citizenid)   -- console + logs table

-- v-status (server)
exports['v-status']:Get(source)               -- { hunger, thirst, stress, bleed, sick }
exports['v-status']:Add(source, 'hunger', 25) -- food/drink items call this
exports['v-status']:SetBleed(source, 0)       -- bandage / treatment
exports['v-status']:Heal(source)              -- EMS full cleanse
```

## i18n (fr / en)
Every resource does `shared_script '@v-core/locale/shared.lua'`, defines its own `Locales = { en = {...}, fr = {...} }`, and calls `L('key', ...)`. The player's language lives in `LocalPlayer.state.lang` (client) / `Player(src).state.lang` (server); use `LP(src, 'key')` server-side. NUI text is driven by sending `Locales[lang]` to the page. Default via `set vcore_lang "fr"`; each player picks their language in v-spawn.
