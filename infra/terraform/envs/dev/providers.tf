terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.15.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}

# use_oidc = true enables Workload Identity Federation auth for GitHub Actions
# and Azure Pipelines — no client secrets stored in CI.
provider "azurerm" {
  use_oidc = true

  features {}
}

provider "azapi" {
  use_oidc = true
}
