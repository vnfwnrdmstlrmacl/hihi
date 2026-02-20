output "db_instance_address" {
  description = "RDS 엔드포인트 주소"
  value       = aws_db_instance.rds.address
}

output "db_instance_id" {
  value = aws_db_instance.rds.id
}
