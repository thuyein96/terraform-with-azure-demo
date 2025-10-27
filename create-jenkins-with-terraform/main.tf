terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# --- 1. Basic Setup ---

variable "location" {
  description = "The Azure region to deploy resources."
  default     = "East US"
}

variable "admin_username" {
  description = "Administrator username for the VM."
  default     = "azureuser"
}

resource "azurerm_resource_group" "jenkins_rg" {
  name     = "jenkins-rg-tf"
  location = var.location
}

# --- 2. Networking ---

resource "azurerm_virtual_network" "jenkins_vnet" {
  name                = "jenkins-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.jenkins_rg.location
  resource_group_name = azurerm_resource_group.jenkins_rg.name
}

resource "azurerm_network_security_group" "jenkins_nsg" {
  name                = "jenkins-nsg"
  location            = azurerm_resource_group.jenkins_rg.location
  resource_group_name = azurerm_resource_group.jenkins_rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # For production, lock this to your IP
  }

  security_rule {
    name                       = "AllowJenkins"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*" # For production, lock this to your IP
  }
}

resource "azurerm_subnet" "jenkins_subnet" {
  name                 = "jenkins-subnet"
  resource_group_name  = azurerm_resource_group.jenkins_rg.name
  virtual_network_name = azurerm_virtual_network.jenkins_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  network_security_group_id = azurerm_network_security_group.jenkins_nsg.id
}

resource "azurerm_public_ip" "jenkins_pip" {
  name                = "jenkins-pip"
  location            = azurerm_resource_group.jenkins_rg.location
  resource_group_name = azurerm_resource_group.jenkins_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "jenkins_nic" {
  name                = "jenkins-nic"
  location            = azurerm_resource_group.jenkins_rg.location
  resource_group_name = azurerm_resource_group.jenkins_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jenkins_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins_pip.id
  }
}

# --- 3. The Virtual Machine (Low Cost) ---

resource "azurerm_linux_virtual_machine" "jenkins_vm" {
  name                = "jenkins-server-vm"
  resource_group_name = azurerm_resource_group.jenkins_rg.name
  location            = azurerm_resource_group.jenkins_rg.location
  
  # This is the low-cost B1s size
  size = "Standard_B1s"

  admin_username = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.jenkins_nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    # Reads the public key you created in Step 1
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    # This is the low-cost Standard HDD
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # This runs the cloud-init.yaml script on first boot
  custom_data = base64encode(file("cloud-init.yaml"))
}

# --- 4. Cost-Saving: Auto-Shutdown ---

resource "azurerm_dev_test_global_vm_shutdown_schedule" "jenkins_shutdown" {
  virtual_machine_id = azurerm_linux_virtual_machine.jenkins_vm.id
  location           = azurerm_linux_virtual_machine.jenkins_vm.location
  enabled            = true
  
  # Shuts down at 7:00 PM in your timezone
  daily_recurrence_time = "1900" 
  timezone              = "SE Asia Standard Time" # This is for Bangkok

  notification_settings {
    enabled = false # Set to true and add an email if you want alerts
  }
}

# --- 5. Outputs ---

output "jenkins_public_ip" {
  description = "The public IP address of the Jenkins server."
  value       = azurerm_public_ip.jenkins_pip.ip_address
}

output "jenkins_login_url" {
  description = "URL to access your Jenkins instance."
  value       = "http://${azurerm_public_ip.jenkins_pip.ip_address}:8080"
}

output "get_jenkins_admin_password_command" {
  description = "Run this command to get the initial admin password."
  value       = "ssh -i ~/.ssh/id_rsa ${var.admin_username}@${azurerm_public_ip.jenkins_pip.ip_address} 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"
}