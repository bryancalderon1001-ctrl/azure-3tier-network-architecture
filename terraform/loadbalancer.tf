resource "azurerm_public_ip" "lb" {
  name                = "load_balancer_ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "this" {
  name                = "load_balancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "lb_frontend_ip"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  loadbalancer_id = azurerm_lb.this.id
  name            = "lb_backend_ip_pool"
}

resource "azurerm_lb_probe" "this" {
  loadbalancer_id = azurerm_lb.this.id
  name            = "health_check_web"
  protocol        = "Http"
  port            = 80
  request_path    = "/health"
}

resource "azurerm_lb_rule" "this" {
  loadbalancer_id                 = azurerm_lb.this.id 
  name                            = "load_balancer_rule"
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
  frontend_ip_configuration_name  = "lb_frontend_ip"
  backend_address_pool_ids        = [azurerm_lb_backend_address_pool.this.id]
  probe_id                        = azurerm_lb_probe.this.id
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
  network_interface_id    = azurerm_network_interface.web.id
  ip_configuration_name   = "web_nic"
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
}
