variable "resource_group_name" {
  description = "Resource group containing the managed identities."
  type        = string
}

variable "location" {
  description = "Azure region for the managed identities."
  type        = string
}

variable "function_identity_name" {
  description = "Name of the Function App user-assigned identity."
  type        = string
}

variable "logic_app_identity_name" {
  description = "Name of the Logic App user-assigned identity."
  type        = string
}

variable "function_api_display_name" {
  description = "Display name of the Function API application registration."
  type        = string
}

variable "tags" {
  description = "Tags applied to Azure managed identities."
  type        = map(string)
}