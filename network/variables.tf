variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "name" {
  type        = string
  default     = "cloud-platform"
  description = "Prefix for every network resource name."
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger; subnets are 4 bits longer, so up to four zones fit."
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
  description = "Zones that each receive one public and one private subnet."
  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Provide two to four distinct availability zones."
  }
}

variable "nat_gateway" {
  type        = bool
  default     = false
  description = "Create one NAT gateway so private subnets reach the internet. Off, private subnets reach only the VPC and its endpoints, and nothing here bills by the hour except the interface endpoints."
}

variable "interface_endpoint_services" {
  type        = set(string)
  default     = ["sqs"]
  description = "AWS service short names that get an interface endpoint with private DNS. Without NAT, every other AWS API a Lambda in the VPC calls (for example secretsmanager, sts, kms, logs) is unreachable until its name is added here."
}

variable "lambda_security_groups" {
  type        = set(string)
  default     = ["processing"]
  description = "Consumer names; each gets a Lambda security group with HTTPS egress and no ingress."
  validation {
    condition     = alltrue([for name in var.lambda_security_groups : can(regex("^[a-z][a-z0-9-]{0,30}$", name))])
    error_message = "Security group consumer names must be short lowercase identifiers."
  }
}

variable "postgres_clients" {
  type        = set(string)
  default     = ["processing"]
  description = "Consumers whose Lambda security group may also open PostgreSQL (5432) connections inside the VPC."
  validation {
    condition     = length(setsubtract(var.postgres_clients, var.lambda_security_groups)) == 0
    error_message = "Every PostgreSQL client must also be listed in lambda_security_groups."
  }
}
