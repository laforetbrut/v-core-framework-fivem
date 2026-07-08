# Project Rules & AI/IDE Instructions

## 1. Project Identity

| Field | Value |
|-------|-------|
| Project name | FiveM Vanilla Dev Server |
| Type | FiveM (GTA V) server — vanilla development base |
| Framework | None (build our own) |
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

## 4. Project Structure

```
fivem/
├── artifacts/                 # FXServer binaries (gitignored, redownloadable)
├── cache/                     # runtime cache (gitignored)
├── resources/
│   ├── [cfx-default]/         # official cfx default resources (the vanilla base) — do not edit
│   └── [local]/               # ← YOUR custom development scripts live here
│       └── hello-world/       # starter resource to copy from
├── server.cfg                 # server configuration (license key here)
├── start.bat / start.ps1      # launchers
├── README.md · CHANGELOG.md · RULES.md · ERROR_LOG.md
└── .gitignore
```

## 5. Adding a New Feature (Step by Step)

1. `git checkout -b feat/<name>` from `develop`.
2. Copy `resources/[local]/hello-world` to `resources/[local]/<your-resource>`.
3. Write `fxmanifest.lua` (declare `client_script` / `server_script` / `shared_script`).
4. Add `ensure <your-resource>` in `server.cfg`.
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
