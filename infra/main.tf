module "network" {
  source                  = "modules/network"
  name                    = local.name
  vpc_cidr                = var.vpc_cidr
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
  availability_zones      = var.availability_zones
  tags                    = local.tags
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Allow public HTTP to ALB"
  vpc_id      = module.network.vpc_id
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "Allow app traffic only from ALB"
  vpc_id      = module.network.vpc_id
  ingress {
    description     = "Application traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Allow PostgreSQL only from ECS tasks"
  vpc_id      = module.network.vpc_id
  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
  tags = local.tags
}

module "ecs" {
  source                 = "modules/ecs"
  name                   = local.name
  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  private_app_subnet_ids = module.network.private_app_subnet_ids
  alb_security_group_id  = aws_security_group.alb.id
  ecs_security_group_id  = aws_security_group.ecs.id
  container_image        = var.container_image
  container_port         = 8080
  desired_count          = var.ecs_desired_count
  task_cpu               = var.ecs_task_cpu
  task_memory            = var.ecs_task_memory
  tags                   = local.tags
}

module "rds" {
  source                  = "modules/rds"
  name                    = local.name
  private_db_subnet_ids   = module.network.private_db_subnet_ids
  rds_security_group_id   = aws_security_group.rds.id
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  backup_retention_period = var.rds_backup_retention_days
  deletion_protection     = var.rds_deletion_protection
  multi_az                = var.rds_multi_az
  database_name           = var.database_name
  master_username         = var.master_username
  tags                    = local.tags
}

output "alb_dns_name" { value = module.ecs.alb_dns_name }
output "rds_endpoint" { value = module.rds.endpoint }
output "rds_database_name" { value = module.rds.database_name }
