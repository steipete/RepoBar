---
summary: "macOS Turkish localization, language selection, and presentation boundaries."
read_when:
  - Adding or changing localized macOS text
  - Packaging application localization resources
---

# Localization

RepoBar includes Turkish translations for its macOS menus and common Settings controls. It follows macOS language preferences, independently of the region used for dates and numbers. To choose Turkish for RepoBar alone, add RepoBar under **System Settings → General → Language & Region → Applications**, select Turkish, and restart RepoBar. Unsupported languages and untranslated text fall back to English.

The initial translation covers Settings tabs, repository visibility controls, Display customization, main menu actions, and common buttons. Some detailed settings, diagnostics, and dynamic status messages remain English.

SwiftUI literal labels use the main app catalog. AppKit titles and fixed String-backed SwiftUI labels use `AppLocalizer`. Keep the English and Turkish catalogs in `Sources/RepoBar/Resources/Localizations` aligned. Packaging installs both the SwiftPM module bundle and the main-bundle catalogs; verify the packaged app as well as unit tests.

Localize fixed presentation labels explicitly. Repository names, paths, URLs, settings values, shared errors, and all CLI output retain their existing contracts. There is no command-line language override. Do not translate completed output lines or shared serialized values.
