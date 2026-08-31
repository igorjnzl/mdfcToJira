output "id" {
  description = "Resource ID of the Function App."
  value       = azurerm_function_app_flex_consumption.this.id
}

output "name" {
  description = "Name of the Function App."
  value       = azurerm_function_app_flex_consumption.this.name
}

output "default_hostname" {
  description = "Default hostname of the Function App."
  value       = azurerm_function_app_flex_consumption.this.default_hostname
}

output "service_plan_id" {
  description = "Resource ID of the Flex Consumption plan."
  value       = azurerm_service_plan.this.id
}

output "package_hash" {
  description = "SHA-256 hash of the deployed Function package."
  value       = data.archive_file.function.output_base64sha256
}