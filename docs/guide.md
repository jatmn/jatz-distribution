# Player guide

Everything you need to know to run Jat'z Distribution in your factory. New to the mod? Start with [How it works](../README.md#how-it-works) in the README.

- [Roads](#roads)
- [Setting up a delivery](#setting-up-a-delivery)
- [The freighter slot](#the-freighter-slot)
- [How freighters choose where to go](#how-freighters-choose-where-to-go)
- [The status light](#the-status-light)
- [When roads or depots change](#when-roads-or-depots-change)
- [Buffer depots](#buffer-depots)
- [Priority](#priority)
- [Liquid depots](#liquid-depots)
- [Copy, paste and blueprints](#copy-paste-and-blueprints)
- [Good to know](#good-to-know)

## Roads

Freighters drive **only on road**. Road is a floor tile you craft and place like stone path; it's in our row of the crafting menu.

- Every depot lays a road tile under its loading zone sign (the marked tile) when you build it. You only need to bring road up to it: road that ends one tile away connects.
- Removing the depot takes that tile away again and puts back the ground that was there, unless you laid your own road or tile over it.
- Buildings can still be placed on road. Freighters drive through them.

## Setting up a delivery

1. Lay road between a provider depot's loading zone and a request depot's.
2. Open the request depot and choose an item and an amount to keep in stock.
3. Put freighters in its freighter slot.

Within a second, a freighter sets off for a provider depot that has the item. It loads what the request depot still needs and has room for, up to ten stacks, then drives back, unloads and parks in the slot again.

If one freighter isn't enough, or one provider doesn't have it all, the depot sends more, one a second, each to the next provider that still has some.

## The freighter slot

A request depot holds up to **100 freighters** in its freighter slot.

| To… | Do this |
| --- | --- |
| Fill the slot | Ctrl+click freighters in your inventory while the depot is open, or ctrl+click the depot. Any that don't fit stay with you. Freighters dropped into the depot's chest move to the slot too. |
| Have robots bring freighters | In remote view, or with no freighters on you, click the slot with a freighter ghost in your cursor. Right-click adds one more. In remote view, a click with an empty cursor cancels. |
| Have robots take freighters away | In remote view, right-click the slot. Right-click again to cancel. |
| Grab a freighter | Pipette (Q) over the slot picks up a freighter, or its ghost. |
| Get them all back | Mine the depot. You get all its freighters, including those out on deliveries. |

The line beside the slot shows how many freighters are out on the road, and a green **+N** while N more are on their way to the depot. Hover it for the full breakdown.

Other items ctrl+clicked in go into the depot's inventory as usual.

## How freighters choose where to go

Freighters pick the provider that is nearest **by road**, not in a straight line. A provider just across a wall of concrete loses to one farther away with a shorter road.

If there's no road route to a provider, no freighter is sent there. The request depot shows why and tries another provider.

## The status light

A light beside the request shows at a glance whether it can be filled. Hover it for the details.

| Light | Meaning |
| --- | --- |
| 🟢 Green | Stocked, or on its way |
| 🟡 Yellow | The item is out there, but something is in the way: no road route, no freighters, or no room |
| 🔴 Red | No provider has it |
| ⚪ Grey | Nothing requested |

## When roads or depots change

- As soon as you lay road, or build or turn a depot, waiting requests try again. Otherwise they try again after 10 seconds.
- Removing road re-routes freighters straight away. If the road is cut behind a loaded freighter, it takes the cargo back to the provider.
- If a provider is removed while a freighter is heading there, the freighter goes on to the next one.

## Buffer depots

Buffer depots keep stock close to where it's needed. They work like request depots, with their own request and freighters, but they fetch only from provider depots and send nothing anywhere themselves.

Tick **Request from buffer depots** on a request depot (like a requester chest's "request from buffer chests") and it takes from buffer depots first, even when a provider is nearer. It goes to providers only for what no buffer can supply.

## Priority

Provider and buffer depots have a **priority** slider from 1 to 10 (5 to start with) in the panel beside their window.

- Freighters go to the highest-priority depot they can reach by road, even when a lower one is nearer, and to the nearest among equals.
- Priority only orders depots of the same kind: a buffer at 1 still comes before a provider at 10.
- Copy and Paste settings, blueprints and clones keep it.

## Liquid depots

Liquid depots work the same way for fluids.

- A **liquid request** depot keeps a fluid in its tank, sending its freighters to liquid provider depots (and liquid buffer depots, if ticked), 500 units at a time.
- A **liquid buffer** depot fills from liquid providers only.
- Liquid provider and buffer depots have the same priority slider.
- Fluids keep their temperature on the way.
- A liquid depot whose tank holds a different fluid waits until it is emptied.
- Items and fluids never mix: item depots only deal with item depots, liquid depots with liquid depots.

## Copy, paste and blueprints

- Copy and Paste settings, copy and paste, and blueprints carry a request depot's request and its number of freighters. The new depot asks for the freighters (as a ghost request), and construction robots, or you by hand, bring them. This works for liquid depots too.
- Cloned depots keep their request.

## Good to know

- Freighters need no fuel yet.
- A freighter destroyed on the road is lost.
- Cargo keeps its data on the way: armor keeps its equipment, food how far it has spoiled.
- Requests are for normal-quality items.
- By default, provider depots are red, request depots blue, buffer depots green and the fuel depot amber. Every color can be changed.
