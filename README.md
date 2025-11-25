# RepoBar 🚦 — CI, PRs, releases—at a glance

macOS menubar app (Swift 6.2, Xcode 26) that surfaces GitHub repo health at a glance: CI state, open issues/PRs, latest release, recent comments, traffic uniques, and a custom commit heatmap. MenuBarExtraAccess distinguishes left/right clicks; Sparkle handles updates; PKCE browser-based login supports GitHub.com and GitHub Enterprise.

## Quick start

```bash
pnpm install          # only needed once for scripts
pnpm check            # swiftformat + swiftlint (autofix)
pnpm test             # swift test
pnpm start            # build, test, launch menubar app
pnpm stop             # quit running debug app
pnpm codegen          # (optional) run Apollo codegen once schema access is set
```

Requirements: Swift 6.2 toolchain, Xcode 26+, `swiftformat`, `swiftlint`, `pnpm` (v10+), and `apollo-ios` CLI if you run codegen.

## Auth setup

1. In GitHub App settings, set callback `http://127.0.0.1:53682/callback`; ensure repo permissions include Actions/Checks/Contents/Issues/PRs/Admin (traffic).  
2. In RepoBar Preferences → Accounts, paste Client ID/Secret, private key path, optional Enterprise base URL (https only).  
3. Sign in; browser opens; loopback captures the code; tokens stored in Keychain.

## Notes

- Menubar icon is a tinted, macOS-native template glyph with a tiny status badge for aggregate CI/login state.
- Left click opens rich repo grid; right click opens classic menu (Refresh, Preferences, Updates, Logout, Quit).
- Pins reorder via drag or card menu; display count and refresh interval configurable in Settings.
- Advanced tab shows diagnostics (API host, last error, rate-limit reset).

## Repo hygiene

- Keep files <500 LOC; prefer extraction to helpers.
- Run `pnpm check && pnpm test` before committing.
- Codegen artifacts are not generated yet; run `pnpm codegen` only when you have GitHub schema access.
