"""Shared App Store Connect API client for the remotebontrol tools.

Auth comes from env (CI) or the Mac's key file:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_PATH
"""
import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

KEY_ID = os.environ.get("ASC_KEY_ID", "KB93R49B9J")
ISSUER = os.environ.get("ASC_ISSUER_ID", "9c44682c-3cc3-4791-bd10-a2d8935788db")
P8 = os.environ.get("ASC_P8_PATH", os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"))
APP_ID = os.environ.get("ASC_APP_ID", "6812974344")
BUNDLE_ID = "com.assiamah.remotebontrol"
BASE = "https://api.appstoreconnect.apple.com"

_token = None
_token_at = 0


def _b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


_offset = None


def clock_offset():
    """Mac clock drifts a day behind; Apple rejects JWTs minted in the past. Ask time.apple.com once."""
    global _offset
    if _offset is None:
        _offset = 0.0
        if os.environ.get("ASC_TIME_OFFSET"):
            _offset = float(os.environ["ASC_TIME_OFFSET"])
        else:
            try:
                out = subprocess.run(["sntp", "-t", "3", "time.apple.com"], capture_output=True, text=True, timeout=8).stdout
                for line in out.splitlines():
                    if "+/-" in line:
                        _offset = float(line.split()[0])
            except Exception:
                pass
    return _offset


def jwt():
    global _token, _token_at
    if _token and time.time() - _token_at < 900:
        return _token
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time() + clock_offset())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    si = f"{_b64url(json.dumps(header).encode())}.{_b64url(json.dumps(payload).encode())}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", P8],
                         input=si.encode(), capture_output=True, check=True).stdout
    i = 2
    rl = der[i + 1]
    r = der[i + 2:i + 2 + rl]
    i += 2 + rl
    sl = der[i + 1]
    s = der[i + 2:i + 2 + sl]
    sig = r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")
    _token, _token_at = f"{si}.{_b64url(sig)}", time.time()
    return _token


def api(method, path, body=None, raw=None, headers=None):
    url = path if path.startswith("http") else BASE + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = {"Authorization": f"Bearer {jwt()}"}
    if raw is None:
        h["Content-Type"] = "application/json"
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        txt = e.read()
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, {"raw": txt.decode(errors="replace")}


def must(status, body, what):
    if status >= 300:
        raise SystemExit(f"{what}: HTTP {status}\n{json.dumps(body, indent=1)[:1500]}")
    return body


def version_id(platform="IOS"):
    st, r = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}&limit=5")
    must(st, r, "list versions")
    for d in r["data"]:
        if d["attributes"]["appStoreState"] not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE"):
            return d["id"], d["attributes"]
    raise SystemExit("no editable app store version found")


def version_localization(vid, locale="en-US"):
    st, r = api("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    must(st, r, "version localizations")
    for d in r["data"]:
        if d["attributes"]["locale"] == locale:
            return d["id"]
    st, r = api("POST", "/v1/appStoreVersionLocalizations", {"data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {"locale": locale},
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    return must(st, r, "create version localization")["data"]["id"]


def app_info_id():
    st, r = api("GET", f"/v1/apps/{APP_ID}/appInfos")
    must(st, r, "appInfos")
    for d in r["data"]:
        if d["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"):
            return d["id"]
    return r["data"][0]["id"]


def app_info_localization(aid, locale="en-US"):
    st, r = api("GET", f"/v1/appInfos/{aid}/appInfoLocalizations")
    must(st, r, "appInfoLocalizations")
    for d in r["data"]:
        if d["attributes"]["locale"] == locale:
            return d["id"]
    st, r = api("POST", "/v1/appInfoLocalizations", {"data": {
        "type": "appInfoLocalizations",
        "attributes": {"locale": locale},
        "relationships": {"appInfo": {"data": {"type": "appInfos", "id": aid}}}}})
    return must(st, r, "create appInfoLocalization")["data"]["id"]
