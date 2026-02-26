#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from urllib import parse, request


PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
DEFAULT_FRANCHISE_ID = os.environ.get("DEFAULT_FRANCHISE_ID", "ch")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "200"))
DRY_RUN = "--dry-run" in sys.argv

MAP_PATH = os.path.join(os.path.dirname(__file__), "franchise-migration-map.json")
REPORT_PATH = os.path.join(os.path.dirname(__file__), "firestore-backfill-report.json")


def get_access_token():
    return subprocess.check_output(
        ["gcloud", "auth", "print-access-token"], text=True
    ).strip()


def http_json(url, token, method="GET", payload=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = request.Request(url, method=method, headers=headers, data=data)
    with request.urlopen(req, timeout=120) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


def list_documents(collection, token):
    docs = []
    page_token = None
    base = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}"
        f"/databases/(default)/documents/{parse.quote(collection)}"
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


def commit_writes(writes, token):
    if not writes:
        return
    url = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}"
        "/databases/(default)/documents:commit"
    )
    http_json(url, token, method="POST", payload={"writes": writes})


def main():
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)

    token = get_access_token()
    collections = migration_map.get("domainFirestoreCollections", [])
    results = []

    for collection in collections:
        print(f"Processing collection: {collection}")
        docs = list_documents(collection, token)
        copied = 0
        writes = []

        for doc in docs:
            name = doc["name"]
            doc_id = name.rsplit("/", 1)[-1]
            fields = doc.get("fields", {})
            franchise_field = fields.get("franchiseId")
            if not franchise_field or not franchise_field.get("stringValue"):
                fields["franchiseId"] = {"stringValue": DEFAULT_FRANCHISE_ID}
            franchise_id = fields["franchiseId"]["stringValue"]

            fields["_migration"] = {
                "mapValue": {
                    "fields": {
                        "legacyCollection": {"stringValue": collection},
                        "migratedAtUnix": {"integerValue": str(int(time.time()))},
                    }
                }
            }

            scoped_name = (
                f"projects/{PROJECT_ID}/databases/(default)/documents/"
                f"franchises/{franchise_id}/{collection}/{doc_id}"
            )

            writes.append(
                {
                    "update": {
                        "name": scoped_name,
                        "fields": fields,
                    }
                }
            )
            copied += 1

            if not DRY_RUN and len(writes) >= BATCH_SIZE:
                commit_writes(writes, token)
                writes = []

        if not DRY_RUN and writes:
            commit_writes(writes, token)

        results.append(
            {
                "collection": collection,
                "total": len(docs),
                "copied": copied,
            }
        )
        print(f"  total={len(docs)} copied={copied}")

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "defaultFranchiseId": DEFAULT_FRANCHISE_ID,
        "dryRun": DRY_RUN,
        "results": results,
    }
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Report written: {REPORT_PATH}")


if __name__ == "__main__":
    main()
