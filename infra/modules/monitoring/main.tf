variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "law_name" { type = string }
variable "app_insights_name" { type = string }
variable "retention_days" { type = number }
variable "tags" { type = map(string) }

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.law_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days
  tags                = var.tags
}

# Workspace-based Application Insights (classic mode is retired).
resource "azurerm_application_insights" "this" {
  name                = var.app_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  retention_in_days   = 90
  tags                = var.tags
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "app_insights_id" {
  value = azurerm_application_insights.this.id
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}
