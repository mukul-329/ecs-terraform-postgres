variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_app_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "ecs_security_group_id" { type = string }
variable "container_image" { type = string }
variable "container_port" {
  type    = number
  default = 80
}
variable "desired_count" { type = number }
variable "task_cpu" { type = number }
variable "task_memory" { type = number }
variable "tags" {
  type    = map(string)
  default = {}
}
