locals {

  prefix = "${var.owner}-${var.environment}-${var.application}"

  ec2 = {
    name = "${local.prefix}-database"
  }

  sg = {
    name = "${local.prefix}-sg"
  }

  vpc = {
    vpc_cidr = "10.0.0.0/16"
    vpc_id   = "vpc-0929b25093fdba3de"
    private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
  }

  container = {
    name  = "${local.prefix}-container"
    port  = 80
    image = "426857564226.dkr.ecr.us-east-1.amazonaws.com/nginx-image:latest"
  }

  tags = {
    owner       = var.owner
    silo        = var.silo 
    project     = var.project
    terraform   = true
  }
}