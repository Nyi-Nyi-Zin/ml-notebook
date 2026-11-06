# Verification — 7 November 2026 (Myanmar time)

## Checks rerun for the GitHub source handoff

| Check | Observed result |
| --- | --- |
| Rust engine tests | 9 passed. |
| Rust formatting and Clippy, all targets with warnings denied | Passed. |
| Flutter static analysis | Passed; no issues. |
| Flutter tests | 14 passed: 6 engine/model tests, 2 phone/desktop layout tests and 6 async workspace tests. |
| Flutter web release | Built successfully with Flutter 3.47.9 / Dart 3.13.7. Wasm compiler dry-run also passed. |
| Rust API + database integration | Passed registration, login/logout, authentication, personal/team isolation, one-use invites, viewer restrictions, coach edits, stale revisions, duplicate heroes, analysis, archive and restore. |
| Seed catalog consistency | Bundled Flutter catalog matches the Rust seed source. |

The integration check used a fresh, isolated **PGlite PostgreSQL WASM database over the PostgreSQL wire protocol**, SQLx migrations and a single pool connection. It exercised the actual Rust HTTP API. Native PostgreSQL 16 execution is configured in GitHub Actions; hosted CI results must be checked after push.

The async fixes prevent a delayed draft-open response from overwriting a new draft or notes typed while loading. Cloud refresh responses are ignored after account/endpoint changes and when a newer refresh has already started. Sign-out waits for queued local cache writes before removing the cached draft.

The earlier implementation session also visually checked the compiled web draft board and Minotaur emblem panel. This handoff reran the layout tests and release build; it did not repeat that browser visual inspection.

The web build emits a non-fatal missing Cupertino font notice. The app uses Material icons.

## Not verified here

- Docker image build and native PostgreSQL server execution: Docker was unavailable, and native PostgreSQL installation was blocked by this environment's package filesystem restrictions.
- Android APK build/install and physical-device behavior: the Android SDK/emulator was not provisioned. CI includes a debug APK build and artifact upload.
- iOS build/signing/device behavior: requires macOS/Xcode and the owner's signing identity.
- A live external Rust API or hosted PostgreSQL database: no hosting account/database was provisioned. The static Flutter demo starts in offline practice mode.
- Live game patch validity, esports pick/ban rules, hero-specific optimality and real coach usability: these need game-client review and user feedback.
