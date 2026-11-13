# Dev / KodeKloud sandbox. No secrets in this file.
# Usage: terraform plan -var-file=envs/dev.tfvars -out=tfplan
environment = "dev"

# KodeKloud pre-creates the resource group: look it up instead of creating it.
use_existing_resource_group = true
resource_group_name         = "<kodekloud-resource-group>" # az group list -o table
# location = "eastus"   # optional; defaults to the RG location

# name_suffix = "cg123" # optional; empty = random suffix kept in state

app_service_sku = "B1"

# Toggles: switch off what the sandbox blocks (see docs/sandbox-constraints.md).
enable_entra_auth       = true # false if you cannot create app registrations
enable_role_assignments = true # false if roleAssignments/write is denied
create_kv_secret        = true # false if you have no data-plane role on the vault
enable_alerts           = true
enable_cpu_alert        = false

# Throwaway sandbox: no purge protection so the vault name can be reused.
kv_purge_protection_enabled   = false
kv_soft_delete_retention_days = 7

# Assign yourself Editor (az ad signed-in-user show --query id -o tsv).
# app_role_members = {
#   Editor = ["<your-object-id>"]
#   Reader = []
# }

# Your own user can manage secrets too (besides the identity running Terraform).
# kv_secrets_officer_object_ids = ["<your-object-id>"]

# Your PC, to load sql/schema.sql (curl -s https://api.ipify.org).
# sql_client_ip_ranges = { MyPC = { start = "1.2.3.4", end = "1.2.3.4" } }

# Set via environment instead of committing it:  export TF_VAR_alert_email="you@example.com"
# alert_email = "you@example.com"
