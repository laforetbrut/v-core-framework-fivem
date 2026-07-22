# Writing a script for v-core

Everything a script needs - the core handle, settings that show up in the admin panel,
safe calls into other modules - comes from one helper. Add one line to your manifest:

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
to do it - 28 hand-tuned sleeps, each a guess. `V.Ready` knows.

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
> local at startup makes that setting do nothing until the server restarts - the operator
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
export, the call returns `nil` instead of throwing - so an optional dependency needs no
`pcall` and no `GetResourceState` check. When a call *does* fail it prints which export,
which resource and **which side**, which is how the framework's nastiest class of bug
(calling a server export from the client) stops being silent.

`V.Has('v-fuel')` if you just want the boolean.

### Players, callbacks, notifications

| | Server | Client |
|---|---|---|
| Player | `V.Player(source)` | `V.Player()` → `PlayerData` |
| Callback | `V.Callback(name, fn)` - `fn(source, resolve, ...)` | `V.Request(name, cb, ...)` |
| Notify | `V.Notify(source, msg, kind)` | `V.Notify(msg, kind)` |

`V.Callback` exists only on the server and `V.Request` only on the client, on purpose:
registering a callback on the wrong side is a hang with no error message.

`kind` is `info` \| `success` \| `warning` \| `error`.

---

## Working with other scripts

A framework is only as good as what somebody else can build on it. Five tools cover the
whole of it.

### Services: ask for a capability, not a resource

```lua
V.Provide('banking')                 -- in the module that implements it
local bank = V.Service('banking')    -- in anything that needs it
bank.GetBalance(src)
```

`V.Service` returns the same forgiving proxy as `V.Use`, so a missing provider is a `nil`
return rather than a crash. **The point is indirection**: a server that replaces
`v-banking` with its own implementation keeps every consumer working, because no consumer
ever named the resource. Twenty-three services ship: `banking`, `inventory`, `vehicles`,
`garages`, `jobs`, `factions`, `licenses`, `police`, `voice`, `sound`, `notify`, `target`,
`status`, `shops`, `crafting`, `mechanic`, `fuel`, `clothing`, `appearance`, `drugs`,
`gangs`, `music`, `anticheat`.

`V.HasService('banking')` if you just want the boolean.

### Hooks: intercept, rewrite or veto

```lua
V.Hook('core:beforeAddMoney', function(p)
    if p.reason == 'salary' and p.amount > 50000 then return false end   -- veto
    p.amount = math.floor(p.amount * 1.1)                                 -- or rewrite
    return p
end, 50)                                                                  -- lower runs first
```

This is the one thing FiveM events **cannot** do. Event arguments are serialised across
resources, so a handler that mutates a table changes nothing on the other side. Hooks go
through exports, which do return values.

Returning `false` vetoes; returning a table replaces the payload; returning nothing leaves
it alone. A handler that errors is skipped rather than allowed to abort the chain - one
broken third-party script must not be able to stop money from moving.

Hooks that ship: `core:beforeAddMoney`, `core:beforeRemoveMoney`, `core:beforeSetJob`.
Run your own with `V.RunHook(name, payload)`; it returns the payload, or `nil` when a
handler vetoed, so **check for nil, not for true**.

### Events, with discovery

```lua
V.On('v-core:server:onPlayerLoaded', function(src) end)
V.Emit('my-script:somethingHappened', data)
V.EmitClient('my-script:show', src, data)   -- server -> one client, or nil for everyone
V.EmitServer('my-script:ask', data)         -- client -> server
```

Thin wrappers over FiveM's own events, plus the thing FiveM does not give you: a registry.
Anything routed through `V.On` / `V.Emit` shows up in the registry below, so the next
developer can find out what exists instead of grepping.

### Turning modules on and off

```lua
V.Enabled('v-drugs')            -- is it running
V.SetEnabled('v-drugs', false)  -- stop it
```

A real resource stop, not a flag every module has to remember to honour. The admin panel's
**Resources** tab does the same thing.

### Refusing to run against the wrong version

```lua
if not V.Require('v-banking', '0.2.0') then return end
```

Prints one clear line and stops, instead of failing somewhere unrelated an hour later.
`V.Version('v-banking')` reads it without judging.

### Discovery

```lua
local r = V.Registry()   -- { modules, services, hooks, events, commands }
```

Or type `vdev` in the server console. It answers "what already exists here" in one call,
which is the question every integrator starts with.

### The rest

| | |
|---|---|
| `V.Command(name, { perm = 'admin', help = '...' }, fn)` | permission-gated and registered in one call |
| `V.Interval(ms, fn)` | returns a function that stops it |
| `V.Timeout(ms, fn)` | |
| `V.State(key, value)` / `V.PlayerState(src, key, value)` | statebags, readable from both sides |
| `V.Log(...)` | prefixed with your resource name |

---

## Shipping a phone app

The phone is the surface most of the game is played through, so an app is the shortest
route from an idea to something players actually use. There is no build step, no
framework and no bundler: an app is **one HTML file and eight lines of Lua**.

`resources/[local]/v-phone-notes` is a complete worked example that ships with the
framework. Copy it.

### The eight lines

```lua
V.Ready(function()
    exports['v-phone']:RegisterApp('notes', {
        label = 'Notes',      -- a literal, or a locale key your resource ships
        icon  = 'note',       -- any key from PhoneUI.icons
        slot  = 20,           -- home-screen position; the operator can change it
        dock  = false,        -- true puts it in the dock instead of the grid
        desc  = 'One line for its FruitStore page',
        page  = 'https://cfx-nui-v-phone-notes/html/index.html',
    })
end)
```

That is the whole server side, unless your app needs logic of its own.

The operator's control over your app is separate and lives in **Admin -> Editor -> Phone
apps**: enabled, ordered, and gated by job or gang. You do not implement any of that, and
you should not try to: an app that decided for itself whether it was installed would be
ignoring the person running the server.

### The page

```html
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css" />
<link rel="stylesheet" href="https://cfx-nui-v-ui/theme-vars.css" />
<link rel="stylesheet" href="https://cfx-nui-v-phone/style.css" />
<script src="https://cfx-nui-v-phone/sdk.js"></script>
<div id="appbody"></div>
<script>
Phone.ready(function (me) {
    Phone.title('Notes');
    PhoneUI.render(
        PhoneUI.group([
            PhoneUI.row({ title: 'My number', value: me.number }),
            PhoneUI.row({ title: 'Write one', icon: 'note', chevron: true, data: { act: 'new' } }),
        ], { header: 'Notes', footer: 'Kept on your character.' })
    );
    PhoneUI.on('[data-act="new"]', 'click', function () { Phone.toast('Hello'); });
});
</script>
```

**Link the phone's stylesheet rather than writing your own.** `PhoneUI` is the same object
the built-in apps draw themselves with - one definition, so your app cannot drift out of
looking native, and it follows the server's v-ui theme for free.

### The kit - `PhoneUI`

| Call | What you get |
|---|---|
| `group(rows, { header, footer })` | An inset, rounded iOS list section |
| `row({ ... })` | One row: `icon`/`avatar`, `title`, `subtitle`, `value` (plus `tone: 'pos'` / `'neg'`, `mono`), `badge`, `time`, `toggle`, `chevron`, `data` |
| `bigNumber(label, value, sub)` | The large centred figure a balance screen wants |
| `button(label, id, style)` | `''` accent, `'tinted'`, `'plain'`, `'destructive'` |
| `field(id, placeholder, value, attrs)` | A rounded input |
| `empty(text, icon)` | The empty state |
| `render(html)` | Replace the app body |
| `on(selector, event, handler)` | Delegated events that survive a re-render |
| `icons`, `svg(name)`, `esc(text)` | The icon set, and the escaper everything goes through |

Every helper returns an **HTML string**. An app is a template, not a component tree,
because somebody writing their first app should not have to learn a framework first.

### The bridge - `Phone`

Every call returns a Promise.

| Call | What it does |
|---|---|
| `Phone.ready(fn)` | Runs once the phone answers with `{ number, apps }` |
| `Phone.title(text)` | The title in the phone's navigation bar |
| `Phone.close()` | Close the app, back to the home screen |
| `Phone.toast(text)` | A transient message at the bottom |
| `Phone.notify(title, body)` | A banner, and an entry in the lock-screen stack |
| `Phone.badge(count)` | The red count on your icon; `0` clears it |
| `Phone.request(method, data)` | Call **your own** server callback |
| `Phone.emit(event, data)` | Fire **your own** server event |
| `Phone.storage.get/set/all` | Per app, per character, persisted server-side |
| `Phone.contacts()` | The player's contact list, read only |
| `Phone.message(number, body)` | Send a message as the player |
| `Phone.call(number)` | Start a call, routed and validated like the dialler |

### What an app can and cannot reach

`Phone.request('save', data)` calls `V.Callback('notes:save', ...)` - the full name is
composed as `<yourAppId>:<method>` **by the phone**, and the app id comes from the phone's
own state rather than from your message. There is therefore no way to spell
`v-banking:withdraw`: it is not that the phone refuses, it is that the name cannot be
formed.

If your app needs another module, call that module **from your own server callback**,
where you can check whatever you like first:

```lua
V.Callback('notes:balance', function(src, resolve)
    if not somethingYouCareAbout(src) then resolve({ error = 'no' }) return end
    resolve({ ok = true, bank = V.Use('v-banking').GetBalance(src) })
end)
```

`Phone.storage` means most apps need no table, no migration and no server file at all.
Values are text; anything structured is your own JSON, because guessing at a schema for
somebody else's data helps nobody.

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

These are not hypothetical - each one shipped, broke something, and was fixed.

- **`local function f` is only visible after its definition.** A settings block appended
  at the end of a file cannot be called by a thread above it. Five modules failed to boot
  this way.
- **FiveM normalises manifest flags.** `v_module 'yes'` reads back as `1`, not `'yes'`.
  Comparing to `'yes'` matched nothing, and the registry found none of them.
- **`cond and nil or x` always yields `x` in Lua.** `nil` is falsy, so the `and` branch is
  discarded. Assign after building the table instead.
- **`INSERT IGNORE` only dedupes on a natural key.** On an `AUTO_INCREMENT` table it
  duplicates every row on re-seed.
- **CEF has no `backdrop-filter`** in this build - it renders as an opaque black box.
- **A NUI page can only be messaged by the resource that owns it**, and `SetNuiFocus` is
  resource-scoped.
- **Enhanced rejects Legacy stream assets.** One `.ytd` in RSC7 format stops the whole
  resource with "Asset version mismatch".
- **Starting a resource before `v-core` makes FiveM hoist the core as a silent
  dependency**, and `v-core` then disappears from the boot log entirely - which reads as
  "the core did not start". It did; the log just stops mentioning it. Put your `ensure`
  after `v-core` and let `V.Ready` handle the timing.
- **A two-name capture drops extra return values.** Several exports here answer with
  `(value, reason)`, and `local ok, res = pcall(...)` keeps only the first - leaving the
  caller able to report nothing but "unknown error". Use `table.pack` / `table.unpack`
  when you wrap a call whose reason you need.

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

Tout ce dont un script a besoin - le handle du core, des réglages qui apparaissent dans
le panneau admin, des appels sûrs vers les autres modules - vient d'un seul helper. Une
ligne dans votre manifest :

```lua
shared_script '@v-core/lib/v.lua'
```

Vous obtenez un global `V` côté client et serveur. Rien d'autre à installer, aucun ordre
de démarrage à respecter.

## L'API

**Cycle de vie** - `V.Ready(fn)` exécute `fn` dès que v-core est prêt (jamais un `Wait`
au jugé), `V.Core()` renvoie le core ou `nil`, `V.name` votre ressource.

**Réglages** - `V.Module(info)` déclare le module et ses réglages, `V.Setting(clé,
défaut)` les lit (jamais `nil`), `V.SettingNumber` / `V.SettingBool` les convertissent,
`V.OnSetting(fn)` réagit quand un admin en change un.

> **Lisez un réglage là où vous l'utilisez, pas au démarrage.** Un module qui met un
> réglage en cache au boot le rend inopérant jusqu'au prochain redémarrage : l'admin le
> change, ne voit rien, et signale un bug.

> **Un réglage que personne ne lit est pire que pas de réglage : il ment à l'admin.**

**Communication** - `V.Use('v-fuel')` renvoie un proxy : si la ressource est absente,
arrêtée, ou n'expose pas cet export, l'appel renvoie `nil` au lieu de planter. Aucun
`pcall`, aucun `GetResourceState`. Et quand un appel échoue vraiment, il **dit** lequel
et de quel côté - c'est ainsi que la pire classe de bug du framework (appeler un export
serveur depuis le client) cesse d'être silencieuse.

**Joueurs, callbacks, notifications** - `V.Player(source)` côté serveur et `V.Player()`
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
