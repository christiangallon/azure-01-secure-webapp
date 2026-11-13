#!/usr/bin/env bash
# One-time: create the identity GitHub Actions uses to deploy, with OIDC
# federated credentials (no client secret anywhere).
#
#   RG=<resource-group> GH_REPO=<owner>/azure-01-secure-webapp ./scripts/bootstrap-oidc.sh
#
# KODEKLOUD NOTE: playground users usually cannot create app registrations or
# role assignments. If a step fails, the pipeline stays "unexecuted"; keep the
# workflows in the repo and deploy from your PC with `terraform apply` instead.
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash on Windows: stop /subscriptions/... IDs being rewritten as file paths

: "${RG:?Set RG to the resource group name}"
: "${GH_REPO:?Set GH_REPO to owner/repo}"
APP_NAME="${APP_NAME:-gh-azure-01-secure-webapp-deployer}"
GH_ENV="${GH_ENV:-production}"               # GitHub Environment used for apply
TFSTATE_SA="${TFSTATE_SA:-}"                  # optional: state storage account name

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
RG_ID="$(az group show -n "$RG" --query id -o tsv)"

echo "1/4 App registration + service principal"
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [ -z "$APP_ID" ]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)"
fi
APP_OBJ_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"
SP_OID="$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp create --id "$APP_ID" --query id -o tsv)"

echo "2/4 Federated credentials (main branch, pull requests, environment '$GH_ENV')"
fic() {
  local name="$1" subject="$2"
  if az ad app federated-credential list --id "$APP_OBJ_ID" --query "[?name=='$name']" -o tsv | grep -q .; then
    echo "  $name exists"; return
  fi
  az ad app federated-credential create --id "$APP_OBJ_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none && echo "  $name -> $subject"
}
fic gh-main "repo:${GH_REPO}:ref:refs/heads/main"
fic gh-pr   "repo:${GH_REPO}:pull_request"
fic gh-env  "repo:${GH_REPO}:environment:${GH_ENV}"

echo "3/4 Azure role assignments (resource group scope only, not subscription)"
# Contributor: create/update the resources in this one RG.
az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$RG_ID" -o none || echo "  WARNING: Contributor assignment failed"

# Terraform also creates two role assignments (Key Vault Secrets User/Officer).
# Instead of Owner / User Access Administrator, use RBAC Administrator with an
# ABAC condition: the pipeline may ONLY assign or remove those two roles.
KV_SECRETS_USER="4633458b-17de-408a-b874-0445c86b69e6"
KV_SECRETS_OFFICER="b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
CONDITION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${KV_SECRETS_USER}, ${KV_SECRETS_OFFICER}})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${KV_SECRETS_USER}, ${KV_SECRETS_OFFICER}}))"
az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope "$RG_ID" \
  --condition "$CONDITION" --condition-version "2.0" -o none \
  || echo "  WARNING: constrained RBAC Administrator assignment failed (set enable_role_assignments = false)"

if [ -n "$TFSTATE_SA" ]; then
  SA_ID="$(az storage account show -g "$RG" -n "$TFSTATE_SA" --query id -o tsv)"
  az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none \
    || echo "  WARNING: state storage assignment failed"
fi

echo "4/4 Entra (Graph) permission for the Easy Auth app registration"
cat <<'EOF'
  For enable_entra_auth = true in CI the service principal needs the Microsoft Graph
  APPLICATION permission Application.ReadWrite.OwnedBy (admin consent required):
    az ad app permission add --id <APP_ID> --api 00000003-0000-0000-c000-000000000000 \
      --api-permissions 18a4783c-866b-4cc7-a460-3d5e5662c884=Role
    az ad app permission admin-consent --id <APP_ID>
  In KodeKloud this is normally impossible: run with enable_entra_auth = false in CI,
  or create the Easy Auth registration from your PC.
EOF

cat <<EOF

Set these GitHub repository VARIABLES (not secrets, they are identifiers):
  AZURE_CLIENT_ID       = $APP_ID
  AZURE_TENANT_ID       = $TENANT_ID
  AZURE_SUBSCRIPTION_ID = $SUB_ID
  TFSTATE_RESOURCE_GROUP / TFSTATE_STORAGE_ACCOUNT / TFSTATE_CONTAINER (from bootstrap-tfstate.sh)
  APP_NAME              = <terraform output -raw web_app_name>
With the GitHub CLI:  gh variable set AZURE_CLIENT_ID --body "$APP_ID" --repo $GH_REPO
Then create the GitHub Environment '$GH_ENV' with required reviewers (Settings > Environments).
EOF
