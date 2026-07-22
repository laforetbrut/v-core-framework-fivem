# Ideas & Roadmap - Projet R (v-core)

Living backlog of enhancements and complementary modules. Not commitments - a place to
capture good ideas as they surface so nothing is lost. Grouped by theme, roughly ordered
by value/effort. Tick items as they ship.

> Constraints reminder: GTA V lore only (no invented brands), no player commands (everything
> via phone/radial/pause + permissions), EMBER design system, version locked at 0.1.0.

---

> **The committed roadmap now lives in [ARCHITECTURE.md](ARCHITECTURE.md) §5** - vehicles
> (persistence, keys, garages, dealerships, rentals), factions + boss menu, gangs, police,
> licences & permits, and the full legal/illegal economy, with the build order and the reasons
> behind it. This file stays what it always was: the loose idea bin for everything *not* yet
> committed to.

## A. Inventory (`v-inventory`) - enhancements

- [x] **Weapon jam at low condition** ✅ (shipped) - worn weapons jam on firing, forcing a reload.
- [ ] **Food / perishable time-decay** - items spoil over real time (store `spoilAt` on craft/spawn);
      spoiled food heals less or turns into `spoiled_food`. Server-computed on open, never silent-deletes.
- [ ] **Tool durability** - extend the weapon wear model to lockpicks / drills / repair kits (chance to
      break per use), feeding the crafting economy.
- [ ] **Item inspection / 3D preview** - right-click → "Inspect" shows the item prop in a small viewport.
- [ ] **Split / combine stacks by keyboard** - shift-drag split exists; add a numeric split modal + "combine all".
- [ ] **Quick-use radial from the hotbar** - number keys 1–5 already; add a wheel for controllers.
- [ ] **Weight-based movement penalty** - over X% capacity slows sprint (ties into `v-status` stamina).
- [ ] **Container categories & search** - filter chips (weapons / food / materials…) + text search in big stashes.
- [ ] **Evidence / serial tracking** - weapons keep an owner-history trail on metadata for police RP.
- [ ] **Move direct-SQL `items`/`stashes` access behind `v-core`** (from the architecture audit).

## B. Crafting (`v-crafting`) - enhancements

- [ ] **In-game recipe editor** (admin) - add/edit recipes without a resource restart (DB-backed).
- [ ] **Server-side craft timer** - move the progress duration server-side to fully close the client-time gap.
- [ ] **Crafting XP / skill tree** - repeated crafts unlock faster times, bulk crafting, rare recipes (roadmap #9).
- [ ] **Blueprints as items** - a recipe is locked until the player owns/learns its blueprint.
- [ ] **Batch queue** - queue several crafts instead of one at a time.
- [x] **Salvage / dismantle + refine** ✅ (shipped) - Recycling Center station breaks items into materials
      (net loss) and refines raw stock. *Next:* let a recycle row title show the INPUT item (currently shows
      the output), and multi-material yields (needs a NUI tweak to the craft row).
- [ ] **Job-gated benches** - mechanic/medic/police stations with restricted recipes (uses the existing `gate`).

## C. Weapons - enhancements

- [ ] **Addon-weapon component map** - fill `data/attachments.lua` for ak74 / ar15 / m4a4 / .38 once their
      component hashes are known (they currently return "doesn't fit").
- [ ] **Weapon-on-back / holster props** - visible slung rifle / holstered pistol while not drawn.
- [ ] **Tints & skins as attachments** - weapon tint index stored on metadata, applied on draw.
- [ ] **Ammo types** - AP vs ball already exist as items; make them actually swap the loaded round.

---

## D. Complementary NEW modules (pair well with inventory/crafting)

- [~] **`v-jobs`** ✅ (foundation shipped) - jobs/grades/duty/salaries + `setjob` admin command + exports;
      job gates across shops/stashes/benches now enforce. *Next:* in-game job manager/boss UI, job center to
      pick a job, duty toggle UI, and wire the **police** job into the frisk `police` gate (replaces the admin stub).
- [x] **`v-shops` selling + hardening** ✅ (shipped) - Buy/Sell toggle, scrap dealer buys raw materials,
      server-authoritative proximity + job-lock enforced. *Next:* in-game stock/price editor, dynamic
      market pricing (supply/demand), restock consuming crafted goods → fully player-driven economy.
- [~] **`v-drugs`** (high, mostly shipped) - ✅ grow cannabis + ✅ process at a hidden Drug Lab + ✅ street
      selling for dirty money + ✅ money laundering (65% rate). *Next:* police heat/risk on sale & laundering,
      weed-plant growth timers, drug-use screen effects (v-status), more meth precursors, addiction.
- [x] **`v-gathering` / resource jobs** ✅ (shipped) - mining / salvage / textile nodes produce raw
      materials (`iron`, `copper`, `cloth`…) crafting consumes. Closes the loop: gather → craft → sell.
      *Next:* tool-gated gathering (pickaxe/durability), gathering XP, more node types (wood, oil, chemicals
      for `gunpowder`), processing stations (ore → ingot).
- [ ] **`v-phone`** (high) - iFruit NUI: primary interaction surface (marketplace to sell crafted items,
      messages, bank, job apps). Gameplay never happens through chat (see `v-chat` in ARCHITECTURE §5.5: local, OOC and
      emotes only), so the phone is a keystone.
- [ ] **`v-radial`** (high) - context radial menu (the other main interaction surface): frisk, give,
      craft-here, vehicle actions - replaces the temporary keybinds (H/X/etc.).
- [x] **Vending machines** ✅ (shipped as v-shops locations, no-ped/no-blip). *Next:* garbage job &
      other recurring-income jobs; dynamic detection of vending props map-wide instead of fixed coords.
- [ ] **`v-storage-rental`** (medium) - rentable warehouses/lockers using the shared-stash engine already built.
- [ ] **`v-blackmarket`** (medium) - illegal buyer for stolen/crafted contraband; ties frisk-stealing to an outlet.
- [ ] **`v-repair` / mechanic** (medium) - vehicle repair consuming `repair_kit`/`tire`/`car_battery` items.
- [ ] **`v-anticheat`** (medium) - server-side sanity checks (money/health/explosion guards), logged.

---

## E. Cross-cutting polish

- [~] **Central `v-target` interaction** ✅ (shipped) - permission/job-aware eye with a full registration API;
      built-ins: vehicle trunk/glovebox, player frisk, admin repair, police search. *Next:* migrate the
      per-resource "press E" prompts (shops, benches, gathering nodes, stashes) onto v-target zones; add
      cursor-hover selection + entity outline/highlight; item-gated options (needs a client item mirror).
- [ ] **Unified notifications** - make sure every module routes through `v-notify` for a consistent look.
- [ ] **Sound design pass** - shared SFX helper (open/close/craft/jam) for a cohesive audio identity.
- [ ] **Localization sweep** - verify fr/en parity across all modules; consider a third language toggle.
- [ ] **Persistence audit** - confirm every metadata-bearing item (weapons, attachments, durability) round-trips
      through save/load and character switch without loss.

---

*Last updated: 2026-07-11. Add freely; keep it lore-safe and permission-driven.*
