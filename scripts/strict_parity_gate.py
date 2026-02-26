#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib import parse, request

PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "greenmotionapp-33413.firebasestorage.app")

BASE_DIR = os.path.dirname(__file__)
MAP_PATH = os.path.join(BASE_DIR, "franchise-migration-map.json")
OUT_PATH = os.path.join(BASE_DIR, "strict-parity-gate-report.json")


def get_access_token():
    return subprocess.check_output(
        ["gcloud", "auth", "print-access-token"], text=True
    ).strip()


def http_json(url, token):
    req = request.Request(
        url,
        method="GET",
        headers={"Authorization": f"Bearer {token}"},
    )
    with request.urlopen(req, timeout=180) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


def list_documents(collection_path, token):
    docs = []
    page_token = None
    base = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}"
        f"/databases/(default)/documents/{parse.quote(collection_path)}"
    )
    while True:
        url = f"{base}?pageSize=300"
        if page_token:
            url += f"&pageToken={parse.quote(page_token)}"
        payload = http_json(url, token)
        docs.extend(payload.get("documents", []))
        page_token = payload.get("nextPageToken")
        if not page_token:
            break
    return docs


def field_string(doc, key):
    return (doc.get("fields", {}).get(key, {}) or {}).get("stringValue")


def gsutil_object_count(path):
    cmd = f"gsutil ls -r \"{path}/**\" | awk '!/\\/$/' | wc -l | xargs"
    out = subprocess.check_output(["bash", "-lc", cmd], text=True).strip()
    return int(out or "0")


def main():
    token = get_access_token()
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)
    domain_collections = migration_map.get("domainFirestoreCollections", [])
    strict_collections = [c for c in domain_collections if c != "userPresence"]
    storage_prefixes = migration_map.get("storagePrefixes", [])

    franchise_docs = list_documents("franchises", token)
    franchise_ids = sorted(
        {
            (field_string(doc, "franchiseId") or doc["name"].rsplit("/", 1)[-1]).upper()
            for doc in franchise_docs
        }
    )

    firestore_results = []
    firestore_ok = True
    for collection in strict_collections:
        legacy_docs = list_documents(collection, token)
        legacy_by_franchise = {}
        for doc in legacy_docs:
            fid = (field_string(doc, "franchiseId") or "").upper()
            if not fid:
                continue
            legacy_by_franchise[fid] = legacy_by_franchise.get(fid, 0) + 1

        for fid in franchise_ids:
            scoped_docs = list_documents(f"franchises/{fid}/{collection}", token)
            legacy_count = legacy_by_franchise.get(fid, 0)
            scoped_count = len(scoped_docs)
            match = legacy_count == scoped_count
            firestore_ok = firestore_ok and match
            firestore_results.append(
                {
                    "collection": collection,
                    "franchiseId": fid,
                    "legacyCount": legacy_count,
                    "scopedCount": scoped_count,
                    "match": match,
                }
            )

    storage_results = []
    storage_ok = True
    for prefix in storage_prefixes:
        legacy_count = gsutil_object_count(f"gs://{BUCKET_NAME}/{prefix}")
        scoped_total = 0
        for fid in franchise_ids:
            scoped_total += gsutil_object_count(
                f"gs://{BUCKET_NAME}/franchises/{fid}/{prefix}"
            )
        match = legacy_count == scoped_total
        storage_ok = storage_ok and match
        storage_results.append(
            {
                "prefix": prefix,
                "legacyCount": legacy_count,
                "scopedTotal": scoped_total,
                "match": match,
            }
        )

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "bucketName": BUCKET_NAME,
        "franchiseIds": franchise_ids,
        "firestoreOk": firestore_ok,
        "storageOk": storage_ok,
        "allOk": firestore_ok and storage_ok,
        "firestoreResults": firestore_results,
        "storageResults": storage_results,
    }
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Report written: {OUT_PATH}")
    print(f"allOk={report['allOk']}")


if __name__ == "__main__":
    main()
