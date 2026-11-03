# Concept art

These are the approved concept images that the Blender models were built from. They were generated with an AI image generator from text prompts, which are kept alongside them. The 3D models interpret the concepts' finer details and unseen surfaces, so the final sprites differ from them in places.

## Freighter

The approved Quinityn concept lives next to its model: [`assets/quinityn-freighter/source/approved-concept.png`](../assets/quinityn-freighter/source/approved-concept.png), with its prompt and a modeling turnaround in the same folder.

## Depots

| Depot | Concept |
| --- | --- |
| Provider | [images/provider.png](depots/images/provider.png) |
| Request | [images/request.png](depots/images/request.png) |
| Buffer | [images/buffer.png](depots/images/buffer.png) |
| Fuel | [images/fuel.png](depots/images/fuel.png) |
| Liquid Provider | [images/liquid-provider.png](depots/images/liquid-provider.png) |
| Liquid Request | [images/liquid-request.png](depots/images/liquid-request.png) |
| Liquid Buffer | [images/liquid-buffer.png](depots/images/liquid-buffer.png) |

[`depots/prompts.json`](depots/prompts.json) holds the prompts. Liquid Provider was regenerated with [a revised prompt](depots/liquid-provider-final-prompt.txt).

The final models changed some concept details at the owner's direction:
- broad automated manifolds replace the manual valves and hose reels;
- every cargo depot uses Provider's circular roof;
- each fluid depot has a single tank;
- all four rotations are supported, with pipe ports that turn with the building.

## Design references

The visual style draws on the Yuoki Industries mods, mainly the storage containers and tanks in [Yuoki-Factorio-2.x](https://github.com/jatmn/Yuoki-Factorio-2.x/tree/2372d6c1e933bd95e4437fa1f3003b9d53b69eea) and [Yuoki-Engines-Factorio-2.x](https://github.com/jatmn/Yuoki-Engines-Factorio-2.x/tree/3fc8761858e6d8d592ec1978ca51f7a57d44e882). Red, blue and green follow Yuoki's provider, requester and buffer colors; amber marks fuel. The concept prompts describe this style in words, and no Yuoki artwork is copied into this repository.
