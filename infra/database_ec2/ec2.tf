module "ec2-instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.0"

  name          = local.ec2.name

  instance_type = "t3.nano"
  key_name      = "keypair"
  monitoring    = true
  subnet_id     = "subnet-06a02b47cb450a697"
  
  vpc_security_group_ids = [module.security-group.security_group_id]
  ami           = "ami-06aa3f7caf3a30282"
  volume_tags   = local.tags
  tags          = local.tags

}

module "security-group" {
  source = "github.com/adexltd/terraform-aws-sg-module"

  name = local.sg.name
  ingress_cidr_blocks = ["10.0.0.0/16"]
  ingress_rules       = ["mysql-tcp", "ssh-tcp"]
  vpc_id              = var.vpc_id //vpc id
  tags = local.tags

}