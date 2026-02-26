#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib import parse, request

PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "250"))
DRY_RUN = "--dry-run" in os.sys.argv

BASE_DIR = os.path.dirname(__file__)
MAP_PATH = os.path.join(BASE_DIR, "franchise-migration-map.json")
OUT_PATH = os.path.join(BASE_DIR, "scoped-lower-to-upper-report.json")


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


def commit_writes(writes, token):
    if not writes:
        return
    url = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}"
        "/databases/(default)/documents:commit"
    )
    http_json(url, token, method="POST", payload={"writes": writes})


def extract_doc_id(name):
    return name.rsplit("/", 1)[-1]


def main():
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)
    domain_collections = migration_map.get("domainFirestoreCollections", [])
    token = get_access_token()

    candidate_ids = set()

    # Collect lowercase franchise IDs from users.
    users = list_documents("users", token)
    for user_doc in users:
        fields = user_doc.get("fields", {})
        franchise_field = fields.get("franchiseId", {})
        franchise_id = franchise_field.get("stringValue")
        if franchise_id and franchise_id.lower() == franchise_id:
            candidate_ids.add(franchise_id)

    # Include common historic keys to be safe.
    candidate_ids.update(["ch", "tr", "de"])

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "dryRun": DRY_RUN,
        "candidateLowerIds": sorted(candidate_ids),
        "copiedByCollection": {},
    }

    for lower_id in sorted(candidate_ids):
        upper_id = lower_id.upper()
        if lower_id == upper_id:
            continue
        for collection in domain_collections:
            source_path = f"franchises/{lower_id}/{collection}"
            docs = list_documents(source_path, token)
            if not docs:
                continue
            writes = []
            copied = report["copiedByCollection"].get(collection, 0)
            for doc in docs:
                doc_id = extract_doc_id(doc["name"])
                fields = doc.get("fields", {})
                fields["franchiseId"] = {"stringValue": upper_id}
                target_name = (
                    f"projects/{PROJECT_ID}/databases/(default)/documents/"
                    f"franchises/{upper_id}/{collection}/{doc_id}"
                )
                writes.append({"update": {"name": target_name, "fields": fields}})
                copied += 1
                if len(writes) >= BATCH_SIZE and not DRY_RUN:
                    commit_writes(writes, token)
                    writes = []
            if writes and not DRY_RUN:
                commit_writes(writes, token)
            report["copiedByCollection"][collection] = copied

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Report written: {OUT_PATH}")


if __name__ == "__main__":
    main()
