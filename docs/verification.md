# Verification — 7 November 2026 (Myanmar time)

## Latest continuation: lineup plans

| Check | Observed result |
| --- | --- |
| Rust tests | 14 passed, including shared lineup fixtures and opponent-dependent strategy changes. |
| Rust formatting and Clippy, all targets with warnings denied | Passed. |
| Rust/Dart plan parity | All 20 outputs (10 scenarios in English and Myanmar) matched exactly, including named actors, provisional drafts, empty teams and Red-side analysis. |
| Standalone Dart analysis | No issues in the new planner, generated rules or scenario exporter. |
| Catalog and generated-rule checks | Passed; 133-hero catalogs remain unchanged. |
| Flutter format, analysis and tests | 35 tests passed in GitHub Actions, including the 10 new bilingual scenario tests with focus invariance and phone/desktop Playbook side-switch checks. |
| Web release | Built successfully in GitHub Actions. |
| Android build5 | Built successfully. Downloaded archive matches the GitHub artifact SHA-256; extracted APK passes ZIP integrity checks and identifies `com.cloudnine.draftroom`, version `0.1.0`, versionCode `5`, minSdk `24`. APK SHA-256: `b42d47360e8828d5eda319c48c2b83754e539c4843738ca17229cb3244707247`. |
| Hosted rollout | Render deploy `dep-dbnlvb8473hc739pqce0` is live at source commit `8389f27567162950b1b1ad3fb0f9d3df6bda808f`. Database health and all 20 bilingual API plan scenarios passed against the public endpoint. These checks did not create accounts or saved drafts. |

Validation workflow: https://github.com/Nyi-Nyi-Zin/ml-notebook/actions/runs/42396460398

Local browser inspection was attempted, but Chromium was absent and its pinned browser download returned an invalid ZIP archive. Phone/desktop interaction coverage comes from the passing Flutter widget tests. Physical Android installation and iOS execution remain unverified.

Build5 uses a different debug signing certificate from build4, so Android cannot install it as an in-place update over build4. Before uninstalling, save local drafts to the cloud or copy their JSON. Then uninstall the old development build, install build5 and sign in again. A stable owner-controlled release signing identity is still needed for normal upgrade distribution.

## Historical checks for the initial GitHub source handoff

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

## Historical limits of the initial source handoff

- Docker image build and native PostgreSQL server execution: Docker was unavailable, and native PostgreSQL installation was blocked by this environment's package filesystem restrictions.
- Android APK build/install and physical-device behavior: the Android SDK/emulator was not provisioned. CI includes a debug APK build and artifact upload.
- iOS build/signing/device behavior: requires macOS/Xcode and the owner's signing identity.
- A live external Rust API or hosted PostgreSQL database: no hosting account/database was provisioned. The static Flutter demo starts in offline practice mode.
- Live game patch validity, esports pick/ban rules, hero-specific optimality and real coach usability: these need game-client review and user feedback.
