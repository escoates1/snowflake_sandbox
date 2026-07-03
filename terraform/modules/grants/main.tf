locals {
  presentation_schema = "\"${var.database_name}\".\"${var.presentation_schema_name}\""
}

#################################################################
# ANALYST: read-only privileges, only on the PRESENTATION Schema
#################################################################

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

#################################################################
# ENGINEER: read/write privileges on all schemas
#################################################################

# 1. Warehouse
resource "snowflake_grant_privileges_to_account_role" "engineer_warehouse" {
  account_role_name = var.engineer_role_name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse_name
  }
}

# 2. Database
resource "snowflake_grant_privileges_to_account_role" "engineer_database" {
  account_role_name = var.engineer_role_name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# 3a. Schema
resource "snowflake_grant_privileges_to_account_role" "engineer_existing_schema" {
  account_role_name = var.engineer_role_name
  privileges = [
    "USAGE",
    "CREATE TABLE",
    "CREATE VIEW",
    "CREATE STAGE",
    "CREATE FILE FORMAT",
    "CREATE FUNCTION",
    "CREATE PROCEDURE",
    "CREATE SEQUENCE",
    "CREATE STREAM",
    "CREATE TASK",
    "CREATE DYNAMIC TABLE",
    # "CREATE MATERIALIZED VIEW" - not supported on Standard edition of Snowflake
  ]

  on_schema {
    all_schemas_in_database = var.database_name
  }
}

# 3b. Schema - existing
resource "snowflake_grant_privileges_to_account_role" "engineer_future_schema" {
  account_role_name = var.engineer_role_name
  privileges = [
    "USAGE",
    "CREATE TABLE",
    "CREATE VIEW",
    "CREATE STAGE",
    "CREATE FILE FORMAT",
    "CREATE FUNCTION",
    "CREATE PROCEDURE",
    "CREATE SEQUENCE",
    "CREATE STREAM",
    "CREATE TASK",
    "CREATE DYNAMIC TABLE",
    # "CREATE MATERIALIZED VIEW" - not supported on Standard edition of Snowflake
  ]

  on_schema {
    future_schemas_in_database = var.database_name
  }
}

# 4a. Tables - existing
resource "snowflake_grant_privileges_to_account_role" "engineer_existing_tables" {
  account_role_name = var.engineer_role_name
  privileges        = ["ALL"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_database        = var.database_name
    }
  }
}

# 4b. Tables - future
resource "snowflake_grant_privileges_to_account_role" "engineer_future_tables" {
  account_role_name = var.engineer_role_name
  privileges        = ["ALL"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_database        = var.database_name
    }
  }
}

# 5a. Views - existing
resource "snowflake_grant_privileges_to_account_role" "engineer_existing_views" {
  account_role_name = var.engineer_role_name
  privileges        = ["ALL"]

  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_database        = var.database_name
    }
  }
}

# 5b. Views - future
resource "snowflake_grant_privileges_to_account_role" "engineer_future_views" {
  account_role_name = var.engineer_role_name
  privileges        = ["ALL"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_database        = var.database_name
    }
  }
}

#################################################################
# Grant roles to users
#################################################################

locals {
  # Turn {ENGINEER = [a, b], ANALYST = [b]} into
  # {"ENGINEER__a" = {...}, "ENGINEER__b" = {...}, "ANALYST__b" = {...}}
  role_member_grants = merge([
    for role, users in var.role_members : {
      for user in users : "${role}__${user}" => {
        role = role
        user = user
      }
    }
  ]...) # the ... spreads the list of maps into merge()
}

resource "snowflake_grant_account_role" "member" {
  for_each = local.role_member_grants

  role_name = each.value.role
  user_name = each.value.user
}