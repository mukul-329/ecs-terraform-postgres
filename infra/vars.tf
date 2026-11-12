variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_app_subnet_cidrs" { type = list(string) }
variable "private_db_subnet_cidrs" { type = list(string) }
variable "availability_zones" { type = list(string) }
variable "container_image" {
  type    = string
  default = "nginxinc/nginx-unprivileged:1.27-alpine"
}
variable "ecs_desired_count" { type = number }
variable "ecs_task_cpu" { type = number }
variable "ecs_task_memory" { type = number }
variable "rds_engine_version" {
  type    = string
  default = "16.4"
}
variable "rds_instance_class" { type = string }
variable "rds_allocated_storage" { type = number }
variable "rds_backup_retention_days" { type = number }
variable "rds_deletion_protection" { type = bool }
variable "rds_multi_az" { type = bool }
variable "database_name" {
  type    = string
  default = "bookingdb"
}
variable "master_username" {
  type    = string
  default = "dbadmin"
}
