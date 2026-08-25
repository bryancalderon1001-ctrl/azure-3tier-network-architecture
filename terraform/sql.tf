resource "random_string" "sql_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "sql_admin" {
  length  = 24
  special = true
}

resource "azurerm_mssql_server" "this" {
  name                          = "sql-3tierlab-iac-${random_string.sql_suffix.result}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.sql_location
  version                       = "12.0"
  administrator_login           = "azureuser"
  administrator_login_password  = random_password.sql_admin.result
  public_network_access_enabled = false
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_mssql_database" "this" {
  name        = "sql_database"
  server_id   = azurerm_mssql_server.this.id
  sku_name    = "Basic"
  max_size_gb = 2
}

resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "Private_DNS_VNet"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "sql" {
  name                = "Sql_Private_Endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.data.id

  private_service_connection {
    name                           = "Private_Connection"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "Private_Dns_Zone_Group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}
