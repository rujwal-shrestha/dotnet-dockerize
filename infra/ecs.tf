# data "aws_availability_zones" "available" {}

################################################################################
# Cluster
################################################################################

module "ecs_cluster" {
  source       = "github.com/adexltd/terraform-aws-ecs-module/tree/K812-Modules-updates"
  cluster_name = "${local.prefix}-cluster"

  cluster_settings = {
    "name" : "containerInsights",
    "value" : "enabled"
  }

  # Capacity provider - autoscaling groups
  default_capacity_provider_use_fargate = false

  autoscaling_capacity_providers = {
    ex-1 = {
      auto_scaling_group_arn         = module.autoscaling["ex-1"].autoscaling_group_arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 2
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 60
      }

      default_capacity_provider_strategy = {
        weight = 70
        base   = 20
      }
    }
  }

  # Service
  services = [{
    name         = "${local.prefix}-service"
    launch_type  = "EC2"
    cluster_arn  = module.ecs_cluster.cluster_arn
    cluster_name = module.ecs_cluster.cluster_name
    family       = local.prefix #unique name for task defination

    # cpu                               = 1536
    # memory                            = 3072
    health_check_grace_period_seconds = 15


    create_task_exec_iam_role = true # Create IAM role for task execution (Uses Managed AmazonECSTaskExecutionRolePolicy)
    create_task_exec_policy   = true # Create IAM policy for task execution (Uses Managed AmazonECSTaskExecutionRolePolicy)

    task_exec_iam_role_name = "${local.service.name}-role"
    tasks_iam_role_name     = "${local.service.name}-task-role"

    iam_role_use_name_prefix = false

    enable_execute_command         = true
    tasks_iam_role_use_name_prefix = false
    create_tasks_iam_role          = true #ECS Task Role

    security_group_name = "${local.prefix}-sg"

    network_configuration = {
      subnets = module.vpc.private_subnets
    }

    # Task Definition
    requires_compatibilities = ["EC2"]
    capacity_provider_strategy = {
      # On-demand instances
      ex-1 = {
        capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["ex-1"].name
        weight            = 1
        base              = 1
      }
    }

    create_iam_role        = true # ECS Service IAM Role: Allows Amazon ECS to make calls to your load balancer on your behalf.
    create_task_definition = true
    create_tasks_iam_role  = true #ECS Task Role


    # Container definition(s)
    container_definitions = jsonencode([
      {
        name      = local.container.name
        image     = local.container.image
        cpu       = 1024
        memory    = 512
        essential = true
        environment = [
          {
            "DB_HOST"     : var.db_host
            "DB_PORT"     : var.db_port
            "DB_NAME"     : var.db_name
            "DB_USER"     : var.user
            "DB_PASSWORD" : var.password
          }
        ]
        portMappings = [
          {
            name          = local.container.name
            containerPort = local.container.port
            hostPort      = local.container.port
            protocol      = "tcp"
          }
        ]
      },
    ])
    subnet_ids = local.vpc.private_subnets

    load_balancer = {
      service = {
        target_group_arn = element(module.alb.target_group_arns, 0)
        container_name   = local.container.name
        container_port   = local.container.port
      }
    }

    security_group_rules = {
      alb_ingress_80 = {
        type        = "ingress"
        from_port   = local.container.port
        to_port     = local.container.port
        protocol    = "tcp"
        description = "Service port"
        cidr_blocks = [local.vpc.vpc_cidr]
      }
      egress_all = {
        type        = "egress"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }


  }]
  # depends_on = [module.autoscaling]
  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

module "alb_sg" {
  source = "terraform-aws-modules/security-group/aws"
  #checkov:skip=CKV_TF_1: "Ensure Terraform module sources use a commit hash"
  version = "~> 5.0"

  name        = "${local.prefix}-alb-sg"
  description = "Service security group"
  vpc_id      = local.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  # egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  egress_cidr_blocks = local.vpc.private_subnets

  tags = local.tags

}

module "alb" {
  source = "terraform-aws-modules/alb/aws"
  #checkov:skip=CKV_TF_1: "Ensure Terraform module sources use a commit hash"
  version = "~> 6.0"

  name = "${local.prefix}-alb"

  load_balancer_type = "application"

  vpc_id          = local.vpc.vpc_id
  subnets         = local.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = "tls-tg"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
    },
  ]
  tags = local.tags

}

module "autoscaling" {
  source = "terraform-aws-modules/autoscaling/aws"
  #checkov:skip=CKV_TF_1: "Ensure Terraform module sources use a commit hash"
  version = "~> 6.5"

  for_each = {
    # On-demand instances
    ex-1 = {
      instance_type              = "t2.micro"
      use_mixed_instances_policy = false
      mixed_instances_policy     = {}
      user_data                  = <<-EOT
        #!/bin/bash
        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.prefix}-cluster
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        ECS_IMAGE_PULL_BEHAVIOR=prefer-cached
        EOF
      EOT
    }
    # Spot instances
    ex-2 = {
      instance_type              = "t2.medium"
      use_mixed_instances_policy = false
      user_data                  = <<-EOT
        #!/bin/bash
        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.prefix}-cluster
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
        ECS_IMAGE_PULL_BEHAVIOR=prefer-cached
        EOF
      EOT
    }
  }

  name = "${local.prefix}-${each.key}"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  security_groups                 = [module.autoscaling_sg.security_group_id]
  user_data                       = base64encode(each.value.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = local.prefix
  iam_role_description        = "ECS role for ${local.prefix}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = local.vpc.private_subnets
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # Required for  managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  tags = local.tags
}

module "autoscaling_sg" {
  source = "terraform-aws-modules/security-group/aws"
  #checkov:skip=CKV_TF_1: "Ensure Terraform module sources use a commit hash"
  version = "~> 5.0"

  name        = "${local.prefix}-autoscaling-sg"
  description = "Autoscaling group security group"
  vpc_id      = local.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1

  egress_rules = ["all-all"]

  tags = local.tags
}

resource "null_resource" "scale_down_asg" {
  triggers = {
    asg_name = module.autoscaling[keys(module.autoscaling)[0]].autoscaling_group_name
  }

  # Only run during destroy, do nothing for apply.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "${self.triggers.asg_name}" --force-delete
  EOT
  }
}

resource "null_resource" "scale_down_asg_2" {
  triggers = {
    asg_name = module.autoscaling[keys(module.autoscaling)[1]].autoscaling_group_name
  }

  # Only run during destroy, do nothing for apply.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "${self.triggers.asg_name}" --force-delete
  EOT
  }
}