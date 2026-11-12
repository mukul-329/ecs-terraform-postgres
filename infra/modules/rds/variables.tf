variable "name" { type = string }
variable "private_db_subnet_ids" { type = list(string) }
variable "rds_security_group_id" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "backup_retention_period" { type = number }
variable "deletion_protection" { type = bool }
variable "multi_az" { type = bool }
variable "database_name" { type = string }
variable "master_username" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
