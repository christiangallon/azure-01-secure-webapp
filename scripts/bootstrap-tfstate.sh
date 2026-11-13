#!/usr/bin/env bash
# One-time: create the storage account that holds Terraform remote state.
# Run in Git Bash after `az login`. Uses the EXISTING resource group (KodeKloud).
#
#   RG=<resource-group> ./scripts/bootstrap-tfstate.sh
#
# Optional: PIPELINE_SP_OBJECT_ID=<oid> to grant the GitHub OIDC identity access.
# Security choices: no public blob access, TLS 1.2, HTTPS only, shared-key auth
# disabled (Entra auth only, so no storage key exists to leak), blob versioning
# + soft delete so a corrupted/deleted state can be recovered.
set -euo pipefail

: "${RG:?Set RG to the resource group name}"
LOC="${LOC:-$(az group show -n "$RG" --query location -o tsv)}"
SA="${SA:-sttfstate$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)}"
CONTAINER="${CONTAINER:-tfstate}"
ME_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"

echo "Creating storage account $SA in $RG ($LOC)"
az storage account create -g "$RG" -n "$SA" -l "$LOC" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --default-to-oauth-authentication true -o none

az storage account blob-service-properties update -g "$RG" --account-name "$SA" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 -o none

SA_ID="$(az storage account show -g "$RG" -n "$SA" --query id -o tsv)"

# Data-plane access (shared keys are disabled). May be BLOCKED in KodeKloud:
# then re-enable shared keys (--allow-shared-key-access true), drop
# use_azuread_auth from the backend file, or use local state (backend_override.tf).
grant() {
  local oid="$1" type="$2"
  az role assignment create --assignee-object-id "$oid" --assignee-principal-type "$type" \
    --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none \
    && echo "Granted Storage Blob Data Contributor to $oid" \
    || echo "WARNING: role assignment for $oid failed (sandbox restriction?)"
}
[ -n "$ME_OID" ] && grant "$ME_OID" User
[ -n "${PIPELINE_SP_OBJECT_ID:-}" ] && grant "$PIPELINE_SP_OBJECT_ID" ServicePrincipal

echo "Waiting 30s for RBAC propagation..."; sleep 30
az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login -o none

cat <<EOF

Done. Put these values in infra/envs/dev.backend.hcl and GitHub repo variables:
  resource_group_name  = "$RG"        (TFSTATE_RESOURCE_GROUP)
  storage_account_name = "$SA"        (TFSTATE_STORAGE_ACCOUNT)
  container_name       = "$CONTAINER" (TFSTATE_CONTAINER)
EOF
