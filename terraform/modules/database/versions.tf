terraform {
  required_providers {
    snowflake = {
      # Maps the local name "snowflake" to the correct provider source.
      # Without this, Terraform assumes "hashicorp/snowflake", which does not exist.
      # Version constraint is intentionally left to the root module.
      source = "snowflakedb/snowflake"
    }
  }
}
