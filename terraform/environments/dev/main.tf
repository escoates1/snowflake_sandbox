module "database" {
  source = "../../modules/database"
  name   = "DWH_DEV"
}

module "warehouse" {
  source = "../../modules/warehouse"
  name   = "WH_DEV"
}