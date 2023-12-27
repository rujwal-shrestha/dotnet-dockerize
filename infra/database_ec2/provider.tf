################################################################################
# Defines the resources to be created
################################################################################

provider "aws" {
  region = var.region
  # Default tags (Global tags) applies to all resources created by this provider
  # default_tags {
  #   tags = {
  #     owner       = var.owner
  #     environment = var.environment
  #     application = var.application
  #     silo        = var.silo  
  #     project     = var.project
  #     terraform   = var.terraform
  #   }
  # }
}