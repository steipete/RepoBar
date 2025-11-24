# Release checklist (RepoBar)

1) Build, sign, and run tests  
   - `Scripts/compile_and_run.sh` (debug smoke build, installs Info.plist, codesigns with default dev identity, runs tests).

2) Package (release/debug)  
   - `Scripts/package_app.sh [debug|release]`  
     - Copies `Resources/Info.plist` into the app bundle.  
     - Codesigns using `CODESIGN_IDENTITY`/`CODE_SIGN_IDENTITY` if set.

3) Notarize (optional but recommended for distribution)  
   - Export a keychain profile for notarytool (e.g., “Xcode Notary”).  
   - `NOTARIZE=1 NOTARY_PROFILE="Xcode Notary" Scripts/package_app.sh release`  
     or call directly: `Scripts/notarize_app.sh .build/release/RepoBar.app "Xcode Notary"`.

4) Staple & verify (if notarized)  
   - `xcrun stapler staple .build/release/RepoBar.app` (already run by the script).  
   - `spctl --assess --verbose .build/release/RepoBar.app`

5) Final sanity
   - Launch the notarized app once, verify menubar icon, Preferences window, and update check.
   - Keep Apollo concurrency warning acknowledged; no other warnings should remain.
