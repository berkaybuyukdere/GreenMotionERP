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
OUT_PATH = os.path.join(BASE_DIR, "uppercase-franchise-migration-report.json")


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


def extract_doc_id(full_name):
    return full_name.rsplit("/", 1)[-1]


def get_string_field(fields, key):
    field = fields.get(key)
    if not field:
        return None
    return field.get("stringValue")


def set_string_field(fields, key, value):
    fields[key] = {"stringValue": value}


def main():
    with open(MAP_PATH, "r", encoding="utf-8") as f:
        migration_map = json.load(f)

    domain_collections = migration_map.get("domainFirestoreCollections", [])
    token = get_access_token()

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "dryRun": DRY_RUN,
        "franchiseMappings": [],
        "usersUpdated": 0,
        "smtpConfigsMoved": 0,
        "domainLegacyUpdated": {},
        "scopedDocsCopied": {},
    }

    # 1) Build franchise mapping and upsert uppercase franchise docs
    franchise_docs = list_documents("franchises", token)
    mapping = {}
    writes = []
    for doc in franchise_docs:
        source_id = extract_doc_id(doc["name"])
        fields = doc.get("fields", {})
        country_code = get_string_field(fields, "countryCode")
        franchise_id_field = get_string_field(fields, "franchiseId")
        target_id = (country_code or franchise_id_field or source_id).upper()
        mapping[source_id] = target_id

        # Normalize franchise document itself.
        set_string_field(fields, "franchiseId", target_id)
        if country_code:
            set_string_field(fields, "countryCode", country_code.upper())

        target_name = (
            f"projects/{PROJECT_ID}/databases/(default)/documents/"
            f"franchises/{target_id}"
        )
        writes.append({"update": {"name": target_name, "fields": fields}})
        if len(writes) >= BATCH_SIZE and not DRY_RUN:
            commit_writes(writes, token)
            writes = []

        report["franchiseMappings"].append(
            {"sourceId": source_id, "targetId": target_id}
        )

    if writes and not DRY_RUN:
        commit_writes(writes, token)

    # 2) Copy scoped docs from lowercase/legacy franchise docs to uppercase docs.
    for source_id, target_id in mapping.items():
        for collection in domain_collections:
            scoped_source = f"franchises/{source_id}/{collection}"
            source_docs = list_documents(scoped_source, token)
            if not source_docs:
                continue
            scoped_copied = report["scopedDocsCopied"].get(collection, 0)
            writes = []
            for doc in source_docs:
                doc_id = extract_doc_id(doc["name"])
                fields = doc.get("fields", {})
                set_string_field(fields, "franchiseId", target_id)
                target_name = (
                    f"projects/{PROJECT_ID}/databases/(default)/documents/"
                    f"franchises/{target_id}/{collection}/{doc_id}"
                )
                writes.append({"update": {"name": target_name, "fields": fields}})
                scoped_copied += 1
                if len(writes) >= BATCH_SIZE and not DRY_RUN:
                    commit_writes(writes, token)
                    writes = []
            if writes and not DRY_RUN:
                commit_writes(writes, token)
            report["scopedDocsCopied"][collection] = scoped_copied

    # 3) Normalize users.franchiseId to uppercase.
    users = list_documents("users", token)
    writes = []
    for user_doc in users:
        fields = user_doc.get("fields", {})
        franchise_id = get_string_field(fields, "franchiseId")
        if not franchise_id:
            continue
        normalized = mapping.get(franchise_id, franchise_id.upper())
        if normalized != franchise_id:
            set_string_field(fields, "franchiseId", normalized)
            writes.append({"update": {"name": user_doc["name"], "fields": fields}})
            report["usersUpdated"] += 1
            if len(writes) >= BATCH_SIZE and not DRY_RUN:
                commit_writes(writes, token)
                writes = []
    if writes and not DRY_RUN:
        commit_writes(writes, token)

    # 4) Move smtpConfigurations doc IDs to uppercase.
    smtp_docs = list_documents("smtpConfigurations", token)
    writes = []
    for smtp_doc in smtp_docs:
        source_id = extract_doc_id(smtp_doc["name"])
        target_id = mapping.get(source_id, source_id.upper())
        if source_id == target_id:
            continue
        fields = smtp_doc.get("fields", {})
        set_string_field(fields, "franchiseId", target_id)
        target_name = (
            f"projects/{PROJECT_ID}/databases/(default)/documents/"
            f"smtpConfigurations/{target_id}"
        )
        writes.append({"update": {"name": target_name, "fields": fields}})
        report["smtpConfigsMoved"] += 1
        if len(writes) >= BATCH_SIZE and not DRY_RUN:
            commit_writes(writes, token)
            writes = []
    if writes and not DRY_RUN:
        commit_writes(writes, token)

    # 5) Normalize franchiseId field in legacy domain collections.
    for collection in domain_collections:
        docs = list_documents(collection, token)
        writes = []
        updated = 0
        for doc in docs:
            fields = doc.get("fields", {})
            franchise_id = get_string_field(fields, "franchiseId")
            if not franchise_id:
                continue
            normalized = mapping.get(franchise_id, franchise_id.upper())
            if normalized == franchise_id:
                continue
            set_string_field(fields, "franchiseId", normalized)
            writes.append({"update": {"name": doc["name"], "fields": fields}})
            updated += 1
            if len(writes) >= BATCH_SIZE and not DRY_RUN:
                commit_writes(writes, token)
                writes = []
        if writes and not DRY_RUN:
            commit_writes(writes, token)
        report["domainLegacyUpdated"][collection] = updated

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Report written: {OUT_PATH}")


if __name__ == "__main__":
    main()
