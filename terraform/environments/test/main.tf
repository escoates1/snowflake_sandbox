module "database" {
  source = "../../modules/database"
  name   = "DWH_TEST"
}

module "warehouse" {
  source = "../../modules/warehouse"
  name   = "WH_TEST"
}