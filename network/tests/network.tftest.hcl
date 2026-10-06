mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

override_resource {
  target = aws_nat_gateway.this
  values = { id = "nat-shared" }
}

override_resource {
  target = aws_vpc_endpoint.s3
  values = { prefix_list_id = "pl-s3" }
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
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0 && output.nat_gateway_ids_by_az == {}
    error_message = "By default there is no NAT gateway, Elastic IP, or private default route."
  }
  assert {
    condition     = aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "Only the public table reaches the internet gateway."
  }
  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && length(aws_vpc_endpoint.s3.route_table_ids) == 2 && jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Condition.StringEquals["aws:ResourceAccount"] == "123456789012"
    error_message = "The S3 gateway endpoint must attach to every private route table and allow only this account's buckets."
  }
  assert {
    condition     = keys(aws_vpc_endpoint.interface) == ["sqs"] && alltrue([for endpoint in aws_vpc_endpoint.interface : endpoint.private_dns_enabled && endpoint.vpc_endpoint_type == "Interface" && length(endpoint.subnet_ids) == 2])
    error_message = "Only SQS gets an interface endpoint by default, with private DNS in every private subnet."
  }
  assert {
    condition     = keys(aws_security_group.lambda) == ["processing"]
    error_message = "Only the processing service runs Lambdas in the VPC by default."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https.cidr_ipv4 == "10.20.0.0/16" && aws_vpc_security_group_ingress_rule.endpoints_https.from_port == 443
    error_message = "Endpoints accept HTTPS from the VPC only."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.lambda_https["processing"].cidr_ipv4 == "10.20.0.0/16" && aws_vpc_security_group_egress_rule.lambda_https["processing"].from_port == 443 && aws_vpc_security_group_egress_rule.lambda_https["processing"].to_port == 443
    error_message = "Without NAT, Lambda HTTPS egress must stay inside the VPC."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.lambda_s3["processing"].prefix_list_id == "pl-s3" && aws_vpc_security_group_egress_rule.lambda_s3["processing"].cidr_ipv4 == null && aws_vpc_security_group_egress_rule.lambda_s3["processing"].from_port == 443
    error_message = "Lambda groups reach S3 only through the gateway endpoint's prefix list."
  }
  assert {
    condition     = toset(keys(output.private_subnet_ids_by_az)) == toset(["ap-south-1a", "ap-south-1b"]) && toset(keys(output.private_route_table_ids_by_az)) == toset(["ap-south-1a", "ap-south-1b"]) && keys(output.lambda_security_group_ids) == ["processing"]
    error_message = "Outputs must be keyed by zone and by consumer name."
  }
  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.lambda_postgres) == ["processing"] && aws_vpc_security_group_egress_rule.lambda_postgres["processing"].cidr_ipv4 == "10.20.0.0/16" && aws_vpc_security_group_egress_rule.lambda_postgres["processing"].from_port == 5432 && aws_vpc_security_group_egress_rule.lambda_postgres["processing"].to_port == 5432
    error_message = "Only the processing group may reach PostgreSQL, and only inside the VPC."
  }
}

run "nat_gateway_enabled" {
  command = apply

  variables {
    nat_gateway = true
  }

  assert {
    condition     = length(aws_eip.nat) == 1 && aws_nat_gateway.this[0].subnet_id == aws_subnet.public["ap-south-1a"].id && output.nat_gateway_ids_by_az == { "ap-south-1a" = "nat-shared", "ap-south-1b" = "nat-shared" }
    error_message = "One NAT gateway in the first public subnet must serve every zone."
  }
  assert {
    condition     = length(aws_route.private_nat) == 2 && alltrue([for route in aws_route.private_nat : route.destination_cidr_block == "0.0.0.0/0" && route.nat_gateway_id == "nat-shared"])
    error_message = "With NAT, every private route table defaults to it."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.lambda_https["processing"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "With NAT, Lambda groups may open HTTPS to the internet."
  }
}

run "additional_consumers" {
  command = plan

  variables {
    interface_endpoint_services = ["sqs", "secretsmanager"]
    lambda_security_groups      = ["processing", "reporting"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 2 && length(aws_security_group.lambda) == 2 && length(aws_vpc_security_group_egress_rule.lambda_postgres) == 1
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

run "rejects_postgres_client_without_group" {
  command = plan

  variables {
    lambda_security_groups = ["reporting"]
  }

  expect_failures = [var.postgres_clients]
}
