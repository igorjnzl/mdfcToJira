output "id" {
  description = "Resource ID of the Logic App workflow."
  value       = azurerm_logic_app_workflow.this.id
}

output "callback_url" {
  description = "Signed callback URL used by Defender for Cloud Workflow Automation."
  value       = azurerm_logic_app_trigger_http_request.defender_recommendation.callback_url
  sensitive   = true
}

output "name" {
  description = "Name of the Logic App workflow."
  value       = azurerm_logic_app_workflow.this.name
}