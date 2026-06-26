locals {
  presentation_schema = "\"${var.database_name}\".\"${var.presentation_schema_name}\""
}

# ----------------------------- ANALYST -----------------------------
# Read-only privileges, only on the PRESENTATION Schema

# 1. Warehouse
resource "snowflake_grant_privileges_to_account_role" "analyst_warehouse" {
  account_role_name = var.analyst_role_name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse_name
  }
}

# 2. Database
resource "snowflake_grant_privileges_to_account_role" "analyst_database" {
  account_role_name = var.analyst_role_name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# 3. Schema
resource "snowflake_grant_privileges_to_account_role" "analyst_schema" {
  account_role_name = var.analyst_role_name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = local.presentation_schema
  }
}

# 4a. Tables - existing
resource "snowflake_grant_privileges_to_account_role" "analyst_existing_tables" {
  account_role_name = var.analyst_role_name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = local.presentation_schema
    }
  }
}

# 4b. Tables - future
resource "snowflake_grant_privileges_to_account_role" "analyst_future_tables" {
  account_role_name = var.analyst_role_name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = local.presentation_schema
    }
  }
}

# 5a. Views - existing
resource "snowflake_grant_privileges_to_account_role" "analyst_existing_views" {
  account_role_name = var.analyst_role_name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = local.presentation_schema
    }
  }
}

# 5b. Views - future
resource "snowflake_grant_privileges_to_account_role" "analyst_future_views" {
  account_role_name = var.analyst_role_name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = local.presentation_schema
    }
  }
}