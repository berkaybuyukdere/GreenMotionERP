#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib import parse, request

PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
DEFAULT_FRANCHISE_ID = os.environ.get("DEFAULT_FRANCHISE_ID", "ch")

MAP_PATH = os.path.join(os.path.dirname(__file__), "franchise-migration-map.json")
REPORT_PATH = os.path.join(os.path.dirname(__file__), "scoped-parity-report.json")


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
    with request.urlopen(req, timeout=120) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


def list_ids(collection_path, token):
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
    return [doc["name"].rsplit("/", 1)[-1] for doc in docs]


def main():
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)

    token = get_access_token()
    results = []
    for collection in migration_map.get("domainFirestoreCollections", []):
        legacy_ids = set(list_ids(collection, token))
        scoped_ids = set(list_ids(f"franchises/{DEFAULT_FRANCHISE_ID}/{collection}", token))
        missing = sorted(list(legacy_ids - scoped_ids))
        results.append(
            {
                "collection": collection,
                "legacyCount": len(legacy_ids),
                "scopedCount": len(scoped_ids),
                "missingCount": len(missing),
                "missingSample": missing[:20],
            }
        )
        print(
            f"{collection}: legacy={len(legacy_ids)} "
            f"scoped={len(scoped_ids)} missing={len(missing)}"
        )

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "defaultFranchiseId": DEFAULT_FRANCHISE_ID,
        "results": results,
    }
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Parity report written: {REPORT_PATH}")


if __name__ == "__main__":
    main()
