#!/usr/bin/env bash
# Arm YOUR fork's CI workflows against YOUR sandbox subscription.
#
# Creates an OIDC app registration federated to your fork, grants it the roles the
# plan-only workflows need, and prints the five repository VARIABLES to add in your
# fork's UI: Settings -> Secrets and variables -> Actions -> Variables tab.
#
# Why variables and not secrets? With OIDC there is no credential to protect —
# client/tenant/subscription IDs are identifiers, and possessing them grants nothing
# without a matching federation subject. The security boundary is the federation:
# it names YOUR fork, so only workflows running in YOUR fork can exchange tokens.
#
# Why never arm the upstream repo? On a public repo, the pull_request OIDC subject
# matches PRs from ANY fork, and pull_request runs the workflow file AS MODIFIED BY
# THE PR. Arming a public upstream hands every fork PR a path toward the subscription
# behind it. Your fork is low-traffic and yours; the course subscription is neither.
# (This reasoning is exam-relevant. You just read a trust-boundary analysis.)
set -euo pipefail

GH_USER="${1:?usage: ./arm-your-fork.sh <your-github-username-or-org>}"
REPO="${2:-cgeaz}"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo ">> App registration: github-${REPO}-${GH_USER}"
APP_ID=$(az ad app create --display-name "github-${REPO}-${GH_USER}" --query appId -o tsv)
APP_OBJ=$(az ad app show --id "$APP_ID" --query id -o tsv)
az ad sp create --id "$APP_ID" --output none 2>/dev/null || true
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

echo ">> Federated credentials for repo:${GH_USER}/${REPO} (pull_request + main)"
# GitHub now issues OIDC subjects that embed immutable owner/repo IDs
# (repo:<owner>@<ownerId>/<repo>@<repoId>:...). Register both the legacy and the
# immutable-ID forms, or azure/login fails with AADSTS700213 (no matching
# federated identity record). Found on the first CI run of this fork.
IDS=$(curl -fsSL "https://api.github.com/repos/${GH_USER}/${REPO}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["owner"]["id"], d["id"])' 2>/dev/null || true)
SUBJECTS=("repo:${GH_USER}/${REPO}:pull_request|pr" "repo:${GH_USER}/${REPO}:ref:refs/heads/main|main")
if [ -n "$IDS" ]; then
  read -r OWNER_ID REPO_ID <<<"$IDS"
  SUBJECTS+=("repo:${GH_USER}@${OWNER_ID}/${REPO}@${REPO_ID}:pull_request|pr-immutable"
             "repo:${GH_USER}@${OWNER_ID}/${REPO}@${REPO_ID}:ref:refs/heads/main|main-immutable")
else
  echo "   (could not look up GitHub IDs; add immutable-ID subjects by hand if login fails)"
fi
for sub in "${SUBJECTS[@]}"; do
  SUBJECT="${sub%|*}"; NAME="${sub#*|}"
  az ad app federated-credential create --id "$APP_OBJ" --parameters "{
    \"name\": \"${REPO}-${NAME}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${SUBJECT}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none 2>/dev/null || echo "   (${REPO}-${NAME} already exists)"
done

echo ">> Roles: Contributor at mg-grc (plan/refresh needs list-keys + config reads;"
echo "   Contributor cannot write RBAC) + blob data on the state RG"
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/providers/Microsoft.Management/managementGroups/mg-grc" --output none 2>/dev/null || true
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-grc-tfstate" --output none 2>/dev/null || true

STATE_SA=$(grep storage_account_name "$(dirname "$0")/../03-foundation/backend.hcl" 2>/dev/null | tr -d ' "' | cut -d= -f2 || echo "<from backend.hcl>")

cat <<EOF

Done. Add these five VARIABLES (not secrets — see header comment) in YOUR fork:
Settings -> Secrets and variables -> Actions -> Variables -> New repository variable

  AZURE_CLIENT_ID        $APP_ID
  AZURE_TENANT_ID        $TENANT_ID
  AZURE_SUBSCRIPTION_ID  $SUB_ID
  STATE_STORAGE_ACCOUNT  $STATE_SA
  OWNER_EMAIL            <your email>

Then enable the two workflows in your fork's Actions tab. Never add these to the
upstream GRCEngClub/cgeaz repo — its workflows are intentionally unarmed.
EOF
