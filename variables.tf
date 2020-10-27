#############################
## Application - Variables ##
#############################

# application name
variable "app_name" {
  type        = string
  description = "This variable defines the application name used to build resources"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

# description
variable "description" {
  type        = string
  description = "Provide a description of the resource"
}

# docker image
variable "docker_image" {
  type        = string
  description = "Provide the Docker image to deploy"
}

# environment
variable "environment" {
  type        = string
  description = "This variable defines the environment to be built"
}

# owner
variable "owner" {
  type        = string
  description = "Specify the owner of the resource"
}

# aws region shortname
variable "region" {
  type        = string
  description = "AWS region where the resource group will be created"
  default     = "us-west-2"
}

# service desired count
variable "service_desired" {
  type        = number
  description = "Desired numbers of containers in the ecs service"
  default     = "2"
}

locals {
  # Common tags to be assigned to all resources
  common_tags = {
    Owner       = var.owner
    Purpose     = var.description
    Environment = var.environment
  }
}
