output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "ACR login server URL (e.g., acratlas02dev.azurecr.io)"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "ACR name for az acr login"
  value       = azurerm_container_registry.main.name
}

output "acr_id" {
  description = "Resource ID of the ACR"
  value       = azurerm_container_registry.main.id
}