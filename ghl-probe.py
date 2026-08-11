#!/usr/bin/env python3
"""
GHL probe — reports what your GoHighLevel account actually returns, so the
KPI sync can be built against real field names instead of guesses.

Run it from this folder:

    python3 ghl-probe.py

It reads GHL_TOKEN and GHL_LOCATION_ID from .env. It only ever prints
structure: field names, pipeline and stage names, tag vocabulary, and
counts. It never prints contact names, phone numbers, emails, addresses,
or message bodies — so the output is safe to paste back into chat.
"""

import json
import sys
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone

BASE = "https://services.leadconnectorhq.com"
API_VERSION = "2021-07-28"

# Anything whose field name matches one of these has its VALUE withheld.
# Field names themselves are still shown, since that's what we're mapping.
PII_HINTS = (
    "name", "email", "phone", "address", "city", "state", "postal", "zip",
    "contact", "body", "message", "text", "firstname", "lastname", "companyname",
    "website", "dnd", "ssn", "attribution",
)


def load_env(path=".env"):
    env = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    env[key.strip()] = val.strip()
    except FileNotFoundError:
        sys.exit("No .env found. Run this from the folder that contains it.")
    return env


def api_get(path, token):
    req = urllib.request.Request(
        BASE + path,
        headers={
            "Authorization": "Bearer " + token,
            "Version": API_VERSION,
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()[:400]
    except Exception as err:  # network, DNS, TLS
        return "ERR", str(err)[:200]


def redact(value, key=""):
    """Keep the shape, drop anything that could identify a person."""
    if any(hint in key.lower() for hint in PII_HINTS):
        if isinstance(value, list):
            return f"<list of {len(value)}, withheld>"
        return "<withheld>"
    if isinstance(value, dict):
        return {k: redact(v, k) for k, v in list(value.items())[:30]}
    if isinstance(value, list):
        return [redact(v, key) for v in value[:2]]
    if isinstance(value, str) and len(value) > 60:
        return value[:60] + "…"
    return value


def section(title):
    print("\n" + "=" * 64)
    print(title)
    print("=" * 64)


def main():
    env = load_env()
    token = env.get("GHL_TOKEN", "")
    loc = env.get("GHL_LOCATION_ID", "")

    if not token:
        sys.exit("GHL_TOKEN is empty in .env")
    if not loc:
        sys.exit("GHL_LOCATION_ID is empty in .env")

    print(f"Location: {loc}")
    print(f"Token:    {token[:8]}… ({len(token)} chars)")

    # --- 1. Does the token work at all? -------------------------------
    section("1. LOCATION — confirms the token and location id are valid")
    status, data = api_get(f"/locations/{loc}", token)
    print("status:", status)
    if status == 401:
        sys.exit("\n401 — token rejected. Regenerate it in Settings -> Private Integrations.")
    if status == 403:
        print("403 — token is valid but missing a scope. Note which scopes you ticked.")
    if isinstance(data, dict):
        print("keys:", list(data.keys())[:15])
    else:
        print("body:", str(data)[:300])

    # --- 2. Pipelines: the single most important thing to see ---------
    # KPI metrics like leadsOfferedOn and dealsProduced are defined by
    # which stage an opportunity sits in, so the mapping is impossible
    # without the real stage names.
    section("2. PIPELINES + STAGES — needed to map offers and deals")
    status, data = api_get(f"/opportunities/pipelines?locationId={loc}", token)
    print("status:", status)
    if isinstance(data, dict):
        for pipe in data.get("pipelines", []):
            print(f"\n  Pipeline: {pipe.get('name')}  (id {pipe.get('id')})")
            for stage in pipe.get("stages", []):
                print(f"     - {stage.get('name')}   (id {stage.get('id')})")
    else:
        print("body:", str(data)[:300])

    # --- 3. Contacts: field names + tag vocabulary --------------------
    section("3. CONTACTS — field names, and which tags you actually use")
    status, data = api_get(f"/contacts/?locationId={loc}&limit=20", token)
    print("status:", status)
    if isinstance(data, dict):
        print("top-level keys:", list(data.keys())[:10])
        contacts = data.get("contacts", [])
        print("returned:", len(contacts))
        if contacts:
            print("\nfield names on a contact:")
            print(" ", sorted(contacts[0].keys()))
            print("\none contact, values redacted:")
            print(json.dumps(redact(contacts[0]), indent=2)[:1200])
            tags = Counter(t for c in contacts for t in (c.get("tags") or []))
            print("\ntags in use (name -> count):")
            for tag, n in tags.most_common(30):
                print(f"  {tag}: {n}")
    else:
        print("body:", str(data)[:300])

    # --- 4. Opportunities --------------------------------------------
    section("4. OPPORTUNITIES — field names and status vocabulary")
    status, data = api_get(f"/opportunities/search?location_id={loc}&limit=5", token)
    print("status:", status)
    if isinstance(data, dict):
        print("top-level keys:", list(data.keys())[:10])
        opps = data.get("opportunities", [])
        print("returned:", len(opps))
        if opps:
            print("\nfield names on an opportunity:")
            print(" ", sorted(opps[0].keys()))
            print("\none opportunity, values redacted:")
            print(json.dumps(redact(opps[0]), indent=2)[:1200])
            print("\nstatus values seen:", Counter(o.get("status") for o in opps))
    else:
        print("body:", str(data)[:300])

    # --- 5. Conversations --------------------------------------------
    section("5. CONVERSATIONS — for touch points and leads contacted")
    status, data = api_get(f"/conversations/search?locationId={loc}&limit=5", token)
    print("status:", status)
    if isinstance(data, dict):
        print("top-level keys:", list(data.keys())[:10])
        convos = data.get("conversations", [])
        print("returned:", len(convos))
        if convos:
            print("\nfield names on a conversation:")
            print(" ", sorted(convos[0].keys()))
            print("\none conversation, values redacted:")
            print(json.dumps(redact(convos[0]), indent=2)[:1200])
    else:
        print("body:", str(data)[:300])

    # --- 6. Volume sanity check --------------------------------------
    # If these numbers look nothing like your real activity, the date
    # filtering needs a different field and it's better to know now.
    section("6. VOLUME — rough contact counts, to sanity-check date filtering")
    now = datetime.now(timezone.utc)
    for label, days in (("last 24h", 1), ("last 7 days", 7), ("last 30 days", 30)):
        start = int((now - timedelta(days=days)).timestamp() * 1000)
        end = int(now.timestamp() * 1000)
        status, data = api_get(
            f"/contacts/?locationId={loc}&limit=1"
            f"&startAfterDate={start}&endBeforeDate={end}",
            token,
        )
        total = data.get("meta", {}).get("total") if isinstance(data, dict) else None
        print(f"  contacts created, {label:12} status {status}  total: {total}")

    print("\n" + "=" * 64)
    print("Done. This output contains no contact data — safe to paste back.")
    print("=" * 64)


if __name__ == "__main__":
    main()
