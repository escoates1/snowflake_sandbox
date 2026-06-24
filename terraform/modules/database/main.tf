resource "snowflake_database" "this" {
  name = var.name
}

resource "snowflake_schema" "this" {
  for_each = toset(var.schemas)

  database = snowflake_database.this.name
  name     = each.value

  data_retention_time_in_days                   = 1
  max_data_extension_time_in_days               = 10
}
