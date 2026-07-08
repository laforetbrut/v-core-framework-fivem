# Project Rules & AI/IDE Instructions

## 1. Project Identity

| Field | Value |
|-------|-------|
| Project name | QBCore Dev Server |
| Type | FiveM (GTA V) roleplay server — development environment |
| Framework | QBCore (`qb-core`) |
| Server runtime | FXServer (cfx.re) — build 25770 (recommended) |
| Game build | 3095 (The Chop Shop DLC) |
| Database | MariaDB via `oxmysql` |
| Scripting | Lua (primary), JS/NUI for UI |
| Author | vyrriox |
| License | Per-resource (QBCore is GPL-3.0) |
| Core dependencies | `qb-core`, `oxmysql`, `pma-voice`, `PolyZone`, `qb-target`, `qb-menu`, `qb-input` |

## 2. Git Workflow

- **Branches:** `main` (stable) · `develop` (integration) · `feat/<name>` · `fix/<name>` · `hotfix/<name>`.
- **Commit convention:** `type: short message` — types: `feat`, `fix`, `chore`, `refactor`, `perf`, `docs`.
- **Never commit:** `artifacts/`, `cache/`, `.claude/`, `CLAUDE.md`, `test-procedures/`, any `sv_licenseKey` real value.
- **Release:** merge `develop` → `main`, tag `vX.Y.Z`, update `CHANGELOG.md`.

## 3. Code Conventions

- **Language policy:** all code, comments, logs, variable names in **English**. UI text may be localized separately.
- **Naming:** Lua locals `camelCase`, globals/exports `PascalCase`, resources `kebab-case` (prefix custom scripts to avoid clashes).
- **QBCore access:** always `local QBCore = exports['qb-core']:GetCoreObject()` at the top of client/server files.
- **DB access:** use `oxmysql` exports (`MySQL.query`, `MySQL.insert`, `MySQL.update`) — never raw sockets.
- **Do NOT:** hardcode credentials, edit vendored QBCore resources directly (fork or override in `[local]`), commit secrets, ship `print` spam.

## 4. Project Structure

```
fivem/
├── artifacts/                 # FXServer binaries (gitignored, redownloadable)
├── cache/                     # runtime cache (gitignored)
├── resources/
│   ├── [cfx-default]/         # default cfx resources (mapmanager, spawnmanager, ...)
│   ├── [standalone]/          # oxmysql, PolyZone, progressbar, menuv, ...
│   ├── [voice]/               # pma-voice, qb-radio
│   ├── [defaultmaps]/         # hospital_map, dealer_map, prison_map
│   ├── [qb]/                  # QBCore framework resources (qb-core + jobs/systems)
│   └── [local]/               # ← YOUR custom development scripts live here
│       └── dev-starter/       # example resource to copy from
├── server.cfg                 # server configuration (license key + DB string here)
├── start.bat / start.ps1      # launchers
├── README.md · CHANGELOG.md · RULES.md
└── .gitignore
```

## 5. Adding a New Feature (Step by Step)

1. `git checkout -b feat/<name>` from `develop`.
2. Create `resources/[local]/<your-resource>/` (copy `dev-starter/` as a base).
3. Write `fxmanifest.lua` (declare `client_script` / `server_script` / `shared_script`).
4. Add `ensure <your-resource>` is covered — `[local]` folder ensure starts it automatically.
5. Add SQL to a migration file if the feature needs tables; import into the `qbcore` DB.
6. Test in-game (`refresh` + `ensure <resource>` or `restart <resource>` from the server console).
7. Update `CHANGELOG.md`. Commit with `feat: ...` and open a PR into `develop`.

## 6. Testing Checklist

- [ ] Server boots with no errors in the console (`start.bat`).
- [ ] `refresh` then `ensure <resource>` loads the resource with no red errors.
- [ ] `oxmysql` connects (no `[oxmysql] connection` errors on boot).
- [ ] Feature works in-game with a connected client.
- [ ] No regressions in dependent QBCore resources.
- [ ] No hardcoded secrets / debug spam left in.

## 7. Environment Setup

1. **Artifacts** (if missing): download `server.zip` from the cfx.re artifacts and extract into `artifacts/`.
2. **Database:** MariaDB service running on `localhost:3306`, database `qbcore` imported from the QBCore SQL.
3. **License key:** set a valid `sv_licenseKey` in `server.cfg` (free at https://keymaster.fivem.net/).
4. **Run:** double-click `start.bat` (or `./start.ps1`).
5. **Connect:** in the FiveM client, `F8` → `connect localhost:30120`.

## 8. AI Assistant Instructions

1. Never edit vendored QBCore resources — extend/override inside `resources/[local]`.
2. Never write a real `sv_licenseKey` or DB password into a committed file.
3. Keep all code/comments in English; talk to the user in French.
4. After any change, verify the affected resource loads (console `refresh`/`ensure`) before reporting success.
5. Preserve existing authors; add `vyrriox` as co-author, never remove credits.
6. Do not bump versions unless explicitly asked.
7. Log every error encountered to `ERROR_LOG.md` with a prevention rule.
