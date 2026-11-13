variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "tenant_id" { type = string }
variable "purge_protection_enabled" { type = bool }
variable "soft_delete_retention_days" { type = number }
variable "public_network_access_enabled" { type = bool }
variable "enable_role_assignments" { type = bool }
variable "secrets_officer_object_ids" { type = list(string) }
variable "create_secret" { type = bool }

variable "api_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "log_analytics_workspace_id" { type = string }
variable "enable_diagnostic_settings" { type = bool }

variable "tags" { type = map(string) }

locals {
  secret_name = "ApiKey"
}

resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:No VNet/private endpoint in the sandbox; App Service KV references and GitHub-hosted runners use the public endpoint, access gated by Entra RBAC
  #checkov:skip=CKV_AZURE_109:Network ACL default Allow for the same reason; private endpoint is the documented hardening path
  #checkov:skip=CKV2_AZURE_32:Private endpoint out of scope for the sandbox (no VNet); see README hardening
  #checkov:skip=CKV_AZURE_110:Purge protection is variable-driven (kv_purge_protection_enabled): false for throwaway dev, true in prod example
  #checkov:skip=CKV_AZURE_42:Soft delete is always on (platform default); purge protection is variable-driven, see CKV_AZURE_110
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true # RBAC mode, no access policies
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# Data-plane write access for the deployer (and optional extra admins), scoped
# to this vault only. Secrets Officer can manage secrets but not keys/certs or RBAC.
resource "azurerm_role_assignment" "secrets_officer" {
  for_each = var.enable_role_assignments ? toset(var.secrets_officer_object_ids) : toset([])

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

# RBAC propagation can take a minute or two; writing the secret immediately fails with 403.
resource "time_sleep" "rbac_propagation" {
  count           = var.enable_role_assignments && var.create_secret ? 1 : 0
  create_duration = "90s"
  depends_on      = [azurerm_role_assignment.secrets_officer]
}

resource "random_password" "api_key" {
  count   = var.create_secret && var.api_key == null ? 1 : 0
  length  = 32
  special = false
}

# NOTE: the secret value is stored in Terraform state (plain JSON). The state
# backend must be access-controlled and encrypted (see README "State security").
resource "azurerm_key_vault_secret" "api_key" {
  #checkov:skip=CKV_AZURE_41:Demo secret rotated manually (see README); a fixed expiry would cause drift or an outage in a demo
  count = var.create_secret ? 1 : 0

  name         = local.secret_name
  value        = coalesce(var.api_key, try(random_password.api_key[0].result, null))
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation]
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  count = var.enable_diagnostic_settings ? 1 : 0

  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "api_key_secret_name" {
  value = local.secret_name
}
