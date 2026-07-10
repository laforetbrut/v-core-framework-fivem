# Project Rules & AI/IDE Instructions

## 1. Project Identity

| Field | Value |
|-------|-------|
| Project name | FiveM Vanilla Dev Server |
| Type | FiveM (GTA V) server — vanilla development base |
| Framework | v-core (custom, in-house — `resources/[local]/v-core`) |
| Server runtime | FXServer (cfx.re) — build 25770 (recommended) |
| Base resources | Official cfx-server-data defaults |
| Scripting | Lua (primary), JS/NUI for UI |
| Sync | OneSync enabled |
| Database | None yet (add `oxmysql` + MariaDB when persistence is needed) |
| Author | vyrriox |
| License | MIT (our code) / cfx defaults keep their own licenses |

## 2. Git Workflow

- **Branches:** `main` (stable) · `develop` (integration) · `feat/<name>` · `fix/<name>` · `hotfix/<name>`.
- **Commit convention:** `type: short message` — types: `feat`, `fix`, `chore`, `refactor`, `perf`, `docs`.
- **Never commit:** `artifacts/`, `cache/`, `.claude/`, `CLAUDE.md`, `test-procedures/`, any real `sv_licenseKey`.

## 3. Code Conventions

- **Language policy:** all code, comments, logs, variable names in **English**. UI text may be localized separately.
- **Naming:** Lua locals `camelCase`, exports/globals `PascalCase`, resources `kebab-case`.
- **Events:** namespace every event as `resourceName:eventName` to avoid collisions.
- **Structure:** one resource = one folder in `resources/[local]/`; declare everything in `fxmanifest.lua`.
- **Do NOT:** edit vendored `[cfx-default]` resources (override in `[local]`), hardcode secrets, leave `print` spam in shipped code.

## 3.5 Visual Identity — "FIELD CASE" design system — MANDATORY

**Every** NUI page in this project uses one design language, defined once in
`resources/[local]/v-ui/theme.css` and loaded with
`<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css">`.
Reuse its tokens and primitives. Only override a token locally when the value genuinely differs
for that module. **Never fork the palette.**

**Concept:** a ruggedized equipment flight-case cracked open on a workbench — foam-cutout slots,
stenciled hazard labels, riveted corner brackets, gauge-cluster readouts. It must read like a
Pelican case in a lock-up garage, **not** like a web UI. Reference implementation:
`resources/[local]/v-inventory/html/`.

**Deliberately avoids the generic "AI" look**: no purple/blue gradients, no glassmorphism, no
centered emoji cards, no pastel rounded everything, no evenly-distributed warm wash.

### The four signature cues — repeat them in every module

1. **Chamfered panel** (`.v-chamfer`) — top-left / bottom-right corners cut. Implemented as a 1px
   border pseudo-layer + a fill pseudo-layer, both `clip-path`'d, so tabs can bleed off the edge
   and the drop-shadow sits on a cheap solid layer instead of repainting the children on hover.
   Set `--v-cw` per element (14px panels, 10px small floats).
2. **Orange stencil tab** (`.v-tab`) — a parallelogram riding the top edge of every panel header,
   carrying the section name in tracked uppercase.
3. **Machined L-brackets** (`.v-brk--tr` / `.v-brk--bl`) on the two sharp corners.
4. **Consolas caliper readouts** — every number in `var(--v-font-num)`, tight, right-aligned,
   the significant figure wrapped in `<b>` (orange).

### Palette (CSS variables — the file is the source of truth)

| Token | Value | Use |
|-------|-------|-----|
| `--v-bg-900` … `--v-bg-500` | `#0A0908` → `#221D18` | warm charcoal surfaces (never neutral black) |
| `--v-bg-sunk` | `#0E0C0A` | recessed wells: inputs, gauges, slots |
| `--v-line` / `--v-line-2` | `#2C2620` / `#3A332B` | borders |
| `--v-text` / `--v-text-dim` / `--v-text-faint` | `#EFE7DC` / `#A9A199` / `#8F877E` | text hierarchy (all ≥ 4.5:1) |
| `--v-ink` | `#170D05` | dark ink on orange/light fills |
| `--v-accent` / `--v-accent-300` / `--v-accent-600` | `#FF6A1A` / `#FF9354` / `#A83C0D` | **brand orange** / hover / pressed |
| `--v-success` / `--v-danger` / `--v-warning` / `--v-info` | `#5FA36A` / `#C2362F` / `#C98A2B` / `#2F6F9E` | status — muted on purpose |
| `--v-rar-common` … `--v-rar-mythic` | earthy | item rarity |

### Hard rules

- **Orange is the only saturated hue on screen**, and it stays under ~10% of pixels: accents, one
  tab per header, fills, hover. Charcoal dominates; orange punches. Status colours are muted and
  must never out-shout it. Only *legendary* and *mythic* rarity are allowed to bloom.
- **No blur, no translucency for depth.** Depth is inset shadow. `backdrop-filter` renders as an
  opaque black box in CEF 103 anyway.
- **Don't round everything.** Radii ≤ 3px (`--v-r-sm` 2px, `--v-r-md` 3px). The identity is
  chamfers and hard notches, not pills.
- **Letters get tracking, numbers get none.** Display = Bahnschrift Condensed uppercase,
  `.12em`–`.24em`. Numbers = Consolas, `letter-spacing: 0`, tabular. Never letter-space a figure.
- Recessed wells use `--v-bg-sunk` + inset shadows. Smooth progress bars become segmented
  `.v-gauge` notch strips wherever a discrete reading makes sense.
- **Line icons only** (stroke, `currentColor`, `aria-hidden="true"`). Never emoji.
- One tasteful drop-shadow per surface. One `0 1px 2px #000` text-shadow for legibility over
  images — no stacked glows.
- **Motion:** one orchestrated open sequence. Panels seat 70ms apart, then slots/rows ripple
  12–18ms apart, driven by an `--i` custom property. Micro-interactions 150–200ms.
  **Always `animation-fill-mode: backwards`, never `both`** — `both` keeps forcing the final
  keyframe's opacity and silently overrides later state classes (hidden, filtered-out, dimmed).

### Accessibility — non-negotiable

- Minimum font-size for real text: **10px**. `--v-text-faint` is the contrast floor (≈5:1).
- Never hardcode a `z-index` — use `--z-base` / `--z-raised` / `--z-sticky` / `--z-tooltip` /
  `--z-context` / `--z-overlay` / `--z-toast`.
- `aria-label` on every input and icon-only control; `aria-hidden="true"` on decorative SVGs.
- The theme ships a global `:focus-visible` ring and a `prefers-reduced-motion` block.
  Don't duplicate them, don't fight them.

### CEF 103 constraints (FiveM's Chromium — violating these ships a broken UI)

**Forbidden:** `backdrop-filter`, `color-mix()`, `:has()`, container queries, CSS nesting,
`mask-image`, `@import`, any external font/CDN/network fetch.
**Allowed and used:** `clip-path: polygon()` with `calc()`, `:focus-visible`,
`prefers-reduced-motion`, custom properties, `aspect-ratio`, `gap` on flex.

### Change discipline for UI

Any new NUI page starts by linking `theme.css` and composing its primitives. If a module needs a
new shared primitive, add it to `theme.css` — never copy-paste it into a module's `style.css`.

### NUI natives are resource-scoped — MANDATORY

`SetNuiFocus`, `SetNuiFocusKeepInput`, `SendNUIMessage` and `RegisterNUICallback` all resolve
against **the calling resource's own NUI frame**. `SET_NUI_FOCUS` returns early when the caller has
no frame (`resourceUI->HasFrame()`), so calling it from a resource without a `ui_page` is a **silent
no-op** — no error, no log.

- Only the resource that declares the `ui_page` may call them. Never proxy them through a helper
  resource; a shared helper may own *bookkeeping* (statebags, ref-counting), never the native.
- Take and release focus next to the bookkeeping call:
  ```lua
  SetNuiFocus(true, true)            -- in the resource that owns the page
  exports['v-core']:MenuOpened()     -- v-core only maintains LocalPlayer.state.nuiOpen
  ```
- Always release focus in `onResourceStop`, or a restart leaves the player's cursor stuck.

## 3.6 Interaction & Management principles — MANDATORY

1. **No player chat commands.** Players interact only through the phone (iFruit), radial menu, custom pause menu, and target/context UI. Keybinds are fine; typed commands are not. Admin/dev commands may exist but must be permission-gated.
2. **Everything manageable in-game via permissions.** Every content system must let an authorized user create/modify/delete its data live in-game (jobs, grades, prices, shops, items, vehicles, weather…). Build management UIs, not console commands; gate them with the v-core permission tiers (`user < mod < admin < superadmin`) and surface them in `v-admin`.
3. **Respect GTA lore.** Use real GTA companies/brands (Fleeca, Maze Bank, Ammu-Nation, Los Santos Customs, LSPD, iFruit…). Never invent brands. Modules keep the single orange accent and the Field Case language (§3.5) — subject-specific variation happens in iconography and copy, not in the palette.

## 3.7 Change discipline — MANDATORY

Whenever a script is created or modified:
1. **Trace the wiring.** Check every resource that communicates with it (exports, events, callbacks, shared DB tables) and update those call sites so nothing breaks.
2. **Update the docs that go with it.** Keep `ARCHITECTURE.md` (API + wiring), `CHANGELOG.md`, `RULES.md`, and any module README in sync with the change — in the same commit.
3. **Always update the Module roadmap** (in `ARCHITECTURE.md`) every time work starts or finishes on a module — mark it 🔨 in-progress or ✅ done.
4. **i18n:** every player-facing string goes through the locale system (`L('key')`), with both `fr` and `en` entries added. Never hardcode display text.
5. **In-game configurable:** every content system ships a permission-gated in-game management UI (no console-only config).

## 4. Project Structure

```
fivem/
├── artifacts/                 # FXServer binaries (gitignored, redownloadable)
├── cache/                     # runtime cache (gitignored)
├── resources/
│   ├── [cfx-default]/         # official cfx default resources (the vanilla base) — do not edit
│   └── [local]/               # ← our custom development scripts live here
│       └── v-core/            # our roleplay framework core (exports GetCore)
├── server.cfg                 # server configuration (license key here)
├── start.bat / start.ps1      # launchers
├── README.md · CHANGELOG.md · RULES.md · ERROR_LOG.md
└── .gitignore
```

## 5. Adding a New Feature (Step by Step)

1. `git checkout -b feat/<name>` from `develop`.
2. Create `resources/[local]/<your-resource>/` with an `fxmanifest.lua`.
3. Consume the core: `local Core = exports['v-core']:GetCore()` — build on its functions.
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
3. **Run:** double-click `start.bat` (or `./start.ps1`).
4. **Connect:** in the FiveM client, `F8` → `connect localhost:30120`.

## 8. AI Assistant Instructions

1. Never edit vendored `[cfx-default]` resources — build/override inside `resources/[local]`.
2. Never write a real `sv_licenseKey` into a committed file.
3. Keep all code/comments in English; talk to the user in French.
4. After any change, verify the affected resource loads (console `refresh`/`ensure`) before reporting success.
5. Preserve existing authors; add `vyrriox` as co-author, never remove credits.
6. Do not bump versions unless explicitly asked.
7. Log every error encountered to `ERROR_LOG.md` with a prevention rule.
8. Only add a database (oxmysql + MariaDB) when a feature actually needs persistence — keep the base lean.
9. **Every NUI page must follow the Field Case design system (§3.5).** Link `v-ui/theme.css`, compose its primitives, and carry the four signature cues. A UI that merely uses the right colours but drops the chamfer / stencil tab / brackets / Consolas readouts is a regression, not a restyle.
10. Before touching a module's NUI, read its `app.js` in full and list every id / class / dataset it reads. Restyle existing hooks — never rename or delete one. Pseudo-elements survive `innerHTML` rewrites; wrapper elements do not.
