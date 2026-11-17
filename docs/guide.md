# Player guide

Everything you need to know to run Jat'z Distribution in your factory. New to the mod? Start with [Up and running in five steps](../README.md#up-and-running-in-five-steps) in the README.

- [Research](#research)
- [Roads](#roads)
- [Road tunnels](#road-tunnels)
- [Setting up a delivery](#setting-up-a-delivery)
- [The freighter slot](#the-freighter-slot)
- [How freighters choose where to go](#how-freighters-choose-where-to-go)
- [Fuel](#fuel)
- [The status light](#the-status-light)
- [When roads or depots change](#when-roads-or-depots-change)
- [Buffer depots](#buffer-depots)
- [Priority](#priority)
- [Logistic robots](#logistic-robots)
- [Liquid depots](#liquid-depots)
- [Quality](#quality)
- [Mining Drones](#mining-drones)
- [Freighter network window](#freighter-network-window)
- [Circuit network](#circuit-network)
- [Milestones](#milestones)
- [Copy, paste and blueprints](#copy-paste-and-blueprints)
- [Good to know](#good-to-know)

## Research

Research **Freight system** (after Engine, with red and green science) to unlock the provider, request, buffer and fuel depots, the freighter and road. **Liquid freight** (after Freight system and Fluid handling) adds the liquid depots. **Road network monitor** (after Freight system and Circuit network) unlocks the [road network monitor](#road-network-monitor). In a game started before research came to the mod, these three are already researched. **Road tunnels** (after Freight system and Logistics) unlocks [road tunnels](#road-tunnels).

Upgrades make freighters better:

- **Freighter speed:** each level makes delivering freighters 20% faster, those already on the road included. After four levels it goes on forever, each level costing twice the last.
- **Freighter item capacity:** each of ten levels adds one stack of items (two to start with, twelve at the last).
- **Freighter fluid capacity:** after Liquid freight, each of ten levels adds 375 fluid (750 to start with, 4,500 at the last).

A freighter already out keeps the load size it set off with. A **Freighters** panel beside the game's Bonuses window lists these bonuses.

## Roads

Freighters drive **only on road**. Road is a floor tile you craft and place like stone path; it's in our row of the crafting menu. It stacks to 250, and with Space Age a rocket carries two stacks of it (500) to a space platform: **Road stack size** and **Road rocket capacity (stacks)** under **Settings → Mod settings → Startup**. You run 50% faster on road.

- Every depot lays a road tile under its loading zone sign (the marked tile) when you build it, except on space platforms. Road that ends one tile away connects. Removing the depot puts back the ground that was there, unless you laid your own tile over it.
- Only belts, pipes and train tracks can be built on road. Nothing else can, not even depots (only their loading zone sits on road), and road can't be laid under buildings.
- Road can't be laid through cliffs: use [road tunnels](#road-tunnels).
- On the map and minimap, road shows light green and freighters violet.

## Road tunnels

Freighters can't drive over buildings, but they can go under them. Road tunnels work like underground belts:

- A road tunnel is one tile wide and two deep. Build one at the end of a road, its mouth to the road: the tile in front of it must be road. Build a second one facing it, up to 18 tiles away, at the end of the other road. Each craft makes two.
- Whatever stands between the two ends doesn't matter: buildings, belts, water, cliffs.
- A freighter drives into a tunnel's mouth, disappears, and comes out of the other end after as long as driving that far takes. It can go through several tunnels on one trip.
- A tunnel counts like any other road, with no penalty, both for the way a freighter takes and for which provider or fuel depot is nearest. A freighter may pause a moment before setting off on a new way while the game measures it.
- A freighter that is on fire, or splashed with acid or slowed, waits at the mouth until that wears off. One already under ground always comes out, even if you remove a tunnel meanwhile.

## Setting up a delivery

1. Lay road between a provider depot's loading zone and a request depot's.
2. Open the request depot and choose an item and an amount to keep in stock. A request can't be more than fills every slot of the depot (with the default 48 slots, 4,800 of an item that stacks to 100). Choosing an item without typing an amount requests one stack (**Default item request (stacks)** under **Settings → Mod settings → Startup**); a fluid starts at 1,000 (**Default fluid request**). Changing these doesn't change requests already set.
3. Put freighters in its freighter slot.

Within a second, a freighter sets off for a provider depot that has the item. It stops for about a second to load what the request depot still needs and has room for, up to two stacks (more with item capacity research), then drives back, unloads and parks in the slot again. If one freighter or one provider isn't enough, the depot sends more, one a second, each to the next provider that still has some.

A freighter's cargo bays are light grey while empty and turn the color of its cargo when it loads, like a pipe window: water blue, copper orange, sulfur yellow, and so on. Cargo without an obvious color keeps the truck's slate blue.

### Full loads only

Tick **Full loads only** on a request or buffer depot (item or liquid) to keep freighters from driving out for a handful of items: they set off only when they can come back full: a depot they fetch from has a whole load to give (two stacks of the item, or 750 of a fluid, more with capacity research), and the requesting depot has room for one. A request smaller than one load is fetched whole. Providers holding less than a load are passed by, even when nearer. The check is made when a freighter sets off; if the stock changes while it is on its way, it still brings back what fits rather than come home empty. It's off by default. **Full loads only by default** under **Settings → Mod settings → Startup** ticks it on new depots; depots already built keep their own.

### Use freighter storage

Tick **Use freighter storage** on a liquid request or buffer depot to count its freighters as storage: 50 freighters carrying 2,625 each hold 131,250, so with a 25,000 tank they add 106,250. Adding or losing freighters, or researching fluid capacity, changes it, and the request you typed follows the limit. Fluid in the parked freighters is shown under the checkbox and goes into the tank as soon as there is room, even after you untick it. If you change the request to another fluid, the freighters keep the old fluid until you ask for it again. Fluid the freighters hold is lost if the depot is removed. It's off by default.

## The freighter slot

A request depot holds up to **100 freighters** in its freighter slot. The slot's tooltip lists the clicks.

| To… | Do this |
| --- | --- |
| Fill the slot | Ctrl+click freighters in your inventory while the depot is open, or ctrl+click the depot. Any that don't fit stay with you. Freighters put in the depot's chest move to the slot too, as does one dropped in with Z, before an inserter can take it. |
| Have robots bring freighters | Click the slot with a freighter ghost in your cursor (in remote view, or with no freighters on you): robots bring as many as fit. |
| Have robots take freighters away | In remote view, right-click the slot. |
| Get them all back | Mine the depot. You get all its freighters, including those out on deliveries. |

The line beside the slot shows how many freighters are out, and a green **+N** while N more are requested. For the full count, open or point at the depot and type `/jatz-freighters` in the console.

## How freighters choose where to go

Of the depots that have the item and can be reached by road, freighters go to the one that comes first in this order:

1. **Buffer depots before providers** for a request depot with **Request from buffer depots** ticked; **providers before buffer depots** when it's unticked. See [Buffer depots](#buffer-depots).
2. **Higher priority before lower**, even when the lower one is nearer. See [Priority](#priority).
3. **Nearest by road among equals**, not in a straight line.

If no road leads to a depot, the depot that asked shows why and tries the next one in this order.

## Fuel

Freighters burn fuel as they drive, and fill up at **fuel depots** by themselves.

- A new freighter comes with a full tank (20 MJ for a normal freighter, about 2,000 tiles of driving; better freighters hold more). It keeps what is left when it parks; the depot sends its best freighters first (see [Quality](#quality)), and of those the one with the most fuel.
- Hover a freighter to see its fuel: green, yellow when low, red when dry. The request depot's window shows its freighters' fuel under the slot.
- Load a fuel depot with **any fuel item**, by hand, inserter or robot, or **pipe in any fluid that burns**. Freighters take the fluid first, then whole items. An item worth more than a tank goes in whole and lasts a very long way. In the base game, **petroleum gas** burns for freighters: 50 fill a normal tank, as with Transport Drones. Fuel that burns into something (a fuel cell, say) leaves that in the depot.
- Before each leg of a trip a freighter checks its tank will last, with some to spare. If not, it first drives to the **fuel depot nearest by road**, fills up, then carries on, cargo and all. If it runs dry anyway, it crawls on at a tenth of its speed.
- Freighters only fill up at fuel depots. Fuel in other depots is ordinary cargo, never burned.
- A freighter too low to reach the provider stays home. The request depot's light turns yellow if the fuel depots are empty, red if none is connected by road.
- If a fluid that doesn't burn gets into a fuel depot, the **flush** button in its window empties it and the pipes joined to it.
- A fuel depot has 48 slots and a 25,000 tank by default (**Settings → Mod settings → Startup**). Making either smaller on an existing save can lose what no longer fits.
- The tank size and the fuel burned per tile are **Settings → Mod settings → Map** options. Setting the use to 0 turns fuel off.

## The status light

A light beside the request shows at a glance whether it can be filled. Hover it for the details. In this table, a provider also means a buffer depot for a request depot, and a lower-priority buffer depot for a buffer depot with **Buffers pull by priority**.

| Light | Meaning |
| --- | --- |
| 🟢 Green | Stocked, a freighter is on its way, or it's finding a provider by road |
| 🟡 Yellow | Waiting on something in the way: no room in the depot, waiting for a full load or, for a liquid depot, for at least 100, its loading zone isn't on road, no road route to a provider that has it, no freighters (or none could be sent), freighters too low on fuel while the fuel depots are empty, or a liquid depot's tank holds another fluid |
| 🔴 Red | No provider with road at its loading zone has it, its freighters need fuel and no fuel depot is connected by road, or the depot is switched off by its circuit condition |
| ⚪ Grey | Nothing requested |

## When roads or depots change

- As soon as you lay road, or build or turn a depot, waiting requests try again. Otherwise they try again after 10 seconds.
- Removing road re-routes the freighters whose way it was on within a second or so. A loaded freighter cut off from home takes the cargo back to the provider.
- If a provider is removed while a freighter is heading there, the freighter goes on to the next one.
- A request or buffer depot marked for deconstruction fetches nothing, so robots can empty it.

## Buffer depots

Buffer depots keep stock close to where it's needed. They work like request depots, with their own request and freighters, but by default fetch only from provider depots.

Turn on **Buffers pull by priority** under **Settings → Mod settings → Startup** (off by default) to let buffer depots also fetch from buffer depots with a strictly lower priority: local buffers at priority 3 can supply a central buffer at priority 8. Buffers of equal priority never send freighters to each other. A buffer depot ranks those buffers and provider depots together, by priority, then by road distance; providers stay in the running whatever their priority.

Request depots take from buffer depots too. The **Request from buffer depots** checkbox (like a requester chest's "request from buffer chests") decides which come first:

- **Ticked:** buffer depots first, even when a provider is nearer.
- **Unticked** (the default): provider depots first. Buffers supply only what no provider can: none has it, none can be reached, or theirs is already promised.

Request and buffer depots replace each other in place, as chests do: by hand, by robots from a ghost, a blueprint pasted with super-forced building (Ctrl+Shift+click) or an upgrade planner, and by undo and redo. The depot keeps its chest, request, settings and freighters, including those out on trips, and does its new job at once. A request too big for the new chest is cut to what fills it. Logistic robots are kept out of a new buffer depot until you let them in.

## Priority

Provider and buffer depots have a **priority** slider from 1 to 10 (5 to start with) in the panel beside their window.

- Freighters go to the highest-priority depot they can reach by road, even when a lower one is nearer, and to the nearest among equals.
- For request depots, priority only orders depots of the same kind: with **Request from buffer depots** ticked, a buffer at 1 still comes before a provider at 10, and the other way round when unticked.

## Logistic robots

Item provider and buffer depots can join the logistic network. Tick **Logistic robots can use it** in the depot's window (off on every new depot):

- A **provider depot** then works like a passive provider chest. Freighters still fetch from it, skipping what robots have taken.
- A **buffer depot** then works like a buffer chest, and its freighters keep its own request stocked as before.
- If the game's own **Enable/disable** condition in the depot's circuit network settings is on, that decides, and the checkbox only shows it.
- Request depots and liquid depots are not part of the logistic network.

## Liquid depots

Liquid depots work the same way for fluids. Research **Liquid freight** to unlock them.

- A liquid depot's window shows your inventory beside its tank, so on a liquid request or buffer depot you can move freighters into the slot (see its tooltip). It has no chest for items.
- A **liquid request** depot keeps a fluid in its tank, fetching from liquid provider and liquid buffer depots, 750 units at a time (more with fluid capacity research).
- A **liquid buffer** depot fills from liquid providers, and with **Buffers pull by priority**, from lower-priority liquid buffers too.
- Liquid provider and buffer depots have the same priority slider.
- Every liquid depot's tank holds 25,000 by default; each kind's size is set under **Settings → Mod settings → Startup**. Making a tank smaller on an existing save can lose the fluid above the new size. A request can't be more than the tank holds (unless it uses [freighter storage](#use-freighter-storage)), and freighters set off only for what still fits, counting what is already on its way: a 25,000 tank with freighters carrying 2,625 has room for 9 full loads out at once and a tenth for the last 1,375 (not with **Full loads only**). A request set in an older version at 25,000 on a liquid request depot, or at a liquid buffer depot's unchanged tank size, now asks to fill the depot.
- Fluids keep their temperature on the way.
- A liquid depot whose tank holds a different fluid waits until it is emptied.
- Freighters never set off for less than **100** of a fluid, so the last drops in a tank don't keep them driving back and forth. A request below 100 is fetched whole.
- Items and fluids never mix: item depots only deal with item depots, liquid depots with liquid depots.

## Quality

With the Quality mod (it comes with Space Age), depots and freighters can be of any quality, and requests can name the quality they want. Without it, everything is normal quality.

- **Requesting by quality.** The **Quality** row in an item request or buffer depot's panel works like the game's logistic requests. A request for *iron plate ≥ rare* fetches rare, epic and legendary plates and counts them all towards the amount. Fluids have no quality.
- **Only the request decides what is fetched**, not the quality of the freighter or depots.
- **Highest first.** Freighters take the highest quality the provider has first. Each quality fills its own cargo stacks.
- **Better freighters** are 30% better per quality level (uncommon 1.3×, rare 1.6×, epic 1.9×, legendary 2.5×): more health, more cargo stacks (rounded down, as chest slots are: two stacks become 3 for rare and 5 for legendary), more fluid, more speed and a bigger fuel tank. A depot sends its best freighters first.
- **Better depots** have the game's bigger chests and tanks, a better Fuel depot's liquid tank included.
- **Upgrading a depot** to another quality keeps everything: request, settings, freighters and what they are bringing. A request is still limited to what the depot holds.
- Robots asked for freighters bring the quality of the ghost in your cursor. A depot replacing a lost freighter asks for one of the same quality.
- A road network monitor reading **What request depots still need** gives each need the quality the request names (normal for **Any quality**).

## Mining Drones

With [Mining Drones](https://mods.factorio.com/mod/Mining_Drones), [Mining Drones 2 Remastered](https://mods.factorio.com/mod/Mining_Drones_Remastered) or [Mining Drones Mod](https://mods.factorio.com/mod/Mining_Drones_Mod) installed, every mining depot is also an item provider depot for whatever its drones mine.

- Freighters load at the tile just behind the depot, on the side away from its mining area. The depot lays road there, so connect your road to it.
- Mining depots have the same priority slider and circuit condition as provider depots, in a panel beside their window.

## Freighter network window

After **Freight system** research, the **Freighter network** button on the shortcut bar opens an overview of your freighters, depots and stock. Hover any icon or number for its exact amount, breakdown and meaning.

- **At the top:** **Freighters** (parked and out) and **Active** (out on the road), then how many of each kind of depot you have, with Fuel and Mining Drones depots under **Support**.
- **Surface:** with Space Age, or with depots on more than one surface, a drop-down picks **All surfaces** or one. Stock on another planet isn't available to a request depot here.
- **Items** and **Fluids** tabs list one row per item or fluid. Under **Providers**, **Requesters** and **Buffers**, each row has the **Stock** held and a count (**Depots** or **Requests**). **Still needed** is what active request and buffer depots still lack, after what they hold and what is on its way.
- **Finding things:** rows with the most still needed come first. The other drop-down shows **All stock and requests**, only shortages (**Unmet demand first — only shortages**), or **Stock without configured requests**. The button above the rows picks one item or fluid; right-click it to show all again.
- The numbers are a snapshot: the window counts the depots a few at a time, then waits five seconds before counting again, only while a connected player has it open. Its age shows beside the page arrows.

## Circuit network

Every depot takes red and green wires. Item depots send their contents and liquid depots their fluid, as chests and storage tanks do.

Provider, request and buffer depots, item and liquid, also have an **Enable/disable** circuit condition at the bottom of their panel, like a logistic chest's:

- Tick **Enable/disable** and set the condition. **Everything** means every signal must match, **Anything** at least one.
- Choose what the condition reads:
  - **Circuit network**: the red and green wires, leaving out this depot's own contents, so a depot asking for *wood > 3000* doesn't count its own wood. Without a wire, the condition does nothing.
  - **This depot's contents**: only what this depot holds. No wire needed. A provider with *iron plate > 200* supplies only while it holds more than 200. For sending freighters, it counts what freighters on their way will take as gone.
- The depot takes part in deliveries only while the condition holds. Freighters a switched-off request or buffer depot already sent finish their trips; those heading to a provider or buffer depot that switches off go to another one, or home.
- When a request or buffer depot gets what it asked for some other way, or a provider loses stock some other way, freighters it no longer needs go elsewhere or come home. A freighter is sent elsewhere only once per trip.
- The light beside the checkbox is green while the depot is on, red while the condition switches it off, and grey while the condition has no effect.

### Road network monitor

To switch depots on what the road network holds or needs, build a **road network monitor** right beside a road, as you would a depot's loading zone, and wire it to the depots. Once a second it sends one reading of the depots on that road network, like a roboport. Open it to choose the reading:

- **What provider and buffer depots hold** (the default)
- **What provider depots hold**
- **What request depots hold**: fluid waiting in a liquid request depot's parked freighters (**Use freighter storage**) counts with its tank's.
- **What request depots still need**

More about it:

- Its road network is all the road joined to one of the four tiles beside it. A depot is on it when its loading zone is.
- Freighters on the road, and depots switched off by their circuit condition, aren't counted.
- Use one monitor per reading, each on its own wire, so a condition reads one thing at a time.

For example, wire a backup provider to a monitor and give it the condition *iron plate < 100*: it supplies only while the other providers on the road run low.

## Milestones

With [Milestones](https://mods.factorio.com/mod/Milestones) installed, its list (in the Progress group) also tracks your first freighter, then 100 freighters and 1,000 road and every tenfold after those, alongside whatever preset it uses.

## Copy, paste and blueprints

- Copy and Paste settings, copy and paste and blueprints carry a depot's request (with its quality), **Request from buffer depots**, **Full loads only**, **Use freighter storage**, priority, circuit condition and **Logistic robots can use it**, and a request depot's number of freighters. The new depot asks robots for the freighters, or you bring them by hand. A road network monitor keeps its reading.
- Clones keep a depot's request, priority and circuit condition.
- Undoing the removal of a depot or road network monitor brings back its settings, and a request depot asks robots for its freighters again.
- Blueprint parametrisation works on request and buffer depots: a depot's item or fluid, its quality, its amount and its number of freighters become parameters. The blueprint lists one "Depot request settings" per depot; it never stays in the world. Pasting a blueprint over the same kind of depot sets its request (clearing it if the blueprint had none) and freighters too. A request above 2,147,483,647 is kept but can't be parametrised.

## Good to know

- Freighters are for depots to send out: you can't place one and drive it yourself unless you turn on **Place freighters as cars** under **Settings → Mod settings → Startup**. Freighters already placed stay drivable either way.
- Construction robots repair damaged freighters, mostly while they stop to load or unload.
- Enemies can destroy freighters. Freighters never fight back or turn aside, and run over enemy units in their way, as a train does, but never harm players or other freighters.
- A destroyed freighter leaves a wreck for 15 minutes and is lost, with its cargo. Its request depot asks construction robots for a replacement.
- Freighters taken out of a depot and put back come with a full tank again.
- Freighters out on deliveries make a little pollution.
- Cargo keeps its data on the way: armor keeps its equipment, food how far it has spoiled.
- In alt mode, a loaded freighter shows the icon of what it carries.
- Provider, request, buffer and fuel depots have 48 slots each by default, like a steel chest. Each kind's slot count (1 to 1,000) is under **Settings → Mod settings → Startup**. Making it smaller on an existing save can lose the items in the slots taken away.
- Provider depots are red, request depots blue, buffer depots green and the fuel depot amber: the default paint of the artwork (see [the depot art](../assets/depots/README.md#paint-layers)); there is no in-game setting for it.
