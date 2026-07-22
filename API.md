# v-core - API reference

> **Writing a new script? Start with [DEVELOPERS.md](DEVELOPERS.md).** One manifest line
> (`shared_script '@v-core/lib/v.lua'`) gives you `V.Ready`, `V.Module`, `V.Setting`,
> `V.Use`, `V.Callback` and `V.Notify` - this file is the raw surface underneath.
>
> **Vous écrivez un nouveau script ?** Commencez par [DEVELOPERS.md](DEVELOPERS.md) :
> une ligne de manifest remplace tout le passe-plat décrit ici.

Every export, callback and event a script outside the framework would reach for. Checked
against the source, so **everything listed here exists**; a handful of internal helpers in
`v-appearance`, `v-clothing` and `v-vehicleshop` are deliberately left out, and the source
is the authority if you need them.

**Three permission concepts, never interchangeable:**

| Concept | Question it answers | Ask |
|---|---|---|
| `v-core` permission | *Is this person staff?* | `Core.HasPermission(src, 'admin')` |
| `v-jobs` job + grade | *Is this character on the payroll?* | `exports['v-jobs']:GetJob(src)` |
| `v-licenses` licence | *Is this character legally allowed to?* | `exports['v-licenses']:Has(src, 'driving')` |

New to the framework? Start with **[DEVELOPERS.md](DEVELOPERS.md)**.

---

## v-core - framework

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
player.RemoveMoney(account, amount, reason)  -- true/false - ALWAYS check the return
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
| `v-core:server:onPlayerLoaded` | server | a character finished loading - `(src, player)` |
| `v-core:server:onMoneyChange` | server | `(src, account, amount, reason)` |
| `v-core:server:onJobChange` | server | job assigned |
| `v-core:server:permissionChanged` | server | `(src, level)` |
| `v-core:server:settingChanged` | server | `(module, key, value)` |
| `v-core:server:modulesReady` | server | the registry finished its first scan |
| `v-core:client:onPlayerLoaded` | client | local player data arrived |
| `v-core:client:onMoneyChange` / `onJobChange` / `onGangChange` | client | mirrored |
| `v-core:client:onSettingChanged` | client | `(module, key, value)` |

---

## v-world - admin-editable content

The single owner of every content table. **28 domains**: `blips`, `shops`, `jobs`,
`gangs`, `items`, `recipes`, `clothstores`, `clothcats`, `garages`, `rentals`, `stations`,
`mechshops`, `dealers`, `vehcat`, `licenses`, `turfs`, `charges`, `drugs`, `radio`,
`jukebox`, `nodes`, `benches`, `spawns`, `cityhall`, `appspots`, `properties`, `factions` (treasuries) and `uitheme` (per-module themes).

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

**`v-world:server:changed(domain)`** - fired after any edit. Rebuild your runtime tables here:
```lua
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'items' then rebuild() end
end)
```

Admin callbacks (permission-gated): `v-world:list` / `v-world:save` / `v-world:delete`.

---

## v-inventory - items

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

## v-jobs / v-licenses - employment and the law

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

### v-vehicles - ownership, keys, persistence (server)
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

### v-vehicles - client
```lua
exports['v-vehicles']:GetProps(veh) / ApplyProps(veh, props)
exports['v-vehicles']:GetFuel(veh) / SetFuel(veh, pct)
exports['v-vehicles']:IsBuckled()     -- client: seatbelt state, for HUDs and EMS scripts
exports['v-vehicles']:IsLocked(plate)         -- server + client
exports['v-vehicles']:SetLocked(plate, bool)  -- server: for police impound, scripted scenes
-- client: exports['v-vehicles']:GetIndicator() -> { left, right, hazards }

-- v-factions (server) - a faction is (name, kind) with kind = 'job' | 'gang'
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

-- v-world (server) - read the admin-editable world content. Everything the Editor
-- manages is readable, so a third-party script never needs its own copy of a shop list.
exports['v-world']:IsReady()
exports['v-world']:GetBlips() / GetShopLocations() / GetJobs() / GetGangs()
exports['v-world']:GetItems() / GetRecipes() / GetClothStores() / GetClothCategories()
exports['v-world']:GetGarages() / GetRentals() / GetStations() / GetMechShops()
exports['v-world']:GetDealers() / GetVehicleCatalogue() / GetLicenseTypes()
exports['v-world']:GetTurfs() / GetCharges() / GetUiThemes()

-- v-vehicles - ownership, keys and the showroom
exports['v-vehicles']:GetOwned(src) / GetOwnedByCid(cid) / GetVehicle(plate)
exports['v-vehicles']:IsOwner(cid, plate) / IsLive(plate)
exports['v-vehicles']:HasKeys(src, plate) / GiveKeys(src, plate) / RemoveKeys(src, plate)
exports['v-vehicles']:SpawnOwned(src, plate, coords, heading)   -- the ONLY legitimate spawn path
exports['v-vehicles']:DespawnOwned(plate, data, state)
exports['v-vehicles']:CreateOwned(cid, model, garage, props)
exports['v-vehicles']:SetState(plate, state) / SetGarage(plate, garage) / SetFuel(veh, n)
exports['v-vehicles']:GetProps(veh) / ApplyProps(veh, props)
-- client: HasKeysLocal(plate), IsBuckled(), and the showroom
--   OpenPreview / ClosePreview / RotatePreview / ZoomPreview / IsPreviewOpen

-- v-fuel (client)
exports['v-fuel']:IsElectric(veh) / GetFuelType(veh) / GetTankSize(veh)
-- server: GetStations(), GetTypes(), GetElectricModels(), GetBatteryHealth(plate),
--         GetUsableCapacity(nominal, plate)

-- v-mechanic
exports['v-mechanic']:GetShops()                    -- server
exports['v-mechanic']:GetLocalParts(plate) / GetMileage(plate) / ScanNearby()   -- client

-- v-target (client) - the interaction eye. Every Add* returns handles you can remove.
exports['v-target']:AddGlobalPlayer(options) / AddGlobalPed(options)
exports['v-target']:AddGlobalVehicle(options) / AddGlobalObject(options)
exports['v-target']:AddSelf(options)               -- shown when pointing at nothing
exports['v-target']:AddModel(models, options) / AddEntity(netId, options)
exports['v-target']:AddBoxZone(name, coords, size, options, { heading, label })
exports['v-target']:AddSphereZone(name, coords, radius, options, { label })
exports['v-target']:AddPolyZone(name, points, options, { z, height, label })
exports['v-target']:RemoveZone(name) / ZoneExists(name)
exports['v-target']:RemoveGlobal(group, ids) / RemoveModel(model, ids) / RemoveEntity(netId)
exports['v-target']:RemoveResource(name)           -- everything one resource registered
exports['v-target']:IsActive() / Close() / GetTarget() / PeekOptions()

-- v-licenses (server) - the rest of the sanction surface
exports['v-licenses']:Suspend(cid, key) / Reinstate(cid, key)

-- v-status (server)
exports['v-status']:Heal(src) / SetSick(src, level)

-- v-notify (client)
exports['v-notify']:Show({ type =, title =, message =, duration = })

-- v-core - the rest of the registry and the NUI focus bookkeeping
exports['v-core']:IsModule(name) / GetRawSetting(name, key) / IsOverridden(name, key)
exports['v-core']:MenuOpened(name, keepInput) / MenuClosed(name) / IsAnyMenuOpen()

-- v-core world policy (client) - what the GAME is allowed to do on its own
exports['v-core']:SetWorldPolicy(key, value)   -- override a setting for a scripted scene
exports['v-core']:ClearWorldPolicy(key)        -- nil clears every override
exports['v-core']:GetWorldPolicy()             -- { applied = {...}, overrides = {...} }
-- keys: npcPolice, maxWanted, npcEmergency, randomCops, randomEvents,
--       randomTrains, randomBoats, garbageTrucks

-- Events with no internal handler, on purpose: they exist for YOU to listen to.
-- The registry lists them, and nothing in the framework consumes them.
--   v-core:server:modulesReady          -- every module has declared itself
--   v-core:server:serviceRegistered     -- (service, resource)
--   v-core:client:onJobChange           -- (job table)
--   v-core:client:onGangChange          -- (gang table)
--   v-factions:server:membershipChanged -- (faction, kind, cid, action, grade)
--   v-factions:server:treasuryChanged   -- (faction, kind, balance, delta)
--   v-status:client:onUpdate            -- (full status table)

-- v-core integration layer (server) - the toolkit third-party scripts plug into.
-- Prefer the V helper in DEVELOPERS.md; these are what it calls.
exports['v-core']:ProvideService(service, providerExport)
exports['v-core']:GetService(service)          -- resource name, or nil when it is down
exports['v-core']:ListServices()
exports['v-core']:RegisterHook(hook, fnExport, priority)
exports['v-core']:RunHook(hook, payload)       -- payload, or nil when vetoed
exports['v-core']:ListHooks()
exports['v-core']:SetModuleEnabled(name, bool) -- a real resource start/stop
exports['v-core']:GetRegistry()                -- modules, services, hooks, events, commands
exports['v-core']:NoteEvent(event, 'emit'|'handle')
exports['v-core']:NoteCommand(name, perm, help)

-- v-social (server) - the shared social layer
exports['v-social']:GetHandle(cid)
exports['v-social']:PostAs(cid, kind, body, image)   -- for modules that post (news, races)

-- v-phone (server) - numbers, contacts, messages, calls, and the app registry
exports['v-phone']:GetNumber(cid) / FindByNumber(number) / IsOnline(number)
exports['v-phone']:NumberOf(src) / IsOnCall(src)
exports['v-phone']:SendMessage(fromCid, toNumber, body)    -- returns ok, errorKey
exports['v-phone']:Notify(src, app, title, body)           -- a banner on their phone
exports['v-phone']:RegisterApp(id, { label, icon, page, slot, dock, desc })
-- the page then uses https://cfx-nui-v-phone/sdk.js: PhoneUI (the kit) + Phone (the bridge)
-- Phone.request/emit/storage/notify/badge/toast/title/close/contacts/message/call
-- see DEVELOPERS.md "Shipping a phone app" and resources/[local]/v-phone-notes
exports['v-phone']:UnregisterApp(id) / GetApps(src)

-- v-banking (server) - the digital card
exports['v-banking']:GetCard(src)          -- mints on first use, then stable
exports['v-banking']:FindByCard(number)    -- citizenid behind a card number
-- v-banking:transfer accepts a card number as `target` as well as a citizen id
-- client: exports['v-phone']:IsOpen() / Open() / Close() / GetNumber() / OnCall()

-- v-housing (server)
exports['v-housing']:GetProperties() / OwnerOf(id) / HasKey(cid, id)
exports['v-housing']:IsInside(src)      -- property id, or nil
exports['v-housing']:StashId(id)        -- the v-inventory stash key for a property
-- client: exports['v-housing']:IsInside()

-- v-music (server)
exports['v-music']:GetSources()          -- every live source
exports['v-music']:StopSource(id)
exports['v-music']:IsAllowed(url)        -- against the allow-list setting
-- client: exports['v-music']:GetSources()

-- v-3dsound (server) - the wire carries a name and a place, never audio
exports['v-3dsound']:Play(name, coords, opts)        -- a world position
exports['v-3dsound']:PlayFromPlayer(src, name, opts) -- position taken from the ped, not a payload
exports['v-3dsound']:PlayOnEntity(entity, name, opts)-- follows a moving vehicle
exports['v-3dsound']:PlayFor(src, name, opts)        -- one person, not positional
exports['v-3dsound']:GetBank() / Has(name)
-- opts = { range, volume }; the bank lives in v-3dsound/config.lua

-- v-anticheat (server)
exports['v-anticheat']:Expect(src, kind, seconds)  -- declare an action a detector would flag
exports['v-anticheat']:Flag(src, kind, detail)     -- report something your module caught
exports['v-anticheat']:IsExempt(src)               -- true for staff at or above the exempt tier
exports['v-anticheat']:GetFlags(src)               -- flags this session
-- kinds: teleport | health | explosion | entity | money | weapon

-- v-voice
exports['v-voice']:GetChannel(src)          -- server: the channel this player TRANSMITS on
exports['v-voice']:GetListening(src)        -- server: every channel they monitor
exports['v-voice']:GetChannels()            -- server: every channel definition
exports['v-voice']:JoinChannel(src, id)     -- server: still gated; the gate is the point
exports['v-voice']:Mute(cid) / Unmute(cid) / IsMuted(cid)   -- server, survives a relog
-- client:
exports['v-voice']:GetState()               -- { step, label, range, channel, radio, talking, muted, injured }
exports['v-voice']:GetChannel() / GetListening() / GetStepLabel()
-- client event: AddEventHandler('v-voice:client:onChannels', function(list, transmit) end)

-- v-radio (client) - the device; it decides no permission
exports['v-radio']:GetPresets() / IsOpen()
exports['v-voice']:PhoneCallStart() / PhoneCallEnd()   -- what v-phone calls

-- v-drugs (server)
exports['v-drugs']:GetHeat(cid) / AddHeat(cid, n)   -- 0..100, decays on its own
exports['v-drugs']:GetPlants()                      -- live plant rows
exports['v-drugs']:GetDemand(district)              -- 0..1 for a district key
-- client: exports['v-drugs']:OfferTo(item) offers to the nearest ped

-- v-police (server)
exports['v-police']:IsCop(src)          -- job + duty, not a permission tier
exports['v-police']:IsCuffed(src)
exports['v-police']:JailLeft(cid)       -- minutes remaining, 0 if free
exports['v-police']:HasWarrant(cid)
exports['v-police']:GetCharges()        -- the live penal code

-- v-licenses (server) - added for the MDT: every licence of an OFFLINE citizen
exports['v-licenses']:GetAllByCid(cid)

-- v-gangs (server) - territory only; membership and treasury are v-factions
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
exports['v-status']:Get(src)          -- { hunger, thirst, stress, bleed, sick } - LIVE ref
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

-- v-target (client) - see the option schema below for every gate a row can declare
exports['v-target']:AddGlobalPlayer(opts) / AddGlobalPed(opts) / AddGlobalVehicle(opts)
exports['v-target']:AddGlobalObject(opts) / AddSelf(opts)
exports['v-target']:AddModel(models, opts) / AddEntity(netId, opts)
exports['v-target']:AddBoxZone(name, coords, size, opts, { heading, label })
exports['v-target']:AddSphereZone(name, coords, radius, opts, { label })
exports['v-target']:AddPolyZone(name, points, opts, { z, height, label })
exports['v-target']:RemoveZone(name) / RemoveResource(name)

-- An option. Every field is optional except a label and one of action/event/serverEvent.
{
  label = 'tgt.trunk',            -- locale key, or a literal string
  icon  = 'trunk',                -- see html/app.js for the set
  hint  = 'tgt.trunk_hint',       -- second line under the label
  priority = 10,                  -- lower sorts first; equal priorities keep insertion order

  -- Gates. job/gang/permission HIDE the row; the rest may grey it out with a reason.
  job    = { police = 2, sheriff = 0 },   -- name, list of names, or name -> min grade
  gang   = 'ballas', gangGrade = 1,
  permission = 'admin',           -- user | mod | admin | superadmin
  duty   = true,                  -- only enforced when the server models duty
  items  = { lockpick = 1 },      -- or 'lockpick', or { any = { 'lockpick', 'screwdriver' } }
  bones  = { 'boot' },            -- which part of the vehicle/ped is being pointed at
  vehicleClass = { 8 },
  distance = 4.5,                 -- metres; may only shorten the eye's reach

  -- Return false to hide, or false plus a locale key to grey the row out with a reason.
  canInteract = function(entity, distance, coords, data) return true end,

  -- What it does. A `menu` opens a nested list instead of acting.
  action = function(data) end,
  event = 'some:client:event', serverEvent = 'some:server:event',
  export = { resource = 'v-shops', method = 'Open' },
  menu = { … } or function(data) return { … } end,
}

-- `data` carries: entity, coords, distance, model, netId, type, bone,
-- playerId, playerServerId, zone, zoneLabel, self

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
module can override it in **Admin -> Editor -> Look -> Module themes** - preset, accent,
panel transparency, backdrop, roundness, motion, font scale - and **anything left blank is
inherited**.

`theme.js` stamps the owning resource onto `<html data-vmod="…">`, and the generated
stylesheet carries a scoped block per module:
```css
:root { /* global */ }
:root[data-vmod="my-script"] { /* only the overrides */ }
```
So your page is themeable the moment it links the three files - including per-module, with
no change to v-ui.

---

## Writing a NUI page

```html
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css" />       <!-- primitives -->
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme-vars.css" />  <!-- palette -->
<script src="https://cfx-nui-v-ui/theme.js"></script>                 <!-- live re-theme -->
```
Then compose the shared primitives: `.v-panel`, `.v-chamfer`, `.v-tab`, `.v-brk`,
`.v-progress` + `.v-progress__fill`, `.v-scroll`, `.v-glass`. **Never hardcode a colour** -
use the `--v-*` variables, or an admin's theme change will skip your page.

The resource that owns the page calls `SetNuiFocus` itself; focus is per-resource.

---

# v-core - Référence API (Version Française)

Chaque export, callback et événement exposé par le framework. Généré depuis les sources :
ce qui est listé ici existe.

**Trois notions de permission, jamais interchangeables :**

| Notion | Question | Appel |
|---|---|---|
| Permission `v-core` | *Est-ce un membre du staff ?* | `Core.HasPermission(src, 'admin')` |
| Métier `v-jobs` | *Est-ce un employé ?* | `exports['v-jobs']:GetJob(src)` |
| Licence `v-licenses` | *En a-t-il légalement le droit ?* | `exports['v-licenses']:Has(src, 'driving')` |

Les signatures sont identiques dans les deux langues - la section anglaise ci-dessus fait
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
`ON DUPLICATE KEY UPDATE` - sinon un redémarrage efface les modifications de l'admin.

```lua
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'items' then reconstruire() end
end)
```

## Règles de la maison

- Locales **fr et en** pour chaque texte joueur.
- **Aucune commande chat** : touches, œil de ciblage, téléphone ou NUI.
- **Revérifier chaque contrôle côté serveur** - un test de distance client est de l'UX.
- **Aucune couleur en dur** dans une NUI : utilise les variables `--v-*`, sinon le
  changement de thème d'un admin ignorera ta page.
