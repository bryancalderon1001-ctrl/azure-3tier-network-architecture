resource "azurerm_log_analytics_workspace" "this" {
  name                = "Log-Analytics-Workspace"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id = azurerm_log_analytics_workspace.this.id
}

resource "azurerm_sentinel_data_connector_azure_security_center" "this" {
  name                       = "Sentinel_Connector"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
}

data "azurerm_subscription" "current" {
}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "Monitor_Diagnostic_Setting"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id

  enabled_log {
    category = "Administrative"
  }
  enabled_log {
    category = "Security"
  }
}
