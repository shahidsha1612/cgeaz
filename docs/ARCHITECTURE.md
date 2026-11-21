# CGE-AZ Pipeline Architecture

How the starter pipeline is put together: the stage flow, the contracts between
stages, where data goes, and which identity is allowed to touch what. The capstone
rubric asks for an architecture doc "showing stage flow and identity boundaries" —
this is the starter's. Yours should describe *your* pipeline, including every place
you departed from this one and why.

## 1. Stage flow

```
            ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐
  Lab 1-3   │ 01 foundation│───▶│ 02 activation│    │ 03 evidence store│
            │ MG hierarchy │    │ discover gap │    │ Cosmos + WORM    │
            │ policies     │    │ enable plans │    │ blob + collector │
            │ remediation  │    │ CSF 2.0 std  │    └────────┬─────────┘
            │ identity     │    └──────────────┘             │
            └──────┬───────┘                                 ▼
                   │                                ┌──────────────────┐
                   │                                │ 04 reporting     │
                   │                                │ POA&M + SAR from │
                   │                                │ the store ONLY   │
                   ▼                                └────────┬─────────┘
            ┌──────────────┐                                 ▼
            │ 06 enforce   │                        ┌──────────────────┐
            │ Modify effect│                        │ 05 narrative     │
            │ audit→dry-run│                        │ (optional) AI    │
            │ →enforce     │                        │ digest of 04     │
            └──────────────┘                        └──────────────────┘
```

Each stage is a Terraform root module with its own state file in the shared
`tfstate` container (bootstrapped once by `labs/03-foundation/bootstrap.sh`, the one
piece that cannot manage itself). Stages are applied in number order and destroyed in
reverse. Stage 05 is a lab, not a stage directory: it reads stage 04's artifacts and
produces prose; it never decides anything.

### The contract between stages

Downstream stages read upstream **outputs** through `terraform_remote_state`. Outputs
are the interface; everything else is private implementation.

| Stage | Reads from | Publishes |
|---|---|---|
| 01 foundation | nothing | `subscription_id`, `management_group_id`, `log_analytics_workspace_id`, `evidence_resource_group_name`, `remediation_identity_id`, `remediation_identity_principal_id` |
| 02 activation | nothing (discovers live state with `azapi` data sources) | Defender plan tiers, the NIST CSF 2.0 assignment |
| 03 evidence store | 01 | `cosmos_endpoint`, `cosmos_account_id/name`, `evidence_storage_account`, `reports_container`, `collector_function_app`, `collector_principal_id` |
| 04 reporting | 01, 03 | `reporting_function_app`, `reporter_principal_id` |
| 06 enforcement | 01 | `remediation_mode` |

Stage 01 adopts the Lab 1–2 resources (management groups, sandbox resource group,
Log Analytics workspace) with `terraform import` rather than recreating them. Stage 02
is discovery-first: `azapi` data sources read every Defender plan's current tier and
activation converges only the measured gap; a plan already at Standard stays
untouched and becomes change-managed.

## 2. Data flow

```
 Defender for Cloud ──(assessments API)──▶ collector Function ──▶ Cosmos: assessments
       │                                   nightly 05:00 UTC          /subscriptionId
       │                                   runId + collectedAt
  Azure Policy ──────────────────────────▶ compliance states (portal / KQL)
                                                                    │
                 frameworks ◀── seed_frameworks.py (CSF 2.0 catalog) │
                 mappings   ◀── the crosswalk, as data               │
                                                                    ▼
                                           reporting Function ◀── reads Cosmos ONLY
                                           POA&M daily (xlsx+json), SAR weekly (md)
                                                                    │
                                                                    ▼
                                           WORM `reports` container (immutable blob)
                                                                    │
                                                                    ▼
                                           Stage 05 narrative (optional) reads reports
```

Three rules make this defensible:

- **Collect once.** One assessment document serves every framework through the
  `mappings` crosswalk. Adding a framework is a data change, not a collector change.
- **Reports read from the store only.** No report touches a live API. Every number is
  reproducible tomorrow with a stored query against a pinned `runId`.
- **Immutability is a platform guarantee, not an access rule.** The `reports`
  container carries a time-based immutability policy. Unlocked for the course so
  teardown works; production locks it.

### Partition keys, justified

| Container | Partition key | Why |
|---|---|---|
| `assessments` | `/subscriptionId` | Every query the reports run is "this subscription, this run". A second and third subscription land as new partitions with no reshaping — the scale-by-scope requirement in the capstone brief. |
| `frameworks` | `/frameworkId` | A catalog is read whole, one framework at a time. |
| `mappings` | `/frameworkId` | The crosswalk is queried per target framework when a report resolves which controls an assessment satisfies. |

Document IDs in `assessments` are a hash of `assessmentId|resourceId`, so a re-run
upserts rather than duplicates; lineage comes from `runId` and `collectedAt` on every
document. If you change a partition key in your capstone, this table is where you
defend it. A schema you cannot justify is a schema you copied.

## 3. Identity boundaries

Zero stored credentials anywhere in the design. Every actor is a managed identity or
an OIDC federation, and every identity's roles are a whitelist of its job.

| Identity | Kind | Roles (scope) | Can | Cannot |
|---|---|---|---|---|
| **Deployer** (you) | `az login` user | Owner on the subscription; Storage Blob Data Contributor on the evidence account; Cosmos Data Contributor | Apply stages, seed frameworks, prove WORM | Nothing is automated through this identity |
| **Remediation** `id-grc-remediation-<env>` | User-assigned MI | Monitoring Contributor (sandbox MG); custom **GRC Remediation - Storage Configuration Writer** (`storageAccounts/read`, `storageAccounts/write`; sandbox MG) *only* when `remediation_mode != audit` | Create diagnostic settings; flip `allowBlobPublicAccess` | List or regenerate keys, delete, or read data from anything |
| **Collector** `func-grc-collectors-*` | System-assigned MI | Security Reader (subscription); Cosmos Built-in Data Contributor (evidence account) | Read Defender assessments; write evidence | Change posture; write reports |
| **Reporter** `func-grc-reporting-*` | System-assigned MI | Cosmos Built-in Data Reader; Storage Blob Data Contributor (`reports`) | Read evidence; write immutable reports | Read live platform data; write evidence |
| **CI** (your fork's gate + drift) | GitHub OIDC federation, fork-scoped | Contributor at `mg-grc`; Storage Blob Data Contributor on the state resource group (hardening to a plan-only custom role is a documented exercise) | `terraform plan`, conftest | Write RBAC; hold a secret — there is none |

The boundaries that matter:

- **Recorder ≠ narrator.** The collector writes evidence and cannot read reports; the
  reporter reads evidence and cannot touch live services. Separation of duties is
  enforced by role scopes, not by policy text.
- **One named author for every automated change.** Filter the Activity Log by the
  remediation identity's principal ID and you have the complete history of what
  automation did. Humans and CI show up as themselves.
- **Control plane ≠ data plane.** Owner on the subscription does not read a blob or a
  Cosmos document; the deployer and both Functions hold explicit data-plane roles.
  The evidence account disables shared keys and Cosmos disables local auth, so there
  is no key-shaped way around this.
- **Upstream is unarmed.** This repo's workflows skip until `AZURE_CLIENT_ID` is set.
  Each learner federates their own fork against their own subscription
  (`labs/06-loop/arm-your-fork.sh`); a public upstream must never hold a path to a
  subscription, because `pull_request` OIDC subjects match PRs from any fork.

## 4. The two loops

**The pipeline on the environment.** Policy assignments at the sandbox management
group inherit to every current and future subscription. Effects are deliberate:
Audit for the tag rule (onboarding), Deny for public blob (earned), DeployIfNotExists
for diagnostics (logging that enforces its own coverage). Stage 06 adds a Modify
effect on an escalation ladder wired to one variable — `audit` → `dry-run` → `enforce`
— where each step up is a reviewed one-line diff and dry-run keeps a human at the
remediation-task approval.

**The pipeline on itself.** The compliance gate (`.github/workflows/gate.yml`) runs
`terraform plan` per stage on every PR and refuses plans that break the repo's own
standard (`policy/*.rego`: no public blob, no shared keys, no broad roles). Drift
detection (`drift.yml`) plans nightly with `-detailed-exitcode` and opens an issue
when reality has moved away from code; the KQL tripwire in Log Analytics answers the
other direction — who has been touching reality.

## 5. Where this starter stops and yours begins

The rubric grades the pipeline, not the estate (`seed-estate.sh` gives you material
to find). At minimum your fork must add one policy or control of your own, correctly
effected and mapped in `CONTROLS.md`, and this document should gain a section for it:
what it checks, which identity acts, what its blast radius is, and why you chose its
effect. Good candidates the seeded estate leaves lying around: management ports open
to the internet, Key Vaults without purge protection, workload identities holding
Contributor, resources missing an owner tag.

## 6. This pipeline's departures from the starter

Everything below was added or changed in this fork. Each entry says what it checks,
which identity acts, its blast radius, and why its effect was chosen.

### 6.1 Own control: no SSH/RDP from the internet (`cge-nsg-no-mgmt-ports-from-internet`)

- **Checks:** NSG rules that `Allow` `Inbound` traffic to 22, 3389 or `*` from `*`,
  `Internet`, `0.0.0.0/0`, `::/0` or `any`. Two branches, because Azure exposes rules
  two ways: inline in `securityRules[*]` (what compliance scans evaluate) and as child
  `securityRules` resources (what a request-time `az network nsg rule create` sends).
  Hence `mode = "All"`: child rules carry no tags or location.
- **Acts:** nobody. Audit records; it does not modify. Assigned through the existing
  `CGE-AZ GRC Baseline` initiative at `mg-grc-sandbox`, so every current and future
  subscription inherits it.
- **Effect, and why:** **Audit** first, because the estate already contains a violation
  (`nsg-fafo-open`) and a new Deny would break legitimate change on day one. The effect
  is a tfvar (`nsg_mgmt_ports_effect`); escalating to Deny is a one-line reviewed diff
  once findings reach zero.
- **Shift-left twin:** `policy/network.rego` fails the same pattern in a Terraform plan,
  so the PR gate stops it before the platform ever sees it.

### 6.2 Own control: storage must refuse plaintext HTTP (`cge-storage-https-only`)

- **Checks:** `supportsHttpsTrafficOnly == false`. **Audit**, same escalation pattern
  (`storage_https_effect`). Seeded finding: `stfafopub*`.

### 6.3 Remediation identity, actually least-privilege

The starter granted **Storage Account Contributor** and documented the identity as
unable to read data. That role includes `listKeys/action` and `regenerateKey/action`:
on any account that still accepts shared keys (the Terraform state account does) a
key is a path to every blob. Stage 06 now defines a custom role at the sandbox
management group with exactly `storageAccounts/read` and `storageAccounts/write` (what
a Modify PATCH needs), and the policy's `roleDefinitionIds` reference it. The
sabotage → scan → approve → remediate loop from Lab 6 was re-run under the new role
to prove the narrower role is sufficient.

### 6.4 Drift in both directions

`drift.yml` (nightly `terraform plan -detailed-exitcode`, issue on exit 2) answers
*does reality still match code?* The starter left the other direction, *who is
touching reality?*, as a portal exercise. Stage 06 now ships it as code:
`grc-tripwire-portal-writes`, a scheduled query alert over the GRC workspace that
fires hourly when a human makes a successful administrative write through the Azure
portal (portal first-party app ID), emailing the owner through `ag-grc-owner`.
CLI/Terraform writes share the az-cli app ID and are deliberately not flagged here;
any of those that leave reality different from code are caught by `drift.yml`.

### 6.5 The crosswalk, as data

`tools/build_csf_crosswalk.py` turns the Defender assessment metadata catalog (the
same assessment keys in every tenant) into `mappings/csf2-defender-crosswalk.json`,
reviewed in Git like code; `labs/05-reports/seed_mappings.py` loads it into the
`mappings` container. The reporter resolves CSF categories from the store, never
from a live API, so a CSF number in the SAR is as reproducible as any other.
Findings with no mapping are reported as `UNMAPPED` rather than guessed.

### 6.6 Fixes found by tracing numbers

- **Severity was never collected.** The assessments list API omits
  `properties.metadata` without `$expand=metadata`; every finding stored
  `severity: null` and the POA&M gave four High findings a 90-day deadline instead of
  30. Found by tracing the SAR's `By severity: Unknown: 7` back to the store.
- **CI could never initialise.** `backend.hcl` is gitignored, so the gate and drift
  workflows now generate it from the `STATE_STORAGE_ACCOUNT` repository variable.

### 6.7 Known trade-off: the CI identity

`arm-your-fork.sh` grants the fork's OIDC identity Contributor at `mg-grc`, because
`terraform plan` refreshes data sources that call `listKeys` and site-config `list`
actions that Reader lacks. It is plan-only by workflow design and federated to this
fork alone; narrowing it to a custom plan-reader role is the next hardening step.
