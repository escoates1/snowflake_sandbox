variable "engineer_role_name" {
  type        = string
  description = "Name of the ENGINEER role to grant privileges to."
}

variable "analyst_role_name" {
  type        = string
  description = "Name of the ANALYST role to grant privileges to."
}

variable "dbt_role_name" {
  type        = string
  description = "Name of the DBT_TRANSFORMATIONS role to grant privileges to."
}

variable "database_name" {
  type        = string
  description = "Database the roles operate on (e.g. DWH_DEV)."
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse the roles use to run queries (e.g. WH_DEV)."
}

variable "presentation_schema_name" {
  type        = string
  description = "Schema the ANALYST role gets read access to."
  default     = "PRESENTATION"
}

variable "role_members" {
  description = "Account role name -> list of users that should hold it."
  type        = map(list(string))
  default     = {}
}