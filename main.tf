# https://learn.microsoft.com/en-us/azure/developer/terraform/deploy-application-gateway-v2
module "rg_name" {
  source             = "github.com/ParisaMousavi/az-naming//rg?ref=2022.10.07"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  location_shortname = var.location_shortname
}

module "resourcegroup" {
  # https://{PAT}@dev.azure.com/{organization}/{project}/_git/{repo-name}
  source   = "github.com/ParisaMousavi/az-resourcegroup?ref=2022.10.07"
  location = var.location
  name     = module.rg_name.result
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

#-----------------------------------------------
#  Deploy web servers
#-----------------------------------------------
module "vm_name" {
  source             = "github.com/ParisaMousavi/az-naming//vm?ref=main"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  location_shortname = var.location_shortname
}

# resource "azurerm_public_ip" "this_win" {
#   name                = "${module.vm_name.result}-pip"
#   location            = module.resourcegroup.location
#   resource_group_name = module.resourcegroup.name
#   allocation_method   = "Static"

#   tags = {
#     environment = "Production"
#   }
# }

resource "azurerm_network_interface" "this_win" {
  name                = "${module.vm_name.result}-nic"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name

  ip_configuration {
    primary                       = true
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.network.outputs.subnets["vm-win"].id
    private_ip_address_allocation = "Dynamic"
    # public_ip_address_id          = azurerm_public_ip.this_win.id
  }
}


#----------------------------------------------
#       For Win Machine (web server)
#----------------------------------------------
module "nsg_win_name" {
  source             = "github.com/ParisaMousavi/az-naming//nsg?ref=main"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  assembly           = "win"
  location_shortname = var.location_shortname
}

# Reference link: https://github.com/Flodu31/Terraform/blob/master/Deploy_New_Environment_Provisioners/modules/2-windows_vm/1-virtual-machine.tf
module "nsg_win" {
  source              = "github.com/ParisaMousavi/az-nsg-v2?ref=main"
  name                = module.nsg_win_name.result
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  security_rules = [
    {
      name                       = "HTTP"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      description                = "HTTP: Allow inbound from any to 80"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
  additional_tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

resource "azurerm_network_interface_security_group_association" "this_win" {
  network_interface_id      = azurerm_network_interface.this_win.id
  network_security_group_id = module.nsg_win.id
}

resource "azurerm_windows_virtual_machine" "this_win" {
  name                = module.vm_name.result
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  size                = "Standard_D4s_v4" #"Standard_B2s" #"Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.this_win.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # az vm image list --all --publisher "MicrosoftWindowsServer" --location westeurope --offer "WindowsServer"
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

}

#used this link for installing IIS: https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/08/az104-08-install_IIS.ps1
resource "azurerm_virtual_machine_extension" "example" {
  name                       = "vm_extension_install_iis"
  virtual_machine_id         = azurerm_windows_virtual_machine.this_win.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  settings                   = <<SETTINGS
{
	"commandToExecute": "powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools && powershell.exe remove-item 'C:\\inetpub\\wwwroot\\iisstart.htm' && powershell.exe Add-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value $($env:computername)"
}
SETTINGS
  tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

#-----------------------------------------------
#  Application Gateway
#-----------------------------------------------
resource "azurerm_public_ip" "pip" {
  name                = "myAGPublicIPAddress"
  location            = module.resourcegroup.location
  resource_group_name = module.resourcegroup.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

locals {
  backend_address_pool_name      = "example-appgateway-beap"
  frontend_port_name             = "example-appgateway-feport"
  frontend_ip_configuration_name = "example-appgateway-feip"
  http_setting_name              = "example-appgateway-be-htst"
  listener_name                  = "example-appgateway-httplstn"
  request_routing_rule_name      = "example-appgateway-rqrt"
  redirect_configuration_name    = "example-appgateway-rdrcfg"
}

# resource "azurerm_application_gateway" "network" {
#   depends_on = [ azurerm_public_ip.pip ]
#   name                = "example-appgateway"
#   location            = module.resourcegroup.location
#   resource_group_name = module.resourcegroup.name

#   sku {
#     name     = "Standard_Small"
#     tier     = "Standard"
#     capacity = 2
#   }

#   gateway_ip_configuration {
#     name      = "my-gateway-ip-configuration"
#     subnet_id = data.terraform_remote_state.network.outputs.subnets["appgw"].id
#   }

#   frontend_port {
#     name = local.frontend_port_name
#     port = 80
#   }

#   frontend_ip_configuration {
#     name                 = local.frontend_ip_configuration_name
#     public_ip_address_id = azurerm_public_ip.pip.id
#   }

#   backend_address_pool {
#     name = local.backend_address_pool_name
#   }

#   backend_http_settings {
#     name                  = local.http_setting_name
#     cookie_based_affinity = "Disabled"
#     path                  = "/path1/"
#     port                  = 80
#     protocol              = "Http"
#     request_timeout       = 60
#   }

#   http_listener {
#     name                           = local.listener_name
#     frontend_ip_configuration_name = local.frontend_ip_configuration_name
#     frontend_port_name             = local.frontend_port_name
#     protocol                       = "Http"
#   }

#   request_routing_rule {
#     name                       = local.request_routing_rule_name
#     rule_type                  = "Basic"
#     http_listener_name         = local.listener_name
#     backend_address_pool_name  = local.backend_address_pool_name
#     backend_http_settings_name = local.http_setting_name
#   }
# }