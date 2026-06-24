# Authenticates as the Terraform service user via key-pair (JWT).
# No secrets are stored here — connection values come from variables, and the
# private key is read from disk at apply time, never committed.

provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.user
  role              = var.role

  authenticator = "SNOWFLAKE_JWT"
  private_key   = file(var.private_key_path)
}
