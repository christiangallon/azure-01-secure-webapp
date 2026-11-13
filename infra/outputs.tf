output "resource_group_name" {
  value = local.rg_name
}

output "web_app_name" {
  value = module.appservice.web_app_name
}

output "web_app_url" {
  value = "https://${module.appservice.default_hostname}"
}

output "web_app_principal_id" {
  description = "Object ID of the web app's system-assigned identity (Key Vault RBAC, SQL contained user)."
  value       = module.appservice.principal_id
}

output "sql_server_fqdn" {
  value = module.sql.server_fqdn
}

output "sql_server_name" {
  value = module.sql.server_name
}

output "sql_database_name" {
  value = module.sql.database_name
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "key_vault_uri" {
  value = module.keyvault.vault_uri
}

output "entra_app_client_id" {
  description = "Client ID of the Easy Auth app registration (null when enable_entra_auth = false)."
  value       = var.enable_entra_auth ? module.auth[0].client_id : null
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}
