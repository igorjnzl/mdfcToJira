output "function_identity_id" {
  description = "Resource ID of the Function App identity."
  value       = azurerm_user_assigned_identity.function.id
}

output "function_identity_client_id" {
  description = "Client ID of the Function App identity."
  value       = azurerm_user_assigned_identity.function.client_id
}

output "function_identity_principal_id" {
  description = "Principal ID of the Function App identity."
  value       = azurerm_user_assigned_identity.function.principal_id
}

output "logic_app_identity_id" {
  description = "Resource ID of the Logic App identity."
  value       = azurerm_user_assigned_identity.logic_app.id
}

output "logic_app_identity_client_id" {
  description = "Client ID of the Logic App identity."
  value       = azurerm_user_assigned_identity.logic_app.client_id
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App identity."
  value       = azurerm_user_assigned_identity.logic_app.principal_id
}

output "function_api_client_id" {
  description = "Client ID configured in Function App Easy Auth."
  value       = azuread_application.function_api.client_id
}

output "function_audience" {
  description = "Audience requested by Logic App managed-identity HTTP actions."
  value       = azuread_application.function_api.client_id
}