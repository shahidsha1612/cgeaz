#!/usr/bin/env python3
"""Load the CSF 2.0 crosswalk (mappings/*.json) into the Cosmos `mappings` container.

Collect once, map many: assessments are stored once by the collector; this loads the
framework crosswalk as DATA, so the reporter can resolve which CSF 2.0 categories each
finding touches without a single line of collector code changing.

    COSMOS_ENDPOINT=$(cd ../../stages/03-evidence-store && terraform output -raw cosmos_endpoint) \
        python3 seed_mappings.py

Authenticates as YOU (az login) via the deployer's Cosmos data role from stage 03.
Idempotent: documents are upserted on deterministic IDs.
"""

import json
import os
import sys
from pathlib import Path

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

MAPPINGS_DIR = Path(__file__).resolve().parents[2] / "mappings"


def main() -> int:
    endpoint = os.environ.get("COSMOS_ENDPOINT")
    if not endpoint:
        print("Set COSMOS_ENDPOINT (see docstring).", file=sys.stderr)
        return 1

    container = (
        CosmosClient(endpoint, DefaultAzureCredential())
        .get_database_client(os.environ.get("COSMOS_DATABASE", "grc"))
        .get_container_client("mappings")
    )

    total = 0
    for path in sorted(MAPPINGS_DIR.glob("*.json")):
        doc = json.loads(path.read_text())
        for row in doc["mappings"]:
            container.upsert_item({**row, "sourceFile": path.name})
            total += 1
        print(f"  {path.name}: {len(doc['mappings'])} mappings")
    print(f"seeded {total} mapping documents into {endpoint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
