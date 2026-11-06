# Mod Portal page

This folder is the mod's page on the [Factorio Mod Portal](https://mods.factorio.com/mod/jatz-distribution). Each release brings the live page in line with it. Nothing here goes into the mod package.

| File | On the portal |
| --- | --- |
| `summary.txt` | The short summary, shown in mod listings and search. 500 characters at most |
| `description.md` | The long description on the mod's page, in Markdown |
| `gallery/` | The screenshot gallery, in filename order (`01-depots.png`, `02-fuel.jpg`, ...). PNG or JPEG, 5 MiB at most each |
| `images/` | Pictures used inside `description.md` only. They are not uploaded to the gallery |
| `README.md` | This file. Not published |

## Writing the description

Link to files in this repository with paths relative to this folder, such as `images/quinityn-freighter.png`, `../docs/guide.md#fuel` or `../assets/depots/provider/3/previews/four-directions.png`, so the page previews correctly on GitHub. For the portal, `tools/portal_page.py` turns them into GitHub URLs pinned to the release tag: pictures (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`) as raw image URLs, other files as GitHub pages. Each release's page keeps showing that release's pictures even after they change on `main`.

- Use inline links (`[text](path)`). Reference-style links and paths with spaces are refused, since they wouldn't be rewritten.
- Every linked file must be committed, or GitHub can't serve it.
- The portal doesn't render HTML, so use Markdown only.
- Keep pictures for the description reasonably small (well under 1 MB where possible): every visitor downloads them.

`images/quinityn-freighter.png` is the freighter's hero render, `assets/quinityn-freighter/masters/hero-default-palette.png`, trimmed and scaled for the page:

```sh
convert assets/quinityn-freighter/masters/hero-default-palette.png -trim +repage -resize 760x760 \
  -depth 8 -strip -define png:compression-level=9 portal/images/quinityn-freighter.png
```

Make it again whenever the freighter's art changes. The other pictures come from in-game screenshots (Factorio 2.1.24, graphical client):

| Picture | Made from |
| --- | --- |
| `freighters-on-the-road.gif` | 14 seconds of a gameplay recording, cropped to the road, 800 px wide at 15 fps (`ffmpeg ... palettegen=max_colors=128:stats_mode=diff`, then `paletteuse` with `diff_mode=rectangle`) |
| `depots-on-road.jpg`, `fuel-depot-flush.jpg` | `gallery/01-depots-on-road.png` and `gallery/09-fuel-depot-flush.png`, 1000 px wide, JPEG quality 88 to 90 |
| `recipes-*.jpg` | Factoriopedia screenshots of each recipe, cropped to the right-hand panel and set side by side (`montage -tile x1`), JPEG quality 92 |
| `milestones.png` | The chat message Milestones prints when it loads our milestones |

The recipe sheets show the recipes and descriptions as they are in game, so take them again whenever a recipe, a crafting time or an entity description changes.

## The gallery

Each file in `gallery/` is uploaded once. The portal names images by their SHA-1, so an unchanged file is never uploaded again, and renaming files only changes their order. Removing a file removes it from the live gallery at the next sync. While `gallery/` is empty or missing, the live gallery is left alone, so screenshots uploaded by hand on the portal survive until the folder has some.

The gallery has every depot on the road, each depot's window, the road network monitor and our Factoriopedia row. Screenshots that would still add to it (graphical client, default graphics settings, no debug overlays):

1. Freighters at work in a real factory, rather than on lab tiles.
2. A request depot's window with a request set and freighters out: the "out" count, fuel line and green status light.
3. Loaded freighters in different cargo colors, with alt mode on to show their cargo icons.
4. A freighter stopping at a fuel depot, with its fuel shown on hover.
5. The technology tree.
6. A freighter driving through biters.

## Checking and previewing

```sh
cd tools
python3 portal_page.py --check                       # the rules above; CI runs this too
python3 portal_page.py --check --print               # the summary and description as the portal will get them
python3 portal_page.py --tag v0.1.1 --dry-run        # what a sync would change on the live page (no API key needed)
```

## How it reaches the portal

The **Publish stable mod** workflow (`.github/workflows/publish.yml`) uploads a release's package, then runs `python3 tools/portal_page.py --tag <tag>` from that same tag. It compares the live page with this folder and changes only what differs: the summary and description through the [Mod details API](https://wiki.factorio.com/Mod_details_API), and the gallery through the [Mod images API](https://wiki.factorio.com/Mod_images_API). An unchanged page sends nothing.

So changes here reach the portal with the next release. Retrying a release (**Actions → Release** with an existing tag) syncs the page as it was in that tag. The sync refuses to replace the page from a tag older than the portal's newest release.

It needs `FACTORIO_API_KEY` to have the **ModPortal: Edit Mods** permission as well as the upload permissions; see [docs/releases.md](../docs/releases.md). Without the key, it is skipped like the upload.
