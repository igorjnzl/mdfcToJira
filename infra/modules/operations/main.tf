locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
}

resource "azurerm_security_center_automation" "this" {
  name                = var.automation_name
  location            = var.location
  resource_group_name = var.resource_group_name
  scopes              = [local.subscription_scope]
  description         = "Create or find a Jira request for each Defender assessment, then assign the Jira reference back to Defender governance."
  enabled             = true
  tags                = var.tags

  source {
    event_source = "Assessments"
  }

  action {
    type        = "LogicApp"
    resource_id = var.logic_app_id
    trigger_url = var.logic_app_callback_url
  }
}

resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name                       = "diag-logic-mdc-jira"
  target_resource_id         = var.logic_app_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "WorkflowRuntime"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-mdc-jira"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

