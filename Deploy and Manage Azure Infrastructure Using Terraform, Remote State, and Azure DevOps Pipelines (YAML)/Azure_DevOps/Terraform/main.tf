terraform {
  backend "azurerm" {
  }
}
# Configure the Azure Provider
provider "azurerm" {
  #While version is optional, we /strongly recommend/ using it to pin the version of the Provider being used
  version = "=2.5.0"
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  features {}
}

resource "azurerm_resource_group" "resourcegroup" {
  name     = "rg-${var.environment}-resources"
  location = "${var.location}"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "network-${var.environment}"
  address_space       = ["${var.virtual_network}"]
  location            = "${azurerm_resource_group.resourcegroup.location}"
  resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
}

resource "azurerm_subnet" "networksubnet" {
  name                       = "subnet-${var.environment}"
  resource_group_name        = "${azurerm_resource_group.resourcegroup.name}"
  virtual_network_name       = "${azurerm_virtual_network.vnet.name}"
  address_prefix             = "${var.internal_subnet}"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.environment}"
  location            = "${azurerm_resource_group.resourcegroup.location}"
  resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
}

resource "azurerm_network_security_rule" "nsgrule" {
   name                        = "Allow-rdp-from-main-office"
   priority                    = 100
   direction                   = "Inbound"
   access                      = "Allow"
   protocol                    = "Tcp"
   source_port_range           = "3389"
   destination_port_range      = "3389"
   source_address_prefix       = "${var.office-WAN}"
   destination_address_prefix  = "*"
   resource_group_name         = "${azurerm_resource_group.resourcegroup.name}"
   network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_network_security_rule" "denyrdpall" {
   name                        = "deny-rdp-all"
   priority                    = 200
   direction                   = "Inbound"
   access                      = "Deny"
   protocol                    = "Tcp"
   source_port_range           = "3389"
   destination_port_range      = "3389"
   source_address_prefix       = "*"
   destination_address_prefix  = "*"
   resource_group_name         = "${azurerm_resource_group.resourcegroup.name}"
   network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_subnet_network_security_group_association" "sga" {
  subnet_id                 = "${azurerm_subnet.networksubnet.id}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
}

resource "azurerm_public_ip" "pip" {
  name                = "pip-${var.environment}"
  resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
  location            = "${azurerm_resource_group.resourcegroup.location}"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.environment}"
  location            = "${azurerm_resource_group.resourcegroup.location}"
  resource_group_name = "${azurerm_resource_group.resourcegroup.name}"

  ip_configuration {
    name                          = "configuration"
    subnet_id                     = "${azurerm_subnet.networksubnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.pip.id}"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "${var.vm_name}"
  location              = "${azurerm_resource_group.resourcegroup.location}"
  resource_group_name   = "${azurerm_resource_group.resourcegroup.name}"
  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size               = "${var.vm_size}"

  # This means the OS Disk will be deleted when Terraform destroys the Virtual Machine
  # NOTE: This may not be optimal in all cases.
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "${var.storageimage_publisher}"
    offer     = "${var.storageimage_offer}"
    sku       = "${var.storageimage_sku}"
    version   = "${var.storageimage_version}"
  }

  storage_os_disk {
    name              = "disk-${var.vm_name}-os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "${var.manageddisk_type}"
  }

  os_profile {
    computer_name  = "${var.vm_name}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }
}
