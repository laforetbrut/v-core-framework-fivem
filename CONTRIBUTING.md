# Contributing to v-core

Thanks for looking. This document is short on purpose — the details live in
**[DEVELOPERS.md](DEVELOPERS.md)**, which is the file to read before writing any code.

## Before you open a PR

**Read [DEVELOPERS.md](DEVELOPERS.md).** It carries the conventions and, more usefully, a
list of gotchas this framework has actually shipped and had to fix — Lua scoping,
`v_module 'yes'` normalising to `1`, `cond and nil or x` always returning `x`,
`INSERT IGNORE` on `AUTO_INCREMENT` tables. Most first PRs hit at least one of them.

**Load the helper.** One manifest line — `shared_script '@v-core/lib/v.lua'` — gives you
`V.Ready`, `V.Module`, `V.Setting`, `V.Use`, `V.Callback` and `V.Notify`. If you find
yourself writing `Wait(2500)` to let v-core start, or a `pcall` around another module's
export, the helper already solves it.

**Run the audits.** A Lua syntax check is not enough. The two that matter:

- every `exports['x']:Y()` call resolved against what `x` actually defines, **on the
  matching side** — this is the class of bug that only appears at runtime, on the one
  code path nobody walked;
- every `TriggerServerEvent` / `TriggerClientEvent` / `TriggerCallback` matched to a
  handler — a dangling callback is a UI that hangs forever with no console error.

**Boot the server.** If your change touches a resource, start it and confirm the module
count and a clean log before opening the PR. "It parses" is not "it runs".

## What gets merged quickly

- A fix with a one-line explanation of the **failure**, not just the change.
- A new module that declares itself with `V.Module` and appears in the admin panel.
- A setting that real code reads.

## What gets sent back

- **A setting nothing reads.** It is worse than no setting: it lies to the operator, who
  changes it, sees nothing happen, and reports the module as broken.
- **A cached setting.** Read it where you use it. A module that caches at boot makes its
  own settings inert until the next restart.
- **Client-trusted state.** Money, items, positions and permissions are validated
  server-side even when the client already checked. A client payload is a request.
- **Hardcoded colours in NUI.** Use the v-ui theme tokens or your page will be the one
  that does not change when the operator picks a different palette.
- **Player-facing text inline.** It belongs in `locales/en.lua` and `locales/fr.lua`.
- **A chat command for players.** Interaction goes through the phone, the radial menu,
  the pause menu or a keybind. Admin commands are fine.

## Commit messages

`type: what changed and why it was wrong`

```
fix(garages): Config.StoreMaxDamage was read nowhere, so a wreck could be
parked and taken back out repaired
```

The *why* is the part that is worth writing. `fix: bug` tells a future maintainer
nothing.

## Reporting a bug

Include the server log around the failure, the resource, and what you expected. If it is
a NUI issue, the browser console from `F8` → `nui_devtools` is usually decisive.

---

# Contribuer à v-core (version française)

Merci de votre intérêt. Ce document est volontairement court — l'essentiel est dans
**[DEVELOPERS.md](DEVELOPERS.md)**, à lire avant d'écrire la moindre ligne.

## Avant d'ouvrir une PR

**Lisez [DEVELOPERS.md](DEVELOPERS.md)** — il contient les conventions et surtout la liste
des pièges que ce framework a réellement rencontrés en production. La plupart des
premières PR en touchent au moins un.

**Chargez le helper** : `shared_script '@v-core/lib/v.lua'`. Si vous écrivez un
`Wait(2500)` en attendant que v-core démarre, ou un `pcall` autour de l'export d'un autre
module, le helper le fait déjà.

**Lancez les audits** — la vérification de syntaxe Lua ne suffit pas. Les appels
inter-modules doivent être résolus **du bon côté**, et chaque callback doit avoir un
handler : un callback orphelin, c'est une interface qui tourne indéfiniment sans aucune
erreur en console.

**Démarrez le serveur.** « Ça compile » n'est pas « ça tourne ».

## Ce qui est refusé

- **Un réglage que personne ne lit** — pire que pas de réglage : il ment à l'admin.
- **Un réglage mis en cache au démarrage** — il devient inerte jusqu'au prochain reboot.
- **Un état auquel on fait confiance côté client** — argent, objets, positions et
  permissions sont revalidés côté serveur.
- **Des couleurs en dur dans le NUI** — utilisez les tokens de thème v-ui.
- **Du texte joueur en dur** — il va dans `locales/`.
- **Une commande chat pour les joueurs** — téléphone, menu radial, menu pause ou raccourci.

## Messages de commit

`type: ce qui change et pourquoi c'était faux`. Le *pourquoi* est la partie qui compte.

## Credits

Author: vyrriox
