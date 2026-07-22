# Project Rules & AI/IDE Instructions

## 1. Project Identity

| Field | Value |
|-------|-------|
| Project name | v-core - a roleplay framework for FiveM Enhanced |
| Repository | `laforetbrut/v-core-framework-fivem` (public) |
| Version | 0.1.1 - every module reads the same number |
| Type | FiveM **Enhanced** (GTA V Enhanced) roleplay framework |
| Framework | v-core (custom, in-house - `resources/[local]/v-core`), 34 modules |
| Server runtime | **`cfx-server.exe`** - the Enhanced binary. `FXServer.exe` is Legacy and rejects Enhanced clients |
| Game build | **Never set `sv_enforceGameBuild`** - those are Legacy build numbers and lock Enhanced clients out |
| Base resources | Official cfx-server-data defaults |
| Scripting | Lua 5.4 (primary), JS/NUI for UI |
| Shared helper | `shared_script '@v-core/lib/v.lua'` - see DEVELOPERS.md |
| Sync | OneSync enabled |
| Database | MariaDB / MySQL via `oxmysql`. `database/schema.sql` plus per-module tables created at boot |
| Author | vyrriox |
| License | MIT (our code) / cfx defaults keep their own licenses |

## 2. Git Workflow

- **Branches:** `main` (stable) · `develop` (integration) · `feat/<name>` · `fix/<name>` · `hotfix/<name>`.
- **Commit convention:** `type: short message` - types: `feat`, `fix`, `chore`, `refactor`, `perf`, `docs`.
- **Never commit:** `artifacts/`, `cache/`, `.claude/`, `CLAUDE.md`, `test-procedures/`,
  the local database launchers (`start-db.bat`, `stop-db.bat`, `database/*-db.ps1`), any real `sv_licenseKey`.

## 3. Code Conventions

- **Language policy:** all code, comments, logs, variable names in **English**. UI text may be localized separately.
- **Naming:** Lua locals `camelCase`, exports/globals `PascalCase`, resources `kebab-case`.
- **Events:** namespace every event as `resourceName:eventName` to avoid collisions.
- **Structure:** one resource = one folder in `resources/[local]/`; declare everything in `fxmanifest.lua`.
- **Do NOT:** edit vendored `[cfx-default]` resources (override in `[local]`), hardcode secrets, leave `print` spam in shipped code.

## 3.5 Visual Identity - "EMBER" design system - MANDATORY

**Every** NUI page in this project uses one design language, defined once in
`resources/[local]/v-ui/theme.css` and loaded with
`<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css">`.
Reuse its tokens and primitives. Only override a token locally when the value genuinely differs
for that module. **Never fork the palette.**

**Concept:** a modern dark-glass HUD - deep warm-graphite panels,
generously rounded cards, soft layered shadows, and one **dominant**
brand orange that glows: gradient fills, a light-streak on every panel's top edge, hover and
selection auras. Reference implementation: `resources/[local]/v-inventory/html/`.

**Deliberately avoids the generic "AI" look**: no purple/blue gradients, no pastel colour salad,
no centered emoji cards. The orange stays warm and singular.

### The four signature cues - repeat them in every module

1. **Rounded glass panel** (`.v-chamfer`) - 1px `--v-line` border, `--v-r-lg` radius, a
   translucent `--v-panel*` gradient fill, `var(--v-shadow-box)`, and an **orange light-streak**
   bleeding across the top edge (a `::before` pseudo, so `innerHTML` rewrites never destroy it).
   The fill stays near-opaque: depth comes from the layered gradient and shadow, never from blur.
2. **Orange gradient tab** (`.v-tab`) - a floating pill riding the top edge of every panel
   header: `--v-grad-accent` fill, dark-ink tracked uppercase, glow shadow.
3. **Glowing corner accents** (`.v-brk--tr` / `.v-brk--bl`) - rounded L-bends on two diagonal
   corners with an orange drop-shadow.
4. **Tabular readouts** - every number in `var(--v-font-num)` with
   `font-variant-numeric: tabular-nums`, the significant figure wrapped in `<b>` (orange).

### Palette (CSS variables - the file is the source of truth)

| Token | Value | Use |
|-------|-------|-----|
| `--v-bg-900` … `--v-bg-500` | `#0B0A08` → `#241F1A` | warm graphite surfaces (never neutral black) |
| `--v-panel` / `--v-panel-2` / `--v-panel-3` | translucent rgba | glass panel fills (near-opaque without blur) |
| `--v-bg-sunk` | `#0D0B09` | recessed wells: inputs, gauge/progress tracks |
| `--v-line` / `--v-line-2` | `rgba(255,221,194,.08/.15)` | warm hairline borders |
| `--v-text` / `--v-text-dim` / `--v-text-faint` | `#F5EEE6` / `#B8AFA5` / `#948B81` | text hierarchy (all ≥ 4.5:1) |
| `--v-ink` | `#1A0D03` | dark ink on orange/light fills |
| `--v-accent` / `--v-accent-300` / `--v-accent-600` | `#FF7A1A` / `#FFA85C` / `#E14E00` | **brand orange - dominant** |
| `--v-grad-accent` / `--v-grad-soft` | 135° orange gradients | primary fills / soft tinted washes |
| `--v-success` / `--v-danger` / `--v-warning` / `--v-info` | `#3FA663` / `#E5484D` / `#E8A33D` / `#4C8DCC` | status - quieter than the orange |
| `--v-rar-common` … `--v-rar-mythic` | muted scale | item rarity (legendary = accent, mythic = red) |

### Hard rules

- **Orange is the dominant hue.** Primary actions use `--v-grad-accent` + glow, hover and
  selection states glow orange, active pills and progress fills are orange. Body text stays on
  the neutral text tokens; status colours stay muted and never out-shout the brand.
- **Roundness is the identity.** Radii ≥ 8px everywhere - `--v-r-sm` 8px small controls,
  `--v-r-md` 12px cards, `--v-r-lg` 16px panels, `--v-r-xl` 22px hero cards, 99px pills.
  No sharp-cornered boxes.
- **No blur, ever.** `backdrop-filter` parses in FiveM's CEF but renders as an opaque black
  box - it is forbidden everywhere. Depth comes from layered gradients and shadows, not from
  translucency tricks; panel fills stay near-opaque.
- **Letters get tracking, numbers get tabular figures.** Display = Bahnschrift / Segoe UI;
  small labels uppercase with `.12em`–`.16em` tracking. Numbers = `font-variant-numeric:
  tabular-nums`, `letter-spacing: 0`. Never letter-space a figure.
- Recessed wells use `--v-bg-sunk`. Segmented `.v-gauge` strips and smooth `.v-progress` bars
  both fill with `--v-grad-accent` + glow.
- **Line icons only** (stroke, `currentColor`, `aria-hidden="true"`). Never emoji.
- One soft layered shadow per surface (`--v-shadow-box` / `--v-shadow-sm`). Orange glows come
  from the glow tokens - no stacked rainbow glows.
- **Motion:** one orchestrated open sequence. Panels seat 60ms apart, then slots/rows ripple
  10–18ms apart, driven by an `--i` custom property. Micro-interactions 140–220ms on
  `var(--v-ease)`; springy entrances on `var(--v-ease-spring)`.
  **Always `animation-fill-mode: backwards`, never `both`** - `both` keeps forcing the final
  keyframe's opacity and silently overrides later state classes (hidden, filtered-out, dimmed).

### Accessibility - non-negotiable

- Minimum font-size for real text: **10px**. `--v-text-faint` is the contrast floor (≈5:1).
- Never hardcode a `z-index` - use `--z-below` / `--z-base` / `--z-raised` / `--z-sticky` /
  `--z-tooltip` / `--z-context` / `--z-overlay` / `--z-toast`.
- `aria-label` on every input and icon-only control; `aria-hidden="true"` on decorative SVGs.
- The theme ships a global `:focus-visible` ring and a `prefers-reduced-motion` block.
  Don't duplicate them, don't fight them.

### CEF constraints (FiveM's Chromium - violating these ships a broken UI)

**Forbidden:** `backdrop-filter` (parses but renders as an opaque black box), `color-mix()`,
`:has()`, container queries, CSS nesting, `mask-image`, `@import`, any external font/CDN/network fetch.
**Allowed and used:** `:focus-visible`, `prefers-reduced-motion`, custom properties,
`aspect-ratio`, `gap` on flex, `-webkit-background-clip: text` for gradient figures.

### Change discipline for UI

Any new NUI page starts by linking `theme.css` and composing its primitives. If a module needs a
new shared primitive, add it to `theme.css` - never copy-paste it into a module's `style.css`.

### NUI natives are resource-scoped - MANDATORY

`SetNuiFocus`, `SetNuiFocusKeepInput`, `SendNUIMessage` and `RegisterNUICallback` all resolve
against **the calling resource's own NUI frame**. `SET_NUI_FOCUS` returns early when the caller has
no frame (`resourceUI->HasFrame()`), so calling it from a resource without a `ui_page` is a **silent
no-op** - no error, no log.

- Only the resource that declares the `ui_page` may call them. Never proxy them through a helper
  resource; a shared helper may own *bookkeeping* (statebags, ref-counting), never the native.
- Take and release focus next to the bookkeeping call:
  ```lua
  SetNuiFocus(true, true)            -- in the resource that owns the page
  exports['v-core']:MenuOpened()     -- v-core only maintains LocalPlayer.state.nuiOpen
  ```
- Always release focus in `onResourceStop`, or a restart leaves the player's cursor stuck.

## 3.6 Interaction & Management principles - MANDATORY

1. **No player chat commands.** Players interact only through the phone (iFruit), radial menu, custom pause menu, and target/context UI. Keybinds are fine; typed commands are not. Admin/dev commands may exist but must be permission-gated.
2. **Everything manageable in-game via permissions.** Every content system must let an authorized user create/modify/delete its data live in-game (jobs, grades, prices, shops, items, vehicles, weather…). Build management UIs, not console commands; gate them with the v-core permission tiers (`user < mod < admin < superadmin`) and surface them in `v-admin`.
3. **Respect GTA lore.** Use real GTA companies/brands (Fleeca, Maze Bank, Ammu-Nation, Los Santos Customs, LSPD, iFruit…). Never invent brands. Modules keep the dominant orange accent and the EMBER language (§3.5) - subject-specific variation happens in iconography and copy, not in the palette.

## 3.7 Change discipline - MANDATORY

Whenever a script is created or modified:
1. **Trace the wiring.** Check every resource that communicates with it (exports, events, callbacks, shared DB tables) and update those call sites so nothing breaks.
2. **Update the docs that go with it.** Keep `ARCHITECTURE.md` (API + wiring), `CHANGELOG.md`, `RULES.md`, and any module README in sync with the change - in the same commit.
3. **Always update the Module roadmap** (in `ARCHITECTURE.md`) every time work starts or finishes on a module - mark it 🔨 in-progress or ✅ done.
4. **i18n:** every player-facing string goes through the locale system (`L('key')`), with both `fr` and `en` entries added. Never hardcode display text.
5. **In-game configurable:** every content system ships a permission-gated in-game management UI (no console-only config).

## 4. Project Structure

```
fivem/
├── artifacts/                 # Enhanced binaries, cfx-server.exe (gitignored, redownloadable)
├── cache/                     # runtime cache (gitignored)
├── database/
│   └── schema.sql             # base tables; modules create their own at boot
├── resources/
│   ├── [cfx-default]/         # official cfx default resources - do not edit
│   ├── [standalone]/          # oxmysql, screenshot-basic
│   └── [local]/               # our 34 modules
│       ├── v-core/            # the framework core, and lib/v.lua (the shared helper)
│       ├── v-ui/              # the design system: theme.css + generated theme-vars.css
│       ├── v-world/           # admin-editable world content, 21 domains
│       ├── v-admin/           # the in-game panel (F10)
│       └── …                  # one folder per module, see ARCHITECTURE.md
├── server.cfg                 # server config; sv_licenseKey lives in license.cfg (gitignored)
├── start.ps1                  # server launcher
├── README.md · ARCHITECTURE.md · API.md · DEVELOPERS.md · CONTRIBUTING.md
├── CHANGELOG.md · RULES.md · ERROR_LOG.md · IDEAS.md · LICENSE
└── .gitignore
```

## 5. Adding a New Feature (Step by Step)

1. `git checkout -b feat/<name>` from `develop`.
2. Create `resources/[local]/<your-resource>/` with an `fxmanifest.lua`.
3. Load the helper: `shared_script '@v-core/lib/v.lua'`, then use `V.Ready`, `V.Module`,
   `V.Setting`, `V.Use`, `V.Callback` and `V.Notify`. See **DEVELOPERS.md** for a complete
   module in 40 lines. `exports['v-core']:GetCore()` still works, but the helper is shorter
   and removes the boot-order guesswork.
4. Add `ensure <your-resource>` in `server.cfg` **after** `v-core`.
5. Test in-game: `refresh` + `ensure <resource>` (or `restart <resource>`) from the server console.
6. Update `CHANGELOG.md`. Commit with `feat: ...` and open a PR into `develop`.

## 6. Testing Checklist

- [ ] Server boots with no errors in the console (`start.bat`).
- [ ] `refresh` then `ensure <resource>` loads the resource with no red errors.
- [ ] Feature works in-game with a connected client.
- [ ] No regressions in other `[local]` resources.
- [ ] No hardcoded secrets / debug spam left in.

## 7. Environment Setup

1. **Artifacts** (if missing): download `server.zip` from the cfx.re artifacts and extract into `artifacts/`.
2. **License key:** set a valid `sv_licenseKey` in `server.cfg` (free at https://keymaster.fivem.net/).
3. **Run:** `./start.ps1`.
4. **Connect:** in the FiveM client, `F8` → `connect localhost:30120`.

## 8. AI Assistant Instructions

1. Never edit vendored `[cfx-default]` resources - build/override inside `resources/[local]`.
2. Never write a real `sv_licenseKey` into a committed file.
3. Keep all code/comments in English; talk to the user in French.
4. After any change, verify the affected resource loads (console `refresh`/`ensure`) before reporting success.
5. Preserve existing authors; add `vyrriox` as co-author, never remove credits.
6. Do not bump versions unless explicitly asked.
7. Log every error encountered to `ERROR_LOG.md` with a prevention rule.
8. Only add a database (oxmysql + MariaDB) when a feature actually needs persistence - keep the base lean.
9. **Every NUI page must follow the EMBER design system (§3.5).** Link `v-ui/theme.css`, compose its primitives, and carry the four signature cues. A UI that merely uses the right colours but drops the rounded glass panel / gradient tab / corner accents / tabular readouts is a regression, not a restyle.
10. Before touching a module's NUI, read its `app.js` in full and list every id / class / dataset it reads. Restyle existing hooks - never rename or delete one. Pseudo-elements survive `innerHTML` rewrites; wrapper elements do not.
