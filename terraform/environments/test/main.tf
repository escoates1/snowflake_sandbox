module "database" {
  source = "../../modules/database"
  name   = "DWH_TEST"
}

module "warehouse" {
  source = "../../modules/warehouse"
  name   = "WH_TEST"
}

module "grants" {
  source = "../../modules/grants"

  providers = {
    snowflake = snowflake.securityadmin
  }

  engineer_role_name = var.engineer_role_name
  analyst_role_name  = var.analyst_role_name
  database_name      = module.database.name
  warehouse_name     = module.warehouse.name
  role_members       = var.role_members

  # Ensures database creation before grants are applied
  depends_on = [module.database]
}