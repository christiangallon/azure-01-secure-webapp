data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource group: existing (KodeKloud) or created
# ---------------------------------------------------------------------------
data "azurerm_resource_group" "existing" {
  count = var.use_existing_resource_group ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "this" {
  count    = var.use_existing_resource_group ? 0 : 1
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
  numeric = true
}

locals {
  rg_name     = var.use_existing_resource_group ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.this[0].name
  rg_location = var.use_existing_resource_group ? coalesce(var.location, data.azurerm_resource_group.existing[0].location) : azurerm_resource_group.this[0].location

  suffix = var.name_suffix != "" ? var.name_suffix : random_string.suffix.result

  names = {
    plan          = "plan-${var.project}-${var.environment}"
    app           = "${var.project}-${var.environment}-${local.suffix}"
    sql_server    = "sql-${var.project}-${var.environment}-${local.suffix}"
    sql_db        = "appdb"
    key_vault     = "kv-secweb-${var.environment}-${local.suffix}" # max 24 chars
    law           = "law-${var.project}-${var.environment}"
    app_insights  = "appi-${var.project}-${var.environment}"
    action_group  = "ag-${var.project}-${var.environment}"
    entra_app     = "${var.project}-${var.environment}-easyauth"
    app_hostname  = "${var.project}-${var.environment}-${local.suffix}.azurewebsites.net"
    key_vault_uri = "https://kv-secweb-${var.environment}-${local.suffix}.vault.azure.net/"
  }

  tags = merge({
    project     = "azure-01-secure-webapp"
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)

  deployer_object_id = data.azurerm_client_config.current.object_id
  tenant_id          = data.azurerm_client_config.current.tenant_id
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = local.rg_name
  location            = local.rg_location
  law_name            = local.names.law
  app_insights_name   = local.names.app_insights
  retention_days      = var.log_retention_days
  tags                = local.tags
}

module "auth" {
  source = "./modules/auth"
  count  = var.enable_entra_auth ? 1 : 0

  display_name                 = local.names.entra_app
  app_hostname                 = local.names.app_hostname
  app_role_assignment_required = var.app_role_assignment_required
  app_role_members             = var.app_role_members
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name           = local.rg_name
  location                      = local.rg_location
  name                          = local.names.key_vault
  tenant_id                     = local.tenant_id
  purge_protection_enabled      = var.kv_purge_protection_enabled
  soft_delete_retention_days    = var.kv_soft_delete_retention_days
  public_network_access_enabled = var.kv_public_network_access_enabled
  enable_role_assignments       = var.enable_role_assignments
  use_access_policies           = var.kv_use_access_policies
  secrets_officer_object_ids    = distinct(concat([local.deployer_object_id], var.kv_secrets_officer_object_ids))
  create_secret                 = var.create_kv_secret
  api_key                       = var.api_key
  log_analytics_workspace_id    = module.monitoring.log_analytics_workspace_id
  enable_diagnostic_settings    = var.enable_diagnostic_settings
  tags                          = local.tags
}

module "sql" {
  source = "./modules/sql"

  resource_group_name        = local.rg_name
  location                   = local.rg_location
  server_name                = local.names.sql_server
  database_name              = local.names.sql_db
  tenant_id                  = local.tenant_id
  admin_login                = coalesce(var.sql_admin_login, "entra-sql-admin")
  admin_object_id            = coalesce(var.sql_admin_object_id, local.deployer_object_id)
  db_sku                     = var.sql_db_sku
  auto_pause_delay_minutes   = var.sql_auto_pause_delay_minutes
  client_ip_ranges           = var.sql_client_ip_ranges
  enable_auditing            = var.enable_sql_auditing
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "appservice" {
  source = "./modules/appservice"

  resource_group_name            = local.rg_name
  location                       = local.rg_location
  plan_name                      = local.names.plan
  app_name                       = local.names.app
  sku_name                       = var.app_service_sku
  startup_command                = var.startup_command
  sql_server_fqdn                = module.sql.server_fqdn
  sql_database_name              = module.sql.database_name
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  api_key_secret_uri             = "${local.names.key_vault_uri}secrets/${module.keyvault.api_key_secret_name}/"
  enable_entra_auth              = var.enable_entra_auth
  entra_client_id                = var.enable_entra_auth ? module.auth[0].client_id : null
  tenant_id                      = local.tenant_id
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
  enable_diagnostic_settings     = var.enable_diagnostic_settings
  tags                           = local.tags
}

module "rbac" {
  source = "./modules/rbac"
  count  = var.enable_role_assignments && !var.kv_use_access_policies ? 1 : 0

  key_vault_id         = module.keyvault.id
  web_app_principal_id = module.appservice.principal_id
}

# Access-policy fallback for the web app identity: read secrets in this vault only.
resource "azurerm_key_vault_access_policy" "webapp" {
  count = var.kv_use_access_policies ? 1 : 0

  key_vault_id       = module.keyvault.id
  tenant_id          = local.tenant_id
  object_id          = module.appservice.principal_id
  secret_permissions = ["Get", "List"]
}

module "alerts" {
  source = "./modules/alerts"
  count  = var.enable_alerts ? 1 : 0

  resource_group_name = local.rg_name
  action_group_name   = local.names.action_group
  alert_email         = var.alert_email
  web_app_id          = module.appservice.web_app_id
  service_plan_id     = module.appservice.service_plan_id
  enable_cpu_alert    = var.enable_cpu_alert
  tags                = local.tags
}
