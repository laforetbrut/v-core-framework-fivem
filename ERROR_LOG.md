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
