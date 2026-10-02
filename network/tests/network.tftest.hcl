mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

override_resource {
  target = aws_nat_gateway.this
  values = { id = "nat-shared" }
}

run "default_layout" {
  command = apply

  assert {
    condition     = aws_vpc.this.cidr_block == "10.20.0.0/16" && aws_vpc.this.enable_dns_hostnames && aws_vpc.this.enable_dns_support
    error_message = "The VPC must use the agreed CIDR with DNS enabled for private endpoint names."
  }
  assert {
    condition     = { for zone, subnet in aws_subnet.public : zone => subnet.cidr_block } == { "ap-south-1a" = "10.20.0.0/20", "ap-south-1b" = "10.20.16.0/20" } && { for zone, subnet in aws_subnet.private : zone => subnet.cidr_block } == { "ap-south-1a" = "10.20.128.0/20", "ap-south-1b" = "10.20.144.0/20" }
    error_message = "Each zone needs one public and one private /20 that do not overlap."
  }
  assert {
    condition     = alltrue([for subnet in merge(aws_subnet.public, aws_subnet.private) : !subnet.map_public_ip_on_launch])
    error_message = "No subnet may assign public addresses on launch."
  }
  assert {
    condition     = aws_nat_gateway.this.subnet_id == aws_subnet.public["ap-south-1a"].id && output.nat_gateway_ids_by_az == { "ap-south-1a" = "nat-shared", "ap-south-1b" = "nat-shared" }
    error_message = "One NAT gateway in the first public subnet must serve every zone."
  }
  assert {
    condition     = alltrue([for route in aws_route.private_nat : route.destination_cidr_block == "0.0.0.0/0" && route.nat_gateway_id == "nat-shared"]) && length(aws_route.private_nat) == 2 && aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "Private route tables default to NAT; only the public table reaches the internet gateway."
  }
  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && length(aws_vpc_endpoint.s3.route_table_ids) == 2 && jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Condition.StringEquals["aws:ResourceAccount"] == "123456789012"
    error_message = "The S3 gateway endpoint must attach to every private route table and allow only this account's buckets."
  }
  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["sqs", "logs"]) && alltrue([for endpoint in aws_vpc_endpoint.interface : endpoint.private_dns_enabled && endpoint.vpc_endpoint_type == "Interface" && length(endpoint.subnet_ids) == 2])
    error_message = "SQS and CloudWatch Logs need interface endpoints with private DNS in every private subnet."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https.cidr_ipv4 == "10.20.0.0/16" && aws_vpc_security_group_ingress_rule.endpoints_https.from_port == 443 && aws_vpc_security_group_egress_rule.lambda_https["fetch"].to_port == 443
    error_message = "Endpoints accept HTTPS from the VPC only; Lambda groups allow HTTPS egress only."
  }
  assert {
    condition     = toset(keys(output.private_subnet_ids_by_az)) == toset(["ap-south-1a", "ap-south-1b"]) && toset(keys(output.private_route_table_ids_by_az)) == toset(["ap-south-1a", "ap-south-1b"]) && toset(keys(output.lambda_security_group_ids)) == toset(["fetch"])
    error_message = "Outputs must be keyed by zone and by consumer name."
  }
}

run "additional_consumers" {
  command = plan

  variables {
    interface_endpoint_services = ["sqs", "logs", "secretsmanager"]
    lambda_security_groups      = ["fetch", "processing"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 3 && length(aws_security_group.lambda) == 2
    error_message = "Extra endpoints and consumer security groups must be added by variables alone."
  }
}

run "rejects_single_zone" {
  command = plan

  variables {
    availability_zones = ["ap-south-1a"]
  }

  expect_failures = [var.availability_zones]
}
