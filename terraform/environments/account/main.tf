module "role" {
  source = "../../modules/role"

  providers = {
    snowflake = snowflake.securityadmin
  }
}