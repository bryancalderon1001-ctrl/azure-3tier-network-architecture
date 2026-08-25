variable "location" { 
  type        = string
  default     = "South Central US"
  description = "Azure region for all resources in this environment"
}

variable "resource_group_name" {
  type        = string
  default     = "rg-3tierlab-iac-southcentralus"
  description = "Resource Group name for all resources in this environment"
}

variable "vnet_name" {
  type        = string
  default     = "vnet-3tierlab-iac-southcentralus"
  description = "Single vnet for environment"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "One vnet with multiple subnets"
}

variable "subnet_address_space" {
  type    = map(string)
  default = {
    subnet_web_prefix  = "10.0.0.0/24"
    subnet_app_prefix  = "10.0.1.0/24"
    subnet_data_prefix = "10.0.2.0/24"
  }
  description = "Three subnets for 3-tier network architecture"
}

variable "sql_location" {
  type        = string
  default     = "West US 3"
  description = "Exception to the US South Central Region"
}


# CI/CD pipeline test
