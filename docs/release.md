---
summary: "RepoBar release checklist: versioning, Sparkle appcast, signing/notarization, and verification."
read_when:
  - Preparing or validating a RepoBar release
  - Running package_app/notarize scripts or checking release assets
  - Changing auth storage or keychain entitlements
---

# Release checklist (RepoBar)

Keep `TMPDIR` set to a private, writable directory for release commands. Packaging uses unique temporary paths for the notarization key, submission archive, and signing entitlements, and removes them when the command exits.

## ✅ Standard Release Flow (RepoBar/VibeTunnel parity)
1) **Version + changelog**
   - Update `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
   - Finalize the top section in `CHANGELOG.md` (no “Unreleased”; header must start with the version).

2) **Run the full release script**
   - `Scripts/release.sh`
   - Builds, signs, notarizes, generates appcast entry + HTML notes from `CHANGELOG.md`, publishes GitHub release, tags/pushes.
   - Shared release helper is resolved by `Scripts/mac-release`; set `MAC_RELEASE_TOOL` or keep `agent-scripts` next to this repo.

3) **Sparkle UX verification**
   - About → “Check for Updates…”
   - Menu only shows “Update ready, restart now?” once the update is downloaded.
   - Sparkle dialog shows formatted release notes (not escaped HTML).
   - Verify the released app does **not** include `RepoBarTokenStore=file`.
   - Verify the packaged `LSMinimumSystemVersion` and generated appcast minimum are both `15.0`.
   - Verify `keychain-access-groups` is present only if the app is signed with a matching provisioning profile. Otherwise leave `REPOBAR_SKIP_KEYCHAIN_GROUPS` at the release default (`1`) to avoid AMFI launch failures.

## Manual steps (only when re-running pieces)
1) Debug smoke build/tests  
   - `Scripts/compile_and_run.sh`
   - Debug bundles use file-backed auth (`RepoBarTokenStore=file`) so local launches do not prompt for Keychain access.

2) Package + notarize  
   - `Scripts/package_app.sh [debug|release]`
   - Optional notarization: `NOTARIZE=1 NOTARY_PROFILE="Xcode Notary" Scripts/package_app.sh release`
   - Packaging exits with the failing command's status if signing or requested notarization fails; resolve the error before distributing the bundle.
   - Verify: `spctl --assess --verbose .build/release/RepoBar.app`
   - Inspect release auth storage: `plutil -p .build/release/RepoBar.app/Contents/Info.plist | rg RepoBarTokenStore` should print nothing.

3) Release notes (markdown)
   - `Scripts/generate-release-notes.sh <version> > RELEASE_NOTES.md`

4) Post-publish asset check  
   - `Scripts/check-release-assets.sh <tag>` (zip + dSYM present)
