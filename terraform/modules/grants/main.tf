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
# DBT_TRANSFORMATIONS: least-privilege role for the dbt CI/CD jobs
#################################################################

locals {
  raw_schema     = "\"${var.database_name}\".\"RAW\""
  admin_schema   = "\"${var.database_name}\".\"ADMIN\""
  staging_schema = "\"${var.database_name}\".\"STAGING\""
  marts_schema   = "\"${var.database_name}\".\"MARTS\""
}

# Warehouse
resource "snowflake_grant_privileges_to_account_role" "dbt_warehouse" {
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse_name
  }
}

# Database
resource "snowflake_grant_privileges_to_account_role" "dbt_database" {
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.database_name
  }
}

# RAW schema: read sources, run the ingestion proc, write the tables it touches
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_schema" {
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE"]
  on_schema { schema_name = local.raw_schema }
}

# RAW tables
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_tables" {
  for_each          = toset(["all", "future"])
  account_role_name = var.dbt_role_name
  privileges        = ["SELECT", "INSERT", "TRUNCATE"]
  on_schema_object {
    dynamic "all" {
      for_each = each.key == "all" ? [1] : []
      content {
        object_type_plural = "TABLES"
        in_schema          = local.raw_schema
      }
    }
    dynamic "future" {
      for_each = each.key == "future" ? [1] : []
      content {
        object_type_plural = "TABLES"
        in_schema          = local.raw_schema
      }
    }
  }
}

# RAW stored procedures - both current and future
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_procedures" {
  for_each          = toset(["all", "future"])
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE"]
  on_schema_object {
    dynamic "all" {
      for_each = each.key == "all" ? [1] : []
      content {
        object_type_plural = "PROCEDURES"
        in_schema          = local.raw_schema
      }
    }
    dynamic "future" {
      for_each = each.key == "future" ? [1] : []
      content {
        object_type_plural = "PROCEDURES"
        in_schema          = local.raw_schema
      }
    }
  }
}

# ADMIN schema: read/write the watermark table only
resource "snowflake_grant_privileges_to_account_role" "dbt_admin_schema" {
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE"]
  on_schema { schema_name = local.admin_schema }
}

# ADMIN tables
resource "snowflake_grant_privileges_to_account_role" "dbt_admin_tables" {
  account_role_name = var.dbt_role_name
  privileges        = ["SELECT", "INSERT"]
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = local.admin_schema
    }
  }
}

# STAGING / MARTS schemas: dbt owns table creation here
resource "snowflake_grant_privileges_to_account_role" "dbt_build_schemas" {
  for_each          = toset([local.staging_schema, local.marts_schema])
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE", "CREATE TABLE"]
  on_schema { schema_name = each.value }
}

# STAGING / MARTS tables
resource "snowflake_grant_privileges_to_account_role" "dbt_build_tables" {
  for_each          = toset([local.staging_schema, local.marts_schema])
  account_role_name = var.dbt_role_name
  privileges        = ["ALL"]
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = each.value
    }
  }
}

# PRESENTATION schema: dbt owns view creation here
resource "snowflake_grant_privileges_to_account_role" "dbt_presentation_schema" {
  account_role_name = var.dbt_role_name
  privileges        = ["USAGE", "CREATE VIEW"]
  on_schema { schema_name = local.presentation_schema }
}

# PRESENTATION views
resource "snowflake_grant_privileges_to_account_role" "dbt_presentation_views" {
  account_role_name = var.dbt_role_name
  privileges        = ["ALL"]
  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = local.presentation_schema
    }
  }
}

# One-time + ongoing ownership transfer so that DBT_TRANSFORMATIONS always has ownership
resource "snowflake_grant_ownership" "dbt_build_tables_ownership" {
  for_each = toset([local.staging_schema, local.marts_schema])

  account_role_name   = var.dbt_role_name
  outbound_privileges = "COPY"

  on {
    all {
      object_type_plural = "TABLES"
      in_schema          = each.value
    }
  }
}

resource "snowflake_grant_ownership" "dbt_build_tables_ownership_future" {
  for_each = toset([local.staging_schema, local.marts_schema])

  account_role_name   = var.dbt_role_name
  outbound_privileges = "COPY"

  on {
    future {
      object_type_plural = "TABLES"
      in_schema          = each.value
    }
  }
}

# Same story for the PRESENTATION views
resource "snowflake_grant_ownership" "dbt_presentation_views_ownership" {
  account_role_name   = var.dbt_role_name
  outbound_privileges = "COPY"

  on {
    all {
      object_type_plural = "VIEWS"
      in_schema          = local.presentation_schema
    }
  }
}

resource "snowflake_grant_ownership" "dbt_presentation_views_ownership_future" {
  account_role_name   = var.dbt_role_name
  outbound_privileges = "COPY"

  on {
    future {
      object_type_plural = "VIEWS"
      in_schema          = local.presentation_schema
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

