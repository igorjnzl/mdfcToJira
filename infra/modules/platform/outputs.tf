output "storage_account_id" {
  description = "Resource ID of the Functions storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the Functions storage account."
  value       = azurerm_storage_account.this.name
}

output "blob_service_endpoint" {
  description = "Blob service endpoint used by the Functions host."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "queue_service_endpoint" {
  description = "Queue service endpoint used by the Functions host."
  value       = azurerm_storage_account.this.primary_queue_endpoint
}

output "table_service_endpoint" {
  description = "Table service endpoint used by the Functions host."
  value       = azurerm_storage_account.this.primary_table_endpoint
}

output "deployment_container_id" {
  description = "Resource ID of the private deployment package container."
  value       = azurerm_storage_container.deployment.id
}

output "deployment_container_name" {
  description = "Name of the private deployment package container."
  value       = var.deployment_container_name
}

output "application_insights_id" {
  description = "Resource ID of Application Insights."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string used as a non-secret endpoint setting."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "key_vault_id" {
  description = "Resource ID of the Jira configuration Key Vault."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Name of the Jira configuration Key Vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Data-plane URI of the Jira configuration Key Vault."
  value       = azurerm_key_vault.this.vault_uri
}

output "deployer_blob_role_assignment_id" {
  description = "Role assignment that permits Terraform to publish the Function package."
  value       = azurerm_role_assignment.deployer_blob_data_contributor.id
}