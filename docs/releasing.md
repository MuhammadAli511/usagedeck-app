# Releasing

UsageDeck ships from tags. Pushing a `v*` tag on `main` runs
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which builds a universal binary,
signs it, attaches a DMG to a GitHub Release, and updates the Sparkle appcast on GitHub Pages.

## Version scheme

Semantic versioning, starting at **v0.1.0**. This line is UsageDeck's own and is deliberately
independent of OpenUsage's: the two projects ship different features on different schedules, and
implying otherwise would be misleading.

| Tag | Channel | Who gets it |
| --- | --- | --- |
| `v0.1.0` | stable | everyone |
| `v0.1.0-beta.1` | beta | only users who opted into the beta channel |

The tag is the single source of truth. `CFBundleShortVersionString` comes from it, and
`CFBundleVersion` is the git commit count, which is monotonic. Never reuse or move a published tag:
Sparkle clients cache by version, and the appcast is append-only.

## What works today, and what does not

The pipeline is deliberately degrading. Each signing step is conditional on its secret, so a release
can be cut now and becomes fully distributable the moment the credentials exist. Nothing else about
the build changes.

| Capability | State | Needs |
| --- | --- | --- |
| Universal build, DMG, GitHub Release | works now | nothing |
| Gatekeeper-clean install on other Macs | **blocked** | paid Apple Developer Program membership, then a Developer ID Application certificate |
| Notarization | **blocked** | the same membership, plus an app-specific password |
| Sparkle auto-updates | **blocked** | an EdDSA key pair (free, see below) |
| iCloud Sync in release builds | **blocked** | an `iCloud.org.vantaso.usagedeck` container and its provisioning profile |

Without a Developer ID certificate the DMG is **ad-hoc signed**. It runs on the machine that built
it, and other Macs refuse it with "cannot be opened because the developer cannot be verified". That
is a hard Apple requirement, not something the pipeline can work around: notarization requires the
paid membership.

## One-time setup

### 1. Sparkle key pair (free, do this first)

Auto-updates need an EdDSA key pair. It has nothing to do with Apple and costs nothing.

```sh
swift package resolve
find .build/artifacts -type f -name generate_keys -exec {} \;
```

It prints a public key and stores the private key in your login keychain. Export the private key
with the `-x` flag, then set both as repository secrets:

- `SPARKLE_PUBLIC_KEY` - baked into the build as `SUPublicEDKey`
- `SPARKLE_PRIVATE_KEY` - used to sign each DMG

They must be a matching pair or the appcast job fails its own signature check. Until both are set,
the appcast steps are skipped and releases simply carry no auto-update.

### 2. Apple Developer Program (paid, unlocks distribution)

Join at [developer.apple.com](https://developer.apple.com/programs/), then:

1. Create a **Developer ID Application** certificate and export it from Keychain Access as a `.p12`
   with its private key. `base64 -i DeveloperID.p12 | pbcopy` gives you `APPLE_CERTIFICATE`; the
   export password is `APPLE_CERTIFICATE_PASSWORD`.
2. Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) under Sign-In
   and Security. That is `APPLE_PASSWORD`; your Apple ID email is `APPLE_ID`.
3. Your team ID from the developer portal is `APPLE_TEAM_ID`.

### 3. iCloud container (optional, for iCloud Sync)

Create `iCloud.org.vantaso.usagedeck` under your team, generate a Developer ID provisioning profile
that includes it, and set the base64 of that profile as `APPLE_DEVELOPER_ID_ICLOUD_PROFILE`. Without
it the build still succeeds and simply ships without iCloud Sync.

### 4. GitHub Pages

The appcast is served from the `gh-pages` branch. Confirm Settings, Pages points at it after the
first release that generates an appcast.

### 5. Crash symbolication (optional)

`POSTHOG_CLI_API_KEY` and `POSTHOG_CLI_PROJECT_ID` upload dSYMs so crash reports symbolicate. A
missing key never blocks a release; stack traces just show raw addresses.

## Cutting a release

1. Make sure `main` is green and every change you want is merged.
2. Move the `## Unreleased` entries in [`CHANGELOG.md`](../CHANGELOG.md) under a new `## v0.1.0`
   heading and commit.
3. Tag and push:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

4. Watch the run with `gh run watch -R MuhammadAli511/usagedeck-app`.
5. Verify the published release has a DMG asset and, once Sparkle keys are set, that the version
   appears in the appcast.

To rehearse locally without publishing anything:

```sh
USAGEDECK_VERSION=0.1.0 ./script/release.sh
```

That produces `dist/UsageDeck-0.1.0.dmg`, ad-hoc signed and unnotarized, and warns about everything
it skipped.

## Gotchas

- `gh` in this repository resolves to the `upstream` remote unless you pass
  `-R MuhammadAli511/usagedeck-app`. Always pass it for release commands.
- The appcast is append-only. The workflow aborts rather than let the item count shrink, so older
  installs and the other channel keep working.
- `actool` cannot compile the Icon Composer source on Xcode 26.4 and later, so the build falls back
  to `assets/AppIcon.prebuilt/`. See the README's icon section.
