variable "location" {
  description = "Azure region for foundation resources."
  type        = string
  default     = "eastus"
}

variable "owner_email" {
  description = "Owner tag applied to governed resource groups; the POA&M generator resolves finding owners from it."
  type        = string
}

variable "environment" {
  description = "Environment name used in tags and resource names."
  type        = string
  default     = "dev"
}

variable "tag_policy_effect" {
  description = "Effect for the require-env-tag policy (Audit while onboarding, Deny once clean)."
  type        = string
  default     = "Audit"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.tag_policy_effect)
    error_message = "tag_policy_effect must be Audit, Deny, or Disabled."
  }
}

variable "public_blob_policy_effect" {
  description = "Effect for the deny-public-blob-access policy. This one has earned Deny."
  type        = string
  default     = "Deny"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.public_blob_policy_effect)
    error_message = "public_blob_policy_effect must be Audit, Deny, or Disabled."
  }
}

# --- Capstone additions: new controls start at Audit (observe before you block). ---

variable "nsg_mgmt_ports_effect" {
  description = "Effect for the no-SSH/RDP-from-internet NSG policy. Audit while the estate is cleaned up; Deny once findings reach zero."
  type        = string
  default     = "Audit"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.nsg_mgmt_ports_effect)
    error_message = "nsg_mgmt_ports_effect must be Audit, Deny, or Disabled."
  }
}

variable "storage_https_effect" {
  description = "Effect for the storage secure-transfer (HTTPS-only) policy."
  type        = string
  default     = "Audit"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.storage_https_effect)
    error_message = "storage_https_effect must be Audit, Deny, or Disabled."
  }
}
