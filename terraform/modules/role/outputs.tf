output "engineer_role_name" {
  description = "Name of the ENGINEER account role."
  value       = snowflake_account_role.engineer_role.name
}

output "analyst_role_name" {
  description = "Name of the ANALYST account role."
  value       = snowflake_account_role.analyst_role.name
}