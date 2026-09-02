# UsageDeck

Track your AI coding subscriptions from the macOS menu bar.

UsageDeck shows how much of your AI coding plans you have used: session and weekly limits,
credits, and spend, all in one popover. Pin the metrics you care about straight into the menu bar.

> UsageDeck is a fork of [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers,
> used under the MIT License. It is not affiliated with or endorsed by OpenUsage.
> See [ATTRIBUTION.md](ATTRIBUTION.md).

## Installation

Download the latest universal DMG from the
[releases page](https://github.com/MuhammadAli511/usagedeck-app/releases/latest), open it, and drag
UsageDeck to your Applications folder.

The app updates itself in place via signed, notarized [Sparkle](docs/updates.md) updates.
Requires macOS 15 (Sequoia) or later.

## Supported providers

- **[Antigravity](docs/providers/antigravity.md)**: shared Gemini and Claude pool quotas, 5-hour and weekly windows
- **[Claude](docs/providers/claude.md)**: session, weekly, model-specific limits, extra usage, local daily spend
- **[Codex](docs/providers/codex.md)**: session, weekly, credits, local daily spend
- **[Copilot](docs/providers/copilot.md)**: AI credits, extra usage, organization billing, chat and completions
- **[Cursor](docs/providers/cursor.md)**: credits, total usage, Grok Bot, Cursor Models, Other Models, requests, on-demand, per-day spend
- **[Devin](docs/providers/devin.md)**: weekly and daily quota, extra usage balance
- **[Grok](docs/providers/grok.md)**: weekly shared pool, pay-as-you-go, local daily spend
- **[OpenCode](docs/providers/opencode.md)**: Go session, weekly and monthly caps, Zen spend, local daily spend
- **[OpenRouter](docs/providers/openrouter.md)**: credit balance, daily, weekly and monthly spend (API key)
- **[Z.ai](docs/providers/zai.md)**: session, weekly, web-search quotas (GLM Coding Plan, API key)

Most providers read the credentials already on your machine (keychain, auth files, app state), so
there is no extra login. OpenRouter and Z.ai are the exceptions: they have no local credential to
reuse, so you supply an API key. Credentials are used only for the corresponding provider requests.

## Features

- **Menu bar pins.** Pin metrics to the menu bar (up to 2 per provider), rendered as compact text or mini bars. Metrics with no data are hidden rather than shown as placeholders.
- **Dashboard popover.** Provider-grouped meters with live reset countdowns and pace indicators. Click a usage or reset value to flip its display everywhere; right-click a row to hide or star it, refresh its provider, or open Customize.
- **Global shortcut.** Toggle the popover from anywhere. Record any combination in Settings.
- **Customize.** Turn providers and metrics on or off, choose which rows stay Always Visible or On Demand, and drag to reorder both.
- **Stale-while-revalidate.** Cached values display instantly at launch; refresh runs every 5 minutes.
- **[One-shot CLI](docs/cli.md).** Agents can read stable limit JSON through the same five-minute cache with `usagedeck`, or bypass freshness with `usagedeck --force`. The menu bar app does not need to be running.
- **[Local HTTP API](docs/local-http-api.md).** Other apps can read machine-friendly limits from `127.0.0.1:6736/v1/limits`. Loopback only, and it never serves credentials.
- **[Proxy support](docs/proxy.md).** Route provider requests through SOCKS5 or HTTP(S) via `~/.usagedeck/config.json`.
- **Native settings.** Launch at login, global shortcut, icon style, theme, density, 12 or 24-hour time. See [Settings](docs/settings.md).
- **[Automatic updates](docs/updates.md).** Signed, notarized in-app updates via Sparkle, with an optional beta channel.

## Documentation

Behavior docs live in [docs/](docs/README.md): the [dashboard](docs/dashboard.md),
[menu bar pins](docs/menu-bar.md), [settings](docs/settings.md),
[refresh and caching](docs/refreshing.md), the [CLI](docs/cli.md), the
[local HTTP API](docs/local-http-api.md), the [proxy](docs/proxy.md), and one page per provider.

For working on the code: [architecture](docs/architecture.md),
[adding a provider](docs/adding-a-provider.md), and [debugging](docs/debugging.md).

## Requirements

- macOS 15 (Sequoia) or later
- Universal binary, running natively on both Apple Silicon and Intel Macs

Spend tiles are computed natively from local CLI logs (Claude, Codex, Grok) or Cursor's usage
export, with no Node.js or other runtime needed. Dollars are estimated with
[dynamically refreshed model pricing](docs/pricing.md).

## Building

```sh
swift build                   # debug build
swift test                    # run the test suite
./script/build_and_run.sh     # build and launch the dev app from dist/ (no install)
```

The dev build uses its own bundle identifier (`org.vantaso.usagedeck.dev`), so it never disturbs an
installed release build.

### App icon

`assets/AppIcon.icon` is an Icon Composer source, and `actool` crashes compiling it on Xcode 26.4
and later (Apple regression FB20183399), including on GitHub's macOS runners. Both build scripts
therefore fall back to the prebuilt icon in `assets/AppIcon.prebuilt/`.

`AppIcon.icns` there is generated by `python3 script/make_icns.py`, which draws the mark directly
and needs only `iconutil`, so it works on any Mac. Regenerate and commit it whenever the mark
changes. `script/compile_icon.sh` still produces the richer Liquid Glass `Assets.car`, but only on a
Mac whose `actool` predates the regression.

## Releasing

UsageDeck ships from tags: pushing a `v*` tag on `main` builds a universal binary, signs it, and
publishes a DMG to GitHub Releases. Versions start at **v0.1.0** and are independent of OpenUsage's.

The pipeline degrades rather than blocking. A release cut today produces a working, ad-hoc signed
DMG; adding the Apple and Sparkle credentials later upgrades the same pipeline to a signed,
notarized, auto-updating build with no other change.

Distribution to other Macs needs a paid Apple Developer Program membership, which is not yet set up.
Full runbook, the state of every credential, and how to cut a release: [docs/releasing.md](docs/releasing.md).

## Architecture

SwiftPM package, SwiftUI content hosted in an AppKit-owned `NSStatusItem` plus a custom
key-capable `NSPanel`, Swift 6 strict concurrency. The app and CLI share one module: providers
implement a small `ProviderRuntime` protocol (auth store, usage client, mapper, `ProviderSnapshot`)
and both surfaces read the same normalized data. See the
[architecture overview](docs/architecture.md) and [AGENTS.md](AGENTS.md).

Note that the internal Swift module and `Sources/OpenUsage/` path are inherited from upstream and
kept unchanged on purpose, so that merges from upstream stay tractable. See
[ATTRIBUTION.md](ATTRIBUTION.md#what-the-fork-retains).

## License

[MIT](LICENSE). Original work copyright Robin Ebers, modifications copyright Muhammad Ali.
See [ATTRIBUTION.md](ATTRIBUTION.md).
