# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "secwebapp"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.project))
    error_message = "project must be 3-12 lowercase letters/digits."
  }
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.environment))
    error_message = "environment must be 2-5 lowercase letters/digits."
  }
}

variable "name_suffix" {
  description = "Suffix for globally unique names (web app, SQL server, Key Vault). Empty = random 5 chars generated once and kept in state."
  type        = string
  default     = ""

  validation {
    condition     = var.name_suffix == "" || can(regex("^[a-z0-9]{3,8}$", var.name_suffix))
    error_message = "name_suffix must be empty or 3-8 lowercase letters/digits."
  }
}

variable "tags" {
  description = "Extra tags merged into the default tags."
  type        = map(string)
  default     = {}
}

variable "resource_provider_registrations" {
  description = "azurerm provider registration mode. 'none' for sandboxes without subscription-level rights."
  type        = string
  default     = "none"
}

# ---------------------------------------------------------------------------
# Resource group (KodeKloud pre-creates one; you usually cannot create RGs)
# ---------------------------------------------------------------------------
variable "use_existing_resource_group" {
  description = "true = look up an existing resource group (data source). false = create it."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the existing (or new) resource group."
  type        = string
}

variable "location" {
  description = "Region. Only required when creating the RG; with an existing RG its location is used when this is null."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Feature toggles (switch off what the sandbox blocks)
# ---------------------------------------------------------------------------
variable "enable_entra_auth" {
  description = "Create the Entra app registration (app roles Reader/Editor) and turn on App Service Authentication. Needs Graph permission to create applications."
  type        = bool
  default     = true
}

variable "enable_role_assignments" {
  description = "Create Azure RBAC role assignments (Key Vault Secrets User for the web app, Secrets Officer for the deployer). Needs Microsoft.Authorization/roleAssignments/write."
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Create the action group and metric alerts."
  type        = bool
  default     = true
}

variable "enable_cpu_alert" {
  description = "Also create the optional App Service plan CPU alert (requires enable_alerts)."
  type        = bool
  default     = false
}

variable "create_kv_secret" {
  description = "Let Terraform write the ApiKey secret. Requires the deployer to have a data-plane role on the vault (enable_role_assignments or granted out of band)."
  type        = bool
  default     = true
}

variable "enable_sql_auditing" {
  description = "Send SQL server audit logs to Log Analytics."
  type        = bool
  default     = true
}

variable "enable_diagnostic_settings" {
  description = "Send web app and Key Vault resource logs to Log Analytics."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# App Service
# ---------------------------------------------------------------------------
variable "app_service_sku" {
  description = "App Service plan SKU. B1 minimum for always_on; F1 if the sandbox only allows free."
  type        = string
  default     = "B1"
}

variable "startup_command" {
  description = "Startup command (installs ODBC 18 if missing, then gunicorn + uvicorn)."
  type        = string
  default     = "bash startup.sh"
}

# ---------------------------------------------------------------------------
# Entra authentication
# ---------------------------------------------------------------------------
variable "app_role_assignment_required" {
  description = "If true, Entra blocks sign-in for users without an app role (you then cannot demo the app's own 403)."
  type        = bool
  default     = false
}

variable "app_role_members" {
  description = "Object IDs of users/groups to assign to the app roles, e.g. { Editor = [\"<oid>\"], Reader = [] }."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.app_role_members) : contains(["Reader", "Editor"], k)])
    error_message = "app_role_members keys must be Reader or Editor."
  }
}

# ---------------------------------------------------------------------------
# SQL
# ---------------------------------------------------------------------------
variable "sql_admin_login" {
  description = "Display name / UPN of the Entra SQL admin. null = the identity running Terraform."
  type        = string
  default     = null
}

variable "sql_admin_object_id" {
  description = "Object ID of the Entra SQL admin (user, group or service principal). null = the identity running Terraform. A group containing you AND the pipeline identity is best."
  type        = string
  default     = null
}

variable "sql_db_sku" {
  description = "Database SKU. GP_S_Gen5_1 = General Purpose serverless, 1 vCore max."
  type        = string
  default     = "GP_S_Gen5_1"
}

variable "sql_auto_pause_delay_minutes" {
  description = "Serverless auto-pause delay in minutes (-1 disables)."
  type        = number
  default     = 60
}

variable "sql_client_ip_ranges" {
  description = "Extra firewall rules (e.g. your PC for loading the schema): map of name => { start, end }."
  type        = map(object({ start = string, end = string }))
  default     = {}
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------
variable "kv_purge_protection_enabled" {
  description = "Purge protection. Recommended true for prod; it can never be turned off again and blocks re-using the vault name until the retention period ends, so false in a throwaway sandbox."
  type        = bool
  default     = false
}

variable "kv_soft_delete_retention_days" {
  description = "Soft-delete retention (7-90 days)."
  type        = number
  default     = 7
}

variable "kv_public_network_access_enabled" {
  description = "Public endpoint of the vault. Must stay true unless you add VNet integration + private endpoint (App Service Key Vault references and the GitHub runner both reach it over the public endpoint)."
  type        = bool
  default     = true
}

variable "kv_secrets_officer_object_ids" {
  description = "Extra principals (e.g. your own user) that get Key Vault Secrets Officer. The identity running Terraform is always included when enable_role_assignments = true."
  type        = list(string)
  default     = []
}

variable "api_key" {
  description = "Value for the ApiKey secret. null = random 32-char value. Either way it ends up in Terraform state: protect the state."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Monitoring / alerts
# ---------------------------------------------------------------------------
variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for the action group. Keep it in tfvars or TF_VAR_alert_email, not in code."
  type        = string
  default     = null
}
