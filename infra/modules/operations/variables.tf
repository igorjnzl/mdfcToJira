variable "automation_name" {
  description = "Name of Defender for Cloud Workflow Automation."
  type        = string
}

variable "location" {
  description = "Azure region for the automation resource."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the automation resource."
  type        = string
}

variable "subscription_id" {
  description = "Subscription scope monitored for Defender assessments."
  type        = string
}

variable "logic_app_id" {
  description = "Resource ID of the target Consumption Logic App."
  type        = string
}

variable "logic_app_callback_url" {
  description = "Signed request-trigger callback URL for the Logic App."
  type        = string
  sensitive   = true
}

variable "key_vault_id" {
  description = "Resource ID of the Jira configuration Key Vault."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the central Log Analytics workspace."
  type        = string
}

variable "tags" {
  description = "Tags applied to Defender automation."
  type        = map(string)
}