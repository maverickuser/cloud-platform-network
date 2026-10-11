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
  description = "Every zone maps to the single shared NAT gateway; empty when nat_gateway is off."
  value       = { for zone in keys(local.nat_zones) : zone => aws_nat_gateway.this[0].id }
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  value = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "interface_endpoint_zones" {
  description = "Zones holding the interface endpoints' network interfaces."
  value       = local.endpoint_zones
}

output "sqs_endpoint_id" {
  value = try(aws_vpc_endpoint.interface["sqs"].id, null)
}

output "lambda_security_group_ids" {
  value = { for name, group in aws_security_group.lambda : name => group.id }
}
