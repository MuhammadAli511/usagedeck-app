# Attribution

UsageDeck is a fork of [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers,
used under the [MIT License](LICENSE). The original copyright notice is retained in `LICENSE`
alongside the copyright covering modifications made in this fork.

UsageDeck is **not** affiliated with, endorsed by, or an official part of OpenUsage.

## Trademark compliance

The OpenUsage name, logo and visual identity are trademarks of Robin Ebers and are not covered
by the MIT license. OpenUsage publishes a
[trademark policy](https://github.com/robinebers/openusage/blob/main/TRADEMARK.md) setting out
what a fork must do. This fork complies with all three requirements:

| Requirement | How UsageDeck complies |
| --- | --- |
| Choose a different name | The product, repository, binary, bundle identifier and CLI are all named UsageDeck. |
| Remove the OpenUsage logo and branding | The OpenUsage mark and app icon are deleted and replaced with an original UsageDeck mark. No OpenUsage artwork ships in this repository. |
| State that this is a fork | Declared here, in the README, and in the app's own About panel. |

No domain or social account uses the OpenUsage name.

## What the fork retains

For maintainability, the internal Swift package name, target names and `Sources/OpenUsage/`
directory are unchanged from upstream. This is deliberate: it keeps merges from upstream
tractable and touches nothing a user ever sees. These are internal build identifiers, not
product branding. Everything user-facing (app name, menu items, About panel, app icon, menu bar
mark, bundle identifier, CLI name, file system paths, log subsystem) is UsageDeck.

## Upstream contributors

The original work is by Robin Ebers, with contributions from Mert, David, and the OpenUsage
contributor community. Their work is credited in the app's About panel and preserved in this
repository's git history, which retains every upstream commit.

## Staying current with upstream

This repository tracks `robinebers/openusage` as the `upstream` git remote. Upstream changes are
merged in periodically. Push to `upstream` is disabled locally.

```sh
git fetch upstream
git merge upstream/main
```
