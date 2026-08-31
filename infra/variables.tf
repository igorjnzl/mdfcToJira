variable "subscription_id" {
  description = "Azure subscription that receives the deployment."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}

variable "tenant_id" {
  description = "Microsoft Entra tenant containing the deployment identity and Function API app registration."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a Microsoft Entra tenant GUID."
  }
}

variable "location" {
  description = "Azure region for all regional resources."
  type        = string
}

variable "environment" {
  description = "Short environment identifier used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must contain 2-8 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group created for the integration."
  type        = string
}

variable "owner" {
  description = "Operational owner tag value."
  type        = string
}

variable "additional_tags" {
  description = "Additional tags merged into every supported Azure resource."
  type        = map(string)
  default     = {}
}

variable "data_service_tags" {
  description = "Optional organization-specific tags applied only to Storage and Key Vault, such as approved policy-exception tags."
  type        = map(string)
  default     = {}
}

variable "governance_owner_domain" {
  description = "Synthetic domain used to encode Jira keys in Defender governance owners."
  type        = string
  default     = "jira.local"
}

variable "high_due_days" {
  description = "Defender remediation due days for high-severity recommendations."
  type        = number
  default     = 7
}

variable "medium_due_days" {
  description = "Defender remediation due days for medium-severity recommendations."
  type        = number
  default     = 30
}

variable "low_due_days" {
  description = "Defender remediation due days for low-severity recommendations."
  type        = number
  default     = 90
}

variable "default_due_days" {
  description = "Defender remediation due days when severity is unknown."
  type        = number
  default     = 30
}

variable "apply_grace_period" {
  description = "Whether Defender governance assignments use a grace period."
  type        = bool
  default     = false
}

variable "zone_redundant" {
  description = "Enable zone balancing on the Flex Consumption plan."
  type        = bool
  default     = true
}

variable "maximum_instance_count" {
  description = "Maximum Flex Consumption scale-out instance count."
  type        = number
  default     = 40

  validation {
    condition     = var.maximum_instance_count >= 40 && var.maximum_instance_count <= 1000
    error_message = "maximum_instance_count must be between 40 and 1000 for Flex Consumption."
  }
}

variable "instance_memory_mb" {
  description = "Memory allocated to each Flex Consumption instance."
  type        = number
  default     = 2048

  validation {
    condition     = contains([512, 2048, 4096], var.instance_memory_mb)
    error_message = "instance_memory_mb must be 512, 2048, or 4096."
  }
}