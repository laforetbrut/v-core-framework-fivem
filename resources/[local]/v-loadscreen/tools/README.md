# tools

The two scripts that produced the backgrounds and the music shipped in
`assets/`. Nothing here is loaded by the game; the resource runs without this
folder. They are kept so the assets can be changed rather than only replaced.

Both need Python with `numpy` and `Pillow`, plus `ffmpeg` on the PATH.

```bash
pip install numpy pillow
```

## Backgrounds

```bash
python tools/gen_backgrounds.py preview  out/     # one PNG per scene, to look at
python tools/gen_backgrounds.py render   assets/backgrounds/
```

Three scenes are defined: `Synthwave` (the Vice City horizon, with the palms),
`Aurora` and `Nebula`. Each renders a twelve second loop that is seamless by
construction: everything is a periodic function of the loop phase, so the last
frame flows back into the first.

Editing:

- **Palette** — the `ramp()` calls hold the colour stops. `Synthwave.__init__`
  has the sky, `sun_col` in `frame()` has the sun.
- **Resolution** — `RW, RH` is what gets painted, `OUT_W, OUT_H` is what gets
  encoded. The shipped files are painted at 1920x1080 and encoded at 2560x1440.
  Raising `OUT_W, OUT_H` to `3840, 2160` gives a 4K file, at roughly twice the
  decode cost on the player's machine for content this smooth.
- **Length** — `DURATION`, in seconds.
- **Palms** — the `trees` list in `palm_layer()`: x position, base y, height,
  lean, frond count, scale.

Quality is set by `-crf` in `render()`. Lower is better and bigger; 30 is the
shipped value.

## Music

```bash
python tools/gen_music.py assets/music/                    # all six tracks
python tools/gen_music.py assets/music/ ocean-drive        # just one
```

Every track is synthesised from oscillators and filtered noise. There are no
samples and no borrowed melody, so nothing here carries a third party licence.

Each entry in `PRESETS` is one track:

- `prog` — the chord loop, as `(bass note, [pad notes])` in MIDI numbers. 60 is
  middle C. Four chords, one per bar.
- `bpm`, `cycles` — tempo, and how many times the four bar loop repeats. Length
  is `cycles * 4 * 4 beats`.
- `harmonics`, `tilt` — pad brightness. More harmonics and a lower tilt give a
  brighter, reedier pad; fewer and higher give a soft round one.
- `pad`, `arp`, `bass` — the mix.
- `rest` — how often the arpeggio skips a sixteenth. Higher is sparser.
- `reverb` — wet amount.
- `seed` — fixes the detuning and noise, so a rerun gives the same track.

Adding a preset here and a line in `config.js` under `music.tracks` is all it
takes to add a track.

---

# tools (Version Française)

Les deux scripts qui ont produit les fonds et la musique livrés dans `assets/`.
Rien ici n'est chargé par le jeu ; la ressource tourne sans ce dossier. Ils sont
conservés pour que les assets puissent être modifiés et pas seulement remplacés.

Les deux demandent Python avec `numpy` et `Pillow`, plus `ffmpeg` dans le PATH.

```bash
pip install numpy pillow
```

## Fonds

```bash
python tools/gen_backgrounds.py preview  out/     # un PNG par scène, pour voir
python tools/gen_backgrounds.py render   assets/backgrounds/
```

Trois scènes sont définies : `Synthwave` (l'horizon Vice City, avec les
palmiers), `Aurora` et `Nebula`. Chacune rend une boucle de douze secondes sans
raccord par construction : tout est fonction périodique de la phase, donc la
dernière image enchaîne sur la première.

Ce qui se modifie :

- **Palette** — les appels à `ramp()` contiennent les points de couleur.
  `Synthwave.__init__` tient le ciel, `sun_col` dans `frame()` tient le soleil.
- **Résolution** — `RW, RH` est ce qui est peint, `OUT_W, OUT_H` ce qui est
  encodé. Les fichiers livrés sont peints en 1920x1080 et encodés en 2560x1440.
  Passer `OUT_W, OUT_H` à `3840, 2160` donne un fichier 4K, pour environ deux
  fois plus de décodage sur la machine du joueur sur un contenu aussi lisse.
- **Durée** — `DURATION`, en secondes.
- **Palmiers** — la liste `trees` dans `palm_layer()` : position x, base y,
  hauteur, inclinaison, nombre de palmes, échelle.

La qualité se règle par `-crf` dans `render()`. Plus bas veut dire meilleur et
plus lourd ; 30 est la valeur livrée.

## Musique

```bash
python tools/gen_music.py assets/music/                    # les six pistes
python tools/gen_music.py assets/music/ ocean-drive        # une seule
```

Chaque piste est synthétisée à partir d'oscillateurs et de bruit filtré. Aucun
sample, aucune mélodie empruntée : rien ici ne porte de licence tierce.

Chaque entrée de `PRESETS` est une piste :

- `prog` — la boucle d'accords, en `(basse, [notes de nappe])` en numéros MIDI.
  60 est le do central. Quatre accords, un par mesure.
- `bpm`, `cycles` — tempo, et nombre de répétitions de la boucle de quatre
  mesures. La durée vaut `cycles * 4 * 4 temps`.
- `harmonics`, `tilt` — brillance de la nappe. Beaucoup d'harmoniques et un
  `tilt` bas donnent une nappe claire et mordante ; peu et haut donnent une
  nappe ronde et douce.
- `pad`, `arp`, `bass` — le mixage.
- `rest` — fréquence à laquelle l'arpège saute une double croche. Plus haut,
  plus aéré.
- `reverb` — quantité de réverbération.
- `seed` — fige le désaccordage et le bruit, donc un nouveau rendu redonne la
  même piste.

Ajouter un preset ici et une ligne dans `config.js` sous `music.tracks` suffit à
ajouter un morceau.
