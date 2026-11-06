# Releases

Release Please follows the same workflow as [yuoki-quinityn](https://github.com/jatmn/yuoki-quinityn): ordinary changes merge to `main`, a bot prepares a release PR, and the maintainer reviews and merges that PR to publish. This repository starts at `0.1.0` and uses patch increments. Installing this automation does not itself publish a game release.

## Prepare a release

Use Conventional Commit PR titles (`feat:`, `fix:`, `ci:`, etc.). Release Please generates `docs/CHANGELOG.md` for GitHub from merged commits. Player-facing notes belong in the separate Factorio `changelog.txt`. Add an entry above the existing numbered history, using exactly 99 dashes for each separator:

```text
---------------------------------------------------------------------------------------------------
Version: Unreleased
  Bugfixes:
    - Describe the change players will notice.
```

Do not change `info.json`, `.github/version.txt` or `.github/release-please-manifest.json` in ordinary feature PRs. Release Please updates all three together. The workflow finalizes player notes on its verified same-repository release branch with the new version and UTC preparation date. Updated main-branch player notes refresh the release PR while preserving its first preparation date. A release with no player-facing notes gets an explicit entry saying so.

Review both changelogs and the successful `CI result` before merging the release PR. Merging it authorizes the stable `vX.Y.Z` tag, GitHub release, ZIP and `SHA256SUMS`, and the optional portal upload if connected. The release workflow calls publishing directly; it does not depend on a tag-triggered workflow.

## Required GitHub credential

Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new), owned by the maintainer and restricted to **jatmn/jatz-distribution**. Give it repository permissions **Contents: Read and write**, **Issues: Read and write**, and **Pull requests: Read and write**. Store it in this repository's Actions secrets as `RELEASE_PLEASE_TOKEN`; rotate it before expiration. Never put the token in a commit, issue, PR or log.

The dedicated token lets release PR pushes trigger normal CI. The workflow deliberately has no `GITHUB_TOKEN` fallback, and the repository's default Actions token remains read-only with PR creation/approval disabled. Its absence or expiry should fail preparation, rather than produce a release PR whose checks cannot run. Allow the SHA-pinned `googleapis/release-please-action` in the repository's Actions policy, alongside the existing approved actions.

## Build and validate locally

```sh
python3 tools/package_mod.py
python3 tools/validate_package.py
python3 tools/test_releases.py
```

The packager includes runtime code, game sprites, Factorio notes and all licence notices. It excludes tools, tests, documentation, Blender sources and previews. ZIP timestamps and modes are fixed and `SHA256SUMS` records the archive digest. Pending notes produce a numeric next-patch development snapshot without changing source version files; a stable publish rejects pending notes and requires its tag to match all version records.

CI builds and validates the complete package when mod, repository tooling or artwork changes. On the release PR, Release Please's own commit raises the version records before the Release workflow finalizes `changelog.txt`, so CI skips the package check for that commit alone, with a notice, and runs it on the finalizing commit that follows. Packaging tests exercise small fixture assets; the CI package job validates the actual committed game sprites. Neither is a substitute for the Factorio gameplay checks required for gameplay changes.

## Optional Factorio Mod Portal publishing

With no `FACTORIO_API_KEY`, GitHub publication succeeds and the portal step explicitly skips. To enable uploads, create an API key in your [Factorio profile](https://factorio.com/profile), with **Upload Mods** permission, **Publish Mods** for creating the first listing and **Edit Mods** for keeping the page in step with [`portal/`](../portal/README.md), and store it as the Actions secret `FACTORIO_API_KEY`.

Before the first listing, create a custom licence on the portal describing this package's mixed terms: project code and artwork are LGPL-3.0-only; the included Yuoki road sprites remain CC BY-NC-SA 4.0. Set the repository Actions variable `FACTORIO_LICENSE_ID` to `custom_` followed by the code at the end of that licence's edit page address (`https://mods.factorio.com/licenses/edit/<code>`), such as `custom_6aee33da2a59c98152d81dc1`; it is set for this repository. Keep `COPYING`, `COPYING.LESSER`, `NOTICE` and the road artwork's `Licence.txt` in every package. The uploader refuses first publication without an explicit custom licence and does not change an existing listing's licence.

The uploader validates the same ZIP used by GitHub, uses the API key only for initialization, and verifies the portal's filename and SHA-1 after uploading. A matching existing version is a successful retry; differing bytes or a newer published version stop the upload. API behavior is tested with simulated responses; enabling the optional key is the point at which real portal publication becomes authorized by merging a release PR.

## The Mod Portal page

The portal page lives in [`portal/`](../portal/README.md): the short summary, the Markdown description and the screenshot gallery. After the package upload, the publish workflow runs `tools/portal_page.py --tag <tag>` on the same tag, which changes only what differs from the live page, and sends nothing when the page is unchanged. Relative links in the description become GitHub URLs pinned to the tag. It refuses a tag older than the portal's newest release, and a missing key skips it like the upload. Preview a sync without a key, before merging the release PR:

```sh
cd tools && python3 portal_page.py --tag vX.Y.Z --dry-run
```

The package CI job runs `tools/portal_page.py --check` and `tools/test_portal_page.py`, with the API simulated. On the first publication the portal briefly shows `info.json`'s description, until the sync that follows replaces it.

## Retry an existing release

Run **Actions → Release → Run workflow** on `main` and put the existing tag, such as `v0.1.1`, in `tag`. Leaving it blank runs Release Please instead.

Retries require an existing stable, published GitHub release whose tag is in main's history. They rebuild that exact tag, upload missing assets and compare existing assets byte-for-byte; they never overwrite an asset. This also retries a failed or newly enabled portal upload and the page sync. If existing bytes differ, investigate rather than replacing them or moving the tag. No nightly release or automatic release-PR merge is configured.
