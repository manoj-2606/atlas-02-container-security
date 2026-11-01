terraform {
  backend "azurerm" {
    resource_group_name  = "rg-atlas-tfstate"
    storage_account_name = "atlastfstate2606"
    container_name       = "tfstate"
    key                  = "atlas-02.tfstate"
    use_oidc             = true
  }
}