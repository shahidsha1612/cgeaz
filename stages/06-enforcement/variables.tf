variable "remediation_mode" {
  description = "Escalation ladder: audit -> dry-run -> enforce. Each step up should be a reviewed PR — automation acts, humans authorize."
  type        = string
  default     = "dry-run"
  validation {
    condition     = contains(["audit", "dry-run", "enforce"], var.remediation_mode)
    error_message = "remediation_mode must be audit, dry-run, or enforce."
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "state_resource_group" {
  type    = string
  default = "rg-grc-tfstate"
}

variable "state_storage_account" {
  type = string
}

variable "owner_email" {
  description = "Where the portal-change tripwire alert is sent. CI supplies it from the OWNER_EMAIL repo variable; never commit a real address."
  type        = string
}
