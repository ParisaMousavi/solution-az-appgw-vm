module "keyvault_m_id_name" {
  source             = "github.com/ParisaMousavi/az-naming//mid?ref=2022.10.07"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  location_shortname = var.location_shortname
}

module "keyvault_m_id" {
  # https://{PAT}@dev.azure.com/{organization}/{project}/_git/{repo-name}
  source              = "github.com/ParisaMousavi/az-managed-identity?ref=2022.10.24"
  resource_group_name = module.resourcegroup.name
  location            = module.resourcegroup.location
  name                = module.keyvault_m_id_name.result
  additional_tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
}

resource "random_string" "assembly" {
  length  = 2
  lower   = false
  upper   = false
  numeric = true
  special = false
}

module "keyvault_name" {
  source             = "github.com/ParisaMousavi/az-naming//kv?ref=2022.11.30"
  prefix             = var.prefix
  name               = var.name
  stage              = var.stage
  assembly           = random_string.assembly.result
  location_shortname = var.location_shortname
}

module "keyvault" {
  depends_on                      = [module.keyvault_m_id]
  source                          = "github.com/ParisaMousavi/az-key-vault?ref=main"
  resource_group_name             = module.resourcegroup.name
  location                        = module.resourcegroup.location
  name                            = module.keyvault_name.result
  tenant_id                       = var.tenant_id
  stage                           = var.stage
  enabled_for_disk_encryption     = false
  sku_name                        = "standard"
  public_network_access_enabled   = true
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  enable_rbac_authorization       = false
  object_ids                      = [module.keyvault_m_id.principal_id, data.azuread_group.aks_cluster_admin.object_id]
  private_endpoint_config         = {}
  additional_tags = {
    CostCenter = "ABC000CBA"
    By         = "parisamoosavinezhad@hotmail.com"
  }
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
}

# https://learn.microsoft.com/en-us/azure/application-gateway/key-vault-certs
# the SSL certificate is stored in the Key Vault as a Base64-encoded PFX file
# reference : https://learn.microsoft.com/en-us/azure/application-gateway/configure-keyvault-ps#create-a-key-vault-policy-and-certificate-to-be-used-by-the-application-gateway
resource "azurerm_key_vault_certificate" "example" {
  name         = "appgw-generated-cert"
  key_vault_id = module.keyvault.id
  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }
    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      validity_in_months = 12
      subject            = "CN=parisa-dummy"
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
    }
  }
}
