# Control Mappings

Every policy, collector, and gate rule in this repo, mapped to the NIST CSF 2.0
category it serves. This file is what turns the repo from code into a control catalog —
and it's a first-class criterion on the capstone rubric.

## Stage 01 — Foundation

| Component | What it does | CSF 2.0 |
|---|---|---|
| Management group hierarchy + initiative assignment | Controls inherit to every current and future subscription — compliance by design | GV.PO, GV.OC |
| `cge-require-env-tag-rg` (Audit) | Inventory hygiene; owner accountability feeds the POA&M | ID.AM |
| `cge-deny-public-blob` (Deny) | Prevents public blob exposure at the API, before the resource exists | PR.DS |
| `cge-dine-storage-diagnostics` (DeployIfNotExists) | Logging that enforces its own coverage | PR.PS, DE.CM |
| **`cge-nsg-no-mgmt-ports-from-internet` (Audit → Deny ladder)** *(capstone addition)* | Flags NSG rules allowing SSH/RDP (22/3389/`*`) inbound from any internet source, evaluated both inline and as child rule resources. Audit while the estate is cleaned up; escalate via `nsg_mgmt_ports_effect`. Seeded estate finding: `nsg-fafo-open`. | PR.IR, PR.AA |
| **`cge-storage-https-only` (Audit)** *(capstone addition)* | Flags storage accounts that accept plaintext HTTP (secure transfer off). Seeded estate finding: `stfafopub*`. | PR.DS |
| Remediation identity (user-assigned, whitelist roles) | Every automated change has a named, auditable author | PR.AA, GV.RR |
| Log Analytics workspace + Activity Log routing | Central audit trail beyond the 90-day default | DE.CM, PR.PS |

## Stage 03 — Evidence Store

| Component | What it does | CSF 2.0 |
|---|---|---|
| Cosmos DB (assessments / frameworks / mappings) | Owned evidence schema; collect once, crosswalk to every framework | GV.OV, ID.RA |
| WORM immutability policy on `reports` | Artifacts tamper-proof by platform guarantee | PR.DS |
| Shared keys disabled + data-plane RBAC | Identity or nothing; no credentials to steal or rotate | PR.AA |
| Collector Function (Security Reader + Cosmos write only) | Continuous control-test capture with lineage; cannot alter what it observes | DE.CM, ID.RA |
| Collector/reporter identity split | The recorder of facts cannot author the narrative — SoD by role scopes | PR.AA, GV.RR |

## Stage 04 — Reporting

| Component | What it does | CSF 2.0 |
|---|---|---|
| POA&M generator (daily, SLA-dated) | Weakness management with owners and dates, from the store only | ID.IM, GV.RM |
| SAR generator (weekly) | Assessment reporting where every number traces to a stored document; per-finding CSF 2.0 categories and a by-function summary | ID.RA, GV.OV |
| **CSF 2.0 crosswalk** (`mappings/csf2-defender-crosswalk.json` → Cosmos `mappings`) *(capstone addition)* | Framework mapping as data: 843 Azure Defender assessments → CSF 2.0 categories, unmapped shown explicitly. Collect once, map many. | GV.OV, ID.RA |
| **Collector severity capture** (`$expand=metadata`) *(capstone fix)* | Without it every finding stored severity=null and POA&M deadlines defaulted to 90 days, including High findings due in 30 | ID.RA, ID.IM |

## Stage 06 — Enforcement

| Component | What it does | CSF 2.0 |
|---|---|---|
| `cge-fix-public-blob` (Modify, mode ladder) | Auto-remediation through the dedicated identity; human-approved in dry-run | PR.DS, RS.MI |
| `remediation_mode` variable | Escalation is a reviewed diff — automation acts, humans authorize | GV.PO, GV.RR |
| **`GRC Remediation - Storage Configuration Writer` custom role** *(capstone addition)* | Replaces Storage Account Contributor for the remediation identity: `storageAccounts/read` + `/write` only. No `listKeys` (no path to data), no delete. | PR.AA |
| **KQL tripwire `grc-tripwire-portal-writes`** (scheduled query alert + action group) *(capstone addition)* | Hourly: any successful admin write made by a human through the Azure portal emails the owner. Drift's second direction — who is touching reality. | DE.CM, DE.AE |

## Repo gates (policy/)

| Rule | Mistake it makes unmergeable | CSF 2.0 |
|---|---|---|
| `storage.rego` | Pipeline storage below the pipeline's own standard | PR.DS |
| `policy_identity.rego` | Remediation that silently never runs | PR.PS |
| `broad_roles.rego` | Owner/Contributor grants in governance code | PR.AA |
| **`network.rego`** *(capstone addition)* | NSG rules (inline or standalone) opening SSH/RDP to the internet — the shift-left twin of `cge-nsg-no-mgmt-ports-from-internet` | PR.IR |
| `drift.yml` (nightly plan, issue on drift) + KQL tripwire (stage 06) | Out-of-band change going unnoticed, in both directions | DE.CM, DE.AE |
