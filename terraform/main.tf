terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

# -----------------------------------------------------------------------------
# Local values — cost tags applied to EVERY resource
# -----------------------------------------------------------------------------
locals {
  default_tags = {
    project      = var.project_name
    environment  = var.environment
    team         = "platform-engineering"
    cost-center  = var.cost_center
    created-by   = var.created_by
    managed-by   = "terraform"
    destroy-by   = "end-of-day"
  }

  # ACR names must be alphanumeric only, globally unique
  acr_name = "acr${replace(var.project_name, "-", "")}${var.environment}"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = local.default_tags
}

# -----------------------------------------------------------------------------
# Azure Container Registry — Basic SKU, admin DISABLED
# -----------------------------------------------------------------------------
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.default_tags
}