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

data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_southcentralus"
  resource_group_name = "NetworkWatcherRG"
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "flowlogs" {
  name                     = "stflowlogs${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_network_watcher_flow_log" "this" {
  name                 = "Flow_Logs_NWatcher"
  network_watcher_name = data.azurerm_network_watcher.this.name
  resource_group_name  = data.azurerm_network_watcher.this.resource_group_name
  target_resource_id   = azurerm_virtual_network.vnet.id
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled                = true
    workspace_id           = azurerm_log_analytics_workspace.this.workspace_id
    workspace_region       = azurerm_log_analytics_workspace.this.location
    workspace_resource_id  = azurerm_log_analytics_workspace.this.id
    interval_in_minutes    = 60
  }
}

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true
  retention_in_days      = 30
}

resource "azurerm_monitor_diagnostic_setting" "sql_audit" {
  name                       = "SQL_Monitor_Diagnostic_Setting"
  target_resource_id         = azurerm_mssql_database.this.id
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "nsg_change" {
  name                       = "NSG_Change_Rule"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  display_name               = "NSG_Change"
  severity                   = "High"
  query_frequency            = "PT1H"
  query_period               = "PT1H"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<QUERY
AzureActivity
| where OperationName == "Create or Update Security Rule"
| where ActivityStatus == "Succeeded"
| project TimeGenerated, Caller, OperationName, ResourceGroup, Resource
QUERY
}

resource "azurerm_sentinel_alert_rule_scheduled" "sql_failed_auth" {
  name                       = "SQL_Failed_AuthN"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  display_name               = "SQL_Fail"
  severity                   = "Medium"
  query_frequency            = "PT1H"
  query_period               = "PT1H"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<QUERY
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents"
| where action_name_s == "DATABASE AUTHENTICATION FAILED"
| project TimeGenerated, server_principal_name_s, client_ip_s, database_name_s
QUERY
}

resource "azurerm_sentinel_alert_rule_scheduled" "defender_high_severity" {
  name                       = "Def_Cloud_High_Severity"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  display_name               = "Defender_High_Severity"
  severity                   = "High"
  query_frequency            = "PT1H"
  query_period               = "PT1H"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<QUERY
SecurityAlert
| where AlertSeverity == "High"
| project TimeGenerated, AlertName, AlertSeverity, Description, CompromisedEntity
QUERY
}

resource "random_uuid" "workbook" {
}

resource "azurerm_application_insights_workbook" "this" {
  name                = random_uuid.workbook.result
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  display_name        = "App_Insigts_Workbook"
  source_id           = lower(azurerm_log_analytics_workspace.this.id)
  category            = "sentinel"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type    = 1
        name    = "title"
        content = { json = "# 3-Tier Lab Security Detections" }
      },
      {
        type = 3
        name = "nsg-changes"
        content = {
          version = "KqlItem/1.0"
          title   = "NSG Rule Changes"
          query   = <<QUERY
AzureActivity
| where OperationName == "Create or Update Security Rule"
| where ActivityStatus == "Succeeded"
| project TimeGenerated, Caller, OperationName, ResourceGroup, Resource
QUERY
        }
      },
      {
        type = 3
        name = "sql-failed-auth"
        content = {
          version = "KqlItem/1.0"
          title   = "SQL Failed Authentication"
          query   = <<QUERY
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents"
| where action_name_s == "DATABASE AUTHENTICATION FAILED"
| project TimeGenerated, server_principal_name_s, client_ip_s, database_name_s
QUERY
        }
      },
      {
        type = 3
        name = "defender-high-severity"
        content = {
          version = "KqlItem/1.0"
          title   = "Defender for Cloud High-Severity Alerts"
          query   = <<QUERY
SecurityAlert
| where AlertSeverity == "High"
| project TimeGenerated, AlertName, AlertSeverity, Description, CompromisedEntity
QUERY
        }
      }
    ]
    isLocked = false
  })
}
