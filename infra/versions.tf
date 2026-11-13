terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Authentication is NOT configured here on purpose (no secrets in code):
#   - Locally:  `az login`, then export ARM_SUBSCRIPTION_ID (azurerm 4.x requires it).
#   - CI:       ARM_USE_OIDC=true + ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
#               (GitHub OIDC federated credential, no client secret).
provider "azurerm" {
  # Sandboxes (KodeKloud) usually forbid registering resource providers at
  # subscription scope. "none" stops Terraform from trying.
  resource_provider_registrations = var.resource_provider_registrations

  features {
    key_vault {
      # Only has an effect when purge protection is OFF (dev). With purge
      # protection ON (prod) the vault stays soft-deleted for the retention period.
      purge_soft_delete_on_destroy    = !var.kv_purge_protection_enabled
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    application_insights {
      disable_generated_rule = true
    }
  }
}

provider "azuread" {}
