variable "name" {
  description = "Name of the Consumption Logic App workflow."
  type        = string
}

variable "location" {
  description = "Azure region for the Logic App."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Logic App."
  type        = string
}

variable "logic_app_identity_id" {
  description = "Resource ID of the user-assigned identity used by the Logic App."
  type        = string
}

variable "function_base_url" {
  description = "Base HTTPS URL of the Function App."
  type        = string
}

variable "function_audience" {
  description = "Microsoft Entra audience configured for Function App Easy Auth."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Logic App."
  type        = map(string)
}