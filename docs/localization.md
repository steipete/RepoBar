# Localization

RepoBar ships English (`en`) and Turkish (`tr`) resources for the app, `RepoBarCore`, and `repobarcli`. English is the fallback language. App localization normally follows the macOS language selection. CLI localization follows the process locale and can be selected deterministically with `REPOBAR_LANGUAGE=en` or `REPOBAR_LANGUAGE=tr`.

Only human-readable output is localized. Command and option names, settings keys, URLs, API values, and JSON keys and values are stable contracts and must remain locale-independent. New visible strings belong in the target's `Localizable.strings` files and should be accessed through that target's localizer. Format visible dates and numbers with the localizer's locale; keep machine-readable dates and numbers unchanged.

`Scripts/package_app.sh` copies all three SwiftPM resource bundles into the packaged app so the embedded CLI and shared core can resolve their own catalogs.
