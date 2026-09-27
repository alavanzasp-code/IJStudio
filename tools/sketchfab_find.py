#!/usr/bin/env python3
"""Curated Sketchfab model finder.

Only surfaces licenses that are safe to ship in a commercial game:
  CC0 (public domain) and CC-BY (attribution required, recorded in the manifest).
Everything else — CC-BY-NC*, CC-BY-ND, Sketchfab "Free Standard", etc — is
rejected outright, because non-commercial terms would block a release.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

TOKEN = os.environ.get("SKETCHFAB_TOKEN", "")
API = "https://api.sketchfab.com/v3"
# Sketchfab license slugs we accept. Anything else is off-limits.
ALLOWED = {"cc0", "cc-by", "by"}


def search(query, licenses=("cc0", "cc-by"), count=24, animated=None):
    params = {
        "type": "models",
        "downloadable": "true",
        "q": query,
        "count": str(count),
        "sort_by": "-likeCount",
    }
    params["license"] = licenses[0]
    if animated is not None:
        params["animated"] = "true" if animated else "false"
    url = f"{API}/search?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"Authorization": f"Token {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r).get("results", [])
    except urllib.error.HTTPError as exc:
        print(f"  ! search '{query}' license={licenses[0]} -> HTTP {exc.code}")
        return []


def detail(uid):
    """Model detail carries the authoritative license + author."""
    req = urllib.request.Request(
        f"{API}/models/{uid}", headers={"Authorization": f"Token {TOKEN}"}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def report(query, animated=None, limit=12, min_tris=0, max_tris=200000):
    print(f"\n{'='*78}\nQUERY: {query!r}" + (f"  (animated={animated})" if animated is not None else "") + f"\n{'='*78}")
    seen = set()
    rows = 0
    # Sketchfab's CC-BY slug is "by"; CC0 is "cc0".
    for lic in ("cc0", "by"):
        for m in search(query, licenses=(lic,), animated=animated):
            uid = m.get("uid")
            if not uid or uid in seen:
                continue
            seen.add(uid)
            try:
                d = detail(uid)
            except Exception as exc:  # noqa: BLE001
                print(f"  ! detail failed {uid}: {exc}")
                continue
            slugs = d.get("license", {}) or {}
            slug = slugs.get("slug", "?")
            label = slugs.get("label", "?")
            if slug not in ALLOWED:
                continue
            face = d.get("faceCount", 0) or 0
            if face < min_tris or face > max_tris:
                continue
            user = d.get("user", {}) or {}
            print(
                f"  [{slug:>5}] {d.get('name','?')[:44]:46} "
                f"tris={face:>8,} anim={d.get('animationCount',0)} "
                f"by {user.get('displayName','?')[:20]:22} {uid}"
            )
            rows += 1
            if rows >= limit:
                return
    if rows == 0:
        print("  (no acceptable-license results)")


if __name__ == "__main__":
    queries = sys.argv[1:] or ["arrow"]
    for q in queries:
        report(q)
