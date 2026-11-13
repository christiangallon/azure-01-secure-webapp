# Least privilege for the workload identity: read secret VALUES in this one
# vault only (no list of keys/certs, no management plane, no RBAC changes).
variable "key_vault_id" { type = string }
variable "web_app_principal_id" { type = string }

resource "azurerm_role_assignment" "webapp_kv_secrets_user" {
  scope                            = var.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = var.web_app_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true # new managed identity may not be replicated yet
}

output "webapp_kv_role_assignment_id" {
  value = azurerm_role_assignment.webapp_kv_secrets_user.id
}
