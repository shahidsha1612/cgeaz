# Azure GRC Engineering Pipeline (CGE-AZ capstone)

A continuous, self-correcting GRC pipeline running in my own Azure subscription,
built on the [CGE-AZ starter](https://github.com/GRCEngClub/cgeaz) and extended for the
capstone. It discovers what runs, collects Defender for Cloud assessments into an
evidence store I own, writes ATO deliverables from that store alone, enforces
policy with a human at the approval gate, and checks itself in CI.

```
01 Foundation → 02 Activation → 03 Evidence Store → 04 Reporting → 06 Enforcement ↺
MG hierarchy     discover gap     Cosmos + WORM        POA&M (daily)   Modify, dry-run
5 policies       enable plans     collector (05:00)    SAR (weekly)    least-priv role
remediation ID   NIST CSF 2.0     CSF crosswalk        CSF per finding KQL tripwire
```

**What this fork adds beyond the starter** (details and rationale in
[docs/ARCHITECTURE.md §6](docs/ARCHITECTURE.md#6-this-pipelines-departures-from-the-starter),
mappings in [docs/CONTROLS.md](docs/CONTROLS.md)):

| Addition | Why |
|---|---|
| Policy `cge-nsg-no-mgmt-ports-from-internet` (Audit) + gate rule `policy/network.rego` | SSH/RDP open to the internet, caught in the PR *and* in the estate |
| Policy `cge-storage-https-only` (Audit) | Plaintext HTTP to storage |
| Custom remediation role (read/write storage config only) | The starter's Storage Account Contributor could list keys, which is a path to data |
| KQL tripwire alert `grc-tripwire-portal-writes` | Drift's second direction, as code: who is touching reality through the portal |
| NIST CSF 2.0 crosswalk as data (`mappings/`) + CSF in POA&M and SAR | Collect once, map many; every CSF number traces to a stored document |
| Collector `$expand=metadata` fix | Severity was never collected; High findings got 90-day deadlines instead of 30 |
| CI writes `backend.hcl` from repo variables | The gate and drift workflows could not `terraform init` from a clean checkout |

## Deploy from an empty subscription

Prerequisites: Azure CLI, Terraform ≥ 1.9, Python 3.11+, `az login` as an Owner of the
subscription, and a tenant where you can create management groups.
Probe Function quota first (`labs/00-setup/probe-quota.sh`) and set
`TF_VAR_functions_location` if `centralus` has none.

```bash
# 0. Providers and remote state (state cannot manage itself, so this one is a script)
./labs/00-setup/register-providers.sh
./labs/03-foundation/bootstrap.sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TF_VAR_state_storage_account=$(grep storage_account_name labs/03-foundation/backend.hcl | cut -d'"' -f2)
export TF_VAR_owner_email=<owner-address>      # tag value + alert recipient; never committed

# 1-4. Stages, in order (each: init with the shared backend, plan, read, apply)
for s in 01-foundation 02-activation 03-evidence-store 04-reporting 06-enforcement; do
  (cd stages/$s && terraform init -backend-config=../../labs/03-foundation/backend.hcl && terraform apply)
done
```

On a subscription where Labs 1–2 were done by hand, adopt those resources with
`terraform import` instead of recreating them (see `labs/03-foundation/README.md` and
`labs/04-evidence/README.md`).

```bash
# 5. Function code (remote build), then the reference data
(cd functions/collect_assessments && zip -r /tmp/collector.zip . && \
  az functionapp deployment source config-zip -g rg-grc-evidence-dev --build-remote true \
    --name $(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app) --src /tmp/collector.zip)
(cd functions/reports && zip -r /tmp/reports.zip . && \
  az functionapp deployment source config-zip -g rg-grc-evidence-dev --build-remote true \
    --name $(cd ../../stages/04-reporting && terraform output -raw reporting_function_app) --src /tmp/reports.zip)

export COSMOS_ENDPOINT=$(cd stages/03-evidence-store && terraform output -raw cosmos_endpoint)
python3 labs/04-evidence/seed_frameworks.py     # CSF 2.0 catalog
python3 labs/05-reports/seed_mappings.py        # CSF 2.0 crosswalk

# 6. CI: arm THIS fork only (never the public upstream), then add the five
#    printed values as repository VARIABLES and enable the workflows
./labs/06-loop/arm-your-fork.sh <github-user>
```

Teardown is the reverse: `terraform destroy` in 06 → 04 → 03 → 02 → 01. The WORM
policy ships unlocked so this works; production would lock it.

## How it runs

| When (UTC) | What | Identity |
|---|---|---|
| 05:00 daily | Collector sweeps Defender assessments into Cosmos (`runId`, `collectedAt`) | collector MI: Security Reader + Cosmos write |
| 06:00 daily | POA&M (xlsx + json) into the WORM `reports` container | reporter MI: Cosmos read + Blob write |
| 07:00 Monday | SAR (markdown) into the WORM container | reporter MI |
| 08:00 daily | `drift.yml`: plan every stage, open an issue on drift | fork-scoped OIDC |
| hourly | KQL tripwire: human portal writes → email | Azure Monitor |
| every PR | `gate.yml`: plan + conftest against `policy/*.rego` | fork-scoped OIDC |

Remediation (`cge-fix-public-blob`) runs in **dry-run**: compliance accumulates, a human
creates the remediation task, and the fix executes as `id-grc-remediation-dev`, which
shows up as the caller in the Activity Log.

## Repo layout

```
stages/     Terraform root modules, one state file each, applied in number order
functions/  collector and report generators (Python, managed identity, zero keys)
mappings/   framework crosswalks as data (NIST CSF 2.0 ← Defender assessments)
policy/     OPA/conftest rules gating this repo's own Terraform
tools/      crosswalk builder
labs/       the course labs and helper scripts this pipeline was built through
docs/       ARCHITECTURE (stage flow, identity boundaries, departures), CONTROLS, RUBRIC
```

## Verify it yourself

```bash
./self-check.sh                                   # mechanical rubric checks
conftest test <plan.json> -p policy/              # the gate, locally
```

Every number in a report traces to a stored document: take the SAR's `runId`, query
`SELECT VALUE COUNT(1) FROM c WHERE c.runId = "<runId>" AND c.status = "Unhealthy"` in
the `assessments` container, and the count matches.

---

Starter © GRC Engineering Club · www.grcengclub.com. Capstone extensions by
[@shahidsha1612](https://github.com/shahidsha1612).
