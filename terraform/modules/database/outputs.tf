output "name" {
  description = "Name of the created database."
  value       = snowflake_database.this.name
}

output "schemas" {
  description = "Names of the schemas created in the database."
  value       = [for s in snowflake_schema.this : s.name]
}
