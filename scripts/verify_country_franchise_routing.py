#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib import parse, request

PROJECT_ID = os.environ.get("PROJECT_ID", "greenmotionapp-33413")
OUT_PATH = os.path.join(
    os.path.dirname(__file__), "country-franchise-routing-report.json"
)


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


def get_string(fields, key):
    field = fields.get(key, {})
    return field.get("stringValue")


def main():
    token = get_access_token()
    users = list_documents("users", token)
    franchises = list_documents("franchises", token)

    franchise_ids = set()
    franchise_country_mismatch = []
    for doc in franchises:
        doc_id = doc["name"].rsplit("/", 1)[-1]
        fields = doc.get("fields", {})
        country = (get_string(fields, "countryCode") or "").upper()
        fid = (get_string(fields, "franchiseId") or doc_id).upper()
        franchise_ids.add(doc_id.upper())
        if country and country != fid:
            franchise_country_mismatch.append(
                {"docId": doc_id, "franchiseId": fid, "countryCode": country}
            )

    user_mismatches = []
    missing_franchise_docs = []
    for user in users:
        fields = user.get("fields", {})
        email = get_string(fields, "email") or user["name"].rsplit("/", 1)[-1]
        country = (get_string(fields, "countryCode") or "").upper()
        fid = (get_string(fields, "franchiseId") or "").upper()
        if country and fid and country != fid:
            user_mismatches.append(
                {"email": email, "countryCode": country, "franchiseId": fid}
            )
        if fid and fid not in franchise_ids:
            missing_franchise_docs.append({"email": email, "franchiseId": fid})

    report = {
        "generatedAt": int(time.time()),
        "projectId": PROJECT_ID,
        "franchiseDocCount": len(franchises),
        "userCount": len(users),
        "franchiseCountryMismatchCount": len(franchise_country_mismatch),
        "userCountryFranchiseMismatchCount": len(user_mismatches),
        "missingFranchiseDocCount": len(missing_franchise_docs),
        "franchiseCountryMismatchSample": franchise_country_mismatch[:20],
        "userCountryFranchiseMismatchSample": user_mismatches[:20],
        "missingFranchiseDocSample": missing_franchise_docs[:20],
    }

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Report written: {OUT_PATH}")


if __name__ == "__main__":
    main()
