module "database" {
  source = "../../modules/database"
  name   = "DWH_DEV"
}

module "warehouse" {
  source = "../../modules/warehouse"
  name   = "WH_DEV"
}

module "role" {
  source = "../../modules/role"
}

module "grants" {
  source = "../../modules/grants"

  engineer_role_name = module.role.engineer_role_name
  analyst_role_name  = module.role.analyst_role_name
  database_name      = module.database.name
  warehouse_name     = module.warehouse.name

  # Ensures database creation before grants are applied
  depends_on = [module.database]
}