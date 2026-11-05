# Jat'z Distribution

**Automated freight trucks, depots and roads for Factorio.**

Jat'z Distribution is a depot-based logistics system for Factorio. Place provider depots where goods are made, request depots where they are needed, connect them with road, and armored freighters will carry the cargo between them. Buffer depots keep stock near where it is needed, fuel depots keep the fleet running, and liquid depots handle fluids.

The gameplay is inspired by Klonan's [Transport Drones](https://mods.factorio.com/mod/Transport_Drones), with heavy freight trucks in place of drones. The rugged industrial look draws on the Yuoki mod family.

> **Status: in development.** Everything can be crafted for free. Freighters already deliver items from provider and buffer depots to request depots over road, and fluids between the liquid depots. The fuel depot can be placed, but doesn't take part yet. The mod is not yet available on the Factorio Mod Portal.

![The Quinityn freighter parked beside Provider, Request, Buffer and Fuel depots in Factorio](docs/images/depots-with-freighter.jpg)

## Features

- **Quinityn sealed freighter:** an armored eight-wheel cargo truck with 64 rotation directions.
- **Road-bound deliveries:** set an item and amount on a request depot, and a freighter fetches it from the provider depot that has it and is nearest by road. Freighters drive only on road tiles, so roads decide where they go.
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
| **Buffer** | Keeps a stock of an item, fetched from providers; request depots can take from it | ![Buffer depot in four rotations](assets/depots/buffer/3/previews/four-directions.png) |
| **Fuel** | Refuels freighters with solid or liquid fuel | ![Fuel depot in four rotations](assets/depots/fuel/3/previews/four-directions.png) |
| **Liquid Provider** | Supplies fluids to liquid request and liquid buffer depots | ![Liquid Provider depot in four rotations](assets/depots/liquid-provider/3/previews/four-directions.png) |
| **Liquid Request** | Keeps a fluid in stock, fetched by its freighters | ![Liquid Request depot in four rotations](assets/depots/liquid-request/3/previews/four-directions.png) |
| **Liquid Buffer** | Keeps a stock of a fluid, fetched from liquid providers; liquid request depots can take from it. Two pipe connections | ![Liquid Buffer depot in four rotations](assets/depots/liquid-buffer/3/previews/four-directions.png) |

## Roads and deliveries

Freighters drive only on **road**, a placeable floor tile in our crafting row. Every depot lays a road tile under its loading zone sign (the marked tile) when you build it, so you only need to bring road up to it: road that ends one tile away connects. Removing the depot takes that tile away again and puts back the ground that was there, unless you laid your own road or tile over it. Lay road between a provider depot's loading zone and a request depot's. Then open the request depot, choose an item and an amount to keep in stock, and put freighters in its freighter slot (up to 100; freighters dropped into the depot's chest move there too). The line beside the slot shows how many freighters are out, and a green "+N" while N more are on their way to the depot. Ctrl+click freighters in your inventory while the depot is open (or ctrl+click the depot) to fill the slot; any that don't fit stay with you. Other items ctrl+clicked in go into the depot's inventory as usual. In remote view, or with no freighters on you, click the slot with a freighter ghost in your cursor and construction robots bring them (right-click: one more; an empty-cursor click in remote view cancels). In remote view, right-click the slot to have robots take its freighters away (right-click again to cancel). Pipette (Q) over the slot picks up a freighter, or its ghost. Within a second, a freighter sets off along the road to the provider depot that has the item and is nearest **by road**: a provider just across a wall of concrete loses to one farther away with a shorter road. It stops for about a second to load what the depot still needs and has room for, up to ten stacks, then drives back, stops again to unload, and parks in the slot again. If one freighter isn't enough, or one provider doesn't have it all, the depot sends more, one a second, each to the next provider nearest by road that still has some. Mining a request depot gives you back all its freighters, including those out on deliveries. Items keep their data on the way: armor keeps its equipment, food how far it has spoiled. If no road route exists, no freighter is sent; the request depot shows why and tries another provider. A status light beside the request shows at a glance whether it can be filled: green (stocked, or on its way), yellow (the item is out there but something is in the way: no road route, no freighters, no room), red (no provider has it) or grey (nothing requested); hover it for the details. As soon as you lay road or build or turn a depot, it tries again; otherwise it tries again after 10 seconds. Removing road re-routes freighters straight away: if the road is cut behind a loaded freighter, it takes the cargo back to the provider. If a provider is removed while a freighter is heading there, the freighter goes on to the next one.

Freighters need no fuel yet, and a freighter destroyed on the road is lost. **Buffer depots** work like request depots, with their own request and freighters, but fetch only from provider depots and send nothing anywhere. A request depot with **Request from buffer depots** ticked (like a requester chest's "request from buffer chests") takes from buffer depots first, even when a provider is nearer, and from providers only for what no buffer can supply. Provider and buffer depots have a **priority** slider from 1 to 10 (5 to start with) in the panel beside their window: freighters go to the highest priority depot they can reach by road, even when a lower one is nearer, and to the nearest among equals. Priority only orders depots of the same kind: a buffer at 1 still comes before a provider at 10. Copy and Paste settings, blueprints and clones keep it.

**Liquid depots** work the same way for fluids: a liquid request depot keeps a fluid in its tank, sending its freighters to liquid provider depots (and liquid buffer depots, if ticked), 500 at a time; liquid buffer depots fill from liquid providers only; liquid provider and buffer depots have the same priority slider. Fluids keep their temperature on the way. Items and fluids never mix: item depots only deal with item depots, liquid depots with liquid depots. A liquid depot's tank holding another fluid waits until it is emptied. Construction robots can bring a liquid depot's freighters too (from remote view, copy and paste, or blueprints). Requests are for normal-quality items. Copy and Paste settings, copy and paste, and blueprints carry a request depot's request and its number of freighters: the new depot asks for the freighters (as a ghost request), and construction robots, or you by hand, bring them. Cloned depots keep their request. Buildings can still be placed on road; freighters drive through them.

By default, provider depots are red, request depots blue, buffer depots green and the fuel depot amber. Every color can be changed.

More screenshots: [every depot in every rotation](docs/images/depots-all-rotations.jpg) · [recoloring each paint layer](docs/images/depots-paint-channels.jpg) · [depots at in-game scale](assets/depots/previews/all-depots-world-scale.png) · [freighter colors](docs/images/freighter-palettes.jpg)

## Roadmap

- [x] Quinityn freighter artwork, tested in game
- [x] Seven depot designs, tested in game with all rotations and pipe connections
- [x] Playable mod: the freighter and all depots can be crafted (free for now), placed, rotated and driven
- [x] Roads, and freighter deliveries from provider to request depots that stay on road
- [x] Buffer depots, and request depots that request from them first
- [x] Priority (1 to 10) for provider and buffer depots
- [x] Liquid depots in deliveries: liquid provider, request and buffer depots, with priority
- [ ] Fuel for freighters
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

Each asset folder's README explains its files, how to use the sprites in Factorio, and how to edit and re-render the models. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and read [AGENTS.md](AGENTS.md) before changing anything; it holds the project rules for human and AI contributors. Report vulnerabilities privately using [SECURITY.md](SECURITY.md).

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
