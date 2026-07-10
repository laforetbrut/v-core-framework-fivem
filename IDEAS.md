# Ideas & Roadmap — Projet R (v-core)

Living backlog of enhancements and complementary modules. Not commitments — a place to
capture good ideas as they surface so nothing is lost. Grouped by theme, roughly ordered
by value/effort. Tick items as they ship.

> Constraints reminder: GTA V lore only (no invented brands), no player commands (everything
> via phone/radial/pause + permissions), Field Case design system, version locked at 1.0.0.

---

## A. Inventory (`v-inventory`) — enhancements

- [x] **Weapon jam at low condition** ✅ (shipped) — worn weapons jam on firing, forcing a reload.
- [ ] **Food / perishable time-decay** — items spoil over real time (store `spoilAt` on craft/spawn);
      spoiled food heals less or turns into `spoiled_food`. Server-computed on open, never silent-deletes.
- [ ] **Tool durability** — extend the weapon wear model to lockpicks / drills / repair kits (chance to
      break per use), feeding the crafting economy.
- [ ] **Item inspection / 3D preview** — right-click → "Inspect" shows the item prop in a small viewport.
- [ ] **Split / combine stacks by keyboard** — shift-drag split exists; add a numeric split modal + "combine all".
- [ ] **Quick-use radial from the hotbar** — number keys 1–5 already; add a wheel for controllers.
- [ ] **Weight-based movement penalty** — over X% capacity slows sprint (ties into `v-status` stamina).
- [ ] **Container categories & search** — filter chips (weapons / food / materials…) + text search in big stashes.
- [ ] **Evidence / serial tracking** — weapons keep an owner-history trail on metadata for police RP.
- [ ] **Move direct-SQL `items`/`stashes` access behind `v-core`** (from the architecture audit).

## B. Crafting (`v-crafting`) — enhancements

- [ ] **In-game recipe editor** (admin) — add/edit recipes without a resource restart (DB-backed).
- [ ] **Server-side craft timer** — move the progress duration server-side to fully close the client-time gap.
- [ ] **Crafting XP / skill tree** — repeated crafts unlock faster times, bulk crafting, rare recipes (roadmap #9).
- [ ] **Blueprints as items** — a recipe is locked until the player owns/learns its blueprint.
- [ ] **Batch queue** — queue several crafts instead of one at a time.
- [ ] **Salvage / dismantle** — break an item back into a fraction of its materials at the workbench.
- [ ] **Job-gated benches** — mechanic/medic/police stations with restricted recipes (uses the existing `gate`).

## C. Weapons — enhancements

- [ ] **Addon-weapon component map** — fill `data/attachments.lua` for ak74 / ar15 / m4a4 / .38 once their
      component hashes are known (they currently return "doesn't fit").
- [ ] **Weapon-on-back / holster props** — visible slung rifle / holstered pistol while not drawn.
- [ ] **Tints & skins as attachments** — weapon tint index stored on metadata, applied on draw.
- [ ] **Ammo types** — AP vs ball already exist as items; make them actually swap the loaded round.

---

## D. Complementary NEW modules (pair well with inventory/crafting)

- [ ] **`v-jobs`** (high) — jobs, grades, duty, salaries + in-game manager. Unlocks job-gated benches,
      shops, stashes, and the police search permission the frisk system already stubs.
- [x] **`v-shops` selling + hardening** ✅ (shipped) — Buy/Sell toggle, scrap dealer buys raw materials,
      server-authoritative proximity + job-lock enforced. *Next:* in-game stock/price editor, dynamic
      market pricing (supply/demand), restock consuming crafted goods → fully player-driven economy.
- [ ] **`v-drugs`** (high) — growing/cooking/processing chains that feed `v-crafting` (weed → joint, coke
      brick → baggies) and the drug items already in the catalogue. Sell zones + police heat.
- [x] **`v-gathering` / resource jobs** ✅ (shipped) — mining / salvage / textile nodes produce raw
      materials (`iron`, `copper`, `cloth`…) crafting consumes. Closes the loop: gather → craft → sell.
      *Next:* tool-gated gathering (pickaxe/durability), gathering XP, more node types (wood, oil, chemicals
      for `gunpowder`), processing stations (ore → ingot).
- [ ] **`v-phone`** (high) — iFruit NUI: primary interaction surface (marketplace to sell crafted items,
      messages, bank, job apps). The server has no chat, so this is a keystone.
- [ ] **`v-radial`** (high) — context radial menu (the other main interaction surface): frisk, give,
      craft-here, vehicle actions — replaces the temporary keybinds (H/X/etc.).
- [ ] **`v-vending` / dispensers** (medium) — placeable vending machines & the garbage job (roadmap #9);
      simple recurring income + item sinks.
- [ ] **`v-storage-rental`** (medium) — rentable warehouses/lockers using the shared-stash engine already built.
- [ ] **`v-blackmarket`** (medium) — illegal buyer for stolen/crafted contraband; ties frisk-stealing to an outlet.
- [ ] **`v-repair` / mechanic** (medium) — vehicle repair consuming `repair_kit`/`tire`/`car_battery` items.
- [ ] **`v-anticheat`** (medium) — server-side sanity checks (money/health/explosion guards), logged.

---

## E. Cross-cutting polish

- [ ] **Central `v-target` interaction** — one eye/entity-target system feeding every module's "press E" (benches,
      stashes, peds, players) instead of per-resource proximity loops. Cleaner + cheaper on the client.
- [ ] **Unified notifications** — make sure every module routes through `v-notify` for a consistent look.
- [ ] **Sound design pass** — shared SFX helper (open/close/craft/jam) for a cohesive audio identity.
- [ ] **Localization sweep** — verify fr/en parity across all modules; consider a third language toggle.
- [ ] **Persistence audit** — confirm every metadata-bearing item (weapons, attachments, durability) round-trips
      through save/load and character switch without loss.

---

*Last updated: 2026-07-11. Add freely; keep it lore-safe and permission-driven.*
