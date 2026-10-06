# Consumers' buckets are not known here, so the gateway endpoint is limited to this account's buckets.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for table in aws_route_table.private : table.id]
  tags              = { Name = "${var.name}-s3" }
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountBucketsOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:ResourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-vpc-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.interface_endpoint_services
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${var.name}-${each.key}" }
}

resource "aws_security_group" "lambda" {
  for_each    = var.lambda_security_groups
  name        = "${var.name}-${each.key}-lambda"
  description = contains(var.postgres_clients, each.key) ? "Lambda functions of the ${each.key} service: HTTPS and in-VPC PostgreSQL egress" : "Lambda functions of the ${each.key} service: HTTPS egress only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-${each.key}-lambda" }
}

# Without NAT nothing outside the VPC is routable except S3 through its gateway endpoint,
# so HTTPS egress is limited to the VPC (interface endpoints) and the S3 prefix list.
resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  for_each          = var.lambda_security_groups
  security_group_id = aws_security_group.lambda[each.key].id
  description       = var.nat_gateway ? "HTTPS to VPC endpoints and, through NAT, the internet" : "HTTPS to interface endpoints inside the VPC"
  cidr_ipv4         = var.nat_gateway ? "0.0.0.0/0" : var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "lambda_s3" {
  for_each          = var.lambda_security_groups
  security_group_id = aws_security_group.lambda[each.key].id
  description       = "HTTPS to S3 through the gateway endpoint"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# The database lives in the consumer's own state; its security group admits this group.
resource "aws_vpc_security_group_egress_rule" "lambda_postgres" {
  for_each          = var.postgres_clients
  security_group_id = aws_security_group.lambda[each.key].id
  description       = "PostgreSQL to databases inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}
