output "resource_group_name" {
  description = "Resource group containing the integration."
  value       = azurerm_resource_group.this.name
}

output "function_app_name" {
  description = "Globally unique Function App name."
  value       = module.compute.name
}

output "function_app_url" {
  description = "HTTPS base URL of the Function App."
  value       = "https://${module.compute.default_hostname}"
}

output "logic_app_name" {
  description = "Consumption Logic App workflow name."
  value       = module.workflow.name
}

output "logic_app_callback_url" {
  description = "Signed callback URL consumed by Defender Workflow Automation."
  value       = module.workflow.callback_url
  sensitive   = true
}

output "key_vault_name" {
  description = "Key Vault that stores Jira settings and credentials."
  value       = module.platform.key_vault_name
}

output "storage_account_name" {
  description = "Functions host and deployment storage account."
  value       = module.platform.storage_account_name
}

output "defender_automation_id" {
  description = "Resource ID of Defender for Cloud Workflow Automation."
  value       = module.operations.defender_automation_id
}