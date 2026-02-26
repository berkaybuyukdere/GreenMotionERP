#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib import parse, request

PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "greenmotionapp-33413.firebasestorage.app")
PRIMARY_FRANCHISE = os.environ.get("PRIMARY_FRANCHISE", "CH")

BASE_DIR = os.path.dirname(__file__)
MAP_PATH = os.path.join(BASE_DIR, "franchise-migration-map.json")
OUT_PATH = os.path.join(BASE_DIR, "final-scoped-only-report.json")


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


def gsutil_count(path):
    cmd = f"gsutil ls -r \"{path}/**\" 2>/dev/null | awk '!/\\/$/' | wc -l | xargs"
    out = subprocess.check_output(["bash", "-lc", cmd], text=True).strip()
    return int(out or "0")


def main():
    token = get_access_token()
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)
    collections = migration_map.get("domainFirestoreCollections", [])
    storage_prefixes = migration_map.get("storagePrefixes", [])

    firestore_results = []
    firestore_ok = True
    for collection in collections:
        legacy_count = len(list_documents(collection, token))
        scoped_count = len(
            list_documents(f"franchises/{PRIMARY_FRANCHISE}/{collection}", token)
        )
        match = legacy_count == 0 and scoped_count >= 0
        # Require scoped existence only for collections that previously had CH data.
        if collection in {
            "araclar",
            "servisler",
            "iadeIslemleri",
            "exitIslemleri",
            "activities",
            "servisFirmalari",
            "office_operations",
            "office_Return",
            "assistantCompanies",
            "protocols",
            "shuttleEntries",
            "shuttleSessions",
            "shuttleReports",
            "semesInvoices",
            "userPresence",
        }:
            match = match and scoped_count > 0
        firestore_ok = firestore_ok and match
        firestore_results.append(
            {
                "collection": collection,
                "legacyCount": legacy_count,
                "scopedCount": scoped_count,
                "match": match,
            }
        )

    storage_results = []
    storage_ok = True
    for prefix in storage_prefixes:
        legacy_count = gsutil_count(f"gs://{BUCKET_NAME}/{prefix}")
        scoped_count = gsutil_count(f"gs://{BUCKET_NAME}/franchises/{PRIMARY_FRANCHISE}/{prefix}")
        match = legacy_count == 0
        if prefix in {
            "hasar_fotograflari",
            "iade_fotograflari",
            "exit_fotograflari",
            "office_operations",
            "office_Return",
            "kafa_kagitlari",
            "return_pdfs",
        }:
            match = match and scoped_count > 0
        storage_ok = storage_ok and match
        storage_results.append(
            {
                "prefix": prefix,
                "legacyCount": legacy_count,
                "scopedCount": scoped_count,
                "match": match,
            }
        )

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "primaryFranchise": PRIMARY_FRANCHISE,
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
