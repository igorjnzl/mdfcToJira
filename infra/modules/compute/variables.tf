variable "name" {
  description = "Globally unique Function App name."
  type        = string
}

variable "plan_name" {
  description = "Flex Consumption service plan name."
  type        = string
}

variable "location" {
  description = "Azure region for compute resources."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing compute resources."
  type        = string
}

variable "subscription_id" {
  description = "Subscription receiving the Defender governance role assignment."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant used by Easy Auth."
  type        = string
}

variable "function_identity_id" {
  description = "Resource ID of the Function user-assigned identity."
  type        = string
}

variable "function_identity_client_id" {
  description = "Client ID of the Function user-assigned identity."
  type        = string
}

variable "function_identity_principal_id" {
  description = "Principal ID of the Function user-assigned identity."
  type        = string
}

variable "logic_app_identity_client_id" {
  description = "Client ID allowed to invoke the Function API."
  type        = string
}

variable "function_api_client_id" {
  description = "Client ID of the Entra application used as the Function API audience."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of Functions host and deployment storage."
  type        = string
}

variable "blob_service_endpoint" {
  description = "Blob service endpoint for identity-based host storage."
  type        = string
}

variable "queue_service_endpoint" {
  description = "Queue service endpoint for identity-based host storage."
  type        = string
}

variable "table_service_endpoint" {
  description = "Table service endpoint for identity-based host storage."
  type        = string
}

variable "deployment_container_name" {
  description = "Container used for Flex Consumption deployment packages."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Jira settings Key Vault."
  type        = string
}

variable "key_vault_uri" {
  description = "Data-plane URI of the Jira settings Key Vault."
  type        = string
}

variable "application_insights_id" {
  description = "Resource ID of Application Insights."
  type        = string
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string."
  type        = string
  sensitive   = true
}

variable "maximum_instance_count" {
  description = "Maximum FC1 instance count."
  type        = number
}

variable "instance_memory_mb" {
  description = "Memory allocated to each FC1 instance."
  type        = number
}

variable "zone_redundant" {
  description = "Enable zone balancing for FC1."
  type        = bool
}

variable "high_due_days" {
  description = "Due days for high-severity recommendations."
  type        = number
}

variable "medium_due_days" {
  description = "Due days for medium-severity recommendations."
  type        = number
}

variable "low_due_days" {
  description = "Due days for low-severity recommendations."
  type        = number
}

variable "default_due_days" {
  description = "Due days when severity is unknown."
  type        = number
}

variable "apply_grace_period" {
  description = "Whether governance assignments use a grace period."
  type        = bool
}

variable "tags" {
  description = "Tags applied to compute resources."
  type        = map(string)
}