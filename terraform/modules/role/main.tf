resource "snowflake_account_role" "engineer_role" {
  name    = "ENGINEER"
  comment = "Engineering role used for all database operations and development."
}

resource "snowflake_account_role" "analyst_role" {
  name    = "ANALYST"
  comment = "Analyst role used for querying object for downstream purposes."
}