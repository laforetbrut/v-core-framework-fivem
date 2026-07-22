# Writing a script for v-core

Everything a script needs — the core handle, settings that show up in the admin panel,
safe calls into other modules — comes from one helper. Add one line to your manifest:

```lua
shared_script '@v-core/lib/v.lua'
```

That gives you a global `V` on both the client and the server. There is nothing else to
install and no boot order to respect.

---

## A complete module in 40 lines

`my-script/fxmanifest.lua`

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'my-script'
author 'you'

-- Makes the module appear in Admin -> Settings. Without it your settings still work,
-- but nobody can find them.
v_module 'yes'
v_module_label 'My script'
v_module_category 'gameplay'   -- gameplay | economy | world | ui | other

shared_script '@v-core/lib/v.lua'
client_script 'client.lua'
server_script 'server.lua'
```

`my-script/server.lua`

```lua
V.Module({
    label = 'My script',
    category = 'gameplay',
    settings = {
        { key = 'reward', label = 'Reward ($)', type = 'number', default = 250, min = 0, max = 10000, step = 10 },
        { key = 'enabled', label = 'Enabled',   type = 'bool',   default = true },
    },
})

V.Callback('my-script:claim', function(source, resolve)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end

    local player = V.Player(source)
    if not player then resolve(false) return end

    player.AddMoney('bank', V.SettingNumber('reward', 250), 'my-script')
    resolve({ ok = true })
end)
```

`my-script/client.lua`

```lua
V.Ready(function()
    V.Request('my-script:claim', function(res)
        if res and res.ok then V.Notify('Claimed.', 'success') end
    end)
end)
```

Start the resource. Your settings are now live in **Admin → Settings → My script**, an
admin can change them in game, and your code reads the new value on the next call.

---

## The API

### Lifecycle

| | |
|---|---|
| `V.Ready(fn)` | Runs `fn(Core)` once v-core is up. Use it instead of sleeping. Safe to call at file scope; if the core is already up, `fn` runs on the next tick. |
| `V.Core()` | The core table, or `nil` if v-core is not up yet. You rarely need this. |
| `V.name` | Your resource name. |

**Never write `Wait(2500)` hoping v-core has started.** That was how this framework used
to do it — 28 hand-tuned sleeps, each a guess. `V.Ready` knows.

### Settings

| | |
|---|---|
| `V.Module(info)` | Declares your module and its settings. Server-side; values mirror to clients automatically. |
| `V.Setting(key, default)` | Your module's setting. Never returns `nil`. |
| `V.SettingNumber(key, default)` / `V.SettingBool(key, default)` | Same, coerced. |
| `V.OnSetting(fn)` | `fn(key, value)` when an admin changes one of **your** settings. |

Setting types: `number` (`min`, `max`, `step`), `bool`, `string` (`maxLength`),
`select` (`options = { { value =, label = } }`), `color`.

> **Read settings where you use them, not at boot.** A module that caches a setting in a
> local at startup makes that setting do nothing until the server restarts — the operator
> changes it, sees no effect, and reports it as broken. If you must cache (a loop
> interval, a marker colour), re-read it in `V.OnSetting`.

> **A setting nothing reads is worse than no setting: it lies to the operator.** Before
> you ship one, grep for the read.

### Talking to other modules

```lua
local fuel = V.Use('v-fuel')

if fuel.IsElectric(veh) then ... end
```

`V.Use` returns a proxy. If the resource is missing, stopped, or does not define that
export, the call returns `nil` instead of throwing — so an optional dependency needs no
`pcall` and no `GetResourceState` check. When a call *does* fail it prints which export,
which resource and **which side**, which is how the framework's nastiest class of bug
(calling a server export from the client) stops being silent.

`V.Has('v-fuel')` if you just want the boolean.

### Players, callbacks, notifications

| | Server | Client |
|---|---|---|
| Player | `V.Player(source)` | `V.Player()` → `PlayerData` |
| Callback | `V.Callback(name, fn)` — `fn(source, resolve, ...)` | `V.Request(name, cb, ...)` |
| Notify | `V.Notify(source, msg, kind)` | `V.Notify(msg, kind)` |

`V.Callback` exists only on the server and `V.Request` only on the client, on purpose:
registering a callback on the wrong side is a hang with no error message.

`kind` is `info` \| `success` \| `warning` \| `error`.

---

## Conventions

**Exports are `PascalCase`.** `exports('GetFuel', …)`, not `getFuel`. The framework has
exactly one historical exception (`v-notify:show`, which now also answers to `Show`), and
that single inconsistency has cost more integrator time than every other naming question
combined.

**Code, comments, logs and variable names in English.** Player-facing text goes in
`locales/en.lua` and `locales/fr.lua`, never inline.

**Three permission concepts, never interchangeable:**

| Concept | Means | Ask with |
|---|---|---|
| v-core permission | staff rank | `Core.HasPermission(src, 'admin')` |
| v-jobs job & grade | employment | `player.job.name`, `player.job.grade` |
| v-licenses licence | the law | `exports['v-licenses']:Has(src, 'driver')` |

`player.job` is a **table** (`{ name, grade }`), never a string. Comparing it to a string
silently matches nothing, which reads as "the feature is disabled for everyone".

**The server decides.** Money, items, positions and permissions are validated server-side
even when the client already checked. A client payload is a request, not a fact.

**No chat commands for players.** Interaction happens through the phone, the radial menu,
the pause menu or a keybind. Admin commands are fine.

**Theming.** Link the three v-ui files and your page follows the server's theme,
including a per-module override, with no work:

```html
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css" />
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme-vars.css" />
<script src="https://cfx-nui-v-ui/theme.js"></script>
```

Use the theme tokens (`--v-panel`, `--v-accent`, `--v-text`, `--v-danger`, `--v-r-md`,
`--v-t-base`, …) rather than literal colours, or your page will be the one that does not
change when the operator picks a different palette.

---

## Gotchas this framework has actually hit

These are not hypothetical — each one shipped, broke something, and was fixed.

- **`local function f` is only visible after its definition.** A settings block appended
  at the end of a file cannot be called by a thread above it. Five modules failed to boot
  this way.
- **FiveM normalises manifest flags.** `v_module 'yes'` reads back as `1`, not `'yes'`.
  Comparing to `'yes'` matched nothing and the registry found 0 of 25 modules.
- **`cond and nil or x` always yields `x` in Lua.** `nil` is falsy, so the `and` branch is
  discarded. Assign after building the table instead.
- **`INSERT IGNORE` only dedupes on a natural key.** On an `AUTO_INCREMENT` table it
  duplicates every row on re-seed.
- **CEF has no `backdrop-filter`** in this build — it renders as an opaque black box.
- **A NUI page can only be messaged by the resource that owns it**, and `SetNuiFocus` is
  resource-scoped.
- **Enhanced rejects Legacy stream assets.** One `.ytd` in RSC7 format stops the whole
  resource with "Asset version mismatch".

---

## Checking your work

The framework ships audit scripts that catch what a Lua syntax check cannot:

- every `exports['x']:Y()` call resolved against the exports `x` actually defines, **on
  the matching side**;
- every `TriggerServerEvent` / `TriggerClientEvent` / `TriggerCallback` matched to a
  handler.

Run them before opening a PR. A dangling callback is a UI that hangs forever with no
error in the console.

---

# Écrire un script pour v-core (version française)

Tout ce dont un script a besoin — le handle du core, des réglages qui apparaissent dans
le panneau admin, des appels sûrs vers les autres modules — vient d'un seul helper. Une
ligne dans votre manifest :

```lua
shared_script '@v-core/lib/v.lua'
```

Vous obtenez un global `V` côté client et serveur. Rien d'autre à installer, aucun ordre
de démarrage à respecter.

## L'API

**Cycle de vie** — `V.Ready(fn)` exécute `fn` dès que v-core est prêt (jamais un `Wait`
au jugé), `V.Core()` renvoie le core ou `nil`, `V.name` votre ressource.

**Réglages** — `V.Module(info)` déclare le module et ses réglages, `V.Setting(clé,
défaut)` les lit (jamais `nil`), `V.SettingNumber` / `V.SettingBool` les convertissent,
`V.OnSetting(fn)` réagit quand un admin en change un.

> **Lisez un réglage là où vous l'utilisez, pas au démarrage.** Un module qui met un
> réglage en cache au boot le rend inopérant jusqu'au prochain redémarrage : l'admin le
> change, ne voit rien, et signale un bug.

> **Un réglage que personne ne lit est pire que pas de réglage : il ment à l'admin.**

**Communication** — `V.Use('v-fuel')` renvoie un proxy : si la ressource est absente,
arrêtée, ou n'expose pas cet export, l'appel renvoie `nil` au lieu de planter. Aucun
`pcall`, aucun `GetResourceState`. Et quand un appel échoue vraiment, il **dit** lequel
et de quel côté — c'est ainsi que la pire classe de bug du framework (appeler un export
serveur depuis le client) cesse d'être silencieuse.

**Joueurs, callbacks, notifications** — `V.Player(source)` côté serveur et `V.Player()`
côté client, `V.Callback(nom, fn)` côté serveur uniquement, `V.Request(nom, cb, …)` côté
client uniquement, `V.Notify(…)` des deux côtés.

## Conventions

Exports en `PascalCase`. Code, commentaires et logs en anglais ; textes joueur dans
`locales/`. Trois notions de permission jamais interchangeables : **permission v-core**
= staff, **job v-jobs** = emploi, **licence v-licenses** = la loi. `player.job` est une
**table**, jamais une chaîne. Le serveur décide : une charge utile client est une
demande, pas un fait. Pas de commandes chat pour les joueurs. Utilisez les tokens de
thème v-ui plutôt que des couleurs en dur.

## Credits

Author: vyrriox
