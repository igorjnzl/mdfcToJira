resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_59:The no-VNet PoC requires public routing for deployment; shared keys and anonymous access are disabled.
  #checkov:skip=CKV_AZURE_33:Queue logging is enabled through azurerm_storage_account_queue_properties; Checkov 3.3 only recognizes the deprecated inline block.
  #checkov:skip=CKV_AZURE_206:The approved single-region PoC uses zone-redundant storage rather than geo-replication.
  #checkov:skip=CKV2_AZURE_33:Private endpoints are deferred until deployment runs from a connected VNet.
  #checkov:skip=CKV2_AZURE_1:Function host and package data is noncritical and uses Microsoft-managed encryption for the PoC.
  # Public routing is retained for this no-VNet PoC; Entra ID is the only authorization path.
  name                             = var.storage_account_name
  resource_group_name              = var.resource_group_name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = "ZRS"
  account_kind                     = "StorageV2"
  access_tier                      = "Hot"
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  local_user_enabled               = false
  public_network_access_enabled    = true
  cross_tenant_replication_enabled = false
  tags                             = merge(var.tags, var.data_service_tags)

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

}

resource "azurerm_storage_account_queue_properties" "this" {
  storage_account_id = azurerm_storage_account.this.id

  logging {
    delete                = true
    read                  = true
    version               = "1.0"
    write                 = true
    retention_policy_days = 7
  }

  depends_on = [azurerm_role_assignment.deployer_queue_data_contributor]
}

resource "azurerm_storage_container" "deployment" {
  #checkov:skip=CKV2_AZURE_21:StorageRead and StorageWrite diagnostics are enabled on this account's blobServices/default resource below.
  name                  = var.deployment_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_blob_data_contributor]
}

resource "azurerm_role_assignment" "deployer_blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.deployer_object_id
  principal_type       = "User"
}

resource "azurerm_role_assignment" "deployer_queue_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.deployer_object_id
  principal_type       = "User"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                         = var.log_analytics_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  internet_ingestion_enabled   = true
  internet_query_enabled       = true
  tags                         = var.tags
}

resource "azurerm_application_insights" "this" {
  name                         = var.application_insights_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  workspace_id                 = azurerm_log_analytics_workspace.this.id
  application_type             = "web"
  local_authentication_enabled = false
  internet_ingestion_enabled   = true
  internet_query_enabled       = true
  retention_in_days            = 30
  sampling_percentage          = 100
  tags                         = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "blob_service" {
  name                       = "diag-storage-mdc-jira"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_109:The no-VNet PoC uses the public endpoint with Entra RBAC; no network allowlist is stable before Function creation.
  #checkov:skip=CKV_AZURE_189:The no-VNet PoC requires public routing for Function startup and operator secret bootstrap.
  #checkov:skip=CKV2_AZURE_32:Private endpoints are deferred until Function and deployment runners have VNet connectivity.
  # Public routing is retained for Function startup and bootstrap in this no-VNet PoC.
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true
  tags                          = merge(var.tags, var.data_service_tags)
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "deployer_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
  principal_type       = "User"
}