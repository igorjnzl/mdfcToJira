resource "azurerm_user_assigned_identity" "function" {
  name                = var.function_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "logic_app" {
  name                = var.logic_app_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azuread_application" "function_api" {
  display_name     = var.function_api_display_name
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2
  }
}

resource "azuread_service_principal" "function_api" {
  client_id                    = azuread_application.function_api.client_id
  app_role_assignment_required = false
}