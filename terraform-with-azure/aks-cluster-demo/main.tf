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

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "my-first-aks-cluster"
  location            = var.rg_location
  resource_group_name = var.rg_name
  dns_prefix          = "my-first-aks-dns"

  default_node_pool {
    name       = "default"
    node_count = 1 
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}