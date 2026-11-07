# Lineup coaching

The Game plan tab, Playbook and copied brief now use both teams' selected heroes to choose a composition plan. The Playbook identifies the analyzed team and lets the coach switch between Blue and Red.

Each plan supplies a win condition, teamfight jobs with the relevant heroes named, opening coordination, objective setup and conditional enemy responses. Incomplete lineups remain provisional. An empty own lineup asks for picks rather than inventing a strategy. Bans never become actors.

The ordered rules favor protecting available sustained damage when multiple enemy divers can reach it, then poke, pick-off, dive follow-up, sustain and coordinated trades. These are conservative tag-based interpretations; grouping a hero under control or sustain is not a damage simulation or skill-by-skill matchup assessment. The planner does not connect to an LLM, predict a win probability, read a live match or promise a win.

## Maintaining the rules

1. Edit `data/playbook_rules.json`, keeping the final unconditional fallback.
2. Run `python3 scripts/generate_playbook.py` to embed the same data in Dart.
3. Add representative scenarios in `data/fixtures/playbook_cases.json`.
4. Run Rust and Flutter checks. `cargo run --manifest-path backend/Cargo.toml --example playbook_export` and `dart scripts/playbook_export.dart`, from the repository root, export the same scenario outputs for byte-independent JSON comparison.

Both languages render the same placeholders and count the same tagged hero groups. Plans intentionally stay invariant when switching the focused role within one team; emblem suggestions remain role-specific.
