################################################################################
# Input variables for the main.tf file
################################################################################

variable "environment" {
  description = "Working application environment eg: dev, stg, prd"
  type        = string
  default     = ""
}

variable "application" {
  description = "Name of the application"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = ""
}

variable "region" {
  description = "Region be used for all the resources"
  type        = string
  default     = "us-east-1"
}

variable "silo" {
  description = "Region be used for all the resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project of terraform"
  type = string
  default = "dotnet"
}

variable "terraform" {
  description = "Terrform used or not"
  type = bool
  default = true
}
