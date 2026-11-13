# Remote state in Azure Blob Storage (partial configuration).
# Values are supplied at init time so the same code works for every environment:
#   terraform init -backend-config=envs/dev.backend.hcl
# The storage account is created once by scripts/bootstrap-tfstate.sh.
# Blob leases give state locking; data is encrypted at rest by Azure Storage.
#
# Sandbox without a state storage account? Copy backend_override.tf.example to
# backend_override.tf (git-ignored) to use local state instead.
terraform {
  backend "azurerm" {}
}
