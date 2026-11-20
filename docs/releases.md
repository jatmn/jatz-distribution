# Releases

Release Please follows the same workflow as [yuoki-quinityn](https://github.com/jatmn/yuoki-quinityn): ordinary changes merge to `main`, a bot prepares a release PR, and the maintainer reviews and merges that PR to publish. Versions rise by one patch per release (`always-bump-patch` in `.github/release-please-config.json`); the released version is in `.github/release-please-manifest.json`. Each release is published on GitHub and on the [Factorio Mod Portal](https://mods.factorio.com/mod/jatz-distribution).

## Prepare a release

Use Conventional Commit PR titles (`feat:`, `fix:`, `ci:`, etc.). Release Please generates `docs/CHANGELOG.md` for GitHub from merged commits. Player-facing notes belong in the separate Factorio `changelog.txt`. Ordinary pull requests do not edit that file, because every one of them would then conflict with the others. Each pull request adds its own file under `changelog/unreleased/`, named for the change, and the release workflow assembles those files. The file holds Factorio categories and entries only:

```text
  Bugfixes:
    - Describe the change players will notice.
```

Do not add `Version:` or `Date:` lines, and do not edit `changelog.txt` or another pull request's note file. Different files merge independently.

Do not change `info.json`, `.github/version.txt` or `.github/release-please-manifest.json` in ordinary feature PRs. Release Please updates all three together. The workflow reads the note files on main, writes them into `changelog.txt` on its verified same-repository release branch with the new version and UTC preparation date, and removes those files so the same note is not published again. Updated notes on main refresh the release PR while preserving its first preparation date. A release with no player-facing notes gets an explicit entry saying so.

Review both changelogs and the successful `CI result` before merging the release PR. Merging it authorizes the stable `vX.Y.Z` tag, GitHub release, ZIP and `SHA256SUMS`, the Mod Portal upload and the portal page sync. The release workflow calls publishing directly; it does not depend on a tag-triggered workflow.

## Required GitHub credential

Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new), owned by the maintainer and restricted to **jatmn/jatz-distribution**. Give it repository permissions **Contents: Read and write**, **Issues: Read and write**, and **Pull requests: Read and write**. Store it in this repository's Actions secrets as `RELEASE_PLEASE_TOKEN`; rotate it before expiration. Never put the token in a commit, issue, PR or log.

The dedicated token lets release PR pushes trigger normal CI. The workflow deliberately has no `GITHUB_TOKEN` fallback, and the repository's default Actions token remains read-only with PR creation/approval disabled. Its absence or expiry should fail preparation, rather than produce a release PR whose checks cannot run. Allow the SHA-pinned `googleapis/release-please-action` in the repository's Actions policy, alongside the existing approved actions.

## Build and validate locally

```sh
python3 tools/test_releases.py
python3 tools/test_portal_page.py
python3 tools/portal_page.py --check
python3 tools/package_mod.py
python3 tools/validate_package.py
```

These are the commands CI's **Installable package** job runs.

The packager includes runtime code, game sprites, Factorio notes and all licence notices. It excludes tools, tests, documentation, Blender sources and previews. ZIP timestamps and modes are fixed and `SHA256SUMS` records the archive digest. Pending notes produce a numeric next-patch development snapshot without changing source version files; a stable publish rejects pending notes and requires its tag to match all version records.

CI's **Installable package** job builds and validates the complete package when the mod, repository tooling or artwork (`assets/*` art or its records) changes, and is part of `CI result`. On the release PR, Release Please's own commit raises the version records before the Release workflow finalizes `changelog.txt`, so CI skips the package check for that commit alone, with a notice, and runs it on the finalizing commit that follows. In the merge queue, the same hold applies if merging the same-repository release branch into the queue's base produces exactly the group's tree and only the unfinalized release metadata has changed. Pushes to `main` always validate the package. Packaging tests exercise small fixture assets; the CI package job validates the actual committed game sprites. Neither is a substitute for the Factorio gameplay checks required for gameplay changes.

## Factorio Mod Portal publishing

The publish workflow uploads each release to the Mod Portal with `tools/publish_mod.py`, using the Actions secret `FACTORIO_API_KEY`. The key is set for this repository. It is an API key from the maintainer's [Factorio profile](https://factorio.com/profile) with **Upload Mods**, **Publish Mods** and **Edit Mods** (for keeping the page in step with [`portal/`](../portal/README.md)) permissions; replace the secret when you rotate the key. Without the secret, GitHub publication still succeeds and both portal steps skip.

The listing uses a custom licence on the portal describing this package's mixed terms: project code and artwork are LGPL-3.0-only; the included Yuoki road sprites remain CC BY-NC-SA 4.0. The repository Actions variable `FACTORIO_LICENSE_ID` holds its ID, `custom_` followed by the code at the end of that licence's edit page address (`https://mods.factorio.com/licenses/edit/<code>`); it is set for this repository. The uploader needs it only to create a listing, and never changes an existing listing's licence. Keep `COPYING`, `COPYING.LESSER`, `NOTICE` and the road artwork's `Licence.txt` in every package.

The uploader validates the same ZIP used by GitHub, uses the API key only for initialization, and verifies the portal's filename and SHA-1 after uploading. It reads the listing past the portal's 15-minute CDN cache, which would otherwise still show the listing from before the upload. A matching existing version is a successful retry; differing bytes or a newer published version stop the upload. API behavior is tested with simulated responses.

## The Mod Portal page

The portal page lives in [`portal/`](../portal/README.md): the short summary, the Markdown description and the screenshot gallery. After the package upload, the publish workflow runs `tools/portal_page.py --tag <tag>` on the same tag (with `FACTORIO_API_KEY`), which changes only what differs from the live page, and sends nothing when the page is unchanged. Relative links in the description become GitHub URLs pinned to the tag. It only syncs the release the portal serves: it refuses a tag older than the portal's newest release, and one not uploaded yet, since the page would link to it. A dry run can still preview an unpublished tag, and a missing key skips the sync like the upload. Preview a sync without a key, before merging the release PR:

```sh
python3 tools/portal_page.py --tag vX.Y.Z --dry-run
```

Add `--print` to also print the summary and description as the portal gets them. CI's **Installable package** job runs `tools/portal_page.py --check` (no network) and `tools/test_portal_page.py`, with the API simulated.

## Retry an existing release

Run **Actions → Release → Run workflow** on `main` and put the existing tag, such as `v0.1.1`, in `tag`. Leaving it blank runs Release Please instead.

Retries require an existing stable, published GitHub release whose tag is in main's history. They rebuild that exact tag, upload missing assets and compare existing assets byte-for-byte; they never overwrite an asset. This also retries a failed portal upload and the page sync. If existing bytes differ, investigate rather than replacing them or moving the tag. No nightly release or automatic release-PR merge is configured.
