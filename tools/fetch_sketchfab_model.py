#!/usr/bin/env python3
"""Download a Sketchfab model as a Godot-ready asset, with attribution recorded.

Refuses any license that is not CC0 or CC-BY, so a non-commercial or
no-derivatives model can never reach the project by accident.

Usage: download.py <uid> <target_dir>

The model is unpacked into <target_dir> with the archive's directory structure
INTACT — glTF resolves its .bin and textures by relative URI, so flattening the
zip silently breaks every texture. Each model gets its own folder so two
assets in the same category cannot collide on a shared `textures/` path.
"""
import json
import os
import sys
import urllib.request
import zipfile

TOKEN = os.environ.get("SKETCHFAB_TOKEN", "")
API = "https://api.sketchfab.com/v3"
ALLOWED = {"cc0", "by"}


def _get(url, binary=False):
    req = urllib.request.Request(url, headers={"Authorization": f"Token {TOKEN}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read() if binary else json.load(r)


def main(uid, target_dir):
    meta = _get(f"{API}/models/{uid}")
    lic = (meta.get("license") or {})
    slug = lic.get("slug")
    if slug not in ALLOWED:
        print(f"REFUSED: license '{slug}' ({lic.get('label')}) is not CC0/CC-BY")
        return 1
    name = meta.get("name")
    author = (meta.get("user") or {}).get("displayName")
    viewer = f"https://sketchfab.com/3d-models/{uid}"
    print(f"  {name} | {lic.get('label')} | by {author}")

    dl = _get(f"{API}/models/{uid}/download")
    # Prefer the glTF option: it is the only format Godot imports losslessly
    # alongside the original, and it carries the original textures.
    entry = (dl.get("gltf") or {})
    if not entry.get("url"):
        print("  ! no gltf download available")
        return 1
    print(f"  downloading {entry.get('size', 0)/1e6:.1f} MB ...")

    tmp = f"/tmp/opencode/dl_{uid}.zip"
    # The URL is a pre-signed CDN link: it must be fetched WITHOUT the
    # Authorization header, which invalidates the signature.
    req = urllib.request.Request(entry["url"])
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as fh:
        fh.write(r.read())

    # Unpack the glTF zip, preserving the directory structure that the .gltf's
    # relative URIs depend on.
    os.makedirs(target_dir, exist_ok=True)
    with zipfile.ZipFile(tmp) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            # Reject path traversal before writing anything.
            rel = info.filename.replace("\\", "/").lstrip("/")
            if ".." in rel.split("/"):
                print(f"  ! refusing unsafe archive path: {info.filename}")
                return 1
            dest = os.path.join(target_dir, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, "wb") as dst:
                dst.write(src.read())

    # Normalise the entry-point name to model.gltf so SPECS paths are stable.
    # Safe: a .gltf references its .bin/textures by URI, not by its own name.
    gltfs = []
    for root, _dirs, files in os.walk(target_dir):
        for f in files:
            if f.lower().endswith(".gltf"):
                gltfs.append(os.path.join(root, f))
    if not gltfs:
        print("  ! no .gltf entry point found after extraction")
        return 1
    gltfs.sort(key=len)
    entry_point = gltfs[0]
    canonical = os.path.join(target_dir, "model.gltf")
    if os.path.abspath(entry_point) != os.path.abspath(canonical):
        os.replace(entry_point, canonical)
    print(f"  -> {canonical}")

    record = {
        "uid": uid,
        "name": name,
        "author": author,
        "license": lic.get("label"),
        "license_slug": slug,
        "url": viewer,
        "attribution": f"{name} by {author} - {lic.get('label')} - {viewer}",
    }
    rec_path = os.path.join(target_dir, "ATTRIBUTION.json")
    with open(rec_path, "w") as fh:
        json.dump(record, fh, indent=2)
    print(f"  attribution -> {rec_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
