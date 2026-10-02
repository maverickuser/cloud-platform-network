output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids_by_az" {
  value = { for zone, subnet in aws_subnet.public : zone => subnet.id }
}

output "private_subnet_ids_by_az" {
  value = { for zone, subnet in aws_subnet.private : zone => subnet.id }
}

output "private_route_table_ids_by_az" {
  value = { for zone, table in aws_route_table.private : zone => table.id }
}

output "nat_gateway_ids_by_az" {
  description = "Every zone maps to the single shared NAT gateway."
  value       = { for zone in var.availability_zones : zone => aws_nat_gateway.this.id }
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  value = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "sqs_endpoint_id" {
  value = try(aws_vpc_endpoint.interface["sqs"].id, null)
}

output "logs_endpoint_id" {
  value = try(aws_vpc_endpoint.interface["logs"].id, null)
}

output "lambda_security_group_ids" {
  value = { for name, group in aws_security_group.lambda : name => group.id }
}

output "fetch_lambda_security_group_id" {
  value = try(aws_security_group.lambda["fetch"].id, null)
}
