# DraftRoom — Flutter + Rust + PostgreSQL

A working first version of an MLBB drafting and coaching app. Mobile UI is Flutter/Dart. The API and authoritative online recommendation engine are Rust/Axum. Accounts, teams, catalogs, draft history and notes persist in PostgreSQL through SQLx migrations.

## Included

- Five picks and five manual bans on both teams; duplicate and unknown heroes are rejected by both app and API.
- A searchable roster of all 133 Original Server heroes, including Hirara, Marcel, Sora, Obsidia, Zetian and Kalea.
- Explainable emblem, battle-spell, matchup and playstyle prompts. Minotaur rules consider the other frontline, enemy burst and explicit Balanced / Survival / Tempo preferences.
- English and Myanmar advice, playbook, coach notes, JSON copy/import and copyable Markdown briefs.
- Lineup-specific win conditions and named teamfight jobs: protect a carry, poke, pick off, coordinate dives or sustain. Playbook switches between Blue and Red; enemy anti-dash, sustain and suppression add actionable responses. Online and offline share the same bilingual rules.
- Offline practice with a bundled catalog and a small Dart companion engine. Online advice is calculated by Rust. Labels identify which engine answered.
- Password accounts with Argon2 hashes and expiring opaque session tokens. Mobile tokens use platform secure storage; only token hashes are stored on the server.
- Personal and team drafts. Owners invite coaches or read-only viewers with one-use, 24-hour codes.
- Optimistic revision checks, save-as-copy conflict recovery, archive and restore.
- Immutable patch catalog import, Docker Compose, a Render deployment blueprint and CI for Rust, Flutter and PostgreSQL integration.

## Start the backend

Install Docker Desktop / Docker Compose, or use the non-Docker path below.

1. Copy `.env.example` to `.env`. Set a random hexadecimal `POSTGRES_PASSWORD`; use the same password in `DATABASE_URL` for direct Rust development.
2. From this directory run:

```sh
docker compose up --build
```

The API is at `http://localhost:8080`; `GET /health` verifies the database. Migrations, the historical 104-hero baseline and the current 133-hero catalog are applied on startup. PostgreSQL data lives in a named Docker volume. The API and database ports bind to your local machine.

### Without Docker

Use an existing PostgreSQL database, including a hosted PostgreSQL provider. Set `DATABASE_URL` in `backend/.env` or in the process environment. For hosted databases preserve the provider's TLS connection options. Then:

```sh
cd backend
cargo run --locked
```

By default the server allows Flutter web at `http://localhost:5173` and `http://127.0.0.1:5173`. Set `APP_ORIGINS` to a comma-separated list of your exact web origins when hosting. Native mobile clients are not subject to browser CORS.

## Run Flutter

Install the stable Flutter SDK and development tools for your target platform, then:

```sh
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` reaches the host machine from an Android emulator. For iOS Simulator use `http://localhost:8080`. For a hosted backend use its HTTPS URL. The URL can also be entered in the app's Settings screen. With no URL the app opens in offline practice mode.

For a desktop browser:

```sh
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8080
```

Release mobile builds require HTTPS. Local cleartext networking is enabled only in the Android debug manifest. Secure token persistence on web requires HTTPS or localhost; if unavailable, sign-in remains in memory for the current session. The generated Android release configuration uses a development signing key until you configure your own signing credentials. iOS builds and signing require macOS/Xcode and an Apple development identity.

## Use it

1. Tap a pick or ban slot; search/filter a hero and select it. Tap the small remove icon to clear a pick; long-press a ban to clear it.
2. Change the coaching focus, priority or advice language. Review the explanation, alternatives, matchup prompts and game plan.
3. Configure the Rust API and create an account. Create a team or join using an invitation code if needed.
4. Save to a personal or team workspace. Open saved drafts from Sessions. Viewer drafts can be copied to your personal workspace.
5. If another coach saved first, your local changes are preserved. Use Save a new copy, or reopen the latest saved draft after copying your work.

Team rooms use explicit refresh in this version; there is no live WebSocket broadcast. Offline edits are cached locally but are **not** automatically uploaded. Deliberate save and revision checks prevent silent overwrites.

## Catalog and recommendation quality

Roster coverage, sources, inference limits and upgrade behavior are recorded in `docs/roster-update.md`. `python3 scripts/check_catalog.py` guards the exact manifest, unique profiles and online/offline parity.

`data/catalog.json` is the versioned seed source; `mobile/assets/catalog.json` is its offline copy. The 133-name roster was cross-checked on 7 November 2026; the catalog remains **review required** for live balance and optimal-build claims. Suggested lanes, utility tags and talent pages are coaching assumptions, not verified live balance data. Physical/magic counts both include mixed-damage profiles, so those columns are not mutually exclusive. Most hero emblem pages are generic role templates; Minotaur has more specific scenario rules. Scores are not win rates or guaranteed counters.

Lineup plans use deterministic composition rules rather than a generative AI service or win predictor. `data/playbook_rules.json` supplies the ordered strategy conditions, hero-name templates and contextual advice for both runtimes. After edits run `python3 scripts/generate_playbook.py`; CI checks the generated Dart copy. Missing picks keep plans provisional; bans never count as actors. No gold, item, cooldown, player-skill or current match-state information is available to the planner.

To add a reviewed catalog, copy the seed shape, assign a **new** patch ID, edit its profiles and review metadata, then import it against the running database:

```sh
cd backend
cargo run --locked --bin import_catalog -- ../data/your-new-catalog.json
```

Existing catalog IDs cannot be overwritten. Old drafts retain their patch ID. This app release upgrades cached baseline working drafts to the 133-hero catalog while retaining picks, bans and notes. Saved server drafts retain their historical patch. The Settings catalog-upgrade action creates a new working copy without clearing the lineup. Keep `reviewed` false until you have checked the relevant game-client effects and draft assumptions.

Background references are included in Settings. They may describe older patches. This project does not connect to an official MLBB API, ingest live balance patches, simulate damage/items, enforce a current tournament draft sequence, or guarantee permission to use phones at an event.

## Checks

CI uses Flutter 3.47.9 and uploads a web build and debug APK as downloadable workflow artifacts.

```sh
cargo test --manifest-path backend/Cargo.toml --locked
cd mobile
flutter analyze
flutter test
flutter build web --release
```

Against an **isolated test** API/database run `python3 scripts/smoke.py http://localhost:8080`. It creates disposable users, teams and drafts. CI runs the integration suite against PostgreSQL 16 and builds Flutter web and a debug APK. Local verification results and platform limits are recorded in `docs/verification.md`.

## Deployment

The preview backend is deployed in Render's Singapore region:

- API base URL: https://draftroom-api-0tyr.onrender.com
- Health check: https://draftroom-api-0tyr.onrender.com/health
- Android CI builds include the hosted API URL by default. Settings still allows a custom API URL or explicit offline practice. Connection startup allows extra time for a Free service cold start.
- PostgreSQL 16 is connected over Render's private network. Database credentials are supplied by a Blueprint reference and external database access is disabled.
- Both resources use Free compute plans. The current Free database expires on **7 December 2026 at 14:52 UTC**; upgrade or migrate before expiry to keep using its data. Free web services sleep after inactivity and can take time to wake.
- Verified on 7 November 2026: database-backed health check, seeded catalog (104 heroes at initial deployment; upgraded to 133 in this release), Rust recommendations, unauthenticated draft access rejection, and invalid analysis request rejection. These checks do not create user accounts or saved drafts.

`render.yaml` provisions the Docker API and PostgreSQL together. For a separately deployed Flutter web frontend, set `APP_ORIGINS` to its exact HTTPS origin. The default empty value supports native Flutter clients without allowing browser cross-origin requests. No credentials are embedded in the source. Use an appropriate always-on service and persistent database plan for time-sensitive shared drafting.

The Flutter web build is a separate static artifact in `mobile/build/web`. Android/iOS distribution requires your own package signing and store accounts. Password reset, email verification, public-registration quotas, membership revocation, account deletion and realtime broadcasts are future production-hardening work; this version is for controlled coach testing.
