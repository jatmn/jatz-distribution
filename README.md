# Jat'z Distribution

**Automated freight trucks and depots for Factorio.**

Jat'z Distribution is a depot-based logistics system for Factorio. Place provider depots where goods are made, request depots where they are needed, and armored freighters will carry the cargo between them. Buffer depots hold stock in transit, fuel depots keep the fleet running, and liquid depots handle fluids.

The gameplay is inspired by Klonan's [Transport Drones](https://mods.factorio.com/mod/Transport_Drones), with heavy freight trucks in place of drones. The rugged industrial look draws on the Yuoki mod family.

> **Status: in development.** All of the artwork is finished and tested in the game. Freight dispatch and cargo transfer are being built next. The mod is not yet available on the Factorio Mod Portal.

![The Quinityn freighter parked beside Provider, Request, Buffer and Fuel depots in Factorio](docs/images/depots-with-freighter.jpg)

## Features

- **Quinityn sealed freighter:** an armored eight-wheel cargo truck with 64 rotation directions.
- **Seven freight depots:** dry cargo and fluid stations on a 3×3 footprint, each with four rotations.
- **Full recoloring:** every vehicle and building has three independently tintable paint layers. Wear, metal and glass keep their detail in any color.
- **Native fluid connections:** depot ports line up with vanilla pipes and turn with the building.
- **Hand-built 3D artwork:** every sprite is rendered from an editable Blender model, with matching ground shadows.

## The Quinityn freighter

![Quinityn sealed freighter](assets/quinityn-freighter/masters/hero-default-palette.png)

The Quinityn is a sealed freight hauler with an armored cab, three clamped cargo bays and an exposed power unit with a circular cooling fan. Chipped coatings, oxide, handling scuffs and smoky armored glass give it a used, industrial look. The cab, clamps and cargo panels each take their own color.

## Depots

Every depot sits on a 3×3 footprint and can be placed facing north, east, south or west. Fluid depots connect to standard Factorio pipes. Their ports turn with the building.

| Depot | Purpose | North · East · South · West |
| --- | --- | --- |
| **Provider** | Sends dry cargo out to freighters | ![Provider depot in four rotations](assets/depots/provider/3/previews/four-directions.png) |
| **Request** | Receives dry cargo from freighters | ![Request depot in four rotations](assets/depots/request/3/previews/four-directions.png) |
| **Buffer** | Holds cargo in transit, with two loading lanes | ![Buffer depot in four rotations](assets/depots/buffer/3/previews/four-directions.png) |
| **Fuel** | Refuels freighters with solid or liquid fuel | ![Fuel depot in four rotations](assets/depots/fuel/3/previews/four-directions.png) |
| **Liquid Provider** | Sends fluids out to freighters | ![Liquid Provider depot in four rotations](assets/depots/liquid-provider/3/previews/four-directions.png) |
| **Liquid Request** | Receives fluids from freighters | ![Liquid Request depot in four rotations](assets/depots/liquid-request/3/previews/four-directions.png) |
| **Liquid Buffer** | Stores fluids between deliveries, with two pipe connections | ![Liquid Buffer depot in four rotations](assets/depots/liquid-buffer/3/previews/four-directions.png) |

By default, provider depots are red, request depots blue, buffer depots green and the fuel depot amber. Every color can be changed.

More screenshots: [every depot in every rotation](docs/images/depots-all-rotations.jpg) · [recoloring each paint layer](docs/images/depots-paint-channels.jpg) · [depots at in-game scale](assets/depots/previews/all-depots-world-scale.png) · [freighter colors](docs/images/freighter-palettes.jpg)

## Roadmap

- [x] Quinityn freighter artwork, tested in game
- [x] Seven depot designs, tested in game with all rotations and pipe connections
- [ ] Freighter dispatch between depots
- [ ] Cargo and fluid loading and unloading
- [ ] Solid and liquid refueling at the Fuel depot
- [ ] Freighter wheel animation and final collision and selection sizes
- [ ] Recipes, technology and balance
- [ ] Release on the Factorio Mod Portal

## Compatibility

Built for **Factorio 2.1** (tested on 2.1.24). The mod requires only the base game.

## Development

| Folder | Contents |
| --- | --- |
| [`assets/quinityn-freighter/`](assets/quinityn-freighter/README.md) | Freighter Blender model, game sprites, Lua helper and render tools |
| [`assets/depots/`](assets/depots/README.md) | Depot Blender models, pipe connector, game sprites, Lua helpers and render tools, plus the archived 1×1 depots |
| [`concepts/`](concepts/README.md) | Approved concept art for the depots, with links to the freighter concept |
| [`tests/factorio/`](tests/factorio/) | Test mods that load the artwork in Factorio |
| [`tools/`](tools/) | Test runners |
| [`docs/`](docs/) | [Testing guide](docs/testing.md), [test results](docs/test-results.md) and README images |

Each asset folder's README explains its files, how to use the sprites in Factorio, and how to edit and re-render the models. Read [AGENTS.md](AGENTS.md) before changing anything; it holds the project rules for human and AI contributors.

You need Python 3.13 and a full Factorio 2.1 install. Blender 4.3.2 is only needed to edit models and re-render sprites.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python assets/quinityn-freighter/tools/validate_assets.py
python3 tools/test_factorio.py --factorio /path/to/factorio/bin/x64/factorio
python3 tools/test_depot_art.py --factorio /path/to/factorio/bin/x64/factorio
```

## Credits

- **Gameplay:** inspired by [Transport Drones](https://mods.factorio.com/mod/Transport_Drones) by Klonan.
- **Visual style:** inspired by the Yuoki Industries family of Factorio mods.

The models and sprites for the mod are original work built in Blender. The concept art and design references are described in [concepts/](concepts/README.md).

## License

Jat'z Distribution is licensed under the [GNU Lesser General Public License v3.0](COPYING.LESSER). This is the same license used by Transport Drones. The LGPL builds on the [GNU GPL v3.0](COPYING), so both texts are included.

You may use, modify and redistribute the mod, including in modpacks. Any modified version you distribute must stay under the LGPL-3.0, with its source available and these notices intact.

The in-game screenshots in `docs/images/` also show Factorio's own artwork, which remains Wube Software's. See [NOTICE](NOTICE) for details and attributions.
