locals {
  name = "booking-${var.environment}"
  tags = {
    Project     = "terraform-database-reliability"
    Environment = var.environment
  }
}