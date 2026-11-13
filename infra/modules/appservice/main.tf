variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "plan_name" { type = string }
variable "app_name" { type = string }
variable "sku_name" { type = string }
variable "startup_command" { type = string }
variable "sql_server_fqdn" { type = string }
variable "sql_database_name" { type = string }

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "api_key_secret_uri" {
  description = "Versionless secret URI so new secret versions are picked up automatically."
  type        = string
}

variable "enable_entra_auth" { type = bool }

variable "entra_client_id" {
  type    = string
  default = null
}

variable "tenant_id" { type = string }

variable "log_analytics_workspace_id" { type = string }
variable "enable_diagnostic_settings" { type = bool }

variable "tags" { type = map(string) }

locals {
  is_free_tier = contains(["F1", "FREE", "D1"], upper(var.sku_name))
}

resource "azurerm_service_plan" "this" {
  #checkov:skip=CKV_AZURE_212:Single instance is intentional for a cost-limited sandbox; prod example uses P1v3 and can scale out
  #checkov:skip=CKV_AZURE_225:Zone redundancy needs Premium v3 and 3+ instances; out of scope for the sandbox
  #checkov:skip=CKV_AZURE_211:B1 is chosen for the sandbox; envs/prod.tfvars.example uses P1v3
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  #checkov:skip=CKV_AZURE_214:always_on is computed (true on every SKU except Free, where it is not supported)
  #checkov:skip=CKV_AZURE_17:Users authenticate with Entra ID via App Service Authentication; mTLS client certificates are not used
  #checkov:skip=CKV_AZURE_222:Public web app by design (browser users); access is gated by Easy Auth with Entra ID
  #checkov:skip=CKV_AZURE_88:Stateless app; no Azure Files mount needed
  name                = var.app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  tags                = var.tags

  # Deployments use Entra tokens (azure/login OIDC), so publishing-profile basic auth is off.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = !local.is_free_tier
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5
    app_command_line                  = var.startup_command

    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    SQL_SERVER                            = var.sql_server_fqdn
    SQL_DB                                = var.sql_database_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    API_KEY                               = "@Microsoft.KeyVault(SecretUri=${var.api_key_secret_uri})"
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  # App Service Authentication (Easy Auth v2) with Entra ID.
  dynamic "auth_settings_v2" {
    for_each = var.enable_entra_auth ? [1] : []

    content {
      auth_enabled           = true
      require_authentication = true
      unauthenticated_action = "RedirectToLoginPage" # HTTP 302 to Entra sign-in
      default_provider       = "azureactivedirectory"
      excluded_paths         = ["/health"] # health probe + alert must work anonymously
      require_https          = true
      runtime_version        = "~1"

      active_directory_v2 {
        client_id            = var.entra_client_id
        tenant_auth_endpoint = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
        allowed_audiences    = ["api://${var.entra_client_id}", var.entra_client_id]
        # No client_secret_setting_name: ID-token flow, no secret to store or rotate.
      }

      login {
        token_store_enabled = true
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Set by the platform after zip deploy.
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "web" {
  count = var.enable_diagnostic_settings ? 1 : 0

  name                       = "diag-to-law"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }
  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "web_app_id" {
  value = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  value = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  value = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  value = azurerm_linux_web_app.this.identity[0].principal_id
}

output "service_plan_id" {
  value = azurerm_service_plan.this.id
}
