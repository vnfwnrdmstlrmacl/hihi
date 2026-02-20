output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "Public 서브넷 ID 리스트"
  value       = aws_subnet.public[*].id
}

output "private_subnets" {
  description = "Private 서브넷 ID 리스트"
  value       = aws_subnet.private[*].id
}

output "vpc_cidr" {
  description = "VPC CIDR 대역"
  value       = aws_vpc.main.cidr_block
}
output "private_route_table_id" { value = aws_route_table.private.id }
