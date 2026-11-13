# Offline plan tests with mocked providers (no Azure credentials needed).
#   terraform init -backend=false && terraform test
# They prove the wiring, toggles and security settings evaluate as intended;
# they do NOT prove Azure accepts the configuration (only a real apply can).

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id       = "11111111-1111-1111-1111-111111111111"
      tenant_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_data "azurerm_resource_group" {
    defaults = {
      location = "eastus"
      id       = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-kodekloud"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  environment         = "dev"
  resource_group_name = "rg-kodekloud"
  name_suffix         = "cg123"
  alert_email         = "owner@example.com"
}

run "full_stack_existing_rg" {
  command = plan

  assert {
    condition     = length(azurerm_resource_group.this) == 0 && length(data.azurerm_resource_group.existing) == 1
    error_message = "Existing resource group must be looked up, not created."
  }

  assert {
    condition     = module.appservice.web_app_name == "secwebapp-dev-cg123"
    error_message = "Unexpected web app name."
  }

  assert {
    condition     = length(module.auth) == 1 && length(module.rbac) == 1 && length(module.alerts) == 1
    error_message = "All feature modules should be enabled by default."
  }
}

run "sandbox_minimal_toggles" {
  command = plan

  variables {
    enable_entra_auth       = false
    enable_role_assignments = false
    enable_alerts           = false
    create_kv_secret        = false
  }

  assert {
    condition     = length(module.auth) == 0 && length(module.rbac) == 0 && length(module.alerts) == 0
    error_message = "Toggles must remove the blocked parts."
  }

  assert {
    condition     = output.entra_app_client_id == null
    error_message = "No Entra app expected when enable_entra_auth = false."
  }
}

run "create_resource_group" {
  command = plan

  variables {
    use_existing_resource_group = false
    location                    = "westeurope"
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 1 && length(data.azurerm_resource_group.existing) == 0
    error_message = "Resource group should be created when use_existing_resource_group = false."
  }
}

run "invalid_environment_rejected" {
  command = plan

  variables {
    environment = "Dev-Environment"
  }

  expect_failures = [var.environment]
}

run "kv_access_policy_fallback" {
  command = plan

  variables {
    enable_role_assignments = false
    kv_use_access_policies  = true
  }

  assert {
    condition     = length(module.rbac) == 0 && length(azurerm_key_vault_access_policy.webapp) == 1
    error_message = "Access-policy fallback must replace the RBAC role assignment for the web app."
  }
}
