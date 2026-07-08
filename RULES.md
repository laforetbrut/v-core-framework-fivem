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

## 3.5 Visual Identity (v-ui) — MANDATORY

All in-game UI shares **one** design language, defined once in `resources/[local]/v-ui/theme.css` and reused via `<link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css">`.

**Mood:** dark, warm-orange, condensed-industrial, high-legibility — tactical RP, not corporate. **Deliberately avoids the generic "AI" look**: no purple/blue gradients, no heavy glassmorphism, no centered emoji cards, no pastel rounded everything.

**Palette (CSS variables):**

| Token | Value | Use |
|-------|-------|-----|
| `--v-bg-900` | `#0B0B0D` | app background (near-black) |
| `--v-bg-800` / `--v-bg-700` / `--v-bg-600` | `#101015` / `#17171D` / `#1E1E26` | panel · raised · input |
| `--v-line` / `--v-line-2` | `#2A2A33` / `#3B3B47` | borders |
| `--v-text` / `--v-text-dim` / `--v-text-faint` | `#ECEAE6` / `#9C99A2` / `#63616C` | text hierarchy |
| `--v-accent` | `#FF6A1A` | **primary orange (brand)** |
| `--v-accent-600` / `--v-accent-300` | `#E8560C` / `#FF9354` | pressed / hover |
| `--v-success` / `--v-danger` / `--v-warning` / `--v-info` | `#43C46A` / `#E5484D` / `#F5A623` / `#4AA8FF` | status |

**Typography:**
- Display & numbers: `Bahnschrift` (condensed, industrial) — titles, money, stats.
- Body: `Segoe UI`. Mono: `Consolas` for ids/codes.
- Numbers always `font-variant-numeric: tabular-nums`.

**Rules:**
- One accent only (orange). No second brand color.
- Labels: UPPERCASE + letter-spacing. Body: sentence case.
- Sharp & restrained: 6–16px radii, thin borders, subtle shadows. No glow except accent-on-hover.
- Line icons (stroke, `currentColor`) — **never emoji**.
- Motion is quick and functional (120–350ms), never bouncy.

## 3.6 Interaction & Management principles — MANDATORY

1. **No player chat commands.** Players interact only through the phone (iFruit), radial menu, custom pause menu, and target/context UI. Keybinds are fine; typed commands are not. Admin/dev commands may exist but must be permission-gated.
2. **Everything manageable in-game via permissions.** Every content system must let an authorized user create/modify/delete its data live in-game (jobs, grades, prices, shops, items, vehicles, weather…). Build management UIs, not console commands; gate them with the v-core permission tiers (`user < mod < admin < superadmin`) and surface them in `v-admin`.
3. **Respect GTA lore.** Use real GTA companies/brands (Fleeca, Maze Bank, Ammu-Nation, Los Santos Customs, LSPD, iFruit…). Never invent brands. Modules may vary their accent to fit their subject while keeping the dark base (§3.5).

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
