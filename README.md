# BoundingBox

[BoundingBox](https://github.com/M0diis/RS3-BoundingBox) is a RuneScape 3 plugin
for configurable entity bounding boxes and object tile footprints.
Uses [PrettyUI](https://github.com/PrettyRS/prettyui) as an external dependency
(mod.io ID **6398181**).

## Features

- Independent toggles and RGBA colour/opacity pickers for NPCs, objects,
  ground-item stacks, other players, and your character.
- Adjustable line width (1–10) and draw distance (1–64 tiles).
- Case-insensitive name filtering and NPC/object config ID exclusions.
- Saved settings, available through the Plugin Hub settings cog and Plugins ribbon.
- Depth-tested outlines, same-floor filtering, and hidden/removed-roof object checks.

NPCs, players, and ground-item stacks use API axis-aligned bounding boxes, not
exact model silhouettes, mouse-picking meshes, or attack ranges. Objects use their
rotated tile footprints. Static scenery merged into combined geometry is not
fully exposed by `LocList`. Ground-item filters match any item in the stack.

Object candidates refresh about every 200 ms. Drawing is capped at 300 outlines
per frame, with the nearest object footprints drawn first. Reduce the distance
or narrow the name filter in dense scenes.

## Installation

1. Install and enable PrettyUI in the RuneScape developer client. Developer
   plugins may need dependencies downloaded manually. Integration uses the
   `SimpleView`, checkbox, colour picker, text field, and slider APIs from
   PrettyUI 1.2.1.
2. Extract the plugin ZIP into `dev_plugins/boundingbox` under the client cache
   directory. On a standard Windows beta install:
   `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\boundingbox`.
3. Confirm this layout; placing an unopened ZIP in the folder will not work:

   ```text
   boundingbox/
     main.lua
     plugin.json
     src/
       renderer.lua
       settings.lua
       settings_ui.lua
   ```

4. In a developer world, open the console with Alt + the key below Escape:

   ```text
   plugins_refresh
   plugins_enable boundingbox
   ```

Open **BoundingBox** in the Plugins ribbon or Plugin Hub settings. To reload:

```text
plugins_reload boundingbox
```

To use a local PrettyUI checkout, place it under `dev_plugins/prettyui` and change
the manifest dependency to `"prettyui": "prettyui"` during development.

## Development

The repository root is the plugin root. Copy `main.lua`, `plugin.json`, and `src/`
into the developer plugin folder after changes.

Run offline Lua checks using Python and Lua 5.4 through Lupa:

```powershell
python -m pip install --target .tools/python lupa
python tests/run.py
```

These checks cover settings validation/persistence, geometry, filters, UI callback
contracts, resize behavior, and subscription cleanup with API mocks. Verify
rendering, animations, slopes, interface scaling, and colours in the game client.

Build an installable archive with PowerShell 7:

```powershell
./scripts/package.ps1
```

The output is `dist/boundingbox.zip`. An optional `-ContactEmail` overrides the
support address in the packaged manifest. The archive includes the license.

## License and dependencies

Licensed under [GNU GPLv3](LICENSE), as provided by this repository's existing
license. PrettyUI is a separate dependency and is not bundled or reimplemented.
No QuestHelper source is included.

Source and issues: [M0diis/RS3-BoundingBox](https://github.com/M0diis/RS3-BoundingBox).

## API references

- [RuneScape Client API](https://developer.runescape.com/rs/)
- [Shapes](https://developer.runescape.com/rs/game/shapes.html)
- [Plugin structure](https://developer.runescape.com/rs/structure.html)
- [PrettyUI](https://prettyui.j3.gg/)

This project has not been submitted to or approved by Jagex. Distribution through
the live Plugin Hub requires their submission and moderation process.
