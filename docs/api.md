# Rust API contract

JSON request/response bodies use snake_case. Session-protected endpoints accept `Authorization: Bearer <opaque-session-token>`. Tokens are valid for 14 days unless logged out. The API does not use cookies. Passwords are hashed with Argon2; tokens and invitation codes are stored as SHA-256 hashes.

| Method | Path | Access / behavior |
| --- | --- | --- |
| GET | `/health` | Public; checks a database query. |
| GET | `/v1/catalog` | Public; latest imported catalog. Optional `patch_id` selects an immutable snapshot. |
| POST | `/v1/analyze` | Public; validates the draft and returns explanations, emblem template, threats, plan and 8 composition-fit candidates. |
| POST | `/v1/auth/register` | Email, password (10–256 characters), display name. Returns user and session token. |
| POST | `/v1/auth/login` | Email/password; returns user and session token. |
| GET | `/v1/auth/me` | Signed-in profile. |
| POST | `/v1/auth/logout` | Revokes this token; returns 204. |
| GET / POST | `/v1/teams` | List memberships / create a team as owner. |
| POST | `/v1/teams/{id}/invites` | Owner only. `role` is `coach` or `viewer`. Returns a one-use code valid for 24 hours. |
| POST | `/v1/teams/join` | Signed-in user plus invitation `code`. |
| GET / POST | `/v1/drafts` | Accessible drafts / create a personal or writable team draft. GET supports `archived=true` and `team_id`. Returns up to 100 latest records. |
| GET / PUT | `/v1/drafts/{id}` | Read accessible draft / update with an exact expected revision. Team viewers cannot write. |
| PUT | `/v1/drafts/{id}/archive` | Editable drafts only. Body: `archived` and `expected_revision`. Supports restoring archived drafts. |

## Draft document

```json
{
  "title": "Scrim preparation",
  "patch_id": "baseline-2026-11-07",
  "blue": {
    "name": "Our team",
    "picks": ["minotaur", "ling", null, "esmeralda", null],
    "bans": [null, null, null, null, null]
  },
  "red": {
    "name": "Opponent",
    "picks": [null, null, null, null, null],
    "bans": [null, null, null, null, null]
  },
  "notes": "Coordinate the second angle."
}
```

Pick positions are fixed as **Roam, Jungle, Mid, EXP, Gold**. All picks and bans share a uniqueness constraint at API validation time. The board is a manual preparation tool, not a current tournament-format simulator.

Analysis body: `draft`, `side` (`blue` or `red`), `role_index` (0–4), `priority` (`balanced`, `survival`, `tempo`), and `language` (`en` or `mm`).

Analysis returns `strategy_id` (for example `lineup-plan-1:dive_followup`) and `plan`, an ordered array of localized `{title, body}` cards. A plan depends on both sides' picks and the selected `side`; `role_index` and `priority` continue to affect the emblem and candidates, rather than the whole-team strategy. The first matching strategy wins: awaiting own picks, protecting damage uptime against multiple divers, poke, pick-off, dive follow-up, sustain, then coordinated trades. Context cards describe missing frontline/control, relevant enemy answers and draft completeness. These are catalog-tag heuristics, not AI predictions. Unknown future strategy IDs should be displayed using their cards rather than rejected.

Save body: `draft`, `team_id` (UUID or null), and for updates `expected_revision`. A draft's workspace cannot be changed by updating it; save a copy to move it. Every accepted update/archive/restore increments the revision. A stale write returns 409 and never overwrites the newer revision.

Errors use `{"error":"Human-readable message"}` for handled API errors. Axum may return its standard rejection response for malformed JSON, unsupported content types or oversized request bodies. The client handles non-JSON failures without exposing internal details. Authentication endpoints have an in-process per-IP limit; deployments with several instances need shared rate limits and a trusted proxy strategy before public signup.
