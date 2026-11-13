# UltimatePet

A Hunter pet build planner and progression tracker for **WoW: Forever** (client 1.60.x,
`## Interface: 16001`).

UltimatePet combines a training point (TP) calculator, preset builds for every pet family, live
tracking of the ranks your Hunter has unlocked in Beast Training, and waypoints (TomTom or the
built-in map pin) to the tameable beasts that teach ranks you are missing.

> **Status: early development.** Phase 1 (scaffold, saved data, slash commands, tooling) and
> phase 2 (ability and beast data) are done. Phase 3 adds the planner logic, build strings
> (`/upet export`, `/upet import <string>`) and suggested presets for every family. The scanner and
> UI are not built yet, so `show` and `scan` say "not implemented yet".

## Install

The repository root is the addon folder. Clone it anywhere and symlink it into your AddOns
directory as `UltimatePet`:

```sh
git clone <repo-url> ~/dev/wow/ultimate-pet
ln -s ~/dev/wow/ultimate-pet "<WoW Forever folder>/Interface/AddOns/UltimatePet"
```

On Windows, use `mklink /D "<WoW folder>\Interface\AddOns\UltimatePet" C:\path\to\ultimate-pet`.

TomTom is optional. If it is installed, waypoints go through it.

## Slash commands

`/ultimatepet` or `/upet`, followed by:

| Command | What it does |
|---|---|
| `show` | Open the planner window *(not implemented yet)* |
| `scan` | Rescan the active pet *(not implemented yet)* |
| `debug` | Print the client build and which game APIs this client provides (paste it into bug reports) |
| `export` | Print the current build as a shareable string *(not implemented yet)* |
| `import <string>` | Load a build string *(not implemented yet)* |
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
