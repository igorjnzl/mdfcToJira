data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix             = lower(random_string.suffix.result)
  function_app_name  = "func-mdc-jira-${var.environment}-${local.suffix}"
  logic_app_name     = "logic-mdc-jira-${var.environment}"
  function_identity  = "id-mdc-jira-${var.environment}-func"
  logic_app_identity = "id-mdc-jira-${var.environment}-logic"
  storage_name       = "stmdcjira${local.suffix}"
  key_vault_name     = "kv-mdc-jira-${var.environment}-${local.suffix}"
  log_analytics_name = "log-mdc-jira-${var.environment}"
  app_insights_name  = "appi-mdc-jira-${var.environment}"
  tags = merge({
    environment = var.environment
    workload    = "mdc-jira-integration"
    managed-by  = "terraform"
    owner       = var.owner
    region      = var.location
  }, var.additional_tags)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

module "identity" {
  source = "./modules/identity"

  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  function_identity_name    = local.function_identity
  logic_app_identity_name   = local.logic_app_identity
  function_api_display_name = "mdc-jira-function-${var.environment}"
  tags                      = local.tags
}

module "platform" {
  source = "./modules/platform"

  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  storage_account_name      = local.storage_name
  deployment_container_name = "deployment-packages"
  log_analytics_name        = local.log_analytics_name
  application_insights_name = local.app_insights_name
  key_vault_name            = local.key_vault_name
  deployer_object_id        = data.azurerm_client_config.current.object_id
  data_service_tags         = var.data_service_tags
  tags                      = local.tags
}

module "compute" {
  source = "./modules/compute"

  name                                   = local.function_app_name
  plan_name                              = "asp-mdc-jira-${var.environment}"
  location                               = azurerm_resource_group.this.location
  resource_group_name                    = azurerm_resource_group.this.name
  subscription_id                        = var.subscription_id
  tenant_id                              = var.tenant_id
  function_identity_id                   = module.identity.function_identity_id
  function_identity_client_id            = module.identity.function_identity_client_id
  function_identity_principal_id         = module.identity.function_identity_principal_id
  logic_app_identity_client_id           = module.identity.logic_app_identity_client_id
  function_api_client_id                 = module.identity.function_api_client_id
  storage_account_id                     = module.platform.storage_account_id
  blob_service_endpoint                  = module.platform.blob_service_endpoint
  queue_service_endpoint                 = module.platform.queue_service_endpoint
  table_service_endpoint                 = module.platform.table_service_endpoint
  deployment_container_name              = module.platform.deployment_container_name
  key_vault_id                           = module.platform.key_vault_id
  key_vault_uri                          = module.platform.key_vault_uri
  application_insights_id                = module.platform.application_insights_id
  application_insights_connection_string = module.platform.application_insights_connection_string
  maximum_instance_count                 = var.maximum_instance_count
  instance_memory_mb                     = var.instance_memory_mb
  zone_redundant                         = var.zone_redundant
  high_due_days                          = var.high_due_days
  medium_due_days                        = var.medium_due_days
  low_due_days                           = var.low_due_days
  default_due_days                       = var.default_due_days
  apply_grace_period                     = var.apply_grace_period
  tags                                   = local.tags

  depends_on = [module.platform]
}

module "workflow" {
  source = "./modules/workflow"

  name                  = local.logic_app_name
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  logic_app_identity_id = module.identity.logic_app_identity_id
  function_base_url     = "https://${module.compute.default_hostname}"
  function_audience     = module.identity.function_audience
  tags                  = local.tags
}

module "operations" {
  source = "./modules/operations"

  automation_name            = "asc-mdc-jira-${var.environment}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  subscription_id            = var.subscription_id
  logic_app_id               = module.workflow.id
  logic_app_callback_url     = module.workflow.callback_url
  key_vault_id               = module.platform.key_vault_id
  log_analytics_workspace_id = module.platform.log_analytics_workspace_id
  tags                       = local.tags
}