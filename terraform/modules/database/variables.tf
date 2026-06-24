variable "name" {
  type        = string
  description = "Name of the database to create (e.g. DWH_DEV)."
}

variable "schemas" {
  type        = list(string)
  description = "Schemas to create inside the database."
  default     = ["RAW", "STAGING", "CONFORMED", "PRESENTATION"]
}
