terraform {
  required_version = ">= 1.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.17.0"
    }
  }

  cloud {
    organization = "escoates1-org"
    workspaces {
      name = "snowflake-sandbox-test"
    }
  }
}


