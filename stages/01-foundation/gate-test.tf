# GATE TEST — do not merge. This PR exists to prove the compliance gate blocks
# non-compliant Terraform. Expected: conftest fails on storage.rego and network.rego.
resource "azurerm_storage_account" "gate_test_public" {
  name                            = "stgrcgatetest0001"
  resource_group_name             = azurerm_resource_group.sandbox.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true
  shared_access_key_enabled       = true
}

resource "azurerm_network_security_group" "gate_test_open" {
  name                = "nsg-gate-test"
  location            = var.location
  resource_group_name = azurerm_resource_group.sandbox.name

  security_rule {
    name                       = "ssh-from-internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}
