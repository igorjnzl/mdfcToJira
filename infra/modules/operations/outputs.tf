output "defender_automation_id" {
  description = "Resource ID of Defender for Cloud Workflow Automation."
  value       = azurerm_security_center_automation.this.id
}