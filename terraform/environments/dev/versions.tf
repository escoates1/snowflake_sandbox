terraform {
  required_version = ">= 1.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }

  # Local state for now, one state file per environment (this directory).
  # To move to a remote backend later, add a `backend "..."` block here.
}
