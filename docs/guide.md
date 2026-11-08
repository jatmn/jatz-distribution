# Player guide

Everything you need to know to run Jat'z Distribution in your factory. New to the mod? Start with [How it works](../README.md#how-it-works) in the README.

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
- [Liquid depots](#liquid-depots)
- [Circuit network](#circuit-network)
- [Copy, paste and blueprints](#copy-paste-and-blueprints)
- [Good to know](#good-to-know)

## Research

Research **Freight system** (after Engine, with red and green science) to unlock the provider, request, buffer and fuel depots, the freighter and road. **Liquid freight** expands it with the liquid depots: research it after Freight system and Fluid handling. **Road network monitor**, after Freight system and Circuit network, unlocks the [road network monitor](#road-network-monitor). In a game started before research came to the mod, these three are already researched, so nothing you could build is taken away. **Road tunnels**, after Freight system and Logistics, unlocks [road tunnels](#road-tunnels).

Upgrades make freighters better:

- **Freighter speed:** each level makes delivering freighters 20% faster, freighters already on the road included. After four levels it goes on forever, each level costing twice the last.
- **Freighter item capacity:** each of five levels lets a freighter carry one more stack of items (ten to start with).
- **Freighter fluid capacity:** after Liquid freight, each of ten levels lets a freighter carry 175 more fluid (750 to start with, 2,500 at the last level).

A freighter already out keeps the load size it set off with.

## Roads

Freighters drive **only on road**. Road is a floor tile you craft and place like stone path; it's in our row of the crafting menu.

- Every depot lays a road tile under its loading zone sign (the marked tile) when you build it, except on space platforms. You only need to bring road up to it: road that ends one tile away connects.
- Removing the depot takes that tile away again and puts back the ground that was there, unless you laid your own road or tile over it.
- Only belts, pipes and train tracks can be built on road (and vehicles can drive on it). Nothing else can: not depots, though their loading zone sits on road, nor poles, inserters or other buildings. Road can't be laid under them either.

## Road tunnels

Freighters can't drive over buildings, but they can go under them. Road tunnels work like underground belts:

- A road tunnel is one tile wide and two deep, a ramp going down from its mouth. Build one at the end of a road, its mouth to the road: the tile in front of it is where freighters drive in and come out, so it must be road. Build a second one facing it, with up to 18 tiles between them, at the end of the other road. While you place it, the game shows how far it reaches and which tunnel it joins, as it does for pipes to ground. Each craft makes two.
- Whatever stands between the two ends doesn't matter: buildings, belts, water.
- A freighter whose provider, fuel depot or home is on another road network that tunnels join drives to a tunnel's mouth, disappears, and comes out of the other end after as long as driving that far on road takes, then drives on. It can go through several tunnels on one trip.
- Freighters use tunnels only to reach another road network. If road already joins the two places, they drive the road, even when a tunnel would be shorter.
- Like any building, a tunnel can't stand on road, and road can't be laid under it.
- A freighter that is on fire, or splashed with acid or slowed, waits at the mouth until that wears off. One already under ground always comes out at the other end, even if you remove a tunnel meanwhile.

## Setting up a delivery

1. Lay road between a provider depot's loading zone and a request depot's.
2. Open the request depot and choose an item and an amount to keep in stock. A request or buffer depot can't request more of the item than fills every one of its slots: a larger amount is set to that (with the default 48 slots, 4,800 of an item that stacks to 100, 480 of one that stacks to 10).
3. Put freighters in its freighter slot.

Within a second, a freighter sets off for a provider depot that has the item. It stops for about a second to load what the request depot still needs and has room for, up to ten stacks (more with item capacity research), then drives back, stops again for about a second to unload and parks in the slot again.

You can tell what a freighter carries by its cargo bays. They are light grey while it's empty, on its way to pick up. When it loads, they turn the color of its cargo, like a chemical plant's tank or a pipe window: water blue, iron plates blue-grey, copper orange, sulfur yellow, and so on. Cargo without an obvious color keeps the truck's usual slate blue. A freighter that's on fire, or splashed with acid or slowed, when it loads keeps its grey until that wears off, then changes color on the road.

If one freighter isn't enough, or one provider doesn't have it all, the depot sends more, one a second, each to the next provider that still has some.

### Full loads only

Tick **Full loads only** on a request or buffer depot (item or liquid) to keep freighters from driving out for a handful of items. A freighter then sets off only when it can come back full: a depot it fetches from has a whole load to give (ten stacks of the item, or 750 of a fluid, more with capacity research), and the requesting depot has room for one. Providers holding less are passed by, even when they're nearer, and smaller amounts wait until a full load is ready. A request smaller than one load counts as a full load, so it's fetched whole once the depot has room for all of it. The check is made when a freighter sets off, and again if it's sent on to another provider. If the depot fills up some other way, or the provider's stock is taken, while the freighter is on its way, it still brings back what fits rather than come home empty. It's off by default.

## The freighter slot

A request depot holds up to **100 freighters** in its freighter slot.

| To… | Do this |
| --- | --- |
| Fill the slot | Ctrl+click freighters in your inventory while the depot is open, or ctrl+click the depot. Any that don't fit stay with you. Freighters dropped into the depot's chest move to the slot too. |
| Have robots bring freighters | In remote view, or with no freighters on you, click the slot with a freighter ghost in your cursor. Right-click adds one more. In remote view, a click with an empty cursor cancels. |
| Have robots take freighters away | In remote view, right-click the slot. Right-click again to cancel. |
| Grab a freighter | Pipette (Q) over the slot picks up a freighter, or its ghost. |
| Get them all back | Mine the depot. You get all its freighters, including those out on deliveries. |

The line beside the slot shows how many freighters are out on the road, and a green **+N** while N more have been requested for the depot. Hover it for the full breakdown.

Other items ctrl+clicked in go into the depot's inventory as usual.

## How freighters choose where to go

Of the depots that have the item and can be reached by road, freighters go to the one that comes first in this order:

1. **Buffer depots before providers** for a request depot with **Request from buffer depots** ticked; **providers before buffer depots** when it's unticked. See [Buffer depots](#buffer-depots).
2. **Higher priority before lower**, even when the lower one is nearer. See [Priority](#priority).
3. **Nearest by road among equals**, not in a straight line. A provider just across a wall of concrete loses to one farther away with a shorter road.

If there's no road route to a depot, no freighter is sent there. The depot that asked shows why and tries the next one in this order, so a request depot with **Request from buffer depots** unticked moves on to buffer depots when no provider can be reached.

## Fuel

Freighters burn fuel as they drive, and fill up at **fuel depots** by themselves.

- A new freighter comes with a full tank (20 MJ, about 2,000 tiles of driving). A freighter keeps what is left in its tank when it parks, and sets off on the next trip with it: the depot sends the one with the most fuel.
- Hover a freighter on the road to see its fuel: green, yellow when low, red when it has run dry. The request depot's window shows the fuel of the freighters in its slot under the freighter slot; hover that line for every freighter's fuel, at home and out.
- Load a fuel depot with **any fuel item** (coal, solid fuel, rocket fuel, a mod's fuel, anything that burns), by hand, inserter or robot, or **pipe in any fluid that burns**. Freighters take the fluid first, then items, a whole item at a time. An item worth more than a tank (some mods have fuel worth 10 GJ) goes in whole, and the freighter keeps all of it, so one such item lasts a very long way. In the base game, **petroleum gas** burns for freighters: 50 fill a tank, as with Transport Drones (unless another mod already gives it a fuel value). Fuel that burns into something (a fuel cell, say) leaves that in the depot.
- Before every leg of a trip (leaving home, leaving the provider) a freighter checks whether its tank will last to where it's going, with some to spare. If not, it first drives to the **fuel depot nearest by road**, stops about a second to fill up, then carries on where it was going, cargo and all.
- If its tank runs dry anyway, it crawls on at a tenth of its speed to a fuel depot, or to where it was going if it can't reach one.
- Freighters only fill up at fuel depots, and are only sent when there is fuel to get. Fuel in provider, request or buffer depots is ordinary cargo: freighters deliver it like anything else and never burn it.
- A freighter that can't even reach the provider on what it has stays home rather than being sent to wait at an empty fuel depot. If there are fuel depots but none has fuel, the request depot's light turns yellow, and the freighter sets off as soon as one does. If no fuel depot is connected by road, the light turns red, and the freighter sets off as soon as you build one or connect it by road (and it has fuel).
- The fuel depot's window shows the fluid in it. If a fluid that doesn't burn got in, the **flush** button beside it empties it (and the pipes joined to it).
- A fuel depot has 48 slots for fuel items and a tank of 25,000 for liquid fuel by default. You can change both under **Settings → Mod settings → Startup**. Making either smaller on an existing save can lose what no longer fits.
- How big the tank is and how much a tile of driving burns are **Settings → Mod settings → Map** options. Setting the use to 0 turns fuel off.

## The status light

A light beside the request shows at a glance whether it can be filled. Hover it for the details.

| Light | Meaning |
| --- | --- |
| 🟢 Green | Stocked, a freighter is on its way, or it's finding a provider (or, for a request depot, a buffer depot) by road |
| 🟡 Yellow | Waiting on something in the way: no room in the depot, waiting for a full load (with **Full loads only** ticked), its loading zone isn't on road, no road route to a provider (or, for a request depot, a buffer depot) that has it, no freighters (or none could be sent), freighters too low on fuel while the fuel depots are empty, or a liquid depot's tank holds another fluid |
| 🔴 Red | No provider depot with road at its loading zone has it (nor, for a request depot, any buffer depot), its freighters need fuel and no fuel depot is connected by road, or the depot is switched off by its circuit condition |
| ⚪ Grey | Nothing requested |

## When roads or depots change

- As soon as you lay road, or build or turn a depot, waiting requests try again. Otherwise they try again after 10 seconds.
- Removing road re-routes freighters straight away. If the road is cut behind a loaded freighter, it takes the cargo back to the provider.
- If a provider is removed while a freighter is heading there, the freighter goes on to the next one.

## Buffer depots

Buffer depots keep stock close to where it's needed. They work like request depots, with their own request and freighters, but they fetch only from provider depots and send nothing anywhere themselves.

Request depots take from buffer depots too. The **Request from buffer depots** checkbox (like a requester chest's "request from buffer chests") decides which come first:

- **Ticked:** buffer depots first, even when a provider is nearer. It goes to providers only for what no buffer can supply.
- **Unticked** (the default): provider depots first, however near a buffer is. It falls back to buffer depots only for what no provider can supply: when no provider has the item, none can be reached by road, or what they have is already promised to other freighters.

## Priority

Provider and buffer depots have a **priority** slider from 1 to 10 (5 to start with) in the panel beside their window.

- Freighters go to the highest-priority depot they can reach by road, even when a lower one is nearer, and to the nearest among equals.
- Priority only orders depots of the same kind: with **Request from buffer depots** ticked, a buffer at 1 still comes before a provider at 10; unticked, a provider at 1 still comes before a buffer at 10.
- Copy and Paste settings, blueprints and clones keep it.

## Liquid depots

Liquid depots work the same way for fluids. Research **Liquid freight** to unlock them.

- A **liquid request** depot keeps a fluid in its tank, sending its freighters to liquid provider depots and liquid buffer depots (buffers first if **Request from buffer depots** is ticked, only when no provider can supply it otherwise), 750 units at a time (more with fluid capacity research).
- A **liquid buffer** depot fills from liquid providers only.
- Liquid provider and buffer depots have the same priority slider.
- Every liquid depot's tank holds 25,000 by default. You can change the tank size of liquid provider depots and of liquid buffer depots separately under **Settings → Mod settings → Startup**. Making a tank smaller on an existing save can lose the fluid above the new size. A liquid request or buffer depot can't request more than its tank holds: a larger amount is set to the tank's size.
- Fluids keep their temperature on the way.
- A liquid depot whose tank holds a different fluid waits until it is emptied.
- Items and fluids never mix: item depots only deal with item depots, liquid depots with liquid depots.

## Mining Drones

With [Mining Drones](https://mods.factorio.com/mod/Mining_Drones), [Mining Drones 2 Remastered](https://mods.factorio.com/mod/Mining_Drones_Remastered) or [Mining Drones Mod](https://mods.factorio.com/mod/Mining_Drones_Mod) installed, every mining depot is also an item provider depot for whatever its drones mine.

- Freighters load at the tile just behind the depot, on the side away from its mining area. The depot lays road there, like our depots do, so connect your road to it.
- Mining depots have the same priority slider and circuit condition as provider depots, in a panel beside their window.

## Circuit network

Every depot takes red and green wires. Item depots send their contents and liquid depots their fluid, as chests and storage tanks do.

Provider, request and buffer depots, item and liquid, also have an **Enable/disable** circuit condition at the bottom of their panel, like a logistic chest's:

- Tick **Enable/disable** and set the condition: a signal compared with another signal, or with a number. **Everything** means every signal must match, **Anything** at least one.
- Choose what the condition reads:
  - **Circuit network**: the red and green wires, leaving out this depot's own contents. A depot sends what it holds on its wires, and a road network monitor counts it too, so without this a depot asking for *wood > 3000* would switch on with 2,800 wood elsewhere and 300 of its own. Without a wire, the condition does nothing.
  - **This depot's contents**: only what this depot holds, each quality its own signal and fluids in whole units. No wire needed. For example, a provider with *iron plate > 200* supplies only while it holds more than 200. For sending freighters, a provider or buffer depot counts what freighters already on their way will take as gone: holding 250 with one freighter coming for 100, it gets no other freighter until it holds more again. The condition must still hold on what it holds now too, so a depot switched off gets no freighters whatever is promised.
- The depot takes part in deliveries only while the condition holds. Switched off, a request or buffer depot sends no freighters, and no freighter is sent to fetch from a provider or buffer depot. A request or buffer depot's freighters already on their way finish their trips; freighters on their way to fetch from a provider or buffer depot that switches off go to another one instead (or home, if none has the item).
- A request or buffer depot that gets what it asked for some other way (you fill it by hand, or an inserter does) lets go of what its freighters on their way out were going to fetch: the stock they had claimed is free for other depots at once, and a freighter left with nothing to fetch comes home.
- The same goes for stock taken out of a provider or buffer depot another way (an inserter, a player): freighters it no longer has enough for go elsewhere, the ones sent there last first, rather than arriving to find nothing. A freighter is sent elsewhere only once per trip, also when the depot it was heading for is removed: if no other depot has the item, that depot can't serve it either, or its own depot needs nothing more by then, it gives up and comes home empty (filling up at a fuel depot on the way if it needs to).
- The light beside the checkbox is green while the depot is on, red while the condition switches it off, and grey while the condition has no effect. Pointing at a switched-off depot shows "Switched off by its circuit condition" with a red light too.

### Road network monitor

To switch depots on what the road network holds or needs, build a **road network monitor** right beside a road, as you would a depot's loading zone, and wire it to the depots. Like every building, it can't stand on the road itself. Once a second it sends one reading of the depots on that road network, like a roboport reading its logistic network. Open it to choose the reading:

- **What provider and buffer depots hold** (the default): what freighters can fetch.
- **What provider depots hold**: buffer depots left out.
- **What request depots hold**: item and liquid request depots, not buffer depots.
- **What request depots still need**: each request depot's request, less what it holds and what freighters are already bringing it.

More about it:

- Its road network is all the road joined, side by side, to one of the four tiles beside it. A depot is on it when its loading zone is.
- Item depots count their items (each quality as its own signal) and liquid depots their fluids.
- Freighters on the road, and depots switched off by their circuit condition, aren't counted.
- Its signals can't be edited: opening it shows only the choice of reading. Copy and Paste settings, blueprints and copies keep the reading.
- Use one monitor per reading, each on its own wire, so a condition reads one thing at a time.

For example, wire a backup provider to a monitor and give it the condition *iron plate < 100*: it supplies only while the other providers on the road run low.

## Milestones

With [Milestones](https://mods.factorio.com/mod/Milestones) installed, its list (in the Progress group) also tracks your first freighter, 100 freighters and 1,000 road, then every tenfold after those, alongside whatever preset it uses.

## Copy, paste and blueprints

- Copy and Paste settings, copy and paste, and blueprints carry a request depot's request, its **Request from buffer depots** and **Full loads only** settings, and its number of freighters. The new depot asks for the freighters (as a ghost request), and construction robots, or you by hand, bring them. This works for liquid depots too.
- They carry every depot's circuit condition too.
- Blueprint parametrisation works on request and buffer depots' requests and freighters: a blueprint of a depot offers its request's item or fluid and amount as parameters, and its number of freighters (as a number only, with no item to swap), and the depots built from it request what you fill in and ask robots for that many freighters. The blueprint lists one "Depot request settings" per request or buffer depot; it is how the game sees the request and freighters, and never stays in the world. Pasting a blueprint over the same kind of depot already built sets its request (clearing it if the blueprint's depot had none) and freighters too. A request above 2,147,483,647 (the most a blueprint parameter holds) is kept, pasting over a depot included, but can't be parametrised.
- Cloned depots keep their request and circuit condition.

## Good to know

- Freighters are for depots to send out: you can't place one and drive it yourself. To allow that, turn on **Place freighters as cars** under **Settings → Mod settings → Startup**. Freighters already placed stay drivable either way, and you can pick them up.
- Enemies can attack and destroy freighters. Freighters never fight back or turn aside: they drive on until they arrive or are destroyed. A freighter that drives through an enemy unit runs it over, as a train does, but it never harms players or other freighters.
- A freighter destroyed on the road explodes and leaves a freighter wreck, which disappears after 15 minutes. It is lost, with its cargo. Its request depot then asks construction robots for a replacement freighter. You can also put one in by hand.
- Freighters taken out of a depot (by hand, robots or mining it) and put back come with a full tank again.
- Freighters out on deliveries make a little pollution.
- Cargo keeps its data on the way: armor keeps its equipment, food how far it has spoiled.
- In alt mode, a loaded freighter shows the icon of the item or fluid it carries, as machines show their recipe. Empty freighters show nothing.
- Requests are for normal-quality items.
- Provider, request, buffer and fuel depots have 48 slots each by default, like a steel chest. You can change each kind's slot count separately (1 to 1,000) under **Settings → Mod settings → Startup**. Making it smaller on an existing save can lose the items in the slots taken away.
- By default, provider depots are red, request depots blue, buffer depots green and the fuel depot amber. Every color can be changed.
