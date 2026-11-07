#!/usr/bin/env python3
"""Integration checks against an isolated API + PostgreSQL database. Not production."""
import json
import sys
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError

base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"
suffix = uuid.uuid4().hex[:12]

def call(method, path, body=None, token=None, expected=200):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = Request(base + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        with urlopen(req, timeout=25) as response:
            status, payload = response.status, response.read()
    except HTTPError as e:
        status, payload = e.code, e.read()
    result = json.loads(payload) if payload else None
    assert status == expected, (method, path, status, expected, result)
    return result

def account(role):
    return call("POST", "/v1/auth/register", {"email": f"{role}-{suffix}@example.test", "password": "test-only-password-2026", "display_name": role.title()})

assert call("GET", "/health")["status"] == "ok"
catalog = call("GET", "/v1/catalog")
assert len(catalog["heroes"]) == 133
assert len(call("GET", "/v1/catalog?patch_id=baseline-2026-11-07")["heroes"]) == 104
owner, viewer, coach, stranger = [account(r) for r in ("owner", "viewer", "coach", "stranger")]
ot, vt, ct, st = [a["token"] for a in (owner, viewer, coach, stranger)]
assert call("GET", "/v1/auth/me", token=ot)["id"] == owner["user"]["id"]
login = call("POST", "/v1/auth/login", {"email": f"owner-{suffix}@example.test", "password": "test-only-password-2026"})
assert login["user"]["id"] == owner["user"]["id"]
call("POST", "/v1/auth/login", {"email": f"owner-{suffix}@example.test", "password": "wrong-password"}, expected=401)
call("GET", "/v1/drafts", expected=401)
team = call("POST", "/v1/teams", {"name": "Disposable integration scrim"}, ot)
vc = call("POST", f"/v1/teams/{team['id']}/invites", {"role": "viewer"}, ot)["code"]
cc = call("POST", f"/v1/teams/{team['id']}/invites", {"role": "coach"}, ot)["code"]
call("POST", "/v1/teams/join", {"code": vc}, vt)
call("POST", "/v1/teams/join", {"code": vc}, st, expected=400)
call("POST", "/v1/teams/join", {"code": cc}, ct)
call("POST", f"/v1/teams/{team['id']}/invites", {"role": "coach"}, vt, expected=403)
draft = {"title": "Integration lineup", "patch_id": catalog["patch"]["id"], "notes": "Disposable test notes", "blue": {"name": "Blue", "picks": ["minotaur", "ling", None, "esmeralda", None], "bans": [None]*5}, "red": {"name": "Red", "picks": ["franco", "hayabusa", "valentina", None, "brody"], "bans": [None]*5}}
analysis = call("POST", "/v1/analyze", {"draft": draft, "side": "blue", "role_index": 0, "priority": "balanced", "language": "en"})
assert analysis["emblem"]["talents"][1] == "Pull Yourself Together"
assert any("Suppression" in threat["title"] for threat in analysis["threats"])
assert analysis["partial"] is True
assert analysis["strategy_id"].startswith("lineup-plan-1:")
assert any("Ling" in card["body"] for card in analysis["plan"])
call("POST", "/v1/analyze", {"draft": draft, "side": "blue", "role_index": 7, "priority": "balanced"}, expected=400)
personal = call("POST", "/v1/drafts", {"draft": draft, "team_id": None}, ot)
shared = call("POST", "/v1/drafts", {"draft": draft, "team_id": team["id"]}, ot)
assert shared["revision"] == 1
visible = call("GET", "/v1/drafts", token=vt)
assert any(d["id"] == shared["id"] and not d["can_edit"] for d in visible)
assert not any(d["id"] == personal["id"] for d in visible)
call("GET", f"/v1/drafts/{shared['id']}", token=st, expected=404)
call("PUT", f"/v1/drafts/{shared['id']}", {"draft": draft, "team_id": team["id"], "expected_revision": 1}, vt, expected=403)
call("POST", "/v1/drafts", {"draft": draft, "team_id": team["id"]}, vt, expected=403)
draft["notes"] = "Coach changed the plan"
updated = call("PUT", f"/v1/drafts/{shared['id']}", {"draft": draft, "team_id": team["id"], "expected_revision": 1}, ct)
assert updated["revision"] == 2
call("PUT", f"/v1/drafts/{shared['id']}", {"draft": draft, "team_id": team["id"], "expected_revision": 1}, ot, expected=409)
invalid = json.loads(json.dumps(draft))
invalid["red"]["bans"][0] = "minotaur"
call("POST", "/v1/drafts", {"draft": invalid, "team_id": None}, ot, expected=400)
archived = call("PUT", f"/v1/drafts/{shared['id']}/archive", {"archived": True, "expected_revision": 2}, ct)
assert archived["archived"] and archived["revision"] == 3
assert not any(d["id"] == shared["id"] for d in call("GET", "/v1/drafts", token=vt))
assert any(d["id"] == shared["id"] for d in call("GET", "/v1/drafts?archived=true", token=vt))
restored = call("PUT", f"/v1/drafts/{shared['id']}/archive", {"archived": False, "expected_revision": 3}, ot)
assert not restored["archived"] and restored["revision"] == 4
call("POST", "/v1/auth/logout", token=ot, expected=204)
call("GET", "/v1/auth/me", token=ot, expected=401)
print("PASS: auth lifecycle, private/team access, single-use invites, viewer restrictions, coach edits, stale revision rejection, duplicate validation, analysis, archive/restore.")
