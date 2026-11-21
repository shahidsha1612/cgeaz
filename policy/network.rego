# Gate rule (capstone addition): the shift-left twin of the
# cge-nsg-no-mgmt-ports-from-internet Azure Policy. The platform policy catches it in
# the estate; this catches it in the PR, before it exists. Same rule, two layers.
package main

import rego.v1

internet_sources := {"*", "Internet", "0.0.0.0/0", "::/0", "any"}

mgmt_ports := {"22", "3389", "*"}

# Inline rules on azurerm_network_security_group
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_network_security_group"
	rc.change.actions[_] != "delete"
	some rule in rc.change.after.security_rule
	open_mgmt(rule)
	msg := sprintf("%s: rule %q allows SSH/RDP inbound from the internet", [rc.address, rule.name])
}

# Standalone azurerm_network_security_rule
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_network_security_rule"
	rc.change.actions[_] != "delete"
	open_mgmt(rc.change.after)
	msg := sprintf("%s: allows SSH/RDP inbound from the internet", [rc.address])
}

open_mgmt(rule) if {
	rule.access == "Allow"
	rule.direction == "Inbound"
	from_internet(rule)
	to_mgmt_port(rule)
}

from_internet(rule) if rule.source_address_prefix in internet_sources

from_internet(rule) if {
	some p in rule.source_address_prefixes
	p in internet_sources
}

to_mgmt_port(rule) if rule.destination_port_range in mgmt_ports

to_mgmt_port(rule) if {
	some p in rule.destination_port_ranges
	p in mgmt_ports
}
