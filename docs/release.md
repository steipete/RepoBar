---
summary: "GitHub Actions releases: signed tags, notarized app and CLI, Sparkle, and Homebrew."
read_when:
  - Preparing or verifying a RepoBar release
  - Changing release automation
---

# Releasing RepoBar

RepoBar ships a universal macOS app ZIP (including `repobarcli`) and a matching
dSYM ZIP through GitHub Releases. Sparkle consumes `appcast.xml` on `main`;
`steipete/homebrew-tap` installs the same archive and exposes the bundled CLI as
`repobar`. The private `package.json` is development tooling, not an npm package.
The SwiftPM library and iOS target are source consumers, not additional release
binaries. No npm token or trusted publisher is required.

## Prepare and publish

1. Update `MARKETING_VERSION` and increment `BUILD_NUMBER` in `version.env`.
   Keep `package.json`'s version equal to `MARKETING_VERSION`.
2. Finalize one changelog section as `## X.Y.Z - YYYY-MM-DD`. Keep pending work
   under `Unreleased`; the release body is the dated section verbatim.
3. Land the preparation PR and wait for successful **push CI on that exact
   main commit**. The release workflow rejects PR-only or other-commit success.
4. Create a signed annotated `vX.Y.Z` tag with the authorized SSH signing key
   listed in `.github/release-signers`, then push it. Never move a release tag.
5. `.github/workflows/release.yml` validates the tag and versions, builds with
   Xcode 26.1, signs with Developer ID, notarizes and staples the app, generates
   the signed Sparkle enclosure, and verifies the downloaded immutable build
   in a separate job without signing secrets. Verification covers both CPU
   architectures, the bundled CLI, signing identity/runtime/timestamp,
   notarization, version metadata, dSYM UUIDs, and the Sparkle public key.
6. The publisher creates a draft, checks every downloaded asset and the notes,
   and publishes it once. It then commits the verified Sparkle item to `main`
   and updates the existing Homebrew cask with the verified ZIP checksum.

Existing releases (including drafts) are refused; there is no overwrite or
`--clobber` path. A failed draft is preserved for inspection. If a downstream
handoff fails after publication, repair that handoff explicitly; do not rerun
publishing or create a replacement version/tag.

## No-publish proof

Dispatch **Release** on `main` with `dry_run: true` (the default) and no tag.
It validates the current version's dated notes and exact push CI, builds,
signs, notarizes, and independently verifies everything. Outputs remain only
in the workflow's 14-day artifact. It creates no tag or GitHub Release and
changes neither the Sparkle feed nor Homebrew. To validate an existing signed
tag, supply `tag` while retaining `dry_run: true`. A dispatch with publishing
enabled requires an existing signed tag; it never creates one.

## Credentials

Repository secrets: `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8`, `SPARKLE_PRIVATE_KEY`,
`HOMEBREW_TAP_TOKEN`. The p12 must contain Peter Steinberger's Developer ID
Application certificate (team `Y5PE65HELJ`); the Sparkle private key must match
the app's existing `AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=` public key.
The tap token needs Contents read/write on `steipete/homebrew-tap` only.
Signing material is scoped to the build job and removed before artifacts are
uploaded. The verifier receives no signing or publishing credentials.

## Local verification

`Scripts/generate-release-notes.sh`, `Scripts/check-release-assets.sh`, and
`Scripts/verify_appcast.sh` remain available. Local packaging scripts remain for
diagnosis; use the existing managed `mac-release codesign-run` helper for local
Developer ID signing. Publishing and appcast mutation now belong to Actions;
the former `Scripts/release.sh` and `Scripts/make_appcast.sh` are removed.
