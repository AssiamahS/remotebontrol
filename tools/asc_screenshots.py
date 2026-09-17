#!/usr/bin/env python3
"""Replace the en-US iPhone 6.7"/6.9" screenshot set on the editable version with the given PNGs.

usage: asc_screenshots.py shots/01-feed.png shots/02-board.png ...
"""
import hashlib
import os
import sys
import urllib.request

from asc_common import api, must, version_id, version_localization

DISPLAY = "APP_IPHONE_67"
ALLOWED = {(1290, 2796), (1320, 2868), (2796, 1290), (2868, 1320)}


def normalize(path):
    """ASC only takes exact sizes; scale to 1290x2796 if the simulator gave something else."""
    from PIL import Image
    im = Image.open(path)
    if im.size in ALLOWED:
        return path
    out = path[:-4] + "-67.png"
    im.convert("RGB").resize((1290, 2796), Image.LANCZOS).save(out)
    print(f"  resized {im.size} -> 1290x2796")
    return out


def screenshot_set(loc_id):
    st, r = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    must(st, r, "screenshot sets")
    for d in r["data"]:
        if d["attributes"]["screenshotDisplayType"] == DISPLAY:
            return d["id"]
    st, r = api("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    return must(st, r, "create screenshot set")["data"]["id"]


def clear(set_id):
    st, r = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    must(st, r, "list screenshots")
    for d in r["data"]:
        api("DELETE", f"/v1/appScreenshots/{d['id']}")
    print(f"  cleared {len(r['data'])} old screenshot(s)")


def upload(set_id, path):
    data = open(path, "rb").read()
    st, r = api("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    must(st, r, f"reserve {path}")
    sid = r["data"]["id"]
    for op in r["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        # the upload URL is pre-signed storage: send ONLY Apple's headers, no Bearer token
        hdrs = {h["name"]: h["value"] for h in op["requestHeaders"]}
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers=hdrs)
        try:
            with urllib.request.urlopen(req) as resp:
                resp.read()
        except urllib.error.HTTPError as e:
            raise SystemExit(f"chunk upload failed: {e.code} {e.read()[:300]!r}")
    st, r = api("PATCH", f"/v1/appScreenshots/{sid}", {"data": {
        "type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    must(st, r, f"commit {path}")
    print(f"  uploaded {os.path.basename(path)} ({len(data)//1024} KB)")


def main(paths):
    vid, attrs = version_id()
    print(f"version {attrs['versionString']} ({attrs['appStoreState']}) id={vid}")
    loc = version_localization(vid)
    set_id = screenshot_set(loc)
    clear(set_id)
    for p in sorted(paths):
        upload(set_id, normalize(p))
    print("done")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    main(sys.argv[1:])
