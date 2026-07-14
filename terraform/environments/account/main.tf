module "role" {
  source = "../../modules/role"

  providers = {
    snowflake = snowflake.securityadmin
  }
}

# Lets DBT_TRANSFORMATIONS (EXECUTE AS CALLER) invoke INGEST_USGS_EARTHQUAKES,
# which needs outbound network access via this integration.
resource "snowflake_grant_privileges_to_account_role" "dbt_external_access_integration" {
  provider = snowflake.securityadmin

  account_role_name = module.role.dbt_runs_role
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "INTEGRATION"
    object_name = "USGS_EARTHQUAKE_ACCESS_INTEGRATION"
  }
}