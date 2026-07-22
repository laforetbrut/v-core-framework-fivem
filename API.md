# v-core — API reference

> **Writing a new script? Start with [DEVELOPERS.md](DEVELOPERS.md).** One manifest line
> (`shared_script '@v-core/lib/v.lua'`) gives you `V.Ready`, `V.Module`, `V.Setting`,
> `V.Use`, `V.Callback` and `V.Notify` — this file is the raw surface underneath.
>
> **Vous écrivez un nouveau script ?** Commencez par [DEVELOPERS.md](DEVELOPERS.md) :
> une ligne de manifest remplace tout le passe-plat décrit ici.

Every export, callback and event the framework exposes. Generated against the source, so
what is listed here exists.

**Three permission concepts, never interchangeable:**

| Concept | Question it answers | Ask |
|---|---|---|
| `v-core` permission | *Is this person staff?* | `Core.HasPermission(src, 'admin')` |
| `v-jobs` job + grade | *Is this character on the payroll?* | `exports['v-jobs']:GetJob(src)` |
| `v-licenses` licence | *Is this character legally allowed to?* | `exports['v-licenses']:Has(src, 'driving')` |

New to the framework? Start with **[DEVELOPERS.md](DEVELOPERS.md)**.

---

## v-core — framework

```lua
local Core = exports['v-core']:GetCore()          -- server or client
```

### Player (server)
```lua
Core.GetPlayer(src)              -- nil | player object
Core.GetPlayerByCitizenId(cid)
Core.GetLicense(src)
```
The player object: `source`, `citizenid`, `license`, `charinfo{firstname,lastname,dob,sex}`,
`name`, `money{cash,bank}`, `job{name,grade}`, `gang{name,grade}`, `position`, `metadata`,
`inventory`, `appearance`, and:
```lua
player.AddMoney(account, amount, reason)     -- true/false
player.RemoveMoney(account, amount, reason)  -- true/false — ALWAYS check the return
player.GetMoney(account)
player.SetJob(name, grade)
player.SetMetadata(key, value) / player.GetMetadata(key)
```

### Callbacks
```lua
-- server
Core.RegisterCallback('my:thing', function(source, resolve, data) resolve(result) end)
-- client
Core.TriggerCallback('my:thing', function(result) end, data)
```

### Permissions, notifications, logs (server)
```lua
Core.HasPermission(src, 'user'|'mod'|'admin'|'superadmin')
Core.SetPermission(src, level)
Core.Notify(src, message, 'success'|'error'|'warning'|'info')
Core.Log(category, message, dataTable, citizenid)
```

### Module registry & settings
```lua
exports['v-core']:RegisterModule(name, { label=, category=, settings={...} })
exports['v-core']:GetSetting(name, key, fallback)
exports['v-core']:GetSettings(name)          -- whole table, defaults filled in
exports['v-core']:SetSetting(name, key, value)
exports['v-core']:GetModules() / IsModule(name)
```
Setting types: `number` (`min`/`max`/`step`), `bool`, `string` (`maxLength`), `select`
(`options`), `color`. See DEVELOPERS.md.

### Client
```lua
exports['v-core']:GetPlayerData()
exports['v-core']:MenuOpened() / MenuClosed() / IsAnyMenuOpen()
Core.GetSetting(module, key, fallback)       -- mirrored from the server
```

### Events
| Event | Side | Fired when |
|---|---|---|
| `v-core:server:onPlayerLoaded` | server | a character finished loading — `(src, player)` |
| `v-core:server:onMoneyChange` | server | `(src, account, amount, reason)` |
| `v-core:server:onJobChange` | server | job assigned |
| `v-core:server:permissionChanged` | server | `(src, level)` |
| `v-core:server:settingChanged` | server | `(module, key, value)` |
| `v-core:server:modulesReady` | server | the registry finished its first scan |
| `v-core:client:onPlayerLoaded` | client | local player data arrived |
| `v-core:client:onMoneyChange` / `onJobChange` / `onGangChange` | client | mirrored |
| `v-core:client:onSettingChanged` | client | `(module, key, value)` |

---

## v-world — admin-editable content

The single owner of every content table. 14 domains: `blips`, `shops`, `jobs`, `items`,
`recipes`, `clothstores`, `clothcats`, `garages`, `stations`, `mechshops`, `dealers`,
`vehcat`, `licenses`, `uitheme`.

```lua
exports['v-world']:IsReady()
exports['v-world']:GetBlips() / GetShopLocations() / GetJobs() / GetItems() / GetRecipes()
exports['v-world']:GetClothStores() / GetClothCategories() / GetGarages() / GetStations()
exports['v-world']:GetMechShops() / GetDealers() / GetVehicleCatalogue() / GetLicenseTypes()
exports['v-world']:RefreshDomain(domain)     -- reload + broadcast after an outside write
exports['v-world']:RefreshBlipsFor(src)      -- re-evaluate a player's visible blips

-- seeds: push a module's config defaults in once (see ARCHITECTURE §0c)
exports['v-world']:SeedJobs(t) / SeedRecipes(t) / SeedShopLocations(t) / SeedGarages(t)
exports['v-world']:SeedStations(t) / SeedMechShops(t) / SeedDealers(t)
exports['v-world']:SeedVehicleCatalogue(t) / SeedLicenseTypes(t)
exports['v-world']:SeedClothStores(t) / SeedClothCategories(t)
```

**`v-world:server:changed(domain)`** — fired after any edit. Rebuild your runtime tables here:
```lua
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'items' then rebuild() end
end)
```

Admin callbacks (permission-gated): `v-world:list` / `v-world:save` / `v-world:delete`.

---

## v-inventory — items

```lua
exports['v-inventory']:AddItem(src, name, count, metadata)   -- false if it doesn't fit
exports['v-inventory']:RemoveItem(src, name, count)
exports['v-inventory']:GetItemCount(src, name)
exports['v-inventory']:GetItems(src)
exports['v-inventory']:GetLimits()             -- { maxSlots, maxWeight, hotbar }
exports['v-inventory']:GetSearchable(src)      -- what a frisk may see; NEVER the hidden pocket
exports['v-inventory']:RegisterUsableItem(name, function(src, item) end)
exports['v-inventory']:OpenSharedStash(src, id)
```
Client-side a container is opened with
`TriggerServerEvent('v-inventory:server:openStash', id, label, kind)`.

---

## v-jobs / v-licenses — employment and the law

```lua
exports['v-jobs']:GetJob(src)                  -- { name, grade }
exports['v-jobs']:SetJob(src, name, grade)
exports['v-jobs']:IsOnDuty(src) / SetDuty(src, bool)
exports['v-jobs']:GetJobLabel(name) / GetGradeLabel(name, grade)
exports['v-jobs']:GetJobDefs()
-- fires v-jobs:server:changed(src, name, grade)

exports['v-licenses']:Has(src, type)           -- THE question
exports['v-licenses']:HasByCid(cid, type)
exports['v-licenses']:Get(src)                 -- every licence this character holds
exports['v-licenses']:GetTypes()
exports['v-licenses']:Grant(cid, type, issuer)
exports['v-licenses']:Revoke(cid, type) / Suspend(cid, type) / Reinstate(cid, type)
exports['v-licenses']:AddPoints(cid, type, n)  -- auto-suspends at the limit
exports['v-licenses']:LicenseForClass(gtaClass)
```

---

## v-vehicles / v-garages / v-vehicleshop / v-fuel / v-mechanic

### v-vehicles — ownership, keys, persistence (server)
```lua
exports['v-vehicles']:CreateOwned(cid, model, garage, props)  -- plate | nil, err
exports['v-vehicles']:SpawnOwned(src, plate, coords, heading) -- netid | nil, err
exports['v-vehicles']:DespawnOwned(plate, stateData, newState)
exports['v-vehicles']:GetOwned(src) / GetOwnedByCid(cid) / GetVehicle(plate)
exports['v-vehicles']:IsOwner(cid, plate) / IsLive(plate)
exports['v-vehicles']:HasKeys(src, plate) / GiveKeys(src, plate) / RemoveKeys(src, plate)
exports['v-vehicles']:SetState(plate, state) / SetGarage(plate, garage)
-- fires v-vehicles:server:spawned(src, plate, netid, row)
```
**Nothing else may spawn an owned vehicle.** `SpawnOwned` creates the entity server-side.

### v-vehicles — client
```lua
exports['v-vehicles']:GetProps(veh) / ApplyProps(veh, props)
exports['v-vehicles']:GetFuel(veh) / SetFuel(veh, pct)
exports['v-vehicles']:IsBuckled()     -- client: seatbelt state, for HUDs and EMS scripts

-- v-factions (server) — a faction is (name, kind) with kind = 'job' | 'gang'
exports['v-factions']:Get(name, kind)              -- definition, or nil
exports['v-factions']:GetGrades(name, kind)        -- [{ grade, name, salary, isboss }]
exports['v-factions']:GetMembers(name, kind)       -- [{ citizenid, names, grade, gradeLabel, online }]
exports['v-factions']:IsBoss(src, name, kind)
exports['v-factions']:GetGrade(src, name, kind)    -- the caller rank, or nil
exports['v-factions']:Hire(bySrc, cid, name, kind, grade)     -- bySrc = nil means the server itself
exports['v-factions']:Fire(bySrc, cid, name, kind)
exports['v-factions']:SetGrade(bySrc, cid, name, kind, grade)
exports['v-factions']:GetBalance(name, kind)
exports['v-factions']:Deposit(name, kind, amount, reason, byCid)   -- new balance, or nil + reason
exports['v-factions']:Withdraw(name, kind, amount, reason, byCid)
exports['v-factions']:GetTransactions(name, kind, limit)
exports['v-factions']:TrySalary(name, kind, amount, cid)  -- nil = not on treasury pay, true/false = paid or not
exports['v-factions']:ListFactions(kind)

-- v-gangs (server) — territory only; membership and treasury are v-factions
exports['v-gangs']:TurfAt(coords)      -- turfId, owner (or nil)
exports['v-gangs']:GetOwner(turfId)
exports['v-gangs']:InOwnTurf(src)      -- true, turfId when standing in own gang territory
exports['v-gangs']:GetState()          -- { [turfId] = { owner, influence, contested } }
exports['v-gangs']:GetTurfs()
exports['v-gangs']:SetOwner(turfId, gang, byCid)   -- hand over without a capture, logged
-- client: exports['v-gangs']:LocalTurf() -> turfId, owner

-- v-bossmenu owns no data: it is a rank gate over v-factions, and exposes no exports.
-- Open it from your own script with the same callbacks the NUI uses, e.g.
--   Core.TriggerCallback('v-bossmenu:open', function(data) end)

-- v-rentals (server)
exports['v-rentals']:GetActive(cid)   -- the caller's live hire row, or nil
exports['v-rentals']:IsRental(plate)  -- true if this plate is a live hire, not an owned car
exports['v-vehicles']:OpenPreview(model, props)   -- showroom instance (local entity)
exports['v-vehicles']:RotatePreview(dx) / ZoomPreview(dz) / ClosePreview() / IsPreviewOpen()
```

### v-garages / v-vehicleshop / v-fuel / v-mechanic
```lua
exports['v-garages']:GetGarages()
exports['v-vehicleshop']:GetCatalogue() / GetDealers()

exports['v-fuel']:GetStations() / GetTypes() / GetElectricModels()
exports['v-fuel']:GetBatteryHealth(plate) / GetUsableCapacity(nominal, plate)
exports['v-fuel']:GetFuelType(veh) / GetTankSize(veh) / IsElectric(veh)   -- client

exports['v-mechanic']:GetParts(plate) / GetShops()
exports['v-mechanic']:GetLocalParts(plate) / GetMileage(plate) / ScanNearby()  -- client
```

---

## v-status / v-clothing / v-appearance / v-target / v-notify / v-ui

```lua
-- v-status (server)
exports['v-status']:Get(src)          -- { hunger, thirst, stress, bleed, sick } — LIVE ref
exports['v-status']:Add(src, 'hunger', 25)
exports['v-status']:Set(src, key, value)
exports['v-status']:SetBleed(src, n) / SetSick(src, n) / Heal(src)
-- client: exports['v-status']:Get() plus the event below, which is how the HUD follows it
AddEventHandler('v-status:client:onUpdate', function(s) end)  -- s = the full status table

-- v-clothing (server)
exports['v-clothing']:GetWorn(src)            -- cat -> { item, drawable, texture }
exports['v-clothing']:Unequip(src, 'tops')
exports['v-clothing']:GetCategories()

-- v-appearance (client)
exports['v-appearance']:ApplyAppearance(a) / GetCurrentAppearance()
exports['v-appearance']:CaptureRef(kind, id) / ApplyRef(kind, id, ref)
exports['v-appearance']:OpenEditor(mode)      -- 'barber' | 'surgery' | 'tattoo'

-- v-target (client) — options are filtered by permission, job and a predicate
exports['v-target']:AddGlobalPlayer(opts) / AddGlobalPed(opts) / AddGlobalVehicle(opts)
exports['v-target']:AddGlobalObject(opts) / AddModel(models, opts) / AddEntity(ent, opts)
exports['v-target']:AddBoxZone(name, coords, len, wid, opts)
exports['v-target']:AddSphereZone(name, coords, radius, opts)
exports['v-target']:RemoveZone(name)

-- v-notify (client)
exports['v-notify']:show({ type='success', title='…', message='…', duration=4000 })
TriggerClientEvent('v-notify:show', src, { … })   -- from the server

-- v-ui (theme)
exports['v-ui']:Version()      -- client: current theme version
exports['v-ui']:Push()         -- client: push the theme into THIS resource's NUI
exports['v-ui']:GetPresets()   -- server
exports['v-ui']:Rebuild()      -- server: regenerate theme-vars.css
exports['v-world']:GetUiThemes()   -- server: the per-module overrides
```

### Theming your page
The global theme lives in `v-ui/config.lua` + **Admin -> Settings -> Interface**. A single
module can override it in **Admin -> Editor -> Look -> Module themes** — preset, accent,
panel transparency, backdrop, roundness, motion, font scale — and **anything left blank is
inherited**.

`theme.js` stamps the owning resource onto `<html data-vmod="…">`, and the generated
stylesheet carries a scoped block per module:
```css
:root { /* global */ }
:root[data-vmod="my-script"] { /* only the overrides */ }
```
So your page is themeable the moment it links the three files — including per-module, with
no change to v-ui.

---

## Writing a NUI page

```html
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css" />       <!-- primitives -->
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme-vars.css" />  <!-- palette -->
<script src="https://cfx-nui-v-ui/theme.js"></script>                 <!-- live re-theme -->
```
Then compose the shared primitives: `.v-panel`, `.v-chamfer`, `.v-tab`, `.v-brk`,
`.v-progress` + `.v-progress__fill`, `.v-scroll`, `.v-glass`. **Never hardcode a colour** —
use the `--v-*` variables, or an admin's theme change will skip your page.

The resource that owns the page calls `SetNuiFocus` itself; focus is per-resource.

---

# v-core — Référence API (Version Française)

Chaque export, callback et événement exposé par le framework. Généré depuis les sources :
ce qui est listé ici existe.

**Trois notions de permission, jamais interchangeables :**

| Notion | Question | Appel |
|---|---|---|
| Permission `v-core` | *Est-ce un membre du staff ?* | `Core.HasPermission(src, 'admin')` |
| Métier `v-jobs` | *Est-ce un employé ?* | `exports['v-jobs']:GetJob(src)` |
| Licence `v-licenses` | *En a-t-il légalement le droit ?* | `exports['v-licenses']:Has(src, 'driving')` |

Les signatures sont identiques dans les deux langues — la section anglaise ci-dessus fait
foi pour les noms. Ce qui suit en résume l'usage.

## L'essentiel

```lua
local Core = exports['v-core']:GetCore()

-- joueur
local p = Core.GetPlayer(src)
p.AddMoney('cash', 100, 'raison')
p.RemoveMoney('bank', 50, 'raison')   -- TOUJOURS vérifier le retour
p.SetJob('police', 2)

-- callbacks
Core.RegisterCallback('mon:truc', function(source, resolve, data) resolve(res) end)
Core.TriggerCallback('mon:truc', function(res) end, data)   -- côté client

-- permission staff / notification / journal
Core.HasPermission(src, 'admin')
Core.Notify(src, 'texte', 'success')
Core.Log('categorie', 'message', donnees, citizenid)
```

## Réglages et registre de modules

```lua
exports['v-core']:RegisterModule('mon-script', { label=, category=, settings={...} })
local v = exports['v-core']:GetSetting('mon-script', 'cle')
AddEventHandler('v-core:server:settingChanged', function(mod, key, value) end)
```
Types : `number`, `bool`, `string`, `select`, `color`. Guide : **[DEVELOPERS.md](DEVELOPERS.md)**.

## Contenu modifiable en jeu

Un *réglage* est un nombre. Une *liste* est un **domaine `v-world`** avec son sous-onglet
dans l'Éditeur. Amorce toujours avec `INSERT IGNORE`, jamais
`ON DUPLICATE KEY UPDATE` — sinon un redémarrage efface les modifications de l'admin.

```lua
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'items' then reconstruire() end
end)
```

## Règles de la maison

- Locales **fr et en** pour chaque texte joueur.
- **Aucune commande chat** : touches, œil de ciblage, téléphone ou NUI.
- **Revérifier chaque contrôle côté serveur** — un test de distance client est de l'UX.
- **Aucune couleur en dur** dans une NUI : utilise les variables `--v-*`, sinon le
  changement de thème d'un admin ignorera ta page.
