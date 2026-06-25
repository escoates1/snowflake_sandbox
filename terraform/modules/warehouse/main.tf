resource "snowflake_warehouse" "this" {
  name                                = var.name
  warehouse_type                      = "STANDARD"
  warehouse_size                      = var.warehouse_size
  max_cluster_count                   = 1
  min_cluster_count                   = 1
  scaling_policy                      = "ECONOMY"
  auto_suspend                        = var.auto_suspend
  auto_resume                         = true
  initially_suspended                 = true
  comment                             = "Warehouse for BAU operations"
  enable_query_acceleration           = false
  max_concurrency_level               = 4
  statement_queued_timeout_in_seconds = 10
  statement_timeout_in_seconds        = 300
}