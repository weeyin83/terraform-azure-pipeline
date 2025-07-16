terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.2.0, < 3.0.0"
    }
  }
backend "azurerm" {
    resource_group_name  = "tfstate-demo-rg"
    storage_account_name = "tfstatetechielass"
    container_name       = "tfstate"
    key                  = "tfdemo.env0.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
  # Configuration options
}

# This is the deployment of the Azure resource group. 
resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = module.naming.resource_group.name_unique

  tags = {
    Environment = var.tag_environment
    Project     = var.tag_project
    Creator     = var.tag_creator
  }
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

#This is the module that deploys a custom DNS zone. 
module "avm-res-network-dnszone" {
  source              = "Azure/avm-res-network-dnszone/azurerm"
  version             = "0.1.0"
  name                = var.custom_domain
  resource_group_name = azurerm_resource_group.rg.name
}

# Deploy Log Analytics Workspace
module "avm-res-operationalinsights-workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.4.2"
  # insert the 3 required variables here
  name                = "log-analytics-workspace"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_telemetry                          = var.enable_telemetry
  log_analytics_workspace_retention_in_days = 60
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_daily_quota_gb    = 200
  log_analytics_workspace_identity = {
    type = "SystemAssigned"
}
}
