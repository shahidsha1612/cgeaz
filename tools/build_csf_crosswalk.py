#!/usr/bin/env python3
"""Build the NIST CSF 2.0 crosswalk for Defender for Cloud assessments, as data.

"Collect once, map many": the collector stores each assessment ONCE; this file maps
assessment keys to framework categories. Adding a framework is a new mapping file,
never a collector change.

Input : the Defender assessment metadata catalog (tenant-independent; keys are the
        same GUIDs in every subscription), saved as JSON:
            az rest --method GET \
              --url "https://management.azure.com/providers/Microsoft.Security/assessmentMetadata?api-version=2021-06-01" \
              > /tmp/assessment-metadata.json
Output: mappings/csf2-defender-crosswalk.json (committed, reviewed like code)

    python3 tools/build_csf_crosswalk.py /tmp/assessment-metadata.json

Mapping method (documented so an assessor can challenge it):
  1. MANUAL overrides below win, for assessments this pipeline has actually seen.
  2. Otherwise ordered keyword RULES over the display name (case-insensitive);
     every matching rule contributes its categories (union).
  3. No match -> category "UNMAPPED". Reports show unmapped findings explicitly
     rather than guessing; an unmapped finding is a backlog item for this file.
AWS/GCP-only assessments are excluded: this pipeline governs Azure.
"""

import json
import sys
from pathlib import Path

FRAMEWORK_ID = "nist-csf-2.0"

# Hand-reviewed for findings observed in this estate.
MANUAL = {
    "e0e431eb-22b3-4f34-ae0d-5ec229fc28e7": ["DE.CM", "ID.RA"],  # Defender CSPM should be enabled
    "77758c9d-8a56-5f54-6ff7-69a762ca6004": ["GV.RR", "RS.CO"],  # security contact email
}

RULES = [
    # (rule name, keywords any-of, CSF 2.0 categories)
    ("defender-plan", ["microsoft defender for", "defender cspm", "should be enabled with malware"], ["DE.CM", "ID.RA"]),
    ("alerting-contacts", ["email notification", "contact email", "security contact"], ["RS.CO", "GV.RR"]),
    ("identity-ownership", ["owner", "owners"], ["PR.AA", "GV.RR"]),
    ("identity-auth", ["mfa", "multi-factor", "authentication", "managed identit", "rbac", "role-based", "permissions", "privileged", "guest account", "blocked accounts", "deprecated accounts", "local authentication", "access policies"], ["PR.AA"]),
    ("data-in-transit", ["https", "tls", "secure transfer", "ftp", "ssl", "encrypted in transit"], ["PR.DS"]),
    ("data-at-rest", ["encrypt", "customer-managed key", "cmk", "public access", "public blob", "anonymous", "shared key", "soft delete", "purge protection", "immutab", "key vault keys", "secrets should have"], ["PR.DS"]),
    ("backup-recovery", ["backup", "geo-redundant", "recovery"], ["RC.RP", "PR.DS"]),
    ("network", ["network", "nsg", "port", "firewall", "private endpoint", "private link", "internet", "ip forwarding", "subnet", "ddos", "just-in-time", "virtual network"], ["PR.IR"]),
    ("logging", ["diagnostic", "log", "audit", "monitor", "auditing"], ["DE.CM", "PR.PS"]),
    ("vulnerability", ["vulnerab", "update", "patch", "endpoint protection", "antimalware", "baseline", "secure configuration", "machine configuration", "guest configuration", "outdated", "latest version", "supported version"], ["ID.RA", "PR.PS"]),
    ("containers-workloads", ["kubernetes", "container", "pod"], ["PR.PS", "PR.IR"]),
    ("exposure", ["public ip", "accessible", "allow access to", "exposed"], ["PR.IR"]),
    ("endpoint-detection", ["edr", "anti-virus", "antivirus", "malware"], ["DE.CM", "PR.PS"]),
    ("devsecops", ["scanning", "findings resolved", "code repositories", "github", "devops", "gitlab", "api security testing"], ["ID.RA", "PR.PS"]),
    ("privilege", ["administrator", "principals", "least privilege", "database roles", "admin"], ["PR.AA"]),
    ("key-management", ["keys", "rotated", "key length", "certificate", "expir"], ["PR.DS", "PR.AA"]),
    ("asset-hygiene", ["unused", "inventory", "should be removed", "remove "], ["ID.AM"]),
    ("integrity", ["signature", "secure boot", "vtpm", "integrity"], ["PR.PS"]),
]

NON_AZURE = ["ec2", "aws", "gcp", "gke", "eks", "amazon", "google", "s3 bucket", "iam ", "cloudtrail",
             "ecs ", "fargate", "vpc", "guardduty", "emr ", "kms key", "opensearch", "route 53",
             "memorydb", "cloud sql", "lambda", "rds ", "redshift", "elasticache", "sagemaker", "cloudfront"]


def map_one(key: str, name: str):
    if key in MANUAL:
        return sorted(MANUAL[key]), "manual"
    lowered = name.lower()
    cats, hits = set(), []
    for rule, words, rule_cats in RULES:
        if any(w in lowered for w in words):
            cats.update(rule_cats)
            hits.append(rule)
    if not cats:
        return ["UNMAPPED"], "none"
    return sorted(cats), "rule:" + "+".join(hits)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 1
    catalog = json.loads(Path(sys.argv[1]).read_text())["value"]
    rows = []
    for item in catalog:
        name = item["properties"].get("displayName", "")
        if any(w in name.lower() for w in NON_AZURE):
            continue
        cats, basis = map_one(item["name"], name)
        rows.append({
            "id": f"csf2-defender-{item['name']}",
            "frameworkId": FRAMEWORK_ID,
            "source": "defender-for-cloud",
            "assessmentId": item["name"],
            "displayName": name,
            "severity": item["properties"].get("severity"),
            "categories": cats,
            "basis": basis,
        })
    rows.sort(key=lambda r: r["displayName"])
    out = Path(__file__).resolve().parent.parent / "mappings" / "csf2-defender-crosswalk.json"
    out.write_text(json.dumps({"frameworkId": FRAMEWORK_ID, "mappings": rows}, indent=1) + "\n")
    unmapped = sum(1 for r in rows if r["categories"] == ["UNMAPPED"])
    print(f"wrote {len(rows)} mappings ({unmapped} unmapped) -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
