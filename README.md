# Jat'z Distribution

**Automated freight trucks, depots and roads for Factorio.**

Jat'z Distribution is a depot-based logistics system for Factorio. Place provider depots where goods are made, request depots where they are needed, connect them with road, and armored freighters will carry the cargo between them. Buffer depots hold stock in transit, fuel depots keep the fleet running, and liquid depots handle fluids.

The gameplay is inspired by Klonan's [Transport Drones](https://mods.factorio.com/mod/Transport_Drones), with heavy freight trucks in place of drones. The rugged industrial look draws on the Yuoki mod family.

> **Status: in development.** Everything can be crafted for free. Freighters already deliver items from provider to request depots over road. Buffer, fuel and liquid depots can be placed, but don't take part in deliveries yet. The mod is not yet available on the Factorio Mod Portal.

![The Quinityn freighter parked beside Provider, Request, Buffer and Fuel depots in Factorio](docs/images/depots-with-freighter.jpg)

## Features

- **Quinityn sealed freighter:** an armored eight-wheel cargo truck with 64 rotation directions.
- **Road-bound deliveries:** set an item and amount on a request depot, and a freighter fetches it from the nearest provider depot that has it. Freighters drive only on road tiles, so roads decide where they go.
- **Seven freight depots:** dry cargo and fluid stations on a 3×3 footprint, each with four rotations. A worn "no parking: loading zone" marking on the ground shows where freighters load; placed unrotated, it's always on the south side.
- **Full recoloring:** every vehicle and building has three independently tintable paint layers. Wear, metal and glass keep their detail in any color.
- **Native fluid connections:** depot ports line up with vanilla pipes and turn with the building.
- **Hand-built artwork:** every building and vehicle sprite is rendered from an editable Blender model, with matching ground shadows.

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

## Roads and deliveries

Freighters drive only on **road**, a placeable floor tile in our crafting row. Lay road from a provider depot's loading zone (the marked tile) to a request depot's loading zone. Then open the request depot and choose an item and an amount to keep in stock. Within a second, a freighter sets off along the road to the nearest provider depot that has the item. It loads what the depot still needs and has room for, up to ten stacks, and drives back to unload. Items keep their data on the way: armor keeps its equipment, food how far it has spoiled. If no road route exists, the request depot shows why and tries another provider. As soon as you lay road or build or turn a depot, it tries again; otherwise it tries again after 10 seconds. Removing road re-routes freighters straight away: if the road is cut behind a loaded freighter, it takes the cargo back to the provider. If a provider is removed while a freighter is heading there, the freighter goes on to the next one.

For now, freighters appear for each delivery and need no fuel. Requests are for normal-quality items. They aren't kept in blueprints yet, but Copy and Paste settings works between request depots, and cloned depots keep theirs. Buildings can still be placed on road; freighters drive through them.

By default, provider depots are red, request depots blue, buffer depots green and the fuel depot amber. Every color can be changed.

More screenshots: [every depot in every rotation](docs/images/depots-all-rotations.jpg) · [recoloring each paint layer](docs/images/depots-paint-channels.jpg) · [depots at in-game scale](assets/depots/previews/all-depots-world-scale.png) · [freighter colors](docs/images/freighter-palettes.jpg)

## Roadmap

- [x] Quinityn freighter artwork, tested in game
- [x] Seven depot designs, tested in game with all rotations and pipe connections
- [x] Playable mod: the freighter and all depots can be crafted (free for now), placed, rotated and driven
- [x] Roads, and freighter deliveries from provider to request depots that stay on road
- [ ] Buffer and liquid depots in deliveries, requests in blueprints, a freighter fleet in place of free freighters
- [ ] Solid and liquid refueling at the Fuel depot
- [x] In-game icons for the freighter and every depot, made from the game sprites
- [ ] Freighter wheel animation and final freighter stats
- [ ] Recipes, technology and balance
- [ ] Release on the Factorio Mod Portal

## Compatibility

Built for **Factorio 2.1** (tested on 2.1.24). The mod requires only the base game and also works with Space Age.

## Trying it

The mod isn't on the Mod Portal yet, so build it from this repository (Python 3.13, no other dependencies):

```sh
python3 tools/package_mod.py
```

Copy the resulting `dist/jatz-distribution_0.1.0.zip` into your [Factorio mods folder](https://wiki.factorio.com/Application_directory#User_data_directory) and enable **Jat'z Distribution**. All items are in the Logistics tab of the crafting menu, in the row just above the car and tank, and are free to craft for now.

## Development

| Folder | Contents |
| --- | --- |
| `info.json`, `data.lua`, [`prototypes/`](prototypes/), `control.lua`, [`scripts/`](scripts/), [`locale/`](locale/) | The mod itself. The repository root is the mod's root, so it uses the sprite helpers and sheets in `assets/` directly. |
| [`assets/quinityn-freighter/`](assets/quinityn-freighter/README.md) | Freighter Blender model, game sprites, Lua helper and render tools |
| [`assets/depots/`](assets/depots/README.md) | Depot Blender models, pipe connector, game sprites, Lua helpers and render tools, plus the archived 1×1 depots |
| [`assets/roads/`](assets/roads/README.md) | The road tile art, from Yuoki Industries - Railways (CC BY-NC-SA 4.0) |
| [`concepts/`](concepts/README.md) | Approved concept art for the depots, with links to the freighter concept |
| [`tests/factorio/`](tests/factorio/) | Test mods that check the mod and the artwork in Factorio |
| [`tools/`](tools/) | Mod packager, test runners and CI tools |
| [`docs/`](docs/) | [Testing guide](docs/testing.md), [test results](docs/test-results.md) and README images |

Each asset folder's README explains its files, how to use the sprites in Factorio, and how to edit and re-render the models. Read [AGENTS.md](AGENTS.md) before changing anything; it holds the project rules for human and AI contributors.

You need Python 3.13 and Factorio 2.1; the free [headless server](https://factorio.com/download) is enough for the automated checks. Blender 4.3.2 is only needed to edit models and re-render sprites.

```sh
python3 tools/test_mod.py --factorio /path/to/factorio/bin/x64/factorio     # the mod: craft, place, rotate, drive, deliver
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python assets/quinityn-freighter/tools/validate_assets.py
python3 tools/test_factorio.py --factorio /path/to/factorio/bin/x64/factorio
python3 tools/test_depot_art.py --factorio /path/to/factorio/bin/x64/factorio
```

## Credits

- **Gameplay:** inspired by [Transport Drones](https://mods.factorio.com/mod/Transport_Drones) by Klonan.
- **Visual style:** inspired by the Yuoki Industries family of Factorio mods.
- **Road artwork:** the slag path tiles from [Yuoki Industries - Railways](https://github.com/jatmn/Yuoki-Railways-Factorio-2.0), © YuokiTani & others, used under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

Apart from the road art, the models and sprites for the mod are original work built in Blender. The concept art and design references are described in [concepts/](concepts/README.md).

## License

Jat'z Distribution is licensed under the [GNU Lesser General Public License v3.0](COPYING.LESSER). This is the same license used by Transport Drones. The LGPL builds on the [GNU GPL v3.0](COPYING), so both texts are included.

You may use, modify and redistribute the mod, including in modpacks. Any modified version you distribute must stay under the LGPL-3.0, with its source available and these notices intact.

The road artwork in `assets/roads/yuoki-railways/` is not LGPL: it keeps its CC BY-NC-SA 4.0 licence, so it can't be used commercially, and changed versions of it must be shared under the same licence. The in-game screenshots in `docs/images/` also show Factorio's own artwork, which remains Wube Software's. See [NOTICE](NOTICE) for details and attributions.
