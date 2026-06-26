provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.user
  role              = "SYSADMIN" # objects: databases, warehouses

  authenticator = "SNOWFLAKE_JWT"
  private_key   = file(var.private_key_path)
}

provider "snowflake" {
  alias = "securityadmin"

  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.user
  role              = "SECURITYADMIN" # roles + grants

  authenticator = "SNOWFLAKE_JWT"
  private_key   = file(var.private_key_path)
}