# Error Log

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
