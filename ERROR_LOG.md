# Error Log

## [2026-07-11 — audit] — Recurring classes found by the framework-wide audit
**Context:** A per-module adversarial audit (19 confirmed fixes). The reusable lessons:
- **Client-only distance/authority gates are not gates.** `v-inventory:give` trusted the client's proximity check → cross-map transfers. Every server callback/net event that acts on a target must re-derive proximity/permission **server-side** (mirror `searchPlayer`/`openStash`).
- **Ignoring a mutation's return value loses data.** `AddItem` returns false when full; v-clothing unequip/equip discarded it and cleared the worn slot anyway → destroyed the item. Always branch on the boolean **before** mutating dependent state.
- **Two-step money must be atomic across the DB.** The offline bank transfer credited the recipient's DB row immediately but only debited the sender in memory → a crash duplicated money. Wrap both sides in `MySQL.transaction.await`.
- **Re-validate on every action, not just on open.** Trunk/drop/stash proximity (and job/gang access) was checked only at open; the move callback now re-checks each move.
- **Client-triggered "on death/respawn" resets need a server death signal.** Gate `onRespawn` on a `Dead` set fed by `baseevents:onPlayerDied`, cleared on respawn.
- **Shared globals: only clear what you set.** The stress blur called `ClearTimecycleModifier()` unconditionally, wiping other resources' modifiers; track a local flag and clear only on the set→unset edge.
- **A synchronous latch must be set BEFORE the first `await`** (selectCharacter re-entrancy), same as the existing `creating` guard.

## [2026-07-11 — session] — Drag-drop broken: `maybeUnequip` called before its definition
**Context:** Every inventory move from the player grid errored: `main.lua:341: attempt to call a nil value (global 'maybeUnequip')`, so drag-drop did nothing.
**Root cause:** `maybeUnequip` is a `local function` defined ~line 396, but the `v-inventory:move` callback calls it ~line 343 — **before** the local exists in scope, so the call resolved to a nil global and the move callback errored for *every* player move.
**Fix:** Forward-declare `local maybeUnequip` near the top, and define it later with `function maybeUnequip(...)` (assigning the forward local) so it's in scope at the call site.
**Prevention:** In Lua a `local function` is only visible *after* its definition — forward-declare any helper used earlier in the file (`local f` up top, `function f() … end` later).

## [2026-07-11 — session] — Appearance UI showed raw i18n keys (APP.ZONE_HEAD…)
**Context:** The tattoo/appearance editor rendered untranslated keys instead of labels.
**Root cause:** The locale files were listed under a `locales { … }` block in the fxmanifest. **`locales` is not a script directive** — FiveM never *executed* those files, so `Locales.fr/en` never got the `app.*` keys and `t()` returned the raw key. (Data-driven text worked; only `t()`-translated text was raw.)
**Fix:** Load the locale files as `shared_scripts` (after `@v-core/locale/shared.lua`, before `config.lua`).
**Prevention:** Locale Lua must be loaded via `shared_scripts`/`client_scripts`/`server_scripts` — never a bare `locales {}` list. Raw keys in a NUI while data renders → the locale table isn't populated (manifest not executing the files).

## [2026-07-11 — session] — Ground drops lootable from anywhere (SECURITY)
**Context:** Ground drops opened as secondary containers; adversarial review of v-inventory.
**Error:** The `openStash` `drop` branch checked only that the id matched `^drop:%d+$` and existed — no proximity check (the trunk/glovebox branch had a 5 m gate). Drop ids come from an incrementing counter, so a modded client could fire `openStash('drop:1',…)`, `drop:2`, … and drain every ground drop on the map remotely; the per-move re-check only runs for `search`, so it wasn't distance-gated on move either.
**Fix:** The `drop` branch now checks the player's ped is within 5 m of the drop's server-stored `coords` before opening.
**Prevention:** Every openable container branch must apply the same server-side proximity gate; never rely on an id being "unguessable" (sequential ids are trivially enumerable).

## [2026-07-11 — session] — Weapon wear was client-authoritative
**Context:** Durability derived from the client-reported ammo delta.
**Error:** A modded client could under-report / not report ammo, so `spent = old - new` stayed ≤ 0 and durability never dropped — the weapon never wore or jammed.
**Fix:** Wear now comes from the engine's `weaponDamageEvent` (trusted `sender`); the ammo net event is a pure magazine sync.
**Prevention:** Never derive an authoritative stat from a client-sent value at a security boundary; use an engine-raised event whose actor the server controls.

## [2026-07-11 — session] — v-shops sell destroyed goods on a $0 payout
**Context:** Money laundering: a launderer that pays a 0.65 rate for `marked_bills` (price 1).
**Error:** Selling 1 marked bill removed the item, then `total = floor(1*1*0.65) = 0` hit the `if total <= 0 then resolve(false)` guard **before** any payout/refund — the bill was destroyed for nothing, with no notification. Caught by an adversarial review workflow (3 agents independently).
**Root cause:** The `total <= 0` guard sat **after** `RemoveItem`. Any sale whose `floor(price*amount*rate)` rounds to 0 fell into the post-removal, no-refund window.
**Fix:** Compute `total` and run the `<= 0` guard **before** removing anything; notify (`shop.too_small`). Order is now compute → validate ownership → remove → pay.
**Prevention:** In any "take then pay" flow, validate the payout amount **before** the irreversible removal. Never place a value guard after the item has been consumed.

## [2026-07-11 — session] — v-inventory RemoveItem only decremented one stack
**Context:** Selling stackable items; adversarial review.
**Error:** `RemoveItem` matched a single stack with `amount >= wanted`; a quantity split across several stacks was wrongly rejected though the total sufficed.
**Fix:** Sum every stack of the item and, if the total is enough, remove spanning stacks.
**Prevention:** "Remove N of item X" must consider the item's **total across all stacks**, not one stack.

## [2026-07-11 — session] — v-gathering harvest rate bypass (server cooldown < client animation)
**Context:** New gathering module; adversarial review.
**Error:** The server cooldown (2 s) was shorter than the client harvest animation (3.5–4.5 s), so a scripted client firing the `harvest` callback directly could gather ~2× faster.
**Root cause:** The pacing that limited legit players lived **client-side** (the animation wait); the server had only a flat 2 s cooldown.
**Fix:** Gate server-side on the resource's own `time` via `GetGameTimer()` (ms).
**Prevention:** Never let a client-side timer be the only rate limit on a server action; enforce the real interval server-side.

## [2026-07-11 — session] — v-shops buy-from-anywhere + unenforced job lock (security)
**Context:** Store buying had no server-side location/job check.
**Error:** Any client could buy any shop's catalogue (incl. a job-locked police armory) from anywhere on the map; `RemoveMoney`'s result was also ignored after `AddItem` (latent free-item dupe).
**Fix:** `canUseShop` verifies the player is at a `Config.Locations` entry mapping to the shop id and holds `shops.job` if set; amount clamped server-side; item label guarded; `RemoveMoney` checked with the item refunded on failure.
**Prevention:** Every money/item server callback must re-derive proximity + authorization server-side and check the return of each mutation, refunding on failure.

## [2026-07-10 19:05] — Infinite loading / stuck black screen after the spawn rework

**Context:** v-spawn ran a "black-out guard" thread at resource start — `while not spawnReady do DoScreenFadeOut(0) ... end` — to hide the default spawnmanager ped before the custom spawn took over.
**Error:** On connect the player got infinite loading, then (after a partial fix) saw the default world for a frame and got stuck on a black screen. The server log showed the join but never `playerReady`/`needCharacter`.
**Root cause:** The default **spawnmanager waits for `IsScreenFadedIn()` before firing `playerSpawned`** (its `spawnPlayer` coroutine fades in and loops until the screen is in). The guard re-faded-OUT every frame, so `IsScreenFadedIn()` was never true → spawnmanager hung → `playerSpawned` never fired → v-core never got `playerReady` → `needCharacter` never sent → the creator never opened → the native loadscreen never dismissed. An earlier variant of the guard also `FreezeEntityPosition`'d the pre-spawn ped, which independently blocked the spawn.
**Fix:** Removed the black-out guard entirely. The spawnmanager now completes its fade-in and fires `playerSpawned` normally; `startCreator` / the `onPlayerLoaded` handler fade out and take over immediately after. The brief flash of the default spawn point is accepted; the real bug (falling into the void) stays fixed in `switchSpawn` (freeze + stream collision + ground-Z before unfreeze).
**Prevention:** **Never hold the screen faded-out (or freeze the player ped) before the first `playerSpawned`.** The default spawn flow needs `IsScreenFadedIn()` to be reachable. Do all custom fading/freezing AFTER `playerSpawned` (i.e. inside `needCharacter` / `onPlayerLoaded`), never in a pre-spawn loop.

## [2026-07-10 17:10] — No mouse cursor in inventory / admin / banking / shops / clothing

**Context:** Every NUI menu routed its focus through a shared helper, `exports['v-core']:OpenMenu()`, which called `SetNuiFocus(true, true)` inside v-core.
**Error:** The panels rendered, but the player had no cursor and no keyboard capture — the UI was impossible to use. v-hud (F7) and v-spawn were unaffected.
**Root cause:** `SET_NUI_FOCUS` is **scoped to the calling resource**. In `code/components/nui-resources/src/ResourceUIScripting.cpp` the handler fetches the *caller's* `ResourceUI`, returns early when `resourceUI->HasFrame()` is false, and otherwise posts `{"type":"focusFrame","frameName":"<caller resource name>"}`. `v-core` declares no `ui_page`, so `HasFrame()` was false and the call was a **silent no-op** — no error, no log line. Even with a frame it would have focused v-core's own page, never the module's. The two modules that still called `SetNuiFocus` locally (v-hud, v-spawn) kept working, which is exactly the pattern that made the bug look module-specific.
**Fix:** `v-core/client/focus.lua` no longer touches `SetNuiFocus`; it only keeps the reference-counted `LocalPlayer.state.nuiOpen` bookkeeping, renamed to `MenuOpened()` / `MenuClosed()` (+ `IsAnyMenuOpen()`). Each owning resource now calls `SetNuiFocus` itself, immediately next to its `MenuOpened()` / `MenuClosed()` report.
**Prevention:** **Never call `SetNuiFocus`, `SendNUIMessage`, `RegisterNUICallback` or `SetNuiFocusKeepInput` from a resource that does not declare the `ui_page`.** They are all resolved against the calling resource's own NUI frame. A shared helper may own *bookkeeping* (statebags, ref-counting), never the native itself. When a native silently does nothing, check whether it is resource-scoped before assuming the arguments are wrong.

## [2026-07-08 08:29] — Expand-Archive fails on bracketed resource folders

**Context:** Extracting `oxmysql.zip` / `menuv.zip` directly into `resources/[standalone]` with PowerShell `Expand-Archive`.
**Error:** `New-Item : Il existe déjà un élément avec le nom spécifié ...[standalone]` — extraction aborted.
**Root cause:** FiveM resource group folders use square brackets (`[standalone]`). PowerShell treats `[` `]` in `-DestinationPath` as wildcard/character-class globs, so the literal path is misresolved.
**Fix:** Extract into a bracket-free temp directory, then move the contents into the bracketed folder with the Bash tool (which handles brackets when the path is quoted).
**Prevention:** Never pass a bracketed path to PowerShell path parameters that glob. Use a temp dir + `mv`, or `[System.IO.Compression.ZipFile]::ExtractToDirectory` with a literal path, or the Bash tool for any file op touching `[...]` folders.

## [2026-07-08 12:xx] — In-game NUI/interface bugs the headless preview missed

**Context:** First real in-game test of the joined experience (loadscreen → language → character creation → HUD). A browser preview validated each NUI in isolation but not the integrated in-game render.
**Symptoms reported in-game:**
- Oversized opaque "black boxes" behind widgets (the compass box was far wider than its content).
- Character-creation menus unusable: couldn't type in inputs, couldn't tell where to click.
- Default GTA HUD (health/armor near minimap, default cash) shown alongside the custom HUD.
- Accent rendered purple instead of orange.
**Root causes (audited):**
- Native GTA HUD never hidden (only cash added afterwards).
- No routing-bucket isolation for creation → simultaneous new players would share the world.
- CEF-sensitive CSS: `width: max-content` on fixed widgets, reliance on `backdrop-filter`/`mask-image`, and cross-resource `cfx-nui-v-ui/theme.css` loading — brittle in-game.
- Risk of a Lua error in `v-spawn` `startCreator` aborting before `DoScreenFadeIn` (black screen).
**Fix:** Hide native HUD; isolate creation in a private routing bucket (`SetPlayerRoutingBucket`); replace `max-content` widget widths with explicit widths; inline the theme locally per resource (drop cross-resource load); guard the creation flow so the screen always fades back in.
**Prevention:** Never ship a NUI/interface change without an in-game smoke test. Prefer explicit sizes and self-contained CSS over `max-content` and cross-resource asset loads. Always guarantee `DoScreenFadeIn` runs (wrap risky natives, add a fail-safe).

## [2026-07-10 — session] — Player kicked mid clothing-thumbnail scan
**Context:** Admin launched the F9 clothing scan (v-clothing); each captured screenshot (base64 data URI, ~200-500 KB) was sent to the server with `TriggerServerEvent('v-clothing:server:saveThumb', ...)` in a tight loop.
**Error:** Client kicked from the server during the scan (FiveM reliable network event overflow protection).
**Root cause:** FiveM hard-limits reliable net event payload volume per client; shipping hundreds of large base64 blobs over `TriggerServerEvent` trips the overflow guard and the server drops the player.
**Fix:** Replaced the net-event upload with an HTTP pipeline: the NUI downscales each capture to a 384px square jpeg (canvas, ~4-40 KB) and POSTs it to a `SetHttpHandler` endpoint (`http://<server>/v-clothing/upload`) authenticated by a one-shot scan token; net events now carry only tiny progress/done signals.
**Prevention:** NEVER send images/blobs (> a few KB) through TriggerServerEvent/TriggerClientEvent. Use the resource HTTP handler (SetHttpHandler + NUI fetch or screenshot-basic upload) for any bulk payload, with token auth and a server-side size guard.

## [2026-07-10 — session] — Minimap health/armour bars wouldn't hide
**Context:** v-hud custom minimap. The GTA:O green (health) + blue (armour) bars kept rendering under the minimap even after (a) repositioning, (b) the QBCore squaremap texture swap, and (c) an opaque NUI cover strip.
**Error:** Bars still visible; the square texture reshapes the map but does NOT remove the bars; the NUI cover misaligned because the native map (bottom-aligned) and the CEF frame (top-left) used different coordinate systems (drag also went the wrong way).
**Root cause:** The bars are drawn by the minimap scaleform itself, not a hideable HUD component or a clippable map region — no amount of repositioning/masking removes them at the source.
**Fix:** Verified CFX method — call the minimap scaleform's `SETUP_HEALTH_ARMOUR` with GOLF mode (param 3 = no bars) every frame:
  `local mm = RequestScaleformMovie('minimap'); BeginScaleformMovieMethod(mm,'SETUP_HEALTH_ARMOUR'); ScaleformMovieMethodAddParamInt(3); EndScaleformMovieMethod()`
  Also unify native map + NUI frame on the SAME top-left coordinate space so drag direction and any overlay line up.
**Prevention:** For minimap/HUD scaleform elements, look for the scaleform METHOD that controls them (SETUP_HEALTH_ARMOUR, etc.) instead of trying to mask/clip. When overlaying CEF on a native element, use ONE coordinate system for both. Verify the technique against a known source before shipping instead of guessing offsets blind.

## [2026-07-10 — session] — Minimap distorted / player blip off-centre after resize
**Context:** Added a resizable minimap. Enlarging it distorted the map (stretched imagery) and the player blip drifted off-centre.
**Error:** The minimap `sizeX`/`sizeY` used a wrong aspect ratio (0.160 x 0.178) and were scaled from there; the game renders the map assuming a fixed ratio, so any other ratio stretches the content and de-centres the blip.
**Root cause:** GTA's minimap expects the frontend.xml default ratio sizeX:sizeY = 0.150 : 0.188888. Deviating from it distorts the map; the effect grows with size.
**Fix:** Use baseW=0.150, baseH=0.188888 as the base and scale BOTH by the same size factor (ratio preserved) -> undistorted, blip centred at any size. Verified default from frontend.xml via CFX docs.
**Prevention:** When resizing the native minimap, always preserve the 0.150:0.188888 ratio (scale uniformly). Never set sizeX/sizeY independently.

## [2026-07-10 — session] — Minimap drag wrong place + HUD not hidden in pause (definitive)
**Context:** Draggable minimap landed in the wrong spot; HUD stayed drawn over the pause menu. Fixed after a multi-agent research pass (CFX cookbook, Dalrae1/MinimapPositionFiveM, qb-hud).
**Error 1 (drag):** The NUI frame was placed with raw vw/vh; the native map with SetMinimapComponentPosition('L','B'). The two diverge because SetMinimapComponentPosition works in SAFE-ZONE space (GetSafeZoneSize, per player) + aspect letterboxing — NOT raw screen fractions. So `screen_top = 1 - posY - sizeY` is wrong.
**Fix 1:** Native map = source of truth (component posX/posY/scale, qb square layout). Read its TRUE screen rect via SetScriptGfxAlign('L','B') + GetScriptGfxPosition (the engine's exact inverse — already applies safezone+aspect) and SLAVE the NUI frame to that pixel rect. Drag reports pixel deltas -> 1:1 component delta (posX += dx/resX, posY -= dy/resY). Never hand-roll safezone math.
**Error 2 (pause):** Only the NUI was hidden; DisplayRadar stayed true and a 1.5s re-assert loop + a per-frame scaleform loop forced the radar back on. IsPauseMenuActive() alone also misses the open/close transition and faded/switch screens.
**Fix 2:** A single hudHidden flag gates the minimap loop (DisplayRadar(false)); robust condition set = IsPauseMenuActive or GetPauseMenuState()~=0 or IsScreenFadedOut/FadingOut or IsPlayerSwitchInProgress or GetIsLoadingScreenActive or IsHudHidden or LocalPlayer.state.nuiOpen. Poll at 50ms, send on change.
**Prevention:** For native minimap position/size use the gfx round-trip, never raw fractions. For "hide HUD in menus" gate the NATIVE radar too (not just NUI), use GetPauseMenuState for transitions, and route all menu SetNuiFocus through a ref-counted v-core OpenMenu/CloseMenu that sets LocalPlayer.state.nuiOpen.
