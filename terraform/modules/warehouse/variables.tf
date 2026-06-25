variable "name" {
  type        = string
  description = "Name of the warehouse to create (e.g. WH_DEV)."
}

variable "warehouse_size" {
  type    = string
  default = "XSMALL"
}

variable "auto_suspend" {
  type    = number
  default = 30
}
