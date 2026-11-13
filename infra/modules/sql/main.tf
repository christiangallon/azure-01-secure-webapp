variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "server_name" { type = string }
variable "database_name" { type = string }
variable "tenant_id" { type = string }
variable "admin_login" { type = string }
variable "admin_object_id" { type = string }
variable "db_sku" { type = string }
variable "auto_pause_delay_minutes" { type = number }
variable "client_ip_ranges" { type = map(object({ start = string, end = string })) }
variable "enable_auditing" { type = bool }
variable "log_analytics_workspace_id" { type = string }
variable "tags" { type = map(string) }

# Entra-only authentication: no SQL login / password exists at all.
resource "azurerm_mssql_server" "this" {
  #checkov:skip=CKV_AZURE_113:Public endpoint needed for the AllowAzureServices rule without VNet integration; auth is Entra-only
  #checkov:skip=CKV2_AZURE_45:Private endpoint out of scope for the sandbox (no VNet); see README hardening
  #checkov:skip=CKV2_AZURE_2:Vulnerability Assessment needs Defender for SQL (paid); not enabled in the sandbox
  #checkov:skip=CKV_AZURE_24:Audit logs go to Log Analytics; retention is governed by the workspace (log_retention_days, 90 in prod)
  name                          = var.server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true # needed for the "Azure services" rule; private endpoint = hardening path
  tags                          = var.tags

  azuread_administrator {
    login_username              = var.admin_login
    object_id                   = var.admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }
}

# Serverless General Purpose database: auto-pauses to keep sandbox cost low.
resource "azurerm_mssql_database" "this" {
  #checkov:skip=CKV_AZURE_224:Ledger not required for this demo data; it is irreversible once enabled
  #checkov:skip=CKV_AZURE_229:Zone redundancy not available/needed for a serverless sandbox database
  name                        = var.database_name
  server_id                   = azurerm_mssql_server.this.id
  sku_name                    = var.db_sku
  max_size_gb                 = 32
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = var.auto_pause_delay_minutes
  storage_account_type        = "Local" # cheapest backup redundancy; use Geo/Zone for prod
  zone_redundant              = false
  tags                        = var.tags

  short_term_retention_policy {
    retention_days = 7
  }
}

# 0.0.0.0-0.0.0.0 = "Allow Azure services and resources to access this server".
# Same as v1. Note it allows ANY Azure-hosted client to reach the endpoint; auth
# is still Entra-only. Hardening path: VNet integration + private endpoint.
resource "azurerm_mssql_firewall_rule" "azure_services" {
  #checkov:skip=CKV2_AZURE_34:0.0.0.0 rule = Allow Azure services (same as v1) because App Service has no VNet integration here; Entra-only auth still required
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "clients" {
  for_each = var.client_ip_ranges

  name             = each.key
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = each.value.start
  end_ip_address   = each.value.end
}

# Server auditing to Log Analytics (pattern: auditing policy with
# log_monitoring_enabled + diagnostic setting on the master database).
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  count = var.enable_auditing ? 1 : 0

  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true
}

resource "azurerm_monitor_diagnostic_setting" "sql_audit" {
  count = var.enable_auditing ? 1 : 0

  name                       = "audit-to-law"
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  depends_on = [azurerm_mssql_server_extended_auditing_policy.this, azurerm_mssql_database.this]
}

output "server_id" {
  value = azurerm_mssql_server.this.id
}

output "server_name" {
  value = azurerm_mssql_server.this.name
}

output "server_fqdn" {
  value = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  value = azurerm_mssql_database.this.name
}
