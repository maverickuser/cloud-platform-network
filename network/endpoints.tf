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
  description = "Lambda functions of the ${each.key} service: HTTPS egress only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-${each.key}-lambda" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  for_each          = var.lambda_security_groups
  security_group_id = aws_security_group.lambda[each.key].id
  description       = "HTTPS to VPC endpoints and, through NAT, the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
