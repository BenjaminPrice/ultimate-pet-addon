# UltimatePet

A Hunter pet build planner and progression tracker for **WoW: Forever** (client 1.60.x,
`## Interface: 16001`).

UltimatePet combines a training point (TP) calculator, preset builds for every pet family, live
tracking of the ranks your Hunter has unlocked in Beast Training, and waypoints (TomTom or the
built-in map pin) to the tameable beasts that teach ranks you are missing.

> **Status: first playable build.** Planner window, Beast Training and pet scanning, presets for
> all 19 families, build strings, waypoints and a minimap button are in. Not yet checked in game;
> report problems with the output of `/upet debug`.

## Using it

1. Open your Beast Training window once (the spellbook icon). UltimatePet reads which ranks you
   know. Do it again after learning new ranks.
2. Type `/upet` or click the minimap button to open the planner.
3. Pick a family and a preset, or tick **Use current pet** to plan for the pet you have out.
4. Each chosen rank shows its status: Trained, Ready to Train, Unlocked (with what's missing),
   Not Unlocked, Trainer (bought from a pet trainer) or No known source.
5. Click a **Not Unlocked** rank to list beasts that teach it, then **Waypoint** to mark one.
6. Save builds, set one active for your current pet, or share them with Export and Import.
7. The Pet tab of the character sheet (C) shows a panel with your pet's TP, its active build and
   the ranks it knows against that build. `/upet pet` opens the same panel on its own.

## Install

The repository root is the addon folder. Clone it anywhere and symlink it into your AddOns
directory as `UltimatePet`:

```sh
git clone <repo-url> ~/dev/wow/ultimate-pet
ln -s ~/dev/wow/ultimate-pet "<WoW Forever folder>/Interface/AddOns/UltimatePet"
```

On Windows, use `mklink /D "<WoW folder>\Interface\AddOns\UltimatePet" C:\path\to\ultimate-pet`.

TomTom is optional. If it is installed, waypoints go through it; otherwise the built-in map pin is used.

The minimap button uses LibDataBroker and LibDBIcon (embedded in `Libs/`), so minimap button
collectors such as EllesmereUI's minimap module and broker bars such as Titan Panel pick it up.

## Slash commands

`/ultimatepet` or `/upet`, followed by:

| Command | What it does |
|---|---|
| (none) or `show` | Open or close the planner window |
| `scan` | Read the active pet again and print its family, level and TP |
| `pet` | Show or hide the current pet panel as a separate window |
| `minimap` | Show or hide the minimap button |
| `debug` | Print the client build, which game APIs exist, the pet and scanner state (paste it into bug reports) |
| `export` | Print the current build as a shareable string |
| `import <string>` | Load a build string |
| `reset confirm` | Wipe this character's saved data (`reset` alone only explains) |
| `reset all confirm` | Wipe all characters' data and global settings |
| `help` | List the commands (also shown for a bare `/upet`) |

Saved data lives in the `UltimatePetDB` SavedVariable: global settings plus one entry per
character (`Name-Realm`), since Beast Training unlocks are per character.

## Development

Requirements: Lua 5.1, [luacheck](https://github.com/lunarmodules/luacheck) and
[busted](https://lunarmodules.github.io/busted/). Run everything from the repository root:

```sh
luacheck .            # lint (config in .luacheckrc)
busted                # unit tests in tests/*_spec.lua (config in .busted)
lua tests/smoke.lua   # loads every TOC file through the WoW stub and runs a few slash commands
```

With luarocks: `luarocks install --local luacheck` and `luarocks install --local busted`.
On Nix, run them without installing anything:

```sh
nix shell nixpkgs#lua51Packages.busted nixpkgs#lua51Packages.luacheck -c sh -c 'luacheck . && busted'
```

`tests/wowstub.lua` is a minimal fake of the WoW API. It reads `UltimatePet.toc` and runs each
listed file with `(addonName, namespace)`, as the game client does, and lets tests fire events and
slash commands. CI (`.github/workflows/ci.yml`) runs lint, tests and the smoke test on every push.

`Data/Families.lua`, `Data/Skills.lua` and `Data/Beasts.lua` are generated; don't edit them by hand.
To regenerate (Python 3, standard library only):

```sh
python3 -I tools/gen_data.py --petopia <abilities-YYYY-MM-DD.html> --wowhead <dir>
```

TrueshotLodge's data files are vendored in `tools/sources/trueshotlodge/` (MIT, upstream commit in
`COMMIT`); pass `--tl <checkout>` to use a newer copy. The Petopia and Wowhead page snapshots are
kept locally, not in the repo.

It rewrites the three files and `tools/DATA_NOTES.md`, which lists every source conflict, unknown
TP cost and beast without coordinates.

For in-game testing, enable Lua errors with `/console scriptErrors 1`, then run `/upet debug`.

## Credits and data sources

- [TrueshotLodge](https://github.com/chazlander/TrueshotLodge), [PetStable](https://github.com/Spotnick2/PetStable) and
  [Huntsworn](https://github.com/Langmans/Huntsworn) (all MIT licensed): ability, spell ID and
  beast location data, and reference API usage for the Forever client.
- [Petopia Forever](https://www.wow-petopia.com/forever/) and [Wowhead](https://www.wowhead.com/):
  used for facts only (names, numbers, IDs). No prose or other content is copied.

## License

MIT. See [LICENSE](LICENSE).
