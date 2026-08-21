resource "azurerm_network_interface" "app" {
  name                = "vm_app_nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  ip_configuration {
    name                          = "app_nic"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_application_security_group_association" "app" {
  network_interface_id          = azurerm_network_interface.app.id
  application_security_group_id = azurerm_application_security_group.app.id
}

resource "azurerm_linux_virtual_machine" "app" {
  name                  = "vm_app"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = "B2pts_v2"
  admin_username        = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.app.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("/home/bc/.ssh/azure_3tierlab_iac.pub")
  }
  
  identity {
    type = "SystemAssigned"
  }

    custom_data = base64encode(templatefile("${path.module}/scripts/bootstrap_app.sh.tpl", {
    app_py_content  = file("${path.module}/scripts/app.py")
    key_vault_uri   = azurerm_key_vault.this.vault_uri
    sql_server_fqdn = azurerm_mssql_server.this.fully_qualified_domain_name
    sql_database    = azurerm_mssql_database.this.name
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }
}

resource "azurerm_role_assignment" "app_kv_access" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.app.identity[0].principal_id
}
