variable "resource_group_name" {
  description = "Resource group containing platform resources."
  type        = string
}

variable "location" {
  description = "Azure region for platform resources."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique Functions storage account name."
  type        = string
}

variable "deployment_container_name" {
  description = "Private container used by Flex Consumption One Deploy."
  type        = string
}

variable "log_analytics_name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "application_insights_name" {
  description = "Application Insights component name."
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name."
  type        = string
}

variable "deployer_object_id" {
  description = "Object ID of the principal running Terraform and the secret bootstrap script."
  type        = string
}

variable "data_service_tags" {
  description = "Optional organization-specific tags applied to Storage and Key Vault."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to platform resources."
  type        = map(string)
}