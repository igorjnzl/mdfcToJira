resource "azurerm_logic_app_workflow" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  enabled             = true
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.logic_app_identity_id]
  }
}

resource "azurerm_logic_app_trigger_http_request" "defender_recommendation" {
  name         = "When_a_Defender_recommendation_is_received"
  logic_app_id = azurerm_logic_app_workflow.this.id

  schema = jsonencode({
    type                 = "object"
    additionalProperties = true
  })
}

resource "azurerm_logic_app_action_custom" "create_or_get_jira_request" {
  name         = "Create_or_get_Jira_request"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "${var.function_base_url}/api/jira/requests"
      headers = {
        "Content-Type" = "application/json"
      }
      body = "@triggerBody()"
      authentication = {
        type     = "ManagedServiceIdentity"
        identity = var.logic_app_identity_id
        audience = var.function_audience
      }
      retryPolicy = {
        type = "none"
      }
    }
    runAfter = {}
  })

  depends_on = [azurerm_logic_app_trigger_http_request.defender_recommendation]
}

resource "azurerm_logic_app_action_custom" "assign_defender_recommendation" {
  name         = "Assign_Defender_recommendation"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "${var.function_base_url}/api/defender/recommendations/assign"
      headers = {
        "Content-Type" = "application/json"
      }
      body = {
        recommendation = "@triggerBody()"
        jira           = "@body('Create_or_get_Jira_request')"
      }
      authentication = {
        type     = "ManagedServiceIdentity"
        identity = var.logic_app_identity_id
        audience = var.function_audience
      }
      retryPolicy = {
        type            = "exponential"
        interval        = "PT10S"
        count           = 2
        minimumInterval = "PT5S"
        maximumInterval = "PT1M"
      }
    }
    runAfter = {
      Create_or_get_Jira_request = ["Succeeded"]
    }
  })

  depends_on = [azurerm_logic_app_action_custom.create_or_get_jira_request]
}

resource "azurerm_logic_app_action_custom" "fail_jira_request" {
  name         = "Fail_Jira_request"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Terminate"
    inputs = {
      runStatus = "Failed"
      runError = {
        code    = "JiraFunctionFailed"
        message = "@concat('Jira function failed. HTTP ', string(actions('Create_or_get_Jira_request')?['outputs']?['statusCode']), ': ', string(actions('Create_or_get_Jira_request')?['outputs']?['body']))"
      }
    }
    runAfter = {
      Create_or_get_Jira_request = ["Failed", "TimedOut"]
    }
  })

  depends_on = [azurerm_logic_app_action_custom.create_or_get_jira_request]
}

resource "azurerm_logic_app_action_custom" "fail_defender_assignment" {
  name         = "Fail_Defender_assignment"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Terminate"
    inputs = {
      runStatus = "Failed"
      runError = {
        code    = "DefenderFunctionFailed"
        message = "@concat('Defender function failed. HTTP ', string(actions('Assign_Defender_recommendation')?['outputs']?['statusCode']), ': ', string(actions('Assign_Defender_recommendation')?['outputs']?['body']))"
      }
    }
    runAfter = {
      Assign_Defender_recommendation = ["Failed", "TimedOut"]
    }
  })

  depends_on = [azurerm_logic_app_action_custom.assign_defender_recommendation]
}