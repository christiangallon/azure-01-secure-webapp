variable "resource_group_name" { type = string }
variable "action_group_name" { type = string }

variable "alert_email" {
  type    = string
  default = null
}

variable "web_app_id" { type = string }
variable "service_plan_id" { type = string }
variable "enable_cpu_alert" { type = bool }
variable "tags" { type = map(string) }

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = "secweb"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email == null ? [] : [var.alert_email]
    content {
      name                    = "owner"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# Errors: more than 3 server errors in 5 minutes.
resource "azurerm_monitor_metric_alert" "http5xx" {
  name                = "alert-http5xx"
  resource_group_name = var.resource_group_name
  scopes              = [var.web_app_id]
  description         = "App returning 5xx"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

# Availability: health check on /health below 100 %.
resource "azurerm_monitor_metric_alert" "health" {
  name                = "alert-health"
  resource_group_name = var.resource_group_name
  scopes              = [var.web_app_id]
  description         = "Health check failing"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

# Optional resource symptom: plan CPU > 80 % for 5 minutes.
resource "azurerm_monitor_metric_alert" "cpu" {
  count = var.enable_cpu_alert ? 1 : 0

  name                = "alert-plan-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.service_plan_id]
  description         = "App Service plan CPU above 80%"
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

output "action_group_id" {
  value = azurerm_monitor_action_group.this.id
}
