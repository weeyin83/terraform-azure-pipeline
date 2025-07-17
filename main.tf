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


resource "azurerm_communication_service" "acs" {
  name                = var.acs_name
  resource_group_name = azurerm_resource_group.rg.name
  data_location       = var.data_location
}

resource "azurerm_email_communication_service" "acsemail" {
  name                = "${module.naming.resource_group.name_unique}-email"
  resource_group_name = azurerm_resource_group.rg.name
  data_location       = var.data_location
}

resource "azurerm_email_communication_service_domain" "acsdomain" {
  name             = var.custom_domain
  email_service_id = azurerm_email_communication_service.acsemail.id

  domain_management = "CustomerManaged"
}

# Create a TXT record for domain verification in the DNS zone
resource "azurerm_dns_txt_record" "domain" {
  count               = 1
  name                = "@"
  zone_name           = var.custom_domain
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = var.ttl_setting

  # Add the TXT record for domain verification
  record {
    value = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].domain[*].value, count.index)
  }

  # Add record for SPF Verification
  record {
    value = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].spf[*].value, count.index)
  }

  # Ensure the ACS Email service & Azure DNS serviec has been deployed before creating these records
  depends_on = [azurerm_email_communication_service_domain.acsdomain]
}

# Create a CNAME record for DKIM verification in the DNS zone
resource "azurerm_dns_cname_record" "dkim" {
  count               = 1
  name                = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim[*].name, count.index)
  zone_name           = var.custom_domain
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim[*].ttl, count.index)
  record              = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim[*].value, count.index)

  # Ensure the ACS Email service & Azure DNS serviec has been deployed before creating these records
  depends_on = [azurerm_email_communication_service_domain.acsdomain]
}

# Create a CNAME record for DKIM2 verification in the DNS zone
resource "azurerm_dns_cname_record" "dkim2" {
  count               = 1
  name                = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim2[*].name, count.index)
  zone_name           = var.custom_domain
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim2[*].ttl, count.index)
  record              = element(azurerm_email_communication_service_domain.acsdomain.verification_records[0].dkim2[*].value, count.index)

  # Ensure the ACS Email service & Azure DNS serviec has been deployed before creating these records
  depends_on = [azurerm_email_communication_service_domain.acsdomain]
}

# Initiate Domain Verification
# API: https://learn.microsoft.com/en-us/rest/api/communication/resourcemanager/domains/initiate-verification?view=rest-communication-resourcemanager-2023-03-31&tabs=HTTP
resource "azapi_resource_action" "validate_domain" {
  count       = 1
  type        = "Microsoft.Communication/emailServices/domains@2023-03-31"
  action      = "initiateVerification"
  resource_id = azurerm_email_communication_service_domain.acsdomain.id

  body = {
    verificationType = "Domain" # or use "SPF", "DKIM", "DMARC", "DKIM2" as needed
  }
  depends_on = [azurerm_dns_txt_record.domain]
}

# Initiate SPF Verification
# API: https://learn.microsoft.com/en-us/rest/api/communication/resourcemanager/domains/initiate-verification?view=rest-communication-resourcemanager-2023-03-31&tabs=HTTP
resource "azapi_resource_action" "validate_spf" {
  count       = 1
  type        = "Microsoft.Communication/emailServices/domains@2023-03-31"
  action      = "initiateVerification"
  resource_id = azurerm_email_communication_service_domain.acsdomain.id

  body = {
    verificationType = "SPF" # or use "SPF", "DKIM", "DMARC", "DKIM2" as needed
  }
  depends_on = [azapi_resource_action.validate_domain]
}

# Initiate DKIM Verification
# API: https://learn.microsoft.com/en-us/rest/api/communication/resourcemanager/domains/initiate-verification?view=rest-communication-resourcemanager-2023-03-31&tabs=HTTP
resource "azapi_resource_action" "validate_dkim" {
  count       = 1
  type        = "Microsoft.Communication/emailServices/domains@2023-03-31"
  action      = "initiateVerification"
  resource_id = azurerm_email_communication_service_domain.acsdomain.id

  body = {
    verificationType = "DKIM" # or use "SPF", "DKIM", "DMARC", "DKIM2" as needed
  }
  depends_on = [azapi_resource_action.validate_spf]
}

# Initiate DKIM2 Verification
# API: https://learn.microsoft.com/en-us/rest/api/communication/resourcemanager/domains/initiate-verification?view=rest-communication-resourcemanager-2023-03-31&tabs=HTTP
resource "azapi_resource_action" "validate_dkim2" {
  count       = 1
  type        = "Microsoft.Communication/emailServices/domains@2023-03-31"
  action      = "initiateVerification"
  resource_id = azurerm_email_communication_service_domain.acsdomain.id

  body = {
    verificationType = "DKIM2" # or use "SPF", "DKIM", "DMARC", "DKIM2" as needed
  }
  depends_on = [azapi_resource_action.validate_dkim]
}

# Association of the Email Domain with the Communication Service
resource "azurerm_communication_service_email_domain_association" "email_domain_association" {
  communication_service_id = azurerm_communication_service.acs.id
  email_service_domain_id  = azurerm_email_communication_service_domain.acsdomain.id
  depends_on               = [azapi_resource_action.validate_dkim2]
}

# Turn on logs being sent to a Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "acs-logs" {
  name                           = module.avm-res-operationalinsights-workspace.log_analytics_workspace.resource.name
  target_resource_id             = azurerm_communication_service.acs.id
  log_analytics_workspace_id     = module.avm-res-operationalinsights-workspace.log_analytics_workspace.resource.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "EmailSendMailOperational"
  }

  enabled_log {
    category = "Usage"
  }

  enabled_log {
    category = "EmailStatusUpdateOperational"
  }

  enabled_log {
    category = "EmailUserEngagementOperational"
  }

  metric {
    category = "AllMetrics"
  }
}