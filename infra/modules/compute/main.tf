locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
  package_path       = "${path.root}/released-package.zip"
  key_vault_secrets = {
    JIRA_API_TOKEN       = "jira-api-token"
    JIRA_USER_EMAIL      = "jira-user-email"
    JIRA_BASE_URL        = "jira-base-url"
    JIRA_PROJECT_KEY     = "jira-project-key"
    JIRA_SERVICE_DESK_ID = "jira-service-desk-id"
    JIRA_REQUEST_TYPE_ID = "jira-request-type-id"
  }
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.root}/../function_app"
  output_path = local.package_path

  excludes = toset(concat(
    [
      ".pytest_cache",
      "local.settings.json",
      "local.settings.json.example",
    ],
    tolist(fileset("${path.root}/../function_app", "**/__pycache__/**")),
    tolist(fileset("${path.root}/../function_app", "**/*.pyc")),
    tolist(fileset("${path.root}/../function_app", "**/*.pyo")),
  ))
}

resource "azurerm_role_assignment" "storage_blob_data_owner" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "storage_queue_data_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "storage_table_data_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  scope                = var.application_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "security_admin" {
  scope                = local.subscription_scope
  role_definition_name = "Security Admin"
  principal_id         = var.function_identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_service_plan" "this" {
  #checkov:skip=CKV_AZURE_212:FC1 is a serverless autoscaling plan; fixed worker counts do not apply.
  name                   = var.plan_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = "FC1"
  zone_balancing_enabled = var.zone_redundant
  tags                   = var.tags
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${var.blob_service_endpoint}${var.deployment_container_name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = var.function_identity_id

  runtime_name           = "python"
  runtime_version        = "3.12"
  maximum_instance_count = var.maximum_instance_count
  instance_memory_in_mb  = var.instance_memory_mb

  https_only                                     = true
  public_network_access_enabled                  = true
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.function_identity_id]
  }

  app_settings = merge(
    {
      AZURE_CLIENT_ID                           = var.function_identity_client_id
      AzureWebJobsStorage__credential           = "managedidentity"
      AzureWebJobsStorage__clientId             = var.function_identity_client_id
      AzureWebJobsStorage__blobServiceUri       = var.blob_service_endpoint
      AzureWebJobsStorage__queueServiceUri      = var.queue_service_endpoint
      AzureWebJobsStorage__tableServiceUri      = var.table_service_endpoint
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${var.function_identity_client_id}"
      DEFENDER_HIGH_DUE_DAYS                    = tostring(var.high_due_days)
      DEFENDER_MEDIUM_DUE_DAYS                  = tostring(var.medium_due_days)
      DEFENDER_LOW_DUE_DAYS                     = tostring(var.low_due_days)
      DEFENDER_DEFAULT_DUE_DAYS                 = tostring(var.default_due_days)
      DEFENDER_APPLY_GRACE_PERIOD               = tostring(var.apply_grace_period)
    },
    {
      for setting, secret_name in local.key_vault_secrets :
      setting => "@Microsoft.KeyVault(SecretUri=${var.key_vault_uri}secrets/${secret_name})"
    }
  )

  site_config {
    application_insights_connection_string = var.application_insights_connection_string
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version                = "1.2"
    http2_enabled                          = true
    remote_debugging_enabled               = false
  }

  auth_settings_v2 {
    auth_enabled           = true
    default_provider       = "azureactivedirectory"
    require_authentication = true
    require_https          = true
    runtime_version        = "~1"
    unauthenticated_action = "Return401"

    active_directory_v2 {
      client_id            = var.function_api_client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
      allowed_applications = [var.logic_app_identity_client_id]
      allowed_audiences    = [var.function_api_client_id]
    }

    login {
      token_store_enabled = false
    }
  }

  depends_on = [
    azurerm_role_assignment.storage_blob_data_owner,
    azurerm_role_assignment.storage_queue_data_contributor,
    azurerm_role_assignment.storage_table_data_contributor,
    azurerm_role_assignment.key_vault_secrets_user,
    azurerm_role_assignment.monitoring_metrics_publisher,
    azurerm_role_assignment.security_admin,
  ]
}

resource "azapi_update_resource" "key_vault_reference_identity" {
  type        = "Microsoft.Web/sites@2024-11-01"
  resource_id = azurerm_function_app_flex_consumption.this.id

  body = {
    properties = {
      keyVaultReferenceIdentity = var.function_identity_id
    }
  }
}

resource "terraform_data" "one_deploy" {
  triggers_replace = [
    data.archive_file.function.output_base64sha256,
    azurerm_function_app_flex_consumption.this.id,
  ]

  provisioner "local-exec" {
    command = <<-POWERSHELL
      & '${abspath("${path.root}/../scripts/Deploy-FunctionPackage.ps1")}' `
        -SubscriptionId '${var.subscription_id}' `
        -ResourceGroupName '${var.resource_group_name}' `
        -FunctionAppName '${var.name}' `
        -PackagePath '${data.archive_file.function.output_path}'
    POWERSHELL

    interpreter = ["pwsh", "-NoProfile", "-Command"]
    working_dir = path.root
  }

  depends_on = [
    azapi_update_resource.key_vault_reference_identity,
  ]
}