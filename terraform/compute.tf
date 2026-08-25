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
  name                  = "vm-app"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = "Standard_B2pts_v2"
  admin_username        = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.app.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
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

resource "azurerm_network_interface" "web" {
  name                            = "vm_web_nic"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.this.name
  ip_configuration {
    name                          = "web_nic"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_application_security_group_association" "web" {
  network_interface_id          = azurerm_network_interface.web.id
  application_security_group_id = azurerm_application_security_group.web.id
}

resource "azurerm_linux_virtual_machine" "web" {
  name                  = "vm-web"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = "Standard_B2pts_v2"
  admin_username        = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.web.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

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

   custom_data = base64encode(templatefile("${path.module}/scripts/bootstrap_web.sh.tpl", {
     nginx_config    = templatefile("${path.module}/scripts/nginx.conf.tpl", {
       app_private_ip = azurerm_network_interface.app.private_ip_address
     })
   }))  
}
