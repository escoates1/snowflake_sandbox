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
  sensitive   = true
}