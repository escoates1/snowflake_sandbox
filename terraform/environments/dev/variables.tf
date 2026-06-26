# Snowflake connection inputs. Real values live in the gitignored
# terraform.tfvars; see terraform.tfvars.example for the template.

variable "organization_name" {
  type        = string
  description = "Org half of the account identifier (the part before the '-')."
}

variable "account_name" {
  type        = string
  description = "Account half of the account identifier (the part after the '-')."
}

variable "user" {
  type        = string
  description = "Snowflake user to authenticate as (the Terraform service user)."
  default     = "TERRAFORM_USER"
}

variable "role" {
  type        = string
  description = "Role to assume. SYSADMIN for databases/schemas/warehouses; SECURITYADMIN for roles/grants."
  default     = "SYSADMIN"
}

variable "private_key_path" {
  type        = string
  description = "Absolute path to the unencrypted PKCS#8 private key (rsa_key.p8)."
}

# --------------------------------- WAREHOUSES ---------------------------------
variable "warehouse_size" {
  type        = string
  description = "Snowflake warehouse size for this environment."
  default     = "XSMALL"
}

# ----------------------------------- GRANTS -----------------------------------
variable "engineer_role_name" {
  type        = string
  description = "Account role granted read/write across all schemas."
  default     = "ENGINEER"
}

variable "analyst_role_name" {
  type        = string
  description = "Account role granted read-only access to PRESENTATION."
  default     = "ANALYST"
}
