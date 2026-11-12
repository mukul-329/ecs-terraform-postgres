resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_db_subnet_ids
  tags       = var.tags
}

resource "aws_db_instance" "this" {
  identifier                   = "${var.name}-postgres"
  engine                       = "postgres"
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  allocated_storage            = var.allocated_storage
  max_allocated_storage        = var.allocated_storage * 2
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = var.database_name
  username                     = var.master_username
  password                     = random_password.master.result
  port                         = 5432
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [var.rds_security_group_id]
  publicly_accessible          = false
  multi_az                     = var.multi_az
  backup_retention_period      = var.backup_retention_period
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = !var.deletion_protection
  final_snapshot_identifier    = var.deletion_protection ? "${var.name}-final-snapshot" : null
  auto_minor_version_upgrade   = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = true
  apply_immediately            = false
  tags                         = var.tags
}
