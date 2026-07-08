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
| `v-core` | ✅ done | DB, API, callbacks, persistent player, money/job/gang |
| `v-hud` | ✅ done | Money HUD (+ later: health/armor/hunger/thirst/voice) |
| `v-banking` | ⬜ next | ATM + bank UI, transfers, transaction log |
| `v-inventory` | ⬜ | Item grid, weight, use/drop/give, item registry from `items` table |
| `v-shops` | ⬜ | Shop peds/markers, buy from `shops` table |
| `v-vehicles` | ⬜ | Garages, ownership (`character_vehicles`), keys |
| `v-jobs` | ⬜ | Job system + duty + salaries (`jobs` table) |
| `v-gangs` | ⬜ | Gangs & mafias, territories (`gangs` table) |
| `v-phone` | ⬜ | Phone NUI: messages, contacts, apps |
| `v-radial` | ⬜ | Radial menu (context actions) |
| `v-pausemenu` | ⬜ | Custom pause menu |
| `v-admin` | ⬜ | In-game admin panel: manage items, prices, shops, vehicles, players |

Everything routes through `v-core` so modules stay decoupled and hot-swappable.
