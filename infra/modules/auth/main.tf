# Entra app registration used by App Service Authentication (Easy Auth).
# Requires the identity running Terraform to be allowed to create applications
# (user setting "Users can register applications", or Graph permission
# Application.ReadWrite.OwnedBy for the pipeline service principal).

variable "display_name" { type = string }

variable "app_hostname" {
  description = "Default hostname of the web app (computed from its name to avoid a dependency cycle)."
  type        = string
}

variable "app_role_assignment_required" { type = bool }

variable "app_role_members" {
  description = "Map of app role value => list of user/group object IDs."
  type        = map(list(string))
}

data "azuread_client_config" "current" {}

resource "random_uuid" "role_reader" {}
resource "random_uuid" "role_editor" {}

locals {
  graph_app_id        = "00000003-0000-0000-c000-000000000000"
  graph_user_read_id  = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # delegated User.Read
  graph_openid_id     = "37f7f235-527c-4136-accd-4a02d197296e" # delegated openid
  graph_profile_scope = "14dad69e-099b-42c9-810b-d002981feec1" # delegated profile

  role_assignments = {
    for pair in flatten([
      for role, members in var.app_role_members : [
        for oid in members : { key = "${role}-${oid}", role = role, oid = oid }
      ]
    ]) : pair.key => pair
  }
}

resource "azuread_application" "this" {
  display_name     = var.display_name
  sign_in_audience = "AzureADMyOrg" # single tenant
  owners           = [data.azuread_client_config.current.object_id]

  web {
    redirect_uris = ["https://${var.app_hostname}/.auth/login/aad/callback"]
    logout_url    = "https://${var.app_hostname}/.auth/logout"

    # Easy Auth without a client secret: ID-token (implicit/hybrid) flow.
    # Avoids a long-lived secret in app settings and in Terraform state.
    implicit_grant {
      id_token_issuance_enabled     = true
      access_token_issuance_enabled = false
    }
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Can read items (GET)."
    display_name         = "Reader"
    enabled              = true
    id                   = random_uuid.role_reader.result
    value                = "Reader"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Can read and create items (GET, POST)."
    display_name         = "Editor"
    enabled              = true
    id                   = random_uuid.role_editor.result
    value                = "Editor"
  }

  required_resource_access {
    resource_app_id = local.graph_app_id

    resource_access {
      id   = local.graph_openid_id
      type = "Scope"
    }
    resource_access {
      id   = local.graph_profile_scope
      type = "Scope"
    }
    resource_access {
      id   = local.graph_user_read_id
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = var.app_role_assignment_required
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_app_role_assignment" "members" {
  for_each = local.role_assignments

  app_role_id         = azuread_application.this.app_role_ids[each.value.role]
  principal_object_id = each.value.oid
  resource_object_id  = azuread_service_principal.this.object_id
}

output "client_id" {
  value = azuread_application.this.client_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.this.object_id
}

output "app_role_ids" {
  value = azuread_application.this.app_role_ids
}
