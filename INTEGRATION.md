# Integrating a script with v-core

A resource does not need to be part of this repository to be a first-class citizen of the
framework. Declare yourself, and the admin panel picks you up.

---

## 1. Announce yourself

In your `fxmanifest.lua`:

```lua
v_module 'yes'
v_module_label 'My Script'
v_module_category 'gameplay'      -- vehicles | law | civic | economy | gameplay | other
```

That alone makes your resource appear in **Admin panel → Settings**. It is how an operator
sees that your script is installed and running, before you expose anything.

## 2. Declare your settings

Server side, once at boot:

```lua
exports['v-core']:RegisterModule('my-script', {
    label = 'My Script', category = 'gameplay',
    settings = {
        { key = 'payout',  label = 'Payout',  type = 'number', default = 250, min = 0, max = 10000 },
        { key = 'enabled', label = 'Enabled', type = 'bool',   default = true },
        { key = 'mode',    label = 'Mode',    type = 'select', default = 'easy',
          options = { 'easy', 'hard' }, hint = 'Difficulty of the job' },
    },
})
```

Types: `number` (with `min` / `max` / `step`), `bool`, `string` (`maxLength`), `select`
(`options`), `color` (`#rrggbb`). Every value is **coerced and range-clamped server-side**;
a value that cannot be coerced is rejected rather than stored as something else.

**v-admin renders whatever you declared.** It has no knowledge of your settings, so adding
one is a change to *your* script only.

## 3. Read them, and react

```lua
local payout = exports['v-core']:GetSetting('my-script', 'payout')

AddEventHandler('v-core:server:settingChanged', function(module, key, value)
    if module == 'my-script' then applySettings() end
end)
```

Client side the values are mirrored automatically:

```lua
local Core = exports['v-core']:GetCore()
local payout = Core.GetSetting('my-script', 'payout', 250)
AddEventHandler('v-core:client:onSettingChanged', function(module, key, value) end)
```

## 4. The rest of the framework

```lua
local Core = exports['v-core']:GetCore()

Core.GetPlayer(src)                       -- citizenid, charinfo, money, job, gang, metadata
Core.RegisterCallback('my:cb', function(source, resolve, data) resolve(...) end)
Core.HasPermission(src, 'admin')          -- STAFF rank
Core.Notify(src, 'text', 'success')
Core.Log('category', 'message', data, citizenid)

exports['v-jobs']:GetJob(src)             -- EMPLOYMENT  { name, grade }
exports['v-licenses']:Has(src, 'driving') -- THE LAW
exports['v-inventory']:AddItem(src, 'water', 1)
exports['v-vehicles']:SpawnOwned(src, plate, coords, heading)
exports['v-vehicles']:OpenPreview(model)  -- showroom instance (client)
```

Those three permission concepts are **not interchangeable** — see `ARCHITECTURE.md` §2.

## 5. Content that an operator must edit in-game

Settings are for *tunables*. For **content** (a list of locations, a table of items) add a
domain to `v-world` and a subtab to the v-admin Editor — the pattern is in
`ARCHITECTURE.md` §7. Seed your defaults with `INSERT IGNORE`, never
`ON DUPLICATE KEY UPDATE`, or a restart silently wipes every admin edit.

## 6. House rules

- **fr and en locales.** Every player-facing string goes through `L('key')`.
- **No player chat commands.** Keybinds, the target eye, the phone or a NUI.
- **Re-derive every gate server-side.** A client-side distance check is UX, not a gate.
- **Use the EMBER design system** (`https://cfx-nui-v-ui/theme.css`) so your NUI looks native.

---

# Intégrer un script à v-core (Version Française)

Un script n'a pas besoin de faire partie de ce dépôt pour être un citoyen de première
classe du framework. Déclare-toi, et le menu admin te détecte.

## 1. Se déclarer

Dans ton `fxmanifest.lua` :

```lua
v_module 'yes'
v_module_label 'Mon Script'
v_module_category 'gameplay'
```

Ça suffit pour apparaître dans **Menu admin → Réglages**. C'est ainsi qu'un opérateur voit
que ton script est installé et démarré, avant même que tu exposes quoi que ce soit.

## 2. Déclarer ses réglages

Côté serveur, une fois au démarrage :

```lua
exports['v-core']:RegisterModule('mon-script', {
    label = 'Mon Script', category = 'gameplay',
    settings = {
        { key = 'gain',   label = 'Gain',   type = 'number', default = 250, min = 0, max = 10000 },
        { key = 'actif',  label = 'Actif',  type = 'bool',   default = true },
    },
})
```

Types : `number` (`min`/`max`/`step`), `bool`, `string` (`maxLength`), `select`
(`options`), `color`. Chaque valeur est **convertie et bornée côté serveur** ; une valeur
inconvertible est refusée plutôt que stockée de travers.

**v-admin affiche ce que tu as déclaré.** Il ne connaît pas tes réglages : en ajouter un
ne modifie que *ton* script.

## 3. Les lire et réagir

```lua
local gain = exports['v-core']:GetSetting('mon-script', 'gain')

AddEventHandler('v-core:server:settingChanged', function(module, key, value)
    if module == 'mon-script' then appliquer() end
end)
```

Côté client, les valeurs sont répliquées automatiquement via `Core.GetSetting(...)` et
l'événement `v-core:client:onSettingChanged`.

## 4. Règles de la maison

- **Locales fr et en** obligatoires.
- **Aucune commande chat joueur.**
- **Revérifier chaque contrôle côté serveur.**
- **Utiliser le design system EMBER** pour que ta NUI ait l'air native.
- Pour du **contenu** (une liste de lieux, une table d'items) : ajoute un domaine à
  `v-world` + un sous-onglet à l'Éditeur, jamais un `config.lua` que l'opérateur doit
  éditer en production. Amorce avec `INSERT IGNORE`.
