# terraform init -backend-config=envs/dev.backend.hcl
# Values come from scripts/bootstrap-tfstate.sh output.
resource_group_name  = "<kodekloud-resource-group>"
storage_account_name = "<sttfstateXXXXX>"
container_name       = "tfstate"
key                  = "azure-01-secure-webapp/dev.tfstate"
use_azuread_auth     = true # Entra auth to the blob (no storage account key)
