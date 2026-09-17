#!/usr/bin/env python3
"""Attach the newest processed build to the editable version and (optionally) submit for review.

  asc_submit.py            attach latest VALID build, set export compliance
  asc_submit.py --submit   ...and create the review submission
  asc_submit.py --wait     poll up to 30 min for a build to finish processing first
"""
import sys
import time

from asc_common import APP_ID, api, must, version_id


def latest_build(wait):
    deadline = time.time() + (1800 if wait else 0)
    while True:
        st, r = api("GET", f"/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=3"
                           "&fields[builds]=version,processingState,uploadedDate,usesNonExemptEncryption")
        must(st, r, "builds")
        for d in r["data"]:
            if d["attributes"]["processingState"] == "VALID":
                return d
        if time.time() > deadline:
            states = [(d["attributes"]["version"], d["attributes"]["processingState"]) for d in r["data"]]
            raise SystemExit(f"no VALID build yet: {states}")
        print("  build still processing, waiting 60s...")
        time.sleep(60)


def main():
    submit = "--submit" in sys.argv
    wait = "--wait" in sys.argv
    vid, attrs = version_id()
    print(f"version {attrs['versionString']} ({attrs['appStoreState']})")
    b = latest_build(wait)
    bid = b["id"]
    print(f"build {b['attributes']['version']} VALID, uploaded {b['attributes']['uploadedDate']}")

    if b["attributes"].get("usesNonExemptEncryption") is None:
        st, r = api("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                                                         "attributes": {"usesNonExemptEncryption": False}}})
        print(f"  export compliance: HTTP {st}")

    st, r = api("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": bid}})
    must(st, r, "attach build")
    print(f"  attached build {b['attributes']['version']} to {attrs['versionString']}")

    if not submit:
        print("not submitting (pass --submit)")
        return

    st, r = api("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    if st == 409:
        st, r = api("GET", f"/v1/reviewSubmissions?filter[app]={APP_ID}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&limit=1")
        must(st, r, "find open submission")
        sub = r["data"][0]["id"]
    else:
        sub = must(st, r, "create review submission")["data"]["id"]
    st, r = api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if st != 409:
        must(st, r, "add version to submission")
    st, r = api("PATCH", f"/v1/reviewSubmissions/{sub}", {"data": {
        "type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})
    must(st, r, "submit")
    print("SUBMITTED for review")


if __name__ == "__main__":
    main()
